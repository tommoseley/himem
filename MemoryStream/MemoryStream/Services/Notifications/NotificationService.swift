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
        static let notifyInboxArrival = "notifyInboxArrival"
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
            Keys.notifyInboxArrival: false,
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

    // MARK: - Inbox arrival

    /// Called from `WatchSessionDelegate` after a clip is added to the
    /// inbox manifest. Fires a banner immediately with the live cumulative
    /// inbox count. Each call uses the same identifier — UNN updates the
    /// existing banner in place AND alerts again (because `.active`
    /// interruption + sound), so a second clip pings as loudly as the first
    /// while Notification Center stays at one row reflecting the latest
    /// total.
    ///
    /// No Swift `Task.sleep` debounce — that gets killed when the process
    /// suspends (typical when iPhone is locked and only briefly woken to
    /// handle WC delivery). The completion-handler form of `add` returns
    /// fast enough that the request reaches UNN before suspension can
    /// drop it.
    func notifyInboxArrival() {
        guard UserDefaults.standard.bool(forKey: Keys.notifyInboxArrival) else {
            NSLog("[Himem][Notify] inbox-arrival toggle off, skipping")
            return
        }

        let inboxCount = InboxManifest.shared.count
        guard inboxCount > 0 else {
            NSLog("[Himem][Notify] inbox empty, skipping")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Hi Mem"
        content.body = inboxCount == 1
            ? "1 voice clip ready to organize"
            : "\(inboxCount) voice clips ready to organize"
        content.categoryIdentifier = Category.inboxArrival.rawValue
        content.interruptionLevel = .active
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Identifiers.inboxArrival,
            content: content,
            trigger: nil // deliver immediately
        )

        // Remove any prior delivered notification with this identifier
        // before re-adding. iOS throttles the alert tone on same-identifier
        // updates that look like in-place edits — clearing first forces
        // each fire to register as a fresh delivery so the buzz/sound
        // reliably plays for every count increment.
        center.removeDeliveredNotifications(withIdentifiers: [Identifiers.inboxArrival])
        center.add(request) { error in
            if let error {
                NSLog("[Himem][Notify] schedule failed: \(error.localizedDescription)")
            } else {
                NSLog("[Himem][Notify] inbox-arrival fired, count=\(inboxCount)")
            }
        }
    }

    // MARK: - Daily nudge

    /// Called from app-active / scenePhase observers and from
    /// EntryLifecycleService save paths. Cancels today's pending nudge if
    /// `hadEntryToday` is true (or if the nudge toggle is off), otherwise
    /// schedules today's nudge for the user's chosen time — provided that
    /// time hasn't already passed today.
    func refreshDailyNudge(hadEntryToday: Bool) async {
        let id = todayNudgeIdentifier()
        center.removePendingNotificationRequests(withIdentifiers: [id])

        guard UserDefaults.standard.bool(forKey: Keys.notifyDailyNudge) else { return }
        guard !hadEntryToday else { return }

        let nudgeMinute = UserDefaults.standard.integer(forKey: Keys.nudgeTimeMinutes)
        let hour = nudgeMinute / 60
        let minute = nudgeMinute % 60

        let now = Date()
        let cal = Calendar.current
        guard
            let nudgeDate = cal.date(bySettingHour: hour, minute: minute, second: 0, of: now),
            nudgeDate > now
        else {
            // Time already passed today — no reschedule. Tomorrow's nudge will
            // be scheduled the next time refresh is called (next app activate).
            return
        }

        let components = cal.dateComponents([.year, .month, .day, .hour, .minute], from: nudgeDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let content = UNMutableNotificationContent()
        content.title = "Hi Mem"
        content.body = "Anything to remember from today?"
        content.sound = .default
        content.categoryIdentifier = Category.dailyNudge.rawValue

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
    }

    private func todayNudgeIdentifier() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return Identifiers.nudgePrefix + f.string(from: Date())
    }
}
