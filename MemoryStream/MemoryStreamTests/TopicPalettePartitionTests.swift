import Testing
import Foundation
@testable import HiMem

/// Money tests for `TopicPalette.partition(returned:existing:)` — the
/// pure-function side of the AI Organize spec §2c "NEW flag" rule.
///
/// The model returns a free-form `topics: [String]` array. Trusting it
/// to self-mark `isNew` is unreliable (models invent novelty and miss
/// matches), so we partition by **set-diff against the actual user
/// palette**. Returned topics that match an existing palette entry —
/// case-insensitively, whitespace-trimmed — get **canonicalized to the
/// palette's casing**, so the user sees their familiar form. Anything
/// not in the palette is flagged as NEW for the review sheet's
/// AI-blue dashed chip.
@Suite
struct TopicPalettePartitionTests {

    @Test func allReturnedMatchExisting_allCanonicalizedFromPalette() {
        let p = TopicPalette.partition(returned: ["garden", "WORK"], existing: ["Garden", "Work"])
        #expect(p.existing == ["Garden", "Work"])
        #expect(p.new == [])
    }

    @Test func emptyExisting_allReturnedAreNew() {
        let p = TopicPalette.partition(returned: ["Garden", "Work"], existing: [])
        #expect(p.existing == [])
        #expect(p.new == ["Garden", "Work"])
    }

    @Test func mixed_returnsBothLists() {
        let p = TopicPalette.partition(returned: ["Garden", "House Project"], existing: ["Garden", "Work"])
        #expect(p.existing == ["Garden"])
        #expect(p.new == ["House Project"])
    }

    @Test func whitespaceTrimming_matchesAcrossPadding() {
        let p = TopicPalette.partition(returned: ["  Garden  "], existing: ["Garden"])
        #expect(p.existing == ["Garden"])
        #expect(p.new == [])
    }

    @Test func returnedWhitespacePreservedOnNew() {
        // A trimmed-on-comparison NEW topic should still surface
        // trimmed in the new list — we don't want stray padding
        // landing as the persisted topic name.
        let p = TopicPalette.partition(returned: ["  Pottery  "], existing: ["Garden"])
        #expect(p.new == ["Pottery"])
    }

    @Test func emptyAndWhitespaceOnlyReturned_filtered() {
        let p = TopicPalette.partition(returned: ["", "  ", "Garden"], existing: ["Garden"])
        #expect(p.existing == ["Garden"])
        #expect(p.new == [])
    }

    @Test func emptyEverything_emptyPartition() {
        let p = TopicPalette.partition(returned: [], existing: [])
        #expect(p.existing == [])
        #expect(p.new == [])
    }

    /// Palette form wins for matches. If the user has "Garden" in
    /// their library and the model returns "garden" or "GARDEN",
    /// the user sees their familiar capitalization — we don't ship
    /// the model's casing through as a "different" topic.
    @Test func casePreservesPaletteForm() {
        let p = TopicPalette.partition(returned: ["garden", "GARDEN"], existing: ["Garden"])
        // Both lowercased-then-matched returned topics canonicalize
        // to the palette's "Garden". Duplicates aren't deduped here
        // — that's the review UI's concern.
        #expect(p.existing == ["Garden", "Garden"])
        #expect(p.new == [])
    }

    /// Palette ordering is preserved when the returned topics happen
    /// to be in the same order as the palette. The partition doesn't
    /// reorder — `returned` order is the user-meaningful order
    /// (model's ranking).
    @Test func orderPreservedFromReturned_notFromPalette() {
        let p = TopicPalette.partition(returned: ["Work", "Garden"], existing: ["Garden", "Work"])
        #expect(p.existing == ["Work", "Garden"])
    }

    /// Spec §2c calls out the regression case explicitly: the
    /// on-device path coins "Gardening" while the palette has
    /// "Garden". With strict equality (this phase), these are
    /// distinct — "Gardening" flagged NEW. The fuzzy-match step is
    /// a separate post-launch improvement; we hold the line here so
    /// the test failure shape is honest.
    @Test func similarButNotIdentical_flaggedAsNew_perStrictMatchScope() {
        let p = TopicPalette.partition(returned: ["Gardening"], existing: ["Garden"])
        #expect(p.existing == [])
        #expect(p.new == ["Gardening"])
    }
}
