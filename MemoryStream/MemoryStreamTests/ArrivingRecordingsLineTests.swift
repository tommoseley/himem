import Testing
import Foundation
@testable import HiMem

/// The paperclip's foot-of-sheet line for recordings that exist but are not
/// yet selectable.
///
/// `AddExistingClipsSheet` lists zero-edge `MediaReference`s. A Watch recording
/// becomes one only once it has fully arrived and transcribed, so an in-flight
/// recording is absent from the list. While the Clips bench existed that was
/// covered — the bench showed arrival state. The vocabulary retirement deletes
/// the bench, and then the absence is unexplained: she recorded something, it
/// is not in the list, nothing says why. Ruled a "safe but unseen" failure
/// (Tom, 2026-09-16).
///
/// These tests pin the PROMISE (the state is named, and only when it is true),
/// not the sentence — per CLAUDE.md § Assert the Meaning, Not the Phrasing.
/// The one literal that IS pinned is the absence of apology/progress language,
/// because that posture is the subject of the ruling rather than its phrasing.
@Suite struct ArrivingRecordingsLineTests {

    private func clip(_ status: InboxClip.Status, id: UUID = UUID()) -> InboxClip {
        InboxClip(
            clipId: id,
            capturedAt: Date(),
            duration: 2,
            transcript: "",
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: "\(id.uuidString).caf",
            transcriptionAttempted: false,
            rollGroupId: nil,
            status: status
        )
    }

    // MARK: - Absent when nothing is arriving

    @Test("no line when the manifest is empty")
    func noLineWhenEmpty() {
        #expect(AddExistingClipsSheet.arrivingLine(clips: []) == nil)
    }

    @Test("no line when every clip has already drained into a ref")
    func noLineWhenAllTranscribed() {
        let clips = [clip(.transcribed), clip(.transcribed)]
        #expect(AddExistingClipsSheet.arrivingLine(clips: clips) == nil)
    }

    @Test("tombstones are not recordings and never produce a line")
    func disposedIsNotArriving() {
        #expect(AddExistingClipsSheet.arrivingLine(clips: [clip(.disposed), clip(.disposed)]) == nil)
    }

    // MARK: - Present, and counting the right set

    @Test("every in-flight status counts as arriving")
    func allInFlightStatusesCount() throws {
        for status in [InboxClip.Status.announced, .received, .transcribing] {
            let line = try #require(
                AddExistingClipsSheet.arrivingLine(clips: [clip(status)]),
                "\(status) is in flight and must be named"
            )
            #expect(line.contains("1"))
        }
    }

    @Test("the count describes only the arriving set, not the whole manifest")
    func countExcludesDrainedAndDisposed() throws {
        // The 2026-08-10 lock: a count must describe the thing it sits on.
        // This line sits under a list of selectable recordings and speaks for
        // the ones NOT in it — so transcribed and disposed rows must not
        // inflate it.
        let clips = [
            clip(.announced), clip(.transcribing),   // 2 arriving
            clip(.transcribed), clip(.transcribed),  // drained — in the list above
            clip(.disposed)                          // tombstone
        ]
        let line = try #require(AddExistingClipsSheet.arrivingLine(clips: clips))
        #expect(line.contains("2"), "expected the arriving count (2), got: \(line)")
        #expect(!line.contains("5"), "the line must not count the whole manifest: \(line)")
        #expect(!line.contains("3"), "the line must not count drained rows: \(line)")
    }

    @Test("singular and plural both read naturally")
    func singularAndPlural() throws {
        let one = try #require(AddExistingClipsSheet.arrivingLine(clips: [clip(.received)]))
        let two = try #require(AddExistingClipsSheet.arrivingLine(clips: [clip(.received), clip(.received)]))
        #expect(one.contains("1"))
        #expect(two.contains("2"))
    }

    // MARK: - Posture — this is the subject of the ruling, so it is pinned

    @Test("the line names the state without apologising or dramatising it")
    func postureIsNamedNotApologised() throws {
        let line = try #require(AddExistingClipsSheet.arrivingLine(clips: [clip(.transcribing)]))
        let lowered = line.lowercased()

        // Crucible: never apologise, never blame, no error register.
        for banned in ["sorry", "unable", "failed", "error", "problem", "wait"] {
            #expect(!lowered.contains(banned), "arriving line must not apologise: \(line)")
        }
        // No progress vocabulary — the ruling is explicit that there is no
        // spinner and no progress bar, so the copy must not imply one.
        for banned in ["%", "loading", "downloading", "progress"] {
            #expect(!lowered.contains(banned), "arriving line must not dramatise: \(line)")
        }
        // It describes arrival, which is the state being named.
        #expect(lowered.contains("arriv"), "the line must name the state: \(line)")
    }
}
