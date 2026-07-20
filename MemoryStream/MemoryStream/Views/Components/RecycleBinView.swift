import SwiftUI
import UIKit

/// Value snapshot of a Recently-Deleted clip (P8, July 19 2026) — a flat
/// preview + type + recycledAt, so the bin's list holds no managed-object
/// lifetimes. Sibling of `EntryDisplayModel` / `ProjectDisplayModel`.
struct RecycledClipDisplay: Identifiable, Equatable {
    let id: UUID
    let preview: String
    let typeLabel: String
    let recycledAt: Date?
    /// Thumbnail source for photo/video rows — the same `(osIdentifier,
    /// mediaType)` the live clip row resolves through `ThumbnailService`
    /// (July 20 2026 fix). Nil for voice/note and unpromoted bench clips.
    /// Recycle never deletes the blob or evicts the thumbnail cache, so this
    /// resolves fine for a recycled clip — no `recycledAt` gating is involved.
    let thumbnailOSIdentifier: String?
    let thumbnailMediaType: MediaReference.MediaType?

    init(ref: MediaReference) {
        id = ref.id
        recycledAt = ref.recycledAt
        switch ref.mediaTypeEnum {
        case .voice: typeLabel = "Voice"
        case .image: typeLabel = "Photo"
        case .video: typeLabel = "Video"
        case .note:  typeLabel = "Note"
        }
        if ref.mediaTypeEnum == .image || ref.mediaTypeEnum == .video {
            thumbnailOSIdentifier = ref.osIdentifier
            thumbnailMediaType = ref.mediaTypeEnum
        } else {
            thumbnailOSIdentifier = nil
            thumbnailMediaType = nil
        }
        let candidates = [ref.transcript, ref.text, ref.mediaDescription]
        let firstReal = candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        preview = firstReal ?? "(no text)"
    }

    /// P8b: an unpromoted bench clip (manifest row) — voice-only, per-device.
    init(inboxClip clip: InboxClip) {
        id = clip.clipId
        recycledAt = clip.recycledAt
        typeLabel = "Voice"
        thumbnailOSIdentifier = nil
        thumbnailMediaType = nil
        let t = clip.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        preview = t.isEmpty ? "(voice clip)" : t
    }
}

