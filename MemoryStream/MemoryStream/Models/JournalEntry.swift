
import Foundation
import CoreData

@objc(JournalEntry)
public class JournalEntry: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var title: String?
    @NSManaged public var content: String
    @NSManaged public var inputType: String // "siri", "voice_in_app", "typed"
    @NSManaged public var audioFilePath: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var sourceDevice: String?
    @NSManaged public var isRecycled: Bool
    @NSManaged public var recycledAt: Date?
    @NSManaged public var lastViewedAt: Date?
    @NSManaged public var latitude: NSNumber?
    @NSManaged public var longitude: NSNumber?
    @NSManaged public var locationName: String?
    @NSManaged public var extractedEntities: NSSet?
    /// Associative-edge set to `MemoryClipEdge`. Reads walk this; writes
    /// go through `StorageService.createMediaReference` which creates
    /// the edge atomically. Membership is exclusively encoded on the
    /// edge per the v1 ontology (clip is evidence; interpretation lives
    /// on the edge). No legacy `mediaReferences` shim — v3 is the only
    /// model version.
    @NSManaged public var edges: NSSet?
    @NSManaged public var inferenceSummary: InferenceSummary?
    @NSManaged public var organizePasses: NSSet?
    @NSManaged public var textSegments: NSSet?
    @NSManaged public var topics: NSSet?
    @NSManaged public var projects: NSSet?
    /// Library-backed mentions (B4, July 18 2026) — many-to-many, replaces
    /// the per-memory `extractedEntities` mentions for display/management.
    @NSManaged public var mentions: NSSet?
    /// Timestamp of the most recent successful AI Organize pass.
    /// `nil` means this memory has never been organized. Used by the
    /// memory detail view to decide whether to show the "N new clips
    /// since last organize" Re-organize callout.
    @NSManaged public var lastOrganizedAt: Date?
    /// Canonical working summary the Memory Detail surface displays
    /// and the user edits in place. Spec: `Memory Detail · unified
    /// editing model.md` §"Where an edited summary lives" (Tom 2026-06-09).
    /// AI drafts live on `OrganizePass.summaryText`; on accept (via
    /// DraftReviewSheet) the draft is copied here. A user tap-to-edit
    /// writes here directly and sets `summaryUserEdited`. `nil` means
    /// either never-organized or never-accepted — `renderedSummary`
    /// falls back to the latest accepted OrganizePass.summaryText for
    /// pre-migration rows.
    @NSManaged public var summary: String?
    /// True iff the user has tap-to-edited the summary at least once.
    /// The load-bearing job is preventing silent overwrites by a Plus
    /// automatic Reorganize pass: when this is true, an auto-pass must
    /// only *propose* a new summary (writes OrganizePass), never
    /// directly replace `summary`. Manual Reorganize is already safe
    /// because it routes through the existing review sheet (which
    /// defaults to current — the user's edit). Never reverts the
    /// "Organized" chip → "Draft organized"; editing is an improvement,
    /// not an un-organizing. See spec §"Locked decisions" + §"AI never
    /// silently overwrites a user-edited field."
    @NSManaged public var summaryUserEdited: Bool
    /// True when the current `title` originated from an AI Organize
    /// pass that the user accepted (via the Title row of the
    /// AISuggestionsCard or via Accept all). Drives the small `✦ AI`
    /// tag rendered next to the title in `titleSection`. Cleared back
    /// to false on any subsequent manual title edit so the tag drops
    /// honestly when the user has reworded the suggestion enough that
    /// it's no longer the AI's wording.
    @NSManaged public var titleSourcedFromAI: Bool
}

// MARK: - Input Type

extension JournalEntry {
    enum InputType: String {
        case siri = "siri"
        case voiceInApp = "voice_in_app"
        case typed = "typed"
        case camera = "camera"
        case composed = "composed"
    }

    var inputTypeEnum: InputType {
        InputType(rawValue: inputType) ?? .typed
    }

    enum SourceDevice: String {
        case phone = "phone"
        case watch = "watch"
        case mac = "mac"
    }

