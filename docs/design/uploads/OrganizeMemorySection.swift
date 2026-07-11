import SwiftUI
import CoreData

/// The Memory Detail AI zone — status chip, action button, stale
/// banner, C1 upgrade nudge. Spec: `AI Organize · spec.md` §7–§9.
///
/// **Single source of truth** for what to render: `AIState`, derived
/// from `(entry, latestOrganizePass)` on every body eval. No `@State`
/// mirrors of Core Data, no flag-juggling between sheets. The current
/// state — idle / draft (initial or reorganize) / organized — is a
/// function of the model.
///
/// **Single sheet binding.** One `@State activeSheet: ActiveSheet?`
/// drives `.sheet(item:)`. Multi-`.sheet(isPresented:)` stacking was
/// the cause of the rise-and-fall race (June 12 2026): each modifier
/// fights for the same UIViewController stack, and a sibling cover
/// (the AppendFAB voice capture, or the TutorialAutoFireOverlay) wins
/// arbitration while the new sheet is mid-animation. `.sheet(item:)`
/// with a unique id per sheet kind lets SwiftUI serialize cleanly.
///
/// **Dismiss = decide later (spec §8.0 June 12).** Closing the
/// Reorganize sheet without committing leaves the draft as `isReviewed
/// == false`. The same `Review draft` button re-opens it. The only
/// ways a draft goes away are (a) commit via `Keep this version`, or
/// (b) `Reorganize again` from inside the sheet, which replaces it.
struct OrganizeMemorySection: View {
    let entryID: UUID
    var onOrganize: () -> Void

    @ObservedObject private var entitlement = Entitlement.shared
    @FetchRequest private var entries: FetchedResults<JournalEntry>

    /// The one modal binding. `nil` = no sheet up. Assigning a new
    /// case while another is up replaces it on the same tick — that's
    /// the SwiftUI contract for `.sheet(item:)` and is precisely the
    /// behaviour that defuses the rise-and-fall race.
    @State private var activeSheet: ActiveSheet?

    @State private var c1HasShown = UpgradeNudgeFlags.c1HasShown

    /// Reorganize in flight — disables the affordance and surfaces a
    /// spinner alongside the chip.
    @State private var isReorganizing = false

