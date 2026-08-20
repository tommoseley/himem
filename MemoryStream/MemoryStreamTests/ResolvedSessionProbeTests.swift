import Testing
import Foundation
@testable import HiMem

/// **The probe must be able to fire.**
///
/// Through C2 step 4 slice B its job was to report where `ResolvedSession` and
/// the legacy `(ClipGroup, mediaBySessionId)` pair disagreed, before ~12
/// consumers migrated. It did that job: on device it reported
/// `resolved=6 legacy=1 · key=00000000 map=HIT` and named B25's colliding
/// sentinel outright, after four wrong theories had failed to.
///
/// **Slice C retires the comparison, not the probe.** With the pair gone there
/// is one composition, and a probe deriving both sides from it could only agree
/// with itself. Four tests here retired with their subject — the count
/// disagreement, and the three discriminating fields (`key=`, `map=`, `kinds=`)
/// that existed to choose among three candidate mechanisms once. **The
/// mechanism is known and fixed; a field that discriminates nothing is chrome
/// on a log line.** A guard whose defect can no longer occur is a different
/// thing from a guard that was wrong, and each is recorded here rather than
/// deleted quietly.
///
/// What survives is the half that was never about the migration: an item the
/// bench composed and the card layer cannot draw. That is a live signal for as
/// long as there is a card layer.
///
/// **A probe that cannot fire is worse than none: it converts an unmeasured
/// swap into one that looks measured.** This project has shipped that exact
/// failure. On 2026-08-09 a diagnostic written specifically to be falsifiable
/// passed by matching nothing — `synthesizedRows` and `emptyGroups` were both
/// reductions over an empty set, so both printed 0 regardless of the truth, in
/// the line meant to end the guessing. And on 2026-08-17 `[ClusterTrace]`
/// reported ~16 emissions of churn it had introduced itself, which is why
/// `lines` here is canonically ordered.
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

    /// Silence is the common case, and it must be real silence rather than a
    /// probe that never speaks.
    @Test
    func itIsSilentWhenEverythingResolved() {
        #expect(ResolvedSessionProbe.finding(resolved: resolved(count: 3)) == nil)
    }

    /// **The one finding that survives the swap.** An item the bench composed
    /// and the card layer cannot draw — `projectGroup` resolved with
    /// `compactMap` and hid exactly this.
    @Test
    func itFiresOnAnUnresolvedItem() {
        let ghost = UUID()
        let finding = ResolvedSessionProbe.finding(resolved: resolved(count: 2, unresolved: [ghost]))
        #expect(finding != nil, "an unread `unresolved` is the UnifiedBenchGrouper shape: complete, tested, never consulted")
        #expect(finding?.unresolved == [ghost])
        #expect(finding?.resolvedCount == 2, "the drawable count travels with the loss, so a reader knows what the session DID draw")

        let line = ResolvedSessionProbe.lines([finding!]).first ?? ""
        #expect(line.contains("UNRESOLVED"))
        #expect(line.contains(String(ghost.uuidString.prefix(8))), "the missing item must be identifiable from the log alone")
    }

    /// `findings(in:)` is what production calls, so the sweep across sessions —
    /// not just the single-session predicate — is what must be guarded.
    /// **Guard the caller, not just the owner.**
    @Test
    func theSweepReportsOnlyTheSessionsThatLostSomething() {
        let ghost = UUID()
        let clean = resolved(count: 3)
        let lossy = resolved(count: 1, unresolved: [ghost])

        let findings = ResolvedSessionProbe.findings(in: [clean, lossy])

        #expect(findings.count == 1, "a clean session must not produce a line, or the log stops being readable")
        #expect(findings.first?.sessionId == lossy.id)
        #expect(findings.first?.unresolved == [ghost])
    }

    /// Canonical order — the B21 lesson. If emission order tracked anything but
    /// the findings themselves, the signature gate would fire on an unchanged
    /// bench and report churn that is not there.
    @Test
    func linesAreOrderedByTheFindingsThemselves() {
        let a = ResolvedSessionProbe.Finding(
            sessionId: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!,
            resolvedCount: 1,
            unresolved: [UUID()]
        )
        let b = ResolvedSessionProbe.Finding(
            sessionId: UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!,
            resolvedCount: 1,
            unresolved: [UUID()]
        )

        #expect(ResolvedSessionProbe.lines([a, b]) == ResolvedSessionProbe.lines([b, a]))
    }
}
