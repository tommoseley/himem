import Foundation

/// Mirrors the Left-Handed FAB preference (`fabHandednessLeft`) between
/// `UserDefaults` — the SwiftUI-facing store every `@AppStorage` site reads —
/// and iCloud `NSUbiquitousKeyValueStore`, so the choice follows the person
/// across devices (phone → iPad).
///
/// - **No CloudKit schema change.** KVS is a separate ~1 MB iCloud key-value
///   bag; the `com.apple.developer.ubiquity-kvstore-identifier` entitlement is
///   already present (it backs `AuthService`'s userName sidecar).
/// - **UserDefaults stays authoritative for local reads** (offline / first
///   launch). KVS only feeds cross-device updates in and pushes local changes
///   out. All five `@AppStorage("fabHandednessLeft")` view sites are untouched
///   — writing the key into `UserDefaults` is what invalidates them.
/// - **Value-compare on both directions breaks the echo loop:** once local and
///   remote agree, neither observer writes again.
final class FABHandednessSync: NSObject {
    static let shared = FABHandednessSync()

    private let key = FABHandedness.storageKey
    private let defaults = UserDefaults.standard
    private let kv = NSUbiquitousKeyValueStore.default
    private var kvoContext = 0

    private override init() { super.init() }

    /// What a reconcile decides to write, and where. `nil` = leave that store
    /// alone. Pure value type so the decision is unit-testable without iCloud.
    struct Plan: Equatable {
        var writeLocal: Bool?  // → UserDefaults (fires @AppStorage)
        var writeRemote: Bool? // → NSUbiquitousKeyValueStore
    }

    /// The reconcile decision, isolated from the stores so it can be tested
    /// against the full truth table. iCloud is the cross-device truth, so on a
    /// present-and-differing remote it wins (the common case: "I set it on my
    /// other device"); a value that exists only locally is pushed up.
    static func reconcile(localExists: Bool, localValue: Bool,
                          remoteExists: Bool, remoteValue: Bool) -> Plan {
        switch (localExists, remoteExists) {
        case (_, true):
            // Remote is the synced truth. Adopt it locally when we differ (or
            // have nothing); never write remote here — it's already right.
            return (localExists && localValue == remoteValue)
                ? Plan(writeLocal: nil, writeRemote: nil)
                : Plan(writeLocal: remoteValue, writeRemote: nil)
        case (true, false):
            // A local-only value — push it up so other devices adopt it.
            return Plan(writeLocal: nil, writeRemote: localValue)
        case (false, false):
            // Neither store has a value — leave the app default in place.
            return Plan(writeLocal: nil, writeRemote: nil)
        }
    }

    /// Call once at launch (`MemoryStreamApp.init`). Seeds before observing so
    /// the seed write can't spuriously re-trigger the outbound observer.
    func start() {
        guard !StorageService.isRunningTests else { return }
        kv.synchronize()
        let plan = Self.reconcile(
            localExists: defaults.object(forKey: key) != nil,
            localValue: defaults.bool(forKey: key),
            remoteExists: kv.object(forKey: key) != nil,
            remoteValue: kv.bool(forKey: key)
        )
        if let local = plan.writeLocal { defaults.set(local, forKey: key) }
        if let remote = plan.writeRemote { kv.set(remote, forKey: key); kv.synchronize() }

        NotificationCenter.default.addObserver(
            self, selector: #selector(iCloudChangedExternally(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: kv)
        defaults.addObserver(self, forKeyPath: key, options: [], context: &kvoContext)
    }

    /// Another device changed the pref → mirror iCloud into UserDefaults so the
    /// `@AppStorage` readers update. Value-compare so an unchanged notification
    /// (or one this device just caused) is a no-op.
    @objc private func iCloudChangedExternally(_ note: Notification) {
        guard kv.object(forKey: key) != nil else { return }
        let remote = kv.bool(forKey: key)
        if defaults.bool(forKey: key) != remote {
            defaults.set(remote, forKey: key)
        }
    }

    /// Local write (the Settings toggle) → push to iCloud. Value-compare breaks
    /// the loop: the inbound mirror above sets UserDefaults, which fires this,
    /// but by then local == remote so nothing is written back.
    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {
        guard context == &kvoContext, keyPath == key else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        let local = defaults.bool(forKey: key)
        if kv.object(forKey: key) == nil || kv.bool(forKey: key) != local {
            kv.set(local, forKey: key)
            kv.synchronize()
        }
    }
}
