import Foundation

/// **TruthReconciler — one Honest-Label gate for all AI organize output,
/// tier-independent (supersedes the on-device-only `HonestLabelGate`,
/// 2026-07-23).**
///
/// **Principle: models are advisory; code is authoritative.** The organize
/// summary/title/mentions/topics a model returns are a *proposal*. What HiMem
/// commits is what this reconciler has verified against the source clips. The
/// guarantee is HiMem's, not any vendor's — so it runs on BOTH tiers (Apple
/// on-device and Anthropic frontier), not just the one that happened to
/// regress.
///
/// **Invariant (the honesty contract).** An AI summary/title may compress,
/// rephrase, reorder, generalize, and carry tone — it may **not introduce
/// people, places, orgs, dates, events, actions, or relationships absent from
/// the source clips, nor narrate the memory's storage structure** (clip
/// counts, media types, "clip N"). A proper name / concrete entity in the
/// model's output that is not present in the clips is a fabrication; so is a
/// container/media word (`fabricatedStructuralClaims`) the clips never used.
///
/// **Enforcement (deterministic).** Verify entities (proper names, places,
/// orgs, dates) in the summary/title against the clip text → retry the pass
/// once, then fall back to a constrained extractive/template summary that
/// cannot introduce a name the source lacks ("say less before saying false").
/// This summary/title gate runs on BOTH tiers. The ungrounded-mention *drop*
/// (a fabricated name in the mentions field) is the `.strict`/on-device
/// palette-bleed guard only — on the frontier tier mentions are extracted from
/// the clips and pass through reconciliation, not dropped. The orchestration
/// (retry, fallback) lives in `ProcessingEngine.reconcileResult`; this type is
/// the deterministic library it calls.
///
/// **Strictness is the only per-tier difference.**
/// - `.strict` (Apple on-device) — exact substring grounding. The 3B model is
///   a platform-controlled moving target (regressed under iOS 27, fabricates
///   proper names) so it gets the tightest check.
/// - `.relaxed` (Anthropic frontier) — grounding also passes when the entity
///   shares a distinctive token with the clips (a variant/paraphrase: the
///   model expanding "Lincoln" the clips contain to "Abraham Lincoln", or the
///   reverse). A true fabrication — no token in common with the source —
///   still fails and falls back. This keeps Plus's beautiful paraphrase from
///   being needlessly downgraded while holding the same guarantee.
///
/// **Modules.** `MentionReconciler` is TruthReconciler's first module
/// (mentions dedup/variant-collapse); `reconcileMentions` and `reconcileTopics`
/// route those field-types through here so summary/title/mentions/topics share
/// one seam. A further seam is reserved for future AI output — Memory **cover**
/// selection and **project** suggestions — which must pass through the same
/// authority before they are surfaced.
///
/// **Known gap (logged, not hidden).** The entity check is deterministic over
/// *named* things. It does NOT catch **semantic-claim entailment** — an
/// unsupported claim built only from common words ("celebrated our
/// anniversary" when no clip says so) names no entity and passes. That is a
/// tracked follow-up (`docs/architecture/2026-07-23-truthreconciler.md`
/// §Known gaps). Consequence for copy: no user-facing "checked against your
/// recordings" claim may exceed what this gate actually verifies — it verifies
/// *entities*, not *claims*.
enum TruthReconciler {

    /// Per-tier grounding tolerance. The guarantee is identical on both — only
    /// the false-positive tolerance differs (see type doc).
    enum Strictness { case strict, relaxed }

    // MARK: - Prose grounding (summary / title)

