import SwiftUI

/// Value snapshot of a Recently-Deleted clip (P8, July 19 2026) — a flat
/// preview + type + recycledAt, so the bin's list holds no managed-object
/// lifetimes. Sibling of `EntryDisplayModel` / `ProjectDisplayModel`.
struct RecycledClipDisplay: Identifiable, Equatable {
    let id: UUID
    let preview: String
    let typeLabel: String
    let recycledAt: Date?

    init(ref: MediaReference) {
        id = ref.id
        recycledAt = ref.recycledAt
        switch ref.mediaTypeEnum {
        case .voice: typeLabel = "Voice"
        case .image: typeLabel = "Photo"
        case .video: typeLabel = "Video"
        case .note:  typeLabel = "Note"
        }
        let candidates = [ref.transcript, ref.text, ref.mediaDescription]
        let firstReal = candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        preview = firstReal ?? "(no text)"
    }
}

struct RecycleBinView: View {
    @ObservedObject var viewModel: JournalViewModel
    /// F1 (2026-07-17): Recently Deleted now also holds soft-deleted projects.
    /// P8 (2026-07-19): and recycled clips. Self-owned VMs (read
    /// StorageService.shared) — no threading through the presenter. NOTE: a
    /// fully object-agnostic bin (one list + restore path for
    /// memory/clip/project) is a real refactor — GhostCard is memory-shaped
    /// and each type has its own VM/service — flagged as a follow-up; for now
    /// each type is a section reusing the same list/restore/purge shape.
    @StateObject private var projectVM = ProjectViewModel()
    private let lifecycle = EntryLifecycleService(storage: .shared, processingEngine: .shared)
    @State private var recycledEntries: [EntryDisplayModel] = []
    @State private var recycledProjects: [ProjectDisplayModel] = []
    @State private var recycledClips: [RecycledClipDisplay] = []
    @State private var showEmptyConfirm = false
    @Environment(\.dismiss) private var dismiss

    private var isEmpty: Bool { recycledEntries.isEmpty && recycledProjects.isEmpty && recycledClips.isEmpty }

    var body: some View {
        NavigationStack {
            Group {
                if isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "trash")
                            .font(.system(size: 40)) // design-token size
                            .foregroundStyle(Crucible.Color.ink4)
                            .accessibilityHidden(true)
                        Text("Recently Deleted is empty")
                            .font(.subheadline)
                            .foregroundStyle(Crucible.Color.ink3)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(recycledEntries) { entry in
                            GhostCard(entry: entry, onRestore: {
                                viewModel.restoreEntry(entryId: entry.id)
                                reload()
                            }, onDelete: {
                                viewModel.deleteEntry(entryId: entry.id)
                                reload()
                            })
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        ForEach(recycledProjects) { project in
                            ProjectGhostCard(project: project, recycledAt: nil, onRestore: {
                                projectVM.restoreProject(id: project.id)
                                reload()
                            }, onDelete: {
                                projectVM.purgeProject(id: project.id)
                                reload()
                            })
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        ForEach(recycledClips) { clip in
                            ClipGhostCard(clip: clip, onRestore: {
                                lifecycle.restoreClip(refId: clip.id)
                                reload()
                            }, onDelete: {
                                lifecycle.purgeClip(refId: clip.id)
                                reload()
                            })
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Crucible.Color.paper)
            .navigationTitle("Recently Deleted")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Empty") {
                            showEmptyConfirm = true
                        }
                        .foregroundStyle(Crucible.Color.danger)
                    }
                }
            }
            .confirmationDialog("Empty Recently Deleted?", isPresented: $showEmptyConfirm, titleVisibility: .visible) {
                Button("Delete All Forever", role: .destructive) {
                    viewModel.emptyRecycleBin()
                    recycledProjects.forEach { projectVM.purgeProject(id: $0.id) }
                    recycledClips.forEach { lifecycle.purgeClip(refId: $0.id) }
                    reload()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                let n = recycledEntries.count + recycledProjects.count + recycledClips.count
                Text("\(n) item\(n == 1 ? "" : "s") will be permanently deleted.")
            }
        }
        .onAppear { reload() }
    }

    private func reload() {
        projectVM.purgeExpiredRecycledProjects()
        lifecycle.purgeExpiredRecycledClips()
        recycledEntries = viewModel.loadRecycledEntries()
        recycledProjects = projectVM.loadRecycledProjects()
        recycledClips = lifecycle.loadRecycledClips()
    }
}

// MARK: - Clip Ghost Card

/// Grayscale ghost card for a recycled clip (P8) — type · preview · days
/// left + Restore/Delete, matching `GhostCard`/`ProjectGhostCard` styling.
private struct ClipGhostCard: View {
    let clip: RecycledClipDisplay
    let onRestore: () -> Void
    let onDelete: () -> Void

