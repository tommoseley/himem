import SwiftUI
import CoreData

/// Promotes N inbox clips into a single new JournalEntry. Audio files
/// move from Documents/Inbox/audio/ to the standard voice store; manifest
/// rows are dropped; lifecycle.save creates the entry with the clips
/// attached as MediaReferences of type .voice.
///
/// Visual layout per `docs/Himem · Captured Clips (session-first)-2.html` §3
/// (Make a Memory · confirm sheet). Operational-to-reflective seam: this
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
                    ExistingMemoryPickerView(
                        selectedEntryId: $selectedExistingEntryId,
                        onSearchTapped: {
                            // TODO: route to global search prefiltered to
                            // memories per spec. For first cut, dismissing
                            // the sheet returns the user to Captured Clips
                            // where they can navigate to Search themselves.
                            dismiss()
                        }
                    )
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
                // Forward-looking placeholder: when the AI title fetch
                // lands, populate `aiSuggestedTitle` here and seed
                // `title` from it. Until then, the field stays empty
                // with the suggestion helper.
                if title.isEmpty, let suggestion = aiSuggestedTitle {
                    title = suggestion
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
        // Kingfisher Language.md §Vocabulary: "Idle-gap session (already
        // grouped) | *What should this become?* | 'Create one memory' /
        // *Review clips · Add to existing · Not yet.*" — the session
        // pill verb is "Create one memory" (see SessionListView).
        destination == .newMemory ? "Create one memory" : "Add to a memory"
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
        var movedClips: [InboxClip] = []
        let fm = FileManager.default
        for clip in clips {
            let inboxURL = InboxManifest.audioURL(for: clip.audioFilename)
            let voiceURL = SpeechService.audioURL(for: clip.audioFilename)
            // **Where the audio lives depends on the source.** Watch
            // clips land at `InboxManifest.audioURL` (`Documents/Inbox/`)
            // and need the move to `SpeechService.audioURL`
            // (`Documents/Audio/`). Phone clips are written directly
            // by `VoiceCaptureScreen` at `SpeechService.audioURL` —
            // they were NEVER in the inbox directory. Pre-fix the
            // create-memory code assumed every clip was watch-origin
            // and always tried to move from Inbox → Audio; for phone
            // clips the source didn't exist, and the coordinated
            // move (which pre-deletes the destination as
            // `.forReplacing`) was **deleting the actual audio file**
            // the phone had just written. That's how a fresh phone-
            // recorded session failed to attach any clips.
            if fm.fileExists(atPath: voiceURL.path) {
                // Already at the destination (phone clip, or a
                // previous partial run that got the file there).
                // Nothing to move.
                movedClips.append(clip)
                continue
            }
            do {
                // Not at destination — try to move from the inbox
                // (watch case). Uses `NSFileCoordinator` per
                // `UbiquityStore.moveIntoStore`.
                _ = try UbiquityStore.shared.moveIntoStore(
                    sourceURL: inboxURL,
                    destinationURL: voiceURL
                )
                movedClips.append(clip)
            } catch {
                // Neither at destination nor at inbox — audio is
                // genuinely absent (iCloud hasn't downloaded a watch
                // clip yet, or the file was deleted out of band).
                // Log with source hint for diagnosis. Console
                // filter: `[HiMem][CreateMemory] move failed`.
                NSLog("[HiMem][CreateMemory] move failed for clip=\(clip.clipId.uuidString.prefix(8)) source=\(clip.source) file=\(clip.audioFilename) error=\(error.localizedDescription)")
                // Path-level diagnostic — the "the former doesn't
                // exist, or the folder containing the latter doesn't
                // exist" error is ambiguous (source? destination?
                // folder? unclear). Dump both paths, whether they
                // exist, and whether the target directory is present
                // so the next log has enough signal to isolate.
                Self.dumpPathDiagnostic(inboxURL: inboxURL, voiceURL: voiceURL, fm: fm)
                continue
            }
        }
        // Guardrail — if every move failed we would otherwise create
        // an empty memory (transcript = "", no fragments). Bail
        // instead so the user's clips stay on the bench for retry.
        // The bus signal + dismiss below would otherwise land them
        // on an empty Memory Detail, which is exactly the July 12
        // dogfood symptom.
        guard !movedClips.isEmpty else {
            NSLog("[HiMem][CreateMemory] aborting — every clip's audio file failed to move; nothing to bundle")
            return
        }

        let joinedTranscript = movedClips
            .map { $0.transcript }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        // Create the entry with no `mediaCaptures` — voice fragments
        // are written explicitly below so each carries its own
        // per-clip capturedAt at creation time and creates its edge
        // atomically.
        let newId = viewModel.saveEntry(
            content: joinedTranscript,
            inputType: .voiceInApp,
            topicName: selectedTopic
        )

        if let newId {
            let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            request.predicate = NSPredicate(format: "id == %@", newId as CVarArg)
            request.fetchLimit = 1
            if let entry = try? storage.viewContext.fetch(request).first {
                if !trimmedTitle.isEmpty {
                    entry.title = trimmedTitle
                }
                for clip in movedClips.sorted(by: { $0.capturedAt < $1.capturedAt }) {
                    _ = try? storage.createVoiceFragment(
                        for: entry,
                        audioFilename: clip.audioFilename,
                        transcript: clip.transcript,
                        createdAt: clip.capturedAt
                    )
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
            for clip in movedClips {
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

        // Drop manifest rows — audio files were already moved out.
        InboxManifest.shared.removeBatch(clipIds: movedClips.map { $0.clipId })
        // Post-create acceptance criteria per `Clip model · spec.md`
        // §Create one memory (July 12 2026): the sheet dismisses,
        // the session is consumed (the manifest publish above
        // triggers `OpenedSessionView` to auto-dismiss back to the
        // calm Clips list), and a **"Memory created" toast** with a
        // View action confirms it worked. NO auto-navigation to
        // Memories — the user asked to make a memory, not to be
        // teleported. The toast provides the opt-in View path.
        if let newId {
            MemoryNavigationBus.shared.justCreatedMemoryId = newId
        }
        dismiss()
    }

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

        var payload: [(audioFilename: String, transcript: String, capturedAt: Date)] = []
        var locationStamps: [(audioFilename: String, latitude: Double?, longitude: Double?)] = []
        let fm = FileManager.default
        for clip in clips {
            let inboxURL = InboxManifest.audioURL(for: clip.audioFilename)
            let voiceURL = SpeechService.audioURL(for: clip.audioFilename)
            // Same phone-vs-watch source logic as `createMemory` —
            // phone clips are already at the destination; watch
            // clips live in the inbox and need the move.
            if fm.fileExists(atPath: voiceURL.path) {
                payload.append((clip.audioFilename, clip.transcript, clip.capturedAt))
                locationStamps.append((clip.audioFilename, clip.latitude, clip.longitude))
                continue
            }
            do {
                _ = try UbiquityStore.shared.moveIntoStore(
                    sourceURL: inboxURL,
                    destinationURL: voiceURL
                )
                payload.append((clip.audioFilename, clip.transcript, clip.capturedAt))
                locationStamps.append((clip.audioFilename, clip.latitude, clip.longitude))
            } catch {
                NSLog("[HiMem][AppendMemory] move failed for clip=\(clip.clipId.uuidString.prefix(8)) source=\(clip.source) file=\(clip.audioFilename) error=\(error.localizedDescription)")
                continue
            }
        }

        let written = lifecycle.appendClips(entryId: entryId, clips: payload)
        guard written > 0 else { return }

        // Stamp per-clip lat/lon onto the freshly-created MediaReferences
        // so the clip-row header in Memory Detail shows the same
        // "Bishop St, Bluffton" line we'd get on the new-memory path.
        for stamp in locationStamps {
            ClipLocationResolver.stamp(
                osIdentifier: stamp.audioFilename,
                latitude: stamp.latitude,
                longitude: stamp.longitude,
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

    /// Emits a per-clip path diagnostic when the move fails. Dumps
    /// the source / destination URLs, whether either file exists,
    /// whether each parent directory exists, and — most usefully —
    /// looks for the filename in the sandbox `Documents/Audio/`
    /// path. If the file ended up in the sandbox instead of the
    /// iCloud container (warmUp race, migration edge case), the
    /// sandbox check tells us so instantly.
    /// Console filter: `[HiMem][CreateMemory][pathDx]`.
    private static func dumpPathDiagnostic(
        inboxURL: URL,
        voiceURL: URL,
        fm: FileManager
    ) {
        let sandboxDocs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let sandboxAudio = sandboxDocs
            .appendingPathComponent("Audio", isDirectory: true)
            .appendingPathComponent(voiceURL.lastPathComponent)
        let sandboxInbox = sandboxDocs
            .appendingPathComponent("Inbox", isDirectory: true)
            .appendingPathComponent(inboxURL.lastPathComponent)
        NSLog("[HiMem][CreateMemory][pathDx] voiceURL=\(voiceURL.path) exists=\(fm.fileExists(atPath: voiceURL.path))")
        NSLog("[HiMem][CreateMemory][pathDx] voiceDir=\(voiceURL.deletingLastPathComponent().path) exists=\(fm.fileExists(atPath: voiceURL.deletingLastPathComponent().path))")
        NSLog("[HiMem][CreateMemory][pathDx] inboxURL=\(inboxURL.path) exists=\(fm.fileExists(atPath: inboxURL.path))")
        NSLog("[HiMem][CreateMemory][pathDx] inboxDir=\(inboxURL.deletingLastPathComponent().path) exists=\(fm.fileExists(atPath: inboxURL.deletingLastPathComponent().path))")
        NSLog("[HiMem][CreateMemory][pathDx] sandboxAudio=\(sandboxAudio.path) exists=\(fm.fileExists(atPath: sandboxAudio.path))")
        NSLog("[HiMem][CreateMemory][pathDx] sandboxInbox=\(sandboxInbox.path) exists=\(fm.fileExists(atPath: sandboxInbox.path))")
        // Directory listing of the current Audio dir — bounded to
        // 20 entries so we don't spam Console.
        let audioDir = voiceURL.deletingLastPathComponent()
        if let contents = try? fm.contentsOfDirectory(atPath: audioDir.path) {
            let sample = contents.prefix(20).joined(separator: ", ")
            NSLog("[HiMem][CreateMemory][pathDx] audioDir contents (\(contents.count) total): \(sample)")
        }
    }
}
