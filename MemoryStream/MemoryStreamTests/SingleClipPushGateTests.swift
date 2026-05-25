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
