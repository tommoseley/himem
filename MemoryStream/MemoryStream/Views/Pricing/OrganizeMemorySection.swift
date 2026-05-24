import SwiftUI
import CoreData

/// State router for the Memory Detail AI zone (v5 design).
/// Picks the right surface for a given entry/pass/assist combo:
///
///   • **Idle** — never organized AND assists available
///     → `OrganizeMemoryCard.idle` (cream card, "1 ASSIST" pill)
///   • **Exhausted** — never organized AND no assists
///     → `OrganizeMemoryCard.exhausted` (muted card, "See options →")
///   • **Review** — organized AND `dismissedAt == nil`
///     → `AISuggestionsCard` always unfolded (no chip — this is the
///       primary "you should look at this" affordance)
///   • **Organized** — organized AND `dismissedAt != nil`
///     → `OrganizedChip` with accordion unfold of `AISuggestionsCard`.
///       The chip carries variant signal (refresh / next steps / default).
///       Folding/unfolding here is ephemeral local @State; the
///       `dismissedAt` data flag is sticky.
///
/// Routing prefers stale > organized > idle when multiple apply —
/// stale memories surface the refresh chip even after dismiss.
struct OrganizeMemorySection: View {
    let entryID: UUID
    var onOrganize: () -> Void
    var onOpenPackSheet: () -> Void
    /// Lifted from local @State so the parent (EntryExpandedView)
    /// can suppress the FAB while the AI Suggestions card is open.
    /// Folded state defaults to true on chip mode; tapping the chip
    /// unfolds; the card's × refolds. Independent of the sticky
    /// `dismissedAt` data flag.
    @Binding var unfolded: Bool

    @ObservedObject var entitlement: EntitlementService = .shared
    @FetchRequest private var entries: FetchedResults<JournalEntry>
    @State private var showStarterCard = false

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
    private var hasAssists: Bool { entitlement.totalAssistsRemaining > 0 }
    private var isPlus: Bool { entitlement.isPlus }
    private var isStale: Bool { entry?.hasChangesSinceLastOrganize ?? false }
    /// True while the entry's latest processing task is in flight.
    /// Drives the spinner in both the idle-state organize card and
    /// the AISuggestionsCard ribbon (where the card surfaces it
    /// itself off the same entry).
    private var isProcessing: Bool {
        switch entry?.latestProcessingTask?.statusEnum {
        case .pending, .processing: return true
        default: return false
        }
    }

    var body: some View {
        Group {
            if let entry, let pass {
                if pass.dismissedAt == nil {
                    // Review state — card always unfolded.
                    AISuggestionsCard(
                        pass: pass,
                        entry: entry,
                        isStale: isStale,
                        canRefresh: hasAssists,
                        onRefresh: handleRefresh,
                        onDismiss: handleDismiss,
                        onOpenPackSheet: onOpenPackSheet
                    )
                } else {
                    // Organized state — chip with accordion unfold.
                    organizedAccordion(pass: pass, entry: entry)
                }
            } else if entry != nil {
                // Idle / Exhausted — never organized.
                OrganizeMemoryCard(
                    state: hasAssists ? .idle : .exhausted,
                    resetDate: entitlement.monthlyResetDate,
                    onOrganize: handleOrganizeTap,
                    onSeeOptions: onOpenPackSheet,
                    isProcessing: isProcessing
                )
            } else {
                EmptyView()
            }
        }
        .sheet(isPresented: $showStarterCard) {
            OnboardingStarterCard(onTry: onOrganize)
                .presentationDetents([.large])
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
                canRefresh: hasAssists,
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
                OrganizedChip(pass: pass, isStale: isStale, canRefresh: hasAssists)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Behavior

    private func handleOrganizeTap() {
        if !entitlement.starterGranted && !isPlus {
            showStarterCard = true
            return
        }
        onOrganize()
    }

    private func handleDismiss() {
        guard let pass else { return }
        let ctx = pass.managedObjectContext ?? StorageService.shared.viewContext
        ctx.performAndWait {
            pass.dismissedAt = Date()
            try? ctx.save()
        }
        // Once dismissed, the next render will fall into Organized
        // state; the chip + folded card is the rest position.
        unfolded = false
    }

    private func handleRefresh() {
        // A successful refresh is a new OrganizePass (`dismissedAt == nil`
        // by default) — the next render will be Review again. The
        // assist deduct happens inside ProcessingEngine.processEntry
        // on success.
        onOrganize()
    }
}
