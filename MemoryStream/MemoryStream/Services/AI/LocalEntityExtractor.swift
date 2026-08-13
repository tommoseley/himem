import Foundation
import NaturalLanguage

/// Abstraction over the local NLTagger pass so `ProcessingEngine`
/// can be unit-tested with a deterministic stub. Production code
/// uses `LocalEntityExtractor`; tests can inject anything that
/// returns a fixed `LocalEntityExtractor.LocalResult` — see
/// `ProcessingEngineFallbackTests.StubEntityExtractor`.
///
/// The protocol lives next to the concrete type so the nested
/// `LocalResult` / `LocalEntity` value types stay in one place.
protocol EntityExtractor {
    func extractEntities(from text: String) -> LocalEntityExtractor.LocalResult
}

final class LocalEntityExtractor: EntityExtractor {
    static let shared = LocalEntityExtractor()

    private let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])

    /// **B14, confirmed 2026-08-12.** One shared mutable `NLTagger` behind a
    /// `shared` singleton, and `extractEntities` is a compound operation —
    /// assign `tagger.string`, then enumerate over it. Two callers interleaving
    /// leaves the second enumerating a string the first has already replaced,
    /// and the process dies: `signal segv`, or `Crash: HiMem` taking down the
    /// whole test host and failing 41 unrelated tests as collateral.
    ///
    /// CLAUDE.md already named this singleton unsafe and prescribed
    /// `@Suite(.serialized)` for suites that touch it — but that orders tests
    /// *within* a suite and Swift Testing runs suites concurrently, so the
    /// remedy could never cover the real case. It held only while few tests
    /// reached the proposer; adding a handful tipped it into reliable crashes.
    ///
    /// B14 had it as circumstantial ("reachable from a main-thread render
    /// path"). It is now reproduced. The lock wraps the whole
    /// assign-then-enumerate, because the compound operation is the unit that
    /// must be atomic — the same shape, and the same fix, as
    /// `BenchClipReviewStore`'s read-modify-write.
    private let lock = NSLock()

    struct LocalResult {
        let entities: [LocalEntity]
    }

    struct LocalEntity {
        let type: ExtractedEntity.EntityType
        let value: String
        let confidence: Double
        let range: Range<String.Index>
    }

    func extractEntities(from text: String) -> LocalResult {
        lock.lock()
        defer { lock.unlock() }
        tagger.string = text

        var entities: [LocalEntity] = []

        // Named entity recognition — people, places, organizations
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            guard let tag else { return true }

            let value = String(text[range]).trimmingCharacters(in: .whitespaces)
            guard value.count > 1 else { return true }

            let entityType: ExtractedEntity.EntityType?
            let confidence: Double

            switch tag {
            case .personalName:
                entityType = .person
                confidence = 0.80
            case .placeName:
                entityType = .project
                confidence = 0.75
            case .organizationName:
                entityType = .project
                confidence = 0.75
            default:
                entityType = nil
                confidence = 0
            }

            if let entityType {
                entities.append(LocalEntity(
                    type: entityType,
                    value: value,
                    confidence: confidence,
                    range: range
                ))
            }

            return true
        }

        return LocalResult(entities: entities)
    }
}
