import Foundation

/// **Code-side Honest-Label verification gate for the on-device organize
/// path (2026-07-23).**
///
/// Apple's on-device model quality is a moving target we don't control — it
/// regressed under iOS 27 and now fabricates proper names into summaries
/// (a Lincoln-only memory drafted "You, Ben, captured two clips…"; "Ben" is
/// in neither the clips nor the library). Prompt tuning against a
/// platform-controlled model is permanently unstable, so HiMem's
/// Honest-Label guarantee is enforced HERE, in deterministic code, not in
/// the prompt: a proper name / concrete entity in the model's summary that
/// is NOT present in the source clip text is a fabrication.
///
/// The gate is applied to the **on-device path only** — the frontier/Plus
/// (Anthropic) path is stable and honest and is not gated. On violation the
/// caller retries once, then falls back to `extractiveSummary` — a
/// constrained restatement of the clips that cannot introduce a name the
/// source doesn't contain ("say less before saying false").
///
/// This mirrors `MentionReconciler` (conservative, deterministic,
/// OS-independent) but operates on the summary/title **prose**, which the
/// reconciler never touches.
enum HonestLabelGate {

    /// Proper nouns / concrete entities in `text` (the model's summary or
    /// title) that do NOT appear in `sourceText` (the clips). Empty = clean.
    ///
    /// Deterministic heuristic: a **mid-sentence capitalized token** (or a
    /// contiguous run of them, "South Carolina") is a proper-noun candidate;
    /// sentence-initial words are skipped (they are capitalized by grammar).
    /// A candidate that is not found in the source (case-insensitive) and is
    /// not a common function/pronoun word is reported. Errs toward catching:
    /// a false positive downgrades to the honest extractive fallback, which
    /// is acceptable ("plainer" beats "false").
    static func fabricatedProperNouns(in text: String, sourceText: String) -> [String] {
        let source = sourceText.lowercased()
        var violations: [String] = []
        var seen = Set<String>()

        for sentence in splitSentences(text) {
            let words = tokenize(sentence)
            var i = 0
            while i < words.count {
                let word = words[i]
                // Sentence-initial (i == 0) words are capitalized by
                // grammar — never a candidate on their own.
                guard i > 0, isProperNounCandidate(word) else { i += 1; continue }

                // Gather a contiguous capitalized run ("South Carolina").
                var run = [word]
                var j = i + 1
                while j < words.count, isProperNounCandidate(words[j]) {
                    run.append(words[j]); j += 1
                }
                let phrase = run.joined(separator: " ")
                let phraseLower = phrase.lowercased()
                if !source.contains(phraseLower), !seen.contains(phraseLower) {
                    violations.append(phrase)
                    seen.insert(phraseLower)
                }
                i = j
            }
        }
        return violations
    }

    /// The gate trigger: true when the **summary** contains a fabricated
    /// proper noun. Scoped to the summary (not the title) on purpose — the
    /// model title-cases every word, so a capitalization signal there is
    /// noise ("A Reflection on Integrity"). The reported failures are all in
    /// the summary prose ("You, Ben, captured…"); on a violation the caller
    /// falls back BOTH summary and title to extractive, so a fabricated
    /// title can't survive either.
    static func violates(summary: String, sourceText: String) -> Bool {
        !fabricatedProperNouns(in: summary, sourceText: sourceText).isEmpty
    }

    /// A constrained, non-fabricating fallback summary: the source's lead
    /// sentence, verbatim (optionally quoted), trimmed to a word ceiling.
    /// Because it is drawn from the clips it cannot introduce a name the
    /// source doesn't contain. Empty source → a plain descriptor.
    static func extractiveSummary(fromClipText clipText: String, wordCeiling: Int = 40) -> String {
        let trimmed = clipText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "A captured moment." }
        let lead = splitSentences(trimmed).first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed
        let words = lead.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        if words.count <= wordCeiling {
            return lead
        }
        return words.prefix(wordCeiling).joined(separator: " ") + "…"
    }

    /// A safe title for the fallback path — the first few words of the
    /// extractive summary, so it too cannot fabricate.
    static func extractiveTitle(fromClipText clipText: String, wordCap: Int = 6) -> String {
        let lead = extractiveSummary(fromClipText: clipText, wordCeiling: wordCap)
        let words = lead.split(whereSeparator: { $0 == " " }).prefix(wordCap)
        let title = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: "“”\"…,.")).trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? "A captured moment" : title
    }

    /// A mention/entity value is "grounded" when it appears in the source
    /// clips (case-insensitive). The mention-field analog of the prose gate:
    /// a name the clips don't contain is a fabrication, one field over. Used
    /// to drop ungrounded mentions from the on-device result.
    static func isGrounded(_ value: String, in sourceText: String) -> Bool {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !v.isEmpty else { return false }
        return sourceText.lowercased().contains(v)
    }

    // MARK: - Internals

    private static func splitSentences(_ text: String) -> [Substring] {
        text.split(whereSeparator: { ".!?".contains($0) }).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Splits on whitespace and separating punctuation, then strips leading/
    /// trailing non-alphanumerics (quotes, commas) from each token.
    private static func tokenize(_ s: Substring) -> [String] {
        s.split(whereSeparator: { $0 == " " || $0 == "," || $0 == ";" || $0 == ":" || $0 == "\n" || $0 == "—" || $0 == "(" || $0 == ")" })
            .map { $0.trimmingCharacters(in: CharacterSet.alphanumerics.inverted) }
            .filter { !$0.isEmpty }
    }

    private static func isProperNounCandidate(_ word: String) -> Bool {
        guard word.count >= 2, let first = word.first, first.isUppercase else { return false }
        // Must be alphabetic (allow internal apostrophe/hyphen).
        guard word.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "-" }) else { return false }
        return !stopwords.contains(word.lowercased())
    }

    /// Common words that may appear capitalized mid-sentence (pronouns,
    /// determiners, connectors) or as capitalized dates — never flagged as
    /// fabricated names.
    private static let stopwords: Set<String> = [
        "i", "i'm", "i've", "i'll", "you", "you're", "you've", "you'll", "your", "yours",
        "we", "we're", "we've", "us", "our", "ours", "he", "he's", "she", "she's", "it",
        "it's", "they", "they're", "them", "their", "his", "her", "hers", "one", "the",
        "a", "an", "and", "but", "or", "so", "as", "if", "of", "to", "in", "on", "at",
        "this", "that", "these", "those", "there", "here", "then", "now", "while", "since",
        "when", "where", "after", "before", "also", "maybe", "not", "no", "yes", "out",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "may", "june", "july", "august",
        "september", "october", "november", "december", "today", "yesterday", "tomorrow",
    ]
}
