import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @StateObject private var voiceSpeech = SpeechService()
    @FocusState private var fieldFocused: Bool
    @State private var showVoice = false
    /// A clip result tapped through — opens the unified Clip Editor
    /// (`Himem · Search.html`: "a clip result taps through to the clip").
    @State private var clipSource: ClipEditorModal.Source? = nil

    let onSelectEntry: (UUID) -> Void
    let onCaptureNewWith: (String) -> Void

    init(
        onSelectEntry: @escaping (UUID) -> Void = { _ in },
        onCaptureNewWith: @escaping (String) -> Void = { _ in }
    ) {
        self.onSelectEntry = onSelectEntry
        self.onCaptureNewWith = onCaptureNewWith
    }

    var body: some View {
        ZStack {
            Crucible.Color.paper.ignoresSafeArea()
            if showVoice {
                VoiceSearchView(
                    speechService: voiceSpeech,
                    knownTopics: viewModel.topicsForBrowse.map(\.name),
                    onCommit: { query, submit in
                        showVoice = false
                        viewModel.onQueryChanged(query)
                        if submit { viewModel.submit() }
                    },
                    onCancel: { showVoice = false }
                )
                .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    searchField
                    if viewModel.state == .results {
                        ObjectScopeWhenBar(viewModel: viewModel)
                        ScopeChipsBar(viewModel: viewModel)
                    }
                    stateBody
                }
                .transition(.opacity)
            }
        }
        .sheet(item: $clipSource) { source in
            ClipEditorModal(source: source)
        }
        .animation(.easeInOut(duration: 0.2), value: showVoice)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(showVoice ? .hidden : .visible, for: .navigationBar)
        .onAppear {
            viewModel.onAppear()
            if !showVoice { fieldFocused = true }
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: Crucible.Space.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Crucible.Color.ink3)
                .accessibilityHidden(true)
            TextField("Search the Memory Box", text: Binding(
                get: { viewModel.queryText },
                set: { viewModel.onQueryChanged($0) }
            ))
            .textFieldStyle(.plain)
            .focused($fieldFocused)
            .submitLabel(.search)
            .onSubmit { viewModel.submit() }
            .foregroundStyle(Crucible.Color.ink)
            if !viewModel.queryText.isEmpty {
                Button {
                    viewModel.clearQuery()
                    fieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Crucible.Color.ink3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            } else {
                Button {
                    fieldFocused = false
                    showVoice = true
                } label: {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(Crucible.Color.captureAudio)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Voice search")
            }
        }
        .padding(.horizontal, Crucible.Space.md)
        .padding(.vertical, 10)
        .background(Crucible.Color.sunk)
        .clipShape(RoundedRectangle(cornerRadius: Crucible.Radius.md))
        .padding(.horizontal, Crucible.Space.lg)
        .padding(.top, Crucible.Space.sm)
        .padding(.bottom, Crucible.Space.sm)
    }

    @ViewBuilder
    private var stateBody: some View {
        switch viewModel.state {
        case .preSearch:
            PreSearchBody(viewModel: viewModel,
                          onSelectEntry: openEntry,
                          onSelectTopic: { viewModel.toggleTopicScope($0); fieldFocused = false })
        case .typing:
            TypingBody(viewModel: viewModel,
                       onSelectEntry: openEntry)
        case .results:
            ResultsBody(viewModel: viewModel,
                        onSelectEntry: openEntry,
                        onSelectClip: { ref in clipSource = .managed(ref) })
        case .noResults:
            NoResultsBody(viewModel: viewModel,
                          onCapture: {
                              onCaptureNewWith(viewModel.queryText)
                          })
        }
    }

    private func openEntry(_ id: UUID) {
        viewModel.touchEntry(id)
        onSelectEntry(id)
    }
}

// MARK: - Pre-search

