import Testing
import Foundation
@testable import HiMem

/// **Channel A · the arrival notification, stripped back** (Tom, 2026-09-16).
///
/// It is kept, not retired. Retiring it would mean she speaks into her Watch
/// and hears nothing ever again — the safe-but-unseen failure Judi named. A
/// recording arriving safely is **reassurance, not an obligation**, and Channel
/// A is already passive by lock: it never buzzes, never wakes the screen, and
/// is only a tappable handle.
///
/// Three things changed, and these tests pin all three:
///
/// 1. **No count.** *"N voice clips waiting"* is the guilt-inbox this product
///    rejects, and it used the retired word. Presence, not arithmetic.
/// 2. **Arrival, not obligation.** It tells her the words made it. Nothing is
///    waiting for her; nothing needs review.
/// 3. **It lands on Memories** — asserted separately, at the shell.
///
/// Per § *Assert the Meaning, Not the Phrasing*: these pin the PROMISES (no
/// number, no obligation, no retired vocabulary, arrival stated), not the
/// sentence. The copy may be reworded freely while all four hold.
@Suite struct ArrivalNotificationCopyTests {

    private var forms: [String] {
        [WatchInboxNotificationCoordinator.arrivalBody(multiple: false),
         WatchInboxNotificationCoordinator.arrivalBody(multiple: true)]
    }

    // MARK: - 1 · No count, in any form

    @Test("the body never contains a number")
    func noArithmeticAnywhere() {
        for body in forms {
            // Hoisted out of `#expect`: `contains(where:)` is `rethrows`, and
            // the macro expansion will not absorb that for us.
            let hasDigit = body.contains { $0.isNumber }
            #expect(!hasDigit, "presence, not arithmetic — got: \(body)")
        }
    }

    /// The structural half, and the reason this cannot regress: `arrivalBody`
    /// takes a **grammatical** fact, never a count. There is no number in scope
    /// to interpolate, so re-introducing one requires changing the signature —
    /// a visible act, not a quiet edit inside a string.
    @Test("the copy function is never handed a count to print")
    func theSignatureCannotRenderACount() {
        // Compiles only while the parameter is `multiple: Bool`. If someone
        // restores `count: Int`, this fails to build rather than silently
        // allowing "3 recordings are here."
        let _: (Bool) -> String = WatchInboxNotificationCoordinator.arrivalBody(multiple:)
    }

    // MARK: - 2 · Arrival, not obligation

    @Test("nothing is described as waiting for her")
    func noObligationVocabulary() {
        for body in forms {
            let lowered = body.lowercased()
            for banned in ["waiting", "review", "unread", "pending", "need", "should", "don't forget"] {
                #expect(!lowered.contains(banned),
                        "the notification must not create an obligation — '\(banned)' in: \(body)")
            }
        }
    }

    @Test("it states that the recording arrived")
    func statesArrival() {
        for body in forms {
            #expect(body.lowercased().contains("here"),
                    "it tells her the words made it — got: \(body)")
        }
    }

    // MARK: - 3 · Vocabulary

    @Test("the retired word never appears")
    func noRetiredVocabulary() {
        for body in forms {
            let lowered = body.lowercased()
            #expect(!lowered.contains("clip"), "'clip' has left the user's vernacular — got: \(body)")
            #expect(!lowered.contains("evidence"), "F7g — never in UI copy")
            #expect(!lowered.contains("part"),
                    "a part is what lives INSIDE a memory; an arriving Watch capture is a recording")
        }
    }

    @Test("it uses the Watch's word — recording")
    func usesRecording() {
        #expect(WatchInboxNotificationCoordinator.arrivalBody(multiple: false).lowercased().contains("recording"))
        #expect(WatchInboxNotificationCoordinator.arrivalBody(multiple: true).lowercased().contains("recording"))
    }

    // MARK: - Source-agnostic (the surviving July 2026 lock)

    @Test("the headline names no source")
    func sourceAgnostic() {
        // Unchanged by the retirement: captures arrive from more than one
        // place, so source is per-item metadata and never the headline.
        for body in forms {
            let lowered = body.lowercased()
            #expect(!lowered.contains("watch"))
            #expect(!lowered.contains("siri"))
        }
    }

    // MARK: - Grammar without arithmetic

    @Test("singular and plural agree without counting")
    func agreementWithoutCounting() {
        let one = WatchInboxNotificationCoordinator.arrivalBody(multiple: false)
        let many = WatchInboxNotificationCoordinator.arrivalBody(multiple: true)
        #expect(one != many, "agreement is grammar, not a number — the two forms differ")
        let neitherCounts = !one.contains { $0.isNumber } && !many.contains { $0.isNumber }
        #expect(neitherCounts)
    }
}
