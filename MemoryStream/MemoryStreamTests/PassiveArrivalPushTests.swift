import Testing
import Foundation
@testable import HiMem

/// Money tests for RH-1 (July 20 2026) — Captured-Clips arrivals are
/// passive-only. The pure decision must: honor the persisted enable
/// toggle, suppress in foreground / snooze / mute, DEFER (not suppress)
/// during quiet hours (10 PM–7 AM), and fire immediately otherwise. The
/// deleted burst/threshold/stale active classes have no representation
/// here — that's the point.
@Suite
struct PassiveArrivalPushTests {

    private func at(_ hour: Int) -> Date {
        // A fixed day at `hour`:00 local.
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 20; c.hour = hour; c.minute = 0
        return Calendar.current.date(from: c)!
    }

    @Test func disabled_suppresses() {
        let d = PassiveArrivalPush.decide(enabled: false, isAppForeground: false,
                                          snoozedUntil: nil, mutedUntil: nil, now: at(10))
        #expect(d == .suppressed(reason: .disabled))
    }

    @Test func foreground_suppresses() {
        let d = PassiveArrivalPush.decide(enabled: true, isAppForeground: true,
                                          snoozedUntil: nil, mutedUntil: nil, now: at(10))
        #expect(d == .suppressed(reason: .foreground))
    }

    @Test func snoozed_and_muted_suppress() {
        let now = at(10)
        let future = now.addingTimeInterval(3600)
        #expect(PassiveArrivalPush.decide(enabled: true, isAppForeground: false,
                snoozedUntil: future, mutedUntil: nil, now: now) == .suppressed(reason: .snoozed))
        #expect(PassiveArrivalPush.decide(enabled: true, isAppForeground: false,
                snoozedUntil: nil, mutedUntil: future, now: now) == .suppressed(reason: .muted))
        // An expired snooze doesn't suppress.
        let past = now.addingTimeInterval(-3600)
        #expect(PassiveArrivalPush.decide(enabled: true, isAppForeground: false,
                snoozedUntil: past, mutedUntil: nil, now: now) == .fireNow)
    }

    @Test func daytime_firesNow() {
        for hour in [7, 10, 15, 21] {
            #expect(PassiveArrivalPush.decide(enabled: true, isAppForeground: false,
                    snoozedUntil: nil, mutedUntil: nil, now: at(hour)) == .fireNow,
                    "hour \(hour) should fire immediately")
        }
    }

    @Test func quietHours_defersToMorning() {
        // 10 PM through 6:59 AM → defer to 7 AM (not suppressed).
        for hour in [22, 23, 0, 3, 6] {
            #expect(PassiveArrivalPush.decide(enabled: true, isAppForeground: false,
                    snoozedUntil: nil, mutedUntil: nil, now: at(hour)) == .deferToMorning,
                    "hour \(hour) is quiet → defer")
        }
        // Boundaries: 22:00 quiet, 07:00 not quiet.
        #expect(PassiveArrivalPush.decide(enabled: true, isAppForeground: false,
                snoozedUntil: nil, mutedUntil: nil, now: at(22)) == .deferToMorning)
        #expect(PassiveArrivalPush.decide(enabled: true, isAppForeground: false,
                snoozedUntil: nil, mutedUntil: nil, now: at(7)) == .fireNow)
    }

    /// Precedence: disabled/foreground/snooze/mute win over quiet-hours defer.
    @Test func suppression_beatsQuietHoursDefer() {
        #expect(PassiveArrivalPush.decide(enabled: false, isAppForeground: false,
                snoozedUntil: nil, mutedUntil: nil, now: at(3)) == .suppressed(reason: .disabled))
        #expect(PassiveArrivalPush.decide(enabled: true, isAppForeground: true,
                snoozedUntil: nil, mutedUntil: nil, now: at(3)) == .suppressed(reason: .foreground))
    }

    /// Enduring contract from the 2026-05-26 stacking-notifications fix,
    /// carried past the RH-1 rewrite: the ONE arrival identifier is a stable
    /// constant with no embedded UUID, so a new arrival replaces the prior
    /// notification in place (Channel A: "one pending notification at a time")
    /// rather than stacking.
    @Test func arrivalIdentifier_isStableConstant_noUUID() {
        let id = WatchInboxNotificationCoordinator.inboxRequestId
        #expect(id == "watch_inbox_arrival")
        let uuidRegex = try? NSRegularExpression(
            pattern: "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}",
            options: .caseInsensitive
        )
        let range = NSRange(id.startIndex..., in: id)
        #expect(uuidRegex?.firstMatch(in: id, range: range) == nil)
    }
}
