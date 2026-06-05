import SwiftUI
import CoreData

/// State router for the Memory Detail AI zone after the assist-quota
/// retirement (PR 8d.2b).
///
///   • **No pass yet** — render `OrganizeMemoryCard(.idle)` so the
///     user can tap to run the on-device organize.
///   • **Has a draft (unreviewed) pass** — render `OrganizedChip` +
///     summary + topic chips + a *"Tap to review & keep"* link.
///     Tapping the chip or the link opens the B1 review sheet
///     (`DraftReviewSheet`). The user signs off there.
///   • **Has a reviewed pass** — render `OrganizedChip` + summary +
///     topic chips. No review CTA. If the entry has new clips since
///     the pass, surface a stale warning banner below per
///     `pricing-screens-lifecycle.jsx` Stage 3st — tapping fires a
///     re-organize.
struct OrganizeMemorySection: View {
    let entryID: UUID
    var onOrganize: () -> Void
    @Binding var unfolded: Bool  // Kept for EntryExpandedView API compat; unused after the AISuggestionsCard retirement.

    @FetchRequest private var entries: FetchedResults<JournalEntry>
    @State private var showReviewSheet = false

    init(
        entryID: UUID,
        unfolded: Binding<Bool>,
        onOrganize: @escaping () -> Void
    ) {
        self.entryID = entryID
        self._unfolded = unfolded
        self.onOrganize = onOrganize
        let request: NSFetchRequest<JournalEntry> = NSFetchRequest(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "id == %@", entryID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \JournalEntry.createdAt, ascending: false)]
        request.fetchLimit = 1
        _entries = FetchRequest(fetchRequest: request)
    }

    private var entry: JournalEntry? { entries.first }
    private var pass: OrganizePass? { entry?.latestOrganizePass }
    private var isStale: Bool { entry?.hasChangesSinceLastOrganize ?? false }
    private var isProcessing: Bool {
        switch entry?.latestProcessingTask?.statusEnum {
        case .pending, .processing: return true
        default: return false
        }
    }

    var body: some View {
        Group {
            if let entry, let pass {
                organizedView(pass: pass, entry: entry)
            } else if entry != nil {
                OrganizeMemoryCard(
                    state: .idle,
                    onOrganize: onOrganize,
                    isProcessing: isProcessing
                )
            } else {
                EmptyView()
            }
        }
        .sheet(isPresented: $showReviewSheet) {
            if let entry, let pass {
                DraftReviewSheet(
                    pass: pass,
                    entry: entry,
                    onDismiss: { showReviewSheet = false }
                )
                .presentationDetents([.large])
            }
        }
    }

    // MARK: - Organized view

    @ViewBuilder
    private func organizedView(pass: OrganizePass, entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 9) {
                Button {
                    if !pass.isReviewed { showReviewSheet = true }
                } label: {
                    OrganizedChip(pass: pass)
                }
                .buttonStyle(.plain)
                .disabled(pass.isReviewed)

                if !pass.isReviewed {
                    Circle()
                        .stroke(Crucible.Color.aiBlue, lineWidth: 1.5)
                        .frame(width: 7, height: 7)
                    Text("unreviewed")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Crucible.Color.ink3)
                }
                Spacer(minLength: 0)
            }

            if let summary = pass.summaryText, !summary.isEmpty {
                Text(SummaryRenderer.renderForOwner(summary))
                    .font(.system(size: 13))
                    .foregroundStyle(Crucible.Color.ink2)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            let topics = entry.topicsArray.map(\.name)
            if !topics.isEmpty {
                HStack(spacing: 6) {
                    ForEach(topics, id: \.self) { name in
                        Text(name)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Crucible.Color.ink2)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(Crucible.Color.wash1)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Crucible.Color.hairline, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Spacer(minLength: 0)
                }
            }

            if !pass.isReviewed {
                Button {
                    showReviewSheet = true
                } label: {
                    Text("Tap to review & keep →")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Crucible.Color.aiBlue)
                }
                .buttonStyle(.plain)
            }

            if pass.isReviewed && isStale {
                staleBanner(newClips: entry.clipsAddedSinceLastOrganize)
            }
        }
    }

    @ViewBuilder
    private func staleBanner(newClips: Int) -> some View {
        Button(action: handleRefresh) {
            HStack(spacing: 10) {
                Text(staleText(newClips: newClips))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Crucible.Color.warnInk)
                Spacer(minLength: 0)
                Text("Refresh")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Crucible.Color.warnInk)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Crucible.Color.warnTint)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Crucible.Color.warning.opacity(0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func staleText(newClips: Int) -> String {
        if newClips == 1 { return "1 new clip since this was organized" }
        return "\(newClips) new clips since this was organized"
    }

    private func handleRefresh() {
        onOrganize()
    }
}
