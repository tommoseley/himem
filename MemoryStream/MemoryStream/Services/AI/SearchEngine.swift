import Foundation
import CoreData

final class SearchEngine {
    private let storage = StorageService.shared

    struct SearchQuery {
        var text: String = ""
        var entityTypes: Set<ExtractedEntity.EntityType> = []
        var topicSlug: String? = nil
    }

    struct SearchResult: Identifiable {
        let id: UUID
        let entry: JournalEntry
        let matchType: MatchType
        let relevanceScore: Double

        enum MatchType {
            case textMatch
            case entityMatch(String)
            case topicMatch
        }
    }

    func search(query: SearchQuery, context: NSManagedObjectContext? = nil) throws -> [SearchResult] {
        let ctx = context ?? storage.viewContext
        var results: [SearchResult] = []
        var seenIds: Set<UUID> = []

        // Text search on journal entries
        if !query.text.isEmpty {
            let textResults = try searchByText(query.text, context: ctx)
            for result in textResults where !seenIds.contains(result.id) {
                results.append(result)
                seenIds.insert(result.id)
            }
        }

        // Entity type filter
        if !query.entityTypes.isEmpty {
            let entityResults = try searchByEntityTypes(query.entityTypes, text: query.text, context: ctx)
            for result in entityResults where !seenIds.contains(result.id) {
                results.append(result)
                seenIds.insert(result.id)
            }
        }

        // Topic filter
        if let topicSlug = query.topicSlug {
            let topicResults = try searchByTopic(topicSlug, context: ctx)
            for result in topicResults where !seenIds.contains(result.id) {
                results.append(result)
                seenIds.insert(result.id)
            }
        }

        return results.sorted { $0.relevanceScore > $1.relevanceScore }
    }

    // MARK: - Text Search

    private func searchByText(_ text: String, context: NSManagedObjectContext) throws -> [SearchResult] {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "content CONTAINS[cd] %@ OR title CONTAINS[cd] %@", text, text)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \JournalEntry.createdAt, ascending: false)]

        let entries = try context.fetch(request)
        return entries.map { entry in
            let score = computeTextRelevance(query: text, content: entry.content)
            return SearchResult(id: entry.id, entry: entry, matchType: .textMatch, relevanceScore: score)
        }
    }

    // MARK: - Entity Type Search

    private func searchByEntityTypes(_ types: Set<ExtractedEntity.EntityType>, text: String, context: NSManagedObjectContext) throws -> [SearchResult] {
        let typeStrings = types.map(\.rawValue)
        let request = NSFetchRequest<ExtractedEntity>(entityName: "ExtractedEntity")

        if text.isEmpty {
            request.predicate = NSPredicate(format: "entityType IN %@", typeStrings)
        } else {
            request.predicate = NSPredicate(format: "entityType IN %@ AND value CONTAINS[cd] %@", typeStrings, text)
        }

        let entities = try context.fetch(request)
        return entities.compactMap { entity in
            guard let entry = entity.entry else { return nil }
            return SearchResult(
                id: entry.id,
                entry: entry,
                matchType: .entityMatch(entity.value),
                relevanceScore: entity.confidenceScore
            )
        }
    }

    // MARK: - Topic Search

    private func searchByTopic(_ slug: String, context: NSManagedObjectContext) throws -> [SearchResult] {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "ANY topics.slug == %@", slug)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \JournalEntry.createdAt, ascending: false)]

        let entries = try context.fetch(request)
        return entries.map { entry in
            SearchResult(id: entry.id, entry: entry, matchType: .topicMatch, relevanceScore: 0.9)
        }
    }

    // MARK: - Relevance Scoring

    private func computeTextRelevance(query: String, content: String) -> Double {
        let lowercaseContent = content.lowercased()
        let lowercaseQuery = query.lowercased()

        // Exact match scores highest
        if lowercaseContent == lowercaseQuery { return 1.0 }

        // Count occurrences
        let occurrences = lowercaseContent.components(separatedBy: lowercaseQuery).count - 1
        let lengthRatio = Double(query.count) / Double(max(content.count, 1))

        // Score based on frequency and proportion
        return min(Double(occurrences) * 0.2 + lengthRatio * 0.3, 0.95)
    }
}
