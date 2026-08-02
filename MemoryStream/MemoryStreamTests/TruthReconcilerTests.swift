import Testing
import Foundation
@testable import HiMem

/// Money tests for `TruthReconciler` — one Honest-Label gate for all AI
/// organize output, tier-independent (supersedes `HonestLabelGate`,
/// 2026-07-23). The gate catches a proper name in the summary the clips don't
/// contain — deterministic, so it holds no matter how Apple's (or Anthropic's)
/// model drifts.
///
/// The modes below are exercised as a LIBRARY. They are not a per-tier split
/// in the organize pipeline: summary/title grounding runs `.relaxed` on BOTH
/// tiers, and `.strict` governs only the ungrounded-mention drop. This header
/// said "`.strict` on-device, `.relaxed` on the frontier path" — the same
/// false claim corrected in three production docs on 2026-07-31, and missed
/// here by that sweep because it only scanned production. Wiring pinned by
/// `GroundingStrictnessWiringTests`.
@Suite
struct TruthReconcilerTests {

    /// The exact reported failure: a Lincoln-only memory whose on-device
    /// draft fabricated "Ben" (not in the clips, not in the library). The
    /// gate must flag it under strict grounding.
    @Test func lincolnFabrication_flagsInventedSpeaker() {
        let clips = "I am not bound to win, but I am bound to be true. I am not bound to succeed, but I'm bound to live up to what light I have."
        let summary = "You, Ben, captured two clips reflecting on truth and moral duty."
        let bad = TruthReconciler.fabricatedEntities(in: summary, sourceText: clips, strictness: .strict)
        #expect(bad.contains("Ben"))
        #expect(TruthReconciler.violates(summary: summary, sourceText: clips, strictness: .strict))
    }

    /// The invent-a-speaker variants seen in the QA panel ("Albert",
    /// "Arnold") — a banned-string list missed them; the gate catches ANY
    /// invented proper noun. And a wholly-invented name has no token in
    /// common with the clips, so it fails on the RELAXED tier too — the
    /// paraphrase allowance never launders a fabrication.
    @Test func inventedSpeakerVariants_allFlagged_bothTiers() {
        let clips = "A quote about being true and living up to what light you have."
        for name in ["Albert", "Arnold", "Darlene", "Ben"] {
            let summary = "You, \(name), shared a quote."
            #expect(TruthReconciler.violates(summary: summary, sourceText: clips, strictness: .strict), "\(name) must be caught (strict)")
            #expect(TruthReconciler.violates(summary: summary, sourceText: clips, strictness: .relaxed), "\(name) must be caught (relaxed)")
        }
    }

    /// A name that IS in the clips is legitimate — never flagged (no false
    /// positive that would needlessly downgrade an honest summary).
    @Test func nameActuallyInClips_notFlagged() {
        let clips = "Walked the market with Darlene. She wanted the Basque cheesecake place Ben kept talking about."
        let summary = "You walked the market with Darlene, and found the Basque cheesecake place Ben kept mentioning."
        #expect(TruthReconciler.fabricatedEntities(in: summary, sourceText: clips, strictness: .strict).isEmpty)
        #expect(!TruthReconciler.violates(summary: summary, sourceText: clips, strictness: .strict))
    }

    @Test func multiWordProperNoun_inClips_notFlagged_butFabricatedIsFlagged() {
        let clips = "South Carolina summer is brutal on the garden by noon."
        #expect(TruthReconciler.fabricatedEntities(in: "You're tending the garden while South Carolina summer bakes it.", sourceText: clips, strictness: .strict).isEmpty)
        // A multi-word name absent from the clips is caught as a unit.
        let bad = TruthReconciler.fabricatedEntities(in: "You, Abraham Lincoln, spoke.", sourceText: clips, strictness: .strict)
        #expect(bad.contains("Abraham Lincoln"))
    }

    /// The relaxed/frontier tier: a legitimate paraphrase — the model
    /// expanding "Lincoln" the clips contain to "Abraham Lincoln", or
    /// contracting it — shares a distinctive token, so it is grounded under
    /// `.relaxed` but flagged under `.strict`. This is the whole point of the
    /// two tiers: Plus's good paraphrase isn't downgraded, the guarantee holds.
    @Test func relaxedGrounding_allowsParaphraseOfInSourceName() {
        let clips = "Reading Lincoln tonight — the second inaugural still lands."
        // Frontier expanded "Lincoln" → "Abraham Lincoln".
        let expanded = "You reflected on Abraham Lincoln and the second inaugural."
        #expect(TruthReconciler.violates(summary: expanded, sourceText: clips, strictness: .strict), "strict flags the expansion")
        #expect(!TruthReconciler.violates(summary: expanded, sourceText: clips, strictness: .relaxed), "relaxed grounds the paraphrase")
        // But a genuinely different name is still caught on relaxed.
        let fabricated = "You reflected on Abraham Lincoln and Frederick Douglass."
        #expect(TruthReconciler.violates(summary: fabricated, sourceText: clips, strictness: .relaxed), "relaxed still catches an unrelated name")
    }