private struct PreSearchBody: View {
    @ObservedObject var viewModel: SearchViewModel
    let onSelectEntry: (UUID) -> Void
    let onSelectTopic: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Crucible.Space.xl) {
                if !viewModel.recentSearches.isEmpty {
                    recentsSection
                }
                if !viewModel.topicsForBrowse.isEmpty {
                    topicsSection
                }
                if let item = viewModel.forgotten {
                    forgottenSection(item: item)
                }
            }
            .padding(.horizontal, Crucible.Space.lg)
            .padding(.vertical, Crucible.Space.lg)
        }
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: Crucible.Space.sm) {
            HStack {
                SectionHeader(title: "Recent")
                Spacer()
                Button("Forget all") { viewModel.forgetAllRecents() }
                    .font(.footnote)
                    .foregroundStyle(Crucible.Color.ink3)
            }
            ForEach(viewModel.recentSearches, id: \.self) { raw in
                Button { viewModel.selectRecent(raw) } label: {
                    HStack(spacing: Crucible.Space.sm) {
                        Image(systemName: "clock")
                            .foregroundStyle(Crucible.Color.ink3)
                            .accessibilityHidden(true)
                        Text(raw)
                            .foregroundStyle(Crucible.Color.ink)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var topicsSection: some View {
        VStack(alignment: .leading, spacing: Crucible.Space.sm) {
            SectionHeader(title: "Browse by topic")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Crucible.Space.sm) {
                    ForEach(viewModel.topicsForBrowse) { item in
                        Button { onSelectTopic(item.slug) } label: {
                            TopicBrowsePill(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func forgottenSection(item: SearchViewModel.ForgottenItem) -> some View {
        Button {
            onSelectEntry(item.id)
        } label: {
            VStack(alignment: .leading, spacing: Crucible.Space.sm) {
                SectionHeader(title: "From your Memory Box")
                VStack(alignment: .leading, spacing: Crucible.Space.md) {
                    Text("\u{201C}\(item.snippet)\u{201D}")
                        .font(.system(.body, design: .serif))
                        .italic()
                        .foregroundStyle(Crucible.Color.ink)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: Crucible.Space.sm) {
                        if let topicName = item.topicName {
                            TopicPip(name: topicName, paletteKey: item.topicPaletteKey)
                        }
                        Text(item.ageLabel)
                            .font(.footnote)
                            .foregroundStyle(Crucible.Color.ink3)
                    }
                }
                .padding(Crucible.Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Crucible.Color.card)
                .clipShape(RoundedRectangle(cornerRadius: Crucible.Radius.lg))
                .modifier(Crucible.shadow1())
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Typing

private struct TypingBody: View {
    @ObservedObject var viewModel: SearchViewModel
    let onSelectEntry: (UUID) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Crucible.Space.xl) {
                if !viewModel.hits.isEmpty {
                    matchesSection
                }
                suggestionsSection
            }
            .padding(.horizontal, Crucible.Space.lg)
            .padding(.vertical, Crucible.Space.md)
        }
    }

    private var matchesSection: some View {
        VStack(alignment: .leading, spacing: Crucible.Space.sm) {
            SectionHeader(title: "In entries")
            ForEach(viewModel.hits.prefix(6).map { $0 }) { hit in
                Button { onSelectEntry(hit.id) } label: {
                    ResultRow(hit: hit, matchTerm: viewModel.parsedQuery.text)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var suggestionsSection: some View {
        FilterSuggestionsSection(viewModel: viewModel)
    }
}

// MARK: - Filter suggestions (shared)

private struct FilterSuggestion {
    let token: String
    let icon: String
    let label: String
    let count: Int
}

@MainActor
private func filterSuggestions(for viewModel: SearchViewModel) -> [FilterSuggestion] {
    var list: [FilterSuggestion] = []
    let typeCounts = viewModel.typeCounts
    let topicCounts = viewModel.topicCounts
    if viewModel.parsedQuery.topicSlug == nil {
        for item in viewModel.topicsForBrowse.prefix(3) {
            let count = topicCounts[item.slug] ?? item.entryCount
            guard count > 0 else { continue }
            list.append(FilterSuggestion(
                token: "topic:\(item.slug)",
                icon: "tag",
                label: "topic: \(item.name)",
                count: count
            ))
        }
    }
    if viewModel.parsedQuery.typeScope == nil {
        for type in TypeScope.allCases {
            let count = typeCounts[type] ?? 0
            guard count > 0 else { continue }
            list.append(FilterSuggestion(
                token: "type:\(type.rawValue)",
                icon: typeIcon(type),
                label: "type: \(typeLabel(type))",
                count: count
            ))
        }
    }
    return list
}

private struct FilterSuggestionsSection: View {
    @ObservedObject var viewModel: SearchViewModel

    var body: some View {
        let suggestions = filterSuggestions(for: viewModel)
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: Crucible.Space.sm) {
                SectionHeader(title: "Filter by")
                ForEach(suggestions, id: \.token) { suggestion in
                    Button { viewModel.applyScopeFromSuggestion(suggestion.token) } label: {
                        HStack {
                            Image(systemName: suggestion.icon)
                                .foregroundStyle(Crucible.Color.ink3)
                                .accessibilityHidden(true)
                            Text(suggestion.label)
                                .foregroundStyle(Crucible.Color.ink)
                            Spacer()
                            Text("\(suggestion.count)")
                                .font(.footnote)
                                .foregroundStyle(Crucible.Color.ink3)
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Results

private struct ResultsBody: View {
    @ObservedObject var viewModel: SearchViewModel
    let onSelectEntry: (UUID) -> Void
    let onSelectClip: (MediaReference) -> Void
    @State private var showRecycled: Bool = false

    var body: some View {
        ScrollView {
            // LazyVStack so result rows render only as they scroll into view.
            // For typical searches (few hits) this is identical; for broad
            // queries returning hundreds, it avoids materializing every row
            // and the snippet-highlight work behind it on first frame.
            LazyVStack(alignment: .leading, spacing: Crucible.Space.lg) {
                if viewModel.objectScope == .memories {
                    memoriesResults
                } else {
                    flatResults
                }
                if viewModel.objectScope != .clips && !viewModel.recycledHits.isEmpty {
                    recycledSection
                }
                FilterSuggestionsSection(viewModel: viewModel)
                    .padding(.horizontal, Crucible.Space.lg)
            }
            .padding(.vertical, Crucible.Space.md)
        }
    }

    /// Memories scope — grouped by date bucket (the reflective view).
    @ViewBuilder
    private var memoriesResults: some View {
        if !viewModel.resultCountSummary.isEmpty {
            Text(viewModel.resultCountSummary)
                .font(.footnote)
                .foregroundStyle(Crucible.Color.ink3)
                .padding(.horizontal, Crucible.Space.lg)
        }
        ForEach(viewModel.groupedHits(), id: \.0) { group, list in
            VStack(alignment: .leading, spacing: Crucible.Space.sm) {
                SectionHeader(title: group.label)
                    .padding(.horizontal, Crucible.Space.lg)
                ForEach(list) { hit in
                    Button { onSelectEntry(hit.id) } label: {
                        ResultRow(hit: hit, matchTerm: viewModel.parsedQuery.text)
                            .padding(.horizontal, Crucible.Space.lg)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Clips / All scopes — a flat list, relevance-first then recency,
    /// clips interleaved with memories (All). A clip taps through to the
    /// clip; a memory to the memory.
    @ViewBuilder
    private var flatResults: some View {
        ForEach(viewModel.flatResults) { item in
            switch item {
            case .memory(let hit):
                Button { onSelectEntry(hit.id) } label: {
                    ResultRow(hit: hit, matchTerm: viewModel.parsedQuery.text)
                        .padding(.horizontal, Crucible.Space.lg)
                }
                .buttonStyle(.plain)
            case .clip(let clipHit):
                Button { onSelectClip(clipHit.ref) } label: {
                    ClipResultRow(hit: clipHit, matchTerm: viewModel.parsedQuery.text)
                        .padding(.horizontal, Crucible.Space.lg)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var recycledSection: some View {
        VStack(alignment: .leading, spacing: Crucible.Space.sm) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { showRecycled.toggle() } } label: {
                HStack(spacing: Crucible.Space.sm) {
                    Image(systemName: "trash")
                        .font(.footnote)
                        .accessibilityHidden(true)
                    Text("Recently deleted")
                        .font(.footnote.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                    Text("\(viewModel.recycledHits.count)")
                        .font(.footnote)
                    Spacer()
                    Image(systemName: showRecycled ? "chevron.up" : "chevron.down")
                        .font(.footnote)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Crucible.Color.ink3)
                .padding(.horizontal, Crucible.Space.lg)
                .padding(.vertical, Crucible.Space.sm)
            }
            .buttonStyle(.plain)

            if showRecycled {
                ForEach(viewModel.recycledHits) { hit in
                    Button { onSelectEntry(hit.id) } label: {
                        ResultRow(hit: hit, matchTerm: viewModel.parsedQuery.text)
                            .opacity(0.6)
                            .padding(.horizontal, Crucible.Space.lg)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - No results

private struct NoResultsBody: View {
    @ObservedObject var viewModel: SearchViewModel
    let onCapture: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Crucible.Space.lg) {
                Text("Nothing in your Memory Box matches \u{201C}\(viewModel.queryText)\u{201D}.")
                    .font(.system(.title3, design: .serif))
                    .italic()
                    .foregroundStyle(Crucible.Color.ink)
                Text("Maybe it\u{2019}s not a memory yet — just a thought looking for a place to land.")
                    .font(.callout)
                    .foregroundStyle(Crucible.Color.ink2)

                Button(action: onCapture) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .accessibilityHidden(true)
                        Text("Capture \u{201C}\(viewModel.queryText)\u{201D} now")
                            .lineLimit(2)
                        Spacer()
                    }
                    .padding(Crucible.Space.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Crucible.Color.captureAudio)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Crucible.Radius.lg))
                }
                .buttonStyle(.plain)

                if let term = viewModel.fallbackTermSuggestion {
                    Button { viewModel.queryText = term; viewModel.submit() } label: {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .accessibilityHidden(true)
                            Text("Search just \u{201C}\(term)\u{201D}")
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .foregroundStyle(Crucible.Color.ink)
                    }
                    .buttonStyle(.plain)
                }
                if let topic = viewModel.fallbackTopicSuggestion {
                    Button { viewModel.toggleTopicScope(topic.slug) } label: {
                        HStack {
                            Image(systemName: "tag")
                                .accessibilityHidden(true)
                            Text("Browse \(topic.name)")
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .foregroundStyle(Crucible.Color.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Crucible.Space.lg)
            .padding(.vertical, Crucible.Space.lg)
        }
    }
}

// MARK: - Scope chip bar (results state)

private struct ScopeChipsBar: View {
    @ObservedObject var viewModel: SearchViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Crucible.Space.sm) {
                ForEach(topicChips(), id: \.slug) { chip in
                    ScopeChip(
                        label: chip.label,
                        count: chip.count,
                        isActive: chip.isActive,
                        action: { viewModel.toggleTopicScope(chip.slug) }
                    )
                }
                ForEach(typeChips(), id: \.type) { chip in
                    ScopeChip(
                        label: chip.label,
                        count: chip.count,
                        isActive: chip.isActive,
                        action: { viewModel.toggleTypeScope(chip.type) }
                    )
                }
            }
            .padding(.horizontal, Crucible.Space.lg)
        }
        .padding(.bottom, Crucible.Space.sm)
    }

    private struct TopicChipModel { let slug: String; let label: String; let count: Int; let isActive: Bool }
    private struct TypeChipModel { let type: TypeScope; let label: String; let count: Int; let isActive: Bool }

    private func topicChips() -> [TopicChipModel] {
        let active = viewModel.parsedQuery.topicSlug
        let counts = viewModel.topicCounts
        return viewModel.topicsForBrowse
            .filter { (counts[$0.slug] ?? 0) > 0 || $0.slug == active }
            .map {
                TopicChipModel(
                    slug: $0.slug,
                    label: $0.name,
                    count: counts[$0.slug] ?? 0,
                    isActive: $0.slug == active
                )
            }
            .prefix(6)
            .map { $0 }
    }

    private func typeChips() -> [TypeChipModel] {
        let active = viewModel.parsedQuery.typeScope
        return TypeScope.allCases.compactMap { type in
            let count = viewModel.typeCounts[type] ?? 0
            guard count > 0 || active == type else { return nil }
            return TypeChipModel(
                type: type,
                label: typeLabel(type),
                count: count,
                isActive: active == type
            )
        }
    }
}

// MARK: - Reusable bits

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Crucible.Color.ink3)
            .textCase(.uppercase)
            .tracking(0.6)
    }
}

private struct ScopeChip: View {
    let label: String
    let count: Int
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                if count > 0 {
                    Text("\(count)")
                        .foregroundStyle(isActive ? .white.opacity(0.8) : Crucible.Color.ink3)
                }
            }
            .font(.footnote)
            .fontWeight(isActive ? .semibold : .regular)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isActive ? Crucible.Color.ink : Color.clear)
            .foregroundStyle(isActive ? .white : Crucible.Color.ink)
            .overlay(
                Capsule().stroke(isActive ? Color.clear : Crucible.Color.divider, lineWidth: 0.5)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct TopicBrowsePill: View {
    let item: SearchViewModel.TopicBrowseItem
    var body: some View {
        let hue = item.paletteKey.map(Crucible.Color.topicHue(forKey:)) ?? Crucible.Color.topicHue(for: item.name)
        return HStack(spacing: Crucible.Space.xs) {
            Text(item.name)
            Text("\(item.entryCount)")
                .foregroundStyle(hue.fg.opacity(0.7))
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(hue.bg)
        .foregroundStyle(hue.fg)
        .clipShape(Capsule())
    }
}

private struct TopicPip: View {
    let name: String
    let paletteKey: String?
    var body: some View {
        let hue = paletteKey.map(Crucible.Color.topicHue(forKey:)) ?? Crucible.Color.topicHue(for: name)
        return HStack(spacing: 4) {
            Circle()
                .fill(hue.fg)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(name)
                .font(.caption)
                .foregroundStyle(hue.fg)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(hue.bg)
        .clipShape(Capsule())
    }
}

// Denser row per Memories list spec §2: search owns needle-finding; the
// list owns browsing. No card chrome — title, highlighted snippet, time,
// hairline divider. The match-highlight is the visual focus.
private struct ResultRow: View {
    let hit: SearchEngine.Hit
    let matchTerm: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(hit.entry.displayTitle)
                .font(.system(size: 15, weight: .medium, design: .serif))
                .tracking(-0.15)
                .foregroundStyle(Crucible.Color.ink)
                .lineLimit(1)

            snippetText
                .font(.system(size: 13))
                .foregroundStyle(Crucible.Color.ink2)
                .lineSpacing(2)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            Text(relativeLabel(for: hit.entry.createdAt))
                .font(.system(size: 11.5))
                .foregroundStyle(Crucible.Color.ink3)
                .monospacedDigit()
                .padding(.top, 1)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Crucible.Color.divider)
                .frame(height: 0.5)
        }
    }

    private var snippetText: Text {
        if let snippet = hit.snippet {
            return Text(highlight(snippet.text, term: snippet.matchTerm))
        }
        if !matchTerm.isEmpty {
            return Text(highlight(String(hit.entry.content.prefix(140)), term: matchTerm))
        }
        return Text(String(hit.entry.content.prefix(140)))
    }
}

// MARK: - Object scope + When facets (Himem · Search.html)

private struct ObjectScopeWhenBar: View {
    @ObservedObject var viewModel: SearchViewModel
    @State private var showWhen = false

    var body: some View {
        HStack(spacing: Crucible.Space.sm) {
            // Object scope — Memories · Clips · All (default Memories).
            HStack(spacing: 2) {
                ForEach(ObjectScope.allCases, id: \.self) { scope in
                    let active = viewModel.objectScope == scope
                    Button { viewModel.setObjectScope(scope) } label: {
                        Text(scope.label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(active ? .white : Crucible.Color.ink2)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(active ? Crucible.Color.accent : Color.clear)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Crucible.Color.sunk)
            .clipShape(Capsule())

            Spacer(minLength: 0)

            whenChip
        }
        .padding(.horizontal, Crucible.Space.lg)
        .padding(.bottom, Crucible.Space.sm)
    }

    private var whenChip: some View {
        let active = viewModel.whenRange != nil
        return HStack(spacing: 0) {
            Button { showWhen = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .semibold))
                    Text(viewModel.whenLabel.map { "When: \($0)" } ?? "When")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(active ? .white : Crucible.Color.ink2)
                .padding(.leading, 12)
                .padding(.trailing, active ? 6 : 12)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showWhen) {
                WhenPopover(viewModel: viewModel, isPresented: $showWhen)
                    .presentationCompactAdaptation(.popover)
            }
            if active {
                Button { viewModel.clearWhen() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.trailing, 9)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear date range")
            }
        }
        .background(active ? Crucible.Color.accent : Crucible.Color.sunk)
        .clipShape(Capsule())
    }
}

private struct WhenPopover: View {
    @ObservedObject var viewModel: SearchViewModel
    @Binding var isPresented: Bool

    @State private var showCustom = false
    @State private var customFrom = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
    @State private var customTo = Date()

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                presetRow("Any time", range: nil)
                presetRow("This year", range: Self.yearInterval(currentYear))
                presetRow("Last year", range: Self.yearInterval(currentYear - 1))
                // Individual years from the Memory Box span, older than
                // "Last year" (which has its own preset).
                ForEach(viewModel.whenYearPresets.filter { $0 <= currentYear - 2 }, id: \.self) { year in
                    presetRow(String(year), range: Self.yearInterval(year))
                }

                Divider().padding(.vertical, 6)

                DisclosureGroup(isExpanded: $showCustom) {
                    VStack(alignment: .leading, spacing: 8) {
                        DatePicker("From", selection: $customFrom, displayedComponents: .date)
                        DatePicker("To", selection: $customTo, displayedComponents: .date)
                        Button { applyCustom() } label: {
                            Text("Apply range")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Crucible.Color.accent)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Crucible.Color.accent, lineWidth: 1))
                                // F17 · the pill is stroked, not filled — without this the tap
                                // region is only the drawn text. Guarded by ButtonHitRegionTests.
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.system(size: 13))
                    .padding(.top, 6)
                } label: {
                    Text("Custom range")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Crucible.Color.ink)
                }
                .tint(Crucible.Color.ink2)
            }
            .padding(16)
        }
        .frame(width: 280)
        .frame(maxHeight: 420)
    }

    private func presetRow(_ label: String, range: DateInterval?) -> some View {
        let isActive = (range == nil && viewModel.whenRange == nil)
            || (range != nil && viewModel.whenRange == range)
        return Button {
            viewModel.setWhen(range: range, label: range == nil ? nil : label)
            isPresented = false
        } label: {
            HStack {
                Text(label)
                    .font(.system(size: 15))
                    .foregroundStyle(Crucible.Color.ink)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Crucible.Color.accent)
                }
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func applyCustom() {
        let cal = Calendar.current
        let lo = min(customFrom, customTo)
        let hi = max(customFrom, customTo)
        let start = cal.startOfDay(for: lo)
        // Inclusive of the "to" day → end is the start of the following day.
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: hi)) ?? hi
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"
        let label = "\(f.string(from: lo)) – \(f.string(from: hi))"
        viewModel.setWhen(range: DateInterval(start: start, end: end), label: label)
        isPresented = false
    }

    static func yearInterval(_ year: Int) -> DateInterval {
        var comps = DateComponents(); comps.year = year; comps.month = 1; comps.day = 1
        let cal = Calendar.current
        let start = cal.date(from: comps) ?? Date()
        let end = cal.date(byAdding: .year, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }
}

// MARK: - Clip result row (Clips / All scopes)

private struct ClipResultRow: View {
    let hit: SearchEngine.ClipHit
    let matchTerm: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: clipGlyph)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink3)
                Text(clipKind)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink)
                Text("·")
                    .foregroundStyle(Crucible.Color.ink4)
                Text(hit.status)
                    .font(.system(size: 12))
                    .foregroundStyle(hit.ref.referencingMemoryCount == 0 ? Crucible.Color.warn : Crucible.Color.ink3)
            }

            snippetText
                .font(.system(size: 13))
                .foregroundStyle(Crucible.Color.ink2)
                .lineSpacing(2)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            Text(relativeLabel(for: hit.ref.createdAt ?? .distantPast))
                .font(.system(size: 11.5))
                .foregroundStyle(Crucible.Color.ink3)
                .monospacedDigit()
                .padding(.top, 1)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Crucible.Color.divider).frame(height: 0.5)
        }
    }

    private var clipGlyph: String {
        switch hit.ref.mediaTypeEnum {
        case .voice: return "waveform"
        case .note:  return "text.alignleft"
        case .image: return "photo"
        case .video: return "video"
        }
    }

    private var clipKind: String {
        switch hit.ref.mediaTypeEnum {
        case .voice: return "Voice clip"
        case .note:  return "Note"
        case .image: return "Photo"
        case .video: return "Video"
        }
    }

    private var snippetText: Text {
        if let snippet = hit.snippet {
            return Text(highlight(snippet.text, term: snippet.matchTerm))
        }
        let body = hit.ref.transcript ?? hit.ref.text ?? hit.ref.mediaDescription ?? ""
        if !matchTerm.isEmpty {
            return Text(highlight(String(body.prefix(140)), term: matchTerm))
        }
        return Text(String(body.prefix(140)))
    }
}

private func relativeLabel(for date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
}

private func typeLabel(_ type: TypeScope) -> String {
    switch type {
    case .voice: return "Voice"
    case .text: return "Text"
    case .photo: return "Photos"
    case .video: return "Videos"
    }
}

private func typeIcon(_ type: TypeScope) -> String {
    switch type {
    case .voice: return "waveform"
    case .text: return "text.alignleft"
    case .photo: return "photo"
    case .video: return "video"
    }
}

// MARK: - Highlighted text

/// Highlights every case-insensitive occurrence of `term` in `text` with
/// the spec's match style: accent-tint background + accent-pressed
/// foreground + semibold. Replaces the legacy yellow wash per Memories
/// list spec §2 SearchRow.
private func highlight(_ text: String, term: String) -> AttributedString {
    var attributed = AttributedString(text)
    let lowerTerm = term.lowercased()
    guard !lowerTerm.isEmpty else { return attributed }

    let lowerText = text.lowercased()
    var searchStart = lowerText.startIndex
    while let range = lowerText.range(of: lowerTerm, range: searchStart..<lowerText.endIndex) {
        let nsRange = NSRange(range, in: text)
        if let attrRange = Range(nsRange, in: attributed) {
            attributed[attrRange].backgroundColor = Crucible.Color.accentTint
            attributed[attrRange].foregroundColor = Crucible.Color.accentPressed
            attributed[attrRange].font = .system(size: 13, weight: .semibold)
        }
        searchStart = range.upperBound
    }
    return attributed
}

#Preview {
    SearchView()
}
