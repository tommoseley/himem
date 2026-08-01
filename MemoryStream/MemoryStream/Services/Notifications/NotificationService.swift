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

/// Notification **permission and tap-routing identity** for HiMem.
///
/// **This class does not fire anything.** It has exactly two methods —
/// `requestPermissionIfNeeded()` and `authorizationStatus()` — plus the
/// category the app delegate matches on when routing a tap. Channel A's
/// firing lives entirely in `WatchInboxNotificationCoordinator.postPassive`.
/// Corrected 2026-07-31: this doc described the fire path in detail as though
/// it were implemented here, and two of its specifics were wrong.
///
/// **Channel A, as actually implemented** (owner:
/// `WatchInboxNotificationCoordinator`) — when a clip lands in the inbox
/// manifest, post a **passive** notification (`interruptionLevel = .passive`,
/// no sound, `badge = nil` per `CLAUDE.md` §Phone) whose body reads
/// *"There are new clips you can review"* or *"N voice clips waiting"*. One
/// at a time: a single stable identifier, with the prior delivered/pending
/// request explicitly removed before the new one is added, so the banner
/// updates rather than stacks.
///   - The body string this doc used to quote — "3 voice clips ready to
///     organize" — exists nowhere in the codebase.
///   - Permission is NOT requested lazily on first arrival. It is requested
///     from onboarding (`MemoryStreamApp:389`) and Settings
///     (`SettingsView:862`).
///
/// `Identifiers.inboxArrival` below has no readers — the coordinator uses its
/// own request id. Dead; left in place rather than removed in a comment-only
/// pass, and flagged.
///
/// **Channel B (Daily nudge / Inactivity) is retired** (2026-07-07 per
/// `CLAUDE.md` §Notifications). Absence is a private matter; the
/// Kingfisher constitution forbids the app raising the skipped thing.
/// The channel was deleted rather than softened — off-by-default
/// opt-in was the old mitigation, but the North Star rule is
/// absolute. It also contradicted the App Store promise ("No streaks.
/// No nudges.").
///
/// No APNs / no server. All scheduling is local via UNN.
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    /// DEAD (verified 2026-07-31): no readers. The live arrival notification
    /// is identified by `WatchInboxNotificationCoordinator.inboxRequestId`.
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
