import SwiftUI

/// The Captured Clips workbench Sort layer. Renders the confident
/// cluster proposals above the loose session list, with a bottom ochre
/// commit bar. Per `docs/design/Captured Clips · session-first ·
/// spec.md` v3 § "The workbench + Sort" and §87:
///
/// - **Collapsed card:** AI-blue reason band, cluster name + preview
///   lines, one quiet-blue "Not together" secondary (dismiss → clips
///   fall back to loose).
/// - **Adjust / card-body tap → the minimal editor (§87, ruling
///   2026-07-15):** expands the card in place, every member clip as a
///   `ClipAtomView` row with a subtractive `Remove`. A removed clip drops
///   to a quiet "Not in this memory" set-aside within the card,
///   reversible via `Add back` — trims are provisional until commit
///   (Model A: the card *is* the review, commit is the decision). No
///   pull-in, no ring; subtractive only.
/// - **Bottom bar: "Keep these · N memories"** — the ONE ochre moment.
///   `N` updates live as clusters are trimmed; a cluster trimmed to empty
///   drops out of the count and the commit; all-empty disables the commit
///   (never commit an empty memory).
///
/// Stateless over its inputs — `SessionListView` owns the trim state
/// (`removedByFingerprint`, `expandedFingerprints`) + all wiring; this
/// view renders and calls back on tap.
/// Copy for the cluster proposal card. Design authority; the wording IS
/// the promise, so `BenchCountAndProposalCopyTests` pins it.
enum ClusterCardCopy {
    /// **Ruled 2026-08-02 (F39).** The weakest honest framing: it observes
    /// that these *might* go together and never asserts that they do.
    ///
    /// "These may **belong** together" was rejected — J5 forbids the
    /// interpretive verb. The AI may say what it measured (same place,
    /// minutes apart); it may not say what that means. A wrong grouping is
    /// not a neutral miss, it asserts a relationship the user cannot cheaply
    /// verify.
    static let mightGoTogether = "Might go together"

    /// **F42, ruled 2026-08-02.** The section heading above the cards, which
    /// is the louder of the two lines and said "seem to **belong** together"
    /// until now. Same observation-not-conclusion rule as the eyebrow: the
    /// AI may report that these were near each other; it may not say they
    /// belong.
    static let sectionHeading = "A few of these might go together"
}

struct ClusterCardStack: View {

    /// The clusters to render, one card each. Ordered
    /// newest-cluster-first per the proposer.
    let proposals: [ClusterProposal]

    /// Resolves a proposal's member clips (kept + removed) for the
    /// expanded editor rows. Ordered by the proposal's `clipIds`.
    let clipsFor: (ClusterProposal) -> [InboxClip]

    /// **F40 · the absorbed photos/videos of the sessions this proposal
    /// consumed** (2026-08-02).
    ///
    /// A proposal is built from WHOLE sessions (`makeTimePlaceProposal`
    /// flatMaps `sessions.flatMap(\.clips)`), and absorbed media used to
    /// render only inside session cards. So when a cluster consumed every
    /// session, its photos had nowhere to appear at all — counted in the
    /// header, drawn by nothing. Mirrors `clipsFor`, deliberately, rather
    /// than minting a second lookup shape.
    let mediaFor: (ClusterProposal) -> [MediaReference]

    /// Fingerprint `rawValue`s whose cards are expanded into the editor.
    let expandedFingerprints: Set<String>

    /// Per-fingerprint set of removed clipIds — the transient trim.
    let removedByFingerprint: [String: Set<UUID>]

    /// `Adjust` / card-body tap — toggle the editor for this cluster.
    let onToggleExpand: (ClusterProposal) -> Void

    /// `Remove` on a kept row — set the clip aside (per-clip "Not
    /// together"). Caller records it in `removedByFingerprint`.
    let onRemoveClip: (ClusterProposal, UUID) -> Void

    /// `Add back` on a set-aside row — undo the trim.
    let onReAddClip: (ClusterProposal, UUID) -> Void

