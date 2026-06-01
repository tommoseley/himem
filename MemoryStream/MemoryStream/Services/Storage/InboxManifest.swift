import Foundation
import Combine
import UserNotifications

/// One row in the inbox manifest — represents an unorganized clip that
/// arrived from the watch. Lives at `Documents/Inbox/manifest.json`. Audio
/// payload lives next to it at `Documents/Inbox/audio/<clipId>.caf`.
///
/// Once the user promotes a clip into a memory (Create memory / Add to
/// memory), the audio file moves to the iOS-side voice store and the row
/// is removed from this manifest.
struct InboxClip: Codable, Identifiable, Equatable {
    /// Lifecycle of a single clip in the inbox. Single source of
    /// truth replacing the three-store split (`InboxManifest` +
    /// `InboxProcessedClipIds` + `InboxArrivalTracker`). See
    /// `docs/architecture/Captured Clips · watch-to-phone sync
    /// system.md` for the rebuild rationale.
    ///
    /// Transitions:
    ///   `.announced` → `.received` → `.transcribing` → `.transcribed`
    ///                                                       ↓
    ///                                                  `.disposed`
    /// A `.disposed` row stays in the manifest as a tombstone so
    /// `acceptArrivedClip` can recognize and drop iOS WC-queue ghost
    /// re-deliveries by reading status — no separate dedup set
    /// needed. Tombstones age out via `InboxManifest.pruned`.
    enum Status: String, Codable {
        /// Pre-announce received, file not yet on disk.
        case announced
        /// File copied into the inbox audio dir, transcription not started.
        case received
        /// Compressed + transcription in flight.
        case transcribing
        /// Transcription attempt completed (transcript may be empty
        /// if the recognizer found no speech).
        case transcribed
        /// User removed or promoted to a memory. Retained as
        /// tombstone to gate redeliveries until pruned.
        case disposed
    }

    let clipId: UUID
    let capturedAt: Date
    let duration: TimeInterval
    let transcript: String
    let latitude: Double?
    let longitude: Double?
    let source: String
    let audioFilename: String
    /// True after the iPhone-side speech recognizer has run for this clip,
    /// even if it returned no text. Combined with `transcript.isEmpty` this
    /// distinguishes "still in flight" from "ran, found no speech" — UI
    /// shows different copy and styling for each. Retained alongside
    /// `status == .transcribed` so existing UI checks don't break in
    /// Step C; later steps simplify these into one read.
    let transcriptionAttempted: Bool
    /// On-a-roll grouping signal — clips with the same non-nil
    /// `rollGroupId` always land in one Memory regardless of
    /// time/location heuristics. Optional so older manifest rows that
    /// predate the feature decode cleanly.
    let rollGroupId: UUID?
    /// Lifecycle state. Decoded with legacy-shape migration in
    /// `init(from:)` — entries written before this field existed
    /// infer `.transcribed` if a transcript was already attempted,
    /// otherwise `.received`.
    let status: Status
    /// When this row transitioned to `.disposed`. Drives the
    /// tombstone-aging prune in `InboxManifest.pruned`.
    let disposedAt: Date?
    /// When the watch's pre-announce `sendMessage` was received on
    /// the phone, if applicable. Currently still maintained
    /// transiently by `InboxArrivalTracker`; the field is positioned
    /// on `InboxClip` so a future post-launch demotion of the
    /// tracker (Step 12 full-form, queued) can move `.announced`
    /// rows into the manifest without a second codable migration.
    /// `nil` on every existing row + any row whose status is past
    /// `.announced` and pre-announce timing wasn't preserved.
    let announcedAt: Date?
    /// File size in bytes carried on the pre-announce. Same
    /// queued-demotion rationale as `announcedAt`. Optional because
    /// older pre-announce wire payloads (and every non-announced
    /// row) don't carry it.
    let fileSizeBytes: Int64?

    var id: UUID { clipId }

