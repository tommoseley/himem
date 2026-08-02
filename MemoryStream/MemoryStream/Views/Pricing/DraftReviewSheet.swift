import SwiftUI
import CoreData

/// B1 review sheet — replaces the assist-quota-era `AISuggestionsCard`
/// per `docs/design/pricing-screens-lifecycle.jsx` `ScrLifeReviewSheet`.
///
/// Surface:
///
///   • Header chip — "Draft organized" (the dashed `OrganizedChip`).
///   • Title — *"A draft from your device."*
///   • Body — *"Make sure it sounds like you. Keep it as is, or
///     edit anything that's a little off."*
///   • Three read-only field rows: title, summary, and **Topics**.
///     Per `AI Organize · spec.md` §2c: first-organize reviews
///     topics here, alongside title and summary. Existing-palette
///     chips render `.set` (ochre dot, wash background); NEW topics
///     render `.new` (sparkle, AI-blue dashed, "NEW" label) and tap
///     drops them before commit. This is the surface the spec named
///     as the topics review moment — the old mid-app
///     `TopicApprovalSheet` popup is retired in slice 4.
///   • Primary action — *"Looks good"* — applies the title to the
///     entry (when the entry's own title is empty), creates Topic
///     records + assigns to entry for every NEW chip that wasn't
///     dropped, marks all rows accepted, sets `pass.dismissedAt`.
///     The chip flips to *"Organized"* on the next render.
///   • Secondary action — *"Edit"* — dismisses the sheet without
///     committing the draft title. The user can edit the memory's
///     title and summary via the standard detail edit mode.
///
/// Per `AI Organize · spec.md` §2b/§9: this sheet exists so the
/// on-device draft is never silently treated as authoritative — the
/// user signs off (or chooses to edit) before the chip reads
/// *"Organized"*.
struct DraftReviewSheet: View {
    let pass: OrganizePass
    let entry: JournalEntry
    var onDismiss: () -> Void