    /// Proper nouns / concrete entities in `text` (the model's summary or
    /// title) that are NOT grounded in `sourceText` (the clips). Empty = clean.
    ///
    /// Deterministic heuristic: a **mid-sentence capitalized token** (or a
    /// contiguous run of them, "South Carolina") is a proper-noun candidate;
    /// sentence-initial words are skipped (they are capitalized by grammar).
    /// A candidate that is not grounded (per `strictness`) and is not a common
    /// function/pronoun word is reported. Errs toward catching: a false
    /// positive downgrades to the honest extractive fallback, which is
    /// acceptable ("plainer" beats "false").
    static func fabricatedEntities(in text: String, sourceText: String, strictness: Strictness) -> [String] {
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
                if !isGrounded(phrase, in: sourceText, strictness: strictness), !seen.contains(phraseLower) {
                    violations.append(phrase)
                    seen.insert(phraseLower)
                }
                i = j
            }
        }
        return violations
    }

    /// The gate trigger: true when the **summary** contains a fabricated
    /// entity OR a fabricated structural claim. Scoped to the summary (not the
    /// title) on purpose — the model title-cases every word, so a
    /// capitalization signal there is noise ("A Reflection on Integrity"). On a
    /// violation the caller falls back BOTH summary and title to extractive, so
    /// a fabricated title can't survive either.
    static func violates(summary: String, sourceText: String, strictness: Strictness) -> Bool {
        !fabricatedEntities(in: summary, sourceText: sourceText, strictness: strictness).isEmpty
            || !fabricatedStructuralClaims(in: summary, sourceText: sourceText).isEmpty
    }

    // MARK: - Title grounding (P1-2, 2026-07-25)

    /// The gate trigger for a TITLE, checked on its own. `violates(summary:)`
    /// can't see a fabricated title: the model title-cases every word, so the
    /// mid-sentence-capitalization heuristic is noise there — which let a title
    /// smuggle an invented author ("Ralph Waldo Emerson's Reflection" on an
    /// unattributed quote) or a raw verbatim clip quote ("I am not bound to
    /// win", reading as the user's own words) straight past the summary gate.
    /// Two case-normalized checks:
    ///  1. an ungrounded MULTI-WORD proper-noun run (an invented name), and
    ///  2. the title being a long verbatim run of the source (a copied quote).
    static func titleViolates(title: String, sourceText: String, strictness: Strictness) -> Bool {
        !fabricatedTitleNames(in: title, sourceText: sourceText, strictness: strictness).isEmpty
            || isVerbatimQuoteFragment(title: title, sourceText: sourceText)
    }

    /// Multi-word proper-noun runs in a TITLE that aren't grounded in the
    /// source. Unlike `fabricatedEntities`, it does NOT skip the first token (a
    /// title has no grammar-initial word to excuse — "Emerson's Reflection"
    /// leads with the name) and requires a run of **≥2** capitalized tokens: a
    /// single title-cased word is editorial framing ("Reflection"), not a
    /// claimed name, so requiring a run keeps false positives off ordinary
    /// titles. Grounding is case-insensitive (`isGrounded` lowercases both
    /// sides) — the "case-normalize before matching" fix, so title-casing can't
    /// hide an ungrounded name.
    static func fabricatedTitleNames(in title: String, sourceText: String, strictness: Strictness) -> [String] {
        let words = tokenize(Substring(title))
        var violations: [String] = []
        var i = 0
        while i < words.count {
            guard isProperNounCandidate(words[i]) else { i += 1; continue }
            var run = [words[i]]
            var j = i + 1
            while j < words.count, isProperNounCandidate(words[j]) { run.append(words[j]); j += 1 }
            if run.count >= 2 {
                let phrase = run.joined(separator: " ")
                if !isGrounded(phrase, in: sourceText, strictness: strictness) { violations.append(phrase) }
            }
            i = j
        }
        return violations
    }

    /// True when the title is a long (≥5-word) verbatim run of the source — a
    /// raw quote fragment presented as a title reads as the user's own words.
    /// The word floor keeps short descriptive titles (legitimately drawn from
    /// the content) safe.
    static func isVerbatimQuoteFragment(title: String, sourceText: String) -> Bool {
        let t = title.trimmingCharacters(in: CharacterSet(charactersIn: "“”\"…,. ")).lowercased()
        guard t.split(whereSeparator: { $0 == " " }).count >= 5 else { return false }
        return sourceText.lowercased().contains(t)
    }

    /// A structural fallback title that can neither fabricate a name nor copy a
    /// quote: built from the (already-reconciled, grounded) topic, else a plain
    /// descriptor. Deliberately NOT `extractiveTitle` — that draws the clip
    /// lead, which for a quote memory reproduces the very fragment we're
    /// avoiding.
    /// NOTE (copy is a *what*, flagged for Tom): the punch-list example was
    /// "A reflection on integrity"; that assumes a *reflective* memory, so this
    /// uses the neutral topic label. Adjust to a ruled copy form if desired.
    static func structuralTitle(topics: [String]) -> String {
        if let topic = topics.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            let t = topic.trimmingCharacters(in: .whitespaces)
            return t.prefix(1).uppercased() + t.dropFirst()
        }
        return "A captured moment"
    }

    // MARK: - Structural-claim leakage (clip scaffolding narrated as content)

    /// The container's own vocabulary — words HiMem uses to talk about how a
    /// memory is stored, never words about what it's *about*. A summary that
    /// says "text clip 1" / "two video clips" is narrating structure the model
    /// was handed as scaffolding, not content (the 2026-07-24 leak). These are
    /// the app-internal container words; deliberately excludes ambiguous
    /// content words ("note", "text", "memory") to keep false-positives near
    /// zero.
    private static let structuralTokens: Set<String> = [
        "clip", "clips", "photo", "photos", "video", "videos",
        "voice", "audio", "recording", "recordings",
    ]

    /// Structural/media words in `text` (the summary) that are NOT present in
    /// `sourceText` (the clips). Empty = clean. Grounding is exact-word: if the
    /// clips genuinely say "video" or "photo", the summary may too — the leak
    /// is only when the model invents container/media language the content
    /// never used. Deterministic and tier-independent (the same wherever the
    /// summary came from). Catches what the proper-noun check can't: these are
    /// lowercase common words, not proper nouns.
    static func fabricatedStructuralClaims(in text: String, sourceText: String) -> [String] {
        let sourceWords = Set(lowercasedWords(in: sourceText))
        var hits: [String] = []
        var seen = Set<String>()
        for word in lowercasedWords(in: text) {
            guard structuralTokens.contains(word), !sourceWords.contains(word), !seen.contains(word) else { continue }
            hits.append(word)
            seen.insert(word)
        }
        return hits
    }

    /// Whole words (letters only), lowercased — used for exact-word grounding.
    private static func lowercasedWords(in s: String) -> [String] {
        s.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
    }

    // MARK: - Extractive fallback (cannot fabricate)

    /// A constrained, non-fabricating fallback summary: the source's lead
    /// sentence, verbatim, trimmed to a word ceiling. Because it is drawn from
    /// the clips it cannot introduce a name the source doesn't contain. Empty
    /// source → a plain descriptor.
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

    // MARK: - Entity / mention grounding

    /// A value (mention, entity, or prose phrase) is "grounded" when it is
    /// supported by the source clips.
    /// - `.strict`: the value appears verbatim (case-insensitive substring).
    /// - `.relaxed`: strict, OR the value shares a **distinctive token** with
    ///   the clips — the legitimate variant/paraphrase case (the frontier model
    ///   expanding "Lincoln" → "Abraham Lincoln", or dropping to a last name).
    ///   A fabrication with no token in common with the source still fails.
    static func isGrounded(_ value: String, in sourceText: String, strictness: Strictness) -> Bool {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !v.isEmpty else { return false }
        let source = sourceText.lowercased()
        if source.contains(v) { return true }
        guard strictness == .relaxed else { return false }
        // Relaxed: a distinctive (non-stopword, ≥3-char) token of the value
        // occurs as a token in the clips. Handles name expansion/contraction
        // without letting a wholly-invented name through (no shared token).
        let sourceTokens = Set(distinctiveTokens(in: source))
        let valueTokens = distinctiveTokens(in: v)
        guard !valueTokens.isEmpty else { return false }
        return valueTokens.contains { sourceTokens.contains($0) }
    }

    /// Back-compat convenience: strict grounding (the pre-2026-07-23 default).
    static func isGrounded(_ value: String, in sourceText: String) -> Bool {
        isGrounded(value, in: sourceText, strictness: .strict)
    }

    // MARK: - Field modules (route mentions / topics through one seam)

    /// Mentions module — delegates to `MentionReconciler` (TruthReconciler's
    /// first module): maps each extracted mention name to its canonical
    /// library form (near-identical variants only; never a mis-merge).
    static func reconcileMentions(extracted: [String], library: [String]) -> [String] {
        MentionReconciler.reconcile(extracted: extracted, library: library)
    }

    /// Topics module — delegates to `TopicPalette`: returned topics that match
    /// an existing palette entry are rewritten to the palette's canonical
    /// casing (matches-first, novelties-next ordering). Non-matches pass
    /// through as NEW.
    static func reconcileTopics(returned: [String], existing: [String]) -> [String] {
        let partition = TopicPalette.partition(returned: returned, existing: existing)
        return partition.existing + partition.new
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

    /// Lowercased word tokens of length ≥3 that aren't stopwords — the
    /// "distinctive" tokens used for relaxed grounding. Operates on already-
    /// lowercased input.
    private static func distinctiveTokens(in s: String) -> [String] {
        s.split(whereSeparator: { !($0.isLetter || $0 == "'" || $0 == "-") })
            .map(String.init)
            .filter { $0.count >= 3 && !stopwords.contains($0) }
    }

    private static func isProperNounCandidate(_ word: String) -> Bool {
        guard word.count >= 2, let first = word.first, first.isUppercase else { return false }
        // Must be alphabetic (allow internal apostrophe/hyphen).
        guard word.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "-" }) else { return false }
        return !stopwords.contains(word.lowercased())
    }

    /// Common words that may appear capitalized mid-sentence (pronouns,
    /// determiners, connectors) or as capitalized dates — never flagged as
    /// fabricated names, and excluded from distinctive-token grounding.
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
