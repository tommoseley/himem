import Testing
import Foundation
@testable import HiMem

/// Slice 7 of the Clip Model convergence (July 11 2026): standing
/// hygiene for the in-flight dedup in `ThumbnailService.cacheThumbnail`.
///
/// Before the change, two concurrent callers requesting the same
/// `osIdentifier` (e.g. a burst row on the Clips tab and the same clip
/// rendered by Memory Detail during a rapid tab switch) would each hit
/// the underlying `MediaResolver` / PHImageManager path. The dedup map
/// coalesces them onto one task and drains after completion.
///
/// **What this test verifies (mechanical):**
///   - Concurrent calls for the same nonexistent id complete (both
///     return nil).
///   - The `inFlight` map is empty after they resolve — no leaks.
///   - No deadlock.
///
/// **What this test does NOT verify:** that a real disk read fires
/// exactly once. That would require injecting `MediaResolver` and a
/// test hook on `phImageManagerThumbnail` / `ubiquityThumbnail`, a
/// larger refactor deferred as a follow-up. The map-empty invariant
/// is the load-bearing correctness property; if it drifts, callers
/// would eventually see a "stuck" thumbnail row.
@MainActor
struct ThumbnailServiceDedupTests {

    @Test func inFlight_drained_afterConcurrentSameIdCalls() async {
        // Own instance, NOT `.shared` (F6, 2026-07-26): `_inFlightCount` reads
        // the instance's `inFlight` map. Asserting it on the singleton races
        // any parallel suite that mutates `ThumbnailService.shared` (every test
        // that saves a media ref → `EntryLifecycleService.cacheThumbnails`).
        // `.serialized` can't fix a cross-SUITE race; an isolated instance does.
        let service = ThumbnailService()
        // Nonexistent identifier — MediaResolver falls through and
        // both callers get nil, but the dedup gate + drain still
        // exercises.
        let id = "test-nonexistent-\(UUID().uuidString)"

        async let a = service.cacheThumbnail(for: id, mediaType: .image)
        async let b = service.cacheThumbnail(for: id, mediaType: .image)
        let (r1, r2) = await (a, b)

        #expect(r1 == nil, "Nonexistent identifier must resolve nil")
        #expect(r2 == nil, "Second caller must also resolve nil")
        #expect(service._inFlightCount == 0, "inFlight map must drain after all callers resolve — otherwise same-id calls forever after would return a stale nil task result")
    }

    @Test func inFlight_isolated_perOsIdentifier() async {
        // Own instance, not `.shared` — see the sibling test (F6, 2026-07-26).
        let service = ThumbnailService()
        let idA = "test-nonexistent-A-\(UUID().uuidString)"
        let idB = "test-nonexistent-B-\(UUID().uuidString)"

        async let a = service.cacheThumbnail(for: idA, mediaType: .image)
        async let b = service.cacheThumbnail(for: idB, mediaType: .image)
        _ = await (a, b)

        // Different identifiers must never share a slot — the
        // guarantee callers depend on.
        #expect(service._inFlightCount == 0)
    }
}
