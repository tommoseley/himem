import Testing
import Foundation
@testable import HiMem

/// Money tests for `HonestLabelGate` — the code-side Honest-Label verifier
/// for the on-device organize path (iOS 27 on-device regression, 2026-07-23).
/// The gate catches a proper name in the summary that the clips don't
/// contain — deterministic, so it holds no matter how Apple's model drifts.
@Suite
struct HonestLabelGateTests {

    /// The exact reported failure: a Lincoln-only memory whose on-device
    /// draft fabricated "Ben" (not in the clips, not in the library). The
    /// gate must flag it.
    @Test func lincolnFabrication_flagsInventedSpeaker() {
        let clips = "I am not bound to win, but I am bound to be true. I am not bound to succeed, but I'm bound to live up to what light I have."
        let summary = "You, Ben, captured two clips reflecting on truth and moral duty."
        let bad = HonestLabelGate.fabricatedProperNouns(in: summary, sourceText: clips)
        #expect(bad.contains("Ben"))
        #expect(HonestLabelGate.violates(summary: summary, sourceText: clips))
    }

    /// The invent-a-speaker variants seen in the QA panel ("Albert",
    /// "Arnold") — a banned-string list missed them; the gate catches ANY
    /// invented proper noun.
    @Test func inventedSpeakerVariants_allFlagged() {
        let clips = "A quote about being true and living up to what light you have."
        for name in ["Albert", "Arnold", "Darlene", "Ben"] {
            let summary = "You, \(name), shared a quote."
            #expect(HonestLabelGate.violates(summary: summary, sourceText: clips), "\(name) must be caught")
        }
    }

    /// A name that IS in the clips is legitimate — never flagged (no false
    /// positive that would needlessly downgrade an honest summary).
    @Test func nameActuallyInClips_notFlagged() {
        let clips = "Walked the market with Darlene. She wanted the Basque cheesecake place Ben kept talking about."
        let summary = "You walked the market with Darlene, and found the Basque cheesecake place Ben kept mentioning."
        #expect(HonestLabelGate.fabricatedProperNouns(in: summary, sourceText: clips).isEmpty)
        #expect(!HonestLabelGate.violates(summary: summary, sourceText: clips))
    }

    @Test func multiWordProperNoun_inClips_notFlagged_butFabricatedIsFlagged() {
        let clips = "South Carolina summer is brutal on the garden by noon."
        #expect(HonestLabelGate.fabricatedProperNouns(in: "You're tending the garden while South Carolina summer bakes it.", sourceText: clips).isEmpty)
        // A multi-word name absent from the clips is caught as a unit.
        let bad = HonestLabelGate.fabricatedProperNouns(in: "You, Abraham Lincoln, spoke.", sourceText: clips)
        #expect(bad.contains("Abraham Lincoln"))
    }

    /// Pronouns/determiners the second-person voice uses ("You're", "The")
    /// are not names — never flagged even though they're absent from a
    /// first-person clip.
    @Test func pronounsAndStopwords_notFlagged() {
        let clips = "I'm out in the garden this morning before it got too hot."
        let summary = "You're out in the garden this morning, and the heat is coming."
        #expect(HonestLabelGate.fabricatedProperNouns(in: summary, sourceText: clips).isEmpty)
    }

    /// The extractive fallback is drawn from the clips, so it can never
    /// introduce a name the source lacks — and it itself passes the gate.
    @Test func extractiveFallback_cannotFabricate_andPassesGate() {
        let clips = "I am not bound to win, but I am bound to be true. I am not bound to succeed."
        let fallback = HonestLabelGate.extractiveSummary(fromClipText: clips)
        #expect(fallback == "I am not bound to win, but I am bound to be true")
        #expect(!HonestLabelGate.violates(summary: fallback, sourceText: clips))
    }

    @Test func extractiveFallback_emptyClips_returnsPlainDescriptor() {
        #expect(HonestLabelGate.extractiveSummary(fromClipText: "   ") == "A captured moment.")
    }
}
