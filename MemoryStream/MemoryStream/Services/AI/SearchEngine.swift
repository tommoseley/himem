import Foundation
import CoreData

final class SearchEngine {
    private let storage: StorageService

    init(storage: StorageService = .shared) {
        self.storage = storage
    }

    // MARK: - Legacy entry-type query (used by current SearchView; will be retired in Phase 2)

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

        if !query.text.isEmpty {
            for result in try searchByText(query.text, context: ctx) where !seenIds.contains(result.id) {
                results.append(result)
                seenIds.insert(result.id)
            }
        }

        if !query.entityTypes.isEmpty {
            for result in try searchByEntityTypes(query.entityTypes, text: query.text, context: ctx) where !seenIds.contains(result.id) {
                results.append(result)
                seenIds.insert(result.id)
            }
        }

        if let topicSlug = query.topicSlug {
            for result in try searchByTopic(topicSlug, context: ctx) where !seenIds.contains(result.id) {
                results.append(result)
                seenIds.insert(result.id)
            }
        }

        return results.sorted { $0.relevanceScore > $1.relevanceScore }
    }

    private func searchByText(_ text: String, context: NSManagedObjectContext) throws -> [SearchResult] {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "content CONTAINS[cd] %@ OR title CONTAINS[cd] %@", text, text)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \JournalEntry.createdAt, ascending: false)]
        request.fetchLimit = 100

        let entries = try context.fetch(request)
        return entries.map { entry in
            let score = computeTextRelevance(query: text, content: entry.content)
            return SearchResult(id: entry.id, entry: entry, matchType: .textMatch, relevanceScore: score)
        }
    }

    private func searchByEntityTypes(_ types: Set<ExtractedEntity.EntityType>, text: String, context: NSManagedObjectContext) throws -> [SearchResult] {
        let typeStrings = types.map(\.rawValue)
        let request = NSFetchRequest<ExtractedEntity>(entityName: "ExtractedEntity")

        if text.isEmpty {
            request.predicate = NSPredicate(format: "entityType IN %@", typeStrings)
        } else {
            request.predicate = NSPredicate(format: "entityType IN %@ AND value CONTAINS[cd] %@", typeStrings, text)
        }
        request.fetchLimit = 200

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

    private func searchByTopic(_ slug: String, context: NSManagedObjectContext) throws -> [SearchResult] {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "ANY topics.slug == %@", slug)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \JournalEntry.createdAt, ascending: false)]
        request.fetchLimit = 100

        let entries = try context.fetch(request)
        return entries.map { entry in
            SearchResult(id: entry.id, entry: entry, matchType: .topicMatch, relevanceScore: 0.9)
        }
    }

    private func computeTextRelevance(query: String, content: String) -> Double {
        let lowercaseContent = content.lowercased()
        let lowercaseQuery = query.lowercased()

        if lowercaseContent == lowercaseQuery { return 1.0 }
        let occurrences = lowercaseContent.components(separatedBy: lowercaseQuery).count - 1
        let lengthRatio = Double(query.count) / Double(max(content.count, 1))
        return min(Double(occurrences) * 0.2 + lengthRatio * 0.3, 0.95)
    }

    // MARK: - Parsed-query path (new — Phase 1 of Search redesign)

    struct Snippet: Equatable {
        let text: String
        let matchTerm: String
    }

    struct Hit: Identifiable {
        let id: UUID
        let entry: JournalEntry
        let snippet: Snippet?
        let relevance: Double
    }

    struct FacetCounts: Equatable {
        var topics: [String: Int] = [:]   // slug -> count
        var types: [TypeScope: Int] = [:]
    }

    func search(parsed: ParsedQuery, limit: Int = 200, context: NSManagedObjectContext? = nil) throws -> [Hit] {
        let ctx = context ?? storage.viewContext
        let entries = try fetchEntries(matching: parsed, recycled: false, limit: limit, context: ctx)
        return makeHits(from: entries, term: parsed.text.trimmingCharacters(in: .whitespaces))
    }

    /// Mirrors `search(parsed:)` against the recycle bin so the search field
    /// can surface entries the user deleted but might still want to find or restore.
    func searchRecycled(parsed: ParsedQuery, limit: Int = 200, context: NSManagedObjectContext? = nil) throws -> [Hit] {
        let ctx = context ?? storage.viewContext
        let entries = try fetchEntries(matching: parsed, recycled: true, limit: limit, context: ctx)
        return makeHits(from: entries, term: parsed.text.trimmingCharacters(in: .whitespaces))
    }

    private func makeHits(from entries: [JournalEntry], term: String) -> [Hit] {
        entries.map { entry in
            let snippet = term.isEmpty ? nil : extractSnippet(matching: term, in: entry.content)
            let relevance = term.isEmpty ? 0.5 : computeTextRelevance(query: term, content: entry.content)
            return Hit(id: entry.id, entry: entry, snippet: snippet, relevance: relevance)
        }
    }

    func topicFacetCounts(for parsed: ParsedQuery, context: NSManagedObjectContext? = nil) throws -> [String: Int] {
        var stripped = parsed
        stripped.topicSlug = nil
        let entries = try fetchEntries(matching: stripped, limit: 1000, context: context ?? storage.viewContext)
        var counts: [String: Int] = [:]
        for entry in entries {
            for topic in entry.topicsArray {
                counts[topic.slug, default: 0] += 1
            }
        }
        return counts
    }

    func typeFacetCounts(for parsed: ParsedQuery, context: NSManagedObjectContext? = nil) throws -> [TypeScope: Int] {
        var stripped = parsed
        stripped.typeScope = nil
        let entries = try fetchEntries(matching: stripped, limit: 1000, context: context ?? storage.viewContext)
        var counts: [TypeScope: Int] = [:]
        for entry in entries {
            for scope in inferredTypeScopes(of: entry) {
                counts[scope, default: 0] += 1
            }
        }
        return counts
    }

    /// Returns a single old-and-not-recently-viewed entry for the "Forgotten" card.
    /// Eligibility: not recycled, created > 6 months ago, never viewed or last viewed > 3 months ago.
    func forgottenCard(now: Date = Date(),
                       calendar: Calendar = .current,
                       picker: ([JournalEntry]) -> JournalEntry? = { $0.randomElement() },
                       context: NSManagedObjectContext? = nil) throws -> JournalEntry? {
        guard
            let createdCutoff = calendar.date(byAdding: .month, value: -6, to: now),
            let viewedCutoff = calendar.date(byAdding: .month, value: -3, to: now)
        else { return nil }

        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(
            format: "(isRecycled == NO OR isRecycled == nil) AND createdAt < %@ AND (lastViewedAt == nil OR lastViewedAt < %@)",
            createdCutoff as NSDate,
            viewedCutoff as NSDate
        )
        request.fetchLimit = 50

        let candidates = try (context ?? storage.viewContext).fetch(request)
        return picker(candidates)
    }

    // MARK: - Parsed query plumbing

    private func fetchEntries(matching parsed: ParsedQuery, recycled: Bool = false, limit: Int, context: NSManagedObjectContext) throws -> [JournalEntry] {
        var predicates: [NSPredicate] = [
            recycled
                ? NSPredicate(format: "isRecycled == YES")
                : NSPredicate(format: "isRecycled == NO OR isRecycled == nil")
        ]

        let term = parsed.text.trimmingCharacters(in: .whitespaces)
        if !term.isEmpty {
            predicates.append(NSPredicate(format: "content CONTAINS[cd] %@ OR title CONTAINS[cd] %@", term, term))
        }
        if let slug = parsed.topicSlug {
            predicates.append(NSPredicate(format: "ANY topics.slug == %@", slug))
        }
        if let typeScope = parsed.typeScope {
            predicates.append(predicate(for: typeScope))
        }
        if let interval = parsed.dateRange {
            predicates.append(NSPredicate(
                format: "createdAt >= %@ AND createdAt < %@",
                interval.start as NSDate,
                interval.end as NSDate
            ))
        }

        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \JournalEntry.createdAt, ascending: false)]
        request.fetchLimit = limit
        return try context.fetch(request)
    }

    private func predicate(for type: TypeScope) -> NSPredicate {
        switch type {
        case .voice:
            return NSPredicate(
                format: "inputType IN %@ OR ANY mediaReferences.mediaType == %@",
                ["voice_in_app", "siri"],
                "voice"
            )
        case .text:
            return NSPredicate(
                format: "inputType == %@ AND mediaReferences.@count == 0",
                "typed"
            )
        case .photo:
            return NSPredicate(format: "ANY mediaReferences.mediaType == %@", "image")
        case .video:
            return NSPredicate(format: "ANY mediaReferences.mediaType == %@", "video")
        }
    }

    private func inferredTypeScopes(of entry: JournalEntry) -> Set<TypeScope> {
        var scopes: Set<TypeScope> = []
        let media = entry.mediaReferencesArray
        if media.contains(where: { $0.mediaTypeEnum == .image }) { scopes.insert(.photo) }
        if media.contains(where: { $0.mediaTypeEnum == .video }) { scopes.insert(.video) }
        let isVoiceInput = entry.inputTypeEnum == .voiceInApp || entry.inputTypeEnum == .siri
        if isVoiceInput || media.contains(where: { $0.mediaTypeEnum == .voice }) {
            scopes.insert(.voice)
        }
        if entry.inputTypeEnum == .typed && media.isEmpty {
            scopes.insert(.text)
        }
        return scopes
    }

    private func extractSnippet(matching term: String, in content: String, contextChars: Int = 70) -> Snippet? {
        guard let matchRange = content.range(of: term, options: .caseInsensitive) else { return nil }
        let lower = content.index(matchRange.lowerBound, offsetBy: -contextChars, limitedBy: content.startIndex) ?? content.startIndex
        let upper = content.index(matchRange.upperBound, offsetBy: contextChars, limitedBy: content.endIndex) ?? content.endIndex
        let body = String(content[lower..<upper])
        let prefix = lower > content.startIndex ? "…" : ""
        let suffix = upper < content.endIndex ? "…" : ""
        return Snippet(text: prefix + body + suffix, matchTerm: term)
    }
}
