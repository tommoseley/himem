import SwiftUI
import CoreData
import UIKit

/// Memory Detail FAB · path 2: add existing loose clips from the bench
/// into this memory (`Memory Detail · unified editing model.md` §"Adding
/// clips to a memory"). Lists every unconnected bench clip
/// (`edges.@count == 0`, not recycled) for multi-select; confirming
/// attaches them via new `MemoryClipEdge`s in the tapped order.
///
/// The attach itself runs in the host's `onAdd` callback (which owns the
/// `EntryLifecycleService`) via `attachExistingClips` — that regenerates
/// content and marks the memory stale (offers Reorganize), and never
/// auto-organizes. This sheet is pure selection UI.
///
/// Operational surface (per Crucible): SF Pro, denser rows, no editorial
/// type — the workshop bench, not the gallery. Selection uses the shared
/// `SelectCircle` (ring → ochre check).
struct AddExistingClipsSheet: View {
    /// Called with the selected clip ids in tap order when the user
    /// commits. The host performs the attach + any follow-up.
    let onAdd: ([UUID]) -> Void

    @Environment(\.dismiss) private var dismiss

    @FetchRequest private var looseClips: FetchedResults<MediaReference>
    /// Tap order preserved — clips attach after the memory's existing
    /// clips in the order the user selected them.
    @State private var selected: [UUID] = []
    /// F22 · the one fact this view reads before it claims to be empty.
    @ObservedObject private var firstImport = FirstImportState.shared

    init(onAdd: @escaping ([UUID]) -> Void) {
        self.onAdd = onAdd
        _looseClips = FetchRequest(
            entity: MediaReference.entity(),
            sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)],
            predicate: NSPredicate(format: "edges.@count == 0 AND recycledAt == nil"),
            animation: .default
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                // F22: `looseClips` is a live fetch over CloudKit-synced
                // `MediaReference`s, so on a fresh install it is empty until
                // the import lands. Secondary surface — say nothing while
                // importing rather than claiming every clip is already placed.
                if !looseClips.isEmpty {
                    clipList
                } else if firstImport.mayAssertEmpty {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Crucible.Color.paper)
            .navigationTitle("Add clips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Crucible.Color.ink)
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Ochre = the user commits (Crucible button colour code).
                    Button(addLabel) {
                        onAdd(selected)
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected.isEmpty ? Crucible.Color.ink4 : Crucible.Color.accent)
                    .disabled(selected.isEmpty)
                }
            }
        }
    }

    private var addLabel: String {
        selected.isEmpty ? "Add" : "Add \(selected.count)"
    }

    private var clipList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                Text("Clips not yet in any memory")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(Crucible.Color.ink3)
                    .padding(.horizontal, 3)
                    .padding(.bottom, 2)

                ForEach(looseClips) { ref in
                    Button {
                        toggle(ref.id)
                    } label: {
                        AddExistingClipRow(ref: ref, checked: selected.contains(ref.id))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    private func toggle(_ id: UUID) {
        if let idx = selected.firstIndex(of: id) {
            selected.remove(at: idx)
        } else {
            selected.append(id)
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    /// Gated by the caller on `firstImport.mayAssertEmpty` — this claim
    /// ("every clip is already in a memory") is only true once the import has
    /// finished looking.
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Crucible.Color.ink4)
            Text("No unconnected clips")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink)
            Text("Every clip you've captured is already in a memory. New clips — from +, your Watch, or Siri — show up here to add.")
                .font(.system(size: 14))
                .foregroundStyle(Crucible.Color.ink3)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 40)
        }
        .padding(.bottom, 40)
    }
}

/// One selectable bench clip. Mirrors `LooseClipRow`'s shape (icon tile ·
/// meta line · preview) but trades the navigation chevron for a
/// `SelectCircle`, and covers all four media types.
private struct AddExistingClipRow: View {
    @ObservedObject var ref: MediaReference
    let checked: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            iconTile
            VStack(alignment: .leading, spacing: 3) {
                metaLine
                previewLine
            }
            Spacer(minLength: 8)
            SelectCircle(checked: checked)
                .padding(.top, 3)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(checked ? Crucible.Color.accent : Crucible.Color.hairline,
                        lineWidth: checked ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 13))
    }

    private var iconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Crucible.Color.hairline.opacity(0.3))
                .frame(width: 30, height: 30)
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Crucible.Color.ink3)
        }
    }

    /// Canonical media glyphs — matches `LooseClipRow` /
    /// `EntryCardView.MediaGlyphRow`.
    private var iconName: String {
        switch ref.mediaTypeEnum {
        case .voice: return "waveform"
        case .note:  return "text.alignleft"
        case .image: return "photo"
        case .video: return "video"
        }
    }

    private var metaLine: some View {
        HStack(spacing: 6) {
            Text(clipTimeString(ref))
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(Crucible.Color.ink2)
            if let place = ref.placeName, !place.isEmpty {
                Text("·").foregroundStyle(Crucible.Color.ink4)
                Text(place)
                    .lineLimit(1)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Crucible.Color.ink3)
            }
        }
    }

    private var previewLine: some View {
        Text(previewText)
            .font(.system(size: 13.5))
            .foregroundStyle(Crucible.Color.ink2)
            .lineSpacing(2)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var previewText: String {
        switch ref.mediaTypeEnum {
        case .voice:
            let t = ref.transcript ?? ""
            return t.isEmpty ? "Voice clip" : "\u{201C}\(t)\u{201D}"
        case .note:
            let t = ref.text ?? ""
            return t.isEmpty ? "Note" : t
        case .image: return "Photo"
        case .video: return "Video"
        }
    }
}
