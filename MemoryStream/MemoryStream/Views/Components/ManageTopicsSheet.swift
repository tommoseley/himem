import SwiftUI
import CoreData

/// Manage Topics — the deliberate, AI-independent topic editor per
/// `AI Organize · spec.md §2c` and `docs/design/screens-topics.jsx`
/// `ScrManageTopics`.
///
/// Reached by tapping the **Edit** affordance on Memory Detail's
/// persistent topic chip row. The user picks from their existing
/// palette (visible at the bottom) or adds a new topic. Topic
/// changes here are deliberate user actions — never an AI side
/// effect of some other pass.
///
/// Surface:
/// - **Top bar** — Cancel · Topics · Done. Done commits.
/// - **Body copy** — "Pick from your library, or add a new topic.
///   Picking the right existing one keeps your topics useful as
///   filters." (Honest-label voice — describes the trade-off
///   without preaching.)
/// - **"On this memory"** — chips in `.pick` state for currently
///   selected topics. Tap to deselect (drops to `.off`).
/// - **"Add a new topic…"** — inline field that promotes the typed
///   name into the selection on submit.
/// - **"From your library"** — every palette topic in `.pick` /
///   `.off` state. Tap to toggle.
///
/// Commit semantics: Done writes the diff between the initial
/// selection and the current one. Topics added: `addToTopics`.
/// Topics removed: `removeFromTopics`. New topics created via the
/// "Add new" field land via `StorageService.findOrCreateTopic`,
/// which is idempotent on slug collision.
struct ManageTopicsSheet: View {
    let entryID: UUID
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// Names currently selected for the entry — initialized from the
    /// entry's topics at appear, mutated by chip taps + add-new.
    @State private var selectedNames: Set<String> = []
    /// All palette topic names — snapshotted at sheet appear so the
    /// list doesn't reshuffle while the user is browsing.
    @State private var paletteNames: [String] = []
    /// The "Add a new topic" field's draft value.
    @State private var newTopicDraft: String = ""
    @FocusState private var newFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Grabber + top-bar paddings match `EditTextSheet`
            // exactly so the Manage Topics, AudioPlayer (voice
            // clip), and PhotoDescription edit sheets all read as
            // siblings at the same vertical rhythm.
            grabber
            topBar
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Pick from your library, or add a new topic. Picking the right existing one keeps your topics useful as filters.")
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

