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
    @NSManaged public var nextStepsMarkdown: String?
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

    /// Convenience: parse `nextStepsMarkdown` into bullet items. Same
    /// minimum-viable parser as `OrganizeDoneSections.NextStepsBullets`
    /// — splits on newlines, strips leading "- ", "* ", "• ". Empty
    /// when the column is nil or blank. Used by the chip variant
    /// ("N next steps") to count items, and by the AISuggestionsCard
    /// Next steps row to render bullets.
    var nextStepsItems: [String] {
        guard let md = nextStepsMarkdown else { return [] }
        return md
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line -> String in
                var s = line.trimmingCharacters(in: .whitespaces)
                for prefix in ["- ", "* ", "• "] {
                    if s.hasPrefix(prefix) { s.removeFirst(prefix.count); break }
                }
                return s
            }
            .filter { !$0.isEmpty }
    }
}
