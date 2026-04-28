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
            ErrorState.shared.report(.searchFailed(error.localizedDescription))
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
        EntryMapper.mapToDisplayModel(entry)
    }
}
