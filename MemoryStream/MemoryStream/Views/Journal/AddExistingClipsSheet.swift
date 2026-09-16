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
    /// Watch recordings still in flight. The manifest is the only place that
    /// knows about a recording which has not yet become a `MediaReference`,
    /// so it is read here rather than inferred from the absence of rows.
    @ObservedObject private var inbox = InboxManifest.shared

    /// The foot-of-sheet state line, or nil when nothing is arriving.
    private var arriving: String? { Self.arrivingLine(clips: inbox.clips) }

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
            VStack(spacing: 0) {
                Group {
                    // F22: `looseClips` is a live fetch over CloudKit-synced
                    // `MediaReference`s, so on a fresh install it is empty until
                    // the import lands. Secondary surface — say nothing while
                    // importing rather than claiming every clip is already placed.
                    if !looseClips.isEmpty {
                        clipList
                    } else if firstImport.mayAssertEmpty && arriving == nil {
                        // `arriving == nil` extends the SAME F22 rule the
                        // `mayAssertEmpty` gate encodes: don't assert emptiness
                        // while something is still on its way. Without it the
                        // empty state reads "Every clip you've captured is
                        // already in a memory" *while recordings are arriving*
                        // — a confident falsehood, the F6i `0:00` class. The
                        // arriving line below carries the true state instead.
                        emptyState
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let arriving {
                    arrivingFooter(arriving)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Crucible.Color.paper)
            .onAppear {
                // Refresh the thing that is about to be READ, rather than
                // relying on whatever happened to be running (CLAUDE.md §
                // Quieting a Busy Path). `looseClips` fetches zero-edge
                // `MediaReference`s; a Watch recording only becomes one once
                // the drain has run. The launch hook
                // (`LaunchScreenView.runMigration`) owns the one-shot
                // migration, but it runs once per launch and post-settle — so
                // a recording that finishes transcribing mid-session, and
                // whose on-arrival materialize did not land, would otherwise
                // not appear here until the next cold start.
                //
                // Cheap and idempotent: only `.transcribed` rows are
                // eligible and each is guarded by `refExists`.
                ArrivedClipMaterializer.materializeAll(in: StorageService.shared.viewContext)
            }
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

    /// The quiet foot-of-sheet line naming recordings that exist but are not
    /// yet selectable.
    ///
    /// **Why it exists.** This sheet lists zero-edge `MediaReference`s, and a
    /// Watch recording only becomes one once it has fully arrived and
    /// transcribed (`ArrivedClipMaterializer`). A recording still in flight is
    /// therefore absent from the list — which was fine while the bench showed
    /// arrival state, and is not fine once the bench is gone: she recorded
    /// something, it is not in the list, and nothing explains why. That is the
    /// "safe but unseen" failure in miniature (Tom, 2026-09-16).
    ///
    /// Posture matches the missing-media rule — **name the state, don't
    /// apologise for it**, and don't dramatise it: no spinner, no progress bar,
    /// no call to action. Returns `nil` when nothing is arriving, so the line
    /// is absent rather than reading "0".
    ///
    /// In-flight is every live manifest status except `.transcribed` (which
    /// drains into a ref and appears in the list above) and `.disposed` (a
    /// tombstone, not a recording).
    static func arrivingLine(clips: [InboxClip]) -> String? {
        // Exhaustive switch with no `default` ON PURPOSE: a new
        // `InboxClip.Status` must not silently pick a side here. Adding a case
        // breaks the build and forces the decision, rather than defaulting a
        // future state into (or out of) the count — the mechanism-over-rule
        // non-negotiable.
        let arriving = clips.filter { clip in
            switch clip.status {
            case .announced, .received, .transcribing: return true
            case .transcribed, .disposed:              return false
            }
        }.count
        guard arriving > 0 else { return nil }
        return "\(arriving) still arriving"
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

    /// The quiet state line for recordings that exist but are not yet
    /// selectable. Deliberately inert: no spinner, no progress bar, no action —
    /// it names the state and stops, per the missing-media posture (*"This
    /// recording was moved or deleted"*), which describes rather than
    /// apologises. Muted ink so it reads as a fact about the list, not a
    /// notice competing with it.
    private func arrivingFooter(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Crucible.Color.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 19)
            .padding(.vertical, 13)
            .background(Crucible.Color.paper)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Crucible.Color.hairline)
                    .frame(height: 1)
            }
            .accessibilityLabel(text)
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
