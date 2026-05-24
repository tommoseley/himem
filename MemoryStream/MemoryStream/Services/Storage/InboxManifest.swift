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
    /// shows different copy and styling for each.
    let transcriptionAttempted: Bool
    /// On-a-roll grouping signal — clips with the same non-nil
    /// `rollGroupId` always land in one Memory regardless of
    /// time/location heuristics. Optional so older manifest rows that
    /// predate the feature decode cleanly.
    let rollGroupId: UUID?

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
        rollGroupId: UUID? = nil
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
    }

    // Custom decoding so old persisted manifests (without
    // `transcriptionAttempted`) round-trip with the field defaulted to
    // false — anything in the existing inbox is treated as "still pending"
    // until we either replace its transcript or re-attempt recognition.
    private enum CodingKeys: String, CodingKey {
        case clipId, capturedAt, duration, transcript, latitude, longitude
        case source, audioFilename, transcriptionAttempted, rollGroupId
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

    /// Surfaced to the inbox UI and the Today banner. Sorted newest-first.
    @Published private(set) var clips: [InboxClip] = []

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
        let updated = InboxClip(
            clipId: existing.clipId,
            capturedAt: existing.capturedAt,
            duration: existing.duration,
            transcript: transcript,
            latitude: existing.latitude,
            longitude: existing.longitude,
            source: existing.source,
            audioFilename: existing.audioFilename,
            transcriptionAttempted: true
        )
        var next = clips
        next[idx] = updated
        replace(with: next)
    }

    /// Removes a single clip and its audio file. Called when the user
    /// deletes from the inbox or after a clip is promoted into a memory.
    func remove(clipId: UUID) {
        guard let clip = clips.first(where: { $0.clipId == clipId }) else { return }
        try? FileManager.default.removeItem(at: Self.audioURL(for: clip.audioFilename))
        let next = clips.filter { $0.clipId != clipId }
        replace(with: next)
        WatchInboxNotificationCoordinator.shared.clipRemoved(clipId: clipId)
    }

    /// Removes a batch — used when the user creates a memory from N clips
    /// or appends N clips to an existing memory. The audio files have
    /// already been moved out by the caller; we just drop the rows here.
    func removeBatch(clipIds: [UUID]) {
        let idSet = Set(clipIds)
        let next = clips.filter { !idSet.contains($0.clipId) }
        replace(with: next)
        for id in clipIds {
            WatchInboxNotificationCoordinator.shared.clipRemoved(clipId: id)
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
            let data = try JSONEncoder.iso8601.encode(clips)
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
        let url = Self.manifestURL
        defer { syncIconBadge(to: clips.count) }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let loaded = try JSONDecoder.iso8601.decode([InboxClip].self, from: data)
            // Drop rows whose audio file is gone — defensive against partial
            // states from older crashes.
            clips = loaded
                .filter { FileManager.default.fileExists(atPath: Self.audioURL(for: $0.audioFilename).path) }
                .sorted { $0.capturedAt > $1.capturedAt }
        } catch {
            // Corrupt manifest — start fresh rather than block the user.
            clips = []
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
