import SwiftUI
import CoreData
import Photos
import AVFoundation
import UIKit

/// Project View — header + purpose + curated memory stack.
/// Entry cards are used here (inside a project), not on the project list.
struct ProjectDetailView: View {
    let projectId: UUID
    @ObservedObject var projectVM: ProjectViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var project: Project?
    @State private var entries: [EntryDisplayModel] = []
    @State private var isEditing = false
    @State private var editedName = ""
    @State private var editedPurpose = ""
    @State private var selectedEntryId: UUID? = nil
    @State private var topicFilter: String? = nil
    @State private var showShareSheet = false
    @State private var showAddMemorySheet = false
    @State private var shareItems: [Any] = []
    @State private var isPreparingShare = false
    @State private var showProjectAssistUpsell = false
    @ObservedObject private var entitlement = EntitlementService.shared

    /// Coordinates the trailing-edge swipe across memory rows so only
    /// one row's Remove affordance is open at a time.
    @State private var openedSwipeRowId: AnyHashable? = nil

    /// Most-recently-removed entry id, held until the undo window
    /// expires (5s per spec). When non-nil, the bottom toast renders.
    @State private var pendingUndoEntryId: UUID? = nil
    /// Task that auto-dismisses the undo toast after 5s. Cancelled
    /// when the user taps Undo (so the toast clears immediately) or
    /// when another removal supersedes this one.
    @State private var undoDismissTask: Task<Void, Never>? = nil

