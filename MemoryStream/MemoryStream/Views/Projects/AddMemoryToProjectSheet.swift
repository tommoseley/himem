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

// MARK: - Manage Projects (memory → projects)

/// The projects sibling of `ManageTopicsSheet` (unified associations
/// model, 2026-07-17). Where `AddMemoryToProjectSheet` pivots
/// project → memories, this pivots **memory → projects**: it edits which
/// projects a single memory belongs to. Reached from the dashed **Edit**
/// on the memory's Projects read section.
///
/// Structure mirrors `ManageTopicsSheet` — *On this memory* (folder
/// chips, tap to remove) · *New project…* (create + add, cap-gated) ·
/// *From your library* (tap to add). Projects have **no** delete-from-
/// library red minus — a project is deleted from its own full-width
/// Delete Project button, never here.
///
/// Membership is staged and committed on **Done** (Cancel discards),
/// matching the app's other membership editors. A *New project* is the
/// one immediate write — creating a container is a deliberate act, like
/// the "+ New project" row, so it persists even on Cancel; only the
/// membership staging is discarded.
struct ManageProjectsSheet: View {
    let entryID: UUID
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var projectVM = ProjectViewModel()
    @ObservedObject private var entitlement = Entitlement.shared

    /// Staged membership — project ids this memory belongs to. Committed
    /// as an add/remove diff on Done.
    @State private var selectedProjectIds: Set<UUID> = []
    /// Membership at open, for the commit diff.
    @State private var initialProjectIds: Set<UUID> = []
    @State private var newProjectDraft: String = ""
    @FocusState private var newFieldFocused: Bool
    /// True after a create was blocked by the Free 3-project cap.
    @State private var atCap = false

    private let storage = StorageService.shared

    var body: some View {
        VStack(spacing: 0) {
            grabber
            topBar
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Add this memory to a project, or start a new one. A project connects memories toward something you're building.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Crucible.Color.ink3)
                        .lineSpacing(2)
                        .padding(.top, 14)
                        .padding(.bottom, 18)

                    sectionEyebrow("On this memory")
                    onMemorySection
                        .padding(.bottom, 18)

                    newProjectField
                        .padding(.bottom, 18)

                    sectionEyebrow("From your library")
                    librarySection
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Crucible.Color.paper)
        .task { loadInitialState() }
    }

    // MARK: - Chrome

    private var grabber: some View {
        Capsule()
            .fill(Crucible.Color.ink4.opacity(0.5))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity)
    }

    private var topBar: some View {
        HStack {
            Button { onDismiss() } label: {
                Text("Cancel")
                    .font(.system(size: 15))
                    .foregroundStyle(Crucible.Color.ink2)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Projects")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink)
            Spacer()
            Button { commitAndDismiss() } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Crucible.Color.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionEyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(1.3)
            .foregroundStyle(Crucible.Color.ink3)
            .padding(.bottom, 8)
    }

    // MARK: - Sections

    private var onMemorySection: some View {
        let selected = projectVM.projects.filter { selectedProjectIds.contains($0.id) }
        return Group {
            if selected.isEmpty {
                Text("Not in any project yet.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Crucible.Color.ink3)
            } else {
                FlowLayout(spacing: 10) {
                    ForEach(selected) { project in
                        ProjectManageChip(name: project.name, state: .pick) {
                            selectedProjectIds.remove(project.id)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var newProjectField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink3)
                TextField("New project…", text: $newProjectDraft)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Crucible.Color.ink)
                    .focused($newFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { createAndAdd() }
                if !newProjectDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: createAndAdd) {
                        Text("Add")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Crucible.Color.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 46)
            .background(Crucible.Color.card)
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Crucible.Color.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 11))
            if atCap {
                Text("You've reached 3 projects. Plus is unlimited.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Crucible.Color.ink3)
                    .padding(.leading, 4)
            }
        }
    }

    private var librarySection: some View {
        let available = projectVM.projects.filter { !selectedProjectIds.contains($0.id) }
        return Group {
            if available.isEmpty {
                Text(projectVM.projects.isEmpty
                     ? "No projects yet. Start one above."
                     : "This memory is in all your projects.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Crucible.Color.ink3)
            } else {
                FlowLayout(spacing: 10) {
                    ForEach(available) { project in
                        ProjectManageChip(name: project.name, state: .off) {
                            selectedProjectIds.insert(project.id)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Actions

    private func createAndAdd() {
        let trimmed = newProjectDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard ProjectCapPolicy.canCreate(isPlus: entitlement.isPlus, currentCount: projectVM.projects.count) else {
            atCap = true
            return
        }
        do {
            let project = try storage.createProject(name: trimmed, purpose: nil)
            projectVM.loadProjects()
            selectedProjectIds.insert(project.id)
            newProjectDraft = ""
            newFieldFocused = false
        } catch {
            ErrorState.shared.report(.projectError(error.localizedDescription))
        }
    }

    private func commitAndDismiss() {
        let toAdd = selectedProjectIds.subtracting(initialProjectIds)
        let toRemove = initialProjectIds.subtracting(selectedProjectIds)
        for pid in toAdd { projectVM.addMemory(entryId: entryID, toProjectId: pid) }
        for pid in toRemove { projectVM.removeMemory(entryId: entryID, fromProjectId: pid) }
        onDismiss()
    }

    private func loadInitialState() {
        projectVM.loadProjects()
        let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        req.predicate = NSPredicate(format: "id == %@", entryID as CVarArg)
        req.fetchLimit = 1
        let ids = ((try? storage.viewContext.fetch(req).first)?.projectsArray ?? []).map(\.id)
        initialProjectIds = Set(ids)
        selectedProjectIds = Set(ids)
    }
}

/// A project chip for the manage sheet — folder glyph + name (the
/// unified glyph rule: dot = topic, folder = project). `.pick` = on this
/// memory (tap to remove, selection ring); `.off` = in the library (tap
/// to add, hairline).
private struct ProjectManageChip: View {
    enum State { case pick, off }
    let name: String
    let state: State
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(state == .pick ? Crucible.Color.ink2 : Crucible.Color.ink4)
                Text(name)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(state == .pick ? Crucible.Color.ink : Crucible.Color.ink3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(minHeight: 44)
            .background(state == .pick ? Crucible.Color.wash1 : .clear)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        state == .pick ? Crucible.Color.accent : Crucible.Color.hairline,
                        lineWidth: state == .pick ? 1.5 : 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state == .pick ? "\(name), in this project. Tap to remove." : "\(name). Tap to add.")
    }
}
