import SwiftUI
import CoreData

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
                                .font(.system(size: 14, weight: .semibold))
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
                    Button { isEditing = true } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 15))
                            .foregroundStyle(Crucible.Color.ink2)
                    }
                }
            }
        }
        .onAppear {
            loadProject()
            loadProjectEntries()
        }
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
        entries = journalEntries.map { entry in
            let task = entry.latestProcessingTask
            let inference = entry.inferenceSummary
            return EntryDisplayModel(
                id: entry.id,
                displayTitle: entry.displayTitle,
                content: entry.content,
                inputType: entry.inputTypeEnum,
                createdAt: entry.createdAt,
                processingStatus: task?.statusEnum,
                progressDescription: task?.progressDescription,
                tags: entry.entitiesArray.map { TagDisplayModel(id: $0.id, value: $0.value, entityType: $0.entityTypeEnum, confidence: $0.confidenceScore) },
                topicNames: entry.topicsArray.map(\.name),
                audioFilePath: entry.audioFilePath,
                inferenceSummary: inference?.summaryText,
                feedbackState: inference?.feedbackStateEnum,
                mediaItems: entry.mediaReferencesArray.map { ref in
                    MediaDisplayItem(id: ref.id, localIdentifier: ref.osIdentifier, mediaType: ref.mediaTypeEnum, thumbnailCacheFilename: ref.thumbnailCacheFilename, isAccessible: ref.isAccessible)
                },
                recycledAt: entry.recycledAt
            )
        }
    }
}