    private let storage = StorageService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                if isEditing {
                    TextField("Project name", text: $editedName)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Crucible.Color.ink)
                        .padding(10)
                        .background(Crucible.Color.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Crucible.Color.accent, lineWidth: 1.5))

                    VStack(alignment: .leading, spacing: 4) {
                        // UI label "Goal" — Core Data attribute remains
                        // `purpose` (see Project model comment).
                        TextField("Goal", text: $editedPurpose)
                            .font(.subheadline)
                            .foregroundStyle(Crucible.Color.ink)
                            .padding(10)
                            .background(Crucible.Color.paper)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Crucible.Color.hairline, lineWidth: 1))
                        Text("What are you building toward? A video, a post, an idea.")
                            .font(.caption)
                            .foregroundStyle(Crucible.Color.ink4)
                            .padding(.leading, 4)
                    }
                } else {
                    // Title — serif 30pt per `ProjectTitleBlock`.
                    // Use `design: .serif` (iOS New York) rather than
                    // `.custom("Source Serif 4", …)`: the latter
                    // silently falls back to SF Pro because the font
                    // isn't bundled, which is why the spec looked
                    // visually compressed. Real serif metrics restore
                    // the cap height the JSX preview's Georgia
                    // fallback was showing.
                    Text(project?.name ?? "")
                        .font(.system(size: 30, design: .serif))
                        .tracking(-0.5)
                        .lineSpacing(2)
                        .foregroundStyle(Crucible.Color.ink)

                    // Goal — italic serif line, ink2. Optional;
                    // hidden when the project has no goal text.
                    if let purpose = project?.purpose, !purpose.isEmpty {
                        Text(purpose)
                            .font(.system(size: 13, design: .serif).italic())
                            .foregroundStyle(Crucible.Color.ink2)
                            .lineSpacing(2)
                    }
                }

                // Topic pills from project entries (tap to filter)
                if let proj = project, !proj.topicNames.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(proj.topicNames, id: \.self) { topic in
                                let hue = Crucible.Color.topicHue(for: topic)
                                Button {
                                    if topicFilter == topic {
                                        topicFilter = nil
                                    } else {
                                        topicFilter = topic
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Circle().fill(hue.fg).frame(width: 6, height: 6)
                                            .accessibilityHidden(true)
                                        Text(topic)
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(hue.fg)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(topicFilter == topic ? hue.bg : hue.bg.opacity(0.5))
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule().stroke(topicFilter == topic ? hue.fg.opacity(0.3) : .clear, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Find the thread — Project Assist affordance.
                // Visible below 3 memories but disabled with helper
                // copy so the user discovers the affordance early.
                // Activates at ≥3 per the Projects MVP spec.
                findTheThreadButton

                // Memory count
                let displayCount = topicFilter == nil ? entries.count : entries.filter { $0.topicNames.contains(topicFilter!) }.count
                Text("\(displayCount) memor\(displayCount == 1 ? "y" : "ies")")
                    .font(.caption)
                    .foregroundStyle(Crucible.Color.ink3)

                // Memory stack — entry cards
                if entries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.title)
                            .foregroundStyle(Crucible.Color.ink4)
                            .accessibilityHidden(true)
                        Text("No memories in this project yet")
                            .font(.subheadline)
                            .foregroundStyle(Crucible.Color.ink3)
                        Text("Open a memory and use \"Add to Project\" to curate this collection.")
                            .font(.caption)
                            .foregroundStyle(Crucible.Color.ink4)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                } else {
                    let filtered = topicFilter == nil ? entries : entries.filter { $0.topicNames.contains(topicFilter!) }
                    ForEach(filtered) { entry in
                        EntryCardView(
                            entry: entry,
                            density: .standard,
                            onFeedback: nil,
                            onEntityTap: nil,
                            onAppend: nil
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { selectedEntryId = entry.id }
                        .contextMenu {
                            Button(role: .destructive) {
                                removeMemoryWithUndo(entryId: entry.id)
                            } label: {
                                Label("Remove from Project", systemImage: "minus.circle")
                            }
                        }
                        // Trailing-edge swipe per Projects MVP spec
                        // (Model § Removing a memory): single-tap
                        // commits, undo toast is the safety net.
                        .swipeToDelete(
                            id: entry.id,
                            openedRowId: $openedSwipeRowId,
                            label: "Remove",
                            systemImage: "minus.circle"
                        ) {
                            removeMemoryWithUndo(entryId: entry.id)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Crucible.Color.paper)
        .overlay(alignment: .bottom) {
            if pendingUndoEntryId != nil {
                undoToast
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: pendingUndoEntryId)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if isEditing {
                    Button("Cancel") {
                        isEditing = false
                        editedName = project?.name ?? ""
                        editedPurpose = project?.purpose ?? ""
                    }
                    .foregroundStyle(Crucible.Color.accent)
                } else {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold)) // design-token size
                                .accessibilityHidden(true)
                            Text("Projects")
                        }
                        .foregroundStyle(Crucible.Color.accent)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if isEditing {
                    Button("Done") {
                        let trimmed = editedName.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        projectVM.updateProject(id: projectId, name: trimmed, purpose: editedPurpose.isEmpty ? nil : editedPurpose)
                        isEditing = false
                        loadProject()
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(Crucible.Color.accent)
                } else {
                    HStack(spacing: 16) {
                        Button { showAddMemorySheet = true } label: {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 16))
                                .foregroundStyle(Crucible.Color.accent)
                        }
                        .accessibilityLabel("Add memory to project")
                        Button {
                            Task { await prepareAndShowShareSheet() }
                        } label: {
                            if isPreparingShare {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 15)) // design-token size
                                    .foregroundStyle(Crucible.Color.ink2)
                            }
                        }
                        .disabled(isPreparingShare)
                        .accessibilityLabel("Share project")
                        Button { isEditing = true } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 15)) // design-token size
                                .foregroundStyle(Crucible.Color.ink2)
                        }
                        .accessibilityLabel("Edit project")
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
        .sheet(isPresented: $showAddMemorySheet, onDismiss: { loadProjectEntries() }) {
            AddMemoryToProjectSheet(projectId: projectId, projectVM: projectVM)
        }
        .sheet(isPresented: $showProjectAssistUpsell) {
            ProjectAssistUpsellSheet()
                .presentationDetents([.medium])
        }
        .onAppear {
            loadProject()
            loadProjectEntries()
        }
    }

    /// Routes the "Find the thread" tap. Free user with starter
    /// available → consume silently and (later) invoke project
    /// assist. Free user with starter spent → present upsell.
    /// Plus / Founders → consume from the monthly bucket. The actual
    /// server invocation lands in a follow-up PR; this scope wires
    /// the entitlement bucket end-to-end so behavior is correct.
    private func handleFindTheThreadTap() {
        guard entitlement.canConsumeProjectAssist else {
            showProjectAssistUpsell = true
            return
        }
        do {
            try entitlement.tryConsumeProjectAssist()
            // TODO: invoke project assist (summary + suggestions).
            // Server-side endpoint design lands as a sibling change.
        } catch {
            showProjectAssistUpsell = true
        }
    }

    /// "Find the thread" card — Project Assist entry point.
    /// Card with a 36-square AI-tint icon on the left, title +
    /// sub-line stacked in the middle, "Run" pill on the right.
    /// Disabled below `ProjectAssistGate.minimumMemories`; sub-line
    /// adapts to whichever threshold is currently active. Spec
    /// (Projects MVP § States) wants `Add a memory first.` for the
    /// ≥1 path and `Add a few more memories first.` for the gated-
    /// off conservative path.
    @ViewBuilder
    private var findTheThreadButton: some View {
        let enabled = ProjectAssistGate.isEnabled(memoryCount: entries.count)
        // Cost label per pricing spec § Open work locked decision 1
        // (2026-05-27): free users on first use see "Starter · free"
        // so they know they're tasting their one freebie. Subsequent
        // taps fall to "1 assist" — same as Plus — and the tap fires
        // the upsell because `canConsumeProjectAssist` is now false.
        let isStarterRun = !entitlement.isPlus && !entitlement.starterProjectAssistUsed
        let costLabel = isStarterRun ? "Starter · free" : "1 assist"
        let subline = enabled
            ? "A short summary across these memories. \(costLabel)."
            : (ProjectAssistGate.allowSingleMemoryThreshold
               ? "Add a memory first."
               : "Add a few more memories first.")
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Crucible.Color.aiBlueTint)
                    .frame(width: 36, height: 36)
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Crucible.Color.aiBlue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Find the thread")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.1)
                    .foregroundStyle(Crucible.Color.ink)
                Text(subline)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Crucible.Color.ink3)
                    .lineSpacing(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                guard enabled else { return }
                handleFindTheThreadTap()
            } label: {
                Text("Run")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(enabled
                                ? Crucible.Color.aiBlue
                                : Crucible.Color.aiBlue.opacity(0.35))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Crucible.Color.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func composeProjectText() -> String {
        Self.composeProjectText(
            name: project?.name,
            purpose: project?.purpose,
            entries: entries
        )
    }

    /// Pure formatter for the share-sheet output. Header (uppercased name +
    /// optional purpose) followed by `---`-separated entry blocks containing
    /// the entry title and clean content. Static so tests can call it
    /// directly with any (name, purpose, entries) inputs.
    static func composeProjectText(name: String?, purpose: String?, entries: [EntryDisplayModel]) -> String {
        var lines: [String] = []

        if let name {
            lines.append(name.uppercased())
            if let purpose, !purpose.isEmpty {
                lines.append(purpose)
            }
            lines.append("")
        }

        for entry in entries {
            lines.append("---")
            lines.append("")
            lines.append(entry.displayTitle)
            lines.append(entry.content)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func loadProject() {
        let request = NSFetchRequest<Project>(entityName: "Project")
        request.predicate = NSPredicate(format: "id == %@", projectId as CVarArg)
        request.fetchLimit = 1
        project = try? storage.viewContext.fetch(request).first
        editedName = project?.name ?? ""
        editedPurpose = project?.purpose ?? ""
    }

    // MARK: - Remove + undo

    /// Removes a memory from the project and arms the 5-second undo
    /// toast. Per Projects MVP spec § Removing a memory: no
    /// confirmation modal — the undo toast IS the safety net.
    /// Subsequent removals supersede any pending undo (only the most
    /// recent removal is undoable, matching standard toast semantics).
    private func removeMemoryWithUndo(entryId: UUID) {
        projectVM.removeMemory(entryId: entryId, fromProjectId: projectId)
        loadProjectEntries()
        openedSwipeRowId = nil
        undoDismissTask?.cancel()
        pendingUndoEntryId = entryId
        undoDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled {
                pendingUndoEntryId = nil
            }
        }
    }

    private func undoLastRemoval() {
        guard let entryId = pendingUndoEntryId else { return }
        projectVM.addMemory(entryId: entryId, toProjectId: projectId)
        loadProjectEntries()
        undoDismissTask?.cancel()
        undoDismissTask = nil
        pendingUndoEntryId = nil
    }

    /// Bottom toast — "Removed from [project] · Undo". Per spec the
    /// only safety net for the swipe-remove path. Project name is
    /// quoted so the user sees exactly which project they removed
    /// the memory from (especially relevant on the second tap of an
    /// undo-then-remove-again sequence).
    private var undoToast: some View {
        HStack(spacing: 12) {
            Text(toastMessage)
                .font(.system(size: 14))
                .foregroundStyle(Crucible.Color.paper)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                undoLastRemoval()
            } label: {
                Text("Undo")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Crucible.Color.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Crucible.Color.ink)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 2)
    }

    private var toastMessage: String {
        let name = project?.name.trimmingCharacters(in: .whitespaces)
        if let name, !name.isEmpty {
            return "Removed from \(name)"
        }
        return "Removed from project"
    }

    private func loadProjectEntries() {
        guard let project else { return }
        let journalEntries = project.entriesArray.filter { !$0.isRecycled }
        entries = journalEntries.map(EntryMapper.mapToDisplayModel)
    }

    // MARK: - Share preparation

    /// Builds the share-sheet payload: composed text plus full-resolution
    /// image data, video file URLs, and voice-clip file URLs pulled from each
    /// entry. PhotoKit lookups are async so we set a `isPreparingShare` flag
    /// to swap the share button to a spinner while we collect items.
    private func prepareAndShowShareSheet() async {
        isPreparingShare = true
        defer { isPreparingShare = false }

        var items: [Any] = [composeProjectText()]

        let photoKitIds: [String] = entries.flatMap { entry in
            entry.mediaItems
                .filter { $0.mediaType == .image || $0.mediaType == .video }
                .map { $0.localIdentifier }
        }
        if !photoKitIds.isEmpty {
            let fetch = PHAsset.fetchAssets(withLocalIdentifiers: photoKitIds, options: nil)
            var assets: [PHAsset] = []
            fetch.enumerateObjects { asset, _, _ in assets.append(asset) }
            for asset in assets {
                if asset.mediaType == .image, let image = await loadFullImage(from: asset) {
                    items.append(image)
                } else if asset.mediaType == .video, let url = await loadVideoURL(from: asset) {
                    items.append(url)
                }
            }
        }

        // Voice clips on disk — every voice fragment lives on a `.voice`
        // MediaReference post-FragmentMigration.
        var voiceFilenames: [String] = []
        for entry in entries {
            voiceFilenames.append(contentsOf: entry.mediaItems
                .filter { $0.mediaType == .voice }
                .map { $0.localIdentifier })
        }
        for filename in voiceFilenames {
            let url = SpeechService.audioURL(for: filename)
            if FileManager.default.fileExists(atPath: url.path) {
                items.append(url)
            }
        }

        shareItems = items
        showShareSheet = true
    }

    private func loadFullImage(from asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded { return }
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }

    private func loadVideoURL(from asset: PHAsset) async -> URL? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            var resumed = false
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                guard !resumed else { return }
                resumed = true
                if let urlAsset = avAsset as? AVURLAsset {
                    continuation.resume(returning: urlAsset.url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
