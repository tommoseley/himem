import Foundation
import SwiftUI
import CoreData

@MainActor
final class SearchViewModel: ObservableObject {

    enum State: Equatable {
        case preSearch
        case typing
        case results
        case noResults
    }

    // MARK: - Published

    @Published var queryText: String = ""
    @Published private(set) var state: State = .preSearch
    @Published private(set) var hits: [SearchEngine.Hit] = []
    @Published private(set) var clipHits: [SearchEngine.ClipHit] = []
    @Published private(set) var recycledHits: [SearchEngine.Hit] = []
    /// Object scope facet — Memories · Clips · All (default Memories).
    @Published private(set) var objectScope: ObjectScope = .memories
    /// Active "When" date range (from the When popover). Overrides any
    /// `date:` token while set; `nil` = Any time.
    @Published private(set) var whenRange: DateInterval? = nil
    @Published private(set) var whenLabel: String? = nil
    @Published private(set) var topicCounts: [String: Int] = [:]
    @Published private(set) var typeCounts: [TypeScope: Int] = [:]
    @Published private(set) var recentSearches: [String] = []
    @Published private(set) var topicsForBrowse: [TopicBrowseItem] = []
    @Published private(set) var forgotten: ForgottenItem?

    // MARK: - Dependencies

    private let engine: SearchEngine
    private let storage: StorageService
    private let recentsKey = "search.recentQueries"
    private let recentsMax = 10

    private var debounceTask: Task<Void, Never>?
    private var committed: Bool = false

    init(engine: SearchEngine? = nil, storage: StorageService = .shared) {
        self.storage = storage
        self.engine = engine ?? SearchEngine(storage: storage)
        self.recentSearches = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
    }

    deinit {
        debounceTask?.cancel()
    }

    // MARK: - Models for the UI

    struct TopicBrowseItem: Identifiable, Equatable {
        let id: UUID
        let name: String
        let slug: String
        let paletteKey: String?
        let entryCount: Int
    }

    struct ForgottenItem: Identifiable, Equatable {
        let id: UUID
        let snippet: String
        let topicName: String?
        let topicPaletteKey: String?
        let createdAt: Date
        var ageLabel: String {
            let months = Calendar.current.dateComponents([.month], from: createdAt, to: Date()).month ?? 0
            if months >= 12 { return "\(months / 12) year\(months / 12 == 1 ? "" : "s") ago" }
            if months >= 1 { return "\(months) month\(months == 1 ? "" : "s") ago" }
            return "weeks ago"
        }
    }

    // MARK: - Lifecycle for the search sheet

    func onAppear() {
        if queryText.isEmpty {
            state = .preSearch
            committed = false
            loadPreSearchData()
        }
    }

    private func loadPreSearchData() {
        topicsForBrowse = fetchTopicsForBrowse()
        forgotten = fetchForgotten()
    }

    // MARK: - Query input

    func onQueryChanged(_ newValue: String) {
        // SwiftUI's TextField echoes our programmatic queryText updates back
        // through this setter. If the value didn't actually change, treat it
        // as a no-op so we don't clobber state set by toggleTopicScope etc.
        if newValue == queryText { return }
        queryText = newValue
        committed = false
        if newValue.isEmpty {
            cancelDebounce()
            hits = []
            clipHits = []
            recycledHits = []
            state = .preSearch
            loadPreSearchData()
            return
        }
        state = .typing
        scheduleLiveSearch()
    }

    func submit() {
        cancelDebounce()
        let trimmed = queryText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        committed = true
        executeSearch()
        recordRecent(trimmed)
    }

    func clearQuery() {
        queryText = ""
        committed = false
        hits = []
        clipHits = []
        recycledHits = []
        state = .preSearch
        loadPreSearchData()
    }

    // MARK: - Scope chip toggles (compose / decompose)

    func toggleTopicScope(_ slug: String) {
        let active = ScopeParser.parse(queryText).topicSlug == slug
        toggleScope(prefix: "topic", value: slug, isCurrentlyActive: active)
    }

    func toggleTypeScope(_ type: TypeScope) {
        let active = ScopeParser.parse(queryText).typeScope == type
        toggleScope(prefix: "type", value: type.rawValue, isCurrentlyActive: active)
    }

    /// If the scope is already on the query, strip its specific token; otherwise
    /// strip any other value of the same kind and append the new one. Either
    /// way, mark the search committed and re-run it.
    private func toggleScope(prefix: String, value: String, isCurrentlyActive: Bool) {
        if isCurrentlyActive {
            queryText = removeScope(prefix: "\(prefix):\(value)", from: queryText)
        } else {
            queryText = removeScope(prefix: "\(prefix):", from: queryText)
            queryText = appendScope("\(prefix):\(value)", to: queryText)
        }
        committed = true
        executeSearch()
    }

    // MARK: - Object scope + When facets

