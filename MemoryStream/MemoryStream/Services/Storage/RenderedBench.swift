import Foundation

/// **What is on the bench, as one value.** (C2 rebuild step 1, 2026-08-03.)
///
/// Seven defects in one day were the same shape: a number on screen computed
/// from a different set than the one being drawn. Each was closed by scoping
/// one more term correctly, and each was followed by another — including the
/// seventh, which was introduced by the fix for the sixth.
///
/// The audit found why, and it is not carelessness. **There was no "all bench
/// items" set anywhere in the program.** `composeBenchClips` unions manifest
/// rows with materialized zero-edge *voice* refs; no photo, video or note
/// ever entered it. Media reached the screen through a side channel — a
/// dictionary keyed by session id plus a cross-view singleton of absorbed ref
/// ids — so **every derived quantity had to remember to add a separately
/// scoped "+ media" term.** Twenty-six sets, nine with more than one
/// producer, and `RENDERED` with no producer at all: it was the view tree.
///
/// This type is that missing union. One value, composed once, read by the
/// header, the session cards, the cluster card and selection. The union stops
/// being something each consumer reconstructs by hand.
///
/// **Purity is the point, not a style preference.** Every bench composition
/// term used to be a `private var` on a SwiftUI struct, which made the
/// sentence *"what the header counted equals what the bench drew"* not merely
/// untested but **inexpressible** — 188 test files contained zero behavioural
/// invocations of any of them, which is why the guards written for F35–F44
/// were `String.contains` over source text. A mutation harness later proved
/// those guards stayed green while four of the fixed defects were fully
/// restored, and failed on a behaviour-preserving rename: blind to wrong
/// sets, hostile to right ones. `compose` takes every input explicitly and
/// returns a value, so the invariant is now one assertion.
struct RenderedBench: Equatable {

    /// **The union actually on screen** — in-flight items, clustered items
    /// and loose sessions together. Those three are a *partition* of this
    /// (`itemsPartitionIntoTheThreeDrawnRegions` pins it), so every count,
    /// span and glyph derives from this or from a subset of it that is named
    /// here, never from a set reconstructed at the call site.
    let items: [BenchClipItem]

    /// The groupable items (`items` minus `inFlight`), grouped
    /// media-agnostically. A photo captured inside a voice clip's idle window
    /// is *in that session*, not absorbed into it by a separate pass.
    let sessions: [UnifiedSession]

    /// Item ids claimed by a cluster proposal **after the user's trim** —
    /// the one definition. There were four independent producers of this for
    /// clips and three for media; a set-aside item is not in here.
    let clustered: Set<UUID>

    /// Sessions rendered below the cluster stack, with clustered items
    /// removed and empties dropped. A session whose items are all claimed
    /// does not appear; a partially-claimed one appears with the remainder,
    /// which is what returns a set-aside item to the bench.
    let loose: [UnifiedSession]

    /// Items still arriving — drawn as `IncomingCard` rows above the cluster
    /// stack, and never grouped into a session (a clip in the `.transcribing`
    /// phase is already a manifest row, so without this it would render twice:
    /// once as an IncomingCard and once as a session card carrying the
    /// legitimate-but-confusing "Transcribing…" body).
    ///
    /// **This is a third REGION, not a third SET.** It is a partition of
    /// `items` alongside `clustered` and `loose`, computed here from one
    /// input — which is the whole difference from the term it replaces.
    /// `headerTitle` used to read `lensClips.count + inFlightOnly +
    /// absorbedMediaCount`: three counts over three separately-scoped sets,
    /// two of which were wrong at different times (F35(a), F38). The header
    /// now reads `count`.
    let inFlight: [BenchClipItem]

    /// What the header must say. Deliberately not a separate computation:
    /// this is the identity that seven defects violated.
    var count: Int { items.count }

