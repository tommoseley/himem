import Testing
import Foundation
@testable import HiMem

/// **The waiting stack** — `HiMem · Transient capture.html` (CURRENT).
///
/// The spec's central claim is that this is *"a stack of one, not a list of
/// many"*, and that the difference from the deleted bench is **structural
/// rather than promised**: you cannot survey, sort, filter or multi-select a
/// stack of one, so those features are unbuildable rather than declined.
///
/// These pin the rules that make that true.
@Suite struct TransientCaptureTests {

    private func clip(_ text: String, minutesAgo: Int,
                      status: InboxClip.Status = .transcribed,
                      recycledAt: Date? = nil) -> InboxClip {
        InboxClip(
            clipId: UUID(),
            capturedAt: Date(timeIntervalSince1970: 1_780_000_000 - Double(minutesAgo) * 60),
            duration: 5, transcript: text,
            latitude: nil, longitude: nil,
            source: "watch", audioFilename: "a.caf",
            transcriptionAttempted: true, rollGroupId: nil,
            status: status, recycledAt: recycledAt
        )
    }

    // MARK: - What waits

    @Test("newest first")
    func newestFirst() {
        let w = TransientCaptureStack.waiting(from: [
            clip("older", minutesAgo: 30),
            clip("newest", minutesAgo: 1),
            clip("middle", minutesAgo: 10),
        ])
        #expect(w.map(\.transcript) == ["newest", "middle", "older"])
    }

    /// A clip still transferring or still being transcribed is **in flight**,
    /// not waiting on her. Surfacing it would ask her to decide about
    /// something she cannot read yet.
    @Test("only transcribed captures wait on her")
    func onlyTranscribedWait() {
        let w = TransientCaptureStack.waiting(from: [
            clip("ready", minutesAgo: 1),
            clip("still arriving", minutesAgo: 2, status: .received),
        ])
        #expect(w.map(\.transcript) == ["ready"])
    }

    /// She already discarded those.
    @Test("discarded captures do not come back")
    func discardedStayGone() {
        let w = TransientCaptureStack.waiting(from: [
            clip("kept", minutesAgo: 1),
            clip("discarded", minutesAgo: 2, recycledAt: Date()),
        ])
        #expect(w.map(\.transcript) == ["kept"])
    }

    /// **The load-bearing one.** Nothing waiting must produce nothing at all —
    /// this is what separates the transient surface from the bench.
    @Test("nothing waiting is an empty stack, not an empty list to render")
    func nothingWaiting() {
        #expect(TransientCaptureStack.waiting(from: []).isEmpty)
        #expect(TransientCaptureStack.head(of: []) == nil)
        #expect(TransientCaptureStack.moreAfterThis(totalWaiting: 0) == nil)
    }

    @Test("one at a time — the head is what is shown")
    func oneAtATime() {
        let w = TransientCaptureStack.waiting(from: [
            clip("a", minutesAgo: 3), clip("b", minutesAgo: 2), clip("c", minutesAgo: 1),
        ])
        #expect(TransientCaptureStack.head(of: w)?.transcript == "c")
    }

    // MARK: - The count is scope, not a badge

    @Test("the count sizes the errand")
    func theCount() {
        #expect(TransientCaptureStack.moreAfterThis(totalWaiting: 3) == "2 more after this")
        #expect(TransientCaptureStack.moreAfterThis(totalWaiting: 2) == "1 more after this")
    }

    /// "0 more after this" is noise. The count exists to size the errand, not
    /// to be reported — and a number that always shows is a number she learns
    /// to stop reading.
    @Test("a lone capture carries no count")
    func loneCaptureHasNoCount() {
        #expect(TransientCaptureStack.moreAfterThis(totalWaiting: 1) == nil)
        #expect(TransientCaptureStack.moreAfterThis(totalWaiting: 0) == nil)
    }

    // MARK: - The exits

    @Test("three outcomes, and no fourth")
    func threeOutcomes() {
        let c = TransientCapture(clipId: UUID(), transcript: "the pears were good",
                                 capturedAt: Date(), placeName: nil)
        #expect(TransientCaptureStack.exits(for: c) == [.addToMemory, .startNewMemory, .discard])
    }

    /// **Heard nothing has two exits, and the asymmetry is correct.** There is
    /// no recoverable text, so there is nothing to add to an existing memory;
    /// manufacturing an object to keep the symmetry would be worse.
    @Test("heard nothing offers two exits, not three")
    func heardNothingHasTwoExits() {
        for empty in ["", "   ", "\n\t "] {
            let c = TransientCapture(clipId: UUID(), transcript: empty,
                                     capturedAt: Date(), placeName: nil)
            #expect(c.heardNothing)
            #expect(TransientCaptureStack.exits(for: c) == [.startNewMemory, .discard],
                    "an empty transcript must not offer 'Add to a memory'")
        }
    }

    @Test("a capture with words is not heard-nothing")
    func wordsAreNotSilence() {
        let c = TransientCapture(clipId: UUID(), transcript: "a", capturedAt: Date(), placeName: nil)
        #expect(!c.heardNothing)
    }

    /// *"From your Watch"* is reassurance here: what she said reached the
    /// phone. The audio is already gone — the recording was transport — so the
    /// copy must not offer a replay or a retry.
    @Test("the heard-nothing copy reassures and promises no retry")
    func heardNothingCopy() {
        let t = TransientCaptureStack.heardNothingText
        #expect(t.contains("From your Watch"))
        #expect(t.contains("didn't catch any words"))
        for forbidden in ["again", "retry", "replay", "listen"] {
            #expect(!t.lowercased().contains(forbidden),
                    "the audio is gone; the copy must not imply it can be re-heard: \(t)")
        }
    }
}