    func setObjectScope(_ scope: ObjectScope) {
        guard scope != objectScope else { return }
        objectScope = scope
        executeSearch()
    }

    /// Apply a When range (nil = Any time / clear). `label` is the chip
    /// text ("This year", "2023", "Jan 1 – Mar 31 2024").
    func setWhen(range: DateInterval?, label: String?) {
        whenRange = range
        whenLabel = range == nil ? nil : label
        executeSearch()
    }

    func clearWhen() { setWhen(range: nil, label: nil) }

    /// The years the Memory Box actually spans, for the When presets.
    var whenYearPresets: [Int] { engine.memoryBoxYears() }

    func applyScopeFromSuggestion(_ scope: String) {
        queryText = appendScope(scope, to: queryText)
        committed = true
        executeSearch()
        recordRecent(queryText)
    }

    func selectRecent(_ raw: String) {
        queryText = raw
        committed = true
        executeSearch()
    }

    // MARK: - Recents

    func forgetAllRecents() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: recentsKey)
    }

    private func recordRecent(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var list = recentSearches.filter { $0 != trimmed }
        list.insert(trimmed, at: 0)
        if list.count > recentsMax { list = Array(list.prefix(recentsMax)) }
        recentSearches = list
        UserDefaults.standard.set(list, forKey: recentsKey)
    }

    // MARK: - Entry view tracking (Forgotten card aging)

    func touchEntry(_ entryId: UUID) {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "id == %@", entryId as CVarArg)
        request.fetchLimit = 1
        guard let entry = try? storage.viewContext.fetch(request).first else { return }
        entry.lastViewedAt = Date()
        try? storage.viewContext.save()
    }

    // MARK: - Live + committed search execution

    private func scheduleLiveSearch() {
        cancelDebounce()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await MainActor.run { self?.executeSearch() }
        }
    }

    private func cancelDebounce() {
        debounceTask?.cancel()
        debounceTask = nil
    }

    private func executeSearch() {
        var parsed = ScopeParser.parse(queryText)
        // The When facet is the effective date filter when set (it wins
        // over a `date:` token — two paths, one slot). Composes with
        // text/topic/type unchanged.
        if let whenRange { parsed.dateRange = whenRange }
        let trimmed = queryText.trimmingCharacters(in: .whitespaces)
        let hasFilters = parsed.topicSlug != nil || parsed.typeScope != nil || parsed.dateRange != nil
        guard !trimmed.isEmpty || hasFilters else {
            hits = []
            clipHits = []
            recycledHits = []
            state = .preSearch
            return
        }

        do {
            // Memories scope covers spoken words already (a memory's text
            // includes its clips' transcripts); Clips scope surfaces clips
            // directly; All runs both.
            let foundHits = objectScope == .clips ? [] : try engine.search(parsed: parsed)
            let foundClips = objectScope == .memories ? [] : try engine.searchClips(parsed: parsed)
            let foundRecycled = objectScope == .clips ? [] : ((try? engine.searchRecycled(parsed: parsed)) ?? [])
            hits = foundHits
            clipHits = foundClips
            recycledHits = foundRecycled
            topicCounts = (try? engine.topicFacetCounts(for: parsed)) ?? [:]
            typeCounts = (try? engine.typeFacetCounts(for: parsed)) ?? [:]

            if committed {
                let empty = foundHits.isEmpty && foundClips.isEmpty && foundRecycled.isEmpty
                state = empty ? .noResults : .results
            } else {
                state = .typing
            }
        } catch {
            ErrorState.shared.report(.searchFailed(error.localizedDescription))
            hits = []
            clipHits = []
            recycledHits = []
            state = .noResults
        }
    }

    // MARK: - Browse data

    private func fetchTopicsForBrowse() -> [TopicBrowseItem] {
        let request = Topic.fetchAll()
        let topics = (try? storage.viewContext.fetch(request)) ?? []
        return topics
            .map { TopicBrowseItem(id: $0.id, name: $0.name, slug: $0.slug, paletteKey: $0.paletteKey, entryCount: $0.entryCount) }
            .filter { $0.entryCount > 0 }
            .sorted { $0.entryCount > $1.entryCount }
    }

    private func fetchForgotten() -> ForgottenItem? {
        let pickIndex = forgottenIndexForToday()
        guard
            let entry = try? engine.forgottenCard(picker: { candidates in
                guard !candidates.isEmpty else { return nil }
                return candidates[pickIndex % candidates.count]
            })
        else { return nil }
        let topic = entry.topicsArray.first
        let snippet = String(entry.content.prefix(140))
        return ForgottenItem(
            id: entry.id,
            snippet: snippet,
            topicName: topic?.name,
            topicPaletteKey: topic?.paletteKey,
            createdAt: entry.createdAt
        )
    }

    private func forgottenIndexForToday() -> Int {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return abs(day)
    }

    // MARK: - Scope text manipulation

    private func appendScope(_ scope: String, to raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return scope }
        return "\(scope) \(trimmed)"
    }

    private func removeScope(prefix: String, from raw: String) -> String {
        let tokens = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        let kept = tokens.filter { !$0.lowercased().hasPrefix(prefix.lowercased()) }
        return kept.joined(separator: " ")
    }

    // MARK: - Derived helpers exposed to the view

    var parsedQuery: ParsedQuery { ScopeParser.parse(queryText) }

    var resultCountSummary: String {
        let n = hits.count
        guard n > 0 else { return "" }
        if let earliest = hits.last?.entry.createdAt {
            let months = max(1, Calendar.current.dateComponents([.month], from: earliest, to: Date()).month ?? 1)
            return "\(n) entr\(n == 1 ? "y" : "ies") · last \(months) month\(months == 1 ? "" : "s")"
        }
        return "\(n) entr\(n == 1 ? "y" : "ies")"
    }

    var fallbackTermSuggestion: String? {
        let words = queryText
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.contains(":") }
        guard words.count > 1, let last = words.last else { return nil }
        return last
    }

    var fallbackTopicSuggestion: TopicBrowseItem? {
        let lower = queryText.lowercased()
        return topicsForBrowse.first { lower.contains($0.slug) || lower.contains($0.name.lowercased()) }
    }
}

