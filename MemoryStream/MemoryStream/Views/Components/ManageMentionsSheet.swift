import SwiftUI
import CoreData

/// The mentions sibling of `ManageTopicsSheet` / `ManageProjectsSheet`
/// (unified associations, B4 Phase 2). Edits which library-backed
/// `Mention`s a memory carries, with a type on each (person · place ·
/// idea · org — the per-type glyph).
///
/// Structure mirrors the topic sheet — *On this memory* (typed chips, tap
/// to remove) · *Add a new…* (name + type) · *From your library* (tap to
/// add) — plus the same delete-from-library affordance: the library Edit
/// toggle reveals a red minus per chip, with an impact confirm. Membership
/// is staged and committed on Done (Cancel discards); a new mention is the
/// one immediate write.
struct ManageMentionsSheet: View {
    let entryID: UUID
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedIds: Set<UUID> = []
    @State private var initialIds: Set<UUID> = []
    /// Snapshot of the whole mention library, taken at appear.
    @State private var library: [MentionChip] = []
    @State private var newDraft: String = ""
    /// F22 · the one fact this view reads before it claims to be empty.
    @ObservedObject private var firstImport = FirstImportState.shared
    @State private var newType: Mention.MentionType = .person
    @FocusState private var newFieldFocused: Bool
    @State private var libraryEditing = false
    @State private var pendingDelete: PendingLibraryDelete?

    private let storage = StorageService.shared

    private struct PendingLibraryDelete: Identifiable {
        let id = UUID()
        let mention: MentionChip
        let count: Int
    }

