import Testing
import Foundation
@testable import HiMem

/// **F38 · media was counted in the New header and drawn by nothing.**
/// **F39 · a cluster was indistinguishable from a session on screen.**
///
/// F38, found on device 2026-08-02: a photo at 7:43 beside a voice clip at
/// 7:44 gave "3 new clips" with 2 in the cluster and the photo in no card
/// and no expanded view.
///
/// **The count and the render key off different things.** `ClipGroup.id` is
/// the `rollGroupId`, deliberately stable across regroupings. Absorbed media
/// lives in `absorbedMediaBySessionId` keyed by that id. The header summed
/// **`.values`** — every entry, whatever its key — while a card *looks up*
/// `absorbedMediaBySessionId[session.id]`. Any entry whose key is not among
/// the rendered sessions is therefore counted and undrawable.
///
/// **Ruled: the header counts only media attached to sessions it describes.**
/// One set, one source — the same ruling as F35(a), which this is the third
/// instance of. The visible consequence is accepted deliberately: the count
/// can drop when a photo is absorbed by a session outside the lens. A count
/// that includes clips nothing can draw is the dishonest option.
///
/// **Accounting, recorded rather than smoothed over.** F36 did not create
/// this — it raised its rate, by making session membership change more often
/// as the still-in-play window opens and closes. The incomplete part *is*
/// mine: F35(a) filtered the `benchClips` term of the header and left the
/// absorbed term unfiltered.
///
/// **The unpaired regroup.** Four of five sites that set `sessions` also
/// called `recomputeAbsorbedMedia()`; `:239` did not. That is the
/// invariant-without-an-owner shape, so the pairing is now structural — one
/// function does both, and this suite asserts there is only one place that
/// can regroup.
@Suite struct BenchCountAndProposalCopyTests {

    // MARK: - F38 · one set, one source

    /// **F38's guard has MOVED, not been dropped** (C2 step 2b-ii-c2).
    ///
    /// It asserted that `headerTitle` scoped its absorbed-media term to the
    /// sessions it described. The header has no media term any more — media
    /// is an item, counted by being drawn — so a source-level assertion here
    /// can only pass by matching nothing. The property F38 ruled is now
    /// behavioural, in `RenderedBenchTests`:
    ///
    ///  - `mediaInARefusedSessionIsNotCounted` — the F38 case itself.
    ///  - `mediaInAnAdmittedSessionIsCountedEvenIfReviewed` — the F37
    ///    converse, which the source guard could never have expressed.
    ///
    /// What remains here is the half that is still a statement about *this
    /// file*: the header must not rebuild any set of its own. That is
    /// `theHeaderAssemblesNoCountOfItsOwn` below, which subsumes the old
    /// assertion — it forbids `absorbedMediaBySessionId` outright rather than
    /// forbidding one wrong way of reading it.

