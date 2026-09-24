import Foundation

/// **A capture that has arrived and is waiting for her to decide.**
///
/// `HiMem · Transient capture.html` (CURRENT). Raising your wrist and saying
/// *"the casing on the knockwurst had much more snap"* is **"don't lose
/// this,"** not **"make a new memory"** — and forcing the second moves a
/// decision from the user to the software, which is the opposite of the
/// principle driving the whole descoping.
///
/// **A stack of one, not a list of many.** The spec's own framing, and the
/// reason this type exposes a `head` rather than a collection to render:
///
/// > You cannot survey, sort, filter or multi-select a stack of one — so
/// > those features are **unbuildable rather than declined**, which is the
/// > only durable way to keep them out.
///
/// That is the line between this and the bench we deleted. The bench was a
/// *workbench*; this is a short queue that is empty most of the time and has
/// three exits.
struct TransientCapture: Equatable, Identifiable {
    let clipId: UUID
    let transcript: String
    let capturedAt: Date
    /// Where the Watch was when she spoke, when we have it.
    let placeName: String?

    var id: UUID { clipId }

    /// **Transcription ran and found no words.** Not an error and not an
    /// empty row: the spec gives this case its own copy and *two* exits
    /// rather than three, because there is no recoverable text to add to an
    /// existing memory.
    var heardNothing: Bool {
        transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The pure decisions behind the waiting card. Free of SwiftUI and of
/// Core Data so the rules can be exercised as a table.
enum TransientCaptureStack {

    /// What is waiting, **newest first**.
    ///
    /// Only `.transcribed` rows qualify. A clip still transferring or still
    /// being transcribed is *in flight*, not waiting on her — surfacing it
    /// would ask her to decide about something she cannot yet read.
    /// Recycled rows are excluded: she already discarded those.
    static func waiting(from clips: [InboxClip]) -> [TransientCapture] {
        clips
            .filter { $0.status == .transcribed && $0.recycledAt == nil }
            .sorted { $0.capturedAt > $1.capturedAt }
            .map {
                TransientCapture(clipId: $0.clipId,
                                 transcript: $0.transcript,
                                 capturedAt: $0.capturedAt,
                                 placeName: nil)
            }
    }

    /// **The one being shown.** Handling it reveals the next.
    static func head(of waiting: [TransientCapture]) -> TransientCapture? {
        waiting.first
    }

    /// **Scope, on the card she is already looking at — never a badge.**
    ///
    /// > "2 more after this" tells her whether this is a one-tap errand or a
    /// > few minutes, and hiding it makes her guess. A number on a tab, a
    /// > list header, or anywhere that follows her is an **obligation to zero
    /// > out**, which is the guilt-inbox the North Star rejects.
    ///
    /// `nil` when this is the only one — "0 more after this" is noise, and
    /// the count exists to size the errand, not to be reported.
    static func moreAfterThis(totalWaiting: Int) -> String? {
        let remaining = totalWaiting - 1
        guard remaining > 0 else { return nil }
        return remaining == 1 ? "1 more after this" : "\(remaining) more after this"
    }

    /// **The exits, and there is no fourth.**
    ///
    /// No "decide later" — waiting is already the default, so an explicit
    /// defer would be a button that does what doing nothing does.
    enum Exit: Equatable {
        /// Ochre. Joins a memory that already exists.
        case addToMemory
        /// This capture becomes the writing of a new memory.
        case startNewMemory
        /// Quiet tertiary, never a peer of the two keeps. Recoverable.
        case discard
    }

    /// Which exits this capture offers.
    ///
    /// **Heard-nothing has two, and the asymmetry is correct.** There is no
    /// text to add to an existing memory, and manufacturing an object to keep
    /// the symmetry would be worse than the gap.
    static func exits(for capture: TransientCapture) -> [Exit] {
        capture.heardNothing
            ? [.startNewMemory, .discard]
            : [.addToMemory, .startNewMemory, .discard]
    }

    /// What the card says when transcription found no words.
    ///
    /// *"From your Watch"* stays because here it is **reassurance**: what she
    /// said reached the phone, and HiMem could not make out the words. The
    /// audio is already gone — the recording was transport — so there is
    /// nothing to replay and nothing to re-transcribe.
    static let heardNothingText = "From your Watch. We didn't catch any words."
}
