import Testing
import Foundation
@testable import HiMem

/// **C2 rebuild, step 1 — the assertion that could not be written.**
///
/// Seven defects in one day, all the same shape: a number computed from a
/// different set than the one drawn. The audit found the reason and it was
/// not carelessness — **every bench composition term was `private` on a
/// SwiftUI struct**, so across 188 test files there were *zero* behavioural
/// invocations of any of them. "What the header counted equals what the
/// bench drew" was not untested; it was **inexpressible**. That is why the
/// F35–F44 guards were `String.contains` over source text, and why a
/// mutation harness later showed those guards staying green while four of
/// the fixed defects were fully restored — and failing on a
/// behaviour-preserving rename. Blind to wrong sets, hostile to right ones.
///
/// `RenderedBench.compose` is a pure function over explicit inputs, so the
/// invariant is now one assertion — `theHeaderCountIsWhatIsDrawn` below.
///
/// **Honest labelling (ADR-050): these are CONTRACT tests.** They were
/// written alongside a new type and passed on first run; there was no
/// red-first cycle, because the defect they prevent lives in code that does
/// not exist yet (the call sites, migrated in steps 2–4). They are
/// mutation-verified instead.
@Suite struct RenderedBenchTests {

    // MARK: - The invariant

    /// **THE assertion.** Everything the bench draws is either in a loose
    /// session or claimed by the cluster; the header counts the union. Seven
    /// defects violated this and none of them could be expressed as a test.
    @Test func theHeaderCountIsWhatIsDrawn() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let bench = RenderedBench.compose(
            allItems: [
                Self.item(.voice, t),
                Self.item(.image, t.addingTimeInterval(60)),
                Self.item(.voice, t.addingTimeInterval(3 * 3600)),
                Self.item(.video, t.addingTimeInterval(3 * 3600 + 30)),
            ],
            reviewedIds: [], hideReviewed: true, now: t.addingTimeInterval(60)
        )
        let drawn = bench.loose.flatMap(\.items).count + bench.clustered.count
        #expect(bench.count == drawn,
                "header says \(bench.count), bench draws \(drawn) — the defect class, as one assertion")
        #expect(bench.count == 4)
    }

    /// The same identity with a cluster in play — the case F40/F43/F44 each
    /// broke one term of.
    @Test func theIdentityHoldsWithAClusterAndATrim() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let voiceA = Self.item(.voice, t)
        let photo  = Self.item(.image, t.addingTimeInterval(60))
        let voiceB = Self.item(.voice, t.addingTimeInterval(3 * 3600))
        let proposal = Self.proposal(claiming: [voiceA.id])
        let bench = RenderedBench.compose(
            allItems: [voiceA, photo, voiceB],
            reviewedIds: [], hideReviewed: true, now: t.addingTimeInterval(60),
            proposals: [proposal],
            trim: [proposal.fingerprint.rawValue: [photo.id]]
        )
        let drawn = bench.loose.flatMap(\.items).count + bench.clustered.count
        #expect(bench.count == drawn)
    }

    // MARK: - Media is an item, not a special case

    /// A photo inside a voice clip's idle window is IN that session — not
    /// absorbed into it by a separate pass keyed on session id. This is the
    /// side channel dying.
    @Test func mediaSharesASessionWithVoiceByGrouping() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let bench = RenderedBench.compose(
            allItems: [Self.item(.voice, t), Self.item(.image, t.addingTimeInterval(60))],
            reviewedIds: [], hideReviewed: false, now: t
        )
        #expect(bench.sessions.count == 1)
        #expect(bench.sessions[0].items.count == 2)
    }

    /// Media outside the window is its own session — it does not attach to
    /// the nearest voice clip just because it is media.
    @Test func mediaOutsideTheWindowIsItsOwnSession() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let bench = RenderedBench.compose(
            allItems: [Self.item(.voice, t), Self.item(.image, t.addingTimeInterval(3 * 3600))],
            reviewedIds: [], hideReviewed: false, now: t
        )
        #expect(bench.sessions.count == 2)
    }

    /// A cluster's kept items include media, because media is an item. F40,
    /// F43 and F44 each added this to one more consumer by hand.
    @Test func keptItemsIncludeMedia() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let voice = Self.item(.voice, t)
        let photo = Self.item(.image, t.addingTimeInterval(60))
        let proposal = Self.proposal(claiming: [voice.id])
        let bench = RenderedBench.compose(
            allItems: [voice, photo], reviewedIds: [], hideReviewed: false,
            now: t, proposals: [proposal]
        )
        let kept = bench.keptItems(for: proposal, trim: [:])
        #expect(kept.count == 2, "the cluster's photo is missing from its kept items")
        #expect(kept.contains(where: { $0.kind == .image }))
    }


    /// **Found by mutation, not by design.** Deleting the trim filter from
    /// `keptItems` — the F44 defect exactly — passed this suite, because
    /// every other test called it with an empty trim so the filter was a
    /// no-op. The rebuild's own tests had the same weakness they replace:
    /// exercising a term without exercising the case that makes it matter.
    @Test func keptItemsExcludesWhatWasSetAside() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let voice = Self.item(.voice, t)
        let photo = Self.item(.image, t.addingTimeInterval(60))
        let proposal = Self.proposal(claiming: [voice.id])
        let bench = RenderedBench.compose(
            allItems: [voice, photo], reviewedIds: [], hideReviewed: false,
            now: t, proposals: [proposal],
            trim: [proposal.fingerprint.rawValue: [photo.id]]
        )
        let kept = bench.keptItems(for: proposal, trim: [proposal.fingerprint.rawValue: [photo.id]])
        #expect(kept.map(\.id) == [voice.id], "a set-aside item is still in the cluster's kept set")
        #expect(kept.contains(where: { $0.kind == .image }) == false)
    }

    // MARK: - Set-aside returns to the bench

    @Test func aSetAsideItemLandsInLooseRatherThanVanishing() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let a = Self.item(.voice, t)
        let b = Self.item(.voice, t.addingTimeInterval(60))
        let proposal = Self.proposal(claiming: [a.id, b.id])
        let bench = RenderedBench.compose(
            allItems: [a, b], reviewedIds: [], hideReviewed: false, now: t,
            proposals: [proposal],
            trim: [proposal.fingerprint.rawValue: [b.id]]
        )
        #expect(bench.clustered == [a.id])
        #expect(bench.loose.flatMap(\.items).map(\.id) == [b.id],
                "the set-aside item did not come back to the bench")
        #expect(bench.count == 2, "it is still on the bench, so it is still counted")
    }

    /// A fully-claimed session does not appear loose — the other side of the
    /// bound, so "everything is loose" cannot pass.
    @Test func aFullyClaimedSessionIsNotDrawnTwice() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let a = Self.item(.voice, t)
        let proposal = Self.proposal(claiming: [a.id])
        let bench = RenderedBench.compose(
            allItems: [a], reviewedIds: [], hideReviewed: false, now: t, proposals: [proposal]
        )
        #expect(bench.loose.isEmpty)
        #expect(bench.clustered == [a.id])
    }

    // MARK: - The lens (F36), now over items of every kind

    @Test func aReviewedItemStaysWhileItsSessionCouldStillGrow() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let seen = Self.item(.voice, t)
        let bench = RenderedBench.compose(
            allItems: [seen], reviewedIds: [seen.id], hideReviewed: true,
            now: t.addingTimeInterval(60)
        )
        #expect(bench.count == 1)
    }

    @Test func onceTheWindowPassesTheReviewedItemLeaves() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let seen = Self.item(.voice, t)
        let bench = RenderedBench.compose(
            allItems: [seen], reviewedIds: [seen.id], hideReviewed: true,
            now: t.addingTimeInterval(ClipSessionGrouper.sessionTimeWindowSeconds + 1)
        )
        #expect(bench.count == 0)
    }

    /// Session-relative, not item-relative — the distinction F36 turned on,
    /// now applying to media too.
    @Test func aSessionIsNotSplitAcrossLensesEvenAcrossKinds() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let voice = Self.item(.voice, t)
        let photo = Self.item(.image, t.addingTimeInterval(9 * 60))
        let bench = RenderedBench.compose(
            allItems: [voice, photo], reviewedIds: [voice.id, photo.id],
            hideReviewed: true, now: t.addingTimeInterval(11 * 60)
        )
        #expect(bench.count == 2, "the session split — one item aged out while its sibling did not")
    }

    // MARK: - Replaces regroupingHasExactlyOneOwner

    /// The retired guard counted a literal, so a differently-spelled second
    /// writer passed it. A pure function has nothing to regroup: composing
    /// twice from the same inputs yields the same value, which is the
    /// invariant that guard was reaching for.
    @Test func composingTwiceFromTheSameInputsYieldsTheSameValue() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let items = [Self.item(.voice, t), Self.item(.image, t.addingTimeInterval(60)),
                     Self.item(.voice, t.addingTimeInterval(4 * 3600))]
        let a = RenderedBench.compose(allItems: items, reviewedIds: [], hideReviewed: true, now: t)
        let b = RenderedBench.compose(allItems: items, reviewedIds: [], hideReviewed: true, now: t)
        #expect(a == b)
    }

    /// Input order must not change the answer — the grouper sorts, and a
    /// caller handing items newest-first must get the same bench.
    @Test func inputOrderDoesNotChangeTheBench() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let items = [Self.item(.voice, t), Self.item(.image, t.addingTimeInterval(60)),
                     Self.item(.voice, t.addingTimeInterval(4 * 3600))]
        let a = RenderedBench.compose(allItems: items, reviewedIds: [], hideReviewed: true, now: t)
        let b = RenderedBench.compose(allItems: items.reversed(), reviewedIds: [], hideReviewed: true, now: t)
        #expect(a.count == b.count)
        #expect(Set(a.clustered) == Set(b.clustered))
        #expect(a.sessions.count == b.sessions.count)
    }

    @Test func anEmptyBenchIsEmptyEverywhere() {
        let bench = RenderedBench.compose(
            allItems: [], reviewedIds: [], hideReviewed: true, now: Date()
        )
        #expect(bench.count == 0 && bench.sessions.isEmpty && bench.loose.isEmpty && bench.clustered.isEmpty)
    }

    // MARK: - Fixtures

    static func item(_ kind: BenchClipItem.Kind, _ at: Date, roll: UUID? = nil) -> BenchClipItem {
        BenchClipItem(id: UUID(), kind: kind, capturedAt: at, rollGroupId: roll)
    }

    static func proposal(claiming ids: [UUID]) -> ClusterProposal {
        ClusterProposal(
            clipIds: ids,
            ruleTag: .timePlace,
            whyText: "test",
            proposedName: "Together",
            previewLines: []
        )
    }
}