    private var daysRemaining: Int {
        guard let recycledAt = clip.recycledAt else { return 30 }
        let elapsed = Calendar.current.dateComponents([.day], from: recycledAt, to: Date()).day ?? 0
        return max(0, 30 - elapsed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(clip.typeLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink3)
                Spacer()
                Text("\(daysRemaining)d left")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Crucible.Color.ink3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Crucible.Color.sunk)
                    .clipShape(Capsule())
            }
            Text(clip.preview)
                .font(.subheadline)
                .italic()
                .foregroundStyle(Crucible.Color.ink3)
                .lineLimit(2)
            HStack(spacing: 12) {
                Spacer()
                Button(action: onRestore) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12))
                            .accessibilityHidden(true)
                        Text("Restore").font(.caption).fontWeight(.semibold)
                    }
                    .foregroundStyle(Crucible.Color.accent)
                }
                .buttonStyle(.plain)
                Button(action: onDelete) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .accessibilityHidden(true)
                        Text("Delete").font(.caption).fontWeight(.semibold)
                    }
                    .foregroundStyle(Crucible.Color.danger)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: Crucible.Radius.xl))
        .modifier(WarmShadow(level: 1))
        .saturation(0)
        .opacity(0.75)
    }
}

// MARK: - Project Ghost Card

/// Grayscale ghost card for a soft-deleted project (name · goal · memory
/// count), matching `GhostCard`'s ghost styling + Restore/Delete actions.
private struct ProjectGhostCard: View {
    let project: ProjectDisplayModel
    let recycledAt: Date?
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(project.name)
                    .font(.system(size: 17, design: .serif))
                    .italic()
                    .foregroundStyle(Crucible.Color.ink3)
                Spacer()
                Text("Project")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Crucible.Color.ink3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Crucible.Color.sunk)
                    .clipShape(Capsule())
            }
            if let purpose = project.purpose, !purpose.isEmpty {
                Text(purpose)
                    .font(.system(size: 12, design: .serif).italic())
                    .foregroundStyle(Crucible.Color.ink3)
                    .lineLimit(2)
            }
            Text("\(project.memoryCount) memor\(project.memoryCount == 1 ? "y" : "ies") — they stay in your library")
                .font(.caption)
                .foregroundStyle(Crucible.Color.ink4)

            HStack(spacing: 12) {
                Spacer()
                Button(action: onRestore) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12))
                            .accessibilityHidden(true)
                        Text("Restore").font(.caption).fontWeight(.semibold)
                    }
                    .foregroundStyle(Crucible.Color.accent)
                }
                .buttonStyle(.plain)
                Button(action: onDelete) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .accessibilityHidden(true)
                        Text("Delete").font(.caption).fontWeight(.semibold)
                    }
                    .foregroundStyle(Crucible.Color.danger)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: Crucible.Radius.xl))
        .modifier(WarmShadow(level: 1))
        .saturation(0)
        .opacity(0.75)
    }
}

// MARK: - Ghost Card

/// Grayscale, italicized card for recycled entries.
private struct GhostCard: View {
    let entry: EntryDisplayModel
    let onRestore: () -> Void
    let onDelete: () -> Void

    private var daysRemaining: Int {
        guard let recycledAt = entry.recycledAt else { return 30 }
        let elapsed = Calendar.current.dateComponents([.day], from: recycledAt, to: Date()).day ?? 0
        return max(0, 30 - elapsed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title + countdown
            HStack {
                Text(entry.displayTitle)
                    .font(.headline)
                    .italic()
                    .foregroundStyle(Crucible.Color.ink3)
                Spacer()
                Text("\(daysRemaining)d left")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Crucible.Color.ink3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Crucible.Color.sunk)
                    .clipShape(Capsule())
            }

            // Timestamp
            Text(entry.timeString)
                .font(.caption)
                .foregroundStyle(Crucible.Color.ink4)

            // Topic pills (grey — ghost styling)
            if !entry.topicNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(entry.topicNames, id: \.self) { name in
                            Text(name)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Crucible.Color.ink2)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Crucible.Color.ink.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            // Content preview (italicized ghost text)
            Text(entry.content)
                .font(.subheadline)
                .italic()
                .foregroundStyle(Crucible.Color.ink3)
                .lineLimit(2)

            // Media dots (grayscale)
            if let summary = entry.mediaSummary {
                HStack(spacing: 6) {
                    if entry.hasAudio {
                        Circle().fill(Crucible.Color.ink4).frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                    }
                    ForEach(entry.mediaItems.indices, id: \.self) { _ in
                        Circle().fill(Crucible.Color.ink4).frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                    }
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(Crucible.Color.ink4)
                }
            }

            // Actions
            HStack(spacing: 12) {
                if let recycledAt = entry.recycledAt {
                    Text("Deleted \(recycledAt, style: .date)")
                        .font(.caption)
                        .foregroundStyle(Crucible.Color.ink4)
                }
                Spacer()
                Button {
                    onRestore()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12)) // design-token size
                            .accessibilityHidden(true)
                        Text("Restore")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(Crucible.Color.accent)
                }
                .buttonStyle(.plain)

                Button {
                    onDelete()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 12)) // design-token size
                            .accessibilityHidden(true)
                        Text("Delete")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(Crucible.Color.danger)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: Crucible.Radius.xl))
        .modifier(WarmShadow(level: 1))
        .saturation(0) // Grayscale ghost effect
        .opacity(0.75)
    }
}
