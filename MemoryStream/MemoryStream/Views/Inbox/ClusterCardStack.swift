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
struct ClusterCardStack: View {

    /// The clusters to render, one card each. Ordered
    /// newest-cluster-first per the proposer.
    let proposals: [ClusterProposal]

    /// Resolves a proposal's member clips (kept + removed) for the
    /// expanded editor rows. Ordered by the proposal's `clipIds`.
    let clipsFor: (ClusterProposal) -> [InboxClip]

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

    /// Tap a compact row — open the unified Clip Editor modal for that clip
    /// (Finding 3, 2026-07-16: the chevron promises tap-to-open, so honor it;
    /// brought forward now that the modal exists — supersedes the in-place
    /// transcript accordion and the post-v1 "row-tap → Clip Detail" deferral,
    /// matching the session rows cycle 2 already wired). Play/Remove stay
    /// independent controls on the row.
    let onOpenClip: (ClipEditorModal.Source) -> Void

    /// Play/stop a clip's audio from its compact row.
    let onPlayClip: (InboxClip) -> Void

    /// The currently-playing clipId — drives the play/stop glyph.
    let playingClipId: UUID?

    /// `Not together` — dismiss the whole cluster. Caller adds it to the
    /// dismissal store; its clips fall back to loose.
    let onDismiss: (ClusterProposal) -> Void

    /// `Keep these · N memories` — batch-commit every cluster's *kept*
    /// clips. Fires only when at least one cluster has a kept clip.
    let onCommitAll: () -> Void

    var body: some View {
        if proposals.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 12) {
                sectionHeader
                ForEach(proposals, id: \.fingerprint.rawValue) { proposal in
                    clusterCard(proposal)
                }
                commitBar
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: - Section header

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            Text("A few of these seem to belong together")
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
                // Name row — a card-body tap toggles the editor (§87).
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
                    editorRows(proposal)
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
    private func editorRows(_ proposal: ClusterProposal) -> some View {
        let clips = clipsFor(proposal)
        let removed = removedSet(proposal)
        let anchor = clips.map(\.capturedAt).min() ?? Date()
        let kept = clips.filter { !removed.contains($0.clipId) }
        let gone = clips.filter { removed.contains($0.clipId) }

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(kept.enumerated()), id: \.element.clipId) { idx, clip in
                if idx > 0 { rowDivider }
                clipEditorRow(proposal: proposal, clip: clip, anchor: anchor, isRemoved: false)
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
                    clipEditorRow(proposal: proposal, clip: clip, anchor: anchor, isRemoved: true)
                }
            }
        }
        .padding(.top, 2)
    }

    private var rowDivider: some View {
        Rectangle().fill(Crucible.Color.hairline).frame(height: 0.5)
    }

    /// One clip as a **compact reflective row** (§87). Layout: glyph + time +
    /// one-line preview + play + Remove + chevron. Tapping the row opens the
    /// unified Clip Editor modal (Finding 3, 2026-07-16 — the chevron is a
    /// tap-to-open promise; the in-place transcript accordion is retired now
    /// that the modal reads *and* edits the clip). Set-aside rows dim the
    /// **content only** — play/Add-back stay full-strength at ≥44px.
    @ViewBuilder
    private func clipEditorRow(proposal: ClusterProposal, clip: InboxClip, anchor: Date, isRemoved: Bool) -> some View {
        let model = ClipDisplayModel(inboxClip: clip, sessionStart: anchor)
        let isPlaying = playingClipId == clip.clipId
        let hasAudio = !clip.audioFilename.isEmpty

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // Tappable compact header → open the modal. The chevron is a
                // static navigation affordance (→), not a disclosure — it no
                // longer rotates, because the tap opens the clip rather than
                // expanding it in place.
                Button {
                    onOpenClip(.inbox(clip))
                } label: {
                    HStack(spacing: 6) {
                        ClipAtomView(model: model,
                                     register: .reflectiveCompact)
                            .opacity(isRemoved ? 0.45 : 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Crucible.Color.ink3)
                    }
                    .frame(minHeight: 44)      // Crucible 44px hit floor
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if hasAudio {
                    Button {
                        onPlayClip(clip)
                    } label: {
                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Crucible.Color.accent)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                // Subtractive vocabulary (§187): Remove / reversible Add
                // back. Full-strength, ≥44px even when content is dimmed.
                Button {
                    if isRemoved { onReAddClip(proposal, clip.clipId) }
                    else { onRemoveClip(proposal, clip.clipId) }
                } label: {
                    Text(isRemoved ? "Add back" : "Remove")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Crucible.Color.aiBlue)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Secondary row (Adjust toggle + Not together)

    private func secondaryRow(_ proposal: ClusterProposal, expanded: Bool) -> some View {
        HStack(spacing: 18) {
            Spacer()
            Button {
                onToggleExpand(proposal)
            } label: {
                // State-driven toggle — names the action it performs:
                // collapsed → "Adjust ⌄" (expand into trim); expanded →
                // "Done ⌃" (collapse back to preview). "Done" = collapse,
                // NOT commit — the ochre "Keep these · N" is the only commit.
                HStack(spacing: 3) {
                    Text(expanded ? "Done" : "Adjust")
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
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

    // MARK: - Commit bar (live N, disabled when nothing kept)

    private var committableCount: Int {
        ClusterTrim.committableCount(proposals: proposals, removedByFingerprint: removedByFingerprint)
    }

    private var commitBar: some View {
        let n = committableCount
        let disabled = n == 0
        return Button {
            if !disabled { onCommitAll() }
        } label: {
            HStack(spacing: 8) {
                Text(commitLabel(n))
                    .font(.system(size: 15.5, weight: .semibold))
                if !disabled {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .foregroundStyle(Crucible.Color.accentInk)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Crucible.Color.accent.opacity(disabled ? 0.4 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .padding(.top, 4)
    }

    private func commitLabel(_ n: Int) -> String {
        guard n > 0 else { return "Nothing found to keep" }
        let noun = n == 1 ? "memory" : "memories"
        return "Keep these · \(n) \(noun)"
    }
}