    init(
        clipId: UUID,
        capturedAt: Date,
        duration: TimeInterval,
        transcript: String,
        latitude: Double?,
        longitude: Double?,
        source: String,
        audioFilename: String,
        transcriptionAttempted: Bool = false,
        rollGroupId: UUID? = nil,
        status: Status = .received,
        disposedAt: Date? = nil,
        announcedAt: Date? = nil,
        fileSizeBytes: Int64? = nil
    ) {
        self.clipId = clipId
        self.capturedAt = capturedAt
        self.duration = duration
        self.transcript = transcript
        self.latitude = latitude
        self.longitude = longitude
        self.source = source
        self.audioFilename = audioFilename
        self.transcriptionAttempted = transcriptionAttempted
        self.rollGroupId = rollGroupId
        self.status = status
        self.disposedAt = disposedAt
        self.announcedAt = announcedAt
        self.fileSizeBytes = fileSizeBytes
    }

    // Custom decoding so legacy manifests (no `status`/`disposedAt`/
    // `announcedAt`/`fileSizeBytes`, and older still without
    // `transcriptionAttempted`) round-trip.
    // Inference rule for missing `status`:
    //   - transcript present OR `transcriptionAttempted == true`
    //     → `.transcribed` (recognizer ran, result may be empty)
    //   - else → `.received` (audio on disk, recognizer hasn't run)
    // `announcedAt` / `fileSizeBytes` decode as nil on legacy entries.
    private enum CodingKeys: String, CodingKey {
        case clipId, capturedAt, duration, transcript, latitude, longitude
        case source, audioFilename, transcriptionAttempted, rollGroupId
        case status, disposedAt
        case announcedAt, fileSizeBytes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clipId = try c.decode(UUID.self, forKey: .clipId)
        capturedAt = try c.decode(Date.self, forKey: .capturedAt)
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        transcript = try c.decode(String.self, forKey: .transcript)
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        source = try c.decode(String.self, forKey: .source)
        audioFilename = try c.decode(String.self, forKey: .audioFilename)
        transcriptionAttempted = try c.decodeIfPresent(Bool.self, forKey: .transcriptionAttempted) ?? false
        rollGroupId = try c.decodeIfPresent(UUID.self, forKey: .rollGroupId)
        if let s = try c.decodeIfPresent(Status.self, forKey: .status) {
            status = s
        } else if transcriptionAttempted || !transcript.isEmpty {
            status = .transcribed
        } else {
            status = .received
        }
        disposedAt = try c.decodeIfPresent(Date.self, forKey: .disposedAt)
        announcedAt = try c.decodeIfPresent(Date.self, forKey: .announcedAt)
        fileSizeBytes = try c.decodeIfPresent(Int64.self, forKey: .fileSizeBytes)
    }
}

/// File-backed, atomic inbox-manifest store.
///
/// This is a **transient working area**. Clips arrive from the watch via
/// WatchConnectivity, sit here until the user organizes them on the phone,
/// then get promoted into JournalEntry rows (and out of this manifest).
/// Deliberately not Core Data / not CloudKit — the inbox is per-iPhone
/// state; once promoted, memories live in the normal store and sync.
///
/// Thread safety: all writes go through the @MainActor `apply` API, which
/// snapshot-then-replaces. Concurrent reads from the UI are safe via the
/// @Published `clips` array.
@MainActor
final class InboxManifest: ObservableObject {
    static let shared = InboxManifest()

    /// Active inbox rows (status != `.disposed`). Sorted newest-first.
    /// Published so UI, badge, and watch-ack reconcile paths refresh
    /// automatically. Tombstones live in `disposedClips`; both arrays
    /// persist to the same JSON file.
    @Published private(set) var clips: [InboxClip] = []

    /// Tombstones — rows with `status == .disposed`. NOT published;
    /// no UI surfaces this list, but the B5 dedup gate reads it via
    /// `status(for:)` to drop ghost re-deliveries iOS's WC queue
    /// resurfaces after the user already disposed of a clip. Aged
    /// out on load via `pruned(_:olderThan:now:)`.
    private var disposedClips: [InboxClip] = []

