import Testing
import Foundation
import UIKit
@testable import HiMem

/// Money tests for `BurstThumbnailPrefetcher` — Slice 6's substantive
/// fix for R2's burst-thumbnail-storm flag (task #148 territory).
///
/// The prefetcher's contract:
///   1. Returns a `[UUID: UIImage]` map keyed by caller-supplied id.
///   2. Bounded concurrency — never more than `maxConcurrent` live
///      loads at once (R2-recommended default 3).
///   3. Dedupes by `osIdentifier` — two atoms in a strip pointing at
///      the same source share one disk hit (edge case, but free
///      to guarantee).
@Suite(.serialized)
struct BurstThumbnailPrefetcherTests {

    // MARK: - Fixtures

    private func input(_ osId: String) -> BurstThumbnailPrefetcher.PrefetchInput {
        BurstThumbnailPrefetcher.PrefetchInput(
            id: UUID(),
            thumbnailKey: ClipDisplayModel.ThumbnailKey(osIdentifier: osId, mediaType: .image)
        )
    }

    private func makeImage() -> UIImage {
        UIGraphicsBeginImageContext(CGSize(width: 1, height: 1))
        let img = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return img
    }

    // MARK: - Contract

    /// Empty input → empty result. No task-group spin.
    @Test func empty_input_returns_empty() async {
        let service = CountingMockService(image: makeImage())
        let out = await BurstThumbnailPrefetcher.prefetch(keys: [], service: service)
        #expect(out.isEmpty)
        #expect(service.cacheCallCount == 0)
    }

    /// Given N distinct osIdentifiers, each is loaded exactly once
    /// and every id in the output map corresponds to a caller input.
    @Test func distinct_keys_load_once_each_and_return_map() async {
        let service = CountingMockService(image: makeImage())
        let inputs = (0..<5).map { input("photo-\($0).jpg") }
        let out = await BurstThumbnailPrefetcher.prefetch(keys: inputs, service: service)
        #expect(service.cacheCallCount == 5, "5 distinct keys → 5 loads")
        #expect(out.count == 5, "each input should have a result entry")
        for input in inputs {
            #expect(out[input.id] != nil, "id \(input.id) should be in the result map")
        }
    }

    /// Duplicate osIdentifiers dedupe to one load, but both caller
    /// ids appear in the output map (fan-back-out). Guards the
    /// same-source-two-atoms edge case.
    @Test func duplicate_osIdentifiers_dedupe_but_both_ids_return_image() async {
        let service = CountingMockService(image: makeImage())
        let shared = ClipDisplayModel.ThumbnailKey(osIdentifier: "shared.jpg", mediaType: .image)
        let inputA = BurstThumbnailPrefetcher.PrefetchInput(id: UUID(), thumbnailKey: shared)
        let inputB = BurstThumbnailPrefetcher.PrefetchInput(id: UUID(), thumbnailKey: shared)
        let out = await BurstThumbnailPrefetcher.prefetch(keys: [inputA, inputB], service: service)
        #expect(service.cacheCallCount == 1, "shared osIdentifier → 1 load, dedup works")
        #expect(out[inputA.id] != nil)
        #expect(out[inputB.id] != nil, "the second atom pointing at the same source still gets the image")
    }

    /// Bounded concurrency: at no point are more than `maxConcurrent`
    /// live loads in flight simultaneously. Uses a counting mock
    /// that tracks peak concurrent calls.
    @Test func bounded_concurrency_never_exceeds_cap() async {
        let service = ConcurrencyTrackingMockService(image: makeImage(), delayNs: 50_000_000)
        let inputs = (0..<10).map { input("photo-\($0).jpg") }
        _ = await BurstThumbnailPrefetcher.prefetch(keys: inputs, maxConcurrent: 3, service: service)
        #expect(service.peakConcurrent <= 3, "peak concurrent loads must not exceed cap; saw \(service.peakConcurrent)")
        #expect(service.cacheCallCount == 10, "all 10 keys still get loaded")
    }

    /// A `maxConcurrent` of 1 serialises the loads — proves the
    /// gating math works at the boundary.
    @Test func maxConcurrent_one_serialises() async {
        let service = ConcurrencyTrackingMockService(image: makeImage(), delayNs: 10_000_000)
        let inputs = (0..<4).map { input("p-\($0).jpg") }
        _ = await BurstThumbnailPrefetcher.prefetch(keys: inputs, maxConcurrent: 1, service: service)
        #expect(service.peakConcurrent == 1)
    }

    /// A failed load (returns nil filename) doesn't wedge the map.
    @Test func failed_load_omits_id_from_map() async {
        let service = FailingMockService()
        let inputs = (0..<3).map { input("p-\($0).jpg") }
        let out = await BurstThumbnailPrefetcher.prefetch(keys: inputs, service: service)
        #expect(out.isEmpty, "all failures → empty map")
        #expect(service.cacheCallCount == 3, "still tries each key")
    }
}

// MARK: - Mocks

/// Base counting mock — records call counts, returns a fixed image.
private final class CountingMockService: ThumbnailFetching, @unchecked Sendable {
    let image: UIImage
    private var _count = 0
    private let lock = NSLock()
    var cacheCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _count
    }
    init(image: UIImage) { self.image = image }
    func cacheThumbnail(for localIdentifier: String, mediaType: MediaReference.MediaType) async -> String? {
        lock.lock(); _count += 1; lock.unlock()
        return localIdentifier
    }
    func cachedThumbnail(filename: String) -> UIImage? { image }
}

/// Tracks the peak number of simultaneous in-flight calls.
private final class ConcurrencyTrackingMockService: ThumbnailFetching, @unchecked Sendable {
    let image: UIImage
    let delayNs: UInt64
    private var _live = 0
    private var _peak = 0
    private var _count = 0
    private let lock = NSLock()
    var peakConcurrent: Int {
        lock.lock(); defer { lock.unlock() }
        return _peak
    }
    var cacheCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _count
    }
    init(image: UIImage, delayNs: UInt64) {
        self.image = image
        self.delayNs = delayNs
    }
    func cacheThumbnail(for localIdentifier: String, mediaType: MediaReference.MediaType) async -> String? {
        lock.lock()
        _live += 1
        _peak = max(_peak, _live)
        _count += 1
        lock.unlock()
        try? await Task.sleep(nanoseconds: delayNs)
        lock.lock()
        _live -= 1
        lock.unlock()
        return localIdentifier
    }
    func cachedThumbnail(filename: String) -> UIImage? { image }
}

/// Every load fails (returns nil).
private final class FailingMockService: ThumbnailFetching, @unchecked Sendable {
    private var _count = 0
    private let lock = NSLock()
    var cacheCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _count
    }
    func cacheThumbnail(for localIdentifier: String, mediaType: MediaReference.MediaType) async -> String? {
        lock.lock(); _count += 1; lock.unlock()
        return nil
    }
    func cachedThumbnail(filename: String) -> UIImage? { nil }
}
