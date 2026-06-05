import SwiftUI
import CoreData

/// Unified AI Suggestions card — replaces the v2 inline
/// `OrganizeDoneSections` pattern. One card, up to four rows
/// (Title / Summary / Topics / Next steps), per-row inline editing,
/// Accept all / × footer.
///
/// Mechanic (pattern A from the v5 design discussion):
///   • Each row starts **pending** — shows the AI's suggested value.
///   • Tap a row → inline editor opens for that field.
///     - **Save** in editor → row writes to its commit destination
///       (title → `entry.title`, summary/next-steps → pass) and
///       visibly mutes with a small ochre ✓ prefix. The committed
///       value stays visible.
///     - **Cancel** in editor → editor closes, row stays pending.
///   • **Accept all** → commits all remaining pending rows as-is and
///     sets `pass.dismissedAt`. Card collapses to `OrganizedChip` in
///     the parent.
///   • **×** → sets `pass.dismissedAt` without applying pending rows
///     (anything still pending is skipped).
///
/// When the pass is `stale` (new clips since `entry.lastOrganizedAt`),
/// the card grows a small header strip with the pass date and a
/// `Refresh · 1 assist` action (or `Resets [date]` when out of
/// assists). Refresh runs a new `ProcessingEngine.processEntry` for
/// the same entry, which writes a new `OrganizePass`.
struct AISuggestionsCard: View {
    let pass: OrganizePass
    let entry: JournalEntry
    let isStale: Bool
    let canRefresh: Bool
    var onRefresh: () -> Void = {}
    var onDismiss: () -> Void = {}
    /// Routes the refresh button to the buy-assists flow when the
    /// user has no assists left. Greyed-but-tappable button (rather
    /// than hidden text) lets the user learn the cost without
    /// hitting a dead end.
    var onOpenPackSheet: () -> Void = {}

    @ObservedObject private var entitlement = EntitlementService.shared
    /// Per-row commit flags. Initialized from `pass.acceptedRows` on
    /// appear so accepted state survives card open/close cycles. Each
    /// successful commit also writes back into `acceptedRowsJSON`,
    /// making the data the source of truth — the @State here just
    /// caches it for view-render speed and animation drive.
    @State private var titleCommitted: Bool = false
    @State private var summaryCommitted: Bool = false
    @State private var topicsCommitted: Bool = false
    @State private var mentionsCommitted: Bool = false
    @State private var nextStepsCommitted: Bool = false
    @State private var editing: Field? = nil
    @State private var hydrated: Bool = false
    /// Card-local per-mention selection state. Defaults to "all
    /// selected" — bias toward accepting AI's work, with explicit
    /// opt-out per item. UUID key matches the ExtractedEntity id so
    /// the set survives entity re-fetches inside the row body.
    /// Population happens lazily on first render in `mentionsContent`
    /// so the default-selected behavior holds for entities that
    /// appear after the card first appears.
    @State private var rejectedMentionIDs: Set<UUID> = []
    /// Card-local per-topic selection state. Same pattern as
    /// `rejectedMentionIDs` — default selected, tap to opt out. Keyed
    /// by topic name (string) because `pass.suggestedTopics` is
    /// `[String]`; the Topic entity relationships on the entry are
    /// found by name at commit time.
    @State private var rejectedTopicNames: Set<String> = []

    private enum Field: String, Identifiable {
        case title, summary, topics, mentions, nextSteps
        var id: String { rawValue }
    }

