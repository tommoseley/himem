import SwiftUI
import CoreData

/// Placement sheet for a `MediaReference` — the answer to "Where does
/// this belong?" per `docs/design/Kingfisher Language.md` §Vocabulary
/// and `docs/design/HiMem · evidence and context.md` §"Where does this
/// belong?".
///
/// Two contexts:
///
/// - **From Clip Detail** (unplaced or placed clip; `sourceMemoryId`
///   is nil). The user places the clip into a memory. Two destinations
///   offered: **Into a new memory** or **Add to an existing memory**.
/// - **From Memory Detail edit state** (`sourceMemoryId` is the current
///   memory). The user is relocating a placed clip. Three destinations
///   offered: **Move to another memory**, **Into a new memory**, or
///   **Remove from this memory** (drops just this edge; clip returns
///   to the Clips bench as unplaced evidence if it was the last one).
///
/// The three-option shape is locked in
/// `Memory Detail · unified editing model.md:66` (July 5 2026):
/// *"the sheet titled 'Where does this belong?' … covers every case."*
struct PlaceClipSheet: View {
    let ref: MediaReference
    /// When non-nil, the sheet is a *relocation* from this memory (the
    /// memory currently referencing the clip). Enables the "Remove
    /// from this memory" option and drops the source edge on the
    /// "Move to another" and "Into a new" flows so the clip really
    /// moves, not just gets copied.
    var sourceMemoryId: UUID? = nil
    /// Optional caller-provided completion — fires after any placement
    /// action commits. Callers use this to regenerate memory content,
    /// refresh UI, etc.
    var onPlaced: (() -> Void)? = nil

    enum Destination: Hashable {
        case existingMemory
        case newMemory
        case removeFromThisMemory
    }

    @Environment(\.dismiss) private var dismiss
    @State private var destination: Destination
    @State private var selectedEntryId: UUID? = nil
    @State private var newMemoryTitle: String = ""
    private let storage = StorageService.shared

    init(ref: MediaReference, sourceMemoryId: UUID? = nil, onPlaced: (() -> Void)? = nil) {
        self.ref = ref
        self.sourceMemoryId = sourceMemoryId
        self.onPlaced = onPlaced
        // Default to the existing-memory picker — it's the highest-value
        // destination for both flows.
        self._destination = State(initialValue: .existingMemory)
    }

    var body: some View {
        NavigationStack {
            // NOT wrapped in a ScrollView: the existing-memory picker owns
            // its own scroll (search field + scrollable list), and nesting
            // it inside an outer ScrollView collapsed its height to a few
            // rows (device bug, 2026-07-21). The short new/remove bodies
            // get a trailing Spacer instead.
            VStack(alignment: .leading, spacing: 16) {
                destinationPicker
                Group {
                    switch destination {
                    case .existingMemory:
                        existingMemoryBody
                    case .newMemory:
                        newMemoryBody
                    case .removeFromThisMemory:
                        removeBody
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if destination != .existingMemory {
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(Crucible.Color.paper)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Crucible.Color.ink2)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(commitLabel) { commit() }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Crucible.Color.accent)
                        .disabled(!canCommit)
                }
            }
        }
        // Default to full height: the "Add to a memory" picker is a
        // searchable all-memories list; at 40+ memories it needs the room
        // without a drag. `.large` first = the opening detent.
        .presentationDetents([.large, .fraction(0.68)])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var title: String {
        // "Placement stops being terminal, which is exactly the point"
        // — HiMem · evidence and context.md. Already-placed clips ask
        // "where else."
        ref.referencingMemoryCount > 0
            ? "Where else does this belong?"
            : "Where does this belong?"
    }

    private var commitLabel: String {
        switch destination {
        case .existingMemory:        return "Add"
        case .newMemory:             return "Create"
        case .removeFromThisMemory:  return "Remove"
        }
    }

    private var canCommit: Bool {
        switch destination {
        case .existingMemory:        return selectedEntryId != nil
        case .newMemory:             return true  // title optional; a blank memory is legal
        case .removeFromThisMemory:  return sourceMemoryId != nil
        }
    }

    // MARK: - Destination picker

    /// Segmented control (or two-tab if `sourceMemoryId` is nil) picking
    /// which destination kind the user is placing into.
    @ViewBuilder
    private var destinationPicker: some View {
        Picker("Destination", selection: $destination) {
            Text(sourceMemoryId != nil ? "Move to existing" : "Existing memory")
                .tag(Destination.existingMemory)
            Text("New memory").tag(Destination.newMemory)
            if sourceMemoryId != nil {
                Text("Remove").tag(Destination.removeFromThisMemory)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Bodies

    private var existingMemoryBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            ExistingMemoryPickerView(selectedEntryId: $selectedEntryId)
            if sourceMemoryId != nil {
                Text("Moves the clip out of this memory into the one you pick.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Crucible.Color.ink3)
            }
        }
    }

    private var newMemoryBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Title (optional)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Crucible.Color.ink3)
            TextField("Untitled memory", text: $newMemoryTitle)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Crucible.Color.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Crucible.Color.hairline, lineWidth: 1)
                )
            Text(sourceMemoryId != nil
                 ? "Creates a new memory with this clip and removes it from this one. You can add more later."
                 : "Creates a new memory with this clip. You can add more later.")
                .font(.system(size: 11.5))
                .foregroundStyle(Crucible.Color.ink3)
                .lineSpacing(2)
        }
    }

    private var removeBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Removes the clip from this memory. The clip itself stays in your library — if this was the only memory holding it, it returns to Clips as unplaced.")
                .font(.system(size: 13))
                .foregroundStyle(Crucible.Color.ink2)
                .lineSpacing(3)
            if ref.referencingMemoryCount > 1 {
                Text("It's currently in \(ref.referencingMemoryCount) memories.")
                    .font(.system(size: 12))
                    .foregroundStyle(Crucible.Color.ink3)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Commit

    private func commit() {
        do {
            switch destination {
            case .existingMemory:
                try addToExisting()
            case .newMemory:
                try createNewMemory()
            case .removeFromThisMemory:
                try removeFromSource()
            }
            onPlaced?()
            dismiss()
        } catch {
            ErrorState.shared.report(.saveFailed(error.localizedDescription))
        }
    }

    private func addToExisting() throws {
        guard let entryId = selectedEntryId else { return }
        let ctx = storage.viewContext
        let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        req.predicate = NSPredicate(format: "id == %@", entryId as CVarArg)
        req.fetchLimit = 1
        guard let entry = try ctx.fetch(req).first else { return }
        try StorageService.createEdge(from: entry, to: ref, linkedAt: Date(), in: ctx)
        try dropSourceEdge(in: ctx)
        try storage.save(context: ctx)
    }

    private func createNewMemory() throws {
        let ctx = storage.viewContext
        let entry = try storage.createEntry(content: "", inputType: .typed)
        let trimmed = newMemoryTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { entry.title = trimmed }
        try StorageService.createEdge(from: entry, to: ref, linkedAt: Date(), in: ctx)
        try dropSourceEdge(in: ctx)
        try storage.save(context: ctx)
    }

    private func removeFromSource() throws {
        guard let sourceId = sourceMemoryId else { return }
        let service = EntryLifecycleService(storage: storage, processingEngine: nil)
        service.removeClipFromMemory(memoryId: sourceId, refId: ref.id)
    }

    /// Drops the edge from `sourceMemoryId` if set — used by both
    /// "Move to another memory" and "Into a new memory" so the clip
    /// really moves out of its source, not just gets copied.
    private func dropSourceEdge(in ctx: NSManagedObjectContext) throws {
        guard let sourceId = sourceMemoryId else { return }
        let edgeReq = NSFetchRequest<MemoryClipEdge>(entityName: "MemoryClipEdge")
        edgeReq.predicate = NSPredicate(
            format: "clipId == %@ AND memoryId == %@",
            ref.id as CVarArg,
            sourceId as CVarArg
        )
        edgeReq.fetchLimit = 1
        if let edge = try ctx.fetch(edgeReq).first {
            ctx.delete(edge)
        }
    }
}

