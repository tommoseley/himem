import Foundation
import Combine
import AVFoundation

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
    /// Acks received for clipIds that weren't in the manifest at the
    /// moment of arrival. Replayed on the next successful
    /// `replace(with:)` so a row that gets loaded/added *after* its
    /// ack lands still gets cleared. Money 2026-06-18: defensive
    /// guard against the cold-launch race where iOS's WC queue
    /// could (in principle) deliver acks before
    /// `WatchPendingManifest.shared`'s lazy init runs. In the
    /// current code the stored-property init order makes this
    /// impossible, but the safety net is cheap insurance against
    /// future refactors moving the load.
    private var bufferedAckClipIds = Set<UUID>()

    /// is the user's own confirmation, no need to celebrate.
    func remove(clipId: UUID, viaSync: Bool = true) {
        guard clips.contains(where: { $0.clipId == clipId }) else {
            // Buffer for replay — see `bufferedAckClipIds`.
            bufferedAckClipIds.insert(clipId)
            NSLog("[HiMem][WC] watch — remove(clipId:) buffered ack for unknown clipId=\(clipId) (will replay on next manifest mutation)")
            return
        }
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
            NSLog("[HiMem][WC] watch — performRemoval no-op clipId=\(clipId) (not in manifest; remaining=\(clips.count))")
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
        NSLog("[HiMem][WC] watch — performRemoval done clipId=\(clipId) remaining=\(next.count) lastConfirmedReceiptAt=\(nowReceipt)")
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

    /// Clears every pending row whose `rollGroupId` matches the
    /// iPhone-acked roll group. Used for the split-clip ack path:
    /// the iPhone collapses N child clipId acks into one rollGroup
    /// ack so the watch can drop the master row (keyed on the
    /// rollGroupId) even if it never saw any child clipId. Closes
    /// § 8.7 of the system reference doc.
    ///
    /// Each match goes through `remove(clipId:viaSync:)` so the
    /// "Synced ✓" flash and `lastConfirmedReceiptAt` update fire
    /// the same way as a per-clip ack. No-op if no rows match.
    func removeByRollGroup(rollGroupId: UUID) {
        let matching = clips.filter { $0.rollGroupId == rollGroupId }
        guard !matching.isEmpty else {
            NSLog("[HiMem][WC] watch — removeByRollGroup no-op rollGroupId=\(rollGroupId) (no matches)")
            return
        }
        NSLog("[HiMem][WC] watch — removeByRollGroup matched \(matching.count) row(s) for rollGroupId=\(rollGroupId)")
        for clip in matching {
            remove(clipId: clip.clipId, viaSync: true)
        }
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
        // Replay any buffered acks against the new state so a clip
        // that got added/loaded after its ack arrived clears
        // immediately. Idempotent — replayBufferedAcksIfApplicable
        // is a no-op when the buffer is empty.
        replayBufferedAcksIfApplicable()
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
        defer {
            syncSharedCountAfterLoad()
            // Replay any acks that may have arrived during the load
            // window (defensive — current code has no such race, but
            // future refactors might). Idempotent: clipIds not in
            // the freshly-loaded `clips` stay buffered for a later
            // mutation.
            replayBufferedAcksIfApplicable()
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            // No manifest file. If there are orphan audio files
            // (fresh install with surviving Documents from prior
            // version, or post-crash state where manifest was lost
            // before first write), recover them.
            clips = Self.rescueOrphans()
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loaded = try decoder.decode([WatchPendingClip].self, from: data)
            clips = loaded
                .filter { FileManager.default.fileExists(atPath: Self.audioURL(for: $0.audioFilename).path) }
                .sorted { $0.capturedAt > $1.capturedAt }
        } catch {
            // Money 2026-06-18: decode failure (corruption, mid-
            // write crash, schema drift) previously silently zeroed
            // `clips`, orphaning every audio file on disk forever —
            // total silent data loss for the user's captures.
            // Instead: scan the audio directory and synthesize
            // best-effort manifest rows from the surviving `.caf`
            // files. Lost metadata: latitude/longitude (nil),
            // rollGroupId (split sessions degrade to standalone
            // clips on iPhone), nextTapOffsets ([] — no further
            // splitting). Recovered metadata: clipId (from
            // filename), capturedAt (file creation), duration
            // (AVAudioFile read).
            NSLog("[HiMem][WC] watch — manifest decode FAILED: \(error.localizedDescription) — scanning audio dir for orphan recovery")
            clips = Self.rescueOrphans()
        }
    }

    /// Scans `audioDirectory` for `.caf` files matching the watch's
    /// `clipId.uuidString.caf` filename convention. Builds best-
    /// effort `WatchPendingClip` rows for each so a corrupted
    /// manifest doesn't silently strand the user's captures.
    /// Returns rows sorted newest-first (matching the load-success
    /// ordering).
    static func rescueOrphans() -> [WatchPendingClip] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: audioDirectory,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return [] }
        var rescued: [WatchPendingClip] = []
        for entry in entries where entry.pathExtension.lowercased() == "caf" {
            let filename = entry.lastPathComponent
            let stem = (filename as NSString).deletingPathExtension
            guard let clipId = UUID(uuidString: stem) else { continue }
            let capturedAt = ((try? entry.resourceValues(forKeys: [.creationDateKey]))?.creationDate) ?? Date()
            let duration: TimeInterval = {
                guard let file = try? AVAudioFile(forReading: entry) else { return 0 }
                let rate = file.processingFormat.sampleRate
                return rate > 0 ? Double(file.length) / rate : 0
            }()
            rescued.append(WatchPendingClip(
                clipId: clipId,
                capturedAt: capturedAt,
                duration: duration,
                transcript: "",
                latitude: nil,
                longitude: nil,
                audioFilename: filename,
                rollGroupId: nil,
                nextTapOffsets: []
            ))
        }
        if !rescued.isEmpty {
            NSLog("[HiMem][WC] watch — rescued \(rescued.count) orphan clip(s) from audio directory")
        }
        return rescued.sorted { $0.capturedAt > $1.capturedAt }
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

    /// Drains `bufferedAckClipIds` against the current `clips`.
    /// Called from `load()` and (separately) from `replace(with:)`
    /// so any ack that arrived for a clipId not-yet-in-manifest
    /// gets applied as soon as the manifest catches up.
    private func replayBufferedAcksIfApplicable() {
        guard !bufferedAckClipIds.isEmpty else { return }
        let liveIds = Set(clips.map(\.clipId))
        let toReplay = bufferedAckClipIds.intersection(liveIds)
        guard !toReplay.isEmpty else { return }
        bufferedAckClipIds.subtract(toReplay)
        NSLog("[HiMem][WC] watch — replaying \(toReplay.count) buffered ack(s) at load")
        for clipId in toReplay {
            remove(clipId: clipId, viaSync: false)
        }
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
