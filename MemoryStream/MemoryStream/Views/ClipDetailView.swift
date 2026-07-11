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
