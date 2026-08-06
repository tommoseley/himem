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

    /// **F38's invariant, now carried by construction** (C2 step 2b).
    ///
    /// The original guard forbade `absorbedMediaBySessionId.values` — the
    /// symptom, not the rule — and required the string "sessions", which any
    /// scoping would satisfy. It could not state the actual requirement,
    /// because the header's count and the drawn set were both private view
    /// state and the union had no name.
    ///
    /// Now `render(now:)` gathers the drawn items ONCE and the header reads
    /// `drawnCount` off that value, so "counted" and "drawn" are the same
    /// array rather than two computations that must agree. What survives here
    /// is the caller half — that the header reads the composed value and does
    /// not rebuild a set of its own. The arithmetic half is behavioural now,
    /// in `RenderedBenchTests.itemsPartitionIntoTheThreeDrawnRegions`.
    @Test func headerCountsOnlyMediaItCanDraw() throws {
        let src = try Self.source("MemoryStream/Views/Inbox/SessionListView.swift")
        let body = try Self.blockBody(startingAtLineContaining: "private func header(_ render: BenchRender)", in: src)
        let code = Self.codeOnly(body)
        #expect(code.contains("render.drawnCount"),
                """
                The header does not read the composed count. Every version of this defect \
                (F35(a), F38, F40, F44) was a number the header computed for itself. \
                Body was:
                \(body)
                """)
        #expect(code.contains("benchItems") == false && code.contains("+ ") == false,
                """
                The header is assembling a count from parts again — that is the \
                three-numbers-two-sets shape, whatever the parts happen to be. Body was:
                \(body)
                """)
    }

    /// **Mechanism, not memory** — and the mechanism changed shape in C2
    /// step 2b, so this now guards the new one.
    ///
    /// The old form counted the literal `sessions = computeSessions()`, which
    /// the troika showed was defeatable by a second writer spelled differently
    /// (`computeSessions(applyFilter: false)` left it green). What it was
    /// reaching for is that bench state has exactly one writer.
    ///
    /// Grouping itself is no longer state — it is a pure function of
    /// `benchItems`, and `RenderedBenchTests.composingTwiceFromTheSameInputs\
    /// YieldsTheSameValue` covers that half behaviourally. What remains
    /// assignable, and therefore ownable, is `benchItems` itself.
    @Test func regroupingHasExactlyOneOwner() throws {
        let src = try Self.source("MemoryStream/Views/Inbox/SessionListView.swift")
        let code = Self.codeOnly(src)
        // Count assignments, not mentions. The `@State` declaration reads
        // `benchItems: [BenchClipItem] = []`, which this pattern deliberately
        // does not match — so the expected count is exactly the one real
        // writer. (Written as 2 first, on the assumption the declaration would
        // match; the guard failed and corrected the assumption, which is the
        // only way a guard earns trust.)
        let writes = code.components(separatedBy: "benchItems = ").count - 1
        #expect(writes == 1,
                """
                `benchItems` is written from \(writes) places, expected 1 \
                (`recomposeBench()`). A second writer is how the absorbed-media map went \
                stale in the first place — four of five sites remembered to pair the \
                update and one did not.
                """)
        #expect(code.contains("private func recomposeBench()"),
                "The single owner is gone or renamed; this guard is now pinned to nothing.")
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
    ///
    /// **Wrong in both directions three times now, so it pins the INVARIANT.**
    /// F40's form accepted a mere declaration (an unused parameter satisfied
    /// it); F44's form pinned one exact call expression and broke on a correct
    /// change; this form pinned `mediaFor: media(forCluster:)` and broke again
    /// on 2026-08-05, when the argument correctly became a closure over the
    /// composed bench. The promise — *the card is supplied its media, from the
    /// bench* — has been intact every time. Assert that, not the spelling.
    @Test func theBenchSuppliesTheClusterItsMedia() throws {
        let src = try Self.source("MemoryStream/Views/Inbox/SessionListView.swift")
        let code = try Self.callArguments(ofCallStartingAtLineContaining: "ClusterCardStack(", in: src)
        let construction = code
        // Self-test: the extractor must span the whole argument list, not one
        // line. `subtitleFor:` sits on a different line from `mediaFor:`, so
        // requiring both proves the window is wide — the exact failure that
        // let the brace-based version pass while seeing a single line.
        #expect(code.contains("subtitleFor:"),
                "The construction window collapsed — `callArguments` is not spanning the call.")
        #expect(code.contains("mediaFor:"),
                "`ClusterCardStack` is constructed without media, so the parameter draws nothing.")
        #expect(code.contains("media(forCluster:"),
                """
                `mediaFor:` is supplied but does not reach `media(forCluster:)`, so the \
                card draws whatever that argument happens to be. Construction was:
                \(construction)
                """)
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

    /// **The composed render is THREADED DOWN, never recomputed per call site**
    /// (device, 2026-08-05 — Clips locked the phone and did not recover).
    ///
    /// `render(now:)` is not a cheap accessor. It performs *two*
    /// `RenderedBench.compose` passes plus `ClipClusterProposer.propose`, and
    /// `propose` reaches `LocalEntityExtractor.shared` — a live **NLTagger
    /// named-entity pass over every session's full transcript**, synchronously,
    /// on the main thread.
    ///
    /// C2 step 2b-ii handed `media(forCluster:)` to `ClusterCardStack` as a
    /// *function reference*, and the card calls it ~4× per card (`:247`, `:248`,
    /// `keptTotal` at `:347`, `"Show all N"` at `:516`), with `clusterSubtitle`
    /// reaching it a fifth time. Each call recomposed the whole bench. A frame
    /// with K clusters therefore ran **1 + ~4K** NLP passes inside `body`, and
    /// the `onChange`/`onReceive` handlers each scheduled another via
    /// `registerSessionIds()`. That is a **livelock, not slowness**: no lock is
    /// held, so nothing deadlocks, but forward progress never completes and it
    /// does not recover.
    ///
    /// The file's own comment at `:146` already promised this — *"Composed ONCE
    /// per render and threaded down… nothing recomputes a set of its own"* —
    /// while four functions recomputed it. Guard-the-caller, inside the rebuild
    /// written to end that class.
    @Test func theComposedRenderIsThreadedDownNotRecomputedPerCallSite() throws {
        let src = try Self.source("MemoryStream/Views/Inbox/SessionListView.swift")
        // `blockBody` throws when a needle is absent, so a rename fails this
        // guard loudly rather than letting it pass by matching nothing.
        let mustNotRecompose = [
            "private func media(forCluster proposal: ClusterProposal",
            "private func includedClusterMedia(",
            "private func clusterSubtitle(",
            "private func registerSessionIds(",
        ]
        for needle in mustNotRecompose {
            let body = try Self.blockBody(startingAtLineContaining: needle, in: src)
            #expect(Self.codeOnly(body).contains("render()") == false,
                    """
                    `\(needle)` calls `render()`, recomposing the entire bench — two \
                    compose passes plus an NLTagger named-entity sweep over every \
                    transcript — for one lookup. Called from `body` per cluster card \
                    this is the 2026-08-05 livelock. Take the already-composed value \
                    as a parameter instead. Body was:
                    \(body)
                    """)
        }
    }

    // MARK: - Source access

    static func codeOnly(_ source: String) -> String {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let marker = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<marker.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// The ARGUMENT LIST of a parenthesised call, delimited by **paren** depth.
    ///
    /// `blockBody` counts BRACES, so on a call whose argument is a closure that
    /// opens and closes on one line, depth goes 0→1→0 and it terminates after
    /// that single line. On 2026-08-05 that made
    /// `theBenchSuppliesTheClusterItsMedia` pass while seeing exactly one line
    /// of a fourteen-line construction — it happened to be the line carrying
    /// both strings the guard checked. **Green for the wrong reason**, the
    /// `loudPeakThenSilence` shape, in a guard written to catch that shape.
    ///
    /// Runs over comment-stripped source so a paren inside a comment cannot
    /// unbalance the scan.
    static func callArguments(ofCallStartingAtLineContaining needle: String, in source: String) throws -> String {
        let lines = codeOnly(source)
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains(needle) }) else {
            throw Failure.blockNotFound(needle)
        }
        var depth = 0, started = false
        var out: [String] = []
        for line in lines[start...] {
            out.append(line)
            for ch in line {
                if ch == "(" { depth += 1; started = true }
                if ch == ")" { depth -= 1 }
            }
            if started && depth <= 0 { break }
        }
        return out.joined(separator: "\n")
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