    init(
        entryID: UUID,
        onOrganize: @escaping () -> Void
    ) {
        self.entryID = entryID
        self.onOrganize = onOrganize
        let request: NSFetchRequest<JournalEntry> = NSFetchRequest(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "id == %@", entryID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \JournalEntry.createdAt, ascending: false)]
        request.fetchLimit = 1
        _entries = FetchRequest(fetchRequest: request)
    }

    // MARK: - Derived state

    private var entry: JournalEntry? { entries.first }
    private var pass: OrganizePass? { entry?.latestOrganizePass }
    private var isStale: Bool { entry?.hasChangesSinceLastOrganize ?? false }
    private var isProcessing: Bool {
        switch entry?.latestProcessingTask()?.statusEnum {
        case .pending, .processing: return true
        default: return false
        }
    }

    /// The previously-accepted summary string (or empty if no accept
    /// ever happened). Non-empty iff this entry has lived through at
    /// least one initial-Organize commit — so a fresh draft on top of
    /// this means the user is in the Reorganize lifecycle.
    private var acceptedSummary: String {
        entry?.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Single source of truth for what to render. Every branch in the
    /// body reads `aiState`; nothing else mirrors the model.
    private var aiState: AIState {
        guard let entry else { return .missing }
        guard let pass else { return .idle }
        if pass.isReviewed {
            return .organized(pass: pass, entry: entry, stale: isStale)
        }
        let kind: DraftKind = acceptedSummary.isEmpty ? .initial : .reorganize
        return .draftReviewing(pass: pass, entry: entry, kind: kind)
    }

    // MARK: - Body

    var body: some View {
        Group {
            switch aiState {
            case .missing:
                EmptyView()
            case .idle:
                OrganizeMemoryCard(state: .idle, onOrganize: onOrganize, isProcessing: isProcessing)
            case .draftReviewing(let pass, _, _):
                organizedRow(pass: pass)
            case .organized(let pass, let entry, let stale):
                organizedRow(pass: pass, entry: entry, stale: stale)
            }
        }
        .sheet(item: $activeSheet) { kind in
            sheetContent(for: kind)
        }
        // Tutorial trigger fires ONCE on section appear. Per spec
        // (`AI Organize · spec.md` §Tutorial trigger and the explicit
        // bug at OrganizeMemorySection.swift original line 322):
        //
        //   • **Plus path** — opening a memory that *already* has a
        //     draft. `aiState == .draftReviewing` at `.onAppear` time.
        //     Tutorial fires. Correct.
        //
        //   • **Free path** — opening an idle memory, then tapping
        //     Organize. At `.onAppear` time `aiState == .idle` so
        //     the guard returns silently. The subsequent state
        //     transition into `.draftReviewing` MUST NOT re-fire the
        //     tutorial because the user is about to tap "Review draft"
        //     and the root cover would race the local sheet (visible
        //     "Attempt to present … which is already presenting"
        //     UIKit error, June 12 2026). The spec calls this out
        //     directly: "the tutorial defers to the next memory with
        //     a draft." Deferred via the orchestrator's session/day
        //     caps + unseen flag.
        //
        // Therefore: no `.onChange(of:)` modifier here. `.onAppear`
        // is the one and only signal.
        .onAppear {
            NSLog("[HiMem][Diag] OrganizeMemorySection.onAppear entryID=\(entryID.uuidString.prefix(8)) activeSheet=\(String(describing: activeSheet))")
            attemptOrganizingTutorial()
        }
        .onDisappear {
            NSLog("[HiMem][Diag] OrganizeMemorySection.onDisappear entryID=\(entryID.uuidString.prefix(8)) activeSheet=\(String(describing: activeSheet))")
        }
    }

    // MARK: - Organized row (chip + action button + nudge + stale)

    /// Status chip + the one primary action of the moment. Per the
    /// June 8 2026 affordance lock: one button per surface, ochre = you,
    /// blue = the AI. Reorganize is blue (rank-3 bordered) only on the
    /// reviewed state; Review draft is blue (rank-1 filled) only on
    /// the unreviewed state.
    @ViewBuilder
    private func organizedRow(pass: OrganizePass, entry: JournalEntry? = nil, stale: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 9) {
                OrganizedChip(pass: pass)
                Spacer(minLength: 0)
                if pass.isReviewed, let entry {
                    reorganizeButton(entry: entry)
                }
            }
            if !pass.isReviewed {
                reviewDraftButton
            }
            if pass.isReviewed, stale, let entry {
                staleBanner(newClips: entry.clipsAddedSinceLastOrganize)
            }
            if pass.isReviewed, !entitlement.isPlus, !c1HasShown {
                AfterAGlanceNudge(onSeePlus: handleSeePlus, onNotNow: handleNudgeDismiss)
                    .onAppear { UpgradeNudgeFlags.markC1Shown() }
                Text("Shown once. Never again inline.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Crucible.Color.ink3)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Sheet routing

    /// Drives `.sheet(item:)`. The draft kind decides which content to
    /// render — initial drafts use `DraftReviewSheet` (full topic +
    /// mention review), reorganize drafts use `ReorganizeReviewSheet`
    /// (title + summary before/after).
    private enum ActiveSheet: Identifiable {
        case initialReview
        case reorganizeReview
        case pricing
        var id: String {
            switch self {
            case .initialReview:    return "initialReview"
            case .reorganizeReview: return "reorganizeReview"
            case .pricing:          return "pricing"
            }
        }
    }

    @ViewBuilder
    private func sheetContent(for kind: ActiveSheet) -> some View {
        switch kind {
        case .initialReview:
            if let entry, let pass {
                DraftReviewSheet(
                    pass: pass,
                    entry: entry,
                    onDismiss: { activeSheet = nil }
                )
                .presentationDetents([.large])
            }
        case .reorganizeReview:
            if let entry, let pass {
                ReorganizeReviewSheet(
                    currentTitle: entry.title ?? "",
                    newTitle: pass.suggestedTitle ?? "",
                    currentSummary: acceptedSummary,
                    newSummary: pass.summaryText ?? "",
                    onKeep: handleReorganizeKeep,
                    onReorganizeAgain: handleReorganizeAgain,
                    onDismiss: { activeSheet = nil }
                )
                .presentationDetents([.large])
            }
        case .pricing:
            PricingView()
        }
    }

    // MARK: - Buttons

    /// Blue rank-1 primary — opens the appropriate review sheet for
    /// the current draft kind. Same affordance for both initial and
    /// reorganize drafts (spec §8.0 June 12: "the standard Stage-2
    /// affordance is present to re-open the same sheet").
    private var reviewDraftButton: some View {
        Button(action: openReviewSheet) {
            HStack(spacing: 7) {
                Text("Review draft")
                    .font(.system(size: 15.5, weight: .semibold))
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background(Crucible.Color.aiBlue)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Review draft")
        .accessibilityHint("Open the AI organize draft for review")
    }

    /// Rank-3 tertiary AI button — bordered blue pill. Spinner replaces
    /// the sparkle while a reorganize pass is in flight.
    @ViewBuilder
    private func reorganizeButton(entry: JournalEntry) -> some View {
        Button {
            handleReorganizeTap(entry: entry)
        } label: {
            HStack(spacing: 6) {
                Text(isReorganizing ? "Working…" : "Reorganize with AI")
                    .font(.system(size: 13, weight: .semibold))
                if isReorganizing {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Crucible.Color.aiBlue)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(Crucible.Color.aiBlue)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(minHeight: 44)
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(Crucible.Color.aiBlue, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isReorganizing)
        .accessibilityLabel(isReorganizing ? "Reorganizing" : "Reorganize with AI")
    }

    // MARK: - Stale banner

    @ViewBuilder
    private func staleBanner(newClips: Int) -> some View {
        Button(action: onOrganize) {
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
        newClips == 1
            ? "1 new clip since this was organized"
            : "\(newClips) new clips since this was organized"
    }

    // MARK: - Actions

    /// Opens the right review sheet for the current draft kind.
    ///
    /// The assignment hops one runloop tick. In theory `.sheet(item:)`
    /// serializes presentations cleanly, but the surrounding parent
    /// hierarchy (`captureFlowHost`, `MediaFragmentEditorStack`, the
    /// root `TutorialAutoFireOverlay`) carries enough other
    /// `.sheet`/`.fullScreenCover` modifiers that a UIViewController
    /// from a recently-dismissed presenter can still be mid-cleanup
    /// when the tap fires. The async hop gives UIKit one tick to
    /// finish the cleanup before we ask it to present again, which
    /// avoids the `Attempt to present X on Y which is already
    /// presenting Z` runtime error and its visible rise-then-fall.
    private func openReviewSheet() {
        guard case .draftReviewing(_, _, let kind) = aiState else { return }
        NSLog("[HiMem][Diag] Review draft tapped. kind=\(kind == .initial ? "initial" : "reorganize") activeSheet=\(String(describing: activeSheet)) orchestrator.visible=\(String(describing: TutorialOrchestrator.shared.visible))")
        DispatchQueue.main.async {
            switch kind {
            case .initial:    activeSheet = .initialReview
            case .reorganize: activeSheet = .reorganizeReview
            }
            NSLog("[HiMem][Diag] activeSheet assigned to \(String(describing: activeSheet)) (next runloop)")
        }
    }

    private func handleReorganizeTap(entry: JournalEntry) {
        isReorganizing = true
        Task { @MainActor in
            await ProcessingEngine.shared.processReorganize(entry)
            isReorganizing = false
            // Auto-open the comparison sheet on first reorganize per
            // spec §8.0: "Reorganize re-enters the same lifecycle…
            // re-opens the review sheet."
            activeSheet = .reorganizeReview
        }
    }

    private func handleReorganizeKeep(titleChoice: ReorgFieldChoice, summaryChoice: ReorgFieldChoice) {
        guard let entry, let pass else { return }
        // `acceptedSummary` is the live previously-accepted value —
        // it's what the user has been looking at as the "Current"
        // column. Passing it as `previousSummary` lets
        // `commitReorganize` write it back to `pass.summaryText` if
        // the user kept the current summary (preserves the "latest
        // pass reflects what's shown" invariant from OrganizePass.swift).
        let previousSummary = acceptedSummary
        let ctx = pass.managedObjectContext ?? StorageService.shared.viewContext
        ctx.performAndWait {
            pass.commitReorganize(
                on: entry,
                titleChoice: titleChoice,
                summaryChoice: summaryChoice,
                previousSummary: previousSummary
            )
            try? ctx.save()
        }
        activeSheet = nil
    }

    /// "Reorganize again" from inside the sheet. Writes the new pass
    /// **before** deleting the superseded one so `latestOrganizePass`
    /// never falls back to a stale pass during the transition. Per
    /// spec §8.0: "Reorganize replaces the draft; it never branches."
    private func handleReorganizeAgain() {
        guard let entry, let pass else { return }
        let supersededID = pass.objectID
        isReorganizing = true
        Task { @MainActor in
            await ProcessingEngine.shared.processReorganize(entry)
            await discardPass(objectID: supersededID)
            isReorganizing = false
        }
    }

    /// Pure discard helper. Used only by `handleReorganizeAgain` to
    /// remove the superseded draft after a fresh pass lands. No-op if
    /// the object can't be resolved (already deleted, or merged out
    /// from under us).
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
        activeSheet = .pricing
    }

    private func handleNudgeDismiss() {
        c1HasShown = true
        UpgradeNudgeFlags.markC1Shown()
    }

    // MARK: - Tutorial trigger

    /// Tutorial #2 (Organizing). Fires when the section first sees a
    /// `draftReviewing` state — i.e. the user is looking at a "Draft
    /// organized" memory for the first time this session. Driven by
    /// `.onChange(of: stateSignature)` and `.onAppear`, both of which
    /// land before the user's tap so the orchestrator's `tryFire` is
    /// always evaluated against a settled state.
    ///
    /// Suppressed if `activeSheet != nil` — if the user already opened
    /// the review sheet, the tutorial would race the sheet's
    /// presentation (the symptomatic rise-and-fall). The deferred fire
    /// re-attempts on the next unreviewed memory per the orchestrator's
    /// once-each-by-deferral rule.
    private func attemptOrganizingTutorial() {
        let stateDesc: String = {
            switch aiState {
            case .missing:          return "missing"
            case .idle:             return "idle"
            case .draftReviewing:   return "draftReviewing"
            case .organized:        return "organized"
            }
        }()
        NSLog("[HiMem][Diag] attemptOrganizingTutorial fired. aiState=\(stateDesc) activeSheet=\(String(describing: activeSheet))")
        guard case .draftReviewing = aiState else { return }
        guard activeSheet == nil else { return }
        TutorialOrchestrator.shared.tryFire(.organizing)
    }

}

// MARK: - AIState

/// One enum, four cases — the spec's §9 state table in code form.
private enum AIState {
    case missing
    case idle
    case draftReviewing(pass: OrganizePass, entry: JournalEntry, kind: DraftKind)
    case organized(pass: OrganizePass, entry: JournalEntry, stale: Bool)
}

private enum DraftKind {
    case initial    // first organize on this entry — DraftReviewSheet
    case reorganize // user has previously accepted a pass — ReorganizeReviewSheet
}
