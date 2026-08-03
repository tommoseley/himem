import Testing
import Foundation
@testable import HiMem

/// **F43 · the cluster card described its original membership and committed
/// something different again.**
///
/// Observed on `89e77df`: header read *"7 clips from 3 sittings · 125
/// minutes apart"* while the card showed 3 kept and 4 set aside.
///
/// **Two of the three numbers were coincidentally right, which is the
/// dangerous half.** `whyText` is a stored `let` computed once from the
/// ORIGINAL sessions; the trim lives in `removedByFingerprint` and never
/// feeds back. In that screenshot the kept set happened to retain both
/// extremes (6:53 and 8:58), so "3 sittings" and "125 minutes apart" were
/// accurate by accident. Set aside the 8:58 and the span becomes silently
/// wrong while still looking plausible. **A partially-correct display is
/// more dangerous than a visibly broken one**, and it is why the guard must
/// pin that the header DESCRIBES THE KEPT SET rather than merely that a
/// subtitle renders — three guards in a row tested the symptom.
///
/// **And the commit disagreed with the card in the opposite direction from
/// the one assumed.** `addClusterToMemory` passed `absorbedMediaRefs: []`
/// while both session paths pass `includedAbsorbedMedia(in:)`. So no photo
/// was ever committed from a cluster: bundling stranded them on the bench
/// while the voice clips moved into the memory. Not introduced today — but
/// F40 made it load-bearing, because the card now says the photos are in
/// while the commit says they are out. The day's recurring shape once more:
/// a confident display over a path that disagrees.
///
/// Ordering matters and was ruled: the commit fix comes FIRST. Set-aside for
/// media without it would build a control that changes nothing — excluding a
/// photo that was never going to be committed anyway.
@Suite struct ClusterKeptSetTests {

    // MARK: - The commit must carry what the card claims

