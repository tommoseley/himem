import Foundation
import Combine

/// One row in the watch's pending manifest. The watch holds onto these
/// until the iPhone confirms receipt of the corresponding clip, then
/// removes the row.
struct WatchPendingClip: Codable, Identifiable, Equatable {
    let clipId: UUID
    let capturedAt: Date
    let duration: TimeInterval
    let transcript: String
    let latitude: Double?
    let longitude: Double?
    let audioFilename: String
    /// On-a-roll session id. Stamped on every clip in the same
    /// Record→Stop session. Phone-side inbox grouper uses this as a
    /// deterministic override over time+location.
    let rollGroupId: UUID?
    /// Next-tap offsets (seconds from session start) for the
    /// continuous master audio file. Empty for single-clip sessions.
    /// iPhone splits the master into per-clip files on receive
    /// (see `VoiceClipSplitter`); the watch ships one file plus this
    /// list rather than rotating recorders per tap.
    let nextTapOffsets: [TimeInterval]

    var id: UUID { clipId }

    init(
        clipId: UUID,
        capturedAt: Date,
        duration: TimeInterval,
        transcript: String,
        latitude: Double?,
        longitude: Double?,
        audioFilename: String,
        rollGroupId: UUID? = nil,
        nextTapOffsets: [TimeInterval] = []
    ) {
        self.clipId = clipId
        self.capturedAt = capturedAt
        self.duration = duration
        self.transcript = transcript
        self.latitude = latitude
        self.longitude = longitude
        self.audioFilename = audioFilename
        self.rollGroupId = rollGroupId
        self.nextTapOffsets = nextTapOffsets
    }

    var metadata: ClipMetadata {
        ClipMetadata(
            clipId: clipId,
            capturedAt: capturedAt,
            duration: duration,
            transcript: transcript,
            latitude: latitude,
            longitude: longitude,
            source: "watch",
            rollGroupId: rollGroupId,
            nextTapOffsets: nextTapOffsets
        )
    }
}

/// File-backed pending manifest on the watch. Lives at
/// `Documents/Pending/manifest.json`; audio files at
/// `Documents/Pending/audio/<clipId>.caf`. This is the watch's source of
/// truth for "what hasn't been delivered to the iPhone yet" — the section
/// 4 list in the design.
@MainActor
final class WatchPendingManifest: ObservableObject {
    static let shared = WatchPendingManifest()

    /// Newest-first; drives the pending list UI.
    @Published private(set) var clips: [WatchPendingClip] = []

    /// Clips currently in the "Synced ✓ → slide out" pre-removal flash.
    /// Populated by `remove(clipId:viaSync:)` when `viaSync == true`; the
    /// list view checks this set to render the green confirmation badge
    /// on each row for a beat before the row removal animation fires.
    @Published private(set) var syncingClipIds: Set<UUID> = []

    /// How long the "Synced ✓" badge stays on the row before the clip is
    /// pulled from the manifest. Matched to the design spec's "brief 1s
    /// pulse before slide-out".
    private static let syncFlashDuration: TimeInterval = 1.0

    static var pendingRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Pending", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var audioDirectory: URL {
        let dir = pendingRoot.appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var manifestURL: URL { pendingRoot.appendingPathComponent("manifest.json") }
    static func audioURL(for filename: String) -> URL { audioDirectory.appendingPathComponent(filename) }

    /// Hard cap from the spec — start warning the user at this many
    /// unsynced clips.
    static let storageCap = 50
    /// Soft warning threshold — amber chip surfaces at this count and
    /// above (spec: "Warning at 45, hard block at 50").
    static let storageWarnCount = 45
    /// Sync-stuck threshold (spec Edge C): after 24h without an
    /// iPhone-confirmed receipt, surface the red sync-issue indicator.
    static let syncStuckSeconds: TimeInterval = 24 * 3600

    /// Last time the iPhone confirmed receipt of any clip from this
    /// watch. Updated in `performRemoval` (which only runs on the ack
    /// path or explicit user delete — both indicate the system is
    /// alive). Persisted alongside the manifest so the stuck indicator
    /// survives launches.
    @Published private(set) var lastConfirmedReceiptAt: Date?

    private init() {
        load()
    }

    var count: Int { clips.count }
    var isEmpty: Bool { clips.isEmpty }
    var isAtCap: Bool { clips.count >= Self.storageCap }
    /// True when the pending count is at or above the soft warning
    /// threshold (45) but below the hard cap (50). UI surfaces an amber
    /// "almost full" chip in this range.
    var isNearCap: Bool { clips.count >= Self.storageWarnCount && clips.count < Self.storageCap }
    /// True when at least one clip is in the manifest *and* the iPhone
    /// hasn't confirmed any receipt for > 24h. If `lastConfirmedReceiptAt`
    /// is nil (fresh install / no prior sync), use the oldest clip's
    /// capture time as the baseline.
    var isSyncStuck: Bool {
        guard !clips.isEmpty else { return false }
        let baseline = lastConfirmedReceiptAt ?? clips.map(\.capturedAt).min() ?? Date()
        return Date().timeIntervalSince(baseline) > Self.syncStuckSeconds
    }

    /// Adds a freshly-recorded clip to the pending manifest.
    func append(_ clip: WatchPendingClip) {
        guard !clips.contains(where: { $0.clipId == clip.clipId }) else { return }
        var next = clips
        next.append(clip)
        next.sort { $0.capturedAt > $1.capturedAt }
        replace(with: next)
    }

