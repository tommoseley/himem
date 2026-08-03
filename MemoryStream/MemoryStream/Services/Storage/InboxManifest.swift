import Foundation
import Combine
import CoreData
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
    /// "Opened by you" — flips true the first time the user opens this
    /// clip (P7-2, July 18 2026). Drives the New filter (`New = reviewed
    /// == false`). **Per-device, not synced** — it rides the local
    /// manifest, never CloudKit; review state is a noise-reduction signal,
    /// so per-device is honest for v1. Legacy rows decode `false`.
    let reviewed: Bool
    /// Non-nil = this bench clip is in Recently Deleted (P8b, July 20 2026).
    /// A user-deleted unpromoted clip — recoverable for 30 days. **Per-device,
    /// not synced** — rides the local manifest exactly like `reviewed`, no
    /// CloudKit schema/deploy (an `InboxClip` is a manifest row, not a
    /// `MediaReference`). Legacy rows decode nil.
    let recycledAt: Date?

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
        fileSizeBytes: Int64? = nil,
        reviewed: Bool = false,
        recycledAt: Date? = nil
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
        self.reviewed = reviewed
        self.recycledAt = recycledAt
    }

    /// Rebuilds this clip with a new `recycledAt`, preserving every other
    /// field — used when moving a clip in/out of Recently Deleted (P8b).
    func withRecycledAt(_ date: Date?) -> InboxClip {
        InboxClip(
            clipId: clipId, capturedAt: capturedAt, duration: duration,
            transcript: transcript, latitude: latitude, longitude: longitude,
            source: source, audioFilename: audioFilename,
            transcriptionAttempted: transcriptionAttempted, rollGroupId: rollGroupId,
            status: status, disposedAt: disposedAt, announcedAt: announcedAt,
            fileSizeBytes: fileSizeBytes, reviewed: reviewed, recycledAt: date
        )
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
        case reviewed
        case recycledAt
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
        reviewed = try c.decodeIfPresent(Bool.self, forKey: .reviewed) ?? false
        recycledAt = try c.decodeIfPresent(Date.self, forKey: .recycledAt)
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

    /// User-deleted bench clips in Recently Deleted (P8b, July 20 2026) —
    /// `recycledAt != nil`, recoverable for 30 days. Kept out of `clips`
    /// (so the bench excludes them) and out of `disposedClips` (those are
    /// permanent redelivery tombstones). Persisted in the same JSON,
    /// partitioned by `recycledAt` on load. Not `@Published` — the bin reads
    /// a snapshot via `loadRecycledClips()`; a restore republishes `clips`.
    private var recycledClips: [InboxClip] = []

    /// User-dismissed cluster proposals per spec § "Sort is the
    /// bench's resting state" + Tom's Q3 answer (July 4 2026).
    /// Tapping *Not together* on a cluster stores it here so Sort
    /// won't re-propose the same grouping. Persisted to a separate
    /// JSON file (`dismissed-clusters.json`) alongside
    /// `manifest.json` — no schema break on the inbox format.
    ///
    /// **Prune-on-write:** after any inbox mutation, entries whose
    /// clipIds no longer all exist in the inbox are dropped. The
    /// fingerprint referencing a missing clipId is dead anyway —
    /// the proposer only ever produces fingerprints from current
    /// clipIds, so a dismissed record with a placed clipId can
    /// never match a future proposal.
    ///
    /// `@Published` so `SessionListView` (which observes
    /// `InboxManifest.shared` as `@ObservedObject`) re-renders
    /// when the user taps *Not together* on a cluster card. The
    /// prior "not Published" reasoning ("a `@Published` clips
    /// update already drives the refresh") was wrong: dismissing
    /// a cluster does NOT touch `clips`, so no publish fires,
    /// SwiftUI never re-runs the `proposals` computed property,
    /// and the dismissed cluster stays on screen (field-observed
    /// bug 2026-07-11).
    ///
    /// Money-tested by `InboxManifestDismissedClustersTests.dismissCluster_firesObjectWillChange_soSwiftUIRerenders`.
    @Published private(set) var dismissedClusters: [DismissedCluster] = []

    /// Voice clip ids the user has *Removed from session* via the
    /// Clip Detail fate row (`Clip model · spec.md` § "Clip triage"
    /// July 12 2026). A solo clip survives on the bench but the
    /// grouper emits it as its own single-clip session — the user
    /// declared it doesn't belong in the cluster the clock would
    /// otherwise form. Persistent across launches via the
    /// `solo-clip-ids.json` companion file.
    ///
    /// `@Published` for the same reason as `dismissedClusters`:
    /// removing a clip from a session doesn't mutate `clips`, so
    /// SwiftUI would never re-run the session grouper without an
    /// explicit publish here.
    @Published private(set) var soloClipIds: Set<UUID> = []

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
    /// Audio clips from the watch land here, then move to
    /// `SpeechService.audioDirectory` when bundled into a memory.
    /// Resolves to the iCloud Drive ubiquity container's `Inbox/`
    /// subdirectory when iCloud is available, sandbox
    /// `Documents/Inbox/` otherwise. The legacy sandbox path was
    /// `Documents/ClipInbox/audio/`; migrated on first launch via
    /// `UbiquityStore.migrateSandboxFilesIfNeeded()`. The inbox
    /// `manifest.json` itself stays in sandbox via `inboxRoot` — it's
    /// per-device sync state, not user content.
    nonisolated static var audioDirectory: URL {
        UbiquityStore.shared.inboxDirectory
    }
    nonisolated static var manifestURL: URL { inboxRoot.appendingPathComponent("manifest.json") }
    /// Companion file to `manifestURL` holding the Sort dismissal
    /// store (spec § "Sort is the bench's resting state"). Separate
    /// file so the manifest's own JSON schema stays unchanged.
    nonisolated static var dismissedClustersURL: URL {
        inboxRoot.appendingPathComponent("dismissed-clusters.json")
    }
    /// Companion file to `manifestURL` holding the per-clip "keep
    /// this loose, don't group into any session" flag set
    /// (`Clip model · spec.md` § "Clip triage" July 12 2026:
    /// *Remove from session* is a structural edit that survives
    /// across app launches). Separate file so the manifest JSON
    /// schema stays unchanged.
    nonisolated static var soloClipIdsURL: URL {
        inboxRoot.appendingPathComponent("solo-clip-ids.json")
    }
    nonisolated static func audioURL(for filename: String) -> URL {
        UbiquityStore.shared.inboxURL(for: filename)
    }

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
        // P8b: a clip the user recycled (Recently Deleted) must not be
        // re-accepted by a watch redelivery — that would resurrect it on the
        // bench AND leave a duplicate in the bin.
        if recycledClips.contains(where: { $0.clipId == clip.clipId }) { return }
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
    /// Returns the text actually stored, or `nil` when the clip is not in
    /// the manifest and nothing was written. **The nil case used to be a
    /// bare `return`** — a hand edit routed here for a clip that had left
    /// the manifest vanished with no error and no signal, and the editor
    /// reported success (F24 Defect 3). The value is `@discardableResult`
    /// so the transcription pipeline's fire-and-forget callers are
    /// unchanged; the *user-facing* write path checks it.
    @discardableResult
    func recordTranscriptionAttempt(clipId: UUID, transcript: String) -> String? {
        guard let idx = clips.firstIndex(where: { $0.clipId == clipId }) else { return nil }
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
            disposedAt: existing.disposedAt,
            announcedAt: existing.announcedAt,
            fileSizeBytes: existing.fileSizeBytes,
            reviewed: existing.reviewed
        )
        var next = clips
        next[idx] = updated
        replace(with: next)
        return updated.transcript
    }

    /// Flips a clip's `reviewed` to true on first open (P7-2). Per-device,
    /// rides the manifest. No-op if already reviewed or the clip's gone —
    /// so it's cheap to call on every open. Carries every other field
    /// forward verbatim (same discipline as `recordTranscriptionAttempt`).
    func markReviewed(clipId: UUID) {
        guard let idx = clips.firstIndex(where: { $0.clipId == clipId }) else { return }
        let existing = clips[idx]
        guard !existing.reviewed else { return }
        let updated = InboxClip(
            clipId: existing.clipId,
            capturedAt: existing.capturedAt,
            duration: existing.duration,
            transcript: existing.transcript,
            latitude: existing.latitude,
            longitude: existing.longitude,
            source: existing.source,
            audioFilename: existing.audioFilename,
            transcriptionAttempted: existing.transcriptionAttempted,
            rollGroupId: existing.rollGroupId,
            status: existing.status,
            disposedAt: existing.disposedAt,
            announcedAt: existing.announcedAt,
            fileSizeBytes: existing.fileSizeBytes,
            reviewed: true
        )
        var next = clips
        next[idx] = updated
        replace(with: next)
    }

    /// Batch variant — marks every listed clip reviewed in a single
    /// persist. Used when opening a session card marks the whole session
    /// seen at once (P7-2, "open the container → its contents are seen"),
    /// so a 5-clip session doesn't write the manifest five times. No-op
    /// for ids already reviewed or absent; if nothing changes, no write.
    func markReviewed(clipIds: [UUID]) {
        let targets = Set(clipIds)
        var changed = false
        let next = clips.map { clip -> InboxClip in
            guard targets.contains(clip.clipId), !clip.reviewed else { return clip }
            changed = true
            return InboxClip(
                clipId: clip.clipId,
                capturedAt: clip.capturedAt,
                duration: clip.duration,
                transcript: clip.transcript,
                latitude: clip.latitude,
                longitude: clip.longitude,
                source: clip.source,
                audioFilename: clip.audioFilename,
                transcriptionAttempted: clip.transcriptionAttempted,
                rollGroupId: clip.rollGroupId,
                status: clip.status,
                disposedAt: clip.disposedAt,
                announcedAt: clip.announcedAt,
                fileSizeBytes: clip.fileSizeBytes,
                reviewed: true
            )
        }
        guard changed else { return }
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
        // RH-8: coordinated delete of the staged ubiquity-container audio.
        // No-op when the file was already moved out (promotion moves audio
        // into the voice store before this runs).
        UbiquityStore.shared.removeFromStore(at: Self.audioURL(for: clip.audioFilename))
        // Snapshot the ack decision BEFORE the array is mutated — the
        // clip's rollGroupId is what we need to send.
        let actions = Self.ackActions(for: [clipId], in: clips)
        let next = clips.filter { $0.clipId != clipId }
        disposedClips.append(tombstone(from: clip))
        replace(with: next)
        WatchInboxNotificationCoordinator.shared.clipRemoved(clipId: clipId)
        emitAcks(actions)
        NSLog("[HiMem][Inbox] remove(clipId:) emitted \(actions.count) ack(s) for clipId=\(clipId), tombstones=\(disposedClips.count)")
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
        NSLog("[HiMem][Inbox] removeBatch emitted \(actions.count) ack(s) for \(clipIds.count) clipId(s), tombstones=\(disposedClips.count)")
    }

    // MARK: - Recently Deleted (P8b, July 20 2026 — uniform clip bin)

    /// Soft-delete a bench clip to Recently Deleted — moves it out of the
    /// active `clips` (so it leaves the bench) into `recycledClips`, stamped
    /// with `recycledAt`. Unlike `remove`, the audio is **preserved** (needed
    /// for restore + playback) and **no watch ack is emitted** (the clip
    /// isn't disposed, it's recoverable — a purely local UI state).
    func recycleClip(clipId: UUID, now: Date = Date()) {
        guard let clip = clips.first(where: { $0.clipId == clipId }) else { return }
        recycledClips.insert(clip.withRecycledAt(now), at: 0)
        replace(with: clips.filter { $0.clipId != clipId })
    }

    /// Batch soft-delete — the Unconnected "Delete N" inbox portion.
    func recycleClips(clipIds: [UUID], now: Date = Date()) {
        let idSet = Set(clipIds)
        let moved = clips.filter { idSet.contains($0.clipId) }
        guard !moved.isEmpty else { return }
        recycledClips.insert(contentsOf: moved.map { $0.withRecycledAt(now) }, at: 0)
        replace(with: clips.filter { !idSet.contains($0.clipId) })
    }

    /// Restore a recycled clip to the bench — clears `recycledAt` and moves
    /// it back into `clips`, where `ClipSessionGrouper`/`computeSessions`
    /// re-groups it into its sitting (the ruling's "re-enters session
    /// grouping"). No-op if the id isn't recycled.
    func restoreClip(clipId: UUID) {
        guard let clip = recycledClips.first(where: { $0.clipId == clipId }) else { return }
        recycledClips.removeAll { $0.clipId == clipId }
        let restored = clip.withRecycledAt(nil)
        replace(with: (clips + [restored]).sorted { $0.capturedAt > $1.capturedAt })
    }

    /// Audio filenames still referenced by a non-disposed clip — active OR
    /// recycled-not-purged. The RH-8 orphan sweep's inbox keep-set: a
    /// recycled clip's staged blob must NEVER be swept, so recycled clips are
    /// included. Disposed tombstones carry `audioFilename == ""` and are
    /// excluded (their file is already gone / to-be-purged).
    var referencedAudioFilenames: Set<String> {
        Set((clips + recycledClips).map(\.audioFilename).filter { !$0.isEmpty })
    }

    /// Recently-Deleted bench clips (snapshot), newest-deleted first — the
    /// bin reads this on reload.
    func loadRecycledClips() -> [InboxClip] {
        recycledClips.sorted { ($0.recycledAt ?? .distantPast) > ($1.recycledAt ?? .distantPast) }
    }

    /// Permanent destruction from the bin (Delete Forever) — removes the
    /// audio and drops the row to a `.disposed` tombstone (redelivery-gated,
    /// `recycledAt` cleared so it never re-partitions as recycled). `clips`
    /// is untouched, so this persists directly rather than republishing.
    func purgeRecycledClip(clipId: UUID) {
        guard let clip = recycledClips.first(where: { $0.clipId == clipId }) else { return }
        // RH-8: the staged audio lives in the iCloud Files ubiquity container
        // — delete it NSFileCoordinator-wrapped (was a bare removeItem).
        UbiquityStore.shared.removeFromStore(at: Self.audioURL(for: clip.audioFilename))
        recycledClips.removeAll { $0.clipId == clipId }
        disposedClips.append(tombstone(from: clip))
        persist()
    }

    /// Status of a clipId across both active and disposed rows. nil
    /// when the manifest has no entry — the rebuild's single-source
    /// query that replaces `InboxProcessedClipIds.contains(_:)` and
    /// the multi-array idempotency checks in `acceptArrivedClip`.
    func status(for clipId: UUID) -> InboxClip.Status? {
        if let c = clips.first(where: { $0.clipId == clipId }) { return c.status }
        // P8b: a recycled clip is "known" so the arrival tracker's
        // `status(for:) != nil` gate drops a redelivery instead of
        // re-accepting it (it still lives in the bin, recoverable).
        if let r = recycledClips.first(where: { $0.clipId == clipId }) { return r.status }
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
            disposedAt: Date(),
            announcedAt: clip.announcedAt,
            fileSizeBytes: clip.fileSizeBytes,
            reviewed: clip.reviewed
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
        let previousIds = Set(clips.map(\.clipId))
        let nextIds = Set(next.map(\.clipId))
        // New arrivals = ids in `next` that weren't there before.
        // Presence, not count — per `CLAUDE.md` §Phone (July 10 2026)
        // "the dot represents new, unseen arrivals and clears when
        // the user opens Clips."
        if !nextIds.subtracting(previousIds).isEmpty {
            hasUnseenArrivals = true
            UserDefaults.standard.set(true, forKey: Self.unseenArrivalsKey)
        }
        clips = next
        // Prune-on-write hook: any dismissed-cluster record whose
        // clipIds are no longer all in the inbox becomes dead
        // weight (the fingerprint referencing a placed clipId
        // can never match a future proposal since the proposer
        // only produces fingerprints from current clipIds). Drop
        // those records before persisting. Spec § "Sort is the
        // bench's resting state" + Tom's Q3 answer.
        pruneDeadDismissedClusters()
        pruneDeadSoloClipIds()
        persist()
        // Home-screen numeric badge retired 2026-07-10 per `CLAUDE.md`
        // §Phone ("App-icon badge: none. iOS only supports a numeric
        // app-icon badge, and a number reintroduces counting"). Force
        // it to 0 so any lingering push payload can't leave a stale
        // number on the icon.
        syncIconBadge(to: 0)
    }

    /// The number iOS is asked to put on the app icon, given how many clips
    /// are pending. **Always zero, by product decision.**
    ///
    /// `CLAUDE.md` §Phone (locked July 10 2026): *"App-icon badge: none. iOS
    /// only supports a numeric app-icon badge, and a number reintroduces
    /// counting"* — the guilt-inbox HiMem rejects. Presence lives on the Clips
    /// tab dot instead.
    ///
    /// Split out from `syncIconBadge` so the decision is assertable
    /// (`InboxManifestBadgeSyncTests`). Restoring a real count here is a
    /// vocabulary/principle change, not an implementation fix: it needs a
    /// ruling, and this returning anything but 0 should fail the build's tests
    /// rather than ship quietly (F23 T2.5).
    static func iconBadgeCount(forPending pendingCount: Int) -> Int { 0 }

    /// Zeroes the home-screen icon badge unconditionally — see
    /// `iconBadgeCount(forPending:)`. Kept as a defensive zeroing call so push
    /// payloads (which iOS still processes) can't leave a stale number on the
    /// icon.
    private func syncIconBadge(to count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(Self.iconBadgeCount(forPending: count)) { _ in }
    }

    private func persist() {
        guard !manifestIsUnreadable else {
            // The file on disk could not be read and could not be moved aside,
            // so the in-memory array is known NOT to describe it. Writing here
            // would discard rows we can still see the bytes of (F23 T1.4).
            ErrorState.shared.report(.saveFailed("Inbox manifest not persisted: the existing file is unreadable and could not be moved aside; refusing to overwrite it."))
            persistDismissedClusters()
            return
        }
        let url = Self.manifestURL
        let tmp = url.appendingPathExtension("tmp")
        do {
            // Single JSON file holds active, recycled, and disposed rows;
            // partitioned on load (recycledAt first, then status). Active
            // first so a human reading the file sees the live inbox at the top.
            let combined = clips + recycledClips + disposedClips
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
        // Also persist the dismissed-clusters companion file. Cheap
        // even when empty — the set is bounded by the number of
        // clusters the user has ever declined, and the JSON is a
        // small array.
        persistDismissedClusters()
    }

    /// Persists the dismissed-clusters companion file. Called from
    /// the same `persist()` path as the manifest so a single
    /// mutation writes both files.
    private func persistDismissedClusters() {
        let url = Self.dismissedClustersURL
        let tmp = url.appendingPathExtension("tmp")
        do {
            let data = try JSONEncoder.iso8601.encode(dismissedClusters)
            try data.write(to: tmp, options: .atomic)
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            ErrorState.shared.report(.saveFailed("Dismissed clusters persist failed: \(error.localizedDescription)"))
        }
    }

    /// Loads the dismissed-clusters companion file. Called from
    /// `load()`. Missing file → empty set (fresh install / never
    /// used Sort). Corrupt file → empty set (rare; user re-earns
    /// their dismissals).
    private func loadDismissedClusters() {
        let url = Self.dismissedClustersURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            dismissedClusters = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            dismissedClusters = try JSONDecoder.iso8601.decode([DismissedCluster].self, from: data)
        } catch {
            dismissedClusters = []
        }
    }

    /// Persists `soloClipIds` to its companion file. Called from
    /// `markSolo` / `unmarkSolo` and from the prune path in
    /// `replace(with:)` when stale ids get filtered out.
    private func persistSoloClipIds() {
        let url = Self.soloClipIdsURL
        let tmp = url.appendingPathExtension("tmp")
        do {
            let data = try JSONEncoder.iso8601.encode(Array(soloClipIds))
            try data.write(to: tmp, options: .atomic)
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            ErrorState.shared.report(.saveFailed("Solo clip ids persist failed: \(error.localizedDescription)"))
        }
    }

    /// Loads the solo-clip-ids companion file. Called from
    /// `load()`. Missing file → empty set (fresh install / user
    /// never removed a clip from a session).
    private func loadSoloClipIds() {
        let url = Self.soloClipIdsURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            soloClipIds = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let array = try JSONDecoder.iso8601.decode([UUID].self, from: data)
            soloClipIds = Set(array)
        } catch {
            soloClipIds = []
        }
    }

    // MARK: - Sort dismissal (spec § "Sort is the bench's resting state")

    /// Fingerprints the workbench's Sort proposer should suppress.
    /// Computed from `dismissedClusters` — the persisted store keeps
    /// the source clipIds + rule so prune-on-write can detect dead
    /// records. The proposer only needs the fingerprint set.
    var dismissedClusterFingerprints: Set<ClusterFingerprint> {
        Set(dismissedClusters.map(\.fingerprint))
    }

    /// Records a user's *Not together* dismissal for a cluster.
    /// Idempotent — the same proposal can't dismiss twice (dedup
    /// on the derived fingerprint). Persists immediately.
    func dismissCluster(_ proposal: ClusterProposal) {
        let record = DismissedCluster(
            clipIds: Set(proposal.clipIds),
            ruleTag: proposal.ruleTag
        )
        let fp = record.fingerprint
        // Idempotent — no-op if already dismissed.
        guard !dismissedClusters.contains(where: { $0.fingerprint == fp }) else { return }
        dismissedClusters.append(record)
        persistDismissedClusters()
    }

    /// Prunes dismissed-cluster records whose member clipIds are
    /// no longer all present in the current inbox. Called from
    /// every mutation path via `replace(with:)`. A dismissed
    /// fingerprint referencing a placed (missing) clipId is dead
    /// weight — the proposer only ever produces fingerprints from
    /// current clipIds, so the record can never match a future
    /// proposal.
    /// Bench clip ids that live as materialized `MediaReference`s rather
    /// than manifest rows — the second store the bench composes from.
    /// Overridable so the prune can be exercised without Core Data.
    nonisolated(unsafe) static var materializedBenchClipIds: () -> Set<UUID> = {
        let ctx = StorageService.shared.viewContext
        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        req.predicate = NSPredicate(
            format: "edges.@count == 0 AND recycledAt == nil AND mediaType == %@",
            MediaReference.MediaType.voice.rawValue
        )
        return Set(((try? ctx.fetch(req)) ?? []).map(\.id))
    }

    private func pruneDeadDismissedClusters() {
        // **F41 · the prune must read the same set the PROPOSER reads.**
        //
        // The comment above ("the proposer only ever produces fingerprints
        // from current clipIds") was true when the bench read one store. P0-3
        // made the bench read TWO — `composeBenchClips(manifestClips:refs:)`
        // unions manifest rows with materialized zero-edge voice refs — and
        // the prune was never updated. So dismissing a cluster containing any
        // ref-backed clip wrote the record and then deleted it on the very
        // next manifest write, because that clipId is not in `clips`. The
        // cluster re-proposed immediately: "Not together" did not stick.
        //
        // Pruning is an optimisation; a stale record is harmless dead weight,
        // while a wrongly-pruned one destroys the user's stated intent. So
        // the union is taken, and if the ref side is unavailable the prune
        // keeps the record rather than guessing.
        let liveIds = Set(clips.map(\.clipId)).union(Self.materializedBenchClipIds())
        let filtered = dismissedClusters.filter { record in
            record.clipIds.isSubset(of: liveIds)
        }
        guard filtered.count != dismissedClusters.count else { return }
        dismissedClusters = filtered
        persistDismissedClusters()
    }

    /// Records the user's *Remove from session* fate action for a
    /// voice clip. Idempotent — marking an already-solo clip is a
    /// no-op. The grouper (`ClipSessionGrouper.group`) reads the
    /// set and emits solo clips as their own single-clip sessions.
    /// Persists immediately so the state survives an app relaunch.
    func markSolo(clipId: UUID) {
        guard !soloClipIds.contains(clipId) else { return }
        soloClipIds.insert(clipId)
        persistSoloClipIds()
    }

    /// Inverse of `markSolo` — restores a clip to normal grouping.
    /// Not currently wired to any UI (Chunk C only ships the
    /// forward direction), but present so the state store is
    /// symmetric and future "Undo Remove" can hook in without
    /// growing the API.
    func unmarkSolo(clipId: UUID) {
        guard soloClipIds.contains(clipId) else { return }
        soloClipIds.remove(clipId)
        persistSoloClipIds()
    }

    /// Prunes solo-clip-id entries whose clipIds are no longer in
    /// the current inbox (bundled, deleted, or promoted to a
    /// memory). Called from `replace(with:)` alongside the
    /// dismissed-clusters prune.
    private func pruneDeadSoloClipIds() {
        let liveIds = Set(clips.map(\.clipId))
        let filtered = soloClipIds.intersection(liveIds)
        guard filtered.count != soloClipIds.count else { return }
        soloClipIds = filtered
        persistSoloClipIds()
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
        defer {
            // Numeric badge retired 2026-07-10; force to zero on load.
            syncIconBadge(to: 0)
            // Load the companion Sort-dismissals file. Missing file
            // → empty set, safe on fresh install.
            loadDismissedClusters()
            // Load the companion solo-clip-ids file (Chunk C, Clip
            // triage July 12 2026). Missing → empty set.
            loadSoloClipIds()
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let loaded = try JSONDecoder.iso8601.decode([InboxClip].self, from: data)
            let (active, recycled, disposed) = partition(loaded)
            // **Don't drop rows whose audio file is temporarily
            // absent** (fix 2026-07-11 for Tom's "clips vanished after
            // update" repro). Watch-clip audio lives in the iCloud
            // ubiquity container — after an app update or fresh
            // sign-in, iCloud may not have finished downloading the
            // audio bytes by the moment `load()` runs. The old filter
            // (`activeWithFiles`) treated a missing file as evidence
            // of a partial-state crash and silently dropped the row;
            // the manifest kept the clip on disk but the UI never saw
            // it again until we somehow re-added it. That failure
            // mode is invisible to the user and violates
            // `CLAUDE.md` §Media specifics ("A missing file is a
            // calm, honest state, never an error or a blame") — the
            // authoritative metadata is safe in the manifest JSON
            // regardless of whether the bytes have landed yet.
            //
            // Log missing-audio rows so the console still surfaces
            // partial states; the UI treats them as normal clips
            // (audio playback will report "downloading from iCloud"
            // when the user hits play — that path already exists via
            // `UbiquityStore.downloadStatus`).
            let missingCount = active.filter { clip in
                !FileManager.default.fileExists(atPath: Self.audioURL(for: clip.audioFilename).path)
            }.count
            if missingCount > 0 {
                NSLog("[HiMem][Inbox] load() — \(missingCount) of \(active.count) active clip(s) have no local audio yet; keeping them so iCloud can catch up")
            }
            // Age out old tombstones. Active rows pass through.
            let agedDisposed = Self.pruned(disposed, olderThan: Self.defaultPruneDays, now: Date())
            clips = active.sorted { $0.capturedAt > $1.capturedAt }
            disposedClips = agedDisposed
            // P8b: recycled rows past 30 days become permanent tombstones on
            // load (the clip-level equivalent of the project bin's expiry).
            let now = Date()
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
            var stillRecycled: [InboxClip] = []
            for clip in recycled {
                if let at = clip.recycledAt, at < cutoff {
                    // RH-8: expiry is a permanent purge — delete the backing
                    // blob (was leaked: it only tombstoned the row).
                    UbiquityStore.shared.removeFromStore(at: Self.audioURL(for: clip.audioFilename))
                    disposedClips.append(tombstone(from: clip))
                } else {
                    stillRecycled.append(clip)
                }
            }
            recycledClips = stillRecycled.sorted { ($0.recycledAt ?? .distantPast) > ($1.recycledAt ?? .distantPast) }
        } catch {
            // Corrupt manifest — start fresh rather than block the user, but
            // NEVER at the cost of the rows.
            //
            // The old code reset `clips` and stopped there. The next mutation
            // calls `persist()`, which writes the whole in-memory array over
            // `manifest.json` — turning an unreadable file into an empty one
            // and permanently discarding every pending clip's transcript,
            // capturedAt, lat/lon and rollGroup. Those bytes are the only copy
            // of that metadata: `backupManifestIfNeeded` is gated on *any*
            // `manifest.backup.*` existing, so it is a one-shot lifetime
            // snapshot, not a recovery point at the moment of corruption. And
            // the audio then has no manifest row referencing it, which is
            // precisely what made it sweep-eligible (F23 T1.1).
            //
            // "Start fresh rather than block the user" stays true. What was
            // never established is that the rows are worthless — so they are
            // moved aside first, intact, and only then do we start fresh
            // (F23 T1.4, audit 2026-07-31).
            manifestIsUnreadable = (Self.quarantineUnreadableManifest(at: url) == nil)
            clips = []
        }
    }

    /// Set when `load()` could not read `manifest.json` **and** could not move
    /// the unreadable bytes aside. While it is set, `persist()` refuses to
    /// write — the in-memory state is known not to describe what is on disk,
    /// and overwriting is the one outcome that cannot be undone.
    private var manifestIsUnreadable = false

    /// Moves an unreadable `manifest.json` to
    /// `manifest.unreadable-<yyyyMMdd-HHmmss>.json` so the reset that follows
    /// cannot overwrite it. A **move**, not a copy: the same bytes must not be
    /// re-read (and re-quarantined) on every subsequent launch.
    ///
    /// Returns the quarantine URL, or `nil` when the bytes are still sitting at
    /// `url` — i.e. the caller must not persist over them.
    @discardableResult
    static func quarantineUnreadableManifest(
        at url: URL,
        now: Date = Date(),
        fileManager fm: FileManager = .default
    ) -> URL? {
        guard fm.fileExists(atPath: url.path) else {
            // Nothing on disk to lose — decoding empty/absent data. Persisting
            // is safe.
            return url
        }
        let stamp = Self.quarantineStampFormatter.string(from: now)
        let root = url.deletingLastPathComponent()
        var dest = root.appendingPathComponent("manifest.unreadable-\(stamp).json")
        var suffix = 2
        while fm.fileExists(atPath: dest.path) {
            dest = root.appendingPathComponent("manifest.unreadable-\(stamp)-\(suffix).json")
            suffix += 1
        }
        do {
            try fm.moveItem(at: url, to: dest)
            NSLog("[HiMem][Inbox] manifest.json was unreadable — moved to \(dest.lastPathComponent); its rows are recoverable from there")
            return dest
        } catch {
            NSLog("[HiMem][Inbox] manifest.json was unreadable AND could not be moved aside (\(error.localizedDescription)) — refusing to persist over it")
            return nil
        }
    }

    private static let quarantineStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

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
        NSLog("[HiMem][Inbox] migrated \(migrated.count) legacy disposed clipId(s) to tombstones")
        let merged = mergeDisposed(existing: disposedClips, migrated: migrated)
        let aged = Self.pruned(merged, olderThan: Self.defaultPruneDays, now: Date())
        disposedClips = aged
        persist()
    }

    private func partition(_ all: [InboxClip]) -> (active: [InboxClip], recycled: [InboxClip], disposed: [InboxClip]) {
        var active: [InboxClip] = []
        var recycled: [InboxClip] = []
        var disposed: [InboxClip] = []
        for clip in all {
            // Recently-Deleted (P8b) is checked first: a recycled row is
            // recoverable and distinct from a permanent `.disposed` tombstone.
            if clip.recycledAt != nil {
                recycled.append(clip)
            } else if clip.status == .disposed {
                disposed.append(clip)
            } else {
                active.append(clip)
            }
        }
        return (active, recycled, disposed)
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
            NSLog("[HiMem][Inbox] wrote one-shot backup at \(dest.lastPathComponent)")
        } catch {
            NSLog("[HiMem][Inbox] backup copy failed: \(error.localizedDescription)")
        }
    }

    /// Public hook so app launch and scene-active can force the icon
    /// badge to zero. Numeric badges retired 2026-07-10; this remains
    /// as a defensive zeroing call because iOS may have set a number
    /// via a push payload while the app was killed.
    func syncBadgeNow() {
        syncIconBadge(to: 0)
    }

    // MARK: - Unseen-arrivals dot (presence, not count)

    /// Persistent key for the "there are new arrivals the user hasn't
    /// seen yet" flag.
    private static let unseenArrivalsKey = "himem.inbox.hasUnseenArrivals"

    /// User has arrivals they haven't reviewed since the last time
    /// they opened the Clips tab. Drives the presence dot on the
    /// Clips tab item per `CLAUDE.md` §Phone (July 10 2026) — never
    /// a count.
    @Published var hasUnseenArrivals: Bool = UserDefaults.standard.bool(forKey: InboxManifest.unseenArrivalsKey)

    /// Clears the presence-dot flag. HiMemTabView calls this when the
    /// user selects the Clips tab. Persistent so a re-launch remembers
    /// the "seen" state.
    func markAllSeen() {
        guard hasUnseenArrivals else { return }
        hasUnseenArrivals = false
        UserDefaults.standard.set(false, forKey: Self.unseenArrivalsKey)
    }

    #if DEBUG
    /// Test seam — replaces the manifest's `clips` and
    /// `disposedClips` (partitioned by status) without going through
    /// persistence. Lets tests seed precise scenarios without
    /// touching disk. Tombstones in `next` route to `disposedClips`;
    /// everything else is treated as active.
    func debugReplaceClipsForTesting(_ next: [InboxClip]) {
        let (active, recycled, disposed) = partition(next)
        clips = active.sorted { $0.capturedAt > $1.capturedAt }
        recycledClips = recycled
        disposedClips = disposed
    }

    /// Test seam for the Sort dismissal store — replaces
    /// `dismissedClusters` in place, without going through disk.
    /// Lets tests reset state between runs cleanly. Never call
    /// from production code.
    func debugReplaceDismissedForTesting(_ next: [DismissedCluster]) {
        dismissedClusters = next
    }

    /// Fixed ids for the seeded Sort-repro cluster so
    /// `debugClearTestCluster` removes exactly these and re-seeding is
    /// idempotent.
    static let debugTestClusterClipIds: [UUID] = [
        UUID(uuidString: "5EED0000-0000-0000-0000-000000000001")!,
        UUID(uuidString: "5EED0000-0000-0000-0000-000000000002")!,
        UUID(uuidString: "5EED0000-0000-0000-0000-000000000003")!,
    ]

    /// Seeds three transcribed clips that flow through the **real** grouping
    /// path (`ClipSessionGrouper` → `ClipClusterProposer`) to surface a
    /// multi-clip Sort cluster on demand — so the cluster editor, and the
    /// aggregate-arbiter check that needs a multi-clip context, are
    /// reproducible without waiting on organic dogfood.
    ///
    /// Mechanics: spaced 15 min apart (> the 10-min idle gap → three separate
    /// sessions) and sharing a distinctive **bigram** ("Kingfisher Wharf"),
    /// which clusters via `proposeWordMatch` with no NLTagger dependency
    /// (bigrams use plain tokenization — robust on sim *and* device) and no
    /// time/location gate. The shared coordinate also feeds the time+place
    /// rule as a bonus signal. Non-destructive + idempotent: existing bench
    /// clips are preserved and a prior seed is replaced, not duplicated.
    func debugSeedTestCluster() {
        let now = Date()
        let lat = 32.2371, lon = -80.8557   // Bluffton — the spec's example place
        let lines = [
            "Notes from Kingfisher Wharf about the afternoon harbor plan.",
            "More from Kingfisher Wharf, watching the boats come in.",
            "Last one from Kingfisher Wharf before heading home.",
        ]
        var next = clips.filter { !Self.debugTestClusterClipIds.contains($0.clipId) }
        for (i, id) in Self.debugTestClusterClipIds.enumerated() {
            next.append(InboxClip(
                clipId: id,
                capturedAt: now.addingTimeInterval(Double(-i) * 15 * 60),
                duration: 5,
                transcript: lines[i],
                latitude: lat,
                longitude: lon,
                source: "phone",
                audioFilename: "",            // no real audio — play is inert for the seed
                transcriptionAttempted: true,
                rollGroupId: nil,             // idle-gap applies → three sessions
                status: .transcribed
            ))
        }
        next.sort { $0.capturedAt > $1.capturedAt }
        replace(with: next)
    }

    /// Removes the seeded Sort-repro clips, leaving the real bench intact.
    func debugClearTestCluster() {
        replace(with: clips.filter { !Self.debugTestClusterClipIds.contains($0.clipId) })
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

/// Per-device review state for bench `MediaReference`s (P7-2, July 18 2026).
/// A `MediaReference` is CloudKit-synced, so a stored `reviewed` attribute
/// would sync and force a schema deploy; review state is per-device +
/// no-deploy by decision, so it lives here in UserDefaults instead, keyed
/// by ref id. The bench-ref sibling of `InboxClip.reviewed` (which rides
/// its own local manifest) — both fold into one `New = not reviewed`
/// predicate. Cross-device review-sync is out of scope for v1 (rides the
/// post-v1 bench→MediaReference unification).
enum BenchClipReviewStore {
    private static let key = "com.himem.bench.reviewedRefIds"

    static func isReviewed(_ id: UUID) -> Bool {
        reviewedIds().contains(id.uuidString)
    }

    /// Idempotent — a no-op (no write) when the id is already recorded.
    static func markReviewed(_ id: UUID) {
        var ids = reviewedIds()
        guard ids.insert(id.uuidString).inserted else { return }
        UserDefaults.standard.set(Array(ids), forKey: key)
    }

    /// Batch variant — one write for the whole set (used by the backfill
    /// migration). Idempotent; no write when nothing new is added.
    static func markReviewed(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        var set = reviewedIds()
        var changed = false
        for id in ids where set.insert(id.uuidString).inserted { changed = true }
        guard changed else { return }
        UserDefaults.standard.set(Array(set), forKey: key)
    }

    private static func reviewedIds() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }
}

