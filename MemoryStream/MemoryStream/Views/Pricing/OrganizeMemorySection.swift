import SwiftUI
import CoreData

/// State router for the Memory Detail AI zone (post-assist-quota
/// retirement, PR 8c).
///
///   • **No pass yet** — render `OrganizeMemoryCard(.idle)`. Free
///     users tap to run the on-device organize; Plus users normally
///     see the pass appear automatically because the auto-organize
///     pipeline fires on capture.
///   • **Has a draft (unreviewed) pass** — `pass.isReviewed == false`.
///     The review surface (still `AISuggestionsCard` in 8c, replaced
///     in 8d with the B1 review sheet) is always visible so the user
///     can glance at the draft and accept or edit.
///   • **Has a reviewed pass** — `pass.isReviewed == true`. Show the
///     `OrganizedChip` with accordion unfold to the same review
///     surface. The chip's solid border + check icon signal the
///     user-confirmed state.
///
/// Stale (`entry.hasChangesSinceLastOrganize`) is now an orthogonal
/// concern surfaced as a warning banner alongside the chip per
/// `pricing-screens-lifecycle.jsx` Stage 3st — not a chip variant.
struct OrganizeMemorySection: View {
    let entryID: UUID
    var onOrganize: () -> Void
    /// Routes upgrade nudges (currently consumed by AISuggestionsCard
    /// for its "Out of assists · See plans" affordance). Will be
    /// repointed at the new PricingView in 8f; kept on the API for
    /// the 8c → 8f transition.
    var onOpenPackSheet: () -> Void
    /// Lifted from local @State so the parent (EntryExpandedView)
    /// can suppress the FAB while the AI Suggestions card is open.
    /// Folded state defaults to true on chip mode; tapping the chip
    /// unfolds; the card's × refolds. Independent of the sticky
    /// `dismissedAt` data flag.
    @Binding var unfolded: Bool

    @FetchRequest private var entries: FetchedResults<JournalEntry>

    init(
        entryID: UUID,
        unfolded: Binding<Bool>,
        onOrganize: @escaping () -> Void,
        onOpenPackSheet: @escaping () -> Void
    ) {
        self.entryID = entryID
        self._unfolded = unfolded
        self.onOrganize = onOrganize
        self.onOpenPackSheet = onOpenPackSheet
        let request: NSFetchRequest<JournalEntry> = NSFetchRequest(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "id == %@", entryID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \JournalEntry.createdAt, ascending: false)]
        request.fetchLimit = 1
        _entries = FetchRequest(fetchRequest: request)
    }

    private var entry: JournalEntry? { entries.first }
    private var pass: OrganizePass? { entry?.latestOrganizePass }
    private var isStale: Bool { entry?.hasChangesSinceLastOrganize ?? false }
    /// True while the entry's latest processing task is in flight.
    /// Drives the spinner in both the idle organize card and the
    /// AISuggestionsCard ribbon (where the card surfaces it itself
    /// off the same entry).
    private var isProcessing: Bool {
        switch entry?.latestProcessingTask?.statusEnum {
        case .pending, .processing: return true
        default: return false
        }
    }

    var body: some View {
        Group {
            if let entry, let pass {
                if !pass.isReviewed {
                    // Draft state — review surface always visible.
                    AISuggestionsCard(
                        pass: pass,
                        entry: entry,
                        isStale: isStale,
                        canRefresh: true,
                        onRefresh: handleRefresh,
                        onDismiss: handleDismiss,
                        onOpenPackSheet: onOpenPackSheet
                    )
                } else {
                    // Organized state — chip with accordion unfold.
                    organizedAccordion(pass: pass, entry: entry)
                }
            } else if entry != nil {
                // Never organized — show manual Organize button.
                OrganizeMemoryCard(
                    state: .idle,
                    onOrganize: onOrganize,
                    isProcessing: isProcessing
                )
            } else {
                EmptyView()
            }
        }
    }

    // MARK: - Organized accordion

    @ViewBuilder
    private func organizedAccordion(pass: OrganizePass, entry: JournalEntry) -> some View {
        // One affordance visible at a time. Folded: chip only —
        // tap to open. Unfolded: card only — × to close. The chip
        // doesn't lie about its function because it's not visible
        // when the card is already open.
        if unfolded {
            AISuggestionsCard(
                pass: pass,
                entry: entry,
                isStale: isStale,
                canRefresh: true,
                onRefresh: handleRefresh,
                onDismiss: { withAnimation(.easeInOut(duration: 0.2)) { unfolded = false } },
                onOpenPackSheet: onOpenPackSheet
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    unfolded = true
                }
            } label: {
                OrganizedChip(pass: pass)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Behavior

    private func handleDismiss() {
        guard let pass else { return }
        let ctx = pass.managedObjectContext ?? StorageService.shared.viewContext
        ctx.performAndWait {
            pass.dismissedAt = Date()
            try? ctx.save()
        }
        // Once dismissed, isReviewed flips true and the next render
        // falls into the Organized state; the chip + folded card is
        // the rest position.
        unfolded = false
    }

    private func handleRefresh() {
        // A successful refresh is a new OrganizePass (dismissedAt nil,
        // acceptedRows empty by default) — the next render will be
        // Draft again.
        onOrganize()
    }
}