    /// Items a cluster proposal still holds, in capture order — what the
    /// cluster card draws and what its subtitle describes. Media included,
    /// because media is an item.
    func keptItems(for proposal: ClusterProposal, trim: [String: Set<UUID>]) -> [BenchClipItem] {
        let removed = trim[proposal.fingerprint.rawValue] ?? []
        let claimed = Self.claimedSessions(for: proposal, in: sessions)
        return claimed
            .flatMap(\.items)
            .filter { !removed.contains($0.id) }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    // MARK: - Composition

    /// - Parameters:
    ///   - allItems: every bench item of every kind, unfiltered.
    ///   - reviewedIds: ids the user has opened. One set for all kinds —
    ///     manifest `reviewed` and the per-device ref store resolve to this
    ///     at the boundary, so nothing downstream asks which backing a thing
    ///     has.
    ///   - hideReviewed: true on the **New** lens.
    ///   - now: injected; the F36 still-in-play window is measured against it.
    ///   - inFlightIds: ids still arriving. They stay in `items` — they are
    ///     on the bench and they are drawn — but they are held out of the
    ///     grouping, so they render only as `IncomingCard`s.
    ///   - soloIds: ids the user removed from their session (July 12 triage).
    ///   - proposals / trim: cluster membership and the user's set-asides.
    static func compose(
        allItems: [BenchClipItem],
        reviewedIds: Set<UUID>,
        hideReviewed: Bool,
        now: Date,
        inFlightIds: Set<UUID> = [],
        soloIds: Set<UUID> = [],
        proposals: [ClusterProposal] = [],
        trim: [String: Set<UUID>] = [:]
    ) -> RenderedBench {

        // 1 · The lens. F36: a reviewed item stays while its SESSION could
        // still gain a neighbour — session-relative, because a clip-relative
        // window splits a real sitting across two lenses.
        //
        // Grouped over ALL items, in-flight included: a session's window is a
        // property of the session, and an arriving clip is one of its members.
        // Matches `BenchLensClips.forLens`, which groups the full bench for
        // the same reason and likewise passes the solo set through.
        let lensItems: [BenchClipItem]
        if hideReviewed {
            let allSessions = UnifiedBenchGrouper.group(allItems, soloIds: soloIds)
            var stillInPlay: Set<UUID> = []
            for session in allSessions {
                guard let latest = session.items.map(\.capturedAt).max() else { continue }
                if now.timeIntervalSince(latest) < ClipSessionGrouper.sessionTimeWindowSeconds {
                    stillInPlay.formUnion(session.items.map(\.id))
                }
            }
            lensItems = allItems.filter { !reviewedIds.contains($0.id) || stillInPlay.contains($0.id) }
        } else {
            lensItems = allItems
        }

        // 2 · In-flight items are partitioned off before grouping, never
        // subtracted from a count afterwards.
        let inFlight = lensItems.filter { inFlightIds.contains($0.id) }
        let groupable = lensItems.filter { !inFlightIds.contains($0.id) }

        let sessions = UnifiedBenchGrouper.group(groupable, soloIds: soloIds)

        // 3 · Clustered, once. A proposal claims whole SESSIONS (the proposer
        // flatMaps them), so everything in a claimed session is clustered —
        // including its media, which is why the cluster card can draw photos
        // without a second lookup. Minus the trim.
        var clustered: Set<UUID> = []
        for proposal in proposals {
            let removed = trim[proposal.fingerprint.rawValue] ?? []
            for session in claimedSessions(for: proposal, in: sessions) {
                for item in session.items where !removed.contains(item.id) {
                    clustered.insert(item.id)
                }
            }
        }

        // 4 · Loose = what the cluster did not keep. A set-aside item lands
        // here rather than vanishing: it is still new, still unconnected, and
        // still hers.
        let loose: [UnifiedSession] = sessions.compactMap { session in
            let remaining = session.items.filter { !clustered.contains($0.id) }
            if remaining.isEmpty { return nil }
            if remaining.count == session.items.count { return session }
            return UnifiedSession(items: remaining)
        }

        return RenderedBench(
            items: lensItems,
            sessions: sessions,
            clustered: clustered,
            loose: loose,
            inFlight: inFlight
        )
    }

    /// Sessions a proposal claims — matched by any member id, since proposals
    /// are built from whole sessions.
    static func claimedSessions(
        for proposal: ClusterProposal,
        in sessions: [UnifiedSession]
    ) -> [UnifiedSession] {
        let ids = Set(proposal.clipIds)
        return sessions.filter { $0.items.contains(where: { ids.contains($0.id) }) }
    }
}

/// **The bench AS DRAWN — C2 step 2b-ii-a, 2026-08-09. Inert: nothing calls
/// this yet.**
///
/// `RenderedBench` is what the bench *composes*. This is what the surface
/// *draws*, and the difference is the whole reason 2b-ii was reverted.
///
/// The shipped 2b-ii was green at 1394/192 with two live defects — a header
/// reading "7 new clips · 0 sessions" over a visible card, and a cluster
/// subtitle saying "1 clip from 1 sitting · 1 minute apart" over three rows
/// spanning 58 minutes. Every guard passed because every guard asserted on the
/// composition, **and the composition was correct**. Nothing asserted on what
/// the view read out of it. Guard-the-caller, one layer further out than the
/// three prior instances.
///
/// So the drawn set becomes a value with a name, and the surface's numbers
/// become properties of it. A guard can then assert what the header SAYS
/// rather than what the bench COMPUTED — premise 4 of the redo contract.
///
/// The one scope the view applies lives here rather than being applied
/// afterwards: a session with no voice item belongs to `ClipsTabView`'s
/// sibling unplaced stack until step 3 retires it. Drawing it here too
/// double-renders (the F35(b) class); drawing it *instead* renders a
/// voice-shaped card over a 1970 date. Keeping that scope inside the value is
/// what makes "what is drawn" answerable by a test.
struct DrawnBench: Equatable {