    var sourceDeviceEnum: SourceDevice {
        SourceDevice(rawValue: sourceDevice ?? "phone") ?? .phone
    }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        // Prefer the AI's inference summary over the raw content. The
        // inference is third-person and descriptive ("This entry reflects
        // on…") which reads as a real title; using content directly reads
        // as a quote of the user's words.
        if let summaryText = inferenceSummary?.summaryText,
           let derived = Self.derivedTitle(from: summaryText), !derived.isEmpty {
            return derived
        }
        if let derived = Self.derivedTitle(from: content), !derived.isEmpty {
            return derived
        }
        switch inputTypeEnum {
        case .siri, .voiceInApp: return "Hands-free capture"
        case .typed: return "Journal entry"
        case .camera: return "Photo / Video capture"
        case .composed: return "Memory"
        }
    }

    /// Characters that ASR sometimes emits at the start of a transcript
    /// when the recognizer thinks the speaker began mid-sentence —
    /// "‚..., So here's the thought…" or ",., I'm testing…". Tom's
    /// 2026-05-27 screenshots showed both stored as content and
    /// rendered as user-visible card titles + body text. Both call
    /// sites strip this set + whitespace before display / persistence.
    static let asrLeadingNoise: Set<Character> = [",", ".", "…", "—", "–", "-", ";", ":"]

    /// Removes ASR leading-noise punctuation + whitespace from the
    /// front of a transcript. Use at ingest (`StorageService
    /// .createVoiceFragment`, `EntryLifecycleService
    /// .updateMediaTranscript`) so the stored data is clean — both
    /// what the user sees and what the AI prompt receives downstream.
    static func cleanedTranscript(_ raw: String) -> String {
        var s = Substring(raw)
        while let first = s.first,
              asrLeadingNoise.contains(first) || first.isWhitespace {
            s = s.dropFirst()
        }
        return String(s)
    }

    /// Falls back to the entry's content when the AI didn't return a title.
    /// Takes the first sentence or first ~10 words, trimmed and truncated to
    /// keep the card title compact. Returns nil for empty content (caller
    /// then uses the input-type fallback).
    static func derivedTitle(from content: String) -> String? {
        var trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Strip leading noise punctuation. Without this, a leading
        // comma + ellipsis falls into the first-sentence split and
        // produces a one-character title (",") — Tom's first
        // 2026-05-27 screenshot.
        while let first = trimmed.first,
              Self.asrLeadingNoise.contains(first) || first.isWhitespace {
            trimmed.removeFirst()
        }
        guard !trimmed.isEmpty else { return nil }

        // First sentence / line: split on . ! ? newline.
        let terminators: Set<Character> = [".", "!", "?", "\n"]
        let firstSentence: String
        if let idx = trimmed.firstIndex(where: { terminators.contains($0) }) {
            firstSentence = String(trimmed[..<idx])
        } else {
            firstSentence = trimmed
        }
        let cleaned = firstSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        // Soft word cap so long single sentences don't dominate the card.
        let words = cleaned.split(separator: " ", omittingEmptySubsequences: true)
        if words.count <= 10 { return cleaned }
        return words.prefix(10).joined(separator: " ") + "…"
    }
}

// MARK: - Relationships

extension JournalEntry {
    var entitiesArray: [ExtractedEntity] {
        let set = extractedEntities as? Set<ExtractedEntity> ?? []
        return set.sorted { $0.createdAt < $1.createdAt }
    }

    var topicsArray: [Topic] {
        let set = topics as? Set<Topic> ?? []
        return set.sorted { $0.name < $1.name }
    }

    /// Active projects this memory belongs to (F2/F3). Excludes soft-deleted
    /// (recycled) projects so a memory doesn't advertise membership in a
    /// container that's in Recently Deleted. Sorted by name for stable chip
    /// order. Many-to-many, so 0-N.
    var projectsArray: [Project] {
        let set = projects as? Set<Project> ?? []
        return set.filter { $0.recycledAt == nil }.sorted { $0.name < $1.name }
    }

    /// Library-backed mentions on this memory (B4), sorted by name for
    /// stable chip order. Many-to-many, so 0-N.
    var mentionsArray: [Mention] {
        let set = mentions as? Set<Mention> ?? []
        return set.sorted { $0.name < $1.name }
    }