    /// Snapshot of the user's existing palette at sheet-appear time.
    /// Used to partition `pass.suggestedTopics` into existing vs NEW.
    /// We snapshot once (rather than re-fetching on every body eval)
    /// so the review state stays stable while the user reads — a
    /// concurrent CloudKit import landing a new Topic mid-review
    /// doesn't yank chips between states.
    @State private var paletteSnapshot: [String] = []
    /// NEW chips the user has tapped to drop. Kept as the model's
    /// raw form (trimmed) so the partition's `.new` list and this
    /// set use comparable strings.
    @State private var droppedNewTopics: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header chip (provisional state — pass is unreviewed
            // when this sheet is up by construction).
            HStack {
                OrganizedChip(pass: pass)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Crucible.Color.ink3)
                        .padding(8)
                }
                .accessibilityLabel("Close")
            }
            .padding(.top, 14)
            .padding(.horizontal, 14)

            Text("A draft from your device.")
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(Crucible.Color.ink)
                .padding(.top, 12)
                .padding(.horizontal, 20)

            Text("Make sure it sounds like you. Keep it as is, or edit anything that's a little off.")
                .font(.system(size: 13.5))
                .foregroundStyle(Crucible.Color.ink2)
                .lineSpacing(2)
                .padding(.top, 8)
                .padding(.horizontal, 20)

            // Drafted fields, read-only here. The "Edit" button below
            // sends the user back to the entry's normal edit mode for
            // any changes.
            VStack(spacing: 0) {
                if let title = pass.suggestedTitle, !title.isEmpty {
                    fieldRow(label: "Title", value: title, useSerif: true)
                    if pass.summaryText?.isEmpty == false || !pass.suggestedTopics.isEmpty {
                        Divider().background(Crucible.Color.divider)
                    }
                }
                if let summary = pass.summaryText, !summary.isEmpty {
                    fieldRow(label: "Summary", value: SummaryRenderer.renderForOwner(summary), useSerif: false)
                    if !pass.suggestedTopics.isEmpty {
                        Divider().background(Crucible.Color.divider)
                    }
                }
                if !pass.suggestedTopics.isEmpty {
                    topicsRow
                }
            }
            .background(Crucible.Color.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Crucible.Color.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.top, 16)
            .padding(.horizontal, 20)

            Spacer()

            VStack(spacing: 8) {
                Button(action: commitLooksGood) {
                    Text("Looks good")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Crucible.Color.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button(action: onDismiss) {
                    Text("Edit")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Crucible.Color.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Crucible.Color.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Crucible.Color.hairline, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Crucible.Color.paper)
        .task {
            await loadPaletteSnapshot()
        }
    }

    // MARK: - Topics row (spec §2c)

    /// Topics field row — partitions `pass.suggestedTopics` against
    /// the user's palette snapshot, renders existing chips as `.set`
    /// and NEW chips as `.new` with one-tap drop. Hidden when the
    /// pass has no topic suggestions at all.
    private var topicsRow: some View {
        let partition = TopicPalette.partition(returned: pass.suggestedTopics, existing: paletteSnapshot)
        let keptNew = partition.new.filter { !droppedNewTopics.contains($0) }
        return VStack(alignment: .leading, spacing: 9) {
            Text("TOPICS")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(Crucible.Color.aiBlue)

            // Each chip sizes to its content (no text wrapping) and
            // flow-wraps to the next row when the available width
            // runs out. Shared `FlowLayout` helper from EntryCardView.
            // 10pt spacing keeps tap zones unambiguous per the June 8
            // 44pt hit-target floor.
            FlowLayout(spacing: 10) {
                ForEach(partition.existing, id: \.self) { name in
                    TopicChip(label: name, state: .set)
                }
                ForEach(keptNew, id: \.self) { name in
                    TopicChip(label: name, state: .new) {
                        droppedNewTopics.insert(name)
                    }
                }
            }

            if !partition.new.isEmpty {
                topicsExplainer(existing: partition.existing, kept: keptNew)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Spec-mockup caption: lists which chips came from the user's
    /// library vs which are NEW. Helps the user understand why the
    /// chips look different without making them read the spec.
    @ViewBuilder
    private func topicsExplainer(existing: [String], kept: [String]) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Crucible.Color.aiBlue)
            Text(Self.captionText(existing: existing, kept: kept))
                .font(.system(size: 11.5))
                .foregroundStyle(Crucible.Color.ink3)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Static caption-text builder for the Topics row explainer.
    /// Pure; extracted from the body so the four variants
    /// (existing-only / new-only / mixed / empty) are testable
    /// without a SwiftUI environment.
    ///
    /// Variants:
    /// - both lists non-empty → "X and Y from your library. Z new — tap to drop…"
    /// - existing only → "X and Y from your library."
    /// - kept new only → "Z new — tap to drop if you'd rather not start a topic."
    /// - both empty → empty string.
    ///
    /// **The caller does not hide on "both empty".** `topicsExplainer` is
    /// gated on `!partition.new.isEmpty` (`:180`), i.e. on there being any NEW
    /// topic at all — not on this caption being non-empty. So when new topics
    /// exist but the user has dropped every one of them AND there are no
    /// existing topics, the row still renders: an AI-blue sparkles glyph above
    /// an empty `Text`. `DraftReviewSheetCaptionTests` pins this function's
    /// return value; nothing tests the hiding. Corrected 2026-07-31 — the
    /// wording promised a guard the caller doesn't implement.
    static func captionText(existing: [String], kept: [String]) -> String {
        let existingPhrase = humanList(existing)
        let keptPhrase = humanList(kept)
        switch (existingPhrase.isEmpty, keptPhrase.isEmpty) {
        case (false, false):
            return "\(existingPhrase) from your library. \(keptPhrase) new — tap to drop if you'd rather not start a topic."
        case (false, true):
            return "\(existingPhrase) from your library."
        case (true, false):
            return "\(keptPhrase) new — tap to drop if you'd rather not start a topic."
        case (true, true):
            return ""
        }
    }

    /// Joins names into a human-readable list. "A", "A and B", "A, B,
    /// and C". Used in the topics caption.
    static func humanList(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default:
            let leading = items.dropLast().joined(separator: ", ")
            return "\(leading), and \(items.last!)"
        }
    }

    // MARK: - Palette snapshot

    /// Fetches the user's Topic names off the view context. Runs once
    /// when the sheet appears; subsequent reads in `topicsRow` use
    /// the snapshotted list so chip states stay stable while the user
    /// reads. The fetch is cheap (one request, name-only) so doing
    /// it on appear rather than at init is fine.
    private func loadPaletteSnapshot() async {
        let ctx = pass.managedObjectContext ?? StorageService.shared.viewContext
        let names: [String] = await ctx.perform {
            let request = NSFetchRequest<Topic>(entityName: "Topic")
            request.propertiesToFetch = ["name"]
            let topics = (try? ctx.fetch(request)) ?? []
            return topics.compactMap { $0.name }
        }
        paletteSnapshot = names
    }

    @ViewBuilder
    private func fieldRow(label: String, value: String, useSerif: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(Crucible.Color.aiBlue)
            Text(value)
                .font(useSerif
                      ? .system(size: 14, design: .serif)
                      : .system(size: 13.5))
                .foregroundStyle(Crucible.Color.ink)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Applies the draft to the entry:
    /// - **Title** — if the entry hasn't got its own, adopt the
    ///   suggested title.
    /// - **Topics** — for each NEW chip the user didn't drop,
    ///   `findOrCreateTopic` + attach to entry. Existing chips are
    ///   already attached (assignTopics handled them at organize
    ///   time); we only need to commit the survived NEW ones here.
    /// - Marks the pass reviewed (dismissedAt + every row accepted)
    ///   so the chip flips to "Organized" on next render.
    private func commitLooksGood() {
        let ctx = pass.managedObjectContext ?? StorageService.shared.viewContext
        let partition = TopicPalette.partition(returned: pass.suggestedTopics, existing: paletteSnapshot)
        let newToCommit = partition.new.filter { !droppedNewTopics.contains($0) }
        ctx.performAndWait {
            let existingTitle = entry.title ?? ""
            if existingTitle.isEmpty, let suggested = pass.suggestedTitle, !suggested.isEmpty {
                entry.title = suggested
                entry.titleSourcedFromAI = true
            }
            for newName in newToCommit {
                if let topic = try? StorageService.shared.findOrCreateTopic(name: newName, context: ctx) {
                    entry.addToTopics(topic)
                }
            }
            // Copy the accepted AI summary into `entry.summary` so the
            // Memory Detail surface (which now reads `entry.summary`
            // first via `renderedSummary`) shows the freshly-accepted
            // text. Unified-editing model (Tom 2026-06-09). Do NOT set
            // `summaryUserEdited` — that marker is reserved for user
            // tap-to-edits.
            if let summaryText = pass.summaryText, !summaryText.isEmpty {
                entry.summary = summaryText
            }
            pass.markRowsAccepted([.title, .summary, .topics, .mentions])
            pass.dismissedAt = Date()
            try? ctx.save()
        }
        onDismiss()
    }
}