    /// Loose sessions this surface draws, after the sibling-stack scope.
    let loose: [UnifiedSession]
    /// Sessions consumed by a cluster proposal. Drawn — as cluster cards.
    let clusteredSessions: [UnifiedSession]
    /// Items still arriving, drawn as `IncomingCard`s.
    let inFlight: [BenchClipItem]

    /// **Every item on screen, in any region.** One set — so the count, the
    /// span and the session term cannot describe different things, which is
    /// the identity seven defects violated.
    var items: [BenchClipItem] {
        loose.flatMap(\.items) + clusteredSessions.flatMap(\.items) + inFlight
    }

    var count: Int { items.count }

    var capturedAts: [Date] { items.map(\.capturedAt) }

    /// **Every drawn session, clustered included** — premise 1's arithmetic,
    /// uniform regardless of region.
    var drawnSessionCount: Int { loose.count + clusteredSessions.count }

    /// **nil when every session is clustered** (ruled 2026-08-09).
    ///
    /// A header saying "1 session" over a cluster card asserts the grouping the
    /// card is only *proposing* — J5's observe-don't-conclude line, crossed by
    /// the surface's own chrome rather than by the AI. "1 group" was rejected
    /// too: it mints a noun for something the user has not accepted, and a
    /// second word for a sitting she would have to learn.
    ///
    /// Saying less is the honest option: the count and the span are facts about
    /// drawn items however they are grouped, and the cluster card already
    /// speaks for itself in its own careful language. When any session is
    /// loose the term returns and counts *all* drawn sessions — the arithmetic
    /// never changes, only whether the sentence carries it.
    var sessionTerm: Int? {
        loose.isEmpty ? nil : drawnSessionCount
    }

    /// Narrow a composed bench to what this surface actually draws.
    ///
    /// - Parameter drawsVoicelessSessions: `false` while `ClipsTabView`'s
    ///   sibling stack still owns them (through step 2). Step 3 retires the
    ///   stack and flips this, and the flip is a one-line change with a test
    ///   rather than a filter to remember at a call site.
    static func from(
        _ bench: RenderedBench,
        proposals: [ClusterProposal],
        drawsVoicelessSessions: Bool = false
    ) -> DrawnBench {
        let drawnLoose = drawsVoicelessSessions
            ? bench.loose
            : bench.loose.filter(\.hasVoice)
        // A proposal consumes whole sessions, so the claimed sets are disjoint
        // across proposals; `Set` on session identity guards the assumption
        // rather than trusting it.
        var seen = Set<UUID>()
        var claimed: [UnifiedSession] = []
        for proposal in proposals {
            for session in RenderedBench.claimedSessions(for: proposal, in: bench.sessions) {
                let key = session.items.first?.id ?? UUID()
                if seen.insert(key).inserted { claimed.append(session) }
            }
        }
        return DrawnBench(
            loose: drawnLoose,
            clusteredSessions: claimed,
            inFlight: bench.inFlight
        )
    }
}