/// Recently Deleted type filter (July 20 2026). All is leftmost + default.
enum RecycleBinFilter: String, CaseIterable, Identifiable, Hashable {
    case all, clips, memories, projects
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:      return "All"
        case .clips:    return "Clips"
        case .memories: return "Memories"
        case .projects: return "Projects"
        }
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
    /// P8b: recycled unpromoted bench clips (manifest-backed, per-device).
    @State private var recycledInboxClips: [RecycledClipDisplay] = []
    @State private var showEmptyConfirm = false
    /// Type selector (July 20 2026) — All · Clips · Memories · Projects,
    /// All leftmost + default. A pure UI filter over the bin; "Empty" stays
    /// global (see the toolbar), not scoped to this.
    @State private var filter: RecycleBinFilter = .all
    @Environment(\.dismiss) private var dismiss

    private var isEmpty: Bool {
        recycledEntries.isEmpty && recycledProjects.isEmpty
            && recycledClips.isEmpty && recycledInboxClips.isEmpty
    }

    private var showClips: Bool { filter == .all || filter == .clips }
    private var showMemories: Bool { filter == .all || filter == .memories }
    private var showProjects: Bool { filter == .all || filter == .projects }

    /// True when the active filter (other than All) has nothing, though the
    /// bin isn't globally empty — a blank area reads as "broken/loading," so
    /// we surface one calm recognition line instead (no count).
    private var activeFilterEmpty: Bool {
        switch filter {
        case .all:      return false // a non-empty bin always has something under All
        case .clips:    return recycledClips.isEmpty && recycledInboxClips.isEmpty
        case .memories: return recycledEntries.isEmpty
        case .projects: return recycledProjects.isEmpty
        }
    }

    private var emptyFilterMessage: String {
        switch filter {
        case .clips:    return "No deleted clips"
        case .memories: return "No deleted memories"
        case .projects: return "No deleted projects"
        case .all:      return ""
        }
    }

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
                    VStack(spacing: 0) {
                        // Reuses the Clips-header segmented control (not a
                        // lookalike). Pure filter — no per-type counts.
                        HiMemSegmentedControl(options: RecycleBinFilter.allCases, selection: $filter, label: \.label)
                            .padding(.top, 10)
                            .padding(.bottom, 6)
                        if activeFilterEmpty {
                            Spacer()
                            Text(emptyFilterMessage)
                                .font(.subheadline)
                                .foregroundStyle(Crucible.Color.ink3)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                            Spacer()
                        } else {
                        List {
                        if showMemories {
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
                        }
                        if showProjects {
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
                        }
                        if showClips {
                        // Clips = both backings (promoted MediaReferences +
                        // unpromoted InboxClips). No "stays in your library"
                        // subline — a clip is the atom; nothing lives beneath it.
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
                        ForEach(recycledInboxClips) { clip in
                            ClipGhostCard(clip: clip, onRestore: {
                                InboxManifest.shared.restoreClip(clipId: clip.id)
                                reload()
                            }, onDelete: {
                                InboxManifest.shared.purgeRecycledClip(clipId: clip.id)
                                reload()
                            })
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        }
                    }
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
                    recycledInboxClips.forEach { InboxManifest.shared.purgeRecycledClip(clipId: $0.id) }
                    reload()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                let n = recycledEntries.count + recycledProjects.count
                    + recycledClips.count + recycledInboxClips.count
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
        recycledInboxClips = InboxManifest.shared.loadRecycledClips().map { RecycledClipDisplay(inboxClip: $0) }
    }
}

// MARK: - Clip Ghost Card

/// Grayscale ghost card for a recycled clip (P8) — type · preview · days
/// left + Restore/Delete, matching `GhostCard`/`ProjectGhostCard` styling.
private struct ClipGhostCard: View {
    let clip: RecycledClipDisplay
    let onRestore: () -> Void
    let onDelete: () -> Void
    @State private var thumbnail: UIImage?

    private var daysRemaining: Int {
        guard let recycledAt = clip.recycledAt else { return 30 }
        let elapsed = Calendar.current.dateComponents([.day], from: recycledAt, to: Date()).day ?? 0
        return max(0, 30 - elapsed)
    }

    /// Photo/video rows carry a leading thumbnail, resolved the same way the
    /// live clip row does (July 20 2026). Nil source (voice/note) → no tile.
    @ViewBuilder private var thumbnailLeading: some View {
        if clip.thumbnailOSIdentifier != nil {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Crucible.Color.sunk)
                if let thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill()
                } else {
                    Image(systemName: clip.thumbnailMediaType == .video ? "video" : "photo")
                        .foregroundStyle(Crucible.Color.ink4)
                }
                if clip.thumbnailMediaType == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnailLeading
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
        }
        .padding(14)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: Crucible.Radius.xl))
        .modifier(WarmShadow(level: 1))
        .saturation(0)
        .opacity(0.75)
        // Resolve the thumbnail the SAME way the live clip row does
        // (MediaClipRow) — cache-or-generate from the media file. No
        // recycledAt gating; recycle keeps the blob + the thumbnail cache.
        .task(id: clip.id) {
            guard thumbnail == nil, let osId = clip.thumbnailOSIdentifier else {
                NSLog("[HiMem][BinThumb] \(clip.id) no source (osId nil) — no tile")
                return
            }
            let mediaType = clip.thumbnailMediaType ?? .image
            guard let name = await ThumbnailService.shared.cacheThumbnail(for: osId, mediaType: mediaType) else {
                NSLog("[HiMem][BinThumb] \(clip.id) cacheThumbnail returned nil (blob not downloaded / decode failed) osId=\(osId) type=\(mediaType.rawValue)")
                return
            }
            let img = ThumbnailService.shared.cachedThumbnail(filename: name)
            if img == nil { NSLog("[HiMem][BinThumb] \(clip.id) cachedThumbnail(\(name)) read nil") }
            thumbnail = img
        }
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
