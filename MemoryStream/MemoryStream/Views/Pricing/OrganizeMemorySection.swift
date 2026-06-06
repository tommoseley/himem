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

    @ObservedObject private var entitlement = Entitlement.shared
    @FetchRequest private var entries: FetchedResults<JournalEntry>
    @State private var showReviewSheet = false
    @State private var showReorganizeSheet = false
    @State private var showPricing = false
    @State private var c1HasShown = UpgradeNudgeFlags.c1HasShown
    /// Reorganize in flight — disables the affordance and surfaces a
    /// spinner alongside the chip.
    @State private var isReorganizing = false
    /// Captured before firing a reorganize pass — the *previous* pass's
    /// summary, shown as "Current · kept" on the Reorganize sheet
    /// (since `entry.latestOrganizePass` becomes the *new* pass once
    /// processReorganize commits).
    @State private var capturedCurrentSummary: String = ""

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
        .sheet(isPresented: $showReorganizeSheet, onDismiss: handleReorganizeSheetDismissed) {
            if let entry, let pass {
                ReorganizeReviewSheet(
                    currentTitle: entry.title ?? "",
                    newTitle: pass.suggestedTitle ?? "",
                    currentSummary: capturedCurrentSummary,
                    newSummary: pass.summaryText ?? "",
                    onKeep: handleReorganizeKeep,
                    onReorganizeAgain: handleReorganizeAgain,
                    onDismiss: { showReorganizeSheet = false }
                )
                .presentationDetents([.large])
            }
        }
        .sheet(isPresented: $showPricing) {
            PricingView()
        }
    }

    // MARK: - Organized view

    @ViewBuilder
    private func organizedView(pass: OrganizePass, entry: JournalEntry) -> some View {
        // The summary and topic chips are rendered at the *top* of the
        // page by `EntryExpandedView.summarySection` / `topicChipsRow`
        // per `AI Organize · spec.md` §7.A. This section is just the
        // chip, the Reorganize affordance, and the review/stale/C1
        // hooks — no body content. Rendering body content here too
        // produced the duplicate summary + topic chip Tom flagged
        // 2026-06-06.
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
                if pass.isReviewed {
                    reorganizeButton(entry: entry)
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

            // C1 · After-a-glance nudge. Shown once-ever to Free
            // users right after they review their first draft —
            // never again inline. Per pricing-screens-upgrade.jsx.
            if pass.isReviewed && !entitlement.isPlus && !c1HasShown {
                AfterAGlanceNudge(
                    onSeePlus: handleSeePlus,
                    onNotNow: handleNudgeDismiss
                )
                .onAppear {
                    // Reading the nudge counts as "shown"; the flag
                    // sticks across launches via UserDefaults.
                    UpgradeNudgeFlags.markC1Shown()
                }
                Text("Shown once. Never again inline.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Crucible.Color.ink3)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Reorganize affordance

    @ViewBuilder
    private func reorganizeButton(entry: JournalEntry) -> some View {
        Button {
            handleReorganizeTap(entry: entry)
        } label: {
            HStack(spacing: 4) {
                if isReorganizing {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Crucible.Color.aiBlue)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(isReorganizing ? "Working…" : "Reorganize")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(Crucible.Color.aiBlue)
        }
        .buttonStyle(.plain)
        .disabled(isReorganizing)
        .accessibilityLabel(isReorganizing ? "Reorganizing" : "Reorganize this memory")
    }

    private func handleReorganizeTap(entry: JournalEntry) {
        guard let currentPass = pass else { return }
        // Capture the visible summary BEFORE the new pass overwrites
        // `latestOrganizePass`. The Reorganize sheet shows this as
        // "Current · kept" alongside the new pass's summary.
        capturedCurrentSummary = currentPass.summaryText ?? ""
        isReorganizing = true
        Task { @MainActor in
            await ProcessingEngine.shared.processReorganize(entry)
            isReorganizing = false
            showReorganizeSheet = true
        }
    }

    /// Commits the user's per-field choices via
    /// `OrganizePass.commitReorganize` (the pure value-shuffle) then
    /// saves. See that method's docstring for the per-field contract.
    private func handleReorganizeKeep(titleChoice: ReorgFieldChoice, summaryChoice: ReorgFieldChoice) {
        guard let entry, let pass else { return }
        let ctx = pass.managedObjectContext ?? StorageService.shared.viewContext
        ctx.performAndWait {
            pass.commitReorganize(
                on: entry,
                titleChoice: titleChoice,
                summaryChoice: summaryChoice,
                previousSummary: capturedCurrentSummary
            )
            try? ctx.save()
        }
        showReorganizeSheet = false
    }

    /// "Reorganize again" — fires another reorganize pass. The previous
    /// "new" pass (the one the user just rejected by tapping again) is
    /// discarded after the next pass lands, per `AI Organize · spec.md`
    /// §8.0: *"Reorganize replaces the draft; it never branches. There
    /// is never a stored v1 vs v2."*
    ///
    /// Discard order matters: we let the new pass write *first*, then
    /// delete the old, so `latestOrganizePass` never falls back to the
    /// previous committed pass during the transition (which would
    /// briefly mis-render the sheet's "new" half).
    private func handleReorganizeAgain() {
        guard let entry, let pass else { return }
        // The pass shown as "new" in this round becomes the "current"
        // for the next round.
        capturedCurrentSummary = pass.summaryText ?? ""
        let supersededID = pass.objectID
        isReorganizing = true
        Task { @MainActor in
            await ProcessingEngine.shared.processReorganize(entry)
            await discardPass(objectID: supersededID)
            isReorganizing = false
        }
    }

    /// Called when the Reorganize sheet finishes presenting. If the
    /// user committed (Keep this version), `handleReorganizeKeep` will
    /// have marked the latest pass reviewed before this fires — that
    /// pass is kept. If the user dismissed without committing (X, swipe
    /// down, or any other cancel path), the latest pass is an orphan
    /// draft and gets discarded so the memory returns cleanly to its
    /// prior Organized state.
    private func handleReorganizeSheetDismissed() {
        guard let pass, !pass.isReviewed else { return }
        let id = pass.objectID
        Task { @MainActor in
            await discardPass(objectID: id)
        }
    }

    /// Pure discard helper. No-op if the object can't be resolved
    /// (already deleted, or merged out from under us).
    private func discardPass(objectID: NSManagedObjectID) async {
        let ctx = StorageService.shared.viewContext
        await ctx.perform {
            if let toDelete = try? ctx.existingObject(with: objectID) {
                ctx.delete(toDelete)
                try? ctx.save()
            }
        }
    }

    private func handleSeePlus() {
        c1HasShown = true
        UpgradeNudgeFlags.markC1Shown()
        showPricing = true
    }

    private func handleNudgeDismiss() {
        c1HasShown = true
        UpgradeNudgeFlags.markC1Shown()
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
