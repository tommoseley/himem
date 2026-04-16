import Foundation
import NaturalLanguage

final class LocalEntityExtractor {
    static let shared = LocalEntityExtractor()

    private let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])

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
