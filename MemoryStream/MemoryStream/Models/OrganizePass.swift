import Foundation
import CoreData

/// One successful AI organize pass against a `JournalEntry`. Each pass
/// costs 1 assist (deducted only on success — failures cost zero, per
/// the v2 pricing spec).
///
/// Holds the three typed AI outputs surfaced in the memory's Done
/// state: a prose summary, a markdown bullet list of next steps, and
/// a JSON-encoded array of related entry UUIDs. None of these are
/// repurposed from existing fields — this entity is purely additive
/// so old code paths keep working until they're migrated.
///
/// Many-to-one with `JournalEntry.organizePasses`; the latest pass
/// (highest `createdAt`) is what the UI renders. Older passes are
/// retained for history / undo / feedback-tracking.
@objc(OrganizePass)
public class OrganizePass: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var entryId: UUID
    @NSManaged public var createdAt: Date
    @NSManaged public var summaryText: String?
    /// AI's suggested title for this pass. Lives here until the user
    /// accepts it via the Title row of the AISuggestionsCard; on accept,
    /// flows into `entry.title` and sets `entry.titleSourcedFromAI`.
    /// Held pending here so unaccepted suggestions don't auto-write
    /// over user-authored titles.
    @NSManaged public var suggestedTitle: String?
    /// AI's suggested topic names as a JSON array of strings. Lives
    /// here until the user accepts via the Topics row. Currently
    /// preserved-but-supplementary — the existing topic-assignment
    /// pipeline still auto-creates Topic relationships at processing
    /// time, this column just lets the Topics row show what the AI
    /// would have picked if rerun.
    @NSManaged public var suggestedTopicsJSON: String?
    @NSManaged public var relatedEntryIDsJSON: String?
    /// Set when the user dismisses the AISuggestionsCard (Accept all
    /// OR ×). The card defaults to its collapsed chip on subsequent
    /// renders when this is non-nil. Per-view fold/unfold after that
    /// point is ephemeral local state — `dismissedAt` doesn't move.
    /// A new OrganizePass (e.g., from Refresh) starts with nil.
    @NSManaged public var dismissedAt: Date?
    /// JSON array of accepted row keys ("title", "summary", "topics",
    /// "mentions", "nextSteps"). Persists per-row commit state across
    /// card open/close cycles — without this, the AISuggestionsCard's
    /// @State commit booleans reset every time the user folds and
    /// re-opens the chip, making accepted suggestions appear pending
    /// again. Source of truth for the row-level ✓ + ochre tint.
    @NSManaged public var acceptedRowsJSON: String?
    @NSManaged public var feedbackState: String?
    @NSManaged public var feedbackAt: Date?
    @NSManaged public var userCorrection: String?
    @NSManaged public var entry: JournalEntry?
}

extension OrganizePass {
    /// Decoded list of related entry IDs from the JSON column. Empty
    /// array on parse failure or nil column — callers don't need to
    /// distinguish.
    var relatedEntryIDs: [UUID] {
        guard let json = relatedEntryIDsJSON, let data = json.data(using: .utf8) else { return [] }
        guard let strings = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return strings.compactMap { UUID(uuidString: $0) }
    }

    func setRelatedEntryIDs(_ ids: [UUID]) {
        let strings = ids.map(\.uuidString)
        if let data = try? JSONEncoder().encode(strings),
           let json = String(data: data, encoding: .utf8) {
            relatedEntryIDsJSON = json
        } else {
            relatedEntryIDsJSON = nil
        }
    }

