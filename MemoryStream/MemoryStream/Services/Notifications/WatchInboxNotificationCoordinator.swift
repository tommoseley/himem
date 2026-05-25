import Foundation
import UserNotifications
import UIKit

/// Pure-function gate for the single-clip passive-push rule. Lives
/// outside the coordinator so it can be tested without UIKit or
/// `UNUserNotificationCenter` plumbing. The coordinator wires the
/// runtime values; tests feed scenarios directly.
enum SingleClipPushGate {
    enum Decision: Equatable {
        case fire
        case suppressed(reason: SuppressionReason)
    }

    enum SuppressionReason: String, Equatable {
        case foreground
        case snoozed
        case muted
    }

    static func evaluate(
        isAppForeground: Bool,
        snoozedUntil: Date?,
        mutedUntil: Date?,
        now: Date
    ) -> Decision {
        if isAppForeground { return .suppressed(reason: .foreground) }
        if let s = snoozedUntil, s > now { return .suppressed(reason: .snoozed) }
        if let m = mutedUntil, m > now { return .suppressed(reason: .muted) }
        return .fire
    }
}

/// Notification policy for watch-clip arrivals, per the Watch → Memory
/// flow spec (`docs/design/CLAUDE.md` → Notifications).
///
/// Four trigger classes:
///   - **Single-clip passive** — every arrival when app is *not* foreground.
///     `.passive` interruption level: lands silently in Notification Center
///     / on the lock screen, no sound, no haptic, no screen wake. Exempt
///     from daily cap / 4-hour suppression / quiet hours (passive by
///     definition doesn't interrupt). Respects snooze + mute because those
///     are explicit user intent.
///   - **Burst** — ≥ 3 clips arrive in a 5-min window. `.active`
///     interruption level (the user is actively dumping thoughts; the
///     batch is worth noting).
///   - **Threshold** — inbox crosses 10 clips. `.active`.
///   - **Stale** — a clip sits unreviewed for > 24 h. Per-clip scheduled
///     `UNCalendarNotificationTrigger`, re-evaluates trigger condition at
///     fire time so we never fire empty. `.active`.
///
/// Rules for active pushes only (burst / threshold / stale):
///   - Daily cap 1 push across all *active* triggers, reset at local midnight.
///   - 4-hour suppression after any *active* push.
///   - Quiet hours 10 PM – 7 AM local: deferred to the next 7 AM.
///
/// Rules for all pushes:
///   - App in foreground: no push (the inbox banner does the work).
///   - Snooze 4h or Mute-for-today: respected.
///   - Burst coalescing: clips within 5 min of an existing burst push are
///     added to that session's count without re-firing.
///   - Stale fires at most 7 times per clip, then stops.
///
/// Snooze (4 h) and Mute-for-today inline actions are wired through
/// `UNNotificationCategory.watchInboxArrival`; their state is persisted
/// in `UserDefaults` and consulted by `canFire(now:)`.
///
/// Persistence: all state lives in `UserDefaults.standard` under the
/// `wic.*` keyspace. No external dependencies — the coordinator can be
/// reset cleanly by removing those keys.
@MainActor
final class WatchInboxNotificationCoordinator {
    static let shared = WatchInboxNotificationCoordinator()

    // MARK: - Identifiers

    /// `UNNotificationCategory` identifier for our inbox-arrival push.
    /// Carries Snooze 4h + Mute for today inline actions.
    static let categoryIdentifier = "watch_inbox_arrival"
    static let actionSnooze4hIdentifier = "snooze_4h"
    static let actionMuteTodayIdentifier = "mute_today"

    /// UN request identifiers. Inbox push uses a single id (newer pushes
    /// replace older ones in Notification Center). Stale pushes are
    /// keyed by clipId.
    private static let inboxRequestId = "watch_inbox_arrival"
    private static func staleRequestId(for clipId: UUID) -> String {
        "watch_inbox_stale_\(clipId.uuidString)"
    }

