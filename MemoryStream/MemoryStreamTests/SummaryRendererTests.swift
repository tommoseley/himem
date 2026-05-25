import Testing
import Foundation
@testable import HiMem

/// Money tests for the `<user>` token substitution layer specified
/// in `docs/design/ai-organize-spec.md` §3. Two render paths to cover:
///
///   • **Owner view** — 12 substitutions (6 forms × 2 capitalizations).
///     No contractions: *you are* / *you have* / *you do*.
///   • **External view** — 2 substitutions (both capitalizations →
///     the user's first name). Possessive `'s` stays attached
///     because the regex matches only the token.
///
/// Plus the invariants:
///   • Hand-edited summaries (no token) pass through unchanged from
///     either renderer.
///   • Order matters in owner-render: verb-bearing substitutions
///     must precede the bare token, otherwise *<User> is* collapses
///     to *You is* (broken).
///   • External-render with empty name returns input unchanged
///     rather than producing broken substitution (the share entry
///     point is supposed to prompt for a name first).
struct SummaryRendererTests {

    // MARK: - Owner view, per-form substitutions

    @Test func owner_possessive_capital() {
        let stored = "<User>'s favorite recipe."
        #expect(SummaryRenderer.renderForOwner(stored) == "Your favorite recipe.")
    }

    @Test func owner_possessive_lowercase() {
        let stored = "Then <user>'s recipe was older than the kitchen."
        #expect(SummaryRenderer.renderForOwner(stored) == "Then your recipe was older than the kitchen.")
    }

    @Test func owner_isVerb_capital_becomesYouAre_noContraction() {
        let stored = "<User> is exploring HiMem."
        #expect(SummaryRenderer.renderForOwner(stored) == "You are exploring HiMem.")
    }

    @Test func owner_isVerb_lowercase_becomesYouAre() {
        let stored = "When <user> is exploring, ideas surface."
        #expect(SummaryRenderer.renderForOwner(stored) == "When you are exploring, ideas surface.")
    }

    @Test func owner_wasVerb_capital_becomesYouWere() {
        let stored = "<User> was tired."
        #expect(SummaryRenderer.renderForOwner(stored) == "You were tired.")
    }

    @Test func owner_wasVerb_lowercase_becomesYouWere() {
        let stored = "Yesterday <user> was at home."
        #expect(SummaryRenderer.renderForOwner(stored) == "Yesterday you were at home.")
    }

    @Test func owner_hasVerb_capital_becomesYouHave_noContraction() {
        let stored = "<User> has captured three audio clips."
        #expect(SummaryRenderer.renderForOwner(stored) == "You have captured three audio clips.")
    }

    @Test func owner_hasVerb_lowercase_becomesYouHave() {
        let stored = "Today <user> has explored two new ideas."
        #expect(SummaryRenderer.renderForOwner(stored) == "Today you have explored two new ideas.")
    }

    @Test func owner_doesVerb_capital_becomesYouDo() {
        let stored = "<User> does prefer the morning ones."
        #expect(SummaryRenderer.renderForOwner(stored) == "You do prefer the morning ones.")
    }

    @Test func owner_doesVerb_lowercase_becomesYouDo() {
        let stored = "Often <user> does the watering at dusk."
        #expect(SummaryRenderer.renderForOwner(stored) == "Often you do the watering at dusk.")
    }

    @Test func owner_bareToken_capital_becomesYou() {
        let stored = "<User> appreciated pears."
        #expect(SummaryRenderer.renderForOwner(stored) == "You appreciated pears.")
    }

    @Test func owner_bareToken_lowercase_becomesYou() {
        let stored = "Sarah and <user> talked about pears."
        #expect(SummaryRenderer.renderForOwner(stored) == "Sarah and you talked about pears.")
    }

    // MARK: - Owner view, multi-token sentences

    @Test func owner_multipleTokens_inSingleSentence() {
        let stored = "<User>'s recipe involves pears, and <user> noted that the harvest was good."
        let expected = "Your recipe involves pears, and you noted that the harvest was good."
        #expect(SummaryRenderer.renderForOwner(stored) == expected)
    }

