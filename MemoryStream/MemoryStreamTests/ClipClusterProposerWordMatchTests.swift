import Testing
import Foundation
@testable import HiMem

/// Money tests for `ClipClusterProposer.proposeWordMatch` per
/// `Captured Clips · session-first · spec.md` v3 § 82. The word-
/// match rule is the highest-risk false-positive vector per Tom's
/// July 4 watch item; these tests exercise the distinctiveness
/// gate (proper noun / bigram / TF-rare) and prove that common
/// content words do NOT cluster.
///
/// Uses `StubEntityExtractor` because NLTagger is unreliable on
/// the iOS 26 simulator (memory: `feedback_nltagger_simulator`).
/// Real-device coverage is the source of truth; simulator tests
/// inject a deterministic extractor.
@Suite(.serialized)
struct ClipClusterProposerWordMatchTests {

    // MARK: - Fixtures

    private func session(
        at time: Date,
        transcript: String
    ) -> ClipGroup {
        let clip = InboxClip(
            clipId: UUID(),
            capturedAt: time,
            duration: 30,
            transcript: transcript,
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: "\(UUID()).caf",
            transcriptionAttempted: true,
            rollGroupId: nil
        )
        return ClipGroup(clips: [clip])
    }

    /// Deterministic entity-extractor stub. Callers map exact
    /// strings the tokenizer will see (lowercased) to the entities
    /// NLTagger would ideally produce on device.
    private final class StubEntityExtractor: EntityExtractor {
        var entitiesForText: [String: [LocalEntityExtractor.LocalEntity]] = [:]
        var defaultEntities: [LocalEntityExtractor.LocalEntity] = []
        func extractEntities(from text: String) -> LocalEntityExtractor.LocalResult {
            LocalEntityExtractor.LocalResult(
                entities: entitiesForText[text] ?? defaultEntities
            )
        }
    }

    private func entity(_ value: String, type: ExtractedEntity.EntityType = .project) -> LocalEntityExtractor.LocalEntity {
        LocalEntityExtractor.LocalEntity(
            type: type,
            value: value,
            confidence: 0.9,
            range: "".startIndex..<"".startIndex
        )
    }

    // MARK: - Positive: proper noun / distinctive term

    /// The spec's Hosta Hideaway case. Two sessions mention a
    /// place proper-noun-detected as an organizationName → cluster.
    @Test
    func properNoun_appearingInTwoSessions_clusters() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let t1 = "Remember the Hosta Hideaway in Gettysburg? Dillsburg."
        let t2 = "www.thehostahideaway.com — Hosta Hideaway looks great"
        let s1 = session(at: base, transcript: t1)
        let s2 = session(at: base.addingTimeInterval(1800), transcript: t2)

        let stub = StubEntityExtractor()
        // NLTagger's likely surface — the extractor detects
        // "Hosta Hideaway" in both transcripts (same surface form
        // regardless of casing — the proposer lowercases for
        // comparison).
        stub.entitiesForText[t1] = [entity("Hosta Hideaway")]
        stub.entitiesForText[t2] = [entity("Hosta Hideaway")]

        let proposals = ClipClusterProposer.proposeWordMatch(
            sessions: [s1, s2],
            entityExtractor: stub
        )

