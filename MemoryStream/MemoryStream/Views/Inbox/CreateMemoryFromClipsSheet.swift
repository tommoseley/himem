import SwiftUI
import CoreData

/// Promotes N inbox clips into a single new JournalEntry. Audio files
/// move from Documents/Inbox/audio/ to the standard voice store; manifest
/// rows are dropped; lifecycle.save creates the entry with the clips
/// attached as MediaReferences of type .voice.
///
/// Visual layout per `docs/design/HiMem · Clips.html` §3
/// (Start a Memory · confirm sheet). Operational-to-reflective seam: this
/// sheet softens from triage into Memory creation. Ochre summary chip
/// names the scope at the top; AI-suggested title renders in AI blue
/// with an AI tag.
struct CreateMemoryFromClipsSheet: View {
    /// Destination of the bundle. Drives the sheet's header, commit
    /// action label, and body content. Per `docs/design/Captured
    /// Clips · session-first · spec.md` § Bundle confirm sheet
    /// (May 25 2026 addition).
    enum Destination: Hashable { case newMemory, existingMemory }

    let clips: [InboxClip]
    /// Source session — used to render the ochre summary chip
    /// ("3 clips · 3:36 PM · 0:12"). Optional so existing single-clip
    /// callers can keep working.
    var session: ClipGroup? = nil
    /// Absorbed photo/video/note `MediaReference`s the user kept
    /// included on the bench session card. Each gets attached to
    /// the new/existing entry via `StorageService.createEdge` so
    /// a mixed 2-voice + 1-photo session yields one memory
    /// containing all three clips (July 11 2026 media-agnostic
    /// idle-gap lock). Empty when the session had no absorbed
    /// media or the user deselected them all.
    var absorbedMediaRefs: [MediaReference] = []
    /// Seeds the Title field when placing from a Sort cluster (the cluster's
    /// proposed title, e.g. "Kingfisher Wharf"). Editable; clearing it falls
    /// back to the AI-suggest default. `nil` for single loose clips — they
    /// keep the optional / AI-suggest default. (2026-07-17, §Sort.)
    var prefillTitle: String? = nil
    @ObservedObject var viewModel: JournalViewModel

    @State private var destination: Destination = .newMemory
    @State private var title: String = ""
    /// Tracks whether the user has overwritten the AI-suggested title.
    /// Drives the `AI` tag visibility — once they type, the tag drops.
    @State private var userEditedTitle: Bool = false
    @State private var selectedTopic: String? = nil
    @State private var selectedProjectId: UUID? = nil
    @State private var selectedExistingEntryId: UUID? = nil
    @State private var aiSuggestedTitle: String? = nil
    /// Drives the "+ New project" inline alert.
    @State private var showingNewProjectAlert: Bool = false
    @State private var newProjectName: String = ""
    /// Routes the "Get AI title · 1 assist →" tap (free + 0 assists)
    /// to the Upgrade Hub per pricing spec § 14 side branch.
    @ObservedObject private var entitlement = Entitlement.shared
    @Environment(\.dismiss) private var dismiss

    /// Fresh per-sheet view-model. Read-only here — we list projects and
    /// (optionally) create one via the "+ New project" chip. Sheet
    /// lifetime is short; a one-shot fetch is fine.
    @StateObject private var projectVM = ProjectViewModel()

