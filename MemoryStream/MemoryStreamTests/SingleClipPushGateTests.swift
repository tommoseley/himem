import Testing
import Foundation
@testable import HiMem

/// Money tests for the single-clip passive-push gate.
///
/// Spec (`docs/design/CLAUDE.md` → Notifications):
/// > **Single clip** — when the app is **not foreground**, fire a `.passive`
/// > notification … When the app **is foreground**, badge only. Single-clip
/// > passive pushes … still respect Snooze and Mute.
///
/// Daily-cap / 4-hour suppression / quiet hours are deliberately NOT in the
/// gate — those apply only to active pushes (burst / threshold / stale).
/// A passive notification is silent and doesn't interrupt, so applying
/// rate limits would defeat its purpose.
struct SingleClipPushGateTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func fires_whenBackgrounded_andNothingSuppressed() {
        let decision = SingleClipPushGate.evaluate(
            isAppForeground: false,
            snoozedUntil: nil,
            mutedUntil: nil,
            now: now
        )
        #expect(decision == .fire)
    }

    @Test func suppressed_whenForeground() {
        let decision = SingleClipPushGate.evaluate(
            isAppForeground: true,
            snoozedUntil: nil,
            mutedUntil: nil,
            now: now
        )
        #expect(decision == .suppressed(reason: .foreground))
    }

    @Test func suppressed_whenSnoozedInFuture() {
        let decision = SingleClipPushGate.evaluate(
            isAppForeground: false,
            snoozedUntil: now.addingTimeInterval(3600),
            mutedUntil: nil,
            now: now
        )
        #expect(decision == .suppressed(reason: .snoozed))
    }

    @Test func fires_whenSnoozeExpired() {
        let decision = SingleClipPushGate.evaluate(
            isAppForeground: false,
            snoozedUntil: now.addingTimeInterval(-60),
            mutedUntil: nil,
            now: now
        )
        #expect(decision == .fire)
    }

    @Test func suppressed_whenMutedInFuture() {
        let decision = SingleClipPushGate.evaluate(
            isAppForeground: false,
            snoozedUntil: nil,
            mutedUntil: now.addingTimeInterval(7200),
            now: now
        )
        #expect(decision == .suppressed(reason: .muted))
    }

    @Test func fires_whenMuteExpired() {
        let decision = SingleClipPushGate.evaluate(
            isAppForeground: false,
            snoozedUntil: nil,
            mutedUntil: now.addingTimeInterval(-1),
            now: now
        )
        #expect(decision == .fire)
    }

    /// Foreground beats every other suppression — even if snoozed AND muted,
    /// foreground is the reason reported. Documenting the precedence so a
    /// future contributor doesn't accidentally reorder the checks.
    @Test func foregroundPrecedesOtherSuppressions() {
        let decision = SingleClipPushGate.evaluate(
            isAppForeground: true,
            snoozedUntil: now.addingTimeInterval(3600),
            mutedUntil: now.addingTimeInterval(7200),
            now: now
        )
        #expect(decision == .suppressed(reason: .foreground))
    }
}

/// Money tests for the 2026-05-26 stacking-notifications bug.
///
/// Symptom (lock-screen screenshot): three separate "Some clips are
/// still waiting to be organized" notifications from HiMem stacked in
/// Notification Center, 46m / 51m / 2h apart. iOS keeps separate
/// notifications because each was scheduled with a per-clip
/// identifier (`watch_inbox_stale_<clipId>`); when they all fired,
/// they all delivered as distinct entries.
///
/// Fix contract: identifiers are stable strings, not clip-derived.
/// One scheduled request per surface; iOS replaces a prior delivered
/// notification when a new one with the same identifier fires (with a
/// `removeDeliveredNotifications` call before `add` covering the case
/// where the trigger fires while another delivered copy is visible).
///
/// Per `docs/design/CLAUDE.md` → Notifications, Channel A: "one
/// pending notification at a time, body re-rendered in place."
@MainActor
struct WatchInboxNotificationIdentifierTests {

    @Test func staleIdentifier_isStableConstant_notPerClipDerived() {
        // Before the fix, the identifier was
        // `"watch_inbox_stale_<clipId.uuidString>"` — a different
        // string per clip. After the fix, one constant.
        let id = WatchInboxNotificationCoordinator.inboxStaleRequestId
        #expect(id == "watch_inbox_stale")
        // No UUID embedded — the previous bug was UUID-suffixed
        // identifiers that produced one delivered notification per
        // scheduled trigger.
        let uuidRegex = try? NSRegularExpression(
            pattern: "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}",
            options: .caseInsensitive
        )
        let range = NSRange(id.startIndex..., in: id)
        #expect(uuidRegex?.firstMatch(in: id, range: range) == nil)
    }

    @Test func singleClipPassiveIdentifier_isStableConstant() {
        // Same bug shape — the single-clip passive path used
        // `"watch_inbox_single_\(UUID().uuidString)"`, so each clip
        // arrival produced a distinct notification in the stack.
        let id = WatchInboxNotificationCoordinator.inboxSinglePassiveRequestId
        #expect(id == "watch_inbox_single")
    }

    @Test func allInboxIdentifiers_areDistinctFromEachOther() {
        // The three identifiers (active arrival / stale / passive) must
        // stay distinct — otherwise an active burst push would replace
        // a pending passive notification or vice versa.
        let ids = Set([
            WatchInboxNotificationCoordinator.inboxRequestId,
            WatchInboxNotificationCoordinator.inboxStaleRequestId,
            WatchInboxNotificationCoordinator.inboxSinglePassiveRequestId,
        ])
        #expect(ids.count == 3)
    }
}
