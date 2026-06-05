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
        destination == .newMemory ? "New memory" : "Add to memory"
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

    /// Two-option segmented control. Per spec: `Make a new memory`
    /// (default) and `Add to existing memory`. Picking either swaps the
    /// body without changing the sheet's presentation.
    private var destinationToggle: some View {
        Picker("Destination", selection: $destination) {
            Text("Make a new memory").tag(Destination.newMemory)
            Text("Add to existing memory").tag(Destination.existingMemory)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Summary chip (ochre, names the session scope)

    /// Session-summary chip per JSX: 28pt rounded-rect icon tile
    /// holding a microphone glyph, then "N clips · time · duration"
    /// primary line + "M clips excluded" sub-line. Card background,
    /// hairline border (not accent tint background).
    private func summaryChip(for session: ClipGroup) -> some View {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        let timeStr = f.string(from: session.capturedAt)
        let bundleCount = clips.count
        let countStr = bundleCount == 1 ? "1 clip" : "\(bundleCount) clips"
        let durStr = formatDuration(session.totalDuration)
        let accidentalCount = session.clips.count - bundleCount
        return HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Crucible.Color.accentTint)
                    .frame(width: 28, height: 28)
                Image(systemName: "mic.fill")
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
                    newTopicChip
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

    /// Forward-looking "+ New" chip per spec. Tapping today is a
    /// no-op — when the inline new-topic flow lands, hook the action
    /// here.
    private var newTopicChip: some View {
        Button { /* TODO: inline new-topic flow */ } label: {
            HStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                Text("New")
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

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Promotion

    /// Moves each clip's audio from Documents/Inbox/audio/ into the
    /// standard voice store at Documents/VoiceEntries/, builds a single
    /// JournalEntry through lifecycle.save with all clips attached, then
    /// drops the inbox manifest rows.
    private func createMemory() {
        // Build the joined transcript for entry.content. Empty transcripts
        // contribute nothing; AI will summarize from whatever's there.
        let joinedTranscript = clips
            .map { $0.transcript }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        var captures: [(localIdentifier: String, mediaType: MediaReference.MediaType)] = []
        for clip in clips {
            let inboxURL = InboxManifest.audioURL(for: clip.audioFilename)
            let voiceURL = SpeechService.audioURL(for: clip.audioFilename)
            do {
                if FileManager.default.fileExists(atPath: voiceURL.path) {
                    try FileManager.default.removeItem(at: voiceURL)
                }
                try FileManager.default.moveItem(at: inboxURL, to: voiceURL)
                captures.append((clip.audioFilename, .voice))
            } catch {
                // If the move fails, skip that clip — its inbox row stays
                // for retry on the next attempt.
                continue
            }
        }

        let inputType: JournalEntry.InputType = .voiceInApp
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        let newId = viewModel.saveEntry(
            content: joinedTranscript,
            inputType: inputType,
            mediaCaptures: captures,
            topicName: selectedTopic
        )

        // Post-save fixups: copy per-clip transcripts onto each new
        // MediaReference (lifecycle.save's `mediaCaptures` tuple doesn't
        // carry transcripts), and apply the user-supplied title if any.
        // Fetch the MediaReferences by `osIdentifier` directly rather than
        // traversing `entry.mediaReferences` — the relationship can hold a
        // snapshot from before lifecycle.save linked the new refs in.
        if let newId {
            let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            request.predicate = NSPredicate(format: "id == %@", newId as CVarArg)
            request.fetchLimit = 1
            if let entry = try? storage.viewContext.fetch(request).first,
               !trimmedTitle.isEmpty {
                entry.title = trimmedTitle
            }
            for clip in clips where !clip.transcript.isEmpty {
                let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
                req.predicate = NSPredicate(format: "osIdentifier == %@", clip.audioFilename)
                req.fetchLimit = 1
                if let ref = try? storage.viewContext.fetch(req).first {
                    ref.transcript = clip.transcript
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

        // Drop manifest rows — audio files were already moved out.
        InboxManifest.shared.removeBatch(clipIds: clips.map { $0.clipId })
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
        for clip in clips {
            let inboxURL = InboxManifest.audioURL(for: clip.audioFilename)
            let voiceURL = SpeechService.audioURL(for: clip.audioFilename)
            do {
                if FileManager.default.fileExists(atPath: voiceURL.path) {
                    try FileManager.default.removeItem(at: voiceURL)
                }
                try FileManager.default.moveItem(at: inboxURL, to: voiceURL)
                payload.append((clip.audioFilename, clip.transcript, clip.capturedAt))
                locationStamps.append((clip.audioFilename, clip.latitude, clip.longitude))
            } catch {
                // Skip clips whose audio failed to move — their inbox
                // rows stay so the user can retry. Matches the
                // create-new-memory path's tolerance.
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

        InboxManifest.shared.removeBatch(clipIds: clips.map { $0.clipId })
        dismiss()
    }
}
