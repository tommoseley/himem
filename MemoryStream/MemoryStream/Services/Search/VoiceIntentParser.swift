import Foundation
import NaturalLanguage

/// User-tunable pace for voice-search silence auto-confirm. Done remains the
/// explicit completion path; this is the safety-net delay.
enum VoiceSilenceMode: String, CaseIterable, Identifiable {
    case snappy
    case standard
    case patient

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .snappy: return 3
        case .standard: return 10
        case .patient: return 20
        }
    }

    var label: String {
        switch self {
        case .snappy: return "Snappy"
        case .standard: return "Standard"
        case .patient: return "Patient"
        }
    }

    var subtitle: String {
        switch self {
        case .snappy: return "3 seconds"
        case .standard: return "10 seconds"
        case .patient: return "20 seconds"
        }
    }
}

/// Local intent parser for voice search. No network. Maps a free-form transcript
/// to a structured search expression that ScopeParser can re-parse.
enum VoiceIntentParser {

    private static let filler: Set<String> = [
        "find", "show", "me", "the", "a", "an", "memory", "memories",
        "about", "for", "on", "in", "i", "saw", "had", "from",
        "search", "look", "looking", "of", "my", "any", "anything"
    ]

    /// Generic nouns that survive part-of-speech tagging but carry no real
    /// search signal. Filtered before phrase grouping so they don't anchor
    /// useless pills.
    private static let genericNouns: Set<String> = [
        "thing", "things", "stuff", "way", "view", "place", "moment", "time",
        "note", "notes", "entry", "entries", "kind", "sort", "lot", "bit"
    ]

    private static let typeKeywords: [(words: [String], scope: TypeScope)] = [
        (["voice", "audio", "recording", "recordings"], .voice),
        (["photo", "photos", "picture", "pictures", "image", "images"], .photo),
        (["video", "videos", "clip", "clips"], .video),
        (["text", "note", "notes", "typed"], .text)
    ]

    private static let dateKeywords: [(phrase: String, token: String)] = [
        // Multi-word phrases first; matched on lowercased transcript.
        ("last week", "date:last-week"),
        ("this week", "date:this-week"),
        ("last month", "date:last-month"),
        ("this month", "date:this-month"),
        ("yesterday", "date:yesterday"),
        ("today", "date:today")
    ]

    struct Result {
        /// Rebuilt query string suitable for ScopeParser (and the search field).
        let query: String
        /// Joined search text — used to build `query`.
        let terms: String
        /// Distinct noun phrases extracted from the transcript, one per
        /// LOOKING FOR pill in the interpreted overlay.
        let termPhrases: [String]
        /// Scopes extracted, for display in the interpreted overlay.
        let scopes: [String]
    }

    static func parse(_ transcript: String, knownTopics: [String] = []) -> Result {
        var working = " " + transcript.lowercased() + " "
        var scopes: [String] = []

        // Date phrases (multi-word match before tokenization).
        for (phrase, token) in dateKeywords where working.contains(" \(phrase) ") {
            working = working.replacingOccurrences(of: " \(phrase) ", with: " ")
            scopes.append(token)
        }

        // Topic name match (longest first, multi-word allowed).
        let sortedTopics = knownTopics.sorted { $0.count > $1.count }
        for topic in sortedTopics {
            let lower = " \(topic.lowercased()) "
            if working.contains(lower) {
                working = working.replacingOccurrences(of: lower, with: " ")
                let slug = topic.lowercased().replacingOccurrences(of: " ", with: "-")
                scopes.append("topic:\(slug)")
                break
            }
        }

        // Type scope (single-token match; remove from working before extraction).
        var tokens = working
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        for (words, scope) in typeKeywords {
            if let idx = tokens.firstIndex(where: { words.contains($0) }) {
                tokens.remove(at: idx)
                scopes.append("type:\(scope.rawValue)")
                break
            }
        }

        let scrubbed = tokens.joined(separator: " ")
        let phrases = extractKeyPhrases(from: scrubbed)
        let terms = phrases.joined(separator: " ")

        let queryParts = scopes + (terms.isEmpty ? [] : [terms])
        return Result(
            query: queryParts.joined(separator: " "),
            terms: terms,
            termPhrases: phrases,
            scopes: scopes
        )
    }

    /// Walks the cleaned transcript with the NaturalLanguage tagger and groups
    /// consecutive content tokens (nouns + numbers) into phrases. Each phrase
    /// becomes its own pill in the interpreted overlay. Generic nouns
    /// ("things", "place", …) and filler words break the run, so the result
    /// is just the distinct subjects the speaker mentioned.
    private static func extractKeyPhrases(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text

        var phrases: [String] = []
        var current: [String] = []

        let flush = {
            if !current.isEmpty {
                phrases.append(current.joined(separator: " "))
                current = []
            }
        }

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, range in
            let word = String(text[range])
            let lower = word.lowercased()
            let isContent = (tag == .noun || tag == .number)
            let isJunk = filler.contains(lower) || genericNouns.contains(lower)
            if isContent && !isJunk {
                current.append(word)
            } else {
                flush()
            }
            return true
        }
        flush()

        // De-dupe (e.g. user said the same noun twice) and cap at 3 pills.
        var seen: Set<String> = []
        var unique: [String] = []
        for phrase in phrases where !seen.contains(phrase.lowercased()) {
            seen.insert(phrase.lowercased())
            unique.append(phrase)
        }
        return Array(unique.prefix(3))
    }
}