    /// Opens the unified Clip Editor modal — fired ONLY by the boxed ✎ Edit
    /// button (2026-07-17: ✎ Edit is the one edit affordance everywhere;
    /// supersedes Finding 3's row-tap-opens-modal). Play/Remove stay
    /// independent; the row tap/chevron expands-to-read in place (accordion).
    let onOpenClip: (ClipEditorModal.Source) -> Void

    /// Single-open accordion — the clipId whose transcript is expanded in
    /// place (nil = all collapsed). Container-owned by `SessionListView`.
    let openClipId: UUID?

    /// Tap a compact row / chevron — toggle its transcript open (single-open:
    /// opening one collapses the prior). Reading only — editing is ✎ Edit.
    let onToggleClusterClip: (UUID) -> Void

    /// `Not together` — dismiss the whole cluster. Caller adds it to the
    /// dismissal store; its clips fall back to loose.
    let onDismiss: (ClusterProposal) -> Void

    /// `Keep these · N memories` — batch-commit every cluster's *kept*
    /// clips. Fires only when at least one cluster has a kept clip.
    /// `Add to a memory…` — the placement action for a single cluster's kept
    /// clips (set-aside excluded). Opens the shared placement sheet (New
    /// memory / add to existing) with the cluster's title prefilled. This is
    /// the ONLY commit — the batch "Keep these · N" bar is retired (2026-07-17,
    /// §Sort). Present on the collapsed teaser and the expanded card.
    let onAddToMemory: (ClusterProposal) -> Void

    /// Per-cluster Compact/Full display mode (§90). Keyed by fingerprint;
    /// absent → the multi-clip default of **Compact** (a big cluster must
    /// never open as a wall of text). Display-only, not persisted.
    @State private var clusterModes: [String: TranscriptMode] = [:]

    private func mode(for proposal: ClusterProposal) -> TranscriptMode {
        clusterModes[proposal.fingerprint.rawValue] ?? .compact
    }
    private func modeBinding(for proposal: ClusterProposal) -> Binding<TranscriptMode> {
        Binding(
            get: { clusterModes[proposal.fingerprint.rawValue] ?? .compact },
            set: { clusterModes[proposal.fingerprint.rawValue] = $0 }
        )
    }

