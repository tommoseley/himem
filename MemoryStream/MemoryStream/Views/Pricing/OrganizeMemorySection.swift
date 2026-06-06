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
        .sheet(isPresented: $showReorganizeSheet) {
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

    /// Commits the user's per-field choices from the Reorganize sheet.
    /// For each field where the user kept current, overwrite the new
    /// pass's value so the latest `OrganizePass` always represents the
    /// memory's *current* state (no stored v1 vs v2). For each field
    /// where the user opted into the new wording, the new pass already
    /// holds it — for the title, also write through to `entry.title`.
    private func handleReorganizeKeep(titleChoice: ReorgFieldChoice, summaryChoice: ReorgFieldChoice) {
        guard let entry, let pass else { return }
        let ctx = pass.managedObjectContext ?? StorageService.shared.viewContext
        ctx.performAndWait {
            switch titleChoice {
            case .new:
                if let newTitle = pass.suggestedTitle, !newTitle.isEmpty {
                    entry.title = newTitle
                    entry.titleSourcedFromAI = true
                }
            case .current:
                // User kept current — overwrite pass.suggestedTitle so
                // the latest pass reflects what's actually shown.
                pass.suggestedTitle = entry.title
            }
            switch summaryChoice {
            case .new:
                // Already on the new pass.
                break
            case .current:
                pass.summaryText = capturedCurrentSummary
            }
            pass.markRowsAccepted([.title, .summary])
            pass.dismissedAt = Date()
            try? ctx.save()
        }
        showReorganizeSheet = false
    }

    /// "Reorganize again" — fires another reorganize pass. The previous
    /// "new" pass becomes the new "current" (its values are what the
    /// sheet just showed). Sheet stays presented; FetchRequest will
    /// re-render with the fresh new pass once it writes.
    private func handleReorganizeAgain() {
        guard let entry, let pass else { return }
        // The pass shown as "new" in this round becomes the "current"
        // for the next round.
        capturedCurrentSummary = pass.summaryText ?? ""
        isReorganizing = true
        Task { @MainActor in
            await ProcessingEngine.shared.processReorganize(entry)
            isReorganizing = false
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