    /// Clips referenced by this memory, sorted by their per-memory
    /// `orderInMemory` on the connecting `MemoryClipEdge` (falls back
    /// to `linkedAt`, then `ref.createdAt`). Walks edges — the legacy
    /// `mediaReferences` set is unused (v2 shim, retired in v3).
    var mediaReferencesArray: [MediaReference] {
        // P8 (July 19 2026): a recycled clip (`recycledAt != nil`) is in
        // Recently Deleted — excluded from every memory it's edged to, so a
        // "Delete this Clip" (soft) vanishes from all its memories while the
        // edge is preserved for restore. The edge stays; the clip hides.
        edgesArray.compactMap { $0.clip }.filter { $0.recycledAt == nil }
    }

    /// Sorted list of `MemoryClipEdge`s linking this memory to its
    /// clips. Ordering: `orderInMemory` ascending, then `linkedAt`
    /// ascending as a stable tiebreaker.
    var edgesArray: [MemoryClipEdge] {
        let set = edges as? Set<MemoryClipEdge> ?? []
        return set.sorted { lhs, rhs in
            if lhs.orderInMemory != rhs.orderInMemory {
                return lhs.orderInMemory < rhs.orderInMemory
            }
            // Nil-safe compare — `MemoryClipEdge.linkedAt` is optional
            // at the Core Data level (see `MemoryClipEdge.swift`).
            // Nil-linkedAt edges sink to the end via `.distantPast`.
            return (lhs.linkedAt ?? .distantPast) < (rhs.linkedAt ?? .distantPast)
        }
    }