// MARK: - Flat results (Clips / All object scopes)

extension SearchViewModel {
    /// A row in the flat result list used by the Clips and All scopes.
    enum ResultItem: Identifiable {
        case memory(SearchEngine.Hit)
        case clip(SearchEngine.ClipHit)
        var id: String {
            switch self {
            case .memory(let h): return "m-\(h.id.uuidString)"
            case .clip(let c):   return "c-\(c.id.uuidString)"
            }
        }
        var relevance: Double {
            switch self {
            case .memory(let h): return h.relevance
            case .clip(let c):   return c.relevance
            }
        }
        var date: Date {
            switch self {
            case .memory(let h): return h.entry.createdAt
            case .clip(let c):   return c.ref.createdAt ?? .distantPast
            }
        }
    }

    /// Flat, interleaved results for Clips (clips only) and All (both),
    /// ordered relevance-first then recency (`Himem · Search.html`
    /// §"Ordering within a bucket").
    var flatResults: [ResultItem] {
        var items: [ResultItem] = []
        if objectScope != .memories { items += clipHits.map { .clip($0) } }
        if objectScope == .all { items += hits.map { .memory($0) } }
        return items.sorted {
            if $0.relevance != $1.relevance { return $0.relevance > $1.relevance }
            return $0.date > $1.date
        }
    }
}

// MARK: - Result grouping

extension SearchViewModel {
    enum ResultGroup: String, CaseIterable, Identifiable {
        case today, yesterday, thisWeek, thisMonth, lastMonth, earlierThisYear, older
        var id: String { rawValue }
        var label: String {
            switch self {
            case .today: return "Today"
            case .yesterday: return "Yesterday"
            case .thisWeek: return "This week"
            case .thisMonth: return "This month"
            case .lastMonth: return "Last month"
            case .earlierThisYear: return "Earlier this year"
            case .older: return "Older"
            }
        }
    }

    func groupedHits(now: Date = Date(), calendar: Calendar = .current) -> [(ResultGroup, [SearchEngine.Hit])] {
        var buckets: [ResultGroup: [SearchEngine.Hit]] = [:]
        for hit in hits {
            let group = Self.bucket(for: hit.entry.createdAt, now: now, calendar: calendar)
            buckets[group, default: []].append(hit)
        }
        return ResultGroup.allCases.compactMap { group in
            guard let list = buckets[group], !list.isEmpty else { return nil }
            return (group, list)
        }
    }

    /// Pure: classifies a date relative to `now` into a result-group bucket.
    /// Made `static` + `nonisolated` (was private) so it's testable without
    /// populating `hits` and from non-MainActor contexts.
    ///
    /// `Calendar.isDateInToday/isDateInYesterday` ignore the caller's `now`
    /// and use the system clock — wrong when tests inject a fixed `now`.
    /// We use `isDate(_:inSameDayAs:)` instead so the function is fully
    /// determined by its inputs.
    nonisolated static func bucket(for date: Date, now: Date, calendar: Calendar) -> ResultGroup {
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return .yesterday
        }
        if let week = calendar.dateInterval(of: .weekOfYear, for: now), week.contains(date) { return .thisWeek }
        if let month = calendar.dateInterval(of: .month, for: now), month.contains(date) { return .thisMonth }
        if let lastMonthDate = calendar.date(byAdding: .month, value: -1, to: now),
           let lastMonth = calendar.dateInterval(of: .month, for: lastMonthDate),
           lastMonth.contains(date) {
            return .lastMonth
        }
        if let year = calendar.dateInterval(of: .year, for: now), year.contains(date) { return .earlierThisYear }
        return .older
    }
}
