import Foundation
import CoreLocation

/// Wraps CLLocationManager + CLGeocoder so the rest of the app can grab a
/// location for an entry without dealing with delegate callbacks. Silent on
/// denial — callers fall back to "no location" and the rest of the entry
/// flow proceeds normally.
@MainActor
final class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    /// Signature of the underlying reverse-geocode primitive. Default
    /// wraps `CLGeocoder.reverseGeocodeLocation`; tests inject a stub
    /// so `SortBatchCommit`'s bulk-stamp behavior can be exercised
    /// without hitting Apple's rate limiter.
    typealias Resolver = (CLLocation) async -> String?

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let resolver: Resolver?

    private var pendingFix: CheckedContinuation<CLLocation?, Never>?
    private var fixDeadline: Task<Void, Never>?
    private var pendingAuth: CheckedContinuation<Bool, Never>?

    /// Resolved-name cache keyed by ~100m coordinate bucket. Bulk
    /// imports (Sort batch commit, single-session promote) can stamp
    /// 20+ clips all at the same restaurant — with an empty cache
    /// that's 20 CLGeocoder calls in one tick, and Apple's cross-
    /// instance rate limiter drops most of them. The cache reduces
    /// same-place batches to one geocode invocation. Lives for the
    /// process lifetime; no eviction needed at these volumes.
    private var placeNameCache: [String: String] = [:]

    /// In-flight geocode tasks by bucket, so concurrent calls for
    /// the same coord coalesce onto the same task instead of racing.
    /// The cache alone is not enough — if two calls arrive before
    /// either has resolved, both would hit the resolver. Coalescing
    /// guarantees exactly one call per bucket in a batch.
    private var inflightGeocode: [String: Task<String?, Never>] = [:]

    override convenience init() {
        self.init(resolver: nil)
    }

    /// Test seam. Production callers use `LocationService.shared`
    /// (which uses the default CLGeocoder path); tests pass a stub
    /// `resolver` to exercise the cache/coalesce logic deterministically.
    init(resolver: Resolver?) {
        self.resolver = resolver
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - Authorization

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    /// Requests "When In Use" if undetermined; updates `authorizationStatus`
    /// via the delegate. Returns `true` if the user can proceed.
    @discardableResult
    func requestWhenInUseAuthorization() async -> Bool {
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        case .denied, .restricted: return false
        case .notDetermined: break
        @unknown default: return false
        }
        // Wait for the actual delegate callback rather than guessing with a
        // fixed sleep — the user takes longer than any reasonable timeout to
        // read the iOS dialog and tap Allow / Don't Allow.
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            pendingAuth?.resume(returning: false)
            pendingAuth = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    // MARK: - Current location

    /// Asks the system for a one-shot fix. Returns nil on denial, restriction,
    /// or timeout. 8s is a forgiving default — first cold fix on cellular
    /// indoors can be slow. The capture is fire-and-forget so this doesn't
    /// block the user.
    func currentLocation(timeout: TimeInterval = 8) async -> CLLocation? {
        guard isAuthorized else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<CLLocation?, Never>) in
            // If a previous request is still pending, resolve it nil and replace.
            pendingFix?.resume(returning: nil)
            fixDeadline?.cancel()
            pendingFix = continuation
            manager.requestLocation()
            fixDeadline = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard let self else { return }
                if let pending = self.pendingFix {
                    self.pendingFix = nil
                    self.fixDeadline = nil
                    pending.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Reverse geocode

    /// Resolves a coordinate to a comma-separated string of placemark
    /// components, ordered from most-specific to least-specific. The card
    /// renderer is responsible for picking how many segments to show — it
    /// drops trailing components until the result fits the available width
    /// (never mid-token truncation). The detail renderer shows the whole
    /// thing.
    ///
    /// Output shapes:
    ///   "Columbus Circle, New York"     (POI + locality)
    ///   "18 Columbus Cir, Bluffton"     (street + locality)
    ///   "Hell's Kitchen, New York"      (neighborhood + locality)
    ///   "New York, NY"                  (locality + admin)
    ///   "NY"                            (admin alone)
    ///   "United States"                 (country alone)
    func reverseGeocode(_ location: CLLocation) async -> String? {
        let key = Self.cacheKey(for: location)

        // Cache hit — return immediately, no work.
        if let cached = placeNameCache[key] { return cached }

        // Coalesce onto an in-flight task if one exists for this bucket.
        // The `await` here yields the MainActor while the existing task
        // resolves.
        if let existing = inflightGeocode[key] {
            return await existing.value
        }

        // Miss + no in-flight — start the resolver, register it as in-flight
        // so any concurrent callers coalesce, then unregister and populate
        // the cache on completion.
        let task = Task { [resolver, geocoder] () -> String? in
            if let resolver {
                return await resolver(location)
            }
            let placemarks: [CLPlacemark]
            do {
                placemarks = try await geocoder.reverseGeocodeLocation(location)
            } catch {
                return nil
            }
            guard let pm = placemarks.first else { return nil }
            return PlacemarkFormatter.displayName(from: pm)
        }
        inflightGeocode[key] = task
        let result = await task.value
        inflightGeocode[key] = nil
        if let result { placeNameCache[key] = result }
        return result
    }

    /// ~100m coordinate bucket. `0.001` degrees is about 111m at the
    /// equator (less at higher latitudes) — small enough that two clips
    /// captured "at the same place" always hash together, large enough
    /// that GPS drift doesn't fragment a real session.
    nonisolated static func cacheKey(for location: CLLocation) -> String {
        let lat = (location.coordinate.latitude * 1000).rounded() / 1000
        let lon = (location.coordinate.longitude * 1000).rounded() / 1000
        return "\(lat),\(lon)"
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            // If a request was awaiting the user's choice, resume it now.
            // Stay parked on .notDetermined — the prompt hasn't been answered.
            if let pending = self.pendingAuth, status != .notDetermined {
                self.pendingAuth = nil
                let granted = (status == .authorizedWhenInUse || status == .authorizedAlways)
                pending.resume(returning: granted)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last else { return }
        Task { @MainActor in
            self.fixDeadline?.cancel()
            self.fixDeadline = nil
            if let pending = self.pendingFix {
                self.pendingFix = nil
                pending.resume(returning: fix)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.fixDeadline?.cancel()
            self.fixDeadline = nil
            if let pending = self.pendingFix {
                self.pendingFix = nil
                pending.resume(returning: nil)
            }
        }
    }
}
