import Testing
import Foundation
@testable import HiMem

/// RH-7 (July 20 2026) — the on-device (Free) organizer cannot reliably
/// TYPE a mention at the 3B-model scale, so it must store every mention
/// **untyped as `.idea`** and the UI renders the neutral idea glyph —
/// never a wrongly-guessed person/place/org. Frontier/Plus types them.
///
/// These lock the guarantee end to end: `mapToAnalysisResult` emits only
/// `.idea` entities, and the mention-write path maps `"idea"` → the neutral
/// `.idea` MentionType (whose glyph is the neutral lightbulb, not a
/// person/place/org symbol).
@Suite
struct OnDeviceMentionsNeutralTypeTests {

    @Test func onDeviceMentions_areAllUntypedIdea_neverGuessedTypes() {
        let output = OnDeviceOrganizer.OrganizeOutput(
            title: "t", summary: "s", topics: [],
            mentions: ["Bob", "Naples", "Acme Corp"]   // a person, a place, an org
        )
        let result = OnDeviceOrganizer.mapToAnalysisResult(output)
        #expect(result.entities.count == 3)
        // Despite the names clearly being person/place/org, on-device stores
        // them ALL as idea — it never guesses a type it can't stand behind.
        for e in result.entities {
            #expect(e.type == ExtractedEntity.EntityType.idea.rawValue,
                    "on-device mention \(e.value) must be untyped .idea, not \(e.type)")
        }
    }

    @Test func idea_mapsToNeutralIdeaMentionType() {
        // The mention-write path (ProcessingEngine) maps the entity type
        // string through MentionMigration; an on-device "idea" must land on
        // the neutral .idea MentionType (lightbulb glyph), not a typed one.
        #expect(MentionMigration.mappedType(for: .idea) == .idea)
        #expect(Mention.MentionType.idea.sfSymbol == "lightbulb")
    }
}