    /// Entities the AI found (people / projects / issues / ideas),
    /// filtered to exclude `nextAction` because those flow into the
    /// Next steps row instead. Live-read from the entry so the row
    /// reflects whatever the most recent processing pass extracted.
    private var mentionEntities: [ExtractedEntity] {
        entry.entitiesArray.filter { $0.entityTypeEnum != .nextAction }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let title = pass.suggestedTitle, !title.isEmpty {
                row(
                    label: "Title",
                    committed: titleCommitted,
                    field: .title,
                    acceptAsIs: { commitTitle(title) },
                    content: { Text(title).font(PricingFonts.serif(16)).foregroundStyle(Crucible.Color.ink) }
                )
            }
            if let summary = pass.summaryText, !summary.isEmpty {
                // Owner-view render via the token-substitution layer.
                // Hand-edited summaries (no `<user>` token in storage)
                // pass through unchanged because there's nothing for
                // the regex to match.
                let displayed = SummaryRenderer.renderForOwner(summary)
                row(
                    label: "Summary",
                    committed: summaryCommitted,
                    field: .summary,
                    // Accept-as-is preserves the stored token form so
                    // a later share/export can substitute the user's
                    // first name in place of the token. Earlier impl
                    // wrote the rendered "You are…" string back into
                    // storage, which baked "you" in permanently and
                    // broke share-time first-name substitution.
                    acceptAsIs: { acceptSummary() },
                    content: {
                        Text(displayed)
                            .font(.system(size: 13))
                            .foregroundStyle(Crucible.Color.ink2)
                            .lineSpacing(2)
                    }
                )
            }
            let suggested = pass.suggestedTopics
            if !suggested.isEmpty {
                row(
                    label: "Topics",
                    committed: topicsCommitted,
                    field: .topics,
                    acceptAsIs: { commitTopics(suggested) },
                    content: { topicsContent(suggested) }
                )
            }
            let mentions = mentionEntities
            if !mentions.isEmpty {
                row(
                    label: "Mentions",
                    committed: mentionsCommitted,
                    field: .mentions,
                    acceptAsIs: { commitMentions() },
                    content: { mentionsContent(mentions) }
                )
            }
            let steps = pass.nextStepsItems
            if !steps.isEmpty {
                row(
                    label: "Next steps",
                    committed: nextStepsCommitted,
                    field: .nextSteps,
                    isLast: true,
                    acceptAsIs: { commitNextSteps(pass.nextStepsMarkdown) },
                    content: { nextStepsContent(steps) }
                )
            }

            if footerHasContent {
                footer
                    .padding(12)
                    .background(Crucible.Color.paper)
            }
        }
        .background(Crucible.Color.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .sheet(item: $editing) { field in
            editorSheet(for: field)
                .presentationDetents([.medium, .large])
        }
        .onAppear { hydrateCommitFlagsIfNeeded() }
        // Auto-collapse runs from the user-action commit functions
        // below — NOT from `.onChange` observers. Observers fire on
        // every flag transition, including the hydration path that
        // restores prior acceptances on appear. The original observer
        // wiring caused the chip-tap "show then vanish" bug: opening a
        // fully-accepted card hydrated the flags, the observers saw
        // false→true, and the 450ms auto-collapse fired immediately.
        // Trigger only from user actions to make that regression
        // structurally impossible.
    }

    /// True when every rendered row in the card has been committed.
    /// "Rendered" matches the conditions used in `body` — a row's
    /// commit flag only matters if the corresponding data is present.
    /// Vacuously true for a card with zero rendered rows, but those
    /// shouldn't reach this check because nothing would have flipped
    /// a commit flag in the first place.
    private var allRenderedRowsCommitted: Bool {
        if let t = pass.suggestedTitle, !t.isEmpty, !titleCommitted { return false }
        if let s = pass.summaryText, !s.isEmpty, !summaryCommitted { return false }
        if !pass.suggestedTopics.isEmpty, !topicsCommitted { return false }
        if !mentionEntities.isEmpty, !mentionsCommitted { return false }
        if !pass.nextStepsItems.isEmpty, !nextStepsCommitted { return false }
        return true
    }

    /// True when NONE of the rendered rows has been committed yet.
    /// Drives the bulk button label — "Accept all" reads honestly on
    /// a fresh pass, "Accept remaining" reads honestly after at
    /// least one row was individually accepted. Per Tom's 2026-05-27
    /// nit: "Accept remaining" was rendering on fresh passes too,
    /// which is misleading.
    private var noRenderedRowsCommitted: Bool {
        if let t = pass.suggestedTitle, !t.isEmpty, titleCommitted { return false }
        if let s = pass.summaryText, !s.isEmpty, summaryCommitted { return false }
        if !pass.suggestedTopics.isEmpty, topicsCommitted { return false }
        if !mentionEntities.isEmpty, mentionsCommitted { return false }
        if !pass.nextStepsItems.isEmpty, nextStepsCommitted { return false }
        return true
    }