    /// Folders. Created lazily on first access. Marked `nonisolated` so the
    /// WatchSessionDelegate can resolve paths off the main actor — the
    /// delegate's `didReceive` callback runs on a background queue, and we
    /// need to copy the audio file synchronously before the system reaps
    /// the source URL.
    ///
    /// IMPORTANT: NOT under `Documents/Inbox/` — that path is system-managed
    /// by WatchConnectivity (it stages incoming files at
    /// `Documents/Inbox/com.apple.watchconnectivity/...`). Touching that
    /// directory tree from the app interferes with framework-managed staging
    /// and the delivered files vanish before we can copy them.
    nonisolated static var inboxRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("ClipInbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    nonisolated static var audioDirectory: URL {
        let dir = inboxRoot.appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    nonisolated static var manifestURL: URL { inboxRoot.appendingPathComponent("manifest.json") }
    nonisolated static func audioURL(for filename: String) -> URL { audioDirectory.appendingPathComponent(filename) }

    /// Pure: drops `.disposed` rows whose `disposedAt` is strictly
    /// older than `(days * 86400)` seconds before `now`. Tombstones
    /// without a `disposedAt` are kept (we can't prove they're old).
    /// Active statuses (`.announced` / `.received` / `.transcribing`
    /// / `.transcribed`) are never pruned.
    ///
    /// Tested by `InboxManifestPruneTests`.
    nonisolated static func pruned(_ clips: [InboxClip], olderThan days: Int, now: Date) -> [InboxClip] {
        let threshold = TimeInterval(days * 86_400)
        return clips.filter { clip in
            guard clip.status == .disposed, let disposedAt = clip.disposedAt else {
                return true
            }
            return now.timeIntervalSince(disposedAt) <= threshold
        }
    }

    /// Default tombstone retention. 90 days is comfortably longer
    /// than iOS's transferUserInfo / transferFile retry windows, so
    /// any ghost re-delivery we'd want to gate against is still
    /// caught by the tombstone.
    static let defaultPruneDays: Int = 90

    /// Location of the legacy `InboxProcessedClipIds.json` file (one
    /// JSON array of UUIDs). Computed so tests can swap the dir.
    nonisolated static var legacyProcessedClipIdsURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return docs.appendingPathComponent("InboxProcessedClipIds.json")
    }

