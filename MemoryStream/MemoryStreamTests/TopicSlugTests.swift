import Testing
@testable import HiMem

/// Spec-locked: `docs/design/Crucible · topic palette spec.md`.
///
/// `Crucible.Color.topicSlug(for:)` is the **cross-platform
/// contract** between the iOS app, the JS reference implementation
/// in the design canvas, and any future surface that needs to
/// auto-pick a topic color from a name. The values below come from
/// the spec's "golden vectors" table — every implementation must
/// produce byte-identical output for these inputs.
///
/// If the palette order, the hash algorithm, or the string
/// normalization ever changes, every implementation breaks together
/// and every user's existing topic colors shuffle. Don't change
/// any of that casually; this suite is the regression guard.
@Suite struct TopicSlugTests {

    // MARK: - Golden vectors from the spec

    @Test func goldenVector_garden_lowercase() {
        #expect(Crucible.Color.topicSlug(for: "garden") == "moss")
    }

    @Test func goldenVector_garden_titleCase() {
        #expect(Crucible.Color.topicSlug(for: "Garden") == "moss")
    }

    @Test func goldenVector_garden_withWhitespace() {
        #expect(Crucible.Color.topicSlug(for: "  Garden  ") == "moss")
    }

    @Test func goldenVector_howWeWork() {
        #expect(Crucible.Color.topicSlug(for: "How We Work") == "clay")
    }

    @Test func goldenVector_tomatoes() {
        #expect(Crucible.Color.topicSlug(for: "Tomatoes") == "terracotta")
    }

    @Test func goldenVector_ideas() {
        #expect(Crucible.Color.topicSlug(for: "Ideas") == "violet")
    }

    @Test func goldenVector_travel() {
        #expect(Crucible.Color.topicSlug(for: "Travel") == "amber")
    }

    @Test func goldenVector_emptyString() {
        #expect(Crucible.Color.topicSlug(for: "") == "sage")
    }

    // MARK: - Determinism + normalization properties

    /// The same input must always produce the same output. Critical:
    /// `Swift.hashValue` (which we used to use) randomizes per app
    /// launch, breaking CloudKit-sync stability. djb2 doesn't.
    @Test func sameInput_alwaysSameOutput() {
        let name = "Cooking"
        let first = Crucible.Color.topicSlug(for: name)
        let second = Crucible.Color.topicSlug(for: name)
        let third = Crucible.Color.topicSlug(for: name)
        #expect(first == second)
        #expect(second == third)
    }

    /// Case-folding happens before hashing, so capitalization
    /// variants collapse to the same slug. Prevents "garden" and
    /// "Garden" rendering as different colors.
    @Test func caseFolding_collapsesCapitalizationVariants() {
        let lower = Crucible.Color.topicSlug(for: "tomatoes")
        let title = Crucible.Color.topicSlug(for: "Tomatoes")
        let upper = Crucible.Color.topicSlug(for: "TOMATOES")
        let mixed = Crucible.Color.topicSlug(for: "ToMaToEs")
        #expect(lower == title)
        #expect(title == upper)
        #expect(upper == mixed)
    }

    /// Leading/trailing whitespace is stripped before hashing, so
    /// `"Garden"` and `"Garden "` and `"  Garden"` are the same
    /// topic for color purposes.
    @Test func whitespaceTrim_collapsesPaddingVariants() {
        let clean = Crucible.Color.topicSlug(for: "Garden")
        #expect(Crucible.Color.topicSlug(for: " Garden")  == clean)
        #expect(Crucible.Color.topicSlug(for: "Garden ")  == clean)
        #expect(Crucible.Color.topicSlug(for: "\tGarden\n") == clean)
    }

    // MARK: - Output is always in the palette

    /// Whatever input we throw at it, the result must be a valid
    /// palette key — never a typo or out-of-bounds string.
    @Test func output_isAlwaysAPaletteKey() {
        let validKeys = Set(Crucible.Color.topicPalette.map(\.key))
        let testInputs = [
            "Garden", "Cooking", "Travel", "Health", "Family",
            "Books", "Music", "Photography", "Side projects",
            "", " ", "🌱", "very-long-topic-name-with-special-chars-!@#$",
        ]
        for input in testInputs {
            let slug = Crucible.Color.topicSlug(for: input)
            #expect(validKeys.contains(slug),
                    "slug \(slug) for input '\(input)' not in palette")
        }
    }
}