    /// Reads `pass.acceptedRows` into the @State commit flags so the
    /// card opens with prior acceptances visible. Runs once per
    /// view instance via `hydrated` guard.
    private func hydrateCommitFlagsIfNeeded() {
        guard !hydrated else { return }
        hydrated = true
        let rows = pass.acceptedRows
        titleCommitted     = rows.contains(.title)
        summaryCommitted   = rows.contains(.summary)
        topicsCommitted    = rows.contains(.topics)
        mentionsCommitted  = rows.contains(.mentions)
        nextStepsCommitted = rows.contains(.nextSteps)
    }

    private func scheduleAutoCollapseIfDone() {
        guard allRenderedRowsCommitted else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            // Re-check after the delay — if the user manually × in
            // between, dismiss already fired and this is a no-op.
            guard allRenderedRowsCommitted else { return }
            onDismiss()
        }
    }

    // MARK: - Header
    //
    // Pill-as-collapsible-header (Option A, 2026-05-18). The
    // expanded card opens with the same chip aesthetic the
    // collapsed state uses — sparkles + variant label + chevron-up
    // + ×, all in one ochre ribbon at the top of the card. Tap the
    // ribbon (or the ×) to collapse. The variant resolver lives on
    // `OrganizedChip.Variant`; share the same source of truth so
    // collapsed/expanded labels match.

    /// True while an analyze pass is in flight — drives the spinner
    /// in the ribbon header and the refresh button. Reads the entry's
    /// latest processing task; when status is pending or processing,
    /// the user is waiting on the AI.
    private var isProcessing: Bool {
        switch entry.latestProcessingTask?.statusEnum {
        case .pending, .processing: return true
        default: return false
        }
    }

    private var headerVariant: OrganizedChip.Variant {
        OrganizedChip.Variant.resolve(isReviewed: pass.isReviewed)
    }

    private var headerLabel: String {
        headerVariant.labelText
    }

    private var headerTint: Color {
        // After the assist-quota retirement (PR 8c), both chip
        // variants wear AI blue; the dashed-vs-solid border carries
        // the review-state semantic. This card is slated for deletion
        // in 8d alongside the new B1 review sheet, so the header
        // tinting is provisional.
        Crucible.Color.aiBlue
    }

    private var headerTintBackground: Color {
        // See `headerTint` — both variants share the AI-blue tint
        // background until 8d replaces this card with the B1 review
        // sheet.
        Crucible.Color.aiBlueTint
    }

    @ViewBuilder
    private var header: some View {
        Button(action: onDismiss) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                Text(headerLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.05)
                Spacer()
                // While AI is working, the chevron is replaced by a
                // spinner — the ribbon is the most visible AI-status
                // surface, so the inflight signal lives here.
                // Chevron is the toggle — same control as the
                // collapsed pill's chevron-down, in its expanded
                // state. No × secondary control; one affordance per
                // function.
                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(headerTint)
                } else {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .opacity(0.6)
                }
            }
            .foregroundStyle(headerTint)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(headerTintBackground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Collapse AI suggestions")
    }

    // MARK: - Row

    /// Per-row layout. Two affordances per row, both visible:
    ///
    ///   • **Tap row body** → opens the inline editor sheet (existing
    ///     pattern A behavior — for "I want to change this before
    ///     accepting").
    ///   • **Tap trailing Accept** → commits the row as-is, no sheet
    ///     (the "Apply some" affordance Tom called for after seeing
    ///     real-world use — for "I'm fine with this, don't make me
    ///     open a sheet just to confirm").
    ///
    /// Both result in `committed == true`. The row then mutes, drops
    /// a leading ✓ in the eyebrow, and the Accept button hides.
    /// Accept all in the footer commits everything still pending; ×
    /// dismisses the rest.
    @ViewBuilder
    private func row<C: View>(
        label: String,
        committed: Bool,
        field: Field,
        isLast: Bool = false,
        acceptAsIs: (() -> Void)? = nil,
        @ViewBuilder content: () -> C
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                editing = field
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if committed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(Crucible.Color.accent)
                        }
                        Text(label)
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.4)
                            .textCase(.uppercase)
                            .foregroundStyle(committed ? Crucible.Color.accent : Crucible.Color.ink3)
                    }
                    // Accepted content stays at FULL opacity. Dim is
                    // the universal UI grammar for "rejected /
                    // disabled / inactive" — putting accepted items
                    // there reads as "we threw this away," the
                    // opposite of what just happened. Brighter, not
                    // darker. The leading ✓ + subtle ochre tint on
                    // the row (below) carry the committed signal.
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(committed)

            // Per-row Accept — visible only when pending. Tap commits
            // this one row as-is without opening the editor. Small
            // by design so the row body remains the primary tap
            // target for users who want to edit before accepting.
            if !committed, let acceptAsIs {
                Button(action: acceptAsIs) {
                    Text("Accept")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Crucible.Color.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Crucible.Color.accentTint)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 14)  // baseline-align with eyebrow
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        // Subtle ochre tint on the row when committed — affirms the
        // commit visually without competing with content. White card
        // background otherwise.
        .background(committed ? Crucible.Color.accentTint.opacity(0.35) : Crucible.Color.card)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Crucible.Color.divider)
                    .frame(height: 0.5)
            }
        }
    }

    /// Topic chips with the topic-color dot. Matches the chip
    /// treatment used elsewhere in the app (memory cards, topic tab
    /// bar) — one visual vocabulary across surfaces. The per-chip
    /// ✓ was redundant with the row-level commit ✓ in the eyebrow.
    @ViewBuilder
    private func topicsContent(_ names: [String]) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(names, id: \.self) { name in
                topicChip(name)
            }
        }
    }

    /// One topic pill. Default selected with the topic's hue dot;
    /// tap to opt out (strike-through, no dot — same visual grammar
    /// as the mentions row). On commit, rejected topics are removed
    /// from the entry's Topic relationships.
    @ViewBuilder
    private func topicChip(_ name: String) -> some View {
        let isRejected = rejectedTopicNames.contains(name)
        let hue = Crucible.Color.topicHue(for: name)
        Button {
            guard !topicsCommitted else { return }
            if isRejected {
                rejectedTopicNames.remove(name)
            } else {
                rejectedTopicNames.insert(name)
            }
        } label: {
            HStack(spacing: 4) {
                if !isRejected {
                    Circle()
                        .fill(hue.fg)
                        .frame(width: 5, height: 5)
                }
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isRejected ? Crucible.Color.ink4 : Crucible.Color.ink2)
                    .strikethrough(isRejected, color: Crucible.Color.ink4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.black.opacity(isRejected ? 0.02 : 0.05))
            .overlay(
                Capsule()
                    .stroke(isRejected ? Crucible.Color.hairline : Color.clear, lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(topicsCommitted)
    }

    /// Renders extracted entities as tappable chips with per-item
    /// opt-out. The AI generates many candidates (often 6–10 for
    /// dense memories); the user wants to keep most but reject
    /// near-duplicates ("Job displacement from AI" + "Job
    /// displacement from AI automation"). Default selected — bias
    /// toward accepting the AI's work; tap to deselect.
    ///
    /// Visual rules:
    ///   • Selected (default): solid chip with the type-color dot
    ///   • Deselected: muted chip with strike-through, no dot
    ///
    /// On `commitMentions()` (per-row Accept or Accept all), the
    /// deselected entities are removed from `entry.extractedEntities`
    /// before the section commits. Selected entities persist as-is.
    @ViewBuilder
    private func mentionsContent(_ entities: [ExtractedEntity]) -> some View {
        let persons = entities.filter { $0.entityTypeEnum == .person }
        let others  = entities.filter { $0.entityTypeEnum != .person }
        VStack(alignment: .leading, spacing: 6) {
            if !persons.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(persons, id: \.id) { mentionChip($0) }
                }
            }
            if !others.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(others, id: \.id) { mentionChip($0) }
                }
            }
        }
    }

    /// One mention pill. Persons get a `person.fill` glyph in place of
    /// the colored dot so people read distinctly at chip scale; other
    /// types keep the dot. Rejected state strips the leading indicator
    /// entirely (matches existing behavior for non-person chips).
    @ViewBuilder
    private func mentionChip(_ entity: ExtractedEntity) -> some View {
        let isRejected = rejectedMentionIDs.contains(entity.id)
        let isPerson = entity.entityTypeEnum == .person
        Button {
            guard !mentionsCommitted else { return }
            if isRejected {
                rejectedMentionIDs.remove(entity.id)
            } else {
                rejectedMentionIDs.insert(entity.id)
            }
        } label: {
            HStack(spacing: 4) {
                if !isRejected {
                    if isPerson {
                        Image(systemName: "person.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Self.mentionTint(for: entity.entityTypeEnum))
                    } else {
                        Circle()
                            .fill(Self.mentionTint(for: entity.entityTypeEnum))
                            .frame(width: 5, height: 5)
                    }
                }
                Text(entity.value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isRejected ? Crucible.Color.ink4 : Crucible.Color.ink2)
                    .strikethrough(isRejected, color: Crucible.Color.ink4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.black.opacity(isRejected ? 0.02 : 0.05))
            .overlay(
                Capsule()
                    .stroke(isRejected ? Crucible.Color.hairline : Color.clear, lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(mentionsCommitted)
    }

    /// Type-indicator dot color. Subtle — meant to be a glance
    /// signal, not a category label. Person/project/issue/idea map
    /// to four warm/cool tints that read at chip scale. `internal`
    /// so the standalone Mentions section in `EntryExpandedView`
    /// reads from the same source of truth.
    static func mentionTint(for type: ExtractedEntity.EntityType) -> Color {
        switch type {
        case .person:     return Crucible.Color.accent
        case .project:    return Crucible.Color.success
        case .issue:      return Crucible.Color.warning
        case .idea:       return Crucible.Color.info
        case .nextAction: return Crucible.Color.accent // unreached — filtered out upstream
        }
    }

    @ViewBuilder
    private func nextStepsContent(_ steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(steps, id: \.self) { step in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(Crucible.Color.ink4)
                        .frame(width: 4, height: 4)
                    Text(step)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Crucible.Color.ink2)
                        .lineSpacing(2)
                }
            }
        }
    }

    // MARK: - Footer

    /// True when the footer would render any visible button — the
    /// refresh action (stale memories OR out-of-assists upsell),
    /// or the Accept all / Accept remaining bulk button (any row
    /// still pending). When false, suppressing the footer entirely
    /// avoids leaving an empty paper-colored strip below the rows.
    private var footerHasContent: Bool {
        if isStale { return true }
        if canRefresh && !allRenderedRowsCommitted { return true }
        return !allRenderedRowsCommitted
    }

    /// True when the stale-state should render the full
    /// "Reorganize with AI" affordance instead of the compact in-card
    /// buttons. After the assist-quota retirement (PR 8c), the big
    /// card is the reorganize callout (no exhausted variants).
    private var usesBigStaleCard: Bool { isStale }

    /// New-clips count drives the `.reorganize` callout copy. Falls
    /// back to 0 when the count isn't available so the surface still
    /// renders during the 8c → 8d transition. This card is being
    /// deleted in 8d.
    private var newClipsSinceOrganize: Int {
        max(entry.clipsAddedSinceLastOrganize, 0)
    }

    @ViewBuilder
    private var footer: some View {
        if usesBigStaleCard {
            // Dashed reorganize callout. Tap fires another organize
            // pass via `onRefresh`.
            OrganizeMemoryCard(
                state: .reorganize(newClipCount: newClipsSinceOrganize),
                onOrganize: onRefresh,
                isProcessing: isProcessing
            )
        } else {
            HStack(spacing: 8) {
                if canRefresh {
                    refreshButton
                    Spacer()
                    if !allRenderedRowsCommitted {
                        applyAllButton(filled: false)
                    }
                } else if !allRenderedRowsCommitted {
                    applyAllButton(filled: true)
                    Spacer()
                }
            }
        }
    }

    private func applyAllButton(filled: Bool) -> some View {
        // Label is independent of fill: "Accept all" reads honestly
        // when nothing's been individually accepted yet, "Accept
        // remaining" reads honestly once at least one row has.
        // Pre-2026-05-27 the label was derived from `filled` which
        // conflated visual treatment with semantic state.
        let label = noRenderedRowsCommitted ? "Accept all" : "Accept remaining"
        return Button(action: applyAll) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(filled ? Crucible.Color.accentInk : Crucible.Color.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(filled ? Crucible.Color.ink : Crucible.Color.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(filled ? Color.clear : Crucible.Color.hairline, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private var refreshButton: some View {
        Button(action: canRefresh ? onRefresh : onOpenPackSheet) {
            HStack(spacing: 6) {
                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    // No clockwise arrow when it's the "See plans"
                    // route — the upgrade hub isn't a refresh.
                    Image(systemName: canRefresh ? "arrow.clockwise" : "arrow.up.forward")
                        .font(.system(size: 11, weight: .bold))
                }
                Text(isProcessing ? "Working…" : refreshButtonLabel)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // Ochre in both branches. The "Out of assists · See plans"
            // variant is still an active CTA (routes to the pack
            // sheet); greying it suggested "disabled" when the button
            // actually drives forward. Per pricing spec § 2.E the
            // "See options" link is accent-colored.
            .background(Crucible.Color.accent)
            .opacity(isProcessing ? 0.85 : 1.0)
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .accessibilityLabel(canRefresh ? refreshButtonLabel : "Out of assists, tap to see plans")
    }

    /// "Refresh" implies the AI has new material to work with — stale
    /// memories. "Re-run" tells the user the AI hasn't seen anything
    /// new but they're explicitly asking for another pass. The label
    /// IS the disclosure — both routes cost one assist; pressing the
    /// button is the decision. No confirmation dialog. When the user
    /// has no assists, the button is greyed and the label calls out
    /// the constraint — tap routes to the buy-assists sheet.
    private var refreshButtonLabel: String {
        if !canRefresh { return "Out of assists · See plans" }
        return isStale ? "Refresh · 1 assist" : "Re-run · 1 assist"
    }

    // MARK: - Commit logic

    private func applyAll() {
        let ctx = entry.managedObjectContext ?? StorageService.shared.viewContext
        ctx.performAndWait {
            if !titleCommitted, let title = pass.suggestedTitle, !title.isEmpty {
                commitTitle(title)
            }
            if !summaryCommitted, let s = pass.summaryText, !s.isEmpty {
                // Same accept-as-is path as the per-row button.
                // Doesn't mutate the stored token form.
                acceptSummary()
            }
            if !topicsCommitted, !pass.suggestedTopics.isEmpty {
                commitTopics(pass.suggestedTopics)
            }
            if !mentionsCommitted, !mentionEntities.isEmpty {
                commitMentions()
            }
            if !nextStepsCommitted, !pass.nextStepsItems.isEmpty {
                commitNextSteps(pass.nextStepsMarkdown)
            }
            pass.dismissedAt = Date()
            try? ctx.save()
        }
        onDismiss()
    }

    /// Writes the title back into `entry.title` and marks
    /// `titleSourcedFromAI` true. The flag drives the `✦ AI` tag next
    /// to the title in `titleSection`. Also persists the acceptance
    /// into `pass.acceptedRowsJSON` so the row stays committed across
    /// card open/close cycles.
    private func commitTitle(_ newTitle: String) {
        entry.title = newTitle
        entry.titleSourcedFromAI = true
        pass.markRowAccepted(.title)
        titleCommitted = true
        try? entry.managedObjectContext?.save()
        scheduleAutoCollapseIfDone()
    }

    /// Summary lives on the pass itself — accepting just records the
    /// (possibly user-edited) text into `pass.summaryText`. Persists
    /// inside the card; no entry-level home, by design (strict v5
    /// rule — derived content doesn't demote primary media).
    /// Accepts the AI's summary as-is without modifying the stored
    /// text. Preserves the `<user>` token in storage so share-time
    /// substitution can swap in the user's first name. Used by the
    /// per-row Accept button and Apply all.
    private func acceptSummary() {
        pass.markRowAccepted(.summary)
        summaryCommitted = true
        try? pass.managedObjectContext?.save()
        scheduleAutoCollapseIfDone()
    }

    /// Saves a hand-edited summary. The edited text overwrites the
    /// AI's tokenized form — from this point on, the summary is a
    /// literal string. Both renderers pass it through unchanged
    /// because there's no `<user>` token to substitute.
    private func commitSummary(_ newSummary: String) {
        pass.summaryText = newSummary
        pass.markRowAccepted(.summary)
        summaryCommitted = true
        try? pass.managedObjectContext?.save()
        scheduleAutoCollapseIfDone()
    }

    /// Topics already exist as `Topic` ←→ `JournalEntry` relationships
    /// from `ProcessingEngine.assignTopics`. The acceptance step
    /// applies any per-chip rejections (removing those Topic
    /// relationships from the entry) and marks the row accepted.
    /// Topic entities themselves stay in the store — only the entry's
    /// relationship to them is cleared, matching how mentions handle
    /// rejection at the relationship level.
    private func commitTopics(_ names: [String]) {
        let ctx = entry.managedObjectContext ?? StorageService.shared.viewContext
        ctx.performAndWait {
            Self.applyTopicRejections(rejectedTopicNames: rejectedTopicNames, to: entry)
            pass.markRowAccepted(.topics)
            try? ctx.save()
        }
        topicsCommitted = true
        scheduleAutoCollapseIfDone()
    }

    /// Pure: removes the entry's `topics` relationships whose name is
    /// in `rejectedTopicNames`. The Topic entities themselves stay in
    /// the store (other entries may still reference them). Extracted
    /// so the rejection logic can be unit-tested without driving the
    /// SwiftUI card.
    static func applyTopicRejections(rejectedTopicNames: Set<String>, to entry: JournalEntry) {
        guard !rejectedTopicNames.isEmpty,
              let topics = entry.topics as? Set<Topic> else { return }
        for topic in topics where rejectedTopicNames.contains(topic.name) {
            entry.removeFromTopics(topic)
        }
    }

    private func commitNextSteps(_ markdown: String?) {
        pass.nextStepsMarkdown = markdown
        pass.markRowAccepted(.nextSteps)
        nextStepsCommitted = true
        try? pass.managedObjectContext?.save()
        scheduleAutoCollapseIfDone()
    }

    /// Mentions commit: deletes any `ExtractedEntity` rows the user
    /// rejected via per-chip opt-out (`rejectedMentionIDs`). Selected
    /// rows persist as they were already written by
    /// `ProcessingEngine.storeEntities`. After commit, the row mutes
    /// and the legacy Mentions disclosure further down reflects the
    /// pruned set automatically.
    private func commitMentions() {
        let ctx = entry.managedObjectContext ?? StorageService.shared.viewContext
        ctx.performAndWait {
            for entity in entry.entitiesArray where rejectedMentionIDs.contains(entity.id) {
                ctx.delete(entity)
            }
            pass.markRowAccepted(.mentions)
            try? ctx.save()
        }
        mentionsCommitted = true
        scheduleAutoCollapseIfDone()
    }

    // MARK: - Editor sheets

    @ViewBuilder
    private func editorSheet(for field: Field) -> some View {
        switch field {
        case .title:
            TitleEditorSheet(
                initial: pass.suggestedTitle ?? "",
                onSave: { newValue in
                    commitTitle(newValue)
                    editing = nil
                },
                onCancel: { editing = nil }
            )
        case .summary:
            SummaryEditorSheet(
                initial: pass.summaryText ?? "",
                onSave: { newValue in
                    commitSummary(newValue)
                    editing = nil
                },
                onCancel: { editing = nil }
            )
        case .topics:
            // Topics editing is held back to the read-only acknowledge
            // pattern for v1 — the sheet shows the suggested topics
            // with a confirm action. Full add/remove of topic
            // relationships is a follow-up that lives next to the
            // existing Topic editor in Settings.
            TopicsAcknowledgeSheet(
                names: pass.suggestedTopics,
                onSave: {
                    commitTopics(pass.suggestedTopics)
                    editing = nil
                },
                onCancel: { editing = nil }
            )
        case .mentions:
            // Same acknowledge-only pattern as Topics for v1.
            // Per-mention removal lives in the legacy Mentions
            // disclosure further down the memory body, where the
            // edit affordance has been honed over multiple rounds.
            MentionsAcknowledgeSheet(
                entities: mentionEntities,
                onSave: {
                    commitMentions()
                    editing = nil
                },
                onCancel: { editing = nil }
            )
        case .nextSteps:
            NextStepsEditorSheet(
                initial: pass.nextStepsMarkdown ?? "",
                onSave: { newValue in
                    commitNextSteps(newValue)
                    editing = nil
                },
                onCancel: { editing = nil }
            )
        }
    }
}

// MARK: - Editor sheets

private struct TitleEditorSheet: View {
    let initial: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Crucible.Color.paper.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 12) {
                    Text("TITLE")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(Crucible.Color.ink3)
                    TextField("Title", text: $text, axis: .vertical)
                        .font(PricingFonts.serif(20))
                        .foregroundStyle(Crucible.Color.ink)
                        .padding(12)
                        .background(Crucible.Color.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Crucible.Color.hairline, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Edit title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        .fontWeight(.semibold)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { text = initial }
        }
    }
}

private struct SummaryEditorSheet: View {
    let initial: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Crucible.Color.paper.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 12) {
                    Text("SUMMARY")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(Crucible.Color.ink3)
                    TextEditor(text: $text)
                        .font(.system(size: 14))
                        .foregroundStyle(Crucible.Color.ink)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Crucible.Color.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Crucible.Color.hairline, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .frame(minHeight: 160)
                }
                .padding(20)
            }
            .navigationTitle("Edit summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(text) }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { text = initial }
        }
    }
}

private struct TopicsAcknowledgeSheet: View {
    let names: [String]
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Crucible.Color.paper.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    Text("TOPICS")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(Crucible.Color.ink3)
                    Text("These topics were applied automatically when the AI ran. Accept to acknowledge, or cancel to leave them pending in the card.")
                        .font(.system(size: 13))
                        .foregroundStyle(Crucible.Color.ink2)
                        .lineSpacing(2)
                    FlowLayout(spacing: 6) {
                        ForEach(names, id: \.self) { name in
                            let hue = Crucible.Color.topicHue(for: name)
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(hue.fg)
                                    .frame(width: 5, height: 5)
                                Text(name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Crucible.Color.ink2)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.05))
                            .clipShape(Capsule())
                        }
                    }
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Topics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Accept", action: onSave).fontWeight(.semibold)
                }
            }
        }
    }
}