/// One-time backfill (2026-07-27): mark the entire PRE-EXISTING bench library
/// reviewed. Review tracking — `InboxClip.reviewed` (P7-2, July 18 2026) and
/// the ref-keyed `BenchClipReviewStore` — only records opens made THROUGH the
/// clip editor AFTER those mechanisms shipped. Every clip captured/opened/
/// promoted before then has no review record and decodes `reviewed == false`;
/// when such a clip later returns from a memory as a loose ref (`edges == 0`)
/// it floods the New lens as "unseen" though it was handled months ago (device
/// pass 2026-07-27: New listed May/June clips already opened and once in
/// memories).
///
/// This is a watermark, not a live-wiring fix — the open paths are correct
/// (every one presents `ClipEditorModal`, whose `.onAppear` marks reviewed).
/// Mark every `MediaReference` present at upgrade time reviewed. Scoped to
/// refs ONLY: recent manifest clips are all post-P7-2 and track correctly, so
/// blanket-marking them would wrongly hide genuinely-new arrivals.
enum BenchReviewBackfillMigration {
    static let doneKey = "com.himem.bench.reviewBackfill.v1.done"

    static var hasRun: Bool { UserDefaults.standard.bool(forKey: doneKey) }

    /// Pure core (unit-tested): record the ids reviewed and set the done flag.
    static func apply(refIds: [UUID]) {
        BenchClipReviewStore.markReviewed(refIds)
        UserDefaults.standard.set(true, forKey: doneKey)
    }