    /// Decoded list of suggested topic names from the JSON column.
    /// Empty array on parse failure or nil column.
    var suggestedTopics: [String] {
        guard let json = suggestedTopicsJSON, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    func setSuggestedTopics(_ names: [String]) {
        if let data = try? JSONEncoder().encode(names),
           let json = String(data: data, encoding: .utf8) {
            suggestedTopicsJSON = json
        } else {
            suggestedTopicsJSON = nil
        }
    }

    /// Stable string keys for the AISuggestionsCard's rows. Used as
    /// values in `acceptedRowsJSON` so the per-row commit state can
    /// survive card open/close cycles. New row types extend this
    /// enum and pick a stable key string.
    enum AcceptedRowKey: String {
        case title
        case summary
        case topics
        case mentions
        /// DORMANT (RH-6, July 20 2026): `nextSteps` is cut from v1 — no
        /// organize output produces it and no UI consumes it. The enum case
        /// is deliberately KEPT so a post-v1 re-add (with a durable editable
        /// home) can reuse the accepted-row plumbing without a schema/JSON
        /// migration. Nothing writes this row today.
        case nextSteps
    }

    /// Decoded set of accepted row keys. Empty when the column is
    /// nil, missing, or malformed.
    var acceptedRows: Set<AcceptedRowKey> {
        guard let json = acceptedRowsJSON, let data = json.data(using: .utf8) else { return [] }
        let strings = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        return Set(strings.compactMap { AcceptedRowKey(rawValue: $0) })
    }

    /// Records that the user accepted a row. Idempotent — re-accepting
    /// the same row is a no-op. Caller is responsible for `try ctx.save()`.
    func markRowAccepted(_ key: AcceptedRowKey) {
        var current = acceptedRows
        current.insert(key)
        writeAcceptedRows(current)
    }

    /// Records acceptance of multiple rows at once — used by Apply
    /// all / Accept all so the JSON write is a single round-trip.
    func markRowsAccepted(_ keys: Set<AcceptedRowKey>) {
        var current = acceptedRows
        current.formUnion(keys)
        writeAcceptedRows(current)
    }

    private func writeAcceptedRows(_ rows: Set<AcceptedRowKey>) {
        let strings = rows.map(\.rawValue).sorted()
        if let data = try? JSONEncoder().encode(strings),
           let json = String(data: data, encoding: .utf8) {
            acceptedRowsJSON = json
        } else {
            acceptedRowsJSON = nil
        }
    }

    /// Derived "user has reviewed this pass" signal — drives the
    /// Memory Detail chip between **Draft organized** (dashed AI
    /// chip, "this is a first draft, give it a glance") and
    /// **Organized** (solid AI chip, "you've signed off"). True
    /// when the user has dismissed the review card OR accepted any
    /// row from it. Per `docs/design/AI Organize · spec.md` §2b/§9
    /// and `pricing-screens-lifecycle.jsx`: the chip tracks REVIEW
    /// STATE, not tier — a Plus auto-organize pass also reads as
    /// "Draft organized" until the user engages with it.
    var isReviewed: Bool {
        dismissedAt != nil || !acceptedRows.isEmpty
    }

    /// Commits the user's per-field choices from the Reorganize
    /// review sheet to this pass and the underlying `JournalEntry`.
    /// Pure value-shuffling — no Core Data save (caller wraps in
    /// `context.performAndWait` and saves). Mirrors the contract
    /// from `AI Organize · spec.md` §8.0 (June 6 2026):
    ///
    /// - **Title kept current** → `suggestedTitle` is overwritten with
    ///   the entry's existing title. The latest pass always reflects
    ///   what's actually shown; no stored v1-vs-v2 branching.
    /// - **Title accepted new** → `entry.title` is updated with
    ///   `suggestedTitle`; `titleSourcedFromAI = true`. Same path as
    ///   the first-organize DraftReviewSheet's "Looks good."
    /// - **Summary kept current** → `summaryText` is overwritten with
    ///   `previousSummary` (the prior pass's summary, captured before
    ///   the reorganize fired).
    /// - **Summary accepted new** → no write; the pass already holds
    ///   the new summary text.
    ///
    /// In all cases: `acceptedRows` gains `.title` and `.summary`,
    /// `dismissedAt` becomes now, and `isReviewed` flips true → chip
    /// returns to plain "Organized" on the next render.
    func commitReorganize(
        on entry: JournalEntry,
        titleChoice: ReorgFieldChoice,
        summaryChoice: ReorgFieldChoice,
        previousSummary: String
    ) {
        switch titleChoice {
        case .new:
            if let newTitle = suggestedTitle, !newTitle.isEmpty {
                entry.title = newTitle
                entry.titleSourcedFromAI = true
            }
        case .current:
            suggestedTitle = entry.title
        }

        switch summaryChoice {
        case .new:
            // Per the unified-editing model (Tom 2026-06-09): the
            // canonical working summary lives on `JournalEntry.summary`.
            // Copy the AI's accepted new wording there so the Memory
            // Detail surface (which now reads `entry.summary` first
            // via `renderedSummary`) shows the freshly-accepted text.
            // Do NOT set `summaryUserEdited` — that marker is reserved
            // for user tap-to-edits and gates the auto-pass-no-clobber
            // rule. Accepting an AI suggestion is not a "user edit"
            // for that purpose.
            if let newSummary = summaryText, !newSummary.isEmpty {
                entry.summary = newSummary
            }
        case .current:
            summaryText = previousSummary
            // Current kept → `entry.summary` already holds whatever
            // the user was looking at (either a previously-accepted
            // AI summary or a user tap-to-edit). Nothing to do.
        }

        markRowsAccepted([.title, .summary])
        dismissedAt = Date()
    }
}