private struct MentionsAcknowledgeSheet: View {
    let entities: [ExtractedEntity]
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Crucible.Color.paper.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    Text("MENTIONS")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(Crucible.Color.ink3)
                    Text("People, projects, issues, and ideas the AI found in this memory. Accept to acknowledge — to remove or edit individual mentions, use the Mentions disclosure further down the memory.")
                        .font(.system(size: 13))
                        .foregroundStyle(Crucible.Color.ink2)
                        .lineSpacing(2)
                    FlowLayout(spacing: 6) {
                        ForEach(entities, id: \.id) { entity in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(mentionTint(for: entity.entityTypeEnum))
                                    .frame(width: 5, height: 5)
                                Text(entity.value)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Crucible.Color.ink2)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.05))
                            .clipShape(Capsule())
                        }
                    }
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Mentions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Accept", action: onSave).fontWeight(.semibold)
                }
            }
        }
    }

    private func mentionTint(for type: ExtractedEntity.EntityType) -> Color {
        switch type {
        case .person:     return Crucible.Color.accent
        case .project:    return Crucible.Color.success
        case .issue:      return Crucible.Color.warning
        case .idea:       return Crucible.Color.info
        case .nextAction: return Crucible.Color.accent
        }
    }
}

private struct NextStepsEditorSheet: View {
    let initial: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Crucible.Color.paper.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 12) {
                    Text("NEXT STEPS")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(Crucible.Color.ink3)
                    Text("One item per line. Lines starting with -, *, or • render as bullets.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Crucible.Color.ink3)
                    TextEditor(text: $text)
                        .font(.system(size: 14))
                        .foregroundStyle(Crucible.Color.ink)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Crucible.Color.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Crucible.Color.hairline, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .frame(minHeight: 200)
                }
                .padding(20)
            }
            .navigationTitle("Edit next steps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(text) }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { text = initial }
        }
    }
}
