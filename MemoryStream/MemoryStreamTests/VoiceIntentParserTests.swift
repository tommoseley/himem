import Testing
import Foundation
@testable import HiMem

struct VoiceIntentParserTests {

    @Test func parse_capsTermsToTrailingNouns() {
        // The user's actual problematic transcript. Garden topic should be
        // extracted as a scope; verbose filler should NOT appear as a term
        // pill; meaningful trailing noun phrase ("bed number one") should.
        let result = VoiceIntentParser.parse(
            "I need to get a view on all of the garden things that are taking place in Garden bed number one",
            knownTopics: ["Garden"]
        )
        #expect(result.scopes.contains("topic:garden"))
        // No phrase should contain filler/generic nouns like "things" / "place"
        for phrase in result.termPhrases {
            #expect(!phrase.lowercased().contains("things"))
            #expect(!phrase.lowercased().contains("place"))
            #expect(!phrase.lowercased().contains("view"))
        }
        // At most 3 pills.
        #expect(result.termPhrases.count <= 3)
    }

    @Test func parse_groupsConsecutiveNounsIntoPhrases() {
        let result = VoiceIntentParser.parse("find tomato seedlings and pumpkin harvest")
        // Two distinct phrases since "and" breaks the run.
        let lowered = result.termPhrases.map { $0.lowercased() }
        #expect(lowered.contains { $0.contains("tomato") || $0.contains("seedlings") })
        #expect(lowered.contains { $0.contains("pumpkin") || $0.contains("harvest") })
    }

    @Test func parse_extractsNounsFromShortQuery() {
        let result = VoiceIntentParser.parse("find the tomato trellis from last spring")
        let lowered = result.termPhrases.map { $0.lowercased() }
        #expect(lowered.contains { $0.contains("tomato") || $0.contains("trellis") })
    }

    @Test func parse_extractsTypeAndTopicScopes() {
        let result = VoiceIntentParser.parse(
            "show me voice notes about cooking",
            knownTopics: ["Cooking"]
        )
        #expect(result.scopes.contains("type:voice"))
        #expect(result.scopes.contains("topic:cooking"))
    }

    @Test func parse_dateKeywords() {
        let result = VoiceIntentParser.parse("memories from last week")
        #expect(result.scopes.contains("date:last-week"))
    }

    @Test func parse_emptyInput() {
        let result = VoiceIntentParser.parse("")
        #expect(result.terms.isEmpty)
        #expect(result.termPhrases.isEmpty)
        #expect(result.scopes.isEmpty)
        #expect(result.query.isEmpty)
    }
}