    /// **Mechanism, not memory.** If `sessions` and the media map must always
    /// move together, one function moves them — rather than five call sites
    /// each remembering to.
    ///
    /// Re-anchored on the composition that replaced `computeSessions()`. The
    /// invariant is unchanged and now covers more: `sessions`, `allSessions`,
    /// the media map, `proposals` and `drawn` are all written in one place, so
    /// none of them can go stale relative to another.
    @Test func regroupingHasExactlyOneOwner() throws {
        let src = try Self.source("MemoryStream/Views/Inbox/SessionListView.swift")
        let code = Self.codeOnly(src)
        let assignments = code.components(separatedBy: "sessions = drawnBench.loose").count - 1
        #expect(assignments == 1,
                """
                `sessions` is assigned from \(assignments) places. Four of the five original \
                sites also refreshed the absorbed-media map and one did not (:239, the \
                remove-clip-from-session regroup), which is how the map went stale. \
                Regrouping needs one owner.
                """)
        // The owner must also be the only composer — a second `compose` call
        // would reintroduce two answers to one question, which is the class
        // this rebuild exists to end.
        let composes = code.components(separatedBy: "RenderedBench.compose(").count - 1
        #expect(composes == 1,
                "`RenderedBench.compose` is called from \(composes) places; the bench has one composer.")
    }

    // MARK: - F39 · a proposal must not read as a session

    @Test func theClusterCardSaysItIsAProposal() throws {
        let src = try Self.source("MemoryStream/Views/Inbox/ClusterCardStack.swift")
        #expect(Self.codeOnly(src).contains("ClusterCardCopy.mightGoTogether"),
                "The cluster card carries no cue that it is a proposal rather than a session.")
    }

    /// "51-minute stretch" reads as one continuous thing, which is exactly
    /// what made a cross-session proposal look like a grouping error.
    @Test func theProposalSubtitleDoesNotClaimOneContinuousStretch() throws {
        let src = try Self.source("MemoryStream/Services/Storage/ClipClusterProposer.swift")
        let code = Self.codeOnly(src)
        #expect(code.contains("-minute stretch, same place") == false,
                """
                The proposal subtitle still reads as a single continuous stretch. A cluster \
                spans sittings; describing it as one stretch is what made it look like a \
                broken session.
                """)
        #expect(code.contains("sittings") || code.contains("sitting"),
                "The subtitle does not say how many sittings the proposal spans.")
    }


    /// The eyebrow copy, pinned as a literal — the wording IS the promise.
    /// A failure here means the claim the card makes has changed, not that
    /// phrasing drifted.
    @Test func theEyebrowIsTheRuledLineAndClaimsNothing() {
        #expect(ClusterCardCopy.mightGoTogether == "Might go together")
        // J5: the AI may observe, never conclude. "belong" is the
        // interpretive verb, and a wrong grouping asserts a relationship the
        // user cannot cheaply verify.
        #expect(ClusterCardCopy.mightGoTogether.lowercased().contains("belong") == false)
        // "Might" is what keeps it a proposal rather than a claim.
        #expect(ClusterCardCopy.mightGoTogether.hasPrefix("Might"))
    }


    // MARK: - F40 / F41 / F42

    /// **F40 · every session's absorbed media must have somewhere to render.**
    ///
    /// This is the INVARIANT, not the symptom. The F38 guard forbade
    /// `.values` and passed happily while the count was scoped to `sessions`
    /// rather than to what actually renders — so media belonging to a
    /// clustered session was still counted and drawn by nothing. A proposal
    /// consumes whole sessions, so if the cluster card cannot draw media,
    /// clustering the whole bench makes real photos vanish.
    @Test func theClusterCardCanDrawItsSessionsMedia() throws {
        let src = try Self.source("MemoryStream/Views/Inbox/ClusterCardStack.swift")
        let code = Self.codeOnly(src)
        #expect(code.contains("mediaFor"),
                """
                The cluster card cannot render absorbed media. Proposals consume WHOLE                 sessions, so with no media path here a clustered bench counts photos in                 the header that nothing draws.
                """)
        // Declaring the parameter is not drawing with it. The first version
        // of this guard accepted the declaration alone — which an UNUSED
        // parameter satisfies: the guard-the-caller shape one layer out, in
        // the guard itself. Confirmed empirically — deleting only the render
        // call left the suite GREEN. Redone against the render.
        // **Assert the invariant, not the expression** (updated at F44,
        // 2026-08-02). This previously pinned the literal
        // `clusterMediaRow(mediaFor(proposal))` and broke when F44 correctly
        // changed the argument to the KEPT media — the promise ("the card
        // draws its media") was intact while the expression moved. That is
        // the mirror of this guard's earlier fault: it was strengthened from
        // accepting a mere declaration, and over-corrected into pinning one
        // exact call. What is durable is that `clusterMediaRow` is both
        // DEFINED and CALLED; which set it is given is F44's guard to own.
        #expect(code.components(separatedBy: "clusterMediaRow(").count - 1 >= 2,
                "`clusterMediaRow` is defined but never called — the card draws no media.")
        #expect(code.contains("MediaReference"),
                "The cluster card has no media type in scope, so it cannot be drawing any.")
    }

    /// The caller must actually supply it — an unused parameter is the
    /// guard-the-caller shape one layer out.
    @Test func theBenchSuppliesTheClusterItsMedia() throws {
        let src = try Self.source("MemoryStream/Views/Inbox/SessionListView.swift")
        #expect(Self.codeOnly(src).contains("mediaFor: media(forCluster:)"),
                "`ClusterCardStack` is constructed without media, so the parameter draws nothing.")
    }

    /// **F41 · the prune must read the same stores the proposer does.**
    /// Reading only the manifest deleted dismissals for ref-backed clips on
    /// the next write, which is why "Not together" did not stick.
    @Test func theDismissalPruneReadsBothStores() throws {
        let src = try Self.source("MemoryStream/Services/Storage/InboxManifest.swift")
        let body = try Self.blockBody(startingAtLineContaining: "private func pruneDeadDismissedClusters()", in: src)
        let code = Self.codeOnly(body)
        #expect(code.contains("materializedBenchClipIds"),
                """
                `pruneDeadDismissedClusters` judges liveness from the manifest alone, but                 the bench composes from manifest rows AND materialized refs. A dismissal                 naming a ref-backed clip is pruned on the next write. Body was:
                \(body)
                """)
    }

    /// **F42 · the interpretive verb must be absent from the whole file, not
    /// just from the constant I happened to guard.** F39 asserted the eyebrow
    /// existed and never checked the louder heading above it.
    @Test func noInterpretiveVerbAnywhereOnTheClusterSurface() throws {
        let src = try Self.source("MemoryStream/Views/Inbox/ClusterCardStack.swift")
        #expect(Self.codeOnly(src).lowercased().contains("belong") == false,
                """
                "belong" still appears in cluster-surface CODE. J5: the AI may observe,                 never conclude. F39 guarded the eyebrow constant and missed the section                 heading — the same guard-the-caller shape it was written to prevent.
                """)
        #expect(ClusterCardCopy.sectionHeading == "A few of these might go together")
    }

    // MARK: - Source access

    // MARK: - C2 step 2b-ii-b · the view must have ONE source

    /// **Premise 4 of the redo contract, as the caller half.**
    ///
    /// The behavioural assertions live on `DrawnBench` (2b-ii-a) and describe
    /// what the surface says. They only *mean* that if the view has no second
    /// source — otherwise they describe a value the header ignores, which is
    /// precisely how the reverted 2b-ii was green at 1394/192 with "7 new
    /// clips · 0 sessions" on screen.
    ///
    /// Every guard in that step asserted on the composition and the
    /// composition was correct. So this one asserts the *relationship*: the
    /// header assembles nothing of its own.
    ///
    /// **RED WHEN WRITTEN, against real shipped code** — the reverted header
    /// reads three separately-scoped terms (`lensClips.count + inFlightOnly +
    /// absorbedMediaCount`) and ranges the span over a *fourth* set that omits
    /// absorbed media, so a photo is counted but never spans. That is not the
    /// defect 2b-ii introduced; it is the one it was written to fix and did
    /// not.
    @Test func theHeaderAssemblesNoCountOfItsOwn() throws {
        let src = try Self.source("MemoryStream/Views/Inbox/SessionListView.swift")
        // `blockBody` throws on a missing anchor, so a rename fails loudly
        // rather than letting this pass by matching nothing.
        for needle in ["private var headerTitle: String {", "private var headerSubtitle: String {"] {
            let body = try Self.blockBody(startingAtLineContaining: needle, in: src)
            let code = Self.codeOnly(body)
            for raw in ["lensClips", "benchClips", "absorbedMediaBySessionId", "arrivals.clipsInFlight", "sessions."] {
                #expect(code.contains(raw) == false,
                        """
                        `\(needle.trimmingCharacters(in: .whitespaces))` reads `\(raw)` directly. \
                        Every number the header says must come from the ONE drawn value, or the \
                        count, the span and the session term can describe different sets again — \
                        which is the class this rebuild exists to end, and which shipped inside \
                        the step written to close it. Body was:
                        \(body)
                        """)
            }
        }
    }

    /// **Select all was inert on a quiet bench** (device, 2026-08-13).
    ///
    /// `resetVisible()` fires on a filter switch and only data-change hooks
    /// re-register, so on a bench where nothing was arriving the registry
    /// stayed empty and Select all had nothing to select.
    ///
    /// It was masked by B15: the 30-second retry sweep republished the
    /// manifest continuously, so a re-registration was never more than a few
    /// seconds away. **Stopping the blink removed the churn that was carrying
    /// this** — a defect that only appears once the noise stops was always
    /// there, and is worth naming as a class: quieting a busy path can reveal
    /// work that was riding on its side effects.
    ///
    /// The registry must be populated when it is about to be USED.
    @Test func enteringSelectionRepopulatesTheVisibleRegistry() throws {
        let src = try Self.source("MemoryStream/Views/Inbox/SessionListView.swift")
        let code = Self.codeOnly(src)
        #expect(code.contains("onChange(of: selection.selecting)"),
                """
                Nothing re-registers the selectable ids when selection mode is entered, so \
                Select all depends on a data change having happened recently. On a quiet \
                bench there is none.
                """)
    }

    static func codeOnly(_ source: String) -> String {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let marker = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<marker.lowerBound])
            }
            .joined(separator: "\n")
    }

    static func blockBody(startingAtLineContaining needle: String, in source: String) throws -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains(needle) }) else {
            throw Failure.blockNotFound(needle)
        }
        var depth = 0, started = false
        var out: [String] = []
        for line in lines[start...] {
            for ch in line {
                if ch == "{" { depth += 1; started = true }
                if ch == "}" { depth -= 1 }
            }
            if started { out.append(line) }
            if started && depth == 0 { return out.joined(separator: "\n") }
        }
        throw Failure.blockNotFound(needle)
    }

    static func source(_ relative: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        guard let src = try? String(contentsOf: url, encoding: .utf8), !src.isEmpty else {
            throw Failure.sourceNotFound(url.path)
        }
        return src
    }

    enum Failure: Error { case sourceNotFound(String), blockNotFound(String) }
}
