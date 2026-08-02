import Testing
import Foundation
@testable import HiMem

/// **F33 · Memory Detail is a PROGRESSION, not a form (ruled 2026-08-01).**
///
///   Unorganized:  title → (summary, if any) → parts → Organize → Delete
///   Organized:    title → summary → parts → topics → projects → mentions
///                 → Organize → Delete, and every section keeps rendering
///                 even if she later empties it.
///
/// It reads *"here's what you recorded → want it organized? → now refine
/// the result"*, instead of asking someone to edit three empty fields
/// before any work has been done.
///
/// **This supersedes part of F19b.** F19b ruled that the summary slot
/// "always exists", with an "Add a summary" invite when empty. F19b was
/// right that a phantom placeholder had to become real; it was wrong
/// about *when*. On an unorganized memory the invite asked her to fill a
/// blank before anything had happened. The slot still exists once there
/// is a summary — the invite is what is retired.
///
/// **F19a's reorder was the same instinct one step earlier**: it moved
/// the empty metadata rows *below* the content. This removes them until
/// they mean something.
///
/// Source-level by necessity — the layout is SwiftUI view structure that
/// no unit test can render. The invariants asserted are structural.
@Suite struct MemoryDetailProgressionTests {

    /// The three metadata sections must be gated on the organized
    /// signal. Ungated is the defect: three empty `+ Edit` rows on a
    /// page where nothing has been organized yet.
    @Test func metadataSectionsAreGatedOnHavingBeenOrganized() throws {
        let src = try Self.source()
        #expect(src.contains("private var hasBeenOrganized: Bool"),
                "The organized gate is gone — the metadata sections cannot be conditional without it.")

        let body = try Self.functionBody(named: "if hasBeenOrganized {", in: src)
        for section in ["topicChipsRow", "projectSection", "mentionsSection"] {
            #expect(body.contains(section),
                    "`\(section)` is outside the organized gate — it renders empty on an unorganized memory.\n\(body)")
        }
    }

    /// Organize and Delete must stay OUTSIDE the gate — they are the
    /// whole point of the unorganized page. Gating Organize would leave
    /// a memory with no way to become organized at all.
    @Test func organizeAndDeleteRenderRegardlessOfState() throws {
        let src = try Self.source()
        let gated = try Self.functionBody(named: "if hasBeenOrganized {", in: src)
        #expect(gated.contains("OrganizeMemorySection") == false,
                "Organize is inside the organized gate — an unorganized memory could never be organized.")
        #expect(gated.contains("BottomDeleteButton") == false && gated.contains("letGo") == false,
                "Delete is inside the organized gate.")
    }

    /// The gate reads the SAME signal the walkthrough reads, so the page
    /// and the guided flow cannot disagree about which state she is in.
    @Test func theGateUsesTheWalkthroughsOrganizedSignal() throws {
        let src = try Self.source()
        let decl = try Self.functionBody(named: "private var hasBeenOrganized: Bool", in: src)
        #expect(decl.contains("inferenceSummary"),
                "The gate uses a different organized signal than `memoryDidOpen(alreadyOrganized:)`.\n\(decl)")
        #expect(src.contains("alreadyOrganized: entry.inferenceSummary != nil"),
                "The walkthrough's signal moved — re-align the gate with it.")
    }

    /// **F19b's empty invite is retired.** Pinned as a literal because
    /// the copy is the subject: a failure means the invite came back.
    @Test func theEmptySummaryInviteIsGone() throws {
        let src = try Self.source()
        let section = try Self.functionBody(named: "private var summarySection: some View", in: src)
        #expect(section.contains("summaryEmptyInvite") == false,
                "The empty-summary invite is rendering again — F33 retired it.\n\(section)")
    }

    /// **The green "Processed" pill is gone.** It rendered only while
    /// unorganized, announcing a pipeline state she never asked about —
    /// and green is semantic (confirmed/success) when nothing had
    /// succeeded yet.
    @Test func theProcessedStatusPillIsGone() throws {
        let src = try Self.source()
        #expect(src.contains("StatusBadge(text: status.text") == false,
                "The status pill is back on Memory Detail.")
    }

    /// **The FAB steps aside for the Organize card unconditionally.**
    /// The old `!topAnchorVisible` qualifier meant "only after a
    /// deliberate scroll" — but a short memory shows the top anchor AND
    /// the card at once, so the FAB sat on top of it. F33 makes
    /// unorganized memories shorter, which is what surfaced it.
    @Test func theFabStepsAsideForOrganizeWithoutRequiringAScroll() throws {
        let src = try Self.source()
        #expect(src.contains("&& !organizeOnScreen"),
                "The FAB no longer yields to the Organize card on its own — it will overlap on a short memory.")
        #expect(src.contains("(letGoOnScreen || organizeOnScreen) && !topAnchorVisible") == false,
                "The old coupled condition is back; Organize is again gated on a scroll.")
    }

    // MARK: - Source access

    static func functionBody(named needle: String, in source: String) throws -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains(needle) }) else {
            throw Failure.notFound(needle)
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
        throw Failure.notFound(needle)
    }

    static func source() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MemoryStream/Views/Journal/EntryExpandedView.swift")
        guard let src = try? String(contentsOf: url, encoding: .utf8), !src.isEmpty else {
            throw Failure.sourceNotFound(url.path)
        }
        return src
    }

    enum Failure: Error { case sourceNotFound(String), notFound(String) }
}
