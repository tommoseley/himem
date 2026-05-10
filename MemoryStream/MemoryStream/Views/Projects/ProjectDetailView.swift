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
                        TextField("What are you building toward?", text: $editedPurpose)
                            .font(.subheadline)
                            .foregroundStyle(Crucible.Color.ink)
                            .padding(10)
                            .background(Crucible.Color.paper)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Crucible.Color.hairline, lineWidth: 1))
                        Text("A video? A post? An idea?")
                            .font(.caption)
                            .foregroundStyle(Crucible.Color.ink4)
                            .padding(.leading, 4)
                    }
                } else {
                    Text(project?.name ?? "")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Crucible.Color.ink)

                    if let purpose = project?.purpose, !purpose.isEmpty {
                        Text(purpose)
                            .font(.subheadline)
                            .foregroundStyle(Crucible.Color.ink2)
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
                                projectVM.removeMemory(entryId: entry.id, fromProjectId: projectId)
                                loadProjectEntries()
                            } label: {
                                Label("Remove from Project", systemImage: "minus.circle")
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Crucible.Color.paper)
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
        .onAppear {
            loadProject()
            loadProjectEntries()
        }
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
