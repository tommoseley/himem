import Testing
import Foundation
@testable import HiMem

/// F23 · T1.3 — **"Start a Memory" could consume the session and create
/// nothing.**
///
/// `createMemoryFromExistingClips` returns nil when no ref resolved, rolling
/// its entry back so no empty memory is stranded
/// (`EntryLifecycleService.swift:786-791`). On that path
/// `CreateMemoryFromClipsSheet.createMemory()` skipped the `if let newId`
/// block — but `InboxManifest.shared.removeBatch(...)` (`:575` pre-fix) and
/// `dismiss()` (`:587` pre-fix) ran unconditionally. The session disappeared
/// from the bench, no memory existed to hold its clips, and nothing was said.
///
/// The session rows are the bench's record of those clips. Consuming them is
/// the destructive half of "Start a Memory" and may only happen once the
/// constructive half has actually succeeded.
///
/// The tail is injected (`finishCreate`) so this proves the real behaviour —
/// *was the session consumed?* — rather than restating `newId != nil`. It also
/// keeps the test off the `InboxManifest` singleton's on-disk rows.
@MainActor
@Suite(.serialized)
struct StartAMemorySessionSurvivalTests {

    /// Records what the tail actually did.
    final class Spy {
        var consumed: [UUID]? = nil
        var announced: UUID? = nil
        var reported: String? = nil
        var dismissed = false
    }

    @discardableResult
    private func runFinish(newMemoryId: UUID?, clipIds: [UUID]) -> Spy {
        let spy = Spy()
        CreateMemoryFromClipsSheet.finishCreate(
            newMemoryId: newMemoryId,
            clipIds: clipIds,
            consumeSession: { spy.consumed = $0 },
            announce: { spy.announced = $0 },
            report: { spy.reported = $0 },
            dismiss: { spy.dismissed = true }
        )
        return spy
    }

    /// THE MONEY TEST. No memory was created → the session must still be on
    /// the bench and the sheet must still be open.
    @Test func whenNoMemoryIsCreated_theSessionIsNotConsumed() {
        let clipIds = [UUID(), UUID(), UUID()]
        let spy = runFinish(newMemoryId: nil, clipIds: clipIds)

        #expect(spy.consumed == nil, "the bench session is the only record of these clips")
        #expect(spy.dismissed == false, "dismissing reports a job done that wasn't")
        #expect(spy.announced == nil, "nothing to navigate to")
        #expect(spy.reported == CreateMemoryFromClipsSheet.creationFailedMessage,
                "no silent no-ops (Non-negotiable #2)")
    }

    /// The non-empty companion: on success the session IS consumed, the new
    /// memory is announced, and the sheet closes. Without this, a
    /// `finishCreate` that did nothing at all would pass the money test.
    @Test func whenTheMemoryIsCreated_theSessionIsConsumedAndTheSheetCloses() {
        let clipIds = [UUID(), UUID()]
        let newId = UUID()
        let spy = runFinish(newMemoryId: newId, clipIds: clipIds)

        #expect(spy.consumed == clipIds, "the session's clips, all of them")
        #expect(spy.announced == newId, "drives the 'Memory created' toast's View action")
        #expect(spy.dismissed == true)
        #expect(spy.reported == nil)
    }

    /// The copy names the object and offers the action that is actually
    /// available — the clips are still listed in the still-open sheet.
    /// Asserted as clauses, not as a sentence: rewording is a copy change,
    /// dropping the promise is a design change.
    @Test func theFailureLineNamesWhatDidNotHappen() {
        let line = CreateMemoryFromClipsSheet.creationFailedMessage
        #expect(line.contains("memory"), "names the object that wasn't created")
        #expect(line.contains("Try again"), "the sheet stays open, so retrying is possible")
        #expect(!line.lowercased().contains("you "), "never blame the user (Crucible voice)")
    }
}