    var body: some View {
        VStack(spacing: 0) {
            grabber
            topBar
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Pick someone or somewhere you've mentioned before, or add a new one. Reusing an entry keeps people and places searchable across memories.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Crucible.Color.ink3)
                        .lineSpacing(2)
                        .padding(.top, 14)
                        .padding(.bottom, 18)

                    sectionEyebrow("On this memory")
                    onMemorySection
                        .padding(.bottom, 18)

                    addNewField
                        .padding(.bottom, 18)

                    libraryHeader
                    librarySection
                        .padding(.bottom, libraryEditing ? 12 : 24)
                    if libraryEditing {
                        libraryEditNote.padding(.bottom, 24)
                    }
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Crucible.Color.paper)
        .task { loadInitialState() }
        .alert(item: $pendingDelete) { pending in
            Alert(
                title: Text("Delete “\(pending.mention.name)”?"),
                message: Text(impactMessage(count: pending.count)),
                primaryButton: .destructive(Text("Delete from library")) {
                    performLibraryDelete(pending.mention)
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Chrome

    private var grabber: some View {
        Capsule()
            .fill(Crucible.Color.ink4.opacity(0.5))
            .frame(width: 36, height: 5)
            .padding(.top, 8).padding(.bottom, 4)
            .frame(maxWidth: .infinity)
    }

    private var topBar: some View {
        HStack {
            Button { onDismiss() } label: {
                Text("Cancel").font(.system(size: 15)).foregroundStyle(Crucible.Color.ink2)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Mentions").font(.system(size: 15, weight: .semibold)).foregroundStyle(Crucible.Color.ink)
            Spacer()
            Button { commitAndDismiss() } label: {
                Text("Done").font(.system(size: 15, weight: .bold)).foregroundStyle(Crucible.Color.accent)
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
        let selected = library.filter { selectedIds.contains($0.id) }
        // F22 EXEMPT: `selected` is this memory's own staged mention set,
        // seeded from the memory the sheet was opened on — a statement about
        // edges already in hand, not about an unfinished import.
        return Group {
            if selected.isEmpty {
                Text("No mentions on this memory yet.")
                    .font(.system(size: 12.5)).foregroundStyle(Crucible.Color.ink3)
            } else {
                FlowLayout(spacing: 10) {
                    ForEach(selected) { mention in
                        MentionManageChip(mention: mention, state: .pick) {
                            selectedIds.remove(mention.id)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var addNewField: some View {
        HStack(spacing: 9) {
            // Type picker — the per-type glyph the new mention takes.
            Menu {
                ForEach(Mention.MentionType.allCases, id: \.self) { type in
                    Button {
                        newType = type
                    } label: {
                        Label(type.label, systemImage: type.sfSymbol)
                    }
                }
            } label: {
                Image(systemName: newType.sfSymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink2)
                    .frame(width: 22)
            }
            TextField("Add a new person or place…", text: $newDraft)
                .font(.system(size: 14.5))
                .foregroundStyle(Crucible.Color.ink)
                .focused($newFieldFocused)
                .submitLabel(.done)
                .onSubmit { createAndSelect() }
            if !newDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: createAndSelect) {
                    Text("Add").font(.system(size: 13, weight: .semibold)).foregroundStyle(Crucible.Color.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 46)
        .background(Crucible.Color.card)
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Crucible.Color.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }

    private var availableLibrary: [MentionChip] {
        library.filter { !selectedIds.contains($0.id) }
    }

    private var libraryHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            sectionEyebrow("From your library")
            Spacer()
            if !availableLibrary.isEmpty {
                Button { libraryEditing.toggle() } label: {
                    Text(libraryEditing ? "Done" : "Edit")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Crucible.Color.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(libraryEditing ? "Done editing library" : "Edit library")
            }
        }
    }

    private var librarySection: some View {
        // F22: the mention library is CloudKit-synced, so "Your library is
        // empty" mid-import is the false-certainty claim. Secondary surface —
        // silent until the import has finished looking.
        Group {
            if availableLibrary.isEmpty, firstImport.mayAssertEmpty {
                Text(library.isEmpty
                     ? "Your library is empty. Add a mention above to get started."
                     : "Everything in your library is on this memory.")
                    .font(.system(size: 12.5)).foregroundStyle(Crucible.Color.ink3)
            } else {
                FlowLayout(spacing: 10) {
                    ForEach(availableLibrary) { mention in
                        Group {
                            if libraryEditing {
                                MentionManageChip(mention: mention, state: .del) {
                                    requestLibraryDelete(mention)
                                }
                            } else {
                                MentionManageChip(mention: mention, state: .off) {
                                    selectedIds.insert(mention.id)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var libraryEditNote: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle")
                .font(.system(size: 12)).foregroundStyle(Crucible.Color.ink4).padding(.top, 1)
            Text("Deleting removes the mention from your whole library — and from every memory that uses it. Removing it from just this memory? Tap it above instead.")
                .font(.system(size: 11.5)).foregroundStyle(Crucible.Color.ink3).lineSpacing(1.5)
        }
    }

    private func impactMessage(count: Int) -> String {
        let memories = count == 1 ? "1 memory" : "\(count) memories"
        return "Used in \(memories). Deleting removes this mention from all of them. The memories themselves are untouched."
    }

    // MARK: - Actions

    private func createAndSelect() {
        let trimmed = newDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let mention = try? storage.findOrCreateMention(name: trimmed, type: newType) else { return }
        let chip = MentionChip(id: mention.id, name: mention.name, type: mention.mentionType)
        if !library.contains(where: { $0.id == chip.id }) {
            library.append(chip)
            library.sort { $0.name < $1.name }
        }
        selectedIds.insert(chip.id)
        newDraft = ""
        newFieldFocused = false
    }

    private func requestLibraryDelete(_ mention: MentionChip) {
        let count = fetchMention(mention.id)?.entryCount ?? 0
        pendingDelete = PendingLibraryDelete(mention: mention, count: count)
    }

    private func performLibraryDelete(_ mention: MentionChip) {
        if let entity = fetchMention(mention.id) {
            storage.viewContext.delete(entity)
            try? storage.viewContext.save()
        }
        library.removeAll { $0.id == mention.id }
        selectedIds.remove(mention.id)
        if availableLibrary.isEmpty { libraryEditing = false }
    }

    private func commitAndDismiss() {
        let toAdd = selectedIds.subtracting(initialIds)
        let toRemove = initialIds.subtracting(selectedIds)
        if !toAdd.isEmpty || !toRemove.isEmpty {
            let ctx = storage.viewContext
            if let entry = fetchEntry() {
                for id in toAdd { if let m = fetchMention(id) { entry.addToMentions(m) } }
                for id in toRemove { if let m = fetchMention(id) { entry.removeFromMentions(m) } }
                try? ctx.save()
            }
        }
        onDismiss()
    }

    // MARK: - Fetch

    private func loadInitialState() {
        library = ((try? storage.viewContext.fetch(Mention.fetchAll())) ?? [])
            .map { MentionChip(id: $0.id, name: $0.name, type: $0.mentionType) }
        let onMemory = fetchEntry()?.mentionsArray.map(\.id) ?? []
        initialIds = Set(onMemory)
        selectedIds = Set(onMemory)
    }

    private func fetchEntry() -> JournalEntry? {
        let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        req.predicate = NSPredicate(format: "id == %@", entryID as CVarArg)
        req.fetchLimit = 1
        return try? storage.viewContext.fetch(req).first
    }

    private func fetchMention(_ id: UUID) -> Mention? {
        let req = NSFetchRequest<Mention>(entityName: "Mention")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return try? storage.viewContext.fetch(req).first
    }
}

/// A mention chip for the manage sheet — per-type glyph + name. `.pick` =
/// on this memory (tap to remove), `.off` = library (tap to add), `.del` =
/// library edit mode (red minus → delete-from-library).
private struct MentionManageChip: View {
    enum State { case pick, off, del }
    let mention: MentionChip
    let state: State
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if state == .del {
                    ZStack {
                        Circle().fill(Crucible.Color.danger).frame(width: 17, height: 17)
                        Image(systemName: "minus").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                    }
                }
                Image(systemName: mention.type.sfSymbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(state == .pick ? Crucible.Color.ink2 : Crucible.Color.ink4)
                Text(mention.name)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(state == .off ? Crucible.Color.ink3 : Crucible.Color.ink)
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
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch state {
        case .pick: return "\(mention.name), on this memory. Tap to remove."
        case .off:  return "\(mention.name). Tap to add."
        case .del:  return "Delete \(mention.name) from library."
        }
    }
}
