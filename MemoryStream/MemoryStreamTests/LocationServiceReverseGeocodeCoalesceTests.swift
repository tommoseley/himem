import Testing
import Foundation
import CoreLocation
@testable import HiMem

/// Money test for the Captured-Clips-import location bug Tom observed
/// 2026-07-06: a batch of 20+ watch clips imported after weeks of
/// deferred sorting rendered only *one* clip with a placeName; the
/// other 19 fell back to date + time only.
///
/// Root cause: `ClipLocationResolver.stamp` fires a fire-and-forget
/// `Task { await LocationService.shared.reverseGeocode(location) }`
/// per clip. When 20 clips are stamped in the batch-commit's per-clip
/// loop, 20 concurrent tasks hit Apple's `CLGeocoder` at once. Apple
/// has an undocumented cross-instance rate limiter that drops most
/// of them (returns a `.network` error) — only the first one or two
/// succeed. The stamped placeName lands on that first ref; the other
/// 19 refs keep `placeName == nil`.
///
/// Fix: `LocationService.reverseGeocode` now (a) caches resolved
/// names by ~100m coordinate bucket and (b) coalesces concurrent
/// callers for the same bucket onto a single in-flight `Task`. So
/// 20 clips at one dinner produce exactly *one* geocode invocation
/// and all 20 refs get the same placeName.
///
/// This test uses `LocationService(resolver:)` — the test seam that
/// injects a call-counting stub in place of the real CLGeocoder path
/// — to verify the coalesce behavior deterministically without
/// depending on Apple's throttler timing.
@MainActor
struct LocationServiceReverseGeocodeCoalesceTests {

    private actor CallCounter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    /// The money assertion. Twenty concurrent `reverseGeocode` calls
    /// at the same coordinate should trigger the injected resolver
    /// exactly once, and every caller must receive the resolved name.
    @Test func concurrentCallsAtSameCoord_coalesceToSingleResolverInvocation() async {
        let counter = CallCounter()
        let service = LocationService(resolver: { _ in
            await counter.increment()
            // Simulate real geocode latency so all 20 callers arrive
            // while the first task is still in flight — otherwise the
            // test could pass via the cache path alone, not the
            // in-flight coalesce path.
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            return "Bluffton, SC"
        })

        // 20 clips captured "at dinner" all share the same coord.
        let dinner = CLLocation(latitude: 32.2340, longitude: -80.8760)

        let results: [String?] = await withTaskGroup(of: String?.self) { group in
            for _ in 0..<20 {
                group.addTask { await service.reverseGeocode(dinner) }
            }
            var out: [String?] = []
            for await value in group { out.append(value) }
            return out
        }

        #expect(results.count == 20)
        #expect(results.allSatisfy { $0 == "Bluffton, SC" },
                "All 20 callers should receive the resolved place name")

        let calls = await counter.count
        #expect(calls == 1,
                "20 concurrent calls at the same bucket must trigger exactly 1 resolver invocation; got \(calls). If this fails the CLGeocoder throttle bug is back.")
    }

    /// Cache hit path — a later call after the first has resolved
    /// should return the cached value without invoking the resolver
    /// again.
    @Test func secondCall_afterFirstResolves_hitsCacheNotResolver() async {
        let counter = CallCounter()
        let service = LocationService(resolver: { _ in
            await counter.increment()
            return "Bluffton, SC"
        })
        let loc = CLLocation(latitude: 32.2340, longitude: -80.8760)

        let first = await service.reverseGeocode(loc)
        let second = await service.reverseGeocode(loc)

        #expect(first == "Bluffton, SC")
        #expect(second == "Bluffton, SC")
        let calls = await counter.count
        #expect(calls == 1, "Second call should hit the cache; got \(calls) resolver invocations")
    }

    /// Distinct coordinates still fire separately — the coalesce is
    /// per-bucket, not global.
    @Test func distinctCoords_fireSeparateResolverInvocations() async {
        let counter = CallCounter()
        let service = LocationService(resolver: { location in
            await counter.increment()
            return "\(location.coordinate.latitude),\(location.coordinate.longitude)"
        })

        let a = CLLocation(latitude: 32.2340, longitude: -80.8760)
        let b = CLLocation(latitude: 40.7128, longitude: -74.0060)  // NYC
        let c = CLLocation(latitude: 34.0522, longitude: -118.2437) // LA

        _ = await service.reverseGeocode(a)
        _ = await service.reverseGeocode(b)
        _ = await service.reverseGeocode(c)

        let calls = await counter.count
        #expect(calls == 3, "Three distinct coordinates should fire three separate invocations")
    }

    /// Nearby coordinates within the ~100m bucket collapse to one
    /// key — a real session's minor GPS drift shouldn't fragment
    /// the cache.
    @Test func nearbyCoords_within100mBucket_shareCacheKey() {
        let a = CLLocation(latitude: 32.23400, longitude: -80.87600)
        let b = CLLocation(latitude: 32.23401, longitude: -80.87599)  // ~1m off — same bucket
        let c = CLLocation(latitude: 32.23500, longitude: -80.87600)  // ~110m off — different bucket

        #expect(LocationService.cacheKey(for: a) == LocationService.cacheKey(for: b))
        #expect(LocationService.cacheKey(for: a) != LocationService.cacheKey(for: c))
    }
}