    var textSegmentsArray: [TextSegment] {
        let set = textSegments as? Set<TextSegment> ?? []
        return set.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    /// Looks up the most recent `ProcessingTask` for this entry by
    /// querying the (Local-store) ProcessingTask table by `entryId`.
    /// Replaces the prior `processingTasks` relationship — see the
    /// `ProcessingTask` docstring for why the relationship had to go.
    ///
    /// Uses the entry's own managed-object context by default (or the
    /// shared viewContext if the entry isn't attached), since the
    /// Local store is on the same coordinator as the Cloud store.
    func latestProcessingTask(in ctx: NSManagedObjectContext? = nil) -> ProcessingTask? {
        let context = ctx ?? managedObjectContext ?? StorageService.shared.viewContext
        let request = NSFetchRequest<ProcessingTask>(entityName: "ProcessingTask")
        request.predicate = NSPredicate(format: "entryId == %@", id as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    var organizePassesArray: [OrganizePass] {
        let set = organizePasses as? Set<OrganizePass> ?? []
        return set.sorted { $0.createdAt > $1.createdAt }
    }

    /// The most recent successful AI organize pass for this entry, if
    /// any. Used by the memory detail view to render the "Done" state
    /// (Summary / Next steps / Related memories sections). Returns
    /// `nil` for entries that have never been organized.
    var latestOrganizePass: OrganizePass? {
        organizePassesArray.first
    }

    /// Count of media clips added after the last successful organize
    /// pass. Zero when never organized (we count from epoch in that
    /// case to mean "nothing new since organize"). Drives the
    /// "N new clips since last organize" Re-organize callout — surfaces
    /// the prompt whenever even one new clip has been added.
    var clipsAddedSinceLastOrganize: Int {
        guard let lastOrganizedAt else { return 0 }
        // "Added since organize" is a property of the EDGE (when the clip
        // joined THIS memory), not the clip's capture time. A clip
        // captured last week but attached to this memory today is new
        // *here* — the Move/Add spec's "identical to new clips arriving"
        // (`Memory Detail · unified editing model.md` §Moving clips).
        // Keying off `ref.createdAt` silently dropped that case: an old
        // clip added via the FAB never marked the memory stale, so it
        // never offered Reorganize. Fall back to `ref.createdAt` for
        // legacy edges with no `linkedAt`.
        return edgesArray.filter { edge in
            guard let ref = edge.clip, ref.recycledAt == nil else { return false }
            let addedHere = edge.linkedAt ?? ref.createdAt ?? .distantPast
            return addedHere > lastOrganizedAt
        }.count
    }

    /// Count of pre-existing clips whose content was edited after the
    /// last organize. Excludes clips added after the organize — those
    /// already count under `clipsAddedSinceLastOrganize`; double-counting
    /// would lie to the user ("1 new + 1 edited" for the same clip).
    /// Zero when never organized.
    var clipsEditedSinceLastOrganize: Int {
        guard let lastOrganizedAt else { return 0 }
        // Same edge-based "added to this memory" notion as
        // `clipsAddedSinceLastOrganize` — so a clip attached after the
        // organize is counted there (added), never double-counted here
        // (edited).
        return edgesArray.filter { edge in
            guard let ref = edge.clip, ref.recycledAt == nil else { return false }
            let addedHere = edge.linkedAt ?? ref.createdAt ?? .distantPast
            guard addedHere <= lastOrganizedAt else { return false }
            guard let edited = ref.lastEditedAt else { return false }
            return edited > lastOrganizedAt
        }.count
    }

    /// Single gate the AI Suggestions card consults to decide whether
    /// the Refresh affordance fires. True when either an add or an edit
    /// has happened after the last organize. Never-organized entries
    /// always return false — they use the first-organize affordance,
    /// not the refresh one.
    var hasChangesSinceLastOrganize: Bool {
        guard lastOrganizedAt != nil else { return false }
        return clipsAddedSinceLastOrganize > 0 || clipsEditedSinceLastOrganize > 0
    }

    /// Owner-rendered summary for surfaces outside the AI Suggestions
    /// card — memory detail header, journal feed snippet. After the
    /// unified-editing migration (Tom 2026-06-09), the canonical
    /// working summary lives on `JournalEntry.summary` — the user can
    /// tap-to-edit it in place, and `summaryUserEdited` records that
    /// touch. AI drafts still live on `OrganizePass.summaryText`; on
    /// accept (DraftReviewSheet), the draft is copied into `summary`.
    ///
    /// Fallback to the latest accepted `OrganizePass.summaryText`
    /// covers pre-migration entries whose `summary` hasn't been
    /// backfilled yet — `EntryLifecycleService.backfillSummaryFromOrganizePass`
    /// handles that on first launch. The `<user>` token in the stored
    /// form is substituted to second-person via
    /// `SummaryRenderer.renderForOwner`.
    var renderedSummary: String? {
        if let stored = summary, !stored.isEmpty {
            return SummaryRenderer.renderForOwner(stored)
        }
        guard let pass = latestOrganizePass,
              pass.acceptedRows.contains(.summary),
              let text = pass.summaryText,
              !text.isEmpty else { return nil }
        return SummaryRenderer.renderForOwner(text)
    }

    @objc(addOrganizePassesObject:)
    @NSManaged func addToOrganizePasses(_ value: OrganizePass)

    // Library-backed mentions accessors (B4). Manual @NSManaged decls —
    // this model uses no Core Data codegen, so the to-many add/remove
    // helpers are declared explicitly (mirrors addToTopics/addToProjects).
    @objc(addMentionsObject:)
    @NSManaged func addToMentions(_ value: Mention)
    @objc(removeMentionsObject:)
    @NSManaged func removeFromMentions(_ value: Mention)
}

// MARK: - Fetch Requests

extension JournalEntry {
    static func fetchAllChronological(limit: Int = 500) -> NSFetchRequest<JournalEntry> {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "isRecycled == NO OR isRecycled == nil")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \JournalEntry.createdAt, ascending: false)]
        request.fetchLimit = limit
        return request
    }

    static func fetchByTopic(_ topic: Topic) -> NSFetchRequest<JournalEntry> {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "ANY topics == %@", topic)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \JournalEntry.createdAt, ascending: false)]
        return request
    }

    static func fetchOne(id: UUID) -> NSFetchRequest<JournalEntry> {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return request
    }

    /// Pure: removes the entry's `topics` relationships whose name is
    /// in `rejectedTopicNames`. The Topic entities themselves stay in
    /// the store (other entries may still reference them). Extracted
    /// so the rejection logic can be unit-tested without driving a
    /// SwiftUI surface.
    ///
    /// Moved out of the assist-quota-era `AISuggestionsCard` so the
    /// logic survives that file's deletion in 8d.
    func applyTopicRejections(_ rejectedTopicNames: Set<String>) {
        guard !rejectedTopicNames.isEmpty,
              let topics = self.topics as? Set<Topic> else { return }
        for topic in topics where rejectedTopicNames.contains(topic.name) {
            self.removeFromTopics(topic)
        }
    }
}