    var body: some View {
        if proposals.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 12) {
                sectionHeader
                ForEach(proposals, id: \.fingerprint.rawValue) { proposal in
                    clusterCard(proposal)
                }
            }
            .padding(.bottom, 12)
        }
    }

    /// Per-media glyphs + counts for media absorbed by this proposal's
    /// sessions — the same composition vocabulary the session card uses
    /// (`mic 2 · camera 1`), never a flat "N clips".
    private func clusterMediaRow(_ media: [MediaReference]) -> some View {
        let photos = media.filter { $0.mediaTypeEnum == .image }.count
        let videos = media.filter { $0.mediaTypeEnum == .video }.count
        return HStack(spacing: 10) {
            if photos > 0 {
                Label("\(photos)", systemImage: "camera")
                    .labelStyle(.titleAndIcon)
            }
            if videos > 0 {
                Label("\(videos)", systemImage: "video")
                    .labelStyle(.titleAndIcon)
            }
            Spacer()
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Crucible.Color.ink2)
    }

    // MARK: - Section header

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            // F42 · "belong" is J5's forbidden interpretive verb, and it
            // survived F39 on the LOUDER line. F39 guarded the card's
            // eyebrow — the owner — and never checked the caller's own
            // heading. Fourth self-reproduction of guard-the-caller on this
            // branch, committed inside the fix for the rule it violates.
            Text(ClusterCardCopy.sectionHeading)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink)
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Per-cluster state readers

    private func isExpanded(_ p: ClusterProposal) -> Bool {
        expandedFingerprints.contains(p.fingerprint.rawValue)
    }

    private func removedSet(_ p: ClusterProposal) -> Set<UUID> {
        removedByFingerprint[p.fingerprint.rawValue] ?? []
    }

    // MARK: - Cluster card

    @ViewBuilder
    private func clusterCard(_ proposal: ClusterProposal) -> some View {
        let expanded = isExpanded(proposal)
        VStack(spacing: 0) {
            reasonBand(proposal)

            VStack(alignment: .leading, spacing: 8) {
                // F39 · the card must say it is a PROPOSAL. Without this it
                // is indistinguishable from a session card — the designer who
                // wrote the spec read one as a grouping error. An eyebrow is
                // the smallest cue that changes what the card claims; the
                // session card has none, so its presence is itself the tell.
                Text(ClusterCardCopy.mightGoTogether)
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(Crucible.Color.ink3)
                // Name row — a card-body tap toggles the editor (§87). When
                // expanded, the Compact/Full toggle (§90) sits right-aligned
                // on the title row (reused from Memory Detail, not minted).
                HStack(spacing: 8) {
                    Button {
                        onToggleExpand(proposal)
                    } label: {
                        Text(proposal.proposedName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Crucible.Color.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if expanded {
                        TranscriptModeToggle(mode: modeBinding(for: proposal))
                    }
                }

                // F40 · the media of the sessions this proposal consumed.
                // Without this the photos are invisible whenever a cluster
                // takes the whole bench — the user captured them and they
                // appear nowhere.
                if !mediaFor(proposal).isEmpty {
                    clusterMediaRow(mediaFor(proposal))
                }

                if expanded {
                    editorRows(proposal, mode: mode(for: proposal))
                } else if !proposal.previewLines.isEmpty {
                    previewLinesView(proposal)
                }

                secondaryRow(proposal, expanded: expanded)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Crucible.Color.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Crucible.Color.aiEdge, lineWidth: 1)
        )
        // The WHOLE collapsed card (head + title + teaser rows) expands — no
        // hidden title-tap dependency (2026-07-17). The "Show all N" cue names
        // it. Inner Buttons ("Show all", "Not together") still win their own
        // taps; a tap anywhere else on the collapsed card expands. When
        // expanded, the background tap is inert — the ✎/⊖/toggle/rows and
        // "Done" own interaction.
        .contentShape(Rectangle())
        .onTapGesture { if !expanded { onToggleExpand(proposal) } }
    }

    private func reasonBand(_ proposal: ClusterProposal) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
            Text(proposal.whyText)
                .font(.system(size: 11.5, weight: .semibold))
            Spacer()
        }
        .foregroundStyle(Crucible.Color.aiBlue)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Crucible.Color.aiBlueTint)
    }

    // MARK: - Collapsed preview

    private func previewLinesView(_ proposal: ClusterProposal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(proposal.previewLines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 8) {
                    Text(line.timeLabel)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Crucible.Color.ink3)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .leading)
                    Text(line.transcriptSnippet)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Crucible.Color.ink2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Expanded editor (§87 · subtractive, expand-in-place)

    @ViewBuilder
    private func editorRows(_ proposal: ClusterProposal, mode: TranscriptMode) -> some View {
        let clips = clipsFor(proposal)
        let removed = removedSet(proposal)
        let anchor = clips.map(\.capturedAt).min() ?? Date()
        let kept = clips.filter { !removed.contains($0.clipId) }
        let gone = clips.filter { removed.contains($0.clipId) }

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(kept.enumerated()), id: \.element.clipId) { idx, clip in
                if idx > 0 { rowDivider }
                clipEditorRow(proposal: proposal, clip: clip, anchor: anchor, isRemoved: false, mode: mode)
            }
            if !gone.isEmpty {
                Rectangle()
                    .fill(Crucible.Color.hairline)
                    .frame(height: 0.5)
                    .padding(.vertical, 8)
                Text("Not in this memory")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink3)
                    .padding(.bottom, 2)
                ForEach(Array(gone.enumerated()), id: \.element.clipId) { idx, clip in
                    if idx > 0 { rowDivider }
                    clipEditorRow(proposal: proposal, clip: clip, anchor: anchor, isRemoved: true, mode: mode)
                }
            }
        }
        .padding(.top, 2)
    }

    private var rowDivider: some View {
        Rectangle().fill(Crucible.Color.hairline).frame(height: 0.5)
    }

    /// One clip as a **compact single-open accordion row** (§89). Layout:
    /// glyph · time · one-line preview · **boxed ✎ pencil** · Remove. Row tap
    /// expands the transcript in place (reading, single-open); the boxed ✎
    /// pencil is the one edit affordance → the unified modal, where playback +
    /// scrub live (no inline Play on cluster rows, 2026-07-17). Set-aside rows
    /// dim the **content only** — Edit/Add-back stay full-strength.
    @ViewBuilder
    private func clipEditorRow(proposal: ClusterProposal, clip: InboxClip, anchor: Date, isRemoved: Bool, mode: TranscriptMode) -> some View {
        let model = ClipDisplayModel(inboxClip: clip, sessionStart: anchor)
        let isOpen = openClipId == clip.clipId
        let transcript = clip.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        // Full → every transcript wrapped, always. Compact → single-line
        // preview + per-row accordion (§90).
        let isFull = mode == .full
        let showTranscript = isFull || isOpen

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // Compact: row tap → expand-to-read (accordion). Full: the
                // transcript is always shown below, so the row isn't a toggle.
                ClipAtomView(model: model,
                             register: .reflectiveCompact,
                             onTapContent: isFull ? nil : { onToggleClusterClip(clip.clipId) },
                             isEmphasized: isOpen,
                             hidePreview: showTranscript)
                    .opacity(isRemoved ? 0.45 : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // The one edit affordance — boxed ✎ pencil → modal (playback +
                // scrub live in the modal, matching Memory Detail Compact;
                // inline Play removed from cluster rows 2026-07-17).
                ClipEditButton(action: { onOpenClip(.inbox(clip)) })

                // Subtractive set-aside (§187) — a boxed ⊖ / ⊕ icon beside the
                // pencil (✎ ⊖). minus.circle = set-aside, plus.circle = Add
                // back. NOT a trash can: this trims cluster membership, it
                // never deletes the clip (Delete lives in the modal).
                RowIconButton(
                    systemName: isRemoved ? "plus.circle" : "minus.circle",
                    tint: Crucible.Color.ink3,
                    accessibilityLabel: isRemoved ? "Add back to this memory" : "Set aside from this memory"
                ) {
                    if isRemoved { onReAddClip(proposal, clip.clipId) }
                    else { onRemoveClip(proposal, clip.clipId) }
                }
            }

            // Full transcript in place (read-only — editing is ✎). Shown on
            // accordion-open (Compact) or always (Full).
            if showTranscript && !transcript.isEmpty {
                Text("\u{201C}\(transcript)\u{201D}")
                    .font(.system(size: 14))
                    .lineSpacing(2)
                    .foregroundStyle(Crucible.Color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(isRemoved ? 0.45 : 1)
                    .padding(.bottom, 8)
                    .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Secondary row (Adjust toggle + Not together)

    private func secondaryRow(_ proposal: ClusterProposal, expanded: Bool) -> some View {
        // Bottom row: Show all N ⌄ · Add to a memory… · Not together — on both
        // the collapsed teaser and the expanded card. "Add to a memory…" is
        // the placement action (the batch commit bar is retired).
        HStack(spacing: 18) {
            Spacer()
            Button {
                onToggleExpand(proposal)
            } label: {
                // The disclosure names what it reveals: collapsed →
                // "Show all N ⌄" (expand to the full clip list + trim);
                // expanded → "Done ⌃" (collapse back to the teaser). "Adjust"
                // is retired — editing (✎), trim (⊖), and the Compact/Full
                // toggle all live inside the expanded state, not the teaser.
                // "Done" = collapse, NOT commit — the ochre "Keep these · N"
                // is the only commit.
                HStack(spacing: 3) {
                    Text(expanded ? "Done" : "Show all \(proposal.clipIds.count)")
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Crucible.Color.aiBlue)
            }
            .buttonStyle(.plain)
            // The placement action — opens the shared sheet (New memory / add
            // to existing) on the cluster's kept clips, title prefilled.
            Button {
                onAddToMemory(proposal)
            } label: {
                Text("Add to a memory…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Crucible.Color.aiBlue)
            }
            .buttonStyle(.plain)
            Button {
                onDismiss(proposal)
            } label: {
                Text("Not together")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Crucible.Color.aiBlue)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }
}