        #expect(proposals.count == 1, "Two sessions with a shared proper noun must cluster; got \(proposals.count)")
        #expect(proposals.first?.ruleTag == .wordMatch)
        #expect(proposals.first?.clipIds.count == 2)
    }

    // MARK: - Negative: common content words

    /// The spec's stated failure mode. "Restaurant" appears in 5
    /// sessions across the inbox → too common to be a signal → no
    /// cluster. This test is the guard against Tom's watch item.
    @Test
    func commonContentWord_restaurant_doesNotCluster() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let sessions = [
            session(at: base,
                    transcript: "great restaurant tonight great flavors"),
            session(at: base.addingTimeInterval(3600),
                    transcript: "another restaurant nearby was excellent"),
            session(at: base.addingTimeInterval(7200),
                    transcript: "restaurant with excellent service"),
            session(at: base.addingTimeInterval(10800),
                    transcript: "found a restaurant that opens late"),
            session(at: base.addingTimeInterval(14400),
                    transcript: "third restaurant this week"),
        ]

        let stub = StubEntityExtractor()  // no proper nouns

        let proposals = ClipClusterProposer.proposeWordMatch(
            sessions: sessions,
            entityExtractor: stub
        )

        #expect(proposals.isEmpty, "Content word 'restaurant' appearing across many sessions must NOT cluster — spec § 82 explicitly names this failure mode. Got \(proposals.count) proposals.")
    }

    /// "Lovely" — the spec's other named failure mode. Common
    /// adjective; two sessions each mentioning it once must not
    /// cluster because "lovely" isn't a proper noun and isn't a
    /// bigram. Post-tightening (v1 launch): single content words
    /// don't qualify as distinctive at all, regardless of
    /// corpus frequency. This is the honest reading of "under-
    /// suggest" — a lone shared adjective reads as random.
    @Test
    func lovelyAloneTwoSessions_doesNotCluster() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let s1 = session(at: base,
                         transcript: "Nazareth is a lovely little town")
        let s2 = session(at: base.addingTimeInterval(3600),
                         transcript: "This town is quite lovely honestly")

        let stub = StubEntityExtractor()

        let proposals = ClipClusterProposer.proposeWordMatch(
            sessions: [s1, s2],
            entityExtractor: stub
        )

        #expect(proposals.isEmpty, "Single content word 'lovely' must not cluster — spec § 82 explicitly names this failure mode; only proper nouns + bigrams cluster in v1.")
    }

    // MARK: - Positive: bigram

    /// A shared bigram of two distinctive components is a strong
    /// signal even without proper-noun detection.
    @Test
    func sharedBigram_distinctiveComponents_clusters() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let s1 = session(at: base,
                         transcript: "vintage guitars everywhere at the shop")
        let s2 = session(at: base.addingTimeInterval(3600),
                         transcript: "quite a collection of vintage guitars")

        let stub = StubEntityExtractor()

        let proposals = ClipClusterProposer.proposeWordMatch(
            sessions: [s1, s2],
            entityExtractor: stub
        )

        #expect(proposals.count == 1, "Shared distinctive bigram must cluster")
        #expect(proposals.first?.ruleTag == .wordMatch)
    }

    /// **Money test for the July 4 revision** — the exact "little
    /// town" case from Tom's dogfood screenshot. Both components
    /// are common content words; the bigram must be rejected as a
    /// generic-content false positive. Spec § "Clustering is
    /// Honest-Label" explicitly names this pattern.
    @Test
    func bigramOfCommonContentWords_littleTown_doesNotCluster() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let s1 = session(at: base,
                         transcript: "Milford is a little town that looks nice")
        let s2 = session(at: base.addingTimeInterval(3600),
                         transcript: "Nazareth is a little town too")

        let stub = StubEntityExtractor()
        // No proper-noun signal on the shared bigram components.

        let proposals = ClipClusterProposer.proposeWordMatch(
            sessions: [s1, s2],
            entityExtractor: stub
        )

        for p in proposals {
            #expect(!p.proposedName.lowercased().contains("little town"),
                    "\"little town\" must not surface as a cluster proposal — both components are common content words")
        }
    }

    /// A bigram with a proper-noun component still passes even if
    /// the OTHER component is a common content word. This is the
    /// escape hatch for cases like "Machu town" where the proper
    /// noun confers distinctness on the pair.
    @Test
    func bigramWithProperNounComponent_survivesFilter() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let s1 = session(at: base,
                         transcript: "the Nazareth restaurant was great tonight")
        let s2 = session(at: base.addingTimeInterval(3600),
                         transcript: "Nazareth restaurant recommended by friends")

        let stub = StubEntityExtractor()
        stub.entitiesForText["the Nazareth restaurant was great tonight"] = [entity("Nazareth")]
        stub.entitiesForText["Nazareth restaurant recommended by friends"] = [entity("Nazareth")]

        let proposals = ClipClusterProposer.proposeWordMatch(
            sessions: [s1, s2],
            entityExtractor: stub
        )

        // Either the proper-noun "Nazareth" or the bigram
        // "Nazareth restaurant" should cluster.
        #expect(!proposals.isEmpty, "Bigram containing a proper noun must still cluster even if other component is common")
    }

    // MARK: - Guards

    /// Only one session mentions the token → nothing to cluster.
    @Test
    func singleSessionMentionsToken_doesNotCluster() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let s1 = session(at: base, transcript: "Machu Picchu is on my list")
        let s2 = session(at: base.addingTimeInterval(3600),
                         transcript: "unrelated grocery run today")

        let stub = StubEntityExtractor()
        stub.entitiesForText["Machu Picchu is on my list"] = [entity("Machu Picchu")]

        let proposals = ClipClusterProposer.proposeWordMatch(
            sessions: [s1, s2],
            entityExtractor: stub
        )

        #expect(proposals.isEmpty)
    }

    /// Stopwords never trigger a cluster even if they appear in
    /// every session. Guard against the ≥4-char band accidentally
    /// admitting a common-word cluster.
    @Test
    func stopwordsAlone_doNotCluster() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let s1 = session(at: base,
                         transcript: "really actually pretty much just yeah")
        let s2 = session(at: base.addingTimeInterval(3600),
                         transcript: "really actually pretty much just yeah")

        let stub = StubEntityExtractor()

        let proposals = ClipClusterProposer.proposeWordMatch(
            sessions: [s1, s2],
            entityExtractor: stub
        )

        #expect(proposals.isEmpty, "Stopword tokens must not cluster")
    }
}