    private let storage = StorageService.shared
    private let lifecycle = EntryLifecycleService()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                if let session {
                    summaryChip(for: session)
                }
                destinationToggle
                if destination == .newMemory {
                    titleField
                    topicChips
                    projectChips
                } else {
                    ExistingMemoryPickerView(selectedEntryId: $selectedExistingEntryId)
                }
                Spacer(minLength: 0)
            }
            .alert("New project", isPresented: $showingNewProjectAlert) {
                TextField("Project name", text: $newProjectName)
                Button("Cancel", role: .cancel) { newProjectName = "" }
                Button("Create") { createNewProjectFromAlert() }
                    .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                Text("Give the project a short name. You can edit it later.")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(Crucible.Color.paper)
            .navigationTitle(headerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Crucible.Color.ink2)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(commitLabel) {
                        commit()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Crucible.Color.accent)
                    .disabled(!canCommit)
                }
            }
            .onAppear {
                // Cluster placement seeds the Title with the cluster's proposed
                // title (editable; clearing it falls back to AI-suggest). Single
                // loose clips have no prefill and keep the AI-suggest default.
                // Forward-looking: when the AI title fetch lands, populate
                // `aiSuggestedTitle` and it seeds here when nothing else has.
                if title.isEmpty {
                    if let prefillTitle, !prefillTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        title = prefillTitle
                    } else if let suggestion = aiSuggestedTitle {
                        title = suggestion
                    }
                }
            }
        }
        // 68% per JSX — half-height with the session card still
        // partly visible above. User can drag to large if they need
        // more room (e.g. long title).
        .presentationDetents([.fraction(0.68), .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header / commit (mode-aware)

    private var headerTitle: String {
        // `docs/design/Kingfisher Language.md` §Vocabulary — Idle-gap
        // session (already grouped): **"Start a Memory"** /
        // *Review clips · Add to existing · Not yet.*  The session pill
        // verb is "Start a Memory" (see `SessionListView`); the sheet
        // is the continuation of that action, so it carries the same
        // header. `Clip model · spec.md` §Start a Memory (July 12 2026).
        destination == .newMemory ? "Start a Memory" : "Add to a memory"
    }

    private var commitLabel: String {
        destination == .newMemory ? "Create" : "Add"
    }

    private var canCommit: Bool {
        switch destination {
        case .newMemory: return true
        case .existingMemory: return selectedExistingEntryId != nil
        }
    }

    private func commit() {
        switch destination {
        case .newMemory: createMemory()
        case .existingMemory: appendToExistingMemory()
        }
    }

    // MARK: - Destination toggle (segmented control)

    /// Two-option segmented control. Kingfisher Language.md bans "Make"
    /// — the segments are `New memory` and `Add to existing memory`
    /// (2026-07-09 rename). Picking either swaps the body without
    /// changing the sheet's presentation.
    private var destinationToggle: some View {
        Picker("Destination", selection: $destination) {
            Text("New memory").tag(Destination.newMemory)
            Text("Add to existing memory").tag(Destination.existingMemory)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Summary chip (ochre, names the session scope)

    /// Session-summary chip per JSX: 28pt rounded-rect icon tile
    /// holding a microphone glyph, then "N clips · time · duration"
    /// primary line + "M clips excluded" sub-line. Card background,
    /// hairline border (not accent tint background).
    ///
    /// Slice 10a of the Clip Model convergence
    /// (`docs/architecture/2026-07-11-clip-model-convergence-plan.md`):
    /// clip-count derives from `CompositionModel.from(clips:)` — the
    /// same primitive `sessionMetaRow` uses. The mic-tile icon +
    /// excluded-count sub-line stay bespoke (session-scoped chrome
    /// `ClipComposition`'s default shape doesn't render), matching
    /// Slice 8's partial-swap pattern.
    private func summaryChip(for session: ClipGroup) -> some View {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        let timeStr = f.string(from: session.capturedAt)
        let composition = CompositionModel.from(
            clips: clips.map { ClipDisplayModel(inboxClip: $0, sessionStart: session.capturedAt) }
        )
        let bundleCount = composition.mediaCounts.total
        let countStr = bundleCount == 1 ? "1 clip" : "\(bundleCount) clips"
        let durStr = formatDuration(session.totalDuration)
        let accidentalCount = session.clips.count - bundleCount
        return HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Crucible.Color.accentTint)
                    .frame(width: 28, height: 28)
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Crucible.Color.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(countStr) · \(timeStr) · \(durStr)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink)
                if accidentalCount > 0 {
                    Text(accidentalCount == 1
                         ? "1 clip excluded"
                         : "\(accidentalCount) clips excluded")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Crucible.Color.ink3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
    }

    // MARK: - Title field (with AI tag + helper)

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Title")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Crucible.Color.ink3)
                if hasAISuggestion {
                    aiTagChip
                }
                Spacer()
            }
            TextField("", text: $title, prompt: Text(titlePlaceholder).foregroundColor(Crucible.Color.ink4))
                .font(.system(size: 17, design: .serif))
                .foregroundStyle(titleTextColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Crucible.Color.card)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(hasAISuggestion ? Crucible.Color.aiBlueTint : Crucible.Color.hairline, lineWidth: 1)
                )
                .onChange(of: title) { _, newValue in
                    if let suggestion = aiSuggestedTitle, newValue != suggestion {
                        userEditedTitle = true
                    }
                }
            if hasAISuggestion, !userEditedTitle {
                Text("Suggested from your transcripts. Tap to rewrite.")
                    .font(.caption)
                    .foregroundStyle(Crucible.Color.ink3)
            }
        }
    }

    private var hasAISuggestion: Bool {
        aiSuggestedTitle != nil && !userEditedTitle
    }

    private var titleTextColor: Color {
        hasAISuggestion ? Crucible.Color.aiBlue : Crucible.Color.ink
    }

    private var titlePlaceholder: String {
        aiSuggestedTitle != nil
            ? "Suggested title…"
            : "Optional — AI will suggest one if blank"
    }

    private var aiTagChip: some View {
        Text("AI")
            .font(.system(size: 9, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(Crucible.Color.aiBlue)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Crucible.Color.aiBlueTint)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Topic chips (existing topics + "+ New")

    private var topicChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Topic")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Crucible.Color.ink3)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(label: "None", topic: nil)
                    ForEach(viewModel.topics, id: \.self) { topic in
                        chip(label: topic, topic: topic)
                    }
                    // `+ New` topic chip hidden for v1 — the inline
                    // new-topic flow isn't wired; users can create
                    // topics from Settings → Topics for now.
                }
            }
        }
    }

    /// Active topic chip per JSX: ochre-on-cream styling with a
    /// warm-grey dot. Background `rgba(198,74,28,0.16)`, border
    /// `rgba(198,74,28,0.28)`, text `#7A3A14`, dot `#7A6B4F`.
    /// Inactive chips stay card-on-hairline, ink2 text.
    private func chip(label: String, topic: String?) -> some View {
        let isSelected = selectedTopic == topic
        return Button {
            selectedTopic = topic
        } label: {
            // Active-topic chip uses Crucible accent-tint family —
            // catalog-backed so the wash auto-flips for dark mode.
            // bg = accent-tint, border = accent-tint-2; dot uses ink2
            // (warm grey light / cream dark) so it stays legible
            // against either chip surface; text uses accent-pressed
            // (deeper ochre light / lighter ochre dark).
            HStack(spacing: 6) {
                if isSelected, topic != nil {
                    Circle()
                        .fill(Crucible.Color.ink2)
                        .frame(width: 6, height: 6)
                }
                Text(label)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(isSelected ? Crucible.Color.accentPressed : Crucible.Color.ink2)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(isSelected ? Crucible.Color.accentTint : Crucible.Color.card)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(
                    isSelected ? Crucible.Color.accentTint2 : Crucible.Color.hairline,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Project chips (existing projects + "+ New project")

    /// Optional project assignment per the Captured Clips spec — the
    /// memory can land in 0–N projects (Memory × Project is many-to-many).
    /// For the bundle flow we surface single-select to keep the sheet
    /// tight; the user can multi-assign later from Memory Detail.
    @ViewBuilder
    private var projectChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Project")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Crucible.Color.ink3)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    projectChip(label: "None", projectId: nil)
                    ForEach(projectVM.projects) { project in
                        projectChip(label: project.name, projectId: project.id)
                    }
                    newProjectChip
                }
            }
        }
    }

    /// Project chip — same visual treatment as the topic chips so the
    /// sheet reads as one consistent row of optional metadata.
    private func projectChip(label: String, projectId: UUID?) -> some View {
        let isSelected = selectedProjectId == projectId
        return Button {
            selectedProjectId = projectId
        } label: {
            HStack(spacing: 6) {
                if isSelected, projectId != nil {
                    Circle()
                        .fill(Crucible.Color.ink2)
                        .frame(width: 6, height: 6)
                }
                Text(label)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(isSelected ? Crucible.Color.accentPressed : Crucible.Color.ink2)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(isSelected ? Crucible.Color.accentTint : Crucible.Color.card)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(
                    isSelected ? Crucible.Color.accentTint2 : Crucible.Color.hairline,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }

    /// "+ New project" chip — opens an alert with a text field. On
    /// Create the new project is selected automatically.
    private var newProjectChip: some View {
        Button {
            newProjectName = ""
            showingNewProjectAlert = true
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                Text("New project")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Crucible.Color.ink3)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Crucible.Color.card)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Crucible.Color.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Confirmed via the "+ New project" alert. Creates the project,
    /// re-fetches the list, and selects the newly-created one so the
    /// user doesn't have to scroll back and tap it.
    private func createNewProjectFromAlert() {
        let trimmed = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        projectVM.createProject(name: trimmed, purpose: nil)
        // ProjectViewModel.createProject re-loads `projects` synchronously
        // before returning, so the new row is already in the list.
        if let created = projectVM.projects.first(where: { $0.name == trimmed }) {
            selectedProjectId = created.id
        }
        newProjectName = ""
    }

    /// "+ New" topic affordance per `HiMem · Buttons & Actions §2`:
    /// dashed ochre — the canonical "add / provisional" shape, same
    /// vocabulary as the `+ Edit` affordance on Memory Detail's
    /// topic row. Tapping today is a no-op — when the inline
    /// new-topic flow lands, hook the action here.
    private var newTopicChip: some View {
        Button { /* TODO: inline new-topic flow */ } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text("New")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Crucible.Color.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Crucible.Color.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .contentShape(Rectangle()) // edge-to-edge tap (dashed pill interior is transparent)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Promotion

    /// Moves each clip's audio from Documents/Inbox/audio/ into the
    /// standard voice store at Documents/VoiceEntries/, creates a
    /// single JournalEntry, then writes each clip as a `.voice`
    /// MediaReference via `storage.createVoiceFragment(createdAt:)`.
    /// The write path creates the edge atomically (Phase 2+3 —
    /// see `docs/architecture/2026-07-08-evidence-context-ontology-plan.md`).
    private func createMemory() {
        // P0-3: bench clips are already CloudKit-synced zero-edge
        // `MediaReference`s (materialize-on-arrival). Materialize each —
        // idempotent, a no-op when the ref already exists, but promoting any
        // clip that finished transcribing this very instant — so every clipId
        // resolves to a ref; then EDGE the existing refs via
        // `createMemoryFromExistingClips`. We never re-materialize (the
        // double-ref bug the old move+mint path would now cause), and there is
        // no audio move here: `materialize` owns the Inbox→Audio move.
        for clip in clips {
            ArrivedClipMaterializer.materialize(clip, in: storage.viewContext)
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        // Assemble the new memory by attaching the existing refs (append order
        // by capturedAt is enforced inside `attachExistingClips`). The content
        // reconcile — which prevents the orphan-`.note` duplication (2026-07-13
        // dogfood defect, `CreateMemoryFromClipsAssemblyTests`) — lives in
        // `attachExistingClips`, the same joined-of-fragments path.
        let newId = lifecycle.createMemoryFromExistingClips(
            clipIds: clips.map(\.clipId),
            topicName: selectedTopic
        )
        // No explicit `loadEntries` — `JournalViewModel.observeStorage
        // Changes` is subscribed to `NSManagedObjectContextObjectsDid
        // Change` on the same viewContext and reloads on the debounced
        // tick after the lifecycle save.

        if let newId {
            let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            request.predicate = NSPredicate(format: "id == %@", newId as CVarArg)
            request.fetchLimit = 1
            if let entry = try? storage.viewContext.fetch(request).first {
                if !trimmedTitle.isEmpty {
                    entry.title = trimmedTitle
                }
                // July 11 2026 media-agnostic idle-gap lock: absorbed
                // photo/video refs on the bench session card get
                // attached here so the resulting memory contains all
                // the session's clips, not just voice. Sorted by
                // `createdAt` so edge ordering matches the visual
                // chronology inside the card. Idempotent via
                // `StorageService.createEdge`.
                let sortedMedia = absorbedMediaRefs
                    .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
                for ref in sortedMedia {
                    try? StorageService.createEdge(
                        from: entry,
                        to: ref,
                        linkedAt: Date(),
                        in: storage.viewContext
                    )
                }
            }
            try? storage.save(context: storage.viewContext)

            // Stamp per-clip lat/lon from the watch's location fix
            // and kick off background reverse-geocode so the clip-row
            // header in Memory Detail can show "Bishop St, Bluffton"
            // alongside the date + time. No-op when the watch
            // captured without a fix (location permission off, no
            // signal, etc.).
            for clip in clips {
                ClipLocationResolver.stamp(
                    osIdentifier: clip.audioFilename,
                    latitude: clip.latitude,
                    longitude: clip.longitude,
                    in: storage.viewContext
                )
            }

            // Optional project assignment from the bundle sheet's
            // chip-row. ProjectViewModel.addMemory handles the
            // many-to-many wiring and saves.
            if let projectId = selectedProjectId {
                projectVM.addMemory(entryId: newId, toProjectId: projectId)
            }
        }

        Self.finishCreate(
            newMemoryId: newId,
            clipIds: clips.map(\.clipId),
            // Belt: any manifest rows are already demoted to tombstones by
            // `materialize` (which the loop above ran on every clip) — this is
            // a harmless no-op for materialized clips, and a safety net for any
            // that somehow weren't.
            consumeSession: { InboxManifest.shared.removeBatch(clipIds: $0) },
            announce: { MemoryNavigationBus.shared.justCreatedMemoryId = $0 },
            report: { ErrorState.shared.report(.saveFailed($0)) },
            dismiss: { dismiss() }
        )
    }

    /// The tail of `createMemory()` — the part that decides the **session's**
    /// fate. `consumeSession` drops the manifest rows; `dismiss` closes the
    /// sheet on a job reported done.
    ///
    /// Neither may run without a memory to hold the clips.
    /// `createMemoryFromExistingClips` returns nil when no ref resolved and
    /// rolls its entry back (`EntryLifecycleService:786-791`) — on that path
    /// the old code skipped the `if let newId` block but consumed the session
    /// and dismissed anyway. The session vanished from the bench, no memory
    /// existed, and nothing was said (F23 T1.3, audit 2026-07-31).
    ///
    /// The steps are injected so the money test can prove the session survives
    /// without reaching the `InboxManifest` singleton's real on-disk rows.
    ///
    /// Post-create acceptance criteria per `Clip model · spec.md` §Start a
    /// Memory (July 12 2026): the sheet dismisses, the session is consumed
    /// (the manifest publish triggers `OpenedSessionView` to auto-dismiss back
    /// to the calm Clips list), and a **"Memory created" toast** with a View
    /// action confirms it worked. NO auto-navigation to Memories — the user
    /// asked to make a memory, not to be teleported.
    @MainActor
    static func finishCreate(
        newMemoryId: UUID?,
        clipIds: [UUID],
        consumeSession: ([UUID]) -> Void,
        announce: (UUID) -> Void,
        report: (String) -> Void,
        dismiss: () -> Void
    ) {
        guard let newMemoryId else {
            report(creationFailedMessage)
            return
        }
        consumeSession(clipIds)
        announce(newMemoryId)
        dismiss()
    }

    /// Shown when no memory was created. The sheet stays open with the
    /// session's clips still listed and still on the bench, so "try again" is
    /// literally what's available.
    static let creationFailedMessage = "Couldn't create this memory. Try again."

    /// Captured Clips · session-first spec § Bundle confirm sheet ·
    /// Add-to-existing-memory mode. Moves each selected clip's audio
    /// from the inbox to the standard voice store, then appends N
    /// `.voice` MediaReferences to the chosen entry in chronological
    /// order via `EntryLifecycleService.appendClips`. **No automatic
    /// re-organize** — per AI Organize § 8, refresh is user-tap-only.
    /// The destination memory's view picks up the new fragments as
    /// "stale" (createdAt past `lastOrganizedAt`) and renders the
    /// amber `N new clips · Refresh · 1 assist` footer.
    private func appendToExistingMemory() {
        guard let entryId = selectedExistingEntryId else { return }

        // P0-3: bench clips are already CloudKit-synced zero-edge refs.
        // Materialize each (idempotent) so every clipId resolves to a ref, then
        // EDGE the existing refs onto the memory (`attachExistingClips`, which
        // orders by capturedAt and reconciles content) — never re-materialize.
        for clip in clips {
            ArrivedClipMaterializer.materialize(clip, in: storage.viewContext)
        }

        let written = lifecycle.attachExistingClips(
            entryId: entryId,
            clipIds: clips.map(\.clipId)
        )
        guard written > 0 else { return }

        // Stamp per-clip lat/lon onto the refs so the clip-row header in Memory
        // Detail shows the same "Bishop St, Bluffton" line as the new-memory
        // path. Idempotent — re-stamps the same values the ref already carries.
        for clip in clips {
            ClipLocationResolver.stamp(
                osIdentifier: clip.audioFilename,
                latitude: clip.latitude,
                longitude: clip.longitude,
                in: storage.viewContext
            )
        }

        // July 11 2026 media-agnostic idle-gap lock: attach
        // absorbed photo/video refs to the destination entry, same
        // as the new-memory path. Fetch the entry once so
        // `createEdge` can build the reciprocal link. Idempotent
        // per `StorageService.createEdge`.
        if !absorbedMediaRefs.isEmpty {
            let entryReq = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            entryReq.predicate = NSPredicate(format: "id == %@", entryId as CVarArg)
            entryReq.fetchLimit = 1
            if let entry = try? storage.viewContext.fetch(entryReq).first {
                let sortedMedia = absorbedMediaRefs
                    .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
                for ref in sortedMedia {
                    try? StorageService.createEdge(
                        from: entry,
                        to: ref,
                        linkedAt: Date(),
                        in: storage.viewContext
                    )
                }
                try? storage.save(context: storage.viewContext)
            }
        }

        InboxManifest.shared.removeBatch(clipIds: clips.map { $0.clipId })
        dismiss()
    }
}
