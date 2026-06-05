import SwiftUI
import CoreData

/// Picker sheet for adding (or removing) memories to a project. Shown from
/// ProjectDetailView's `+` toolbar button.
///
/// Layout: search field on top, a "Filter to project topics" toggle, then a
/// scrollable list of every memory. Memories already in the project render
/// with a checkmark; tapping a row toggles membership immediately (no
/// separate Save step). Done dismisses.
///
/// Defaults: when the project has any topics already, the topic filter is
/// on by default — most projects organize around one topic, so the "fast
/// path" is to surface only memories tagged with one of those topics. The
/// user can flip the toggle off to see everything.
struct AddMemoryToProjectSheet: View {
    let projectId: UUID
    @ObservedObject var projectVM: ProjectViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var filterToProjectTopics: Bool = true
    @State private var entries: [EntryDisplayModel] = []
    /// Membership at the moment the sheet opened. Read-only after load.
    @State private var initialMemberIds: Set<UUID> = []
    /// Toggles staged in this sheet session. `Done` applies them; `Cancel`
    /// drops them.
    @State private var pendingAdds: Set<UUID> = []
    @State private var pendingRemoves: Set<UUID> = []
    @State private var projectTopicSlugs: Set<String> = []

    private let storage = StorageService.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                if !projectTopicSlugs.isEmpty {
                    topicFilterToggle
                }
                Divider()
                memoryList
            }
            .background(Crucible.Color.paper)
            .navigationTitle("Add memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Crucible.Color.ink2)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        commitPendingChanges()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Crucible.Color.accent)
                    .disabled(pendingAdds.isEmpty && pendingRemoves.isEmpty)
                }
            }
        }
        .onAppear { loadData() }
    }

    // MARK: - Subviews

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(Crucible.Color.ink3)
            TextField("Search memories", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Crucible.Color.ink4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Crucible.Color.sunk)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var topicFilterToggle: some View {
        HStack {
            Toggle(isOn: $filterToProjectTopics) {
                Text("Filter to project topics")
                    .font(.subheadline)
                    .foregroundStyle(Crucible.Color.ink2)
            }
            .tint(Crucible.Color.accent)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var memoryList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if filteredEntries.isEmpty {
                    emptyState
                } else {
                    ForEach(filteredEntries) { entry in
                        memoryRow(entry: entry)
                    }
                }
            }
        }
    }

    // Concise selection row per Memories list spec §2. Selection = ring
    // with an inner dot (NOT a check — completion vs selection per
    // Crucible). Serif title, time line, media glyphs on the right.
    private func memoryRow(entry: EntryDisplayModel) -> some View {
        let isMember = effectiveMembership(for: entry.id)
        return Button {
            toggleMembership(entry: entry)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                selectionRing(selected: isMember)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayTitle)
                        .font(.system(size: 14.5, weight: .medium, design: .serif))
                        .tracking(-0.15)
                        .foregroundStyle(Crucible.Color.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(entry.timeString)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Crucible.Color.ink3)
                        .monospacedDigit()
                }

                Spacer(minLength: 8)

                if !entry.mediaItems.isEmpty {
                    MediaGlyphRow(mediaItems: entry.mediaItems)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Crucible.Color.divider)
                    .frame(height: 0.5)
                    .padding(.leading, 16)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func selectionRing(selected: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(
                    selected ? Crucible.Color.accent : Crucible.Color.ink4,
                    lineWidth: 2
                )
                .background(
                    Circle()
                        .fill(selected ? Crucible.Color.accent : Color.clear)
                )
                .frame(width: 20, height: 20)
            if selected {
                Circle()
                    .fill(Crucible.Color.accentInk)
                    .frame(width: 7, height: 7)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(Crucible.Color.ink4)
                .accessibilityHidden(true)
            Text(emptyStateText)
                .font(.subheadline)
                .foregroundStyle(Crucible.Color.ink3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 24)
    }

    private var emptyStateText: String {
        if !searchText.isEmpty {
            return "No memories match \"\(searchText)\"."
        }
        if filterToProjectTopics, !projectTopicSlugs.isEmpty {
            return "No memories with this project's topics. Turn off the filter to see all memories."
        }
        return "No memories yet."
    }

    // MARK: - Filtering

    private var filteredEntries: [EntryDisplayModel] {
        var list = entries
        if filterToProjectTopics, !projectTopicSlugs.isEmpty {
            list = list.filter { entry in
                let slugs = entry.topicNames.map { TopicSlugHelper.slugify($0) }
                return slugs.contains { projectTopicSlugs.contains($0) }
            }
        }
        if !searchText.isEmpty {
            let needle = searchText.lowercased()
            list = list.filter { entry in
                entry.displayTitle.lowercased().contains(needle)
                    || entry.content.lowercased().contains(needle)
            }
        }
        return list
    }

    // MARK: - Membership (staged)

    /// True if the entry would be in the project after applying pending
    /// changes. Read by row rendering.
    private func effectiveMembership(for entryId: UUID) -> Bool {
        if pendingAdds.contains(entryId) { return true }
        if pendingRemoves.contains(entryId) { return false }
        return initialMemberIds.contains(entryId)
    }

    /// Stages a toggle. Symmetric handling so re-tapping reverts: if the
    /// entry was originally a member, an "add" cancels a pending remove
    /// rather than stacking up. Same in reverse.
    private func toggleMembership(entry: EntryDisplayModel) {
        let id = entry.id
        let wasMember = initialMemberIds.contains(id)
        let isEffectivelyMember = effectiveMembership(for: id)
        if isEffectivelyMember {
            // Stage a remove.
            if wasMember {
                pendingRemoves.insert(id)
            } else {
                // Was a pending add — un-stage.
                pendingAdds.remove(id)
            }
        } else {
            // Stage an add.
            if wasMember {
                // Was a pending remove — un-stage.
                pendingRemoves.remove(id)
            } else {
                pendingAdds.insert(id)
            }
        }
    }

    /// Applies all staged toggles via the project view model. Called by Done.
    private func commitPendingChanges() {
        for id in pendingAdds {
            projectVM.addMemory(entryId: id, toProjectId: projectId)
        }
        for id in pendingRemoves {
            projectVM.removeMemory(entryId: id, fromProjectId: projectId)
        }
    }

    // MARK: - Data load

    private func loadData() {
        // All non-recycled entries for the picker.
        let request = JournalEntry.fetchAllChronological(limit: 500)
        if let journal = try? storage.viewContext.fetch(request) {
            entries = journal.map(EntryMapper.mapToDisplayModel)
        }

        // Current project — its members + topic slugs for filtering.
        let projReq = NSFetchRequest<Project>(entityName: "Project")
        projReq.predicate = NSPredicate(format: "id == %@", projectId as CVarArg)
        projReq.fetchLimit = 1
        if let project = try? storage.viewContext.fetch(projReq).first {
            initialMemberIds = Set(project.entriesArray.map(\.id))
            projectTopicSlugs = Set(project.topicNames.map { TopicSlugHelper.slugify($0) })
        }
        // If the project has no topics yet (empty project), default the
        // filter off — there's nothing to filter against.
        if projectTopicSlugs.isEmpty {
            filterToProjectTopics = false
        }
    }
}
