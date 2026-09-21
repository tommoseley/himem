import Testing
import Foundation
import CoreData
@testable import HiMem

/// **A roll arrives as ONE memory** — `On a roll · spec.md` (CURRENT,
/// rewritten 2026-09-20):
///
/// > A roll arrives on the phone as one memory. Its transcripts are joined in
/// > order, and the tap boundaries become **paragraph breaks** — which is what
/// > she meant by tapping Next. Nothing in the interface names a roll; the join
/// > key produces paragraphs and then disappears.
///
/// and, on the mechanism:
///
/// > `rollGroupId` is stamped at recording-session start and preserved across
/// > taps. On arrival it is a **deterministic override** of the time/place
/// > session heuristics — same roll, same memory, regardless of the gap
/// > between taps.
///
/// **The defect these reproduce.** §1 rewrote `materialize` to create a
/// `JournalEntry` per arrived clip and never read `rollGroupId` — so someone
/// who tapped Next four times, deliberately keeping one train of thought
/// together, got **five memories** and the tapping actively made it worse.
/// Found by the data-migration audit, confirmed against CURRENT authority
/// 2026-09-20, ruled to be fixed before the deletion slice because
/// `ClipSessionGrouper` — the only code that knows how to turn a `rollGroupId`
/// into one session — dies in that slice.
@MainActor
@Suite(.serialized)
struct WatchRollArrivesAsOneMemoryTests {

    private func context() -> NSManagedObjectContext {
        // Shares the one production `cachedModel`; store stays per-test.
        StorageService(inMemory: true).viewContext
    }

    private func clip(_ text: String, at offset: TimeInterval, roll: UUID?,
                      base: Date) -> InboxClip {
        InboxClip(
            clipId: UUID(),
            capturedAt: base.addingTimeInterval(offset),
            duration: 5,
            transcript: text,
            latitude: nil, longitude: nil,
            source: "watch",
            audioFilename: "",
            transcriptionAttempted: true,
            rollGroupId: roll,
            status: .transcribed
        )
    }

    private func entries(in ctx: NSManagedObjectContext) -> [JournalEntry] {
        let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return (try? ctx.fetch(req)) ?? []
    }

    // MARK: - The money test

