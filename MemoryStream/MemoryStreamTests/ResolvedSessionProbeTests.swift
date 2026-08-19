import Testing
import Foundation
@testable import HiMem

/// **The step-4 probe must be able to disagree.**
///
/// Its job is to report where `ResolvedSession` and the legacy
/// `(ClipGroup, mediaBySessionId)` pair differ, before ~12 consumers migrate to
/// the new value. A probe that cannot fire is worse than none: it converts an
/// unmeasured swap into one that looks measured.
///
/// **This project has shipped that exact failure.** On 2026-08-09 a diagnostic
/// written specifically to be falsifiable passed by matching nothing —
/// `synthesizedRows` and `emptyGroups` were both reductions over an empty set,
/// so both printed 0 regardless of the truth, in the line meant to end the
/// guessing. And on 2026-08-17 `[ClusterTrace]` reported ~16 emissions of churn
/// it had introduced itself, which is why `lines` here is canonically ordered.
struct ResolvedSessionProbeTests {

    private func resolved(count: Int, unresolved: [UUID] = []) -> ResolvedSession {
        let items = (0..<count).map { i -> ResolvedSession.Item in
            .voice(InboxClip(
                clipId: UUID(),
                capturedAt: Date(timeIntervalSinceReferenceDate: Double(i)),
                duration: 30,
                transcript: "t",
                latitude: nil,
                longitude: nil,
                source: "watch",
                audioFilename: "\(UUID()).caf",
                transcriptionAttempted: true,
                rollGroupId: nil
            ))
        }
        return ResolvedSession(id: UUID(), items: items, unresolved: unresolved)
    }

    @Test
    func itIsSilentWhenTheTwoWaysOfCountingAgree() {
        #expect(ResolvedSessionProbe.finding(resolved: resolved(count: 3), legacyCount: 3) == nil)
    }

    /// The disagreement the step exists to prevent: one session, two counts.
    @Test
    func itFiresWhenTheCountsDiffer() {
        let finding = ResolvedSessionProbe.finding(resolved: resolved(count: 4), legacyCount: 3)
        #expect(finding != nil, "a probe that cannot fire makes an unmeasured swap look measured")
        #expect(finding?.resolvedCount == 4)
        #expect(finding?.legacyCount == 3)

        let line = ResolvedSessionProbe.lines([finding!]).first ?? ""
        #expect(line.contains("DIFFER"), "the log must name the disagreement, not merely record numbers")
        #expect(line.contains("resolved=4") && line.contains("legacy=3"), "both sides must be readable from the line")
    }

    /// An item the bench composed and the card layer cannot draw is a finding
    /// even when the counts happen to agree — `projectGroup`'s `compactMap`
    /// would have hidden it.
    @Test
    func itFiresOnAnUnresolvedItemEvenWhenCountsAgree() {
        let ghost = UUID()
        let finding = ResolvedSessionProbe.finding(resolved: resolved(count: 2, unresolved: [ghost]), legacyCount: 2)
        #expect(finding != nil, "an unread `unresolved` is the UnifiedBenchGrouper shape: complete, tested, never consulted")
        #expect(finding?.unresolved == [ghost])

        let line = ResolvedSessionProbe.lines([finding!]).first ?? ""
        #expect(line.contains("UNRESOLVED"))
        #expect(line.contains(String(ghost.uuidString.prefix(8))), "the missing item must be identifiable from the log alone")
    }

    /// Canonical order — the B21 lesson. If emission order tracked anything but
    /// the findings themselves, the signature gate would fire on an unchanged
    /// bench and report churn that is not there.
    @Test
    func linesAreOrderedByTheFindingsThemselves() {
        let a = ResolvedSessionProbe.Finding(sessionId: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!, resolvedCount: 1, legacyCount: 2, unresolved: [])
        let b = ResolvedSessionProbe.Finding(sessionId: UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!, resolvedCount: 1, legacyCount: 2, unresolved: [])

        #expect(ResolvedSessionProbe.lines([a, b]) == ResolvedSessionProbe.lines([b, a]))
    }
}