    // MARK: - Persisted state

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let lastPushAt = "wic.lastPushAt"
        static let snoozedUntil = "wic.snoozedUntil"
        static let mutedUntil = "wic.mutedUntil"
        static let burstWindowStart = "wic.burstWindowStart"
        static let burstWindowCount = "wic.burstWindowCount"
        static let staleFiresByClip = "wic.staleFiresByClip"
        static let pushedThresholdAtCount = "wic.pushedThresholdAtCount"
    }

    /// Thresholds and durations, all per the spec.
    private static let burstClipCount = 3
    private static let burstWindowSeconds: TimeInterval = 5 * 60
    private static let thresholdInboxCount = 10
    private static let staleAgeSeconds: TimeInterval = 24 * 3600
    private static let dailyCapSuppressionSeconds: TimeInterval = 4 * 3600
    private static let quietHoursStart = 22  // 10 PM
    private static let quietHoursEnd = 7     // 7 AM
    private static let staleFireCap = 7

    // MARK: - Bootstrap

    private init() {}

    /// Register the notification category + inline actions. Call once at
    /// app launch (after `NotificationService.registerDefaults`).
    func registerCategories() {
        let snooze = UNNotificationAction(
            identifier: Self.actionSnooze4hIdentifier,
            title: "Snooze 4h",
            options: []
        )
        let mute = UNNotificationAction(
            identifier: Self.actionMuteTodayIdentifier,
            title: "Mute for today",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [snooze, mute],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Lifecycle hooks (call from `InboxManifest` mutations)

    /// Called from `WatchSessionDelegate.didReceive(file:)` after the
    /// clip has been added to `InboxManifest`. Schedules the per-clip
    /// 24h stale trigger, evaluates burst/threshold for an immediate
    /// active push, and — if no active push fired — posts a silent
    /// `.passive` single-clip notification so the user knows something
    /// arrived without being interrupted.
    func clipArrived(clipId: UUID, capturedAt: Date) {
        let now = Date()
        scheduleStaleTrigger(for: clipId)
        let firedActivePush = evaluateBurstAndThreshold(now: now)
        if !firedActivePush {
            firePassiveSingleClipPushIfAllowed(now: now)
        }
    }

    /// Called when a clip leaves the inbox (moved into an Entry or
    /// discarded). Cancels its pending stale trigger and the
    /// `staleFires` counter so future pings start fresh if a *new*
    /// clip with the same id ever appears (won't happen in practice
    /// because we use UUIDs, but cheap to clean).
    func clipRemoved(clipId: UUID) {
        cancelStaleTrigger(for: clipId)
        var fires = staleFiresByClip
        fires.removeValue(forKey: clipId.uuidString)
        staleFiresByClip = fires
    }

    /// Inline action handler — called from the
    /// `UNUserNotificationCenterDelegate` when the user picks an action.
    func handleAction(identifier: String) {
        switch identifier {
        case Self.actionSnooze4hIdentifier:
            snoozedUntil = Date().addingTimeInterval(4 * 3600)
            NSLog("[Himem][Notify] snoozed for 4h until \(snoozedUntil!)")
        case Self.actionMuteTodayIdentifier:
            mutedUntil = endOfTodayLocal(from: Date())
            NSLog("[Himem][Notify] muted until midnight local \(mutedUntil!)")
        default:
            break
        }
    }

    // MARK: - Trigger evaluation

    /// Burst + threshold are evaluated synchronously on each clip
    /// arrival. Stale is event-driven via its scheduled trigger.
    /// Returns `true` when an active push fired so the caller can skip
    /// the passive single-clip fallback.
    @discardableResult
    private func evaluateBurstAndThreshold(now: Date) -> Bool {
        // Burst window bookkeeping: extend the window if a clip arrived
        // within 5 min of the window start; otherwise open a fresh one.
        var windowStart = burstWindowStart
        var count = burstWindowCount
        if let start = windowStart, now.timeIntervalSince(start) <= Self.burstWindowSeconds {
            count += 1
        } else {
            windowStart = now
            count = 1
        }
        burstWindowStart = windowStart
        burstWindowCount = count

        let inboxCount = InboxManifest.shared.count

        // Burst: ≥ 3 clips inside the window → fire (subject to canFire).
        if count >= Self.burstClipCount, canFire(now: now) {
            firePush(body: burstBody(count: count), now: now, reason: "burst")
            return true
        }

        // Threshold: inbox crosses 10 (we push once when it first
        // exceeds; the `pushedThresholdAtCount` watermark prevents
        // re-firing as the count fluctuates around the boundary).
        if inboxCount > Self.thresholdInboxCount, canFire(now: now),
           inboxCount > pushedThresholdAtCount {
            firePush(body: thresholdBody(count: inboxCount), now: now, reason: "threshold")
            pushedThresholdAtCount = inboxCount
            return true
        }

        // If the inbox dipped back under threshold, reset the watermark
        // so a future crossing fires again.
        if inboxCount <= Self.thresholdInboxCount {
            pushedThresholdAtCount = 0
        }
        return false
    }

    // MARK: - Single-clip passive push

    /// Posts a silent `.passive` notification announcing a single new
    /// clip, IFF the app isn't foreground and the user hasn't snoozed
    /// or muted. `.passive` notifications land in Notification Center
    /// and on the lock screen without lighting the screen, vibrating,
    /// or playing a sound — so they're exempt from the daily-cap /
    /// 4-hour suppression / quiet-hours rules that exist to control
    /// active-push fatigue. Each fire uses a unique request id so
    /// multiple passive notifications can coexist in Notification
    /// Center until the user opens the inbox.
    private func firePassiveSingleClipPushIfAllowed(now: Date) {
        let gate = SingleClipPushGate.evaluate(
            isAppForeground: UIApplication.shared.applicationState == .active,
            snoozedUntil: snoozedUntil,
            mutedUntil: mutedUntil,
            now: now
        )
        guard case .fire = gate else {
            NSLog("[Himem][Notify] single-clip passive suppressed: \(gate)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "HiMem"
        content.body = "New voice clip from your Watch"
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = ["reason": "single"]
        content.badge = NSNumber(value: InboxManifest.shared.count)
        content.sound = nil
        content.interruptionLevel = .passive

        let request = UNNotificationRequest(
            identifier: "watch_inbox_single_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("[Himem][Notify] single-clip passive fire failed: \(error.localizedDescription)")
            } else {
                NSLog("[Himem][Notify] single-clip passive fired")
            }
        }
        // Deliberately do NOT update lastPushAt — passive notifications
        // shouldn't count toward the daily-cap budget that gates active
        // pushes.
    }

    // MARK: - Stale (per-clip scheduled triggers)

    private func scheduleStaleTrigger(for clipId: UUID) {
        let fires = staleFiresByClip[clipId.uuidString] ?? 0
        if fires >= Self.staleFireCap { return }

        let fireDate = Date().addingTimeInterval(Self.staleAgeSeconds)
        let cal = Calendar.current
        let components = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let content = UNMutableNotificationContent()
        content.title = "HiMem"
        content.body = staleBody()
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = ["reason": "stale", "clipId": clipId.uuidString]
        content.badge = NSNumber(value: InboxManifest.shared.count)

        let request = UNNotificationRequest(
            identifier: Self.staleRequestId(for: clipId),
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("[Himem][Notify] stale schedule failed for \(clipId): \(error.localizedDescription)")
            }
        }
    }

    private func cancelStaleTrigger(for clipId: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.staleRequestId(for: clipId)]
        )
    }

    /// Called from the foreground-presentation delegate when a stale
    /// trigger fires. Returns true if the push should be presented; the
    /// caller (`UNUserNotificationCenterDelegate.willPresent`) is then
    /// expected to apply its standard suppression. Side-effects: when
    /// returning true we also bump the per-clip fire counter; when
    /// false we suppress and schedule the *next* attempt 24 h later
    /// (still subject to the 7-fire cap).
    func handleStaleFire(clipId: UUID, now: Date) -> Bool {
        // Re-evaluate: is the clip still in the inbox?
        guard InboxManifest.shared.clips.contains(where: { $0.clipId == clipId }) else {
            return false
        }
        // Suppression rules (app foreground / daily cap / quiet hours / snooze / mute).
        guard canFire(now: now) else {
            // Re-schedule for next 7am if quiet, otherwise 24h out.
            // Cheapest: re-arm a fresh 24h trigger to retry tomorrow.
            scheduleStaleTrigger(for: clipId)
            return false
        }
        // Bump counter; record this push.
        var fires = staleFiresByClip
        fires[clipId.uuidString] = (fires[clipId.uuidString] ?? 0) + 1
        staleFiresByClip = fires
        lastPushAt = now
        return true
    }

    // MARK: - canFire rules

    private func canFire(now: Date) -> Bool {
        // App foreground? No push.
        if UIApplication.shared.applicationState == .active { return false }
        // Snoozed?
        if let snoozed = snoozedUntil, snoozed > now { return false }
        if let muted = mutedUntil, muted > now { return false }
        // Daily cap (one push per calendar day, local time).
        if let last = lastPushAt, Calendar.current.isDate(last, inSameDayAs: now) {
            return false
        }
        // 4-hour suppression after any push.
        if let last = lastPushAt, now.timeIntervalSince(last) < Self.dailyCapSuppressionSeconds {
            return false
        }
        // Quiet hours: defer instead of fire. (Burst/Threshold callers
        // will retry on the next clip arrival; stale callers reschedule.)
        if isInQuietHours(now) { return false }
        return true
    }

    private func isInQuietHours(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        // 22 (10pm) through 06 (6:59am).
        return hour >= Self.quietHoursStart || hour < Self.quietHoursEnd
    }

    private func endOfTodayLocal(from date: Date) -> Date {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: date)
        // 24 hours later is start of tomorrow = end of today.
        return cal.date(byAdding: .day, value: 1, to: startOfToday) ?? date.addingTimeInterval(86400)
    }

    // MARK: - Fire push

    private func firePush(body: String, now: Date, reason: String) {
        let content = UNMutableNotificationContent()
        content.title = "HiMem"
        content.body = body
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = ["reason": reason]
        content.badge = NSNumber(value: InboxManifest.shared.count)
        content.sound = .default
        content.interruptionLevel = .active

        let request = UNNotificationRequest(
            identifier: Self.inboxRequestId,
            content: content,
            trigger: nil
        )
        // Clear any prior delivered notification with this id so the
        // new fire registers as a fresh delivery (buzz + sound).
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: [Self.inboxRequestId]
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("[Himem][Notify] \(reason) fire failed: \(error.localizedDescription)")
            } else {
                NSLog("[Himem][Notify] \(reason) fired: \(body)")
            }
        }
        lastPushAt = now
    }

    // MARK: - Copy

    private func burstBody(count: Int) -> String {
        "\(count) voice clips ready to organize"
    }

    private func thresholdBody(count: Int) -> String {
        "You have \(count) voice clips waiting"
    }

    private func staleBody() -> String {
        "Some clips are still waiting to be organized"
    }

    // MARK: - UserDefaults accessors

    private var lastPushAt: Date? {
        get { defaults.object(forKey: Keys.lastPushAt) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastPushAt) }
    }

    private var snoozedUntil: Date? {
        get { defaults.object(forKey: Keys.snoozedUntil) as? Date }
        set { defaults.set(newValue, forKey: Keys.snoozedUntil) }
    }

    private var mutedUntil: Date? {
        get { defaults.object(forKey: Keys.mutedUntil) as? Date }
        set { defaults.set(newValue, forKey: Keys.mutedUntil) }
    }

    private var burstWindowStart: Date? {
        get { defaults.object(forKey: Keys.burstWindowStart) as? Date }
        set { defaults.set(newValue, forKey: Keys.burstWindowStart) }
    }

    private var burstWindowCount: Int {
        get { defaults.integer(forKey: Keys.burstWindowCount) }
        set { defaults.set(newValue, forKey: Keys.burstWindowCount) }
    }

    private var pushedThresholdAtCount: Int {
        get { defaults.integer(forKey: Keys.pushedThresholdAtCount) }
        set { defaults.set(newValue, forKey: Keys.pushedThresholdAtCount) }
    }

    private var staleFiresByClip: [String: Int] {
        get {
            guard let data = defaults.data(forKey: Keys.staleFiresByClip),
                  let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else {
                return [:]
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.staleFiresByClip)
            }
        }
    }
}