    /// Fetch every existing bench ref id and back-fill, once. Runs from
    /// `LaunchScreenView.runMigration` (post-CloudKit-settle, so historical
    /// refs are present) on a background context.
    static func runIfNeeded(in storage: StorageService) {
        guard !hasRun else { return }
        let ctx = storage.backgroundContext()
        ctx.perform {
            let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
            let ids = ((try? ctx.fetch(req)) ?? []).map { $0.id }
            apply(refIds: ids)
            NSLog("[HiMem][Inbox] bench review backfill: marked \(ids.count) existing ref(s) reviewed")
        }
    }
}

/// Per-device duration cache for materialized bench clips (P0-3). A voice
/// `MediaReference` carries no `duration` attribute (the no-schema-change
/// constraint), so the duration from the capture payload is stashed here at
/// materialize time and read back into the synthetic bench clip — the
/// originating device shows the real session length immediately. A device that
/// only RECEIVES the ref via CloudKit has no cache entry and shows 0:00; the
/// graceful degradation ruling (a) accepted (2026-07-25), pending an async
/// `AVURLAsset.load(.duration)` derivation on the bench card as a follow-up.
enum BenchClipDurationStore {
    private static let key = "com.himem.bench.clipDurations"

    static func duration(_ id: UUID) -> TimeInterval? {
        UserDefaults.standard.dictionary(forKey: key)?[id.uuidString] as? Double
    }