    @Test func owner_multipleSentences_capitalAndLowercase() {
        let stored = "<User> is exploring HiMem. <User>'s favorite recipe involves pears, and <user> appreciated the second pear."
        let expected = "You are exploring HiMem. Your favorite recipe involves pears, and you appreciated the second pear."
        #expect(SummaryRenderer.renderForOwner(stored) == expected)
    }

    @Test func owner_threeVerbForms_oneSentence() {
        let stored = "<User> is at the garden. <User> has watered. <User> was happy."
        let expected = "You are at the garden. You have watered. You were happy."
        #expect(SummaryRenderer.renderForOwner(stored) == expected)
    }

    // MARK: - Owner view, hand-edit pass-through

    @Test func owner_handEditedSummary_passesThrough_unchanged() {
        let edited = "I went to the garden today and it was beautiful."
        #expect(SummaryRenderer.renderForOwner(edited) == edited)
    }

    @Test func owner_emptyString_returnsEmpty() {
        #expect(SummaryRenderer.renderForOwner("") == "")
    }

    @Test func owner_textWithNoToken_doesNotChange() {
        let stored = "A sunset over the ridge."
        #expect(SummaryRenderer.renderForOwner(stored) == "A sunset over the ridge.")
    }

    // MARK: - Owner view, regression — order-sensitive substitution

    /// Regression: if bare-token substitution ran before verb-bearing
    /// substitution, *<User> is* would become *You is* — broken
    /// second-person agreement. This test would fail in that ordering.
    @Test func owner_verbBearingSubstitutions_runBeforeBare() {
        let stored = "<User> is well. <User> has time."
        let expected = "You are well. You have time."
        #expect(SummaryRenderer.renderForOwner(stored) == expected)
    }

    // MARK: - External view

    @Test func external_bareToken_capital_becomesName() {
        let stored = "<User> appreciated pears."
        #expect(SummaryRenderer.renderForExternal(stored, name: "Tom") == "Tom appreciated pears.")
    }

    @Test func external_bareToken_lowercase_becomesName() {
        let stored = "Sarah and <user> talked about pears."
        #expect(SummaryRenderer.renderForExternal(stored, name: "Tom") == "Sarah and Tom talked about pears.")
    }

    /// Verbs stay third-person — storage already in third-person
    /// singular matches the external read.
    @Test func external_verbBearingStorage_renderedThirdPerson() {
        let stored = "<User> is exploring HiMem. <User> has captured three audio clips."
        let expected = "Tom is exploring HiMem. Tom has captured three audio clips."
        #expect(SummaryRenderer.renderForExternal(stored, name: "Tom") == expected)
    }

    /// Possessive 's stays attached — regex only matches the token.
    @Test func external_possessive_preservesApostropheS() {
        let stored = "<User>'s recipe was older than the kitchen."
        #expect(SummaryRenderer.renderForExternal(stored, name: "Tom") == "Tom's recipe was older than the kitchen.")
    }

    @Test func external_emptyName_returnsInputUnchanged() {
        // Share entry point is responsible for prompting for a name
        // first; if it bypasses that, the renderer returns the input
        // unchanged rather than producing broken substitution.
        let stored = "<User> is exploring HiMem."
        #expect(SummaryRenderer.renderForExternal(stored, name: "") == stored)
    }

    @Test func external_whitespaceOnlyName_treatedAsEmpty() {
        let stored = "<User> is exploring HiMem."
        #expect(SummaryRenderer.renderForExternal(stored, name: "   ") == stored)
    }

    @Test func external_handEditedSummary_passesThrough_unchanged() {
        let edited = "I went to the garden today."
        #expect(SummaryRenderer.renderForExternal(edited, name: "Tom") == edited)
    }

    @Test func external_nameWithLeadingTrailingWhitespace_isTrimmed() {
        let stored = "<User> appreciated pears."
        #expect(SummaryRenderer.renderForExternal(stored, name: "  Tom  ") == "Tom appreciated pears.")
    }