    /// One-shot migration of the legacy `InboxProcessedClipIds.json`
    /// into `.disposed` tombstones. Returns the rows to insert into
    /// `disposedClips`; the legacy file is deleted on the way out so
    /// subsequent loads skip the work. Best-effort: absent or corrupt
    /// files yield an empty result and don't throw.
    ///
    /// `now` is the timestamp stamped on every migrated tombstone
    /// (we don't know when the user actually disposed, so we use one
    /// migration moment — close enough for the 90-day prune window).
    nonisolated static func migrateLegacyDisposedSet(legacyURL: URL, now: Date) -> [InboxClip] {
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return [] }
        defer { try? FileManager.default.removeItem(at: legacyURL) }
        guard let data = try? Data(contentsOf: legacyURL),
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else {
            return []
        }
        return ids.map { id in
            InboxClip(
                clipId: id,
                capturedAt: now,
                duration: 0,
                transcript: "",
                latitude: nil,
                longitude: nil,
                source: "watch",
                audioFilename: "",
                transcriptionAttempted: false,
                rollGroupId: nil,
                status: .disposed,
                disposedAt: now
            )
        }
    }

    private init() {
        load()
    }

    // MARK: - Public API

    var count: Int { clips.count }
    var isEmpty: Bool { clips.isEmpty }

    /// Atomic insert of a clip received from the watch. Audio file must
    /// already be in `audioDirectory` (the WatchSessionDelegate writes the
    /// file first, then calls this). Idempotent on duplicate clipIds.
    func acceptClip(_ clip: InboxClip) {
        if clips.contains(where: { $0.clipId == clip.clipId }) { return }
        var next = clips
        next.append(clip)
        next.sort { $0.capturedAt > $1.capturedAt }
        replace(with: next)
    }

    /// Records the outcome of an iPhone-side transcription attempt. Called
    /// once the speech recognizer task completes — `transcript` may be the
    /// recognized text, or empty if the recognizer reported no speech /
    /// failed. Either way this marks the clip as "attempted" so the UI can
    /// distinguish in-flight pending state from a confirmed no-speech
    /// result.
    func recordTranscriptionAttempt(clipId: UUID, transcript: String) {
        guard let idx = clips.firstIndex(where: { $0.clipId == clipId }) else { return }
        let existing = clips[idx]
        // CRITICAL: carry `rollGroupId` forward. Before 2026-05-27 this
        // init call omitted `rollGroupId:`, defaulting it to nil, which
        // silently wiped the on-a-roll session signal as soon as the
        // phone's transcriber finished — and since every watch clip goes
        // through transcription, every clip ended up nil-rolled.
        // Downstream the grouper fell back to time+location and merged
        // unrelated recordings into one session card. Carry every field
        // forward verbatim except `transcript` and `transcriptionAttempted`.
        //
        // Also strip ASR leading-noise punctuation from the transcript
        // — same cleaner used in `StorageService.createVoiceFragment`
        // — so the Captured Clips card doesn't render ",.," prefixes.
        let updated = InboxClip(
            clipId: existing.clipId,
            capturedAt: existing.capturedAt,
            duration: existing.duration,
            transcript: JournalEntry.cleanedTranscript(transcript),
            latitude: existing.latitude,
            longitude: existing.longitude,
            source: existing.source,
            audioFilename: existing.audioFilename,
            transcriptionAttempted: true,
            rollGroupId: existing.rollGroupId,
            status: .transcribed,
            disposedAt: existing.disposedAt
        )
        var next = clips
        next[idx] = updated
        replace(with: next)
    }

    /// What ack the iPhone needs to send to the watch for a disposed
    /// clipId. Roll-session clips collapse into a single rollGroup ack
    /// — one message clears the watch's pending row (keyed on the
    /// master clipId, which the watch stored as the rollGroupId) even
    /// when only some children were removed. Single clips (nil
    /// rollGroupId) emit a clipId ack as before.
    ///
    /// Closes the split-clip re-ack gap (§ 8.7 of the system reference
    /// doc): for split sessions the children carry fresh clipIds the
    /// watch never knew, so per-clipId acks couldn't match the watch
    /// row. Now one rollGroup ack covers master + every child.
    enum AckAction: Hashable {
        case clip(UUID)
        case rollGroup(UUID)
    }

    /// Pure decision: turn a batch of about-to-be-removed clipIds into
    /// the minimum set of ack messages. Reads `manifestClips` to find
    /// each clipId's `rollGroupId`; missing entries fall back to a
    /// clip ack (the watch's no-op-on-unknown handler absorbs stale
    /// requests).
    ///
    /// Order isn't part of the contract — callers should not depend
    /// on it. Caller is responsible for actually emitting the acks.
    ///
    /// `nonisolated` because the function is pure over value types
    /// (`InboxClip` is `Codable`/`Equatable`, no actor state). Lets
    /// unit tests drive it without hopping to MainActor.
    nonisolated static func ackActions(for clipIds: [UUID], in manifestClips: [InboxClip]) -> [AckAction] {
        var rollGroupIds = Set<UUID>()
        var clipAcks: [UUID] = []
        for clipId in clipIds {
            let clip = manifestClips.first { $0.clipId == clipId }
            if let rg = clip?.rollGroupId {
                rollGroupIds.insert(rg)
            } else {
                clipAcks.append(clipId)
            }
        }
        return rollGroupIds.map { AckAction.rollGroup($0) }
            + clipAcks.map { AckAction.clip($0) }
    }

    /// Removes a single clip and its audio file. Called when the user
    /// deletes from the inbox or after a clip is promoted into a memory.
    /// The row stays in `disposedClips` as a tombstone so the B5 gate
    /// (`status(for:) == .disposed`) catches ghost re-deliveries iOS's
    /// WC queue resurfaces hours/days later.
    func remove(clipId: UUID) {
        guard let clip = clips.first(where: { $0.clipId == clipId }) else { return }
        try? FileManager.default.removeItem(at: Self.audioURL(for: clip.audioFilename))
        // Snapshot the ack decision BEFORE the array is mutated — the
        // clip's rollGroupId is what we need to send.
        let actions = Self.ackActions(for: [clipId], in: clips)
        let next = clips.filter { $0.clipId != clipId }
        disposedClips.append(tombstone(from: clip))
        replace(with: next)
        WatchInboxNotificationCoordinator.shared.clipRemoved(clipId: clipId)
        emitAcks(actions)
        NSLog("[Himem][Inbox] remove(clipId:) emitted \(actions.count) ack(s) for clipId=\(clipId), tombstones=\(disposedClips.count)")
    }

    /// Removes a batch — used when the user creates a memory from N clips
    /// or appends N clips to an existing memory. The audio files have
    /// already been moved out by the caller; we just drop the rows here.
    /// Each row becomes a `.disposed` tombstone for the same reason as
    /// `remove(clipId:)`.
    func removeBatch(clipIds: [UUID]) {
        // Same snapshot-before-mutate pattern as `remove`: capture
        // ack actions while the clips still have their rollGroupId
        // readable in `clips`.
        let actions = Self.ackActions(for: clipIds, in: clips)
        let idSet = Set(clipIds)
        let removed = clips.filter { idSet.contains($0.clipId) }
        let next = clips.filter { !idSet.contains($0.clipId) }
        disposedClips.append(contentsOf: removed.map { tombstone(from: $0) })
        replace(with: next)
        for id in clipIds {
            WatchInboxNotificationCoordinator.shared.clipRemoved(clipId: id)
        }
        emitAcks(actions)
        NSLog("[Himem][Inbox] removeBatch emitted \(actions.count) ack(s) for \(clipIds.count) clipId(s), tombstones=\(disposedClips.count)")
    }

    /// Status of a clipId across both active and disposed rows. nil
    /// when the manifest has no entry — the rebuild's single-source
    /// query that replaces `InboxProcessedClipIds.contains(_:)` and
    /// the multi-array idempotency checks in `acceptArrivedClip`.
    func status(for clipId: UUID) -> InboxClip.Status? {
        if let c = clips.first(where: { $0.clipId == clipId }) { return c.status }
        if let t = disposedClips.first(where: { $0.clipId == clipId }) { return t.status }
        return nil
    }

    /// True if any clip (active or tombstone) is tagged with this
    /// `rollGroupId`. Drives the efficiency leg of
    /// `WatchSessionDelegate.shouldDropArrivedMaster`: a master with
    /// a rollGroupId the manifest already split is a redundant
    /// delivery — re-splitting would produce the same children
    /// (deterministic UUIDs, Step A), but skip the work.
    func isRollGroupKnown(_ rollGroupId: UUID) -> Bool {
        clips.contains { $0.rollGroupId == rollGroupId }
            || disposedClips.contains { $0.rollGroupId == rollGroupId }
    }

    /// Turn an active row into a tombstone — drops audio reference
    /// (file is already gone), stamps `disposedAt`, status to
    /// `.disposed`. All other fields preserved for forensic / future
    /// re-ack scenarios.
    private func tombstone(from clip: InboxClip) -> InboxClip {
        InboxClip(
            clipId: clip.clipId,
            capturedAt: clip.capturedAt,
            duration: clip.duration,
            transcript: clip.transcript,
            latitude: clip.latitude,
            longitude: clip.longitude,
            source: clip.source,
            audioFilename: "",
            transcriptionAttempted: clip.transcriptionAttempted,
            rollGroupId: clip.rollGroupId,
            status: .disposed,
            disposedAt: Date()
        )
    }

    private func emitAcks(_ actions: [AckAction]) {
        for action in actions {
            switch action {
            case .clip(let id):
                WatchSessionDelegate.shared.sendConfirmation(clipId: id)
            case .rollGroup(let id):
                WatchSessionDelegate.shared.sendConfirmation(rollGroupId: id)
            }
        }
    }

    /// Finds the on-disk audio URL for a clip. Returns nil if the file is
    /// missing (e.g. partial transfer, manual cleanup).
    func audioURL(for clipId: UUID) -> URL? {
        guard let clip = clips.first(where: { $0.clipId == clipId }) else { return nil }
        let url = Self.audioURL(for: clip.audioFilename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Atomic persistence

    private func replace(with next: [InboxClip]) {
        clips = next
        persist()
        // Keep the iOS home-screen badge in lockstep with the inbox.
        // Push payloads from `WatchInboxNotificationCoordinator` set
        // the badge to whatever the count was when the push fired,
        // but the system doesn't lower the badge when the user
        // reviews clips in-app — we have to do that ourselves.
        // Money-tested in `InboxManifestBadgeSyncTests`.
        syncIconBadge(to: next.count)
    }

    /// Sets the home-screen icon badge to `count` via the modern
    /// `UNUserNotificationCenter.setBadgeCount` API (iOS 17+, replaces
    /// the deprecated `UIApplication.applicationIconBadgeNumber`).
    /// Errors are swallowed — a transient permission/HAL hiccup
    /// shouldn't cascade into a manifest-persist failure.
    private func syncIconBadge(to count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
    }

    private func persist() {
        let url = Self.manifestURL
        let tmp = url.appendingPathExtension("tmp")
        do {
            // Single JSON file holds both active and disposed rows;
            // partitioned by `status` on load. Active first so a
            // human reading the file sees the live inbox at the top.
            let combined = clips + disposedClips
            let data = try JSONEncoder.iso8601.encode(combined)
            try data.write(to: tmp, options: .atomic)
            // Atomic rename — if we crash between the write and the rename
            // the manifest stays at the previous version, never half-written.
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            // Failing to persist isn't fatal — the in-memory state is still
            // correct, we'll retry on the next mutation. Log and move on.
            ErrorState.shared.report(.saveFailed("Inbox manifest persist failed: \(error.localizedDescription)"))
        }
    }

    private func load() {
        // Fast path: read + partition `manifest.json` only. No
        // backup write, no legacy `InboxProcessedClipIds.json`
        // migration — those are deferred to
        // `runStartupMigrationsIfNeeded()` which `LaunchScreenView`
        // calls after CloudKit's initial import has settled.
        //
        // The reason: the singleton is lazily initialized on first
        // access, which on Tom's dev device with a WC backlog
        // happens inside `WatchSessionDelegate.session(_:didReceive:)`
        // via a `main.sync` from the background WC delegate thread.
        // That fires DURING the `NSPersistentCloudKitContainer`
        // initial-import window, where Core Data is fragile —
        // running heavy main-thread I/O here trips the
        // two-NSManagedObjectModel race documented in
        // LaunchScreenView.swift:230 and crashes the app.
        //
        // 2026-05-30: confirmed by Tom's device run — first launch
        // with the rebuild crashed during CloudKit setup; second
        // launch (migration already inert) was clean; fresh install
        // (no legacy file → no migration) was clean.
        let url = Self.manifestURL
        defer { syncIconBadge(to: clips.count) }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let loaded = try JSONDecoder.iso8601.decode([InboxClip].self, from: data)
            let (active, disposed) = partition(loaded)
            // Drop active rows whose audio file is gone — defensive
            // against partial states from older crashes. Tombstones
            // never had audio (we cleared `audioFilename` on disposal),
            // so the file check doesn't apply.
            let activeWithFiles = active.filter { clip in
                FileManager.default.fileExists(atPath: Self.audioURL(for: clip.audioFilename).path)
            }
            // Age out old tombstones. Active rows pass through.
            let agedDisposed = Self.pruned(disposed, olderThan: Self.defaultPruneDays, now: Date())
            clips = activeWithFiles.sorted { $0.capturedAt > $1.capturedAt }
            disposedClips = agedDisposed
        } catch {
            // Corrupt manifest — start fresh rather than block the user.
            clips = []
        }
    }

    /// Runs the heavy migration steps that must not race with
    /// CloudKit's initial-import window:
    ///   - Backup write of `manifest.json` (one-shot, gated by
    ///     existence of `manifest.backup.*.json`).
    ///   - Pull legacy `InboxProcessedClipIds.json` into `.disposed`
    ///     tombstones, then delete the legacy file (gated by
    ///     existence of that legacy file).
    ///
    /// Idempotent — safe to call multiple times. After the first
    /// successful run both file-existence gates become falsy and
    /// subsequent calls are no-ops.
    ///
    /// Call site: `LaunchScreenView.runMigration()` (which also
    /// drives `FragmentMigration`), invoked after the CloudKit
    /// import-success event OR the 3-second safety net fires. Per
    /// the existing comment in LaunchScreenView.swift:230 that
    /// window is where the two-MOM race lives; running our
    /// migration after it eliminates the crash.
    ///
    /// Trade-off: between app launch and this hook firing, the B5
    /// dedup gate (`status(for:) == .disposed`) won't catch clipIds
    /// whose only record was in the legacy file. The window is
    /// narrow (1-3 seconds typical) and the consequence — a ghost
    /// re-delivery from one of those clipIds slipping through —
    /// only matters for the FIRST launch after the rebuild lands
    /// on a device that has a legacy file. Subsequent launches the
    /// migration has already absorbed them into tombstones.
    func runStartupMigrationsIfNeeded() {
        Self.backupManifestIfNeeded()
        let migrated = Self.migrateLegacyDisposedSet(
            legacyURL: Self.legacyProcessedClipIdsURL,
            now: Date()
        )
        guard !migrated.isEmpty else { return }
        NSLog("[Himem][Inbox] migrated \(migrated.count) legacy disposed clipId(s) to tombstones")
        let merged = mergeDisposed(existing: disposedClips, migrated: migrated)
        let aged = Self.pruned(merged, olderThan: Self.defaultPruneDays, now: Date())
        disposedClips = aged
        persist()
    }

    private func partition(_ all: [InboxClip]) -> (active: [InboxClip], disposed: [InboxClip]) {
        var active: [InboxClip] = []
        var disposed: [InboxClip] = []
        for clip in all {
            if clip.status == .disposed {
                disposed.append(clip)
            } else {
                active.append(clip)
            }
        }
        return (active, disposed)
    }

    private func mergeDisposed(existing: [InboxClip], migrated: [InboxClip]) -> [InboxClip] {
        let known = Set(existing.map(\.clipId))
        return existing + migrated.filter { !known.contains($0.clipId) }
    }

    /// Writes a copy of `manifest.json` to
    /// `manifest.backup.<unix-seconds>.json` the first time `load`
    /// runs on a build that has the backup hook. The presence of any
    /// `manifest.backup.*.json` file in the inbox root gates
    /// subsequent runs to a no-op — idempotent without UserDefaults.
    private static func backupManifestIfNeeded() {
        let fm = FileManager.default
        let root = inboxRoot
        let url = manifestURL
        guard fm.fileExists(atPath: url.path) else { return }
        let existing = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        if existing.contains(where: { $0.hasPrefix("manifest.backup.") }) {
            return
        }
        let stamp = Int(Date().timeIntervalSince1970)
        let dest = root.appendingPathComponent("manifest.backup.\(stamp).json")
        do {
            try fm.copyItem(at: url, to: dest)
            NSLog("[Himem][Inbox] wrote one-shot backup at \(dest.lastPathComponent)")
        } catch {
            NSLog("[Himem][Inbox] backup copy failed: \(error.localizedDescription)")
        }
    }

    /// Public hook so app launch and scene-active can force the
    /// icon badge to match the current inbox count. Defensive against
    /// state drift from notifications that fired while the app was
    /// killed: the push set the badge to N when delivered, but if the
    /// user reviewed clips in-app and then quit, the next launch
    /// might find the manifest empty while the badge still shows N.
    /// Calling this on scene-active resolves the gap immediately.
    func syncBadgeNow() {
        syncIconBadge(to: clips.count)
    }

    #if DEBUG
    /// Test seam — replaces the manifest's `clips` and
    /// `disposedClips` (partitioned by status) without going through
    /// persistence. Lets tests seed precise scenarios without
    /// touching disk. Tombstones in `next` route to `disposedClips`;
    /// everything else is treated as active.
    func debugReplaceClipsForTesting(_ next: [InboxClip]) {
        let (active, disposed) = partition(next)
        clips = active.sorted { $0.capturedAt > $1.capturedAt }
        disposedClips = disposed
    }
    #endif
}

private extension JSONEncoder {
    static let iso8601: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

private extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