    /// Idempotent; a non-positive duration is not recorded (nothing to show).
    static func record(_ id: UUID, _ duration: TimeInterval) {
        guard duration > 0 else { return }
        var dict = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        dict[id.uuidString] = duration
        UserDefaults.standard.set(dict, forKey: key)
    }
}

/// Per-device "was in a memory" marker (P7-3, July 19 2026). A
/// `MediaReference` with `edges == 0` is otherwise indistinguishable
/// between never-connected (phone-bench capture) and previously-attached-
/// then-detached; this records the latter so the Unconnected row can show
/// the honest "was in a memory · now unconnected" line. Recorded only on a
/// USER detach (remove-from-memory / Let Go), never a system path.
///
/// Per-device + no-deploy, consistent with `reviewed`: the line is a
/// nicety, not load-bearing. Accepted limitation: the marker doesn't
/// survive reinstall or cross-device (a clip let-go on another device
/// shows without the line) — resolves with the same post-v1
/// bench→MediaReference unification as `reviewed`.
enum PreviouslyConnectedStore {
    private static let key = "com.himem.bench.previouslyConnectedRefIds"

    static func wasConnected(_ id: UUID) -> Bool {
        ids().contains(id.uuidString)
    }

    static func record(_ id: UUID) {
        var s = ids()
        guard s.insert(id.uuidString).inserted else { return }
        UserDefaults.standard.set(Array(s), forKey: key)
    }

    private static func ids() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }
}
