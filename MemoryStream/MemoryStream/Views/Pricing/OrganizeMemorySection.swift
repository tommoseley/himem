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
    /// Drives the failed-state copy variant ("try again" vs "try again when
    /// you're back online") from the CURRENT connection, so the honest failure
    /// tells the user whether a retry can succeed right now.
    @ObservedObject private var connectivity = ConnectivityMonitor.shared
    @FetchRequest private var entries: FetchedResults<JournalEntry>

    /// Reference to the currently-presented review sheet host, if
    /// any. Manual UIKit presentation pattern (Path B, 2026-06-13):
    /// SwiftUI's `.fullScreenCover(item:)` and `.sheet(item:)` both
    /// fire `present()` TWICE during the iOS 26 binding-flip body
    /// re-evaluation — verified via swizzled UIViewController logs
    /// showing the second `present()` call from
    /// `SwiftUI.Update.dispatchActions()` after a SwiftUI-internal
    /// `dismiss()` on the navigation hosting controller. The first
    /// present succeeds, occupies UIKit's `_presentedViewController`
    /// slot, the second is refused with "Attempt to present X on Y
    /// which is already presenting Z" — and Z is our own first PHC.
    /// Bypassing SwiftUI's modifier and presenting via UIKit directly
    /// avoids the double-fire entirely.
    @State private var presentedHost: UIHostingController<AnyView>?

    @State private var c1HasShown = UpgradeNudgeFlags.c1HasShown

    /// Reorganize in flight — disables the affordance and surfaces a
    /// spinner alongside the chip.
    @State private var isReorganizing = false

    /// Backs the presented `ReorganizeReviewSheet` so "Reorganize again" can
    /// swap the fresh pass in place (Approach B, 2026-07-24) instead of the
    /// old dismiss-then-re-present race.
    @State private var reorganizeModel: ReorganizeReviewModel?

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

    /// Whether the no-pass state is a FAILURE (retryable) rather than idle:
    /// true iff the latest processing task ended `.failed`. Pure + `static` so
    /// the Ruling-2 money test can exercise it without a View. Callers guard
    /// `pass == nil` first (a committed pass always wins).
    static func failedStateApplies(latestTaskStatus: ProcessingTask.Status?) -> Bool {
        latestTaskStatus == .failed
    }

    /// Single source of truth for what to render. Every branch in the
    /// body reads `aiState`; nothing else mirrors the model.
    private var aiState: AIState {
        guard let entry else { return .missing }
        guard let pass else {
            // No committed pass. If the last organize attempt FAILED, show the
            // honest retryable failure — never silent idle (Ruling 2).
            if Self.failedStateApplies(latestTaskStatus: entry.latestProcessingTask()?.statusEnum) {
                return .failed(offline: !connectivity.isConnected)
            }
            return .idle
        }
        if pass.isReviewed {
            return .organized(pass: pass, entry: entry, stale: isStale)
        }
        let kind: DraftKind = acceptedSummary.isEmpty ? .initial : .reorganize
        return .draftReviewing(pass: pass, entry: entry, kind: kind)
    }

    // MARK: - Body

    var body: some View {
        Group {
            if case .missing = aiState {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    // F7c · the Organize help ?. Anchored in a fixed header row
                    // that WRAPS the state switch — not inside any one state's
                    // card — so it never relocates when the card flips from the
                    // idle CTA to the organized chip+button (Tom's constraint,
                    // 2026-07-27: a help affordance that moves on state change is
                    // worse than none). No new eyebrow — a bare ?, left-aligned
                    // where the other sections' ? sits.
                    HStack {
                        SectionHelpButton(topic: .memoryOrganize, size: 15)
                        Spacer(minLength: 0)
                    }
                    stateCard
                }
            }
        }
        // NO `.fullScreenCover(item:)` or `.sheet(item:)` here —
        // those modifiers fire `present()` twice on iOS 26 during the
        // binding-flip body re-evaluation cycle (see `presentedHost`
        // doc for the full diagnosis). All review-sheet presentations
        // go through manual UIKit via `presentInitialReview()`,
        // `presentReorganizeReview()`, and `presentPricing()`.
        .onAppear { attemptOrganizingTutorial() }
    }

    /// The state-dependent card body — extracted so `body` can wrap it with the
    /// fixed F7c help header without the `?` living inside any one state.
    @ViewBuilder
    private var stateCard: some View {
        switch aiState {
        case .missing:
            EmptyView()
        case .idle:
            OrganizeMemoryCard(state: .idle, onOrganize: onOrganize, isProcessing: isProcessing)
        case .failed(let offline):
            OrganizeMemoryCard(state: .failed(offline: offline), onOrganize: onOrganize, isProcessing: isProcessing)
        case .draftReviewing(let pass, _, _):
            organizedRow(pass: pass)
        case .organized(let pass, let entry, let stale):
            organizedRow(pass: pass, entry: entry, stale: stale)
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
            }
        }
    }

    // MARK: - Manual UIKit presentation (Path B)

    /// Walks every active scene's key window down to the deepest
    /// presented controller, returning the controller that any new
    /// modal should be presented from.
    private static func topPresentingController() -> UIViewController? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene,
                  windowScene.activationState == .foregroundActive else { continue }
            for window in windowScene.windows where window.isKeyWindow {
                guard let root = window.rootViewController else { continue }
                var top = root
                while let presented = top.presentedViewController { top = presented }
                return top
            }
        }
        return nil
    }

    /// Presents `DraftReviewSheet` for the initial-organize draft.
    /// The host's `onDismiss` is captured into the sheet so explicit
    /// dismiss paths ("Looks good", "Edit", swipe-down) route through
    /// UIKit's `dismiss(animated:)` — exactly one `present()`, exactly
    /// one `dismiss()`, no SwiftUI modifier in between.
    private func presentInitialReview() {
        guard let entry, let pass else { return }
        var hostRef: UIHostingController<AnyView>?
        let dismissHost: () -> Void = { hostRef?.dismiss(animated: true) }
        let host = UIHostingController(rootView: AnyView(
            DraftReviewSheet(pass: pass, entry: entry, onDismiss: { handleDismissDraft(dismissHost: dismissHost) })
        ))
        hostRef = host
        host.modalPresentationStyle = .pageSheet
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.large()]
        }
        presentedHost = host
        Self.topPresentingController()?.present(host, animated: true)
    }

    /// Presents `ReorganizeReviewSheet` for the before/after comparison.
    /// `onKeep` wraps `handleReorganizeKeep` with a dismiss; the
    /// commit/dismiss order matters because `commitReorganize` mutates
    /// the pass's `dismissedAt` (flipping `isReviewed` true) and we
    /// want the sheet visually gone before the body re-renders the
    /// `Organized` state.
    private func presentReorganizeReview() {
        guard let entry, let pass else { return }
        var hostRef: UIHostingController<AnyView>?
        let dismissHost: () -> Void = { hostRef?.dismiss(animated: true) }
        let model = ReorganizeReviewModel(
            currentTitle: entry.title ?? "",
            newTitle: pass.suggestedTitle ?? "",
            currentSummary: acceptedSummary,
            newSummary: pass.summaryText ?? ""
        )
        reorganizeModel = model
        let host = UIHostingController(rootView: AnyView(
            ReorganizeReviewSheet(
                model: model,
                onKeep: { titleChoice, summaryChoice in
                    handleReorganizeKeep(
                        titleChoice: titleChoice,
                        summaryChoice: summaryChoice
                    )
                    dismissHost()
                },
                // Approach B: no dismiss — the sheet stays up, shows a working
                // state, and swaps the fresh pass into `model` in place.
                onReorganizeAgain: { handleReorganizeAgain() },
                // X discards the reorganize draft → the prior committed pass
                // resurfaces (Case 1). Never leaves a Draft-organized strand.
                onDismiss: { handleDismissDraft(dismissHost: dismissHost) }
            )
        ))
        hostRef = host
        host.modalPresentationStyle = .pageSheet
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.large()]
        }
        presentedHost = host
        Self.topPresentingController()?.present(host, animated: true)
    }

    /// Presents the Plus upgrade sheet (C1 nudge → See plans).
    private func presentPricing() {
        var hostRef: UIHostingController<AnyView>?
        let dismissHost: () -> Void = { hostRef?.dismiss(animated: true) }
        _ = dismissHost  // PricingView manages its own dismiss via Environment
        let host = UIHostingController(rootView: AnyView(PricingView()))
        hostRef = host
        host.modalPresentationStyle = .pageSheet
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.large()]
        }
        presentedHost = host
        Self.topPresentingController()?.present(host, animated: true)
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

    /// Routes the Review-draft tap to the right manual UIKit
    /// presentation. Single `present()` call → no double-fire race.
    private func openReviewSheet() {
        guard case .draftReviewing(_, _, let kind) = aiState else { return }
        switch kind {
        case .initial:    presentInitialReview()
        case .reorganize: presentReorganizeReview()
        }
    }

    private func handleReorganizeTap(entry: JournalEntry) {
        isReorganizing = true
        Task { @MainActor in
            await ProcessingEngine.shared.processReorganize(entry)
            isReorganizing = false
            guard self.entry != nil, self.pass != nil else { return }
            // Auto-open the comparison sheet per spec §8.0.
            presentReorganizeReview()
        }
    }

    private func handleReorganizeKeep(titleChoice: ReorgFieldChoice, summaryChoice: ReorgFieldChoice) {
        guard let entry, let pass else { return }
        // `acceptedSummary` is the live previously-accepted value —
        // it's what the user has been looking at as the "Current"
        // column. Passing it as `previousSummary` lets
        // `commitReorganize` write it back to `pass.summaryText` if
        // the user kept the current summary.
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
        // Dismiss handled by the closure-wrapper at the call site
        // (see `presentReorganizeReview`), not here.
    }

    /// "Reorganize again" from inside the sheet (Approach B, 2026-07-24).
    /// The sheet observes `reorganizeModel`, so it **stays presented**: we flip
    /// it to a working state, run the pass, then swap the fresh title/summary
    /// into the model in place. No dismiss, no re-present — this kills the
    /// present-while-dismissing race that used to leave the sheet closed.
    ///
    /// Discard order matters: we let the new pass write *first*, then delete
    /// the superseded one, so `latestOrganizePass` never falls back to a stale
    /// pass during the transition.
    private func handleReorganizeAgain() {
        guard let entry, let pass, let model = reorganizeModel else { return }
        let supersededID = pass.objectID
        model.isWorking = true
        isReorganizing = true
        Task { @MainActor in
            await ProcessingEngine.shared.processReorganize(entry)
            await discardPass(objectID: supersededID)
            isReorganizing = false
            guard let freshPass = self.pass else { model.isWorking = false; return }
            // Swap the fresh suggestion into the same sheet, in place.
            model.applyFreshPass(
                newTitle: freshPass.suggestedTitle ?? "",
                newSummary: freshPass.summaryText ?? ""
            )
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

    /// X on the review / reorganize sheet **discards the uncommitted draft** and
    /// returns the memory to its last committed state — never the old
    /// "Draft organized / Review draft" strand (spec §8, reversed 2026-07-24;
    /// the June 12 "dismiss = decide later, never discard" pin is superseded).
    /// Both cases fall out of deleting the current draft `OrganizePass`:
    ///   • **Case 1** — a prior committed pass exists (Reorganize on an already-
    ///     Organized memory, then X): the draft is deleted, so `latestOrganizePass`
    ///     resurfaces the prior committed pass → memory reads Organized, the
    ///     action is a Reorganize CTA. X here == "Keep this version."
    ///   • **Case 2** — first draft, never committed, X'd: the only pass is
    ///     deleted → memory reads unorganized, the action is an Organize CTA.
    /// Topics/mentions (library-backed associations) are NEVER destroyed here;
    /// re-organize reconciles them. Dismiss first, then delete, so the sheet's
    /// content isn't mutated under it.
    ///
    /// Caveat resolution (Tom's ruling a + "hide the lingering summary"): the
    /// initial draft's own `InferenceSummary` would otherwise un-suppress the
    /// legacy `InferenceCard` once the pass is gone (`LegacyInferenceCardSlot`
    /// renders when `latestOrganizePass == nil`) → "unorganized card but a
    /// summary shows." So on a Case-2 discard (no committed pass remains) the
    /// orphaned draft summary goes too — it's the draft's artifact, not an
    /// association. Case 1 keeps it (it belongs to the restored committed pass).
    private func handleDismissDraft(dismissHost: () -> Void) {
        let draftPass = pass
        dismissHost()
        guard let draftPass else { return }
        let ctx = StorageService.shared.viewContext
        ctx.perform { EntryLifecycleService.discardDraftPass(draftPass, in: ctx) }
    }

    private func handleSeePlus() {
        c1HasShown = true
        UpgradeNudgeFlags.markC1Shown()
        presentPricing()
    }

    private func handleNudgeDismiss() {
        c1HasShown = true
        UpgradeNudgeFlags.markC1Shown()
    }

    // MARK: - Tutorial trigger

    /// Tutorial #2 (Organizing). Currently fires from `.onAppear`
    /// only — i.e. when the section first lands and the user is
    /// looking at a `draftReviewing` state. Free path defers (no draft
    /// at appear time; the orchestrator's once-each guarantee re-fires
    /// at the next memory that already has a draft on appear).
    ///
    /// **Deviation from `Tutorials · triggers spec.md`.** The spec
    /// says the Free trigger fires after the first Organize tap,
    /// before the review sheet opens — i.e. the tutorial chains into
    /// the review. The chain-on-dismiss path is a real product call
    /// (CD's preference) but requires a completion hook on
    /// `TutorialOrchestrator` and is not yet built. Until then the
    /// Free path's first organize is untaught; the orchestrator
    /// surfaces the lesson on the next memory's appear.
    ///
    /// Suppressed if `activeSheet != nil` — never overlap a tutorial
    /// with a review sheet.
    private func attemptOrganizingTutorial() {
        guard case .draftReviewing = aiState else { return }
        // We no longer guard on a SwiftUI sheet binding since the
        // manual UIKit presentation path doesn't expose one. The
        // tutorial only fires from `.onAppear`, which runs before
        // the user's tap, so there's no race to defend against.
        TutorialOrchestrator.shared.tryFire(.organizing)
    }

}

// MARK: - AIState

/// One enum, four cases — the spec's §9 state table in code form.
private enum AIState {
    case missing
    case idle
    /// A previous organize attempt failed and produced no `OrganizePass`
    /// (on-device refusal, timeout, or offline with no cloud). Ruling 2
    /// (2026-07-25): show an honest, retryable state — never reset to idle,
    /// which reads as "the tap did nothing." `offline` picks the copy variant.
    case failed(offline: Bool)
    case draftReviewing(pass: OrganizePass, entry: JournalEntry, kind: DraftKind)
    case organized(pass: OrganizePass, entry: JournalEntry, stale: Bool)
}

private enum DraftKind {
    case initial    // first organize on this entry — DraftReviewSheet
    case reorganize // user has previously accepted a pass — ReorganizeReviewSheet
}
