import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @StateObject private var voiceSpeech = SpeechService()
    @FocusState private var fieldFocused: Bool
    @State private var showVoice = false

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
                        ScopeChipsBar(viewModel: viewModel)
                    }
                    stateBody
                }
                .transition(.opacity)
            }
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
                        onSelectEntry: openEntry)
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
    @State private var showRecycled: Bool = false

    var body: some View {
        ScrollView {
            // LazyVStack so result rows render only as they scroll into view.
            // For typical searches (few hits) this is identical; for broad
            // queries returning hundreds, it avoids materializing every row
            // and the snippet-highlight work behind it on first frame.
            LazyVStack(alignment: .leading, spacing: Crucible.Space.lg) {
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
                if !viewModel.recycledHits.isEmpty {
                    recycledSection
                }
                FilterSuggestionsSection(viewModel: viewModel)
                    .padding(.horizontal, Crucible.Space.lg)
            }
            .padding(.vertical, Crucible.Space.md)
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
