import Foundation
import UserNotifications

/// Local notifications for HiMem. Two surfaces:
/// 1. **Inbox arrival** — when a watch-recorded clip lands in the iPhone's
///    inbox manifest, fire an alerting banner immediately with the live
///    inbox count in the body ("3 voice clips ready to organize"). One
///    ping per arrival, same UNN identifier each time so the existing
///    banner updates rather than stacking. Fires synchronously on the
///    delegate's call thread — no Swift `Task.sleep` debounce — so the
///    OS receives the request before the process suspends (key when the
///    iPhone is locked and only briefly woken to handle WC delivery).
/// 2. **Daily nudge** — at the user's chosen time, prompt if no entry has
///    been created that day. Re-evaluated on app activation and on every
///    entry save so the nudge cancels itself once you've captured something.
///
/// No APNs / no server. All scheduling is local via UNN. Permission is
/// requested lazily — first time the user toggles either setting on.
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    /// UserDefaults keys, mirrored by `@AppStorage` in SettingsView.
    enum Keys {
        static let notifyDailyNudge = "notifyDailyNudge"
        /// Minutes since midnight (0..1439). Default 1200 = 8:00pm.
        static let nudgeTimeMinutes = "nudgeTimeMinutes"
    }

    /// UNN identifier prefix for the per-day nudge — full id is
    /// `nudge-yyyy-mm-dd`. Stable per day so we can cancel today's without
    /// touching tomorrow's.
    private enum Identifiers {
        static let inboxArrival = "inbox-arrival"
        static let nudgePrefix = "nudge-"
    }

    /// Notification category identifiers — used by the UNN delegate to route
    /// taps to the right surface (Inbox vs root composer).
    enum Category: String {
        case inboxArrival = "inbox_arrival"
        case dailyNudge = "daily_nudge"
    }

    /// Posted when the user taps an inbox-arrival notification. Observed by
    /// the journal view to surface the inbox sheet.
    static let openInboxNotification = Notification.Name("HiMem.openInbox")

    /// Posted when the user taps a daily-nudge notification. Observed by the
    /// journal view to ensure the feed is foreground.
    static let dailyNudgeTappedNotification = Notification.Name("HiMem.dailyNudgeTapped")

    private let center = UNUserNotificationCenter.current()

    private init() {}

    // MARK: - Bootstrap

    /// Registers default UserDefaults values so first-run reads return our
    /// chosen defaults (toggles off, nudge time = 8pm) rather than zero/false.
    /// Call once at app launch.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.notifyDailyNudge: false,
            Keys.nudgeTimeMinutes: 1200, // 20:00 local
        ])
    }

    // MARK: - Permission

    /// Returns true if the user has authorized banners/sounds. Requests
    /// permission only when authorization is `.notDetermined` — repeated calls
    /// after a denial don't re-prompt (iOS would no-op anyway).
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

    // MARK: - Daily nudge

    /// Called from app-active / scenePhase observers and from
    /// EntryLifecycleService save paths. Cancels today's pending
    /// nudge if the toggle is off OR the user captured anything
    /// inside the chosen-time rollover window ending now; otherwise
    /// schedules the next nudge fire at the next chosen-time tick
    /// (today if it hasn't passed yet, tomorrow if it has).
    ///
    /// `lastCaptureAt` is the createdAt of the most recent
    /// non-recycled JournalEntry (see `StorageService
    /// .mostRecentEntryAt`); pass `nil` if no entries exist (first
    /// launch). Rollover semantics live in `DailyNudgePolicy
    /// .nextFireDate` — see its docstring for the chosen-time
    /// window definition and the midnight-rollover special case.
    ///
    /// Signature changed 2026-06-01 from `hadEntryToday: Bool`
    /// (midnight rollover) to `lastCaptureAt: Date?` (chosen-time
    /// rollover) — Tom's intent per the Settings copy: *"if you
    /// haven't captured anything by your chosen time."*
    func refreshDailyNudge(lastCaptureAt: Date?) async {
        let id = todayNudgeIdentifier()
        center.removePendingNotificationRequests(withIdentifiers: [id])

        guard UserDefaults.standard.bool(forKey: Keys.notifyDailyNudge) else { return }

        let nudgeMinutes = UserDefaults.standard.integer(forKey: Keys.nudgeTimeMinutes)
        let now = Date()
        guard let fireDate = DailyNudgePolicy.nextFireDate(
            lastCaptureAt: lastCaptureAt,
            nudgeMinutes: nudgeMinutes,
            now: now
        ) else {
            // Suppressed (capture inside window) — leave the
            // pending request canceled above and return.
            return
        }

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let content = UNMutableNotificationContent()
        content.title = "HiMem"
        content.body = "Anything to remember from today?"
        content.sound = .default
        content.categoryIdentifier = Category.dailyNudge.rawValue

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            NSLog("[Himem][Notify] daily-nudge schedule failed: \(error.localizedDescription)")
        }
    }

    private func todayNudgeIdentifier() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return Identifiers.nudgePrefix + f.string(from: Date())
    }
}
