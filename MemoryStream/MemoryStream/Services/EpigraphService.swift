import Foundation
import CoreData

final class EpigraphService {
    static let shared = EpigraphService()

    private let cacheKey = "cachedEpigraphs"
    private let recentKey = "recentEpigraphs"
    private let apiURL = URL(string: "https://api.thecombine.ai/himem/epigraphs")!

    struct Epigraph: Codable {
        let text: String
        let source: String
        let stage: Int
    }

    // MARK: - Public API

    func todaysEpigraph(entryCount: Int) -> String {
        let catalog = loadCatalog()
        let pool = eligiblePool(from: catalog, entryCount: entryCount)
        guard !pool.isEmpty else { return "" }

        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let recent = recentlyShown()

        // Try to find one not shown recently
        let fresh = pool.filter { !recent.contains($0.text) }
        let candidates = fresh.isEmpty ? pool : fresh

        let index = dayOfYear % candidates.count
        let selected = candidates[index]

        trackShown(selected.text)
        return selected.text
    }

    /// Kick off an async refresh of the catalog from the API.
    func refreshFromAPI() {
        Task {
            do {
                var request = URLRequest(url: apiURL)
                request.httpMethod = "GET"
                request.timeoutInterval = 10

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

                let epigraphs = try JSONDecoder().decode([Epigraph].self, from: data)
                if let encoded = try? JSONEncoder().encode(epigraphs) {
                    UserDefaults.standard.set(encoded, forKey: cacheKey)
                }
            } catch {
                // Silent failure — bundled seed is the fallback
            }
        }
    }

    // MARK: - Stage Selection

    private func eligiblePool(from catalog: [Epigraph], entryCount: Int) -> [Epigraph] {
        let stage1 = catalog.filter { $0.stage == 1 }
        let stage2 = catalog.filter { $0.stage == 2 }
        let stage3 = catalog.filter { $0.stage == 3 }

        // Blend stages based on entry count
        if entryCount < 5 {
            return stage1
        } else if entryCount < 15 {
            // Mix stage 1 + 2
            return stage1 + stage2
        } else if entryCount < 25 {
            // Mostly stage 2, some stage 1
            return Array(stage1.prefix(3)) + stage2
        } else if entryCount < 50 {
            // Mix stage 2 + 3
            return Array(stage1.prefix(2)) + stage2 + stage3
        } else {
            // Mostly stage 3, some stage 2
            return Array(stage2.prefix(3)) + stage3
        }
    }

    // MARK: - Catalog Loading

    private func loadCatalog() -> [Epigraph] {
        // Try cached version first
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([Epigraph].self, from: data),
           !cached.isEmpty {
            return cached
        }

        // Fall back to bundled seed
        return loadBundledSeed()
    }

    private func loadBundledSeed() -> [Epigraph] {
        guard let url = Bundle.main.url(forResource: "epigraphs", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let epigraphs = try? JSONDecoder().decode([Epigraph].self, from: data) else {
            return []
        }
        return epigraphs
    }

    // MARK: - Recent Tracking

    private func recentlyShown() -> Set<String> {
        let list = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
        return Set(list)
    }

    private func trackShown(_ text: String) {
        var list = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
        list.append(text)
        if list.count > 7 { list = Array(list.suffix(7)) }
        UserDefaults.standard.set(list, forKey: recentKey)
    }

    // MARK: - Entry Count (lightweight)

    func entryCount() -> Int {
        let request = NSFetchRequest<NSNumber>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "isRecycled == NO OR isRecycled == nil")
        request.resultType = .countResultType
        return (try? StorageService.shared.viewContext.count(for: NSFetchRequest<JournalEntry>(entityName: "JournalEntry"))) ?? 0
    }
}
