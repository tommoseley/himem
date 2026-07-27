import Testing
import Foundation
@testable import HiMem

/// F7c · the per-section help must hold the locked three-clause shape for every
/// topic: what it is → what you can do → **where it's maintained**. The third
/// clause is load-bearing (the part nothing else in the app says), so a topic
/// missing it is a defect, not a stylistic gap. Copy itself is F7e-drafted for
/// cold validation; these tests pin structure, not wording.
struct SectionHelpTests {

    @Test func everyTopicHasAllThreeClauses() {
        for topic in HelpTopic.allCases {
            #expect(!topic.title.isEmpty, "\(topic) has a title")
            #expect(!topic.whatItIs.isEmpty, "\(topic) has a 'what it is' clause")
            #expect(!topic.whatYouCanDo.isEmpty, "\(topic) has a 'what you can do' clause")
            #expect(!topic.whereItsMaintained.isEmpty,
                    "\(topic) has a 'where it's maintained' clause — the load-bearing one")
        }
    }

    /// All six sections Tom named are covered.
    @Test func coversEverySection() {
        let ids = Set(HelpTopic.allCases.map(\.id))
        for expected in ["memoryTopics", "memoryProjects", "memoryMentions",
                         "memoryClip", "memoryOrganize", "editClip"] {
            #expect(ids.contains(expected), "missing help topic: \(expected)")
        }
    }

    /// Ontology stays accurate where it's easy to regress: a clip is stored once
    /// and shared — the clip/edit topics must carry that, since it's the fact
    /// that makes "delete removes it everywhere" honest.
    @Test func clipTopicsStateTheSharedAtomModel() {
        #expect(HelpTopic.memoryClip.whereItsMaintained.lowercased().contains("stored once"))
        #expect(HelpTopic.editClip.whereItsMaintained.lowercased().contains("stored once"))
    }
}
