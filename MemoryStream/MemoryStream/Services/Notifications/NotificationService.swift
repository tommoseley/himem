import Foundation
import UserNotifications

/// The one persisted user control for Captured-Clips arrival notifications
/// (RH-1, July 20 2026). Defaults ON. Consulted by
/// `WatchInboxNotificationCoordinator` before every passive push and bound
/// to the single toggle in onboarding + Settings. Distinct from the OS
/// permission: arrivals fire only when BOTH the OS grant AND this toggle
/// are on. Before RH-1 the onboarding toggle was cosmetic (never consulted).
enum NotificationPreference {
    private static let key = "himem.notify.arrivalsEnabled"

    static var arrivalsEnabled: Bool {
        // Default ON — the onboarding toggle ships enabled and confirmed.
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// Local notifications for HiMem. One surface only:
///
/// **Inbox arrival (Channel A)** — when a watch-recorded clip lands in
/// the iPhone's inbox manifest, fire a **passive** notification with
/// the live inbox count in the body ("3 voice clips ready to organize").
/// One ping per arrival, same UNN identifier each time so the existing
/// banner updates rather than stacking. Fires synchronously on the
/// delegate's call thread — no Swift `Task.sleep` debounce — so the OS
/// receives the request before the process suspends (key when the
/// iPhone is locked and only briefly woken to handle WC delivery).
///
/// **Channel B (Daily nudge / Inactivity) is retired** (2026-07-07 per
/// `CLAUDE.md` §Notifications). Absence is a private matter; the
/// Kingfisher constitution forbids the app raising the skipped thing.
/// The channel was deleted rather than softened — off-by-default
/// opt-in was the old mitigation, but the North Star rule is
/// absolute. It also contradicted the App Store promise ("No streaks.
/// No nudges.").
///
/// No APNs / no server. All scheduling is local via UNN. Permission
/// is requested lazily — first time an arrival needs a banner slot.
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    /// UNN identifier prefix for the inbox-arrival notification.
    private enum Identifiers {
        static let inboxArrival = "inbox-arrival"
    }

    /// Notification category identifiers — used by the UNN delegate to
    /// route taps to the right surface.
    enum Category: String {
        case inboxArrival = "inbox_arrival"
    }

    /// Posted when the user taps an inbox-arrival notification.
    /// Observed by the journal view to route to the Clips tab.
    static let openInboxNotification = Notification.Name("HiMem.openInbox")

    private let center = UNUserNotificationCenter.current()

    private init() {}

    // MARK: - Permission

    /// Returns true if the user has authorized banners/sounds. Requests
    /// permission only when authorization is `.notDetermined` — repeated
    /// calls after a denial don't re-prompt (iOS would no-op anyway).
    func requestPermissionIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    /// Current authorization status — cached read for Settings UI.
    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }
}