    @Test func theClusterCommitCarriesItsKeptMedia() throws {
        let src = try Self.source("MemoryStream/Views/Inbox/SessionListView.swift")
        let body = try Self.blockBody(startingAtLineContaining: "private func addClusterToMemory(", in: src)
        let code = Self.codeOnly(body)
        #expect(code.contains("absorbedMediaRefs: []") == false,
                """
                `addClusterToMemory` commits an EMPTY media array while both session paths \
                pass `includedAbsorbedMedia(in:)`. The card counts and shows the photos; the \
                commit drops them, stranding them on the bench. Body was:
                \(body)
                """)
        #expect(code.contains("keptMedia") || code.contains("includedClusterMedia"),
                "The cluster commit does not resolve its kept media at all.")
    }

    // MARK: - The header must describe the kept set

    /// **The invariant, not the symptom.** `proposal.whyText` is frozen at
    /// construction; rendering it can never reflect a trim.
    @Test func theHeaderDescribesTheKeptSetNotTheProposal() throws {
        let src = try Self.source("MemoryStream/Views/Inbox/ClusterCardStack.swift")
        let code = Self.codeOnly(src)
        #expect(code.contains("proposal.whyText") == false,
                """
                The card renders `proposal.whyText`, which is a stored `let` computed once \
                from the ORIGINAL membership. It cannot change when a clip is set aside, so \
                the header describes a set the card is not showing.
                """)
        #expect(code.contains("subtitleFor"),
                "The card has no kept-set subtitle source.")
    }

    /// The caller must supply it — an unused parameter is the shape that
    /// slipped past the F40 guard.
    @Test func theBenchSuppliesTheKeptSetSubtitle() throws {
        let src = try Self.source("MemoryStream/Views/Inbox/SessionListView.swift")
        #expect(Self.codeOnly(src).contains("subtitleFor: clusterSubtitle"),
                "`ClusterCardStack` is constructed without a kept-set subtitle source.")
    }

    // MARK: - Media must be excludable, and the vocabulary must not borrow

    @Test func mediaCanBeSetAsideLikeVoiceClips() throws {
        let src = try Self.source("MemoryStream/Views/Inbox/ClusterCardStack.swift")
        let body = try Self.blockBody(startingAtLineContaining: "private func editorRows(", in: src)
        let code = Self.codeOnly(body)
        #expect(code.contains("mediaFor"),
                """
                The cluster's editor rows list voice clips only, so a photo cannot be \
                excluded from the proposal. Committing takes it regardless — a data-shaping \
                decision taken away from the user. Body was:
                \(body)
                """)
    }

    /// "Not in this memory" borrows a noun from a container that does not
    /// exist yet — the user has not decided to make a memory.
    @Test func theSetAsideHeadingMintsNoContainer() throws {
        let src = try Self.source("MemoryStream/Views/Inbox/ClusterCardStack.swift")
        let code = Self.codeOnly(src)
        #expect(code.contains("\"Not in this memory\"") == false,
                """
                The set-aside block still says "Not in this memory" on a bench cluster where \
                no memory exists — and "this memory" implies one has been created, which is \
                exactly the decision the user has not made.
                """)
        #expect(code.contains("ClusterCardCopy.setAside"),
                "The set-aside heading is not the ruled copy.")
    }


    // MARK: - The subtitle must MOVE when a clip is set aside (behavioural)

    /// **The invariant the three previous guards missed.** Pinning that a
    /// subtitle renders proves nothing; this pins that its output tracks the
    /// kept set.
    @Test func theSubtitleChangesWhenAClipIsSetAside() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let all = [t, t.addingTimeInterval(50 * 60), t.addingTimeInterval(125 * 60)]
        let full = ClusterSubtitleBuilder.subtitle(clipCount: 3, sittingCount: 3, capturedAts: all)
        let trimmed = ClusterSubtitleBuilder.subtitle(
            clipCount: 2, sittingCount: 2, capturedAts: Array(all.prefix(2))
        )
        #expect(full != trimmed, "the subtitle is identical after a trim — it is not reading the kept set")
        #expect(full.hasPrefix("3 clips"))
        #expect(trimmed.hasPrefix("2 clips"))
    }

    /// **The coincidence that made this dangerous.** With both endpoints
    /// kept, the span is unchanged — so the span alone can look right while
    /// the count is wrong. Removing an ENDPOINT is what must move it.
    @Test func theSpanShrinksOnlyWhenAnEndpointGoes() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let all = [t, t.addingTimeInterval(50 * 60), t.addingTimeInterval(125 * 60)]
        let middleGone = ClusterSubtitleBuilder.subtitle(
            clipCount: 2, sittingCount: 2, capturedAts: [all[0], all[2]]
        )
        #expect(middleGone.contains("125 minutes apart"),
                "dropping a middle clip must not change the span")
        let endpointGone = ClusterSubtitleBuilder.subtitle(
            clipCount: 2, sittingCount: 2, capturedAts: [all[0], all[1]]
        )
        #expect(endpointGone.contains("50 minutes apart"),
                "dropping the last clip must shrink the span — this is the silently-wrong case")
    }

    /// Singulars, since a trim can reach one of anything.
    @Test func theSubtitleReadsCorrectlyAtOne() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let one = ClusterSubtitleBuilder.subtitle(clipCount: 1, sittingCount: 1, capturedAts: [t])
        #expect(one == "1 clip from 1 sitting · 1 minute apart")
    }

    /// The ruled copy, pinned — and it must mint no container noun.
    @Test func theSetAsideCopyIsTheRuledLine() {
        #expect(ClusterCardCopy.setAside == "Set aside")
        for noun in ["memory", "group", "collection"] {
            #expect(ClusterCardCopy.setAside.lowercased().contains(noun) == false)
        }
    }


    // MARK: - F44 · the card's THREE numbers come from ONE kept-set value

    /// **The guard the previous five could not have caught.** Each earlier
    /// guard pinned one term against one set. This pins that the card's
    /// subtitle, composition glyphs and expander label all read the SAME
    /// kept-set source — so a seventh term cannot quietly describe a sixth
    /// set.
    @Test func allThreeCardNumbersReadTheKeptSet() throws {
        let src = try Self.source("MemoryStream/Views/Inbox/ClusterCardStack.swift")
        let code = Self.codeOnly(src)

        // Glyphs: kept media, not every absorbed ref.
        #expect(code.contains("clusterMediaRow(keptMedia(proposal))"),
                "The composition glyphs count set-aside media — a second set on the same card.")
        #expect(code.contains("clusterMediaRow(mediaFor(proposal))") == false,
                "The glyph row still reads the untrimmed media.")

        // Expander: kept clips + kept media, not the frozen original.
        #expect(code.contains("Show all \\(keptTotal(proposal))"),
                """
                "Show all N" still counts `proposal.clipIds` — voice only, original \
                membership — while the subtitle counts the kept set including media.
                """)
        #expect(code.contains("proposal.clipIds.count") == false,
                "The expander label reads the proposal's original membership.")

        // And the subtitle keeps reading kept (F43), so all three agree.
        #expect(code.contains("subtitleFor(proposal, keptClips(proposal))"))
    }

    /// The three numbers must be *derivable from each other* — the expander
    /// total is exactly kept clips plus kept media, which is what the
    /// subtitle counts. Pins the arithmetic relationship, not just the
    /// call sites.
    @Test func theExpanderTotalIsTheSubtitleTotal() throws {
        let src = try Self.source("MemoryStream/Views/Inbox/ClusterCardStack.swift")
        let body = try Self.blockBody(startingAtLineContaining: "private func keptTotal(", in: src)
        let code = Self.codeOnly(body)
        #expect(code.contains("keptClips(proposal).count + keptMedia(proposal).count"),
                "The expander total is not kept clips + kept media, so it cannot match the subtitle.")
    }

    /// **A set-aside clip is still hers.** It is new, unconnected, and must
    /// return to the loose list rather than disappearing from the bench —
    /// hiding it is the subtractive posture J2 retired.
    @Test func setAsideReturnsTheClipToTheLooseList() throws {
        let src = try Self.source("MemoryStream/Views/Inbox/SessionListView.swift")
        let body = try Self.blockBody(startingAtLineContaining: "private var looseSessions:", in: src)
        let code = Self.codeOnly(body)
        #expect(code.contains("proposals.flatMap(\\.clipIds)") == false,
                """
                `looseSessions` treats the proposal's ORIGINAL membership as clustered, so a \
                clip removed from the proposal vanishes from the bench as well. Body was:
                \(body)
                """)
        #expect(code.contains("removedByFingerprint"),
                "`looseSessions` does not consult the trim, so set-aside clips stay hidden.")
        #expect(code.contains("ClipGroup(clips: remaining)"),
                "A partially-kept session is not rendered with its remaining clips.")
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
