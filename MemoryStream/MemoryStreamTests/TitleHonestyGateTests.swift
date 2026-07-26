import Testing
@testable import HiMem

/// Money tests for the title-honesty gate (P1-2, 2026-07-25). The summary gate
/// (`violates(summary:)`) is deliberately summary-only — the model title-cases
/// every word, so its mid-sentence-capitalization heuristic is noise on a
/// title. That let two Honest-Label failures slip through on the TITLE:
///  1. an invented author — "Ralph Waldo Emerson's Reflection" on an
///     unattributed quote, and
///  2. a raw verbatim clip quote as the title — "I am not bound to win" reads
///     as the user's own words.
/// `titleViolates` catches both; the fallback is a STRUCTURAL title (never the
/// clip lead, which would reproduce the quote).
struct TitleHonestyGateTests {

    /// The Lincoln-quote memory: the clips are an UNATTRIBUTED quotation, so a
    /// title naming "Ralph Waldo Emerson" fabricates an author.
    private let unattributedQuote = "I am not bound to win, but I am bound to be true. I am not bound to succeed, but I am bound to live up to what light I have."

    @Test func fabricatedAuthorInTitle_isCaught() {
        #expect(TruthReconciler.titleViolates(
            title: "Ralph Waldo Emerson's Reflection",
            sourceText: unattributedQuote, strictness: .relaxed))
        // And it is precisely the summary gate's blind spot: the title-name
        // check reports the ungrounded multi-word run.
        #expect(!TruthReconciler.fabricatedTitleNames(
            in: "Ralph Waldo Emerson's Reflection",
            sourceText: unattributedQuote, strictness: .relaxed).isEmpty)
    }

    @Test func verbatimQuoteFragmentTitle_isCaught() {
        // A ≥5-word title copied verbatim from the clips.
        #expect(TruthReconciler.titleViolates(
            title: "I am not bound to win",
            sourceText: unattributedQuote, strictness: .relaxed))
    }

    @Test func groundedName_isAllowed() {
        // The frontier expansion "Abraham Lincoln" over clips that say "Lincoln"
        // is grounded (relaxed) — NOT a fabrication.
        let clips = "A note about Lincoln and the war years."
        #expect(!TruthReconciler.titleViolates(title: "Abraham Lincoln", sourceText: clips, strictness: .relaxed))
        // A real place run that IS in the clips.
        let sc = "We drove through South Carolina to the coast."
        #expect(!TruthReconciler.titleViolates(title: "South Carolina Trip", sourceText: sc, strictness: .relaxed))
    }

    @Test func ordinaryEditorialTitle_isNotFalseFlagged() {
        // Single title-cased words separated by a stopword are editorial
        // framing, not a name run — must not fire.
        let clips = "Thinking through what integrity means when no one is watching."
        #expect(!TruthReconciler.titleViolates(title: "A Reflection on Integrity", sourceText: clips, strictness: .relaxed))
        #expect(!TruthReconciler.titleViolates(title: "Garden Notes", sourceText: "Planting the spring garden beds today.", strictness: .relaxed))
    }

    @Test func structuralTitle_isTopicBasedOrPlain() {
        #expect(TruthReconciler.structuralTitle(topics: ["integrity"]) == "Integrity")
        #expect(TruthReconciler.structuralTitle(topics: []) == "A captured moment")
        #expect(TruthReconciler.structuralTitle(topics: ["  "]) == "A captured moment")
    }

    /// The blind-spot proof: a fabricated-author title on a memory whose SUMMARY
    /// is clean. The summary gate never sees the title, so only `titleViolates`
    /// stops it — exactly the gap P1-2 closes.
    @Test func cleanSummary_fabricatedTitle_onlyTitleGateStopsIt() {
        let cleanSummary = "You're reflecting on staying true to your own conscience."
        #expect(!TruthReconciler.violates(summary: cleanSummary, sourceText: unattributedQuote, strictness: .relaxed))
        #expect(TruthReconciler.titleViolates(title: "Ralph Waldo Emerson's Reflection",
                                              sourceText: unattributedQuote, strictness: .relaxed))
    }
}
