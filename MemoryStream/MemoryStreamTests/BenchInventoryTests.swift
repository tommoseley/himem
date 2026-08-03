import Testing
import Foundation
@testable import HiMem

/// **The two-store boundary, tested behaviourally** (C2 rebuild step 2).
///
/// This mapping was flagged before it was written as the highest-risk part of
/// the rebuild: the bench is backed by a device-local manifest AND
/// CloudKit-synced refs, review state lives in one place for each, and they
/// must resolve into ONE set. If that resolution is wrong the New lens is
/// wrong and **the failure is silent** — nothing crashes, a clip is simply in
/// the wrong lens.
///
/// Every wiring defect on this bench has had that shape, so this suite tests
/// the mapping itself rather than only testing `RenderedBench.compose`
/// downstream of it.
@Suite struct BenchInventoryTests {

    // MARK: - Refs win on collision, and review follows the same precedence

    /// `composeBenchClips` writes manifest rows first and lets refs overwrite
    /// by id. A materialized clip exists in BOTH stores during the overlap,
    /// so a rule is required rather than an accident of ordering.
    @Test func aMaterializedClipIsCountedOnceAndTheRefWins() {
        let id = UUID()
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let r = BenchInventory.compose(
            manifestClips: [Self.clip(id: id, at: t, reviewed: false)],
            refs: [Self.ref(id: id, kind: .voice, at: t.addingTimeInterval(5))],
            refIsReviewed: { _ in false }
        )
        #expect(r.items.count == 1, "the same clip appeared twice — once per store")
        #expect(r.items[0].capturedAt == t.addingTimeInterval(5), "the manifest row won; the ref is the source of truth")
    }

    /// **The silent-failure case.** Manifest says unseen, ref store says seen.
    /// If precedence differs between the item and its review state, the clip
    /// is in the lens by one rule and out by the other.
    @Test func reviewPrecedenceMatchesItemPrecedence() {
        let id = UUID()
        let t = Date(timeIntervalSince1970: 1_785_000_000)

        let refSaysSeen = BenchInventory.compose(
            manifestClips: [Self.clip(id: id, at: t, reviewed: false)],
            refs: [Self.ref(id: id, kind: .voice, at: t)],
            refIsReviewed: { _ in true }
        )
        #expect(refSaysSeen.reviewedIds == [id],
                "the ref won for the item but not for its review state — the two stores disagree about one clip")

        let refSaysUnseen = BenchInventory.compose(
            manifestClips: [Self.clip(id: id, at: t, reviewed: true)],
            refs: [Self.ref(id: id, kind: .voice, at: t)],
            refIsReviewed: { _ in false }
        )
        #expect(refSaysUnseen.reviewedIds.isEmpty,
                "a stale manifest `reviewed` survived materialization")
    }

    /// The end-to-end consequence, since the point of the mapping is the lens:
    /// a clip the ref store calls seen must leave New (once its window closes).
    @Test func theLensAgreesWithTheResolvedReviewState() {
        let id = UUID()
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let inv = BenchInventory.compose(
            manifestClips: [Self.clip(id: id, at: t, reviewed: false)],
            refs: [Self.ref(id: id, kind: .voice, at: t)],
            refIsReviewed: { _ in true }
        )
        let bench = RenderedBench.compose(
            allItems: inv.items, reviewedIds: inv.reviewedIds, hideReviewed: true,
            now: t.addingTimeInterval(ClipSessionGrouper.sessionTimeWindowSeconds + 1)
        )
        #expect(bench.count == 0, "a clip the ref store calls seen is still on the New lens")
    }

    // MARK: - Kinds

    /// The manifest is voice by construction; refs carry their own kind. This
    /// is where media stops being a special case.
    @Test func kindsSurviveTheBoundary() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let r = BenchInventory.compose(
            manifestClips: [Self.clip(id: UUID(), at: t, reviewed: false)],
            refs: [
                Self.ref(id: UUID(), kind: .image, at: t),
                Self.ref(id: UUID(), kind: .video, at: t),
                Self.ref(id: UUID(), kind: .note,  at: t),
            ],
            refIsReviewed: { _ in false }
        )
        #expect(Set(r.items.map(\.kind)) == [.voice, .image, .video, .note])
        #expect(r.items.count == 4, "the union is not voice-only any more")
    }

    // MARK: - Preserved oddity, pinned so a change is deliberate

    /// A ref with no `createdAt` sinks to the epoch, matching
    /// `ArrivedClipMaterializer.syntheticClip`. Inherited behaviour, pinned
    /// rather than silently improved — such an item groups alone in 1970,
    /// which is visible, and changing it needs its own evidence.
    @Test func aRefWithNoDateSinksToTheEpoch() {
        let r = BenchInventory.compose(
            manifestClips: [],
            refs: [Self.ref(id: UUID(), kind: .image, at: nil)],
            refIsReviewed: { _ in false }
        )
        #expect(r.items[0].capturedAt == Date(timeIntervalSince1970: 0))
    }

    // MARK: - Shape

    @Test func rollGroupSurvivesFromBothStores() {
        let roll = UUID()
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let r = BenchInventory.compose(
            manifestClips: [Self.clip(id: UUID(), at: t, reviewed: false, roll: roll)],
            refs: [Self.ref(id: UUID(), kind: .voice, at: t, roll: roll)],
            refIsReviewed: { _ in false }
        )
        #expect(r.items.allSatisfy { $0.rollGroupId == roll },
                "on-a-roll grouping is lost at the boundary")
    }

    @Test func anEmptyInventoryIsEmpty() {
        let r = BenchInventory.compose(manifestClips: [], refs: [], refIsReviewed: { _ in true })
        #expect(r.items.isEmpty && r.reviewedIds.isEmpty)
    }

    /// Bound the other side: a mapper that marked everything reviewed would
    /// pass several assertions above while emptying the lens.
    @Test func unreviewedItemsAreNotMarkedReviewed() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let r = BenchInventory.compose(
            manifestClips: [Self.clip(id: UUID(), at: t, reviewed: false)],
            refs: [Self.ref(id: UUID(), kind: .image, at: t)],
            refIsReviewed: { _ in false }
        )
        #expect(r.reviewedIds.isEmpty)
        #expect(r.items.count == 2)
    }

    // MARK: - Fixtures

    static func clip(id: UUID, at: Date, reviewed: Bool, roll: UUID? = nil) -> InboxClip {
        InboxClip(
            clipId: id, capturedAt: at, duration: 5, transcript: "",
            latitude: nil, longitude: nil, source: "phone",
            audioFilename: "inv-\(id.uuidString).m4a",
            transcriptionAttempted: true, rollGroupId: roll, reviewed: reviewed
        )
    }

    static func ref(id: UUID, kind: BenchClipItem.Kind, at: Date?, roll: UUID? = nil) -> BenchRefDescriptor {
        BenchRefDescriptor(id: id, kind: kind, createdAt: at, rollGroupId: roll)
    }
}
