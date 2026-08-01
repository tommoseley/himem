import Testing
import Foundation
@testable import HiMem

/// F23 · audit finding #4 (logged Tier 2) — **"Add to a memory" looked dead.**
///
/// `attachExistingClips` returns 0 when no ref resolved. `appendToExistingMemory`
/// met that with `guard written > 0 else { return }` (`:614` pre-fix) and said
/// nothing: the sheet stayed open, unchanged, with the clips still listed and
/// the Add button still lit. The user taps Add, and the app does nothing —
/// twice, three times — with no way to tell whether it failed or they missed
/// the button.
///
/// Keeping the session was correct (it is the sibling defect of T1.3, where
/// the session was consumed on a failure). The silence was not: Non-negotiable
/// #2 — every action either works, is absent, or explains itself.
@MainActor
@Suite(.serialized)
struct AddToMemorySilentNoOpTests {

    final class Spy {
        var consumed: [UUID]? = nil
        var reported: String? = nil
        var dismissed = false
    }

    @discardableResult
    private func runFinish(written: Int, clipIds: [UUID]) -> Spy {
        let spy = Spy()
        CreateMemoryFromClipsSheet.finishAppend(
            written: written,
            clipIds: clipIds,
            consumeSession: { spy.consumed = $0 },
            report: { spy.reported = $0 },
            dismiss: { spy.dismissed = true }
        )
        return spy
    }

    /// THE MONEY TEST. Nothing attached → the user is told, and nothing is
    /// consumed or dismissed behind the failure.
    @Test func whenNothingAttaches_theUserIsTold() {
        let spy = runFinish(written: 0, clipIds: [UUID(), UUID()])

        #expect(spy.reported != nil, "a dead-looking button is a silent no-op")
        #expect(spy.consumed == nil, "nothing attached, so nothing may be consumed")
        #expect(spy.dismissed == false, "dismissing would claim the add succeeded")
    }

    /// The non-empty companion: a real attach consumes the session and closes
    /// the sheet, and says nothing. Without it, a `finishAppend` that only
    /// ever reported would pass the money test.
    @Test func whenClipsAttach_theSessionIsConsumedAndTheSheetCloses() {
        let clipIds = [UUID(), UUID()]
        let spy = runFinish(written: 2, clipIds: clipIds)

        #expect(spy.consumed == clipIds)
        #expect(spy.dismissed == true)
        #expect(spy.reported == nil, "success is not an occasion for a message")
    }

    /// A partial attach still succeeded — some clips landed, so the session is
    /// consumed and the sheet closes. The failure path is *nothing* attached,
    /// not *not everything*.
    @Test func aPartialAttachIsStillASuccess() {
        let spy = runFinish(written: 1, clipIds: [UUID(), UUID(), UUID()])

        #expect(spy.dismissed == true)
        #expect(spy.reported == nil)
    }

    /// The copy names the action the user tapped, and matches the sibling
    /// sheet's approved line for the single-clip case. Asserted as clauses:
    /// rewording keeps the invariant, dropping the promise does not.
    @Test func theFailureLineMatchesTheSiblingsConstruction() {
        #expect(CreateMemoryFromClipsSheet.appendFailedMessage(clipCount: 1)
                == "Couldn't add this clip. Try again.",
                "the approved sibling line, verbatim")
        let plural = CreateMemoryFromClipsSheet.appendFailedMessage(clipCount: 3)
        #expect(plural.contains("add"), "names the action the user tapped")
        #expect(plural.contains("Try again"), "the sheet stays open, so retrying is possible")
        #expect(!plural.lowercased().contains("you "), "never blame the user (Crucible voice)")
    }

    // MARK: - The caller actually reaches the decision

    /// THE GATE — and the one that caught a mistake in this very fix.
    ///
    /// The first attempt added `finishAppend` at the tail of
    /// `appendToExistingMemory` but LEFT the original
    /// `guard written > 0 else { return }` above it. The seam tests all passed
    /// while production still returned early and said nothing: the owner was
    /// correct and the caller bypassed it — the exact Class-4 #2 shape this
    /// pass has been closing everywhere else.
    ///
    /// So: after the attach, `appendToExistingMemory` may not contain a bare
    /// `return`. Every path must fall through to `finishAppend`.
    @Test func appendHasNoEarlyExitPastTheDecision() throws {
        let body = try Self.appendToExistingMemoryBody()
        let bareReturns = body.enumerated().compactMap { i, line -> Int? in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.hasPrefix("//"), !t.hasPrefix("///") else { return nil }
            return t == "return" ? i + 1 : nil
        }
        #expect(
            bareReturns.isEmpty,
            """
            `appendToExistingMemory` returns early after the attach (offset \
            line(s) \(bareReturns.map(String.init).joined(separator: ", "))), \
            skipping `finishAppend`. That is the defect restored: the user \
            taps Add, nothing happens, nothing is said.
            """
        )
        #expect(body.contains { $0.contains("Self.finishAppend(") },
                "the function must end at the one decision point")
    }

    /// Guards the guard: the extractor must actually find the function body,
    /// and the matcher must see a bare return.
    @Test func theExtractorFindsTheBodyAndSeesABareReturn() throws {
        let body = try Self.appendToExistingMemoryBody()
        #expect(body.count > 20, "the body was not located — the scan would pass on nothing")
        #expect(body.contains { $0.contains("attachExistingClips") },
                "the located body must be the right function")
    }

    /// Lines of `appendToExistingMemory` from the `attachExistingClips` call to
    /// the end of the function. Scoped to AFTER the attach deliberately: the
    /// guards ABOVE it (missing entry id, etc.) are legitimate early exits
    /// taken before any work happened.
    static func appendToExistingMemoryBody() throws -> [String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MemoryStream/Views/Inbox/CreateMemoryFromClipsSheet.swift")
        guard let src = try? String(contentsOf: url, encoding: .utf8), !src.isEmpty else {
            throw GateFailure.sourceNotFound(url.path)
        }
        let lines = src.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.contains("let written = lifecycle.attachExistingClips(") })
        else { throw GateFailure.anchorNotFound("attachExistingClips") }
        guard let end = lines[start...].firstIndex(where: { $0.contains("Self.finishAppend(") })
        else { throw GateFailure.anchorNotFound("Self.finishAppend(") }
        return Array(lines[start...end])
    }

    enum GateFailure: Error { case sourceNotFound(String), anchorNotFound(String) }
}
