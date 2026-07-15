import SwiftUI

/// The Captured Clips workbench Sort layer. Renders the confident
/// cluster proposals above the loose session list, with a bottom
/// ochre commit bar. Per `docs/design/Captured Clips · session-first
/// · spec.md` v3 § "The workbench + Sort":
///
/// - Cluster cards: AI-blue reason band, cluster name + preview
///   lines, one quiet-blue "Not together" secondary (dismiss →
///   clips fall back to loose). The card body is non-interactive —
///   no tap it can't honor. `Adjust` is deliberately NOT rendered
///   in v1: no cluster editor exists behind it, and a dead
///   interactive control violates the affordance invariant. It
///   returns only if the post-v1 editor is pulled forward
///   ([DECISION → Tom]).
/// - Bottom bar: "Keep these · N memories" — the ONE ochre moment
///   on the workbench. One tap → each cluster becomes its own
///   draft Memory (spec § 74: no confirmation sheet after).
///
/// The view is stateless over its inputs. `SessionListView` owns
/// the proposal set + wiring; this view just renders and calls
/// back on tap.
struct ClusterCardStack: View {

    /// The clusters to render, one card each. Ordered
    /// newest-cluster-first per the proposer.
    let proposals: [ClusterProposal]

    /// Called with a proposal when the user taps its *Not
    /// together* button. Caller adds it to the dismissal store.
    let onDismiss: (ClusterProposal) -> Void

    /// Called when the user taps the bottom "Keep these · N
    /// memories" bar. Fires the batch commit for all clusters
    /// currently on screen.
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

    // MARK: - Cluster card

    @ViewBuilder
    private func clusterCard(_ proposal: ClusterProposal) -> some View {
        VStack(spacing: 0) {
            // AI-blue reason band with sparkle glyph.
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

            VStack(alignment: .leading, spacing: 8) {
                Text(proposal.proposedName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink)
                if !proposal.previewLines.isEmpty {
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
                // One honest quiet-blue secondary: Not together (dismiss →
                // clips fall back to loose). No per-cluster ochre; commit
                // lives in the bottom bar. `Adjust` is deliberately NOT
                // rendered in v1 — there is no cluster editor behind it, and a
                // disabled interactive-looking control violates the affordance
                // invariant (interactive look = exactly one real job). It
                // returns only if the post-v1 cluster editor is pulled forward
                // ([DECISION → Tom]). v1 cluster interaction = two honest
                // paths: Keep these · N (commit) and Not together (dismiss).
                HStack(spacing: 18) {
                    Spacer()
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

    // MARK: - Commit bar

    private var commitBar: some View {
        Button {
            onCommitAll()
        } label: {
            HStack(spacing: 8) {
                Text(commitLabel)
                    .font(.system(size: 15.5, weight: .semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(Crucible.Color.accentInk)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Crucible.Color.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private var commitLabel: String {
        let noun = proposals.count == 1 ? "memory" : "memories"
        return "Keep these · \(proposals.count) \(noun)"
    }
}
