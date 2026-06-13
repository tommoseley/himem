import Testing
import Foundation
@testable import HiMem

/// Money tests for `DraftReviewSheet.captionText(existing:kept:)` and
/// `humanList(_:)` — the Topics-row explainer copy from
/// `screens-topics.jsx`'s `ScrOrganizeReviewTopics` mockup. Pinning
/// the copy down: a typo or grammar regression in the spec's voice
/// is the kind of bug that survives most lint passes, slips through
/// reviewers, and surfaces in the App Store reviews.
@Suite
struct DraftReviewSheetCaptionTests {

    // MARK: - humanList

    @Test func humanList_empty_returnsEmpty() {
        #expect(DraftReviewSheet.humanList([]) == "")
    }

    @Test func humanList_singleItem_returnsItem() {
        #expect(DraftReviewSheet.humanList(["Garden"]) == "Garden")
    }

    @Test func humanList_two_joinsWithAnd() {
        #expect(DraftReviewSheet.humanList(["Garden", "Travel"]) == "Garden and Travel")
    }

    /// Oxford comma — matches the spec mockup's *"Travel, Family,
    /// and New England"* construction. Three+ items get serial-
    /// comma joining.
    @Test func humanList_three_oxfordComma() {
        #expect(DraftReviewSheet.humanList(["Travel", "Family", "New England"]) == "Travel, Family, and New England")
    }

    @Test func humanList_four_oxfordComma() {
        #expect(DraftReviewSheet.humanList(["A", "B", "C", "D"]) == "A, B, C, and D")
    }

    // MARK: - captionText variants

    /// Mixed — some existing, some kept-new. Mirrors the spec
    /// mockup exactly:
    /// > *"Travel and Family are from your library. New England is
    /// > new — tap to drop it if you'd rather not start a topic."*
    /// (Wording reads "New England new" rather than "is new" so the
    /// flow matches when N kept-new exceeds one.)
    @Test func mixed_namesBothLists_includesBothPhrases() {
        let caption = DraftReviewSheet.captionText(
            existing: ["Travel", "Family"],
            kept: ["New England"]
        )
        #expect(caption.contains("Travel and Family"))
        #expect(caption.contains("from your library"))
        #expect(caption.contains("New England"))
        #expect(caption.contains("tap to drop"))
    }

    @Test func existingOnly_noNewPhrase() {
        let caption = DraftReviewSheet.captionText(
            existing: ["Travel", "Family"],
            kept: []
        )
        #expect(caption == "Travel and Family from your library.")
        #expect(!caption.contains("new"))
    }

    @Test func newOnly_noLibraryPhrase() {
        let caption = DraftReviewSheet.captionText(
            existing: [],
            kept: ["New England"]
        )
        #expect(caption.contains("New England"))
        #expect(caption.contains("tap to drop"))
        #expect(!caption.contains("from your library"))
    }

    @Test func bothEmpty_returnsEmpty() {
        let caption = DraftReviewSheet.captionText(existing: [], kept: [])
        #expect(caption.isEmpty)
    }

    @Test func singleExistingChip_singularGrammarLandsCleanly() {
        let caption = DraftReviewSheet.captionText(
            existing: ["Travel"],
            kept: []
        )
        // "Travel from your library." reads acceptably even though
        // strictly the "Family and Travel from your library" form
        // is plural — we don't conjugate the verb because there
        // isn't one in this phrasing. The empty-string-on-both-sides
        // case is the only one we suppress.
        #expect(caption == "Travel from your library.")
    }

    @Test func singleKeptNew_singularGrammarLandsCleanly() {
        let caption = DraftReviewSheet.captionText(
            existing: [],
            kept: ["Pottery"]
        )
        #expect(caption.contains("Pottery"))
        #expect(caption.contains("tap to drop"))
    }
}
