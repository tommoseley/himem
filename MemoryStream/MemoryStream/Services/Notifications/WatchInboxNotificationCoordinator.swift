import Foundation
import UserNotifications
import UIKit

/// Pure decision for the Captured-Clips arrival push (RH-1, July 20 2026).
/// Lives outside the coordinator so it can be tested without UIKit /
/// `UNUserNotificationCenter`. The coordinator supplies runtime values.
///
/// **Passive-only, one channel** per `docs/design/CLAUDE.md` §Notifications:
/// there is exactly one Captured-Clips notification class and it never
/// interrupts. The active burst / inbox-threshold / stale classes were
/// **deleted** (RH-1) — a stale-clip buzz is "the app raising the skipped
/// thing," forbidden by `Kingfisher · North Star.md` and the App Store
/// "no nudges" promise.
enum PassiveArrivalPush {
    enum Outcome: Equatable {
        /// Post immediately (trigger nil).
        case fireNow
        /// In quiet hours — defer to the next 7 AM so it lands once, silently,
        /// in the morning with current state.
        case deferToMorning
        case suppressed(reason: SuppressionReason)
    }

    enum SuppressionReason: String, Equatable {
        case disabled     // the user turned Captured-Clips arrivals off
        case foreground   // app is active; the in-app dot does the work
        case snoozed
        case muted
    }

    /// Quiet hours 10 PM – 7 AM local (`CLAUDE.md` §Notifications):
    /// first-of-stretch defers to 7 AM.
    static let quietHoursStart = 22
    static let quietHoursEnd = 7

    static func decide(
        enabled: Bool,
        isAppForeground: Bool,
        snoozedUntil: Date?,
        mutedUntil: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> Outcome {
        if !enabled { return .suppressed(reason: .disabled) }
        if isAppForeground { return .suppressed(reason: .foreground) }
        if let s = snoozedUntil, s > now { return .suppressed(reason: .snoozed) }
        if let m = mutedUntil, m > now { return .suppressed(reason: .muted) }
        let hour = calendar.component(.hour, from: now)
        if hour >= quietHoursStart || hour < quietHoursEnd { return .deferToMorning }
        return .fireNow
    }
}

/// Notification policy for Captured-Clips arrivals — **one passive channel**
/// (`docs/design/CLAUDE.md` §Notifications, Channel A). Every arrival, when
/// the app isn't foreground and the user hasn't disabled / snoozed / muted,
/// posts a single silent `.passive` notification (no sound, no numeric
/// badge) that lands in Notification Center / on the lock screen without
/// waking the device. In quiet hours (10 PM–7 AM) it defers to 7 AM.
/// Subsequent arrivals replace the one pending/delivered notification in
/// place with the current count.
///
/// Snooze 4h + Mute-for-today inline actions ride the
/// `watch_inbox_arrival` category; their state persists in the `wic.*`
/// UserDefaults keyspace.
@MainActor
final class WatchInboxNotificationCoordinator {
    static let shared = WatchInboxNotificationCoordinator()

    // MARK: - Identifiers

    static let categoryIdentifier = "watch_inbox_arrival"
    static let actionSnooze4hIdentifier = "snooze_4h"
    static let actionMuteTodayIdentifier = "mute_today"

    /// One stable identifier so iOS replaces the prior notification rather
    /// than stacking (Channel A: "one pending notification at a time").
    static let inboxRequestId = "watch_inbox_arrival"
    /// Legacy identifiers from the retired active/stale classes — still
    /// cleared on inbox-empty so a pre-RH-1 delivered notification can't
    /// linger.
    private static let legacyRequestIds = ["watch_inbox_stale", "watch_inbox_single"]

    // MARK: - Persisted state

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let snoozedUntil = "wic.snoozedUntil"
        static let mutedUntil = "wic.mutedUntil"
    }

    private init() {}