    /// Called by the coordinator when the iPhone confirms receipt of a
    /// clip. Removes both the manifest row and the audio file.
    ///
    /// When `viaSync` is true (iPhone ack path), the row stays in the
    /// manifest for `syncFlashDuration` with its id in `syncingClipIds`
    /// so the list can flash a "Synced ✓" badge before the removal
    /// animation fires. User-initiated deletes skip the badge — the swipe
    /// is the user's own confirmation, no need to celebrate.
    func remove(clipId: UUID, viaSync: Bool = true) {
        guard clips.contains(where: { $0.clipId == clipId }) else { return }
        if viaSync {
            syncingClipIds.insert(clipId)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.syncFlashDuration * 1_000_000_000))
                self?.performRemoval(clipId: clipId)
            }
        } else {
            performRemoval(clipId: clipId)
        }
    }

    private func performRemoval(clipId: UUID) {
        syncingClipIds.remove(clipId)
        guard let clip = clips.first(where: { $0.clipId == clipId }) else {
            // Sink fired but the row was already gone — duplicate
            // ack, prior sweep already cleared it, or the watch
            // received an ack for a clip it never had. Log so the
            // "coordinator removing clipId=X" trace in the
            // coordinator doesn't dangle with no follow-up.
            NSLog("[Himem][WC] watch — performRemoval no-op clipId=\(clipId) (not in manifest; remaining=\(clips.count))")
            return
        }
        try? FileManager.default.removeItem(at: Self.audioURL(for: clip.audioFilename))
        let next = clips.filter { $0.clipId != clipId }
        replace(with: next)
        // Successful confirmed-receipt — record so the sync-stuck timer
        // resets. Survives across launches via the manifest persistence.
        let nowReceipt = Date()
        lastConfirmedReceiptAt = nowReceipt
        persistLastConfirmedReceipt()
        NSLog("[Himem][WC] watch — performRemoval done clipId=\(clipId) remaining=\(next.count) lastConfirmedReceiptAt=\(nowReceipt)")
    }

    /// Persistence for `lastConfirmedReceiptAt` — small enough to stash
    /// in UserDefaults rather than inflate the manifest JSON.
    private static let lastReceiptKey = "watchPending.lastConfirmedReceiptAt"

    private func persistLastConfirmedReceipt() {
        UserDefaults.standard.set(lastConfirmedReceiptAt, forKey: Self.lastReceiptKey)
    }

    private func loadLastConfirmedReceipt() {
        lastConfirmedReceiptAt = UserDefaults.standard.object(forKey: Self.lastReceiptKey) as? Date
    }

    /// User-initiated delete from the pending list. Same effect as a
    /// confirmation-driven removal but without iPhone involvement —
    /// nothing was sent, so no "Synced ✓" badge either.
    func userDelete(clipId: UUID) {
        remove(clipId: clipId, viaSync: false)
    }

    #if DEBUG
    /// Test-only seam for replacing the manifest's `clips` without
    /// going through persistence. Used by ack-pipeline tests to
    /// drive deterministic scenarios. Skips `persist` because
    /// hitting UserDefaults from test runs leaks state.
    func debugReplaceClipsForTesting(_ next: [WatchPendingClip]) {
        clips = next
        syncingClipIds = []
    }

    /// Test-only seam for pinning `lastConfirmedReceiptAt` to a
    /// known value (e.g., 48 h ago to set up an `isSyncStuck`
    /// precondition).
    func debugSetLastConfirmedReceiptForTesting(_ date: Date?) {
        lastConfirmedReceiptAt = date
    }
    #endif

    func audioURL(for clipId: UUID) -> URL? {
        guard let clip = clips.first(where: { $0.clipId == clipId }) else { return nil }
        let url = Self.audioURL(for: clip.audioFilename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Persistence

    private func replace(with next: [WatchPendingClip]) {
        clips = next
        persist()
        // Surface the count to the App Group so the complication widget
        // can read it from its separate process. Refresh widget timelines
        // so the badge updates without waiting for the next periodic poll.
        WatchSharedState.pendingCount = next.count
        Task { await WidgetTimelineRefresher.refresh() }
    }

    private func persist() {
        let url = Self.manifestURL
        let tmp = url.appendingPathExtension("tmp")
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .sortedKeys
            let data = try encoder.encode(clips)
            try data.write(to: tmp, options: .atomic)
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            // Persistence failure isn't fatal — in-memory state stays
            // correct, retry on next mutation.
        }
    }

    private func load() {
        loadLastConfirmedReceipt()
        let url = Self.manifestURL
        defer { syncSharedCountAfterLoad() }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loaded = try decoder.decode([WatchPendingClip].self, from: data)
            clips = loaded
                .filter { FileManager.default.fileExists(atPath: Self.audioURL(for: $0.audioFilename).path) }
                .sorted { $0.capturedAt > $1.capturedAt }
        } catch {
            clips = []
        }
    }

    /// Force-syncs the App Group's `pendingCount` to match `clips.count`
    /// and kicks the complication's timeline. Required after `load()`
    /// because both the audio-missing filter on load AND the
    /// decode-failure fallback (`clips = []`) bypass `replace(with:)`,
    /// the normal mutation funnel. Without this, the complication can
    /// read a stale count from a prior session — symptom: watch app
    /// says "all caught up" while the complication still shows
    /// "1 pending." Money-tested in
    /// `WatchPendingManifestLoadSyncTests`.
    private func syncSharedCountAfterLoad() {
        WatchSharedState.pendingCount = clips.count
        Task { await WidgetTimelineRefresher.refresh() }
    }

    #if DEBUG
    /// Test seam — re-runs the load logic so each money test can
    /// observe `clips` and `WatchSharedState.pendingCount` against a
    /// freshly-prepared manifest on disk. The shared singleton init
    /// runs once per process; without this seam, tests would all see
    /// whatever the first init landed on.
    func forceReloadForTesting() {
        load()
    }
    #endif
}
