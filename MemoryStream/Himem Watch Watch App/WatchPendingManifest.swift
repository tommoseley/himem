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

    var id: UUID { clipId }

    var metadata: ClipMetadata {
        ClipMetadata(
            clipId: clipId,
            capturedAt: capturedAt,
            duration: duration,
            transcript: transcript,
            latitude: latitude,
            longitude: longitude,
            source: "watch"
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

    private init() {
        load()
    }

    var count: Int { clips.count }
    var isEmpty: Bool { clips.isEmpty }
    var isAtCap: Bool { clips.count >= Self.storageCap }

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
        guard let clip = clips.first(where: { $0.clipId == clipId }) else { return }
        try? FileManager.default.removeItem(at: Self.audioURL(for: clip.audioFilename))
        let next = clips.filter { $0.clipId != clipId }
        replace(with: next)
    }

    /// User-initiated delete from the pending list. Same effect as a
    /// confirmation-driven removal but without iPhone involvement —
    /// nothing was sent, so no "Synced ✓" badge either.
    func userDelete(clipId: UUID) {
        remove(clipId: clipId, viaSync: false)
    }

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
        let url = Self.manifestURL
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
}
