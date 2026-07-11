import SwiftUI
import CoreData

/// Clip as primary object — Phase 7. Shows the transcript / media,
/// timestamp, and the memories that reference this clip ("Referenced in").
/// Delete Clip at the bottom in danger red; warns if the clip is
/// attached to memories before it goes to Recently Deleted.
///
/// See `docs/design/HiMem · evidence and context.md` (edge ontology)
/// and `docs/architecture/2026-07-08-evidence-context-ontology-plan.md`
/// § Phase 7.
struct ClipDetailView: View {
    @ObservedObject var ref: MediaReference
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var showingPlacement = false
    /// Slice 7 (Clip Model convergence): inline description editor
    /// state for photo/video clips. Nil = read state (invite or
    /// filled description); non-nil = editing (inline
    /// `ClipEditor(field: .description)`).
    @State private var descriptionDraft: String? = nil

    private let storage = StorageService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if ref.mediaTypeEnum == .voice, let transcript = ref.transcript, !transcript.isEmpty {
                    transcriptSection(transcript)
                } else if ref.mediaTypeEnum == .note, let text = ref.text, !text.isEmpty {
                    transcriptSection(text)
                }
                if isMediaClip {
                    descriptionSection
                }
                referencedInSection
                placementAffordance
                Spacer(minLength: 40)
                deleteSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(Crucible.Color.paper.ignoresSafeArea())
        .navigationTitle("Clip")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPlacement) {
            PlaceClipSheet(ref: ref)
        }
    }

    private var isMediaClip: Bool {
        ref.mediaTypeEnum == .image || ref.mediaTypeEnum == .video
    }

    // MARK: - Description section (photo/video — Slice 7)

    /// Description slot for photo/video clips per `Clip model ·
    /// spec.md` §Content ("the description is the media clip's
    /// words") and Q2's answer: **Clip Detail is an opened
    /// context**, so the ochre invite lights up when empty. Tap
    /// the invite (or the existing description body) → inline
    /// `ClipEditor(field: .description)`. No sheet.
    @ViewBuilder
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DESCRIPTION")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(Crucible.Color.ink3)
            if descriptionDraft != nil {
                ClipEditor(
                    field: .description,
                    draft: Binding(
                        get: { descriptionDraft ?? "" },
                        set: { descriptionDraft = $0 }
                    ),
                    initialValue: ref.mediaDescription ?? "",
                    editId: "description-\(ref.id.uuidString)",
                    evidence: nil,
                    fateActions: ClipEditorFateActions(
                        onDelete: {
                            descriptionDraft = nil
                            confirmingDelete = true
                        },
                        onRelocate: nil
                    ),
                    onCancel: { descriptionDraft = nil },
                    onDone: { newValue in
                        ref.mediaDescription = newValue.isEmpty ? nil : newValue
                        ref.lastEditedAt = Date()
                        try? storage.save(context: context)
                        descriptionDraft = nil
                    }
                )
            } else if let description = ref.mediaDescription, !description.isEmpty {
                Text(description)
                    .font(.system(size: 14))
                    .foregroundStyle(Crucible.Color.ink)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        descriptionDraft = description
                    }
            } else {
                emptyDescriptionInvite
            }
        }
    }

    private var emptyDescriptionInvite: some View {
        Button {
            descriptionDraft = ""
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("Add a description")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Crucible.Color.accent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        Crucible.Color.accent,
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a description")
    }

    // MARK: - Sections

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dateLine)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink2)
            if let place = ref.placeName, !place.isEmpty {
                Text(place)
                    .font(.system(size: 12))
                    .foregroundStyle(Crucible.Color.ink3)
            }
        }
    }

    private var dateLine: String {
        guard let date = ref.createdAt else { return "" }
        let df = DateFormatter()
        df.dateFormat = "EEE MMM d · h:mm a"
        return df.string(from: date)
    }

    @ViewBuilder
    private func transcriptSection(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, design: .serif))
            .foregroundStyle(Crucible.Color.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var referencedInSection: some View {
        let memories = ref.referencingMemoriesSortedByLinkedAtDesc
        VStack(alignment: .leading, spacing: 10) {
            Text("Referenced in")
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(Crucible.Color.ink3)
            if memories.isEmpty {
                Text("Not attached to a memory yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(Crucible.Color.ink3)
            } else {
                ForEach(memories, id: \.id) { mem in
                    referencedInRow(mem)
                }
            }
        }
    }

    @ViewBuilder
    private func referencedInRow(_ memory: JournalEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(Crucible.Color.aiBlue)
                .frame(width: 5, height: 5)
                .offset(y: -3)
            VStack(alignment: .leading, spacing: 2) {
                Text(memory.title ?? "Untitled memory")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink)
                Text(memoryDateLine(memory))
                    .font(.system(size: 11))
                    .foregroundStyle(Crucible.Color.ink3)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private func memoryDateLine(_ memory: JournalEntry) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d, yyyy"
        return df.string(from: memory.createdAt)
    }

    // MARK: - Placement

    /// Dashed ochre "+ Where (else) does this belong?" affordance per
    /// `docs/design/screens-clips-page.jsx` `ScrClipDetail`. Label
    /// branches on placement state — an unplaced clip asks "Where does
    /// this belong?"; a placed clip asks "where **else**" (placement
    /// stops being terminal, per `HiMem · evidence and context.md`).
    @ViewBuilder
    private var placementAffordance: some View {
        Button {
            showingPlacement = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                Text(placementLabel)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Crucible.Color.accent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        Crucible.Color.accent,
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(placementLabel)
    }

    private var placementLabel: String {
        ref.referencingMemoryCount > 0
            ? "Where else does this belong?"
            : "Where does this belong?"
    }

    // MARK: - Delete

    @ViewBuilder
    private var deleteSection: some View {
        let attachedCount = ref.referencingMemoryCount
        VStack(alignment: .leading, spacing: 8) {
            Button(role: .destructive) {
                if attachedCount > 0 {
                    confirmingDelete = true
                } else {
                    performDelete()
                }
            } label: {
                Text("Delete clip")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(Crucible.Color.danger)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Crucible.Color.danger, lineWidth: 1)
                    )
            }
            if attachedCount > 0 {
                Text("This is attached to \(attachedCount) \(attachedCount == 1 ? "memory" : "memories").")
                    .font(.system(size: 12))
                    .foregroundStyle(Crucible.Color.ink3)
            }
        }
        .alert("Delete clip?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This clip is attached to \(attachedCount) \(attachedCount == 1 ? "memory" : "memories"). Deleting it will remove it from all of them.")
        }
    }

    private func performDelete() {
        let service = EntryLifecycleService(storage: storage, processingEngine: ProcessingEngine.shared)
        service.deleteMediaReference(refId: ref.id)
        dismiss()
    }
}