    /// Register the notification category + inline actions. Call once at launch.
    func registerCategories() {
        let snooze = UNNotificationAction(identifier: Self.actionSnooze4hIdentifier, title: "Snooze 4h", options: [])
        let mute = UNNotificationAction(identifier: Self.actionMuteTodayIdentifier, title: "Mute for today", options: [])
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [snooze, mute],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Lifecycle hooks

    /// Called from `WatchSessionDelegate.didReceive(file:)` after the clip is
    /// added to `InboxManifest`. Posts (or defers) the single passive push.
    func clipArrived(clipId: UUID, capturedAt: Date) {
        firePassiveArrival(now: Date())
    }

    /// Called when a clip leaves the inbox. Clears the notification when the
    /// inbox becomes empty (the spec: it disappears when the user clears).
    func clipRemoved(clipId: UUID) {
        guard InboxManifest.shared.count == 0 else { return }
        let center = UNUserNotificationCenter.current()
        let ids = [Self.inboxRequestId] + Self.legacyRequestIds
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// Inline action handler — Snooze 4h / Mute-for-today.
    func handleAction(identifier: String) {
        switch identifier {
        case Self.actionSnooze4hIdentifier:
            let until = Date().addingTimeInterval(4 * 3600)
            snoozedUntil = until
            NSLog("[HiMem][Notify] snoozed for 4h until \(until)")
        case Self.actionMuteTodayIdentifier:
            let until = endOfTodayLocal(from: Date())
            mutedUntil = until
            NSLog("[HiMem][Notify] muted until midnight local \(until)")
        default:
            break
        }
    }

    // MARK: - The passive push

    private func firePassiveArrival(now: Date) {
        let outcome = PassiveArrivalPush.decide(
            enabled: NotificationPreference.arrivalsEnabled,
            isAppForeground: UIApplication.shared.applicationState == .active,
            snoozedUntil: snoozedUntil,
            mutedUntil: mutedUntil,
            now: now
        )
        switch outcome {
        case .suppressed(let reason):
            NSLog("[HiMem][Notify] arrival suppressed: \(reason.rawValue)")
        case .fireNow:
            postPassive(trigger: nil)
        case .deferToMorning:
            postPassive(trigger: quietHoursMorningTrigger())
        }
    }

    private func postPassive(trigger: UNNotificationTrigger?) {
        let count = InboxManifest.shared.count
        let content = UNMutableNotificationContent()
        content.title = "HiMem"
        content.body = passiveBody(count: count)
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = ["reason": "arrival"]
        content.sound = nil
        content.interruptionLevel = .passive
        // No numeric badge — `CLAUDE.md` §Phone "App-icon badge: none."
        content.badge = nil

        let request = UNNotificationRequest(identifier: Self.inboxRequestId, content: content, trigger: trigger)
        let center = UNUserNotificationCenter.current()
        // One at a time: replace any prior delivered/pending arrival.
        center.removeDeliveredNotifications(withIdentifiers: [Self.inboxRequestId])
        center.removePendingNotificationRequests(withIdentifiers: [Self.inboxRequestId])
        center.add(request) { error in
            if let error {
                NSLog("[HiMem][Notify] passive arrival fire failed: \(error.localizedDescription)")
            } else {
                NSLog("[HiMem][Notify] passive arrival \(trigger == nil ? "fired" : "deferred to 7am") (count=\(count))")
            }
        }
    }

    /// Fires at the next 7:00 AM local — the quiet-hours deferral target.
    private func quietHoursMorningTrigger() -> UNNotificationTrigger {
        var comps = DateComponents()
        comps.hour = PassiveArrivalPush.quietHoursEnd
        comps.minute = 0
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    }

    private func endOfTodayLocal(from date: Date) -> Date {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: date)
        return cal.date(byAdding: .day, value: 1, to: startOfToday) ?? date.addingTimeInterval(86400)
    }

    // MARK: - Copy

    /// Source-agnostic per `CLAUDE.md` §Phone (clips arrive from +, Watch,
    /// Siri) — the headline names no source.
    private func passiveBody(count: Int) -> String {
        count <= 1 ? "There are new clips you can review" : "\(count) voice clips waiting"
    }

    // MARK: - UserDefaults accessors

    private var snoozedUntil: Date? {
        get { defaults.object(forKey: Keys.snoozedUntil) as? Date }
        set { defaults.set(newValue, forKey: Keys.snoozedUntil) }
    }

    private var mutedUntil: Date? {
        get { defaults.object(forKey: Keys.mutedUntil) as? Date }
        set { defaults.set(newValue, forKey: Keys.mutedUntil) }
    }
}
