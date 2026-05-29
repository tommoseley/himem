import Testing
import Foundation
@testable import HiMem

/// Money tests for `InboxProcessedClipIds` — the persistent dedup
/// set that closes B5 (iOS WC delivery queue ghost-redelivering
/// clips the user already disposed of).
///
/// Five invariants:
///   1. `markProcessed` makes `contains` return true (basic)
///   2. State survives load — a fresh instance pointing at the same
///      URL sees the prior writes (durability across launches is the
///      whole point)
///   3. Marking the same id twice doesn't grow the set (idempotent)
///   4. Past `maxCapacity` the oldest entries drop off (bounded
///      storage, no unbounded growth)
///   5. Batch `markProcessed` is equivalent to N single-call markings
///      (used by `removeBatch` when promoting a session)
@MainActor
@Suite(.serialized)
struct InboxProcessedClipIdsTests {

    private func makeStore() -> (InboxProcessedClipIds, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("processed-\(UUID().uuidString).json")
        return (InboxProcessedClipIds(storageURL: url), url)
    }

    @Test func markProcessed_makesContainsTrue() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let id = UUID()
        #expect(store.contains(id) == false)
        store.markProcessed(id)
        #expect(store.contains(id) == true)
    }

    /// THE BUG-FIX MONEY TEST. After the user disposes of a clip
    /// (mark → write to disk), a fresh `InboxProcessedClipIds`
    /// instance loading from the same URL — i.e., the phone after
    /// a relaunch — must still recognize the clipId as processed.
    /// Without this, the dedup forgets across launches and iOS's
    /// WC redelivery queue successfully ghost-files the clip on
    /// the next cold boot.
    @Test func markProcessed_survivesReloadFromDisk() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("processed-survive-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let id = UUID()
        do {
            let first = InboxProcessedClipIds(storageURL: url)
            first.markProcessed(id)
            #expect(first.contains(id) == true)
        }
        let second = InboxProcessedClipIds(storageURL: url)
        #expect(second.contains(id) == true, "B5 dedup must persist across launches")
    }

    @Test func markProcessed_isIdempotent() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let id = UUID()
        store.markProcessed(id)
        store.markProcessed(id)
        store.markProcessed(id)
        #expect(store.count == 1)
    }

    @Test func markProcessed_pastCap_dropsOldestEntries() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        // Build a set just over the cap. The first N - maxCapacity
        // entries should be evicted; the rest survive.
        let ids = (0..<(InboxProcessedClipIds.maxCapacity + 10)).map { _ in UUID() }
        for id in ids {
            store.markProcessed(id)
        }
        #expect(store.count == InboxProcessedClipIds.maxCapacity, "Bounded storage cap not enforced")
        // The first 10 ids should have been evicted.
        for old in ids.prefix(10) {
            #expect(store.contains(old) == false, "Oldest entry \(old) should have evicted")
        }
        // The rest survive.
        for survivor in ids.suffix(InboxProcessedClipIds.maxCapacity) {
            #expect(store.contains(survivor) == true, "Recent entry \(survivor) should have survived")
        }
    }

    @Test func batchMarkProcessed_equivalentToSequentialSingles() {
        let (single, urlA) = makeStore()
        let (batch, urlB) = makeStore()
        defer {
            try? FileManager.default.removeItem(at: urlA)
            try? FileManager.default.removeItem(at: urlB)
        }
        let ids = (0..<10).map { _ in UUID() }
        for id in ids { single.markProcessed(id) }
        batch.markProcessed(ids)
        #expect(single.count == batch.count)
        for id in ids {
            #expect(single.contains(id) == batch.contains(id))
        }
    }

    /// Locks the integration: when `InboxManifest.remove(clipId:)`
    /// fires for a clip in the live inbox, the shared
    /// `InboxProcessedClipIds.shared` instance receives the mark.
    /// This is the wiring that makes the WC-arrival dedup actually
    /// kick in for clips the user just deleted.
    @Test func inboxManifestRemove_marksClipIdAsProcessed() throws {
        // Use the shared singleton — the production wiring goes
        // through it. Reset to a known baseline first.
        #if DEBUG
        InboxProcessedClipIds.shared.debugResetForTesting()
        #endif

        let clip = InboxClip(
            clipId: UUID(),
            capturedAt: Date(),
            duration: 5,
            transcript: "",
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: "test-\(UUID().uuidString).caf"
        )
        InboxManifest.shared.acceptClip(clip)
        InboxManifest.shared.remove(clipId: clip.clipId)

        #expect(InboxProcessedClipIds.shared.contains(clip.clipId) == true,
                "InboxManifest.remove must persist the disposal via InboxProcessedClipIds")
    }

    @Test func inboxManifestRemoveBatch_marksAllClipIdsAsProcessed() throws {
        #if DEBUG
        InboxProcessedClipIds.shared.debugResetForTesting()
        #endif

        let clips = (0..<3).map { _ in
            InboxClip(
                clipId: UUID(),
                capturedAt: Date(),
                duration: 5,
                transcript: "",
                latitude: nil,
                longitude: nil,
                source: "watch",
                audioFilename: "test-\(UUID().uuidString).caf"
            )
        }
        for c in clips { InboxManifest.shared.acceptClip(c) }
        InboxManifest.shared.removeBatch(clipIds: clips.map(\.clipId))

        for c in clips {
            #expect(InboxProcessedClipIds.shared.contains(c.clipId) == true,
                    "removeBatch must mark every clipId as processed")
        }
    }
}
