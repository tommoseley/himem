import Foundation

/// Pure-function renderer for AI summary text. Substitutes the
/// `<User>` / `<user>` token (per `docs/design/ai-organize-spec.md`
/// §3) into either:
///
///   • **Owner-view text** — token becomes "You" / "you" with verb
///     agreement (no contractions: *you are*, *you have*, *you do*).
///   • **External-view text** — token becomes the owner's first name.
///     Storage's third-person singular verbs already match a third-
///     person external read, so no verb transformation is needed.
///
/// Hand-edited summaries (which contain no token) pass through
/// unchanged from either renderer — the user's literal text ships as
/// their voice on share too.
///
/// All substitutions are pure regex. No NLP, no parsing, no
/// sentence-boundary detection. Capitalization is handled by the AI
/// emitting `<User>` at sentence starts and `<user>` mid-sentence,
/// which the substitution table preserves on the rendered "You" /
/// "you" sides.
enum SummaryRenderer {

    /// Renders a stored summary for the owner's UI.
    ///
    /// Ordered substitution table (most-specific first):
    ///   1. `<User>'s` / `<user>'s`  → *Your* / *your*  (possessive)
    ///   2. `<User> is`  / `<user> is`   → *You are*  / *you are*
    ///   3. `<User> was` / `<user> was`  → *You were* / *you were*
    ///   4. `<User> has` / `<user> has`  → *You have* / *you have*
    ///   5. `<User> does`/ `<user> does` → *You do*   / *you do*
    ///   6. Bare `<User>` / `<user>`     → *You*      / *you*
    ///
    /// Order matters: the verb-bearing variants must replace before
    /// the bare token, otherwise *<User> is* would become *You is*
    /// (broken second-person verb agreement).
    static func renderForOwner(_ text: String) -> String {
        var result = text

        // 1. Possessive — capital first
        result = replace(result, pattern: #"<User>'s"#,  with: "Your")
        result = replace(result, pattern: #"<user>'s"#,  with: "your")

        // 2. <user> is → you are
        result = replace(result, pattern: #"<User> is\b"#, with: "You are")
        result = replace(result, pattern: #"<user> is\b"#, with: "you are")

        // 3. <user> was → you were
        result = replace(result, pattern: #"<User> was\b"#, with: "You were")
        result = replace(result, pattern: #"<user> was\b"#, with: "you were")

        // 4. <user> has → you have
        result = replace(result, pattern: #"<User> has\b"#, with: "You have")
        result = replace(result, pattern: #"<user> has\b"#, with: "you have")

        // 5. <user> does → you do
        result = replace(result, pattern: #"<User> does\b"#, with: "You do")
        result = replace(result, pattern: #"<user> does\b"#, with: "you do")

        // 6. Bare token (must run last; matches whatever's left)
        result = replace(result, pattern: #"<User>"#, with: "You")
        result = replace(result, pattern: #"<user>"#, with: "you")

        // 7. Server-non-compliance fallback — the model sometimes
        // emits the literal English "The user" / "the user" instead
        // of the `<User>` token (observed 2026-05-18). Substitute the
        // literal forms the same way the token would have rendered.
        // Mirrors the token table: possessive and verb-bearing forms
        // run before the bare form so verb agreement holds — without
        // this, "The user is" → "You is". The `(?!-)` lookahead
        // protects hyphenated compounds ("user-agent", "user-id")
        // from matching — those are not journal-owner references.
        result = replace(result, pattern: #"\bThe user's\b"#,    with: "Your")
        result = replace(result, pattern: #"\bthe user's\b"#,    with: "your")
        result = replace(result, pattern: #"\bThe user is\b"#,   with: "You are")
        result = replace(result, pattern: #"\bthe user is\b"#,   with: "you are")
        result = replace(result, pattern: #"\bThe user was\b"#,  with: "You were")
        result = replace(result, pattern: #"\bthe user was\b"#,  with: "you were")
        result = replace(result, pattern: #"\bThe user has\b"#,  with: "You have")
        result = replace(result, pattern: #"\bthe user has\b"#,  with: "you have")
        result = replace(result, pattern: #"\bThe user does\b"#, with: "You do")
        result = replace(result, pattern: #"\bthe user does\b"#, with: "you do")
        result = replace(result, pattern: #"\bThe user\b(?!-)"#, with: "You")
        result = replace(result, pattern: #"\bthe user\b(?!-)"#, with: "you")

        return result
    }

    /// Renders a stored summary for an external audience (share,
    /// export, family view). Substitutes the token with the owner's
    /// first name. Storage's third-person verbs match the third-
    /// person external read without any verb transformation —
    /// possessive `<user>'s` becomes `Tom's` because the regex
    /// only matches `<user>`, leaving `'s` intact.
    ///
    /// Returns the original text unchanged when `name` is empty —
    /// the share/export entry point is responsible for prompting
    /// the user for their name before invoking this; if it somehow
    /// reaches here without a name, returning untouched text is
    /// safer than producing broken substitution.
    static func renderForExternal(_ text: String, name: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return text }
        var result = text
        result = replace(result, pattern: #"<User>"#, with: trimmedName)
        result = replace(result, pattern: #"<user>"#, with: trimmedName)
        // Server-non-compliance fallback — same intent as the owner
        // renderer's literal-form substitution. "The user's" stays
        // possessive in English when we leave `'s` attached, matching
        // how the token's possessive form behaves. `(?!-)` lookahead
        // protects hyphenated compounds ("user-agent", "user-id")
        // from matching.
        result = replace(result, pattern: #"\bThe user\b(?!-)"#, with: trimmedName)
        result = replace(result, pattern: #"\bthe user\b(?!-)"#, with: trimmedName)
        return result
    }

    // MARK: - Internals

    private static func replace(_ source: String, pattern: String, with replacement: String) -> String {
        source.replacingOccurrences(
            of: pattern,
            with: replacement,
            options: .regularExpression
        )
    }
}
