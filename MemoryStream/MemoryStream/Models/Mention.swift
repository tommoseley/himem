import Foundation
import CoreData

/// A library-backed mention — a recurring person, place, idea, or
/// organization referenced across memories. The mentions sibling of
/// `Topic` / `Project`: many-to-many to `JournalEntry`, deduped so a
/// person stays one searchable entry instead of fragmenting (Darlene /
/// Darlene G. / Darlene Graham).
///
/// **Dedup is on (normalizedName, type)** — a person "Foodies" and an org
/// "Foodies" are deliberately distinct entries (Tom, 2026-07-17); only a
/// same-name **same-type** pair merges. `normalizedName` is the stored,
/// case/whitespace-folded key the find-or-create path matches on.
///
/// Introduced in the July 18 2026 schema batch (B4). Existing per-memory
/// `ExtractedEntity` mentions are migrated in (idea→idea, person→person,
/// project→org, issue→idea, next_action skipped) by `MentionMigration`.
@objc(Mention)
public class Mention: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    /// Raw value of `MentionType`. Defaults to `idea` — the honest
    /// "uncategorized" bucket for an untyped organizer mention, never a
    /// confident-but-wrong `person` (ruled 2026-07-18).
    @NSManaged public var type: String
    /// Case/whitespace-folded `name`, the dedup key. Set on create via
    /// `Mention.normalize(_:)`; never edited independently of `name`.
    @NSManaged public var normalizedName: String
    @NSManaged public var createdAt: Date
    @NSManaged public var entries: NSSet?
}

// MARK: - Type

extension Mention {
    /// Per-type identity drives the read/manage chip glyph (unified
    /// associations glyph rule: dot = topic only; mentions carry a
    /// per-type line glyph — person · place · idea · org).
    enum MentionType: String, CaseIterable {
        case person
        case place
        case idea
        case org
    }

    /// Fallbacks to `.idea` for an unknown/missing raw value — matches the
    /// storage default and the untyped-defaults-to-idea rule.
    var mentionType: MentionType {
        MentionType(rawValue: type) ?? .idea
    }
}

// MARK: - Relationships

extension Mention {
    var entriesArray: [JournalEntry] {
        let set = entries as? Set<JournalEntry> ?? []
        return set.sorted { $0.createdAt > $1.createdAt }
    }

    var entryCount: Int {
        (entries as? Set<JournalEntry>)?.count ?? 0
    }
}

// MARK: - Normalization + fetch

extension Mention {
    /// The dedup key: trimmed, lowercased, internal whitespace collapsed.
    /// "  Darlene   Graham " and "darlene graham" resolve to one entry.
    static func normalize(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .joined(separator: " ")
    }

    static func fetchAll() -> NSFetchRequest<Mention> {
        let request = NSFetchRequest<Mention>(entityName: "Mention")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Mention.name, ascending: true)]
        return request
    }
}
