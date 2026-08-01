import Testing
import Foundation
@testable import HiMem

/// **F26 — the walkthrough was an open-loop state machine.**
///
/// Six reported symptoms, one cause with three properties:
///
/// **A · The script assumes the Clips pipeline; the FAB is context-aware.**
/// `clipDidLand()` has a single caller, inside
/// `.onChange(of: captureLanding.pendingReturnToClips)`, and that flag is set
/// only by the `.dropOnBench` branch. On Memories, + creates a `JournalEntry`
/// directly, so the flag never flips and the machine sits on `record`.
/// **Cold launch lands on Memories** — the default first-run user started on
/// the one tab where step 2 could never arrive.
///
/// **B · No anchoring.** Every beat is a floating claim (F16, unchanged).
///
/// **C · No terminal state.** `advance()` is a no-op for every pipeline beat,
/// so a missing signal stalls the machine permanently — and `finish()` is the
/// only thing that clears `walkthroughMemoryId`, which the ring reads through
/// `isRunning`. **"Step 5 never appears" and "the ring persists after
/// completion" are the same defect**: there is no after-completion. It never
/// terminated, and the stuck ring is its visible residue.
///
/// These tests pin the three rulings of 2026-08-01.
@Suite(.serialized)
struct WalkthroughTerminationTests {

    @MainActor private func fresh() -> WalkthroughOrchestrator {
        let o = WalkthroughOrchestrator.shared
        o.skip()             // force a clean terminal state
        return o
    }

    // MARK: - C · termination clears the ring (the load-bearing one)

    /// The ring's window is `isRunning ? walkthroughMemoryId : nil`. Ending
    /// the walkthrough from ANY beat must close that window — otherwise the
    /// ochre ring stays on her memory forever.
    @Test @MainActor func endingFromAnyBeat_clearsTheRingWindow() {
        for beat in [WalkthroughOrchestrator.Beat.record,
                     .clipLanded, .makeMemory, .openMemory,
                     .memoryInList, .detailTour, .organize, .done] {
            let o = fresh()
            o.start()
            o.beginFromOffer()
            o.debugForceBeat(beat, memoryId: UUID())
            #expect(o.isRunning == true)

            o.skip()

            #expect(o.isRunning == false, "Still running after ending on \(beat) — the ring would persist.")
            #expect(o.walkthroughMemoryId == nil, "Ring target survived the exit on \(beat).")
        }
    }

    /// A stalled walkthrough — the exact F26 condition — must still be
    /// endable. This is what makes the persistent affordance meaningful.
    @Test @MainActor func aStalledWalkthrough_isStillEndable() {
        let o = fresh()
        o.start()
        o.beginFromOffer()
        o.debugForceBeat(.openMemory, memoryId: UUID())

        // The signal never arrives; tapping through does nothing (by design —
        // beats advance on real signals, never on a tap).
        o.advance()
        #expect(o.activeBeat == .openMemory, "Pipeline beats must not tap-advance (F10 invariant).")

        o.skip()
        #expect(o.isRunning == false)
        #expect(o.walkthroughMemoryId == nil)
    }

    // MARK: - A · the flow runs on Clips, and says so

    @Test @MainActor func beginningTheFlow_requestsTheClipsTab() {
        let o = fresh()
        o.start()
        #expect(o.pendingClipsTabSwitch == false)
        o.beginFromOffer()
        #expect(o.pendingClipsTabSwitch == true, "The flow must move to the tab whose pipeline it teaches.")
        #expect(o.consumeClipsTabSwitch() == true)
        #expect(o.consumeClipsTabSwitch() == false, "One-shot — a re-consume would fight the user's own tab taps.")
    }

    /// The move is announced, never silent. Ruled 2026-08-01: she is not
    /// teleported without explanation.
    @Test func offerCopy_namesTheTabItMovesTo() {
        let offer = WalkthroughOrchestrator.Beat.offer.body(alreadyOrganized: false)
        #expect(offer.contains("Clips"), "The offer must name where the flow starts.")
        #expect(offer.contains("first memory"), "It must still promise the outcome she's here for.")
    }

    /// F13 holds: naming the destination is orientation, not curriculum. The
    /// offer must not start teaching the ontology.
    @Test func offerCopy_doesNotTeachTheOntology() {
        let offer = WalkthroughOrchestrator.Beat.offer.body(alreadyOrganized: false).lowercased()
        #expect(offer.contains("part") == false)
        #expect(offer.contains("evidence") == false)   // F7g — never in UI copy
    }

    // MARK: - B · step 3 pins where its referents are

    @Test func stepThreeBeats_pinToTheBottom() {
        for beat in [WalkthroughOrchestrator.Beat.makeMemory, .openMemory, .memoryInList] {
            #expect(beat.stepNumber == 3)
            #expect(beat.pinsToBottom, "\(beat) references something low on screen and must not cover it.")
        }
    }

    @Test func otherBeats_stayPinnedToTheTop() {
        for beat in [WalkthroughOrchestrator.Beat.record, .clipLanded, .organize, .done] {
            #expect(beat.pinsToBottom == false)
        }
    }

    // MARK: - Caller guards

    /// The way out must be on EVERY banner, and must route through `skip()`
    /// (→ `finish()`). An exit that bypasses `finish()` re-creates the stuck
    /// ring — the bug this item exists to close.
    @Test func everyBanner_carriesAnExitRoutedThroughFinish() throws {
        let src = try Self.source("MemoryStream/Views/Components/WalkthroughOverlay.swift")
        #expect(src.contains("orchestrator.skip"),
                "The overlay's exit no longer routes through skip() → finish(); the ring would persist.")
        let banner = try Self.functionBody(named: "private func topBanner(", in: src)
        #expect(banner.contains("endWalkthroughLink"),
                "The banner does not render a way out on every beat.\n\(banner)")
        // It must not be conditional on the beat.
        let gated = banner.contains("if beat") && banner.range(of: "endWalkthroughLink")
            .map { banner[..<$0.lowerBound].hasSuffix("{\n                    ") } ?? false
        #expect(gated == false, "The exit is gated on a beat — it must be unconditional.")
    }

    /// `finish()` must keep clearing the ring target. This is the invariant
    /// every exit path depends on.
    @Test func finishClearsTheRingTarget() throws {
        let src = try Self.source("MemoryStream/Services/Tutorials/WalkthroughOrchestrator.swift")
        let body = try Self.functionBody(named: "private func finish()", in: src)
        #expect(body.contains("walkthroughMemoryId = nil"),
                "finish() no longer clears the ring target — the ring would outlive the walkthrough.\n\(body)")
        #expect(body.contains("activeBeat = nil"),
                "finish() no longer closes isRunning — the ring window would stay open.\n\(body)")
    }

    // MARK: - Source access

    static func functionBody(named needle: String, in source: String) throws -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains(needle) }) else {
            throw Failure.functionNotFound(needle)
        }
        var depth = 0, started = false
        var out: [String] = []
        for line in lines[start...] {
            for ch in line {
                if ch == "{" { depth += 1; started = true }
                if ch == "}" { depth -= 1 }
            }
            if started { out.append(line) }
            if started && depth == 0 { return out.joined(separator: "\n") }
        }
        throw Failure.functionNotFound(needle)
    }

    static func source(_ relative: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        guard let src = try? String(contentsOf: url, encoding: .utf8), !src.isEmpty else {
            throw Failure.sourceNotFound(url.path)
        }
        return src
    }

    enum Failure: Error { case sourceNotFound(String), functionNotFound(String) }
}