                    sectionEyebrow("From your library")
                    libraryPalette
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Crucible.Color.paper)
        .task { await loadInitialState() }
    }

    // MARK: - Top chrome (grabber + bar)

    /// Matches `EditTextSheet.grabber` exactly — same dimensions,
    /// opacity, and spacing so the two edit sheets read as siblings.
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
            Button(action: cancelAndDismiss) {
                Text("Cancel")
                    .font(.system(size: 15))
                    .foregroundStyle(Crucible.Color.ink2)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Topics")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink)
            Spacer()
            Button(action: commitAndDismiss) {
                Text("Done")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Crucible.Color.accent)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Sections

    private func sectionEyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(1.3)
            .foregroundStyle(Crucible.Color.ink3)
            .padding(.bottom, 8)
    }

    private var onMemorySection: some View {
        let sorted = selectedNames.sorted()
        return Group {
            if sorted.isEmpty {
                Text("No topics on this memory yet.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Crucible.Color.ink3)
            } else {
                FlowingChips(names: sorted) { name in
                    TopicChip(label: name, state: .pick) {
                        toggle(name)
                    }
                }
            }
        }
    }

    private var addNewField: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink3)
            TextField("Add a new topic…", text: $newTopicDraft)
                .font(.system(size: 14.5))
                .foregroundStyle(Crucible.Color.ink)
                .focused($newFieldFocused)
                .submitLabel(.done)
                .onSubmit { promoteDraftToSelection() }
            if !newTopicDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: promoteDraftToSelection) {
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
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }

    private var libraryPalette: some View {
        // Hide names already selected — they live in "On this memory"
        // above. Empty palette gets a quiet placeholder so the section
        // header doesn't dangle.
        let available = paletteNames.filter { !selectedNames.contains($0) }
        return Group {
            if available.isEmpty {
                Text(paletteNames.isEmpty
                     ? "Your library is empty. Add a topic above to get started."
                     : "Everything in your library is on this memory.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Crucible.Color.ink3)
            } else {
                FlowingChips(names: available) { name in
                    TopicChip(label: name, state: .off) {
                        toggle(name)
                    }
                }
            }
        }
    }

    // MARK: - Selection actions

    private func toggle(_ name: String) {
        if selectedNames.contains(name) {
            selectedNames.remove(name)
        } else {
            selectedNames.insert(name)
        }
    }

    /// Promotes the draft field's text into the selection (creating a
    /// palette entry if the name's new). Idempotent — typing a name
    /// that already exists in the palette just selects it.
    private func promoteDraftToSelection() {
        let trimmed = newTopicDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Snap to the palette's canonical form if a case-variant
        // exists. Otherwise add as-is — Done will findOrCreateTopic.
        let key = trimmed.lowercased()
        let canonical = paletteNames.first(where: { $0.lowercased() == key }) ?? trimmed
        selectedNames.insert(canonical)
        if !paletteNames.contains(canonical) {
            paletteNames.append(canonical)
        }
        newTopicDraft = ""
        newFieldFocused = false
    }

    // MARK: - Commit / cancel

    private func cancelAndDismiss() {
        onDismiss()
    }

    /// Diffs initial vs current selection and writes the delta to
    /// the entry. New topic names go through `findOrCreateTopic` so
    /// the palette gains a Topic record idempotently.
    private func commitAndDismiss() {
        let ctx = StorageService.shared.viewContext
        let toAddNow = selectedNames
        ctx.performAndWait {
            guard let entry = fetchEntry(in: ctx) else { return }
            let initialNames = Set((entry.topics as? Set<Topic>)?.compactMap { $0.name } ?? [])
            let delta = Self.computeDelta(initial: initialNames, selected: toAddNow)
            for name in delta.toRemove {
                if let topic = findTopic(named: name, in: ctx) {
                    entry.removeFromTopics(topic)
                }
            }
            for name in delta.toAdd {
                if let topic = try? StorageService.shared.findOrCreateTopic(name: name, context: ctx) {
                    entry.addToTopics(topic)
                }
            }
            try? ctx.save()
        }
        onDismiss()
    }

    /// The add/remove split between an entry's initial topic set and
    /// the user's current selection in the sheet. Extracted as a
    /// pure value type so the test suite can exercise it without
    /// standing up Core Data.
    struct CommitDelta: Equatable {
        /// Names selected now but not in `initial` — will become
        /// `entry.addToTopics(...)` (with `findOrCreateTopic` first
        /// for names new to the palette).
        let toAdd: Set<String>
        /// Names in `initial` but not selected now — will become
        /// `entry.removeFromTopics(...)`.
        let toRemove: Set<String>
    }

    /// Set-diff between the entry's initial topic membership and the
    /// user's current selection. Pure; no Core Data. The caller is
    /// responsible for translating the deltas into Topic lookups +
    /// addToTopics/removeFromTopics writes.
    ///
    /// Comparison is case-sensitive — both `initial` and `selected`
    /// originate from palette-canonical names, so a case-only
    /// disagreement would already indicate a palette consistency
    /// bug elsewhere. The sheet's "Add a new topic" field
    /// canonicalizes against the palette before insertion, so the
    /// inputs to this function are always palette-form.
    static func computeDelta(initial: Set<String>, selected: Set<String>) -> CommitDelta {
        CommitDelta(
            toAdd: selected.subtracting(initial),
            toRemove: initial.subtracting(selected)
        )
    }

    // MARK: - Snapshot fetch

    private func loadInitialState() async {
        let ctx = StorageService.shared.viewContext
        let (entryNames, allNames) = await ctx.perform { () -> ([String], [String]) in
            let entryTopics = (fetchEntry(in: ctx)?.topics as? Set<Topic>) ?? []
            let entryNames = entryTopics.compactMap { $0.name }
            let request = NSFetchRequest<Topic>(entityName: "Topic")
            let palette = ((try? ctx.fetch(request)) ?? []).compactMap { $0.name }.sorted()
            return (entryNames, palette)
        }
        selectedNames = Set(entryNames)
        paletteNames = allNames
    }

    private func fetchEntry(in ctx: NSManagedObjectContext) -> JournalEntry? {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "id == %@", entryID as CVarArg)
        request.fetchLimit = 1
        return (try? ctx.fetch(request))?.first
    }

    private func findTopic(named name: String, in ctx: NSManagedObjectContext) -> Topic? {
        let request = NSFetchRequest<Topic>(entityName: "Topic")
        request.predicate = NSPredicate(format: "slug == %@", TopicSlugHelper.slugify(name))
        request.fetchLimit = 1
        return (try? ctx.fetch(request))?.first
    }
}

/// Flow-wraps `TopicChip`s in a left-aligned row. Each chip sizes
/// to its intrinsic width (no text wrapping); the row wraps to the
/// next line only when no more chips fit horizontally. Backed by the
/// shared `FlowLayout` Layout helper in EntryCardView.swift.
private struct FlowingChips<Content: View>: View {
    let names: [String]
    let chip: (String) -> Content

    var body: some View {
        // 10pt spacing per the June 8 44pt hit-target floor —
        // separates chip tap zones unambiguously.
        FlowLayout(spacing: 10) {
            ForEach(names, id: \.self) { chip($0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