    /// Pronouns/determiners the second-person voice uses ("You're", "The")
    /// are not names — never flagged even though they're absent from a
    /// first-person clip.
    @Test func pronounsAndStopwords_notFlagged() {
        let clips = "I'm out in the garden this morning before it got too hot."
        let summary = "You're out in the garden this morning, and the heat is coming."
        #expect(TruthReconciler.fabricatedEntities(in: summary, sourceText: clips, strictness: .strict).isEmpty)
    }

    /// The extractive fallback is drawn from the clips, so it can never
    /// introduce a name the source lacks — and it itself passes the gate on
    /// both tiers.
    @Test func extractiveFallback_cannotFabricate_andPassesGate() {
        let clips = "I am not bound to win, but I am bound to be true. I am not bound to succeed."
        let fallback = TruthReconciler.extractiveSummary(fromClipText: clips)
        #expect(fallback == "I am not bound to win, but I am bound to be true")
        #expect(!TruthReconciler.violates(summary: fallback, sourceText: clips, strictness: .strict))
        #expect(!TruthReconciler.violates(summary: fallback, sourceText: clips, strictness: .relaxed))
    }

    @Test func extractiveFallback_emptyClips_returnsPlainDescriptor() {
        #expect(TruthReconciler.extractiveSummary(fromClipText: "   ") == "A captured moment.")
    }

    /// `reconcileMentions` routes through `MentionReconciler` (TruthReconciler's
    /// first module) — the umbrella exposes the same conservative dedup.
    @Test func reconcileMentions_collapsesVariantsViaModule() {
        let out = TruthReconciler.reconcileMentions(extracted: ["Darlene"], library: ["Darlene G."])
        #expect(out == ["Darlene G."])
        // Different token → kept as-is (never mis-merged).
        #expect(TruthReconciler.reconcileMentions(extracted: ["Ben"], library: ["Benjamin"]) == ["Ben"])
    }

    // MARK: - Structural-claim leakage (the "text clip 1 / two video clips" bug)

    /// The exact reported failure: a Lincoln voice+photo memory whose summary
    /// narrates clip scaffolding. The proper-noun check misses it (lowercase
    /// common words); the structural check catches `clip`/`clips`/`video`, and
    /// `violates` fires on both tiers.
    @Test func structuralLeak_clipAndMediaWords_flagged() {
        let clips = "I am not bound to win, but I am bound to be true."
        let summary = "You, while reflecting on the quote, held two memories: text clip 1 and two video clips."
        let hits = TruthReconciler.fabricatedStructuralClaims(in: summary, sourceText: clips)
        #expect(hits.contains("clip"))
        #expect(hits.contains("clips"))
        #expect(hits.contains("video"))
        #expect(TruthReconciler.violates(summary: summary, sourceText: clips, strictness: .strict))
        #expect(TruthReconciler.violates(summary: summary, sourceText: clips, strictness: .relaxed))
        // The proper-noun path alone would NOT have caught it.
        #expect(TruthReconciler.fabricatedEntities(in: summary, sourceText: clips, strictness: .strict).isEmpty)
    }

    /// If the clips genuinely use a media word, the summary may too — grounded,
    /// not flagged (no false positive when the content is really about video).
    @Test func structuralWord_presentInClips_notFlagged() {
        let clips = "Spent the afternoon editing a video of the garden — the light was perfect."
        let summary = "You edited a video of the garden while the light held."
        #expect(TruthReconciler.fabricatedStructuralClaims(in: summary, sourceText: clips).isEmpty)
        #expect(!TruthReconciler.violates(summary: summary, sourceText: clips, strictness: .strict))
    }

    /// The extractive fallback is drawn from the clips, so it can't introduce a
    /// structural word the source lacks — it passes the structural check too.
    @Test func extractiveFallback_hasNoStructuralLeak() {
        let clips = "I am not bound to win, but I am bound to be true."
        let fallback = TruthReconciler.extractiveSummary(fromClipText: clips)
        #expect(TruthReconciler.fabricatedStructuralClaims(in: fallback, sourceText: clips).isEmpty)
    }
}
