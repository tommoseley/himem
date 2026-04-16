import Foundation
import SwiftUI

@MainActor
class SearchViewModel: ObservableObject {
    @Published var queryText = ""
    @Published var selectedEntityTypes: Set<ExtractedEntity.EntityType> = []
    @Published var results: [EntryDisplayModel] = []

    private let searchEngine = SearchEngine()
    private let storage = StorageService.shared

    func performSearch() {
        guard !queryText.isEmpty || !selectedEntityTypes.isEmpty else {
            results = []
            return
        }

        let query = SearchEngine.SearchQuery(
            text: queryText,
            entityTypes: selectedEntityTypes
        )

        do {
            let searchResults = try searchEngine.search(query: query)
            results = searchResults.map { result in
                mapToDisplayModel(result.entry)
            }
        } catch {
            print("Search failed: \(error)")
            results = []
        }
    }

    func toggleEntityType(_ type: ExtractedEntity.EntityType) {
        if selectedEntityTypes.contains(type) {
            selectedEntityTypes.remove(type)
        } else {
            selectedEntityTypes.insert(type)
        }
        performSearch()
    }

    private func mapToDisplayModel(_ entry: JournalEntry) -> EntryDisplayModel {
        let task = entry.latestProcessingTask
        let inference = entry.inferenceSummary

        return EntryDisplayModel(
            id: entry.id,
            displayTitle: entry.displayTitle,
            content: entry.content,
            inputType: entry.inputTypeEnum,
            createdAt: entry.createdAt,
            processingStatus: task?.statusEnum,
            progressDescription: task?.progressDescription,
            tags: entry.entitiesArray.map { entity in
                TagDisplayModel(
                    id: entity.id,
                    value: entity.value,
                    entityType: entity.entityTypeEnum,
                    confidence: entity.confidenceScore
                )
            },
            topicNames: entry.topicsArray.map(\.name),
            audioFilePath: entry.audioFilePath,
            inferenceSummary: inference?.summaryText,
            feedbackState: inference?.feedbackStateEnum
        )
    }
}
