import SwiftUI
import CoreData

/// Inline picker for the Captured Clips "Add to existing memory" mode of
/// the bundle confirm sheet. Per `docs/design/Captured Clips · session-
/// first · spec.md` § Bundle confirm sheet · Add-to-existing-memory mode.
///
/// Filter: memories with at least one MediaReference in the last 7 days,
/// sorted by most-recent-clip descending. Per-row: Source Serif title
/// (reflective seam — same family as the AI-suggested new-memory title)
/// + SF Pro 12 sub-line with topic dot + topic name + date · clip count
/// + right-edge selection ring.
///
/// Empty 7-day window state shows the helper copy and a visible search
/// row. The search row at the bottom of the list is the documented exit
/// for older memories ("Search all memories…").
struct ExistingMemoryPickerView: View {
    @Binding var selectedEntryId: UUID?
    /// Fires when the user taps the "Search all memories…" row. The
    /// parent sheet dismisses and routes to global search. Today this
    /// just dismisses the bundle sheet — the spec calls for opening
    /// global search prefiltered to memories; threading that through
    /// the navigation stack is a follow-up.
    let onSearchTapped: () -> Void

    @State private var entries: [JournalEntry] = []

    private let storage = StorageService.shared
    private static let sevenDays: TimeInterval = 7 * 24 * 60 * 60

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if entries.isEmpty {
                    emptyState
                        .padding(.top, 24)
                        .padding(.bottom, 12)
                } else {
                    ForEach(entries, id: \.id) { entry in
                        row(entry)
                        if entry.id != entries.last?.id {
                            Rectangle()
                                .fill(Crucible.Color.hairline)
                                .frame(height: 0.5)
                                .padding(.leading, 14)
                        }
                    }
                }
                // Search row hidden for v1 — the destination ("global
                // search prefiltered to memories") isn't wired yet, so
                // showing the affordance would route the user to a
                // dismiss-only no-op. Restored once the Search route
                // lands.
            }
            .background(Crucible.Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Crucible.Color.hairline, lineWidth: 1)
            )
        }
        .onAppear { entries = fetchRecent() }
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
                    Text(rowTitle(entry))
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

    private func rowTitle(_ entry: JournalEntry) -> String {
        let t = entry.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? "Untitled memory" : t
    }

    private func rowSubline(_ entry: JournalEntry) -> some View {
        let topicName = entry.topicsArray.first?.name
        let mostRecent = mostRecentClipDate(entry)
        let dateStr: String = {
            let cal = Calendar.current
            if cal.isDateInToday(mostRecent) { return "Today" }
            if cal.isDateInYesterday(mostRecent) { return "Yesterday" }
            let f = DateFormatter(); f.dateFormat = "MMM d"
            return f.string(from: mostRecent)
        }()
        let clipCount = entry.mediaReferencesArray.filter { $0.mediaTypeEnum == .voice }.count
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

    // MARK: - Empty / search

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No recent memories")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink)
            Text("Search to find an older one.")
                .font(.system(size: 13))
                .foregroundStyle(Crucible.Color.ink3)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
    }

    private var searchRow: some View {
        Button(action: onSearchTapped) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Crucible.Color.ink3)
                Text("Search all memories…")
                    .font(.system(size: 14))
                    .foregroundStyle(Crucible.Color.ink2)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Fetch

    /// Memories with at least one MediaReference whose `createdAt` is
    /// within the last 7 days. Sorted by most-recent-clip desc. The
    /// `ANY mediaReferences.createdAt` predicate runs in Core Data; the
    /// secondary sort by max-clip-date is done in Swift because Core
    /// Data can't aggregate across a to-many relationship in a fetch
    /// sort descriptor.
    private func fetchRecent() -> [JournalEntry] {
        let cutoff = Date().addingTimeInterval(-Self.sevenDays)
        let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        req.predicate = NSPredicate(
            format: "isRecycled == NO AND ANY edges.clip.createdAt >= %@",
            cutoff as NSDate
        )
        let raw = (try? storage.viewContext.fetch(req)) ?? []
        return raw.sorted { mostRecentClipDate($0) > mostRecentClipDate($1) }
    }

    private func mostRecentClipDate(_ entry: JournalEntry) -> Date {
        entry.mediaReferencesArray
            .compactMap { $0.createdAt }
            .max() ?? entry.createdAt
    }
}