/// Placement sheet for a bench **`InboxClip`** (manifest-backed) — the
/// promote-then-place flow (Tom, July 16; wired 2026-07-25). Mirrors
/// `PlaceClipSheet` but MATERIALIZES the clip into a `MediaReference` only ON
/// COMMIT, so a cancel leaves the bench clip untouched (no orphan refs). This
/// replaces the `InboxPromotePlacePlaceholder` dev-text stub — the "Add to a
/// memory" bug on manifest-backed (e.g. Siri/watch voice) clips.
struct PlaceInboxClipSheet: View {
    let clip: InboxClip
    var onPlaced: (() -> Void)? = nil

    enum Destination: Hashable { case existingMemory, newMemory }

    @Environment(\.dismiss) private var dismiss
    @State private var destination: Destination = .existingMemory
    @State private var selectedEntryId: UUID? = nil
    private let lifecycle = EntryLifecycleService()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Destination", selection: $destination) {
                    Text("Existing memory").tag(Destination.existingMemory)
                    Text("New memory").tag(Destination.newMemory)
                }
                .pickerStyle(.segmented)
                Group {
                    switch destination {
                    case .existingMemory:
                        ExistingMemoryPickerView(selectedEntryId: $selectedEntryId)
                    case .newMemory:
                        Text("Creates a new memory with this clip. You can add more, and title it, once it opens.")
                            .font(.system(size: 13))
                            .foregroundStyle(Crucible.Color.ink2)
                            .lineSpacing(3)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if destination != .existingMemory { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 16)
            .background(Crucible.Color.paper)
            .navigationTitle("Where does this belong?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Crucible.Color.ink2)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(destination == .existingMemory ? "Add" : "Create") { commit() }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Crucible.Color.accent)
                        .disabled(destination == .existingMemory && selectedEntryId == nil)
                }
            }
        }
        .presentationDetents([.large, .fraction(0.68)])
        .presentationDragIndicator(.visible)
    }

    private func commit() {
        let ok: Bool
        switch destination {
        case .existingMemory:
            guard let entryId = selectedEntryId else { return }
            ok = lifecycle.placeInboxClip(clip, intoExisting: entryId)
        case .newMemory:
            ok = lifecycle.createMemoryFromInboxClip(clip) != nil
        }
        if ok {
            onPlaced?()
            dismiss()
        } else {
            ErrorState.shared.report(.saveFailed("Couldn't add this clip. Try again."))
        }
    }
}
