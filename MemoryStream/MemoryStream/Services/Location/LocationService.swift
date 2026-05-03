import Foundation
import CoreLocation

/// Wraps CLLocationManager + CLGeocoder so the rest of the app can grab a
/// location for an entry without dealing with delegate callbacks. Silent on
/// denial — callers fall back to "no location" and the rest of the entry
/// flow proceeds normally.
@MainActor
final class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    private var pendingFix: CheckedContinuation<CLLocation?, Never>?
    private var fixDeadline: Task<Void, Never>?
    private var pendingAuth: CheckedContinuation<Bool, Never>?

    override init() {
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
        let placemarks: [CLPlacemark]
        do {
            placemarks = try await geocoder.reverseGeocodeLocation(location)
        } catch {
            return nil
        }
        guard let pm = placemarks.first else { return nil }
        return PlacemarkFormatter.displayName(from: pm)
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
