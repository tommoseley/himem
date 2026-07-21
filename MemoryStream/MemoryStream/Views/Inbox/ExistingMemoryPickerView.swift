import SwiftUI
import CoreData

/// Inline picker for the "Add to a memory" flows — the clip Edit sheet's
/// placement (`PlaceClipSheet`) and the Captured Clips bundle-confirm
/// "Add to existing memory" mode (`CreateMemoryFromClipsSheet`).
///
/// Shows **every** non-recycled memory, most-recent first, with an inline
/// **search field** (title or date). A library of 30–40 memories needs
/// filtering, and the picker must be able to reach *any* memory — the
/// earlier build listed only memories with a clip in the last 7 days and
/// disabled the "Search all" escape, so older memories were unreachable
/// (device bug, 2026-07-21).
///
/// Per-row: Source Serif title (reflective seam) + SF Pro sub-line with
/// topic dot + topic name + date · clip count + right-edge selection ring.
struct ExistingMemoryPickerView: View {
    @Binding var selectedEntryId: UUID?

    @State private var allEntries: [JournalEntry] = []
    @State private var searchText: String = ""

    private let storage = StorageService.shared

    private var visibleEntries: [JournalEntry] {
        Self.filter(allEntries, query: searchText)
    }

    var body: some View {
        VStack(spacing: 10) {
            searchField
            ScrollView {
                VStack(spacing: 0) {
                    if allEntries.isEmpty {
                        emptyState(title: "No memories yet",
                                   detail: "Memories you create will show up here.")
                            .padding(.vertical, 28)
                    } else if visibleEntries.isEmpty {
                        emptyState(title: "No matches",
                                   detail: "No memory matches “\(searchText)”.")
                            .padding(.vertical, 28)
                    } else {
                        ForEach(visibleEntries, id: \.id) { entry in
                            row(entry)
                            if entry.id != visibleEntries.last?.id {
                                Rectangle()
                                    .fill(Crucible.Color.hairline)
                                    .frame(height: 0.5)
                                    .padding(.leading, 14)
                            }
                        }
                    }
                }
                .background(Crucible.Color.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Crucible.Color.hairline, lineWidth: 1)
                )
            }
        }
        .onAppear { allEntries = Self.fetchAllMemories(in: storage.viewContext) }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Crucible.Color.ink3)
            TextField("Search memories by title or date", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Crucible.Color.ink4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
    }

    // MARK: - Row

    @ViewBuilder
    private func row(_ entry: JournalEntry) -> some View {
        let isSelected = selectedEntryId == entry.id
        Button {
            // Single-select: tapping the current row deselects it; the
            // commit button in the parent sheet stays disabled until a
            // row is picked.
            selectedEntryId = isSelected ? nil : entry.id
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.rowTitle(entry))
                        .font(.system(size: 17, design: .serif))
                        .foregroundStyle(Crucible.Color.ink)
                        .lineLimit(1)
                    rowSubline(entry)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ring(isSelected: isSelected)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowSubline(_ entry: JournalEntry) -> some View {
        let topicName = entry.topicsArray.first?.name
        let mostRecent = Self.mostRecentClipDate(entry)
        let dateStr = Self.shortDateString(mostRecent)
        // Count all clips (any media type), not just voice — a photo-only
        // memory should not read "0 clips".
        let clipCount = entry.mediaReferencesArray.count
        let clipStr = clipCount == 1 ? "1 clip" : "\(clipCount) clips"
        return HStack(spacing: 6) {
            if topicName != nil {
                Circle()
                    .fill(Crucible.Color.ink3)
                    .frame(width: 6, height: 6)
            }
            if let topicName {
                Text(topicName)
                Text("·")
                    .foregroundStyle(Crucible.Color.ink4)
            }
            Text(dateStr)
            Text("·")
                .foregroundStyle(Crucible.Color.ink4)
            Text(clipStr)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Crucible.Color.ink2)
    }

    /// Selection ring — same Crucible convention as the clip rows on
    /// `SessionListView`: empty ring on rest, ochre fill + paper-color
    /// inner dot on select. Never a check glyph; that's a completion
    /// state, not a selection state.
    private func ring(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(
                    isSelected ? Crucible.Color.accent : Crucible.Color.ink4,
                    lineWidth: 1.5
                )
                .background(Circle().fill(isSelected ? Crucible.Color.accent : Color.clear))
                .frame(width: 20, height: 20)
            if isSelected {
                Circle()
                    .fill(Crucible.Color.accentInk)
                    .frame(width: 8, height: 8)
            }
        }
    }

    private func emptyState(title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(Crucible.Color.ink3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
    }

    // MARK: - Fetch / filter / format (testable statics)

    /// Every non-recycled memory, sorted by most-recent-clip descending.
    /// The secondary sort is done in Swift because Core Data can't
    /// aggregate across a to-many relationship in a fetch sort descriptor.
    /// (Was a 7-day `ANY edges.clip.createdAt` window — the cause of the
    /// "only ~3 memories" bug.)
    static func fetchAllMemories(in ctx: NSManagedObjectContext) -> [JournalEntry] {
        let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        // `!= YES` (not `== NO`) so CloudKit-synced records that stored the
        // flag as nil still appear — the same nil-safe form the main
        // Memories fetch uses (`JournalEntry` recycled predicate).
        req.predicate = NSPredicate(format: "isRecycled != YES")
        let raw = (try? ctx.fetch(req)) ?? []
        return raw.sorted { mostRecentClipDate($0) > mostRecentClipDate($1) }
    }

    /// Case-insensitive filter over title + a date haystack (so "jul",
    /// "18", "2026", "today" all match). Empty query → everything.
    static func filter(_ entries: [JournalEntry], query: String) -> [JournalEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return entries }
        return entries.filter { searchHaystack(for: $0).contains(q) }
    }

    /// Lowercased title + several date renderings of the most-recent clip,
    /// so a query can match either the words or the date.
    static func searchHaystack(for entry: JournalEntry) -> String {
        let date = mostRecentClipDate(entry)
        let cal = Calendar.current
        var parts: [String] = [rowTitle(entry)]
        if cal.isDateInToday(date) { parts.append("today") }
        if cal.isDateInYesterday(date) { parts.append("yesterday") }
        let fmts = ["MMM d", "MMMM d", "MMM d yyyy", "MMMM d, yyyy", "M/d/yy", "yyyy", "EEEE"]
        let df = DateFormatter()
        for f in fmts {
            df.dateFormat = f
            parts.append(df.string(from: date))
        }
        return parts.joined(separator: " ").lowercased()
    }

    static func rowTitle(_ entry: JournalEntry) -> String {
        let t = entry.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? "Untitled memory" : t
    }

    static func shortDateString(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    static func mostRecentClipDate(_ entry: JournalEntry) -> Date {
        entry.mediaReferencesArray
            .compactMap { $0.createdAt }
            .max() ?? entry.createdAt
    }
}
