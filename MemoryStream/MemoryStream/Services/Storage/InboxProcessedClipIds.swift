import Foundation

/// Persistent set of `clipId`s the phone has *already disposed of* —
/// promoted into a memory, user-deleted, or discarded as part of a
/// session sweep. The watch-clip arrival path checks this set before
/// adding a clip to the inbox, so a clip the user already made a
/// decision about can't ghost-reappear if iOS re-delivers its
/// system-cached transferFile later.
///
/// **The bug this closes (B5, 2026-05-29).** When the watch calls
/// `transferFile`, iOS makes its own copy in a system delivery store
/// that's separate from both the watch app's `WatchPendingManifest`
/// and the phone app's `InboxManifest`. The OS retries delivery for
/// days on its own schedule. Clearing either app-level manifest does
/// not touch the OS queue, so iOS can deliver a clip the user
/// already deleted hours or days earlier — and the phone, finding
/// an empty inbox, treats it as a fresh arrival and files it again.
///
/// **Semantics.** Marking is one-way — once a clipId is "processed,"
/// it stays processed. Adding to the inbox does NOT mark; only
/// removal (which represents an explicit user decision) does. The
/// store is bounded at `maxCapacity` entries (~2000); older entries
/// drop off when the cap is exceeded. UUID collisions across that
/// many entries are astronomically unlikely, so the bound is a
/// pragmatic cap on disk usage rather than a correctness concern.
///
/// **Persistence.** JSON array at `Documents/InboxProcessedClipIds.json`,
/// rewritten atomically on every mutation. Cheap — order-of-bytes
/// per entry, and mutations happen at human timescales (a user
/// disposes of a handful of clips per session, not thousands).
@MainActor
final class InboxProcessedClipIds {
    static let shared = InboxProcessedClipIds()

    /// Hard ceiling on the number of clipIds we remember. Past
    /// this point the oldest entries drop off so the JSON file
    /// can't grow without bound. 2000 corresponds to ~80 KB on
    /// disk and roughly a year of heavy capture activity.
    static let maxCapacity = 2000

    private let storageURL: URL

    /// Newest-last. Maintains insertion order so we know which
    /// entries to evict when the cap is exceeded.
    private var ordered: [UUID] = []

    /// O(1) lookup mirror of `ordered`. Always kept in sync.
    private var set: Set<UUID> = []

    /// Convenience designated init for the shared singleton.
    /// Default storage URL points at the app's Documents
    /// directory.
    private convenience init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.init(storageURL: dir.appendingPathComponent("InboxProcessedClipIds.json"))
    }

    /// Test seam: construct an instance backed by a specified URL
    /// so tests don't trip over the singleton's shared state.
    init(storageURL: URL) {
        self.storageURL = storageURL
        load()
    }

    // MARK: - Public API

    /// `true` when this clipId has previously been processed and
    /// should NOT be re-added to the inbox on a re-delivery.
    func contains(_ clipId: UUID) -> Bool {
        set.contains(clipId)
    }

    /// Number of clipIds currently remembered. Visible for tests
    /// and diagnostic logging.
    var count: Int { ordered.count }

    /// Records that this clipId has been disposed of (promoted,
    /// user-deleted, or session-discarded). Idempotent — calling
    /// twice with the same id is a no-op.
    func markProcessed(_ clipId: UUID) {
        markProcessed([clipId])
    }

    /// Batch version. Used by `removeBatch` so a session-promotion
    /// of N clips persists once instead of N times.
    func markProcessed(_ clipIds: [UUID]) {
        var didChange = false
        for id in clipIds where !set.contains(id) {
            ordered.append(id)
            set.insert(id)
            didChange = true
        }
        guard didChange else { return }
        trimToCapacity()
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else {
            return
        }
        ordered = ids
        set = Set(ids)
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(ordered)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            NSLog("[Himem][Inbox] InboxProcessedClipIds save failed: \(error.localizedDescription)")
        }
    }

    private func trimToCapacity() {
        guard ordered.count > Self.maxCapacity else { return }
        let removeCount = ordered.count - Self.maxCapacity
        for old in ordered.prefix(removeCount) {
            set.remove(old)
        }
        ordered.removeFirst(removeCount)
    }

    #if DEBUG
    /// Test seam: clears state in memory and on disk so tests can
    /// start from a known baseline without leaking between cases.
    func debugResetForTesting() {
        ordered = []
        set = []
        try? FileManager.default.removeItem(at: storageURL)
    }
    #endif
}