    /// **THE RED.** Three taps of Next, one train of thought, one memory.
    @Test("a three-tap roll becomes one memory, not three")
    func rollBecomesOneMemory() {
        let ctx = context()
        let roll = UUID()
        let base = Date(timeIntervalSince1970: 1_780_000_000)
        let clips = [
            clip("Notes from the wharf about the afternoon plan.", at: 0, roll: roll, base: base),
            clip("More from the wharf, watching the boats come in.", at: 20, roll: roll, base: base),
            clip("Last one before heading home.", at: 40, roll: roll, base: base),
        ]

        ArrivedClipMaterializer.materialize(clips, in: ctx, deleteAudio: { _ in true })

        let made = entries(in: ctx)
        #expect(made.count == 1, """
            A roll produced \(made.count) memories. `On a roll · spec.md` is explicit \
            that a roll arrives as ONE memory — tapping Next is how she keeps a train \
            of thought together, so splitting it punishes the behaviour it exists for.
            """)
        #expect(made.first?.content == """
            Notes from the wharf about the afternoon plan.

            More from the wharf, watching the boats come in.

            Last one before heading home.
            """, "tap boundaries become paragraph breaks, joined in capture order")
    }

    /// The roll's memory is stamped when the roll *started*, not when its last
    /// tap landed — the memory is the sitting, not the final fragment.
    @Test("the memory carries the roll's start time")
    func createdAtIsTheRollStart() {
        let ctx = context()
        let roll = UUID()
        let base = Date(timeIntervalSince1970: 1_780_000_000)
        ArrivedClipMaterializer.materialize([
            clip("second", at: 20, roll: roll, base: base),
            clip("first", at: 0, roll: roll, base: base),
        ], in: ctx, deleteAudio: { _ in true })

        let made = entries(in: ctx)
        // Count asserted too: sorted-ascending `first` would read `base`
        // even if the roll had split into two memories, so without this the
        // test passes under the very defect it accompanies.
        #expect(made.count == 1)
        #expect(made.first?.createdAt == base)
    }

    /// Order comes from capture time, not from the order the transfers landed.
    /// Each tap is its own transfer unit with no transaction around the roll,
    /// so arrival order is not a promise the transport makes.
    @Test("transcripts join in capture order, not arrival order")
    func joinsInCaptureOrder() {
        let ctx = context()
        let roll = UUID()
        let base = Date(timeIntervalSince1970: 1_780_000_000)
        ArrivedClipMaterializer.materialize([
            clip("third", at: 40, roll: roll, base: base),
            clip("first", at: 0, roll: roll, base: base),
            clip("second", at: 20, roll: roll, base: base),
        ], in: ctx, deleteAudio: { _ in true })

        #expect(entries(in: ctx).first?.content == "first\n\nsecond\n\nthird")
    }

    /// *"If 3 of 5 arrive, they form the memory and the remaining 2 join it
    /// when they land."* — the spec's own partial-arrival case. The late taps
    /// must reach the SAME memory, which is what makes `rollGroupId` the
    /// memory's identity rather than the first clip's id.
    @Test("late taps join the memory the earlier ones made")
    func lateArrivalsJoinTheSameMemory() {
        let ctx = context()
        let roll = UUID()
        let base = Date(timeIntervalSince1970: 1_780_000_000)

        ArrivedClipMaterializer.materialize([
            clip("first", at: 0, roll: roll, base: base),
            clip("second", at: 20, roll: roll, base: base),
        ], in: ctx, deleteAudio: { _ in true })
        #expect(entries(in: ctx).count == 1)

        ArrivedClipMaterializer.materialize([
            clip("third", at: 40, roll: roll, base: base),
        ], in: ctx, deleteAudio: { _ in true })

        let made = entries(in: ctx)
        #expect(made.count == 1, "a late tap created a second memory instead of joining the roll's")
        #expect(made.first?.content == "first\n\nsecond\n\nthird")
    }

    /// The everyday case must not regress: a single tap with no roll is still
    /// one memory, and still keyed by its own clip id so the drain stays
    /// idempotent and two devices converge on one CloudKit record.
    @Test("an un-rolled capture is unchanged")
    func singleCaptureIsUnchanged() {
        let ctx = context()
        let base = Date(timeIntervalSince1970: 1_780_000_000)
        let solo = clip("just the one thought", at: 0, roll: nil, base: base)
        ArrivedClipMaterializer.materialize([solo], in: ctx, deleteAudio: { _ in true })

        let made = entries(in: ctx)
        #expect(made.count == 1)
        #expect(made.first?.id == solo.clipId)
        #expect(made.first?.content == "just the one thought")
    }

    /// Two different rolls in one drain are two memories — the grouping must
    /// key on the roll, not merge everything it is handed.
    @Test("separate rolls stay separate")
    func distinctRollsDoNotMerge() {
        let ctx = context()
        let base = Date(timeIntervalSince1970: 1_780_000_000)
        let a = UUID(), b = UUID()
        ArrivedClipMaterializer.materialize([
            clip("a1", at: 0, roll: a, base: base),
            clip("a2", at: 10, roll: a, base: base),
            clip("b1", at: 900, roll: b, base: base),
            clip("solo", at: 1800, roll: nil, base: base),
        ], in: ctx, deleteAudio: { _ in true })

        #expect(entries(in: ctx).count == 3)
    }

    /// A tap that transcribed to nothing must not leave a blank paragraph —
    /// the join is of what she said, and an empty run would read as a gap she
    /// did not make.
    @Test("a silent tap does not become an empty paragraph")
    func silentTapsAreNotJoined() {
        let ctx = context()
        let roll = UUID()
        let base = Date(timeIntervalSince1970: 1_780_000_000)
        ArrivedClipMaterializer.materialize([
            clip("first", at: 0, roll: roll, base: base),
            clip("", at: 20, roll: roll, base: base),
            clip("third", at: 40, roll: roll, base: base),
        ], in: ctx, deleteAudio: { _ in true })

        #expect(entries(in: ctx).first?.content == "first\n\nthird")
    }

    /// **The title stays untouched on this path** — it is automatic, and
    /// `TitleAuthorshipTests` scans for any write to `entry.title` outside a
    /// user-initiated one. Pinned here too because the roll fix rewrites the
    /// function that scan protects.
    @Test("the roll path never authors a title")
    func noTitleIsWritten() {
        let ctx = context()
        let roll = UUID()
        let base = Date(timeIntervalSince1970: 1_780_000_000)
        ArrivedClipMaterializer.materialize([
            clip("one", at: 0, roll: roll, base: base),
            clip("two", at: 20, roll: roll, base: base),
        ], in: ctx, deleteAudio: { _ in true })

        #expect(entries(in: ctx).first?.title == nil)
    }
}