    // MARK: - Edge cases that should NOT be touched

    @Test func owner_userAsSubstring_notMatched() {
        // The token regex must match literal `<user>` only — strings
        // like "username" or "useragent" must pass through. Token
        // delimiters `<` and `>` are not word characters; literal
        // text without the delimiters won't match.
        let stored = "The username field requires entry."
        #expect(SummaryRenderer.renderForOwner(stored) == "The username field requires entry.")
    }

    @Test func external_userAsSubstring_notMatched() {
        let stored = "The user-agent string is useful."
        #expect(SummaryRenderer.renderForExternal(stored, name: "Tom") == "The user-agent string is useful.")
    }

    @Test func owner_uppercaseUSER_notMatched() {
        // Only `<User>` and `<user>` are tokens. `<USER>` is not a
        // token and should pass through unchanged.
        let stored = "<USER> is shouting."
        #expect(SummaryRenderer.renderForOwner(stored) == "<USER> is shouting.")
    }

    // MARK: - Server-non-compliance fallback (the literal "The user")
    //
    // 2026-05-18: server occasionally emits literal English "The user"
    // / "the user" instead of the `<User>` token. Until the prompt
    // gets the model fully compliant, the client substitutes the
    // literal forms the same way it would the token — owner sees
    // correct second-person English, external sees correct
    // third-person English.

    @Test func owner_literalTheUser_capital_becomesYou() {
        let stored = "The user identified an action to source lemon trees."
        #expect(SummaryRenderer.renderForOwner(stored) == "You identified an action to source lemon trees.")
    }

    @Test func owner_literalTheUser_lowercase_becomesYou() {
        let stored = "After the harvest the user noted good results."
        #expect(SummaryRenderer.renderForOwner(stored) == "After the harvest you noted good results.")
    }

    @Test func owner_literalTheUsersPossessive_capital_becomesYour() {
        let stored = "The user's favorite recipe involves pears."
        #expect(SummaryRenderer.renderForOwner(stored) == "Your favorite recipe involves pears.")
    }

    @Test func owner_literalTheUsersPossessive_lowercase_becomesYour() {
        let stored = "Sarah used the user's tools."
        #expect(SummaryRenderer.renderForOwner(stored) == "Sarah used your tools.")
    }

    /// "The entry" is NOT a user reference and must pass through —
    /// only "The user" / "the user" gets substituted. Guards against
    /// the substitution drifting to match too aggressively.
    @Test func owner_literalTheEntry_doesNotMatch() {
        let stored = "The entry flags difficulty in finding suitable trees."
        #expect(SummaryRenderer.renderForOwner(stored) == "The entry flags difficulty in finding suitable trees.")
    }

    @Test func owner_literalTheUser_andToken_mixedSentence() {
        // The model sometimes mixes both forms in the same response.
        // Both paths land at the same rendered result.
        let stored = "The user is exploring; <user> also noted the season."
        let expected = "You are exploring; you also noted the season."
        #expect(SummaryRenderer.renderForOwner(stored) == expected)
    }

    @Test func external_literalTheUser_capital_becomesName() {
        let stored = "The user identified an action to source lemon trees."
        #expect(SummaryRenderer.renderForExternal(stored, name: "Tom") == "Tom identified an action to source lemon trees.")
    }

    @Test func external_literalTheUser_lowercase_becomesName() {
        let stored = "After the harvest the user noted good results."
        #expect(SummaryRenderer.renderForExternal(stored, name: "Tom") == "After the harvest Tom noted good results.")
    }

    @Test func external_literalTheUsersPossessive_capital_keepsApostropheS() {
        // External substitution maps "The user's" → "Tom's", same
        // possessive shape as the `<User>'s` → `Tom's` case.
        let stored = "The user's favorite recipe."
        #expect(SummaryRenderer.renderForExternal(stored, name: "Tom") == "Tom's favorite recipe.")
    }
}
