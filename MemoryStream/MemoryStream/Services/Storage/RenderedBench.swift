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
