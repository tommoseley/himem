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

    /// **THE assertion.** Everything the bench draws is in exactly one of the
    /// three drawn regions — arriving, claimed by a cluster, or loose — and
    /// the header counts the union. Seven defects violated this and none of
    /// them could be expressed as a test.
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
        let drawn = bench.loose.flatMap(\.items).count + bench.clustered.count + bench.inFlight.count
        #expect(bench.count == drawn,
                "header says \(bench.count), bench draws \(drawn) — the defect class, as one assertion")
        #expect(bench.count == 4)
    }

    /// The identity above, stated as the partition it actually is, with all
    /// three regions non-empty at once and a trim in play. Two of the four
    /// three-numbers-two-sets defects were caused *while fixing* the previous
    /// one, because each guard tested the symptom rather than this.
    @Test func itemsPartitionIntoTheThreeDrawnRegions() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let arriving = Self.item(.voice, t.addingTimeInterval(7 * 3600))
        let clusterA = Self.item(.voice, t)
        let clusterPhoto = Self.item(.image, t.addingTimeInterval(60))
        let setAside = Self.item(.voice, t.addingTimeInterval(120))
        let elsewhere = Self.item(.note, t.addingTimeInterval(4 * 3600))
        let proposal = Self.proposal(claiming: [clusterA.id])
        let bench = RenderedBench.compose(
            allItems: [arriving, clusterA, clusterPhoto, setAside, elsewhere],
            reviewedIds: [], hideReviewed: true, now: t.addingTimeInterval(7 * 3600),
            inFlightIds: [arriving.id],
            proposals: [proposal],
            trim: [proposal.fingerprint.rawValue: [setAside.id]]
        )
        let looseIds = Set(bench.loose.flatMap(\.items).map(\.id))
        let flightIds = Set(bench.inFlight.map(\.id))

        // Every region is genuinely populated — a partition check over an
        // empty region proves nothing about the region.
        #expect(!looseIds.isEmpty && !bench.clustered.isEmpty && !flightIds.isEmpty)
        // Covering: nothing on the bench is undrawn.
        #expect(looseIds.union(bench.clustered).union(flightIds) == Set(bench.items.map(\.id)),
                "an item is on the bench and in none of the three drawn regions")
        // Disjoint: nothing is drawn twice — the F35(b) duplication class.
        #expect(looseIds.isDisjoint(with: bench.clustered))
        #expect(flightIds.isDisjoint(with: bench.clustered))
        #expect(flightIds.isDisjoint(with: looseIds))
        // And the set-aside item came back to the loose region, not the void.
        #expect(looseIds.contains(setAside.id))
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

    // MARK: - Still arriving (C2 step 2b-i, 2026-08-03)
    //
    // Replaces `headerTitle`'s `inFlightOnly` term. That term existed
    // because `computeSessions` filtered in-flight ids out of the grouping
    // and the header then had to add them back — two scopes, one number,
    // the exact shape of F35(a) and F38. Here one input produces both.
    //
    // Mutation-verified: dropping the `inFlightIds` filter before grouping
    // fails `anArrivingItemIsCountedButNeverGrouped`.

    /// An arriving clip is already a manifest row, so without the partition
    /// it renders twice — once as an `IncomingCard`, once as a session card
    /// showing the legitimate-but-confusing "Transcribing…" body.
    @Test func anArrivingItemIsCountedButNeverGrouped() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let arriving = Self.item(.voice, t)
        let bench = RenderedBench.compose(
            allItems: [arriving], reviewedIds: [], hideReviewed: true, now: t,
            inFlightIds: [arriving.id]
        )
        #expect(bench.count == 1, "an arriving clip is on the bench and must be counted")
        #expect(bench.inFlight.map(\.id) == [arriving.id])
        #expect(bench.sessions.isEmpty, "the arriving clip was grouped into a session card")
        #expect(bench.loose.isEmpty)
    }

    /// Holding one item out must not pull its neighbours out with it — the
    /// rest of the sitting still groups, and still groups *together*.
    @Test func anArrivingItemDoesNotDisbandTheRestOfItsSitting() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let arriving = Self.item(.voice, t)
        let landed = Self.item(.voice, t.addingTimeInterval(60))
        let photo = Self.item(.image, t.addingTimeInterval(120))
        let bench = RenderedBench.compose(
            allItems: [arriving, landed, photo], reviewedIds: [], hideReviewed: true, now: t,
            inFlightIds: [arriving.id]
        )
        #expect(bench.count == 3)
        #expect(bench.sessions.count == 1)
        #expect(Set(bench.sessions[0].items.map(\.id)) == [landed.id, photo.id])
    }

    /// The lens measures the window over ALL items including the arriving
    /// one — a session that is still *receiving* is self-evidently still in
    /// play, so a reviewed sibling must not age out from under it.
    @Test func anArrivingItemKeepsItsReviewedSiblingInTheNewLens() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let seen = Self.item(.voice, t)
        let arriving = Self.item(.voice, t.addingTimeInterval(9 * 60))
        let bench = RenderedBench.compose(
            allItems: [seen, arriving], reviewedIds: [seen.id], hideReviewed: true,
            now: t.addingTimeInterval(11 * 60),
            inFlightIds: [arriving.id]
        )
        #expect(bench.count == 2, "the reviewed sibling aged out while its session was still arriving")
    }

    // MARK: - Removed from session, threaded through composition

    /// The July 12 triage survives the rebuild end-to-end, not just in the
    /// grouper: a solo item is its own session here too. Mixed-kind, so a
    /// voice-only path cannot satisfy it.
    @Test func aRemovedItemIsItsOwnSessionOnTheComposedBench() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let voice = Self.item(.voice, t)
        let photo = Self.item(.image, t.addingTimeInterval(60))
        let bench = RenderedBench.compose(
            allItems: [voice, photo], reviewedIds: [], hideReviewed: false, now: t,
            soloIds: [photo.id]
        )
        #expect(bench.sessions.count == 2, "the removed item was re-absorbed by its old sitting")
        #expect(bench.count == 2)
    }

    /// All three new inputs at once, with a reviewed item and a non-empty
    /// trim — the combination, because each of these has been correct alone
    /// and wrong together before.
    @Test func theRegionsHoldWithSoloArrivingReviewedAndATrimTogether() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let clusterA = Self.item(.voice, t)
        let setAside = Self.item(.image, t.addingTimeInterval(60))
        let removed = Self.item(.note, t.addingTimeInterval(120))
        let arriving = Self.item(.voice, t.addingTimeInterval(180))
        let staleSeen = Self.item(.voice, t.addingTimeInterval(-5 * 3600))
        let proposal = Self.proposal(claiming: [clusterA.id])
        let bench = RenderedBench.compose(
            allItems: [clusterA, setAside, removed, arriving, staleSeen],
            reviewedIds: [staleSeen.id], hideReviewed: true, now: t.addingTimeInterval(180),
            inFlightIds: [arriving.id],
            soloIds: [removed.id],
            proposals: [proposal],
            trim: [proposal.fingerprint.rawValue: [setAside.id]]
        )
        // The stale reviewed item is gone from the New lens; the other four stay.
        #expect(bench.count == 4)
        #expect(bench.items.contains { $0.id == staleSeen.id } == false)
        // Still a partition, with every region populated.
        let looseIds = Set(bench.loose.flatMap(\.items).map(\.id))
        let flightIds = Set(bench.inFlight.map(\.id))
        #expect(looseIds.union(bench.clustered).union(flightIds) == Set(bench.items.map(\.id)))
        #expect(looseIds.isDisjoint(with: bench.clustered))
        #expect(flightIds.isDisjoint(with: looseIds))
        // Added because a mutation walked through the gap: with in-flight items
        // grouped, `arriving` joined the claimed session and was drawn BOTH as
        // an IncomingCard and inside the cluster, and this test stayed green
        // while `itemsPartitionIntoTheThreeDrawnRegions` caught it. Two of the
        // three pairs is not disjointness.
        #expect(flightIds.isDisjoint(with: bench.clustered))
        // The set-aside photo is loose, the removed note is its own session.
        #expect(looseIds.contains(setAside.id))
        #expect(bench.loose.contains { $0.items.map(\.id) == [removed.id] })
    }

    @Test func anEmptyBenchIsEmptyEverywhere() {
        let bench = RenderedBench.compose(
            allItems: [], reviewedIds: [], hideReviewed: true, now: Date()
        )
        #expect(bench.count == 0 && bench.sessions.isEmpty && bench.loose.isEmpty
                && bench.clustered.isEmpty && bench.inFlight.isEmpty)
    }

    // MARK: - C2 step 2b-ii-a · what the SURFACE draws

    /// **The ruling, 2026-08-09.** With every session clustered, the header is
    /// count + span only. "1 session" over a cluster card asserts the grouping
    /// the card is merely proposing — J5's line crossed by chrome rather than
    /// by the AI — and "1 group" mints a noun the user has not accepted.
    @Test func theSessionTermDropsWhenEverySessionIsClustered() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let a = Self.item(.voice, t), b = Self.item(.voice, t.addingTimeInterval(60))
        let bench = RenderedBench.compose(
            allItems: [a, b], reviewedIds: [], hideReviewed: false, now: t,
            proposals: [Self.proposal(claiming: [a.id, b.id])]
        )
        let drawn = DrawnBench.from(bench, proposals: [Self.proposal(claiming: [a.id, b.id])])
        #expect(drawn.loose.isEmpty, "fixture precondition: the proposal claims every session")
        #expect(drawn.sessionTerm == nil,
                "the header still carries a session term while the only thing on screen is a proposal")
        #expect(drawn.count == 2, "dropping the SENTENCE must not drop the COUNT")
    }

    /// The other half: the term returns the moment anything is loose, and it
    /// counts **every** drawn session — clustered included. The arithmetic is
    /// uniform; only the sentence drops.
    @Test func theSessionTermReturnsAndCountsClusteredSessionsToo() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let a = Self.item(.voice, t), b = Self.item(.voice, t.addingTimeInterval(60))
        let far = Self.item(.voice, t.addingTimeInterval(6 * 3600))   // its own sitting
        let proposals = [Self.proposal(claiming: [a.id, b.id])]
        let bench = RenderedBench.compose(
            allItems: [a, b, far], reviewedIds: [], hideReviewed: false, now: t,
            proposals: proposals
        )
        let drawn = DrawnBench.from(bench, proposals: proposals)
        #expect(drawn.loose.count == 1)
        #expect(drawn.sessionTerm == 2,
                "the term must count the clustered session too — premise 1's arithmetic is uniform")
    }

    /// **One set, mechanically.** The count, the span and the term all read
    /// `items`, so they cannot describe different things — the identity seven
    /// defects violated and 2b-ii claimed in prose while breaking.
    @Test func theCountAndTheSpanAreTheSameSet() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let items = [Self.item(.voice, t), Self.item(.image, t.addingTimeInterval(120)),
                     Self.item(.note, t.addingTimeInterval(240))]
        let bench = RenderedBench.compose(
            allItems: items, reviewedIds: [], hideReviewed: false, now: t
        )
        let drawn = DrawnBench.from(bench, proposals: [])
        #expect(drawn.capturedAts.count == drawn.count)
        #expect(drawn.count == drawn.items.count)
    }

    /// The sibling-stack scope lives in the value, not in the view — otherwise
    /// "what is drawn" is unanswerable by a test, which is how the reverted
    /// step shipped two visible defects under a green suite.
    @Test func aVoicelessSessionIsNotDrawnHereUntilStep3() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let photo = Self.item(.image, t)
        let bench = RenderedBench.compose(
            allItems: [photo], reviewedIds: [], hideReviewed: false, now: t
        )
        #expect(DrawnBench.from(bench, proposals: []).loose.isEmpty,
                "a photo-only sitting belongs to ClipsTabView's stack until step 3")
        #expect(DrawnBench.from(bench, proposals: [], drawsVoicelessSessions: true).loose.count == 1,
                "and the step-3 flip is one parameter with a test, not a filter to remember")
    }

    /// **An arriving clip is DRAWN, so it counts — even if reviewed** (device,
    /// 2026-08-10; ruled by Tom).
    ///
    /// `compose` applied the lens at step 1 and partitioned in-flight at step 2
    /// **from the already-lensed set**, so a reviewed clip that is re-arriving
    /// was dropped before it could reach the in-flight region. Meanwhile
    /// `SessionListView` feeds its `IncomingCard` list from
    /// `arrivals.sortedNewestFirst()` — **un-lensed** — so the item is on
    /// screen while the composed count omits it.
    ///
    /// Caught by `[BenchPerf]` on device: `bench DIFFER · oldCount=4
    /// newCount=3`, firing only inside a retry sweep and `AGREE` in every
    /// quiet window. The old header's `inFlightOnly` term — which reads like a
    /// rogue second set — was **compensating for this**: right intent, wrong
    /// layer.
    ///
    /// The lens governs what is *groupable into sessions*, not what is
    /// *arriving*. An arriving clip's review state is stale by construction.
    @Test func anArrivingClipIsDrawnEvenWhenReviewed() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let arriving = Self.item(.voice, t)
        let bench = RenderedBench.compose(
            allItems: [arriving],
            reviewedIds: [arriving.id],
            hideReviewed: true,
            now: t.addingTimeInterval(3600),   // far past the still-in-play window
            inFlightIds: [arriving.id]
        )
        #expect(bench.inFlight.count == 1,
                "a reviewed clip that is re-arriving was dropped by the lens before the in-flight partition")
        #expect(bench.count == 1, "the composed count omits an item the view draws as an IncomingCard")
        #expect(DrawnBench.from(bench, proposals: []).count == 1,
                "the drawn count must include arriving items — premise 1: it is drawn, so it counts")
    }

    /// The converse, so the fix cannot become "in-flight ignores the lens
    /// entirely in both directions": an UNREVIEWED arriving clip was always
    /// counted, and must stay counted.
    @Test func anUnreviewedArrivingClipStillCounts() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let arriving = Self.item(.voice, t)
        let bench = RenderedBench.compose(
            allItems: [arriving], reviewedIds: [], hideReviewed: true,
            now: t.addingTimeInterval(3600), inFlightIds: [arriving.id]
        )
        #expect(bench.inFlight.count == 1)
        #expect(bench.count == 1)
    }

    // MARK: - Guards inherited from the view, C2 step 2b-ii-c2

    /// **F44 · a set-aside clip comes BACK to the loose list.**
    ///
    /// Inherited from `ClusterKeptSetTests.setAsideReturnsTheClipToTheLooseList`,
    /// which asserted that `SessionListView.looseSessions` consulted
    /// `removedByFingerprint`. The swap moved that decision into
    /// `RenderedBench`, so a source-level guard on the view now describes a
    /// property the view no longer has — it would pass by matching nothing,
    /// or fail while the behaviour is intact.
    ///
    /// **This is the stronger form**: it asserts the outcome (the clip is
    /// drawn, in the loose region, and not clustered) rather than the
    /// mechanism, so it survives the next move and still fails if the clip
    /// vanishes. Verified by mutation — dropping the `!clustered.contains`
    /// filter in `claiming` fails it.
    @Test func aSetAsideItemReturnsToTheLooseRegion() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let kept = Self.item(.voice, t)
        let setAside = Self.item(.voice, t.addingTimeInterval(120))
        let bench = RenderedBench.compose(
            allItems: [kept, setAside],
            reviewedIds: [], hideReviewed: true, now: t.addingTimeInterval(180)
        )
        let proposal = Self.proposal(claiming: [kept.id, setAside.id])
        let claimed = bench.claiming(
            proposals: [proposal],
            trim: [proposal.fingerprint.rawValue: [setAside.id]]
        )
        #expect(claimed.clustered.contains(setAside.id) == false,
                "a set-aside item is still counted as clustered")
        #expect(claimed.loose.flatMap(\.items).contains(setAside) == true,
                """
                the set-aside item is not in the loose region — it has vanished from the \
                bench entirely. It is still new, still unconnected and still hers; hiding \
                it is the subtractive posture J2 retired.
                """)
        #expect(claimed.count == 2, "the count must not move when an item is merely set aside")
    }

    /// **F38 · the header counted media that nothing drew.**
    ///
    /// Inherited from `BenchCountAndProposalCopyTests.headerCountsOnlyMediaItCanDraw`,
    /// which asserted that `headerTitle` scoped its absorbed-media term to
    /// the rendered sessions. The header has no media term any more — media
    /// is an item, so it is counted by being drawn — and the guard's subject
    /// moved with it.
    ///
    /// Stated as the property F38 actually ruled: **a photo in a session the
    /// lens turned away is not counted.** Under F37 the unit of admission is
    /// the session, so the case is a photo alone in an all-reviewed sitting.
    @Test func mediaInARefusedSessionIsNotCounted() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let seenVoice = Self.item(.voice, t)
        let seenPhoto = Self.item(.image, t.addingTimeInterval(60))
        let freshVoice = Self.item(.voice, t.addingTimeInterval(5 * 3600))
        let bench = RenderedBench.compose(
            allItems: [seenVoice, seenPhoto, freshVoice],
            reviewedIds: [seenVoice.id, seenPhoto.id],
            hideReviewed: true,
            // Well past the still-in-play window for the reviewed sitting.
            now: t.addingTimeInterval(6 * 3600)
        )
        #expect(bench.items.contains(seenPhoto) == false,
                "a photo in a session the lens refused is counted but cannot be drawn")
        #expect(bench.count == 1)
    }

    /// The converse, and the F37 half: **a photo in an ADMITTED session is
    /// counted even when the photo itself has been seen.** Every count
    /// describes its own container's full contents, so a session admitted for
    /// one fresh clip carries its reviewed media into the number.
    @Test func mediaInAnAdmittedSessionIsCountedEvenIfReviewed() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let seenPhoto = Self.item(.image, t)
        let freshVoice = Self.item(.voice, t.addingTimeInterval(60))
        let bench = RenderedBench.compose(
            allItems: [seenPhoto, freshVoice],
            reviewedIds: [seenPhoto.id],
            hideReviewed: true,
            now: t.addingTimeInterval(6 * 3600)
        )
        #expect(bench.count == 2,
                """
                the admitted session was counted pre-shrunk — F37's 2 · 2 · 4 defect, \
                where the header said one number and the card opened to another.
                """)
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
