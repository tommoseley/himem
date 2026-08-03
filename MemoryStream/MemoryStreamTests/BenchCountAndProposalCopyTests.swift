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

    @Test func headerCountsOnlyMediaItCanDraw() throws {
        let src = try Self.source("MemoryStream/Views/Inbox/SessionListView.swift")
        let body = try Self.blockBody(startingAtLineContaining: "private var headerTitle: String {", in: src)
        let code = Self.codeOnly(body)
        #expect(code.contains("absorbedMediaBySessionId.values") == false,
                """
                `headerTitle` sums every absorbed-media entry regardless of whether a \
                session with that key renders. A card looks the media up by session id, \
                so anything keyed to a session outside the lens is counted and undrawable. \
                Body was:
                \(body)
                """)
        #expect(code.contains("sessions"),
                "`headerTitle` does not scope the absorbed-media count to the sessions it describes.")
    }

    /// **Mechanism, not memory.** If `sessions` and the absorbed-media map
    /// must always move together, one function moves them — rather than five
    /// call sites each remembering to.
    @Test func regroupingHasExactlyOneOwner() throws {
        let src = try Self.source("MemoryStream/Views/Inbox/SessionListView.swift")
        let code = Self.codeOnly(src)
        let assignments = code.components(separatedBy: "sessions = computeSessions()").count - 1
        #expect(assignments == 1,
                """
                `sessions` is assigned from \(assignments) places. Four of the five original \
                sites also refreshed the absorbed-media map and one did not (:239, the \
                remove-clip-from-session regroup), which is how the map went stale. \
                Regrouping needs one owner.
                """)
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
