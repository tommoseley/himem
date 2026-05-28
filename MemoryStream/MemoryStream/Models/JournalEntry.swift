
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
    @NSManaged public var mediaReferences: NSSet?
    @NSManaged public var processingTasks: NSSet?
    @NSManaged public var inferenceSummary: InferenceSummary?
    @NSManaged public var organizePasses: NSSet?
    @NSManaged public var textSegments: NSSet?
    @NSManaged public var topics: NSSet?
    @NSManaged public var projects: NSSet?
    /// Timestamp of the most recent successful AI Organize pass.
    /// `nil` means this memory has never been organized. Used by the
    /// memory detail view to decide whether to show the "N new clips
    /// since last organize" Re-organize callout.
    @NSManaged public var lastOrganizedAt: Date?
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

    var mediaReferencesArray: [MediaReference] {
        let set = mediaReferences as? Set<MediaReference> ?? []
        return set.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    var textSegmentsArray: [TextSegment] {
        let set = textSegments as? Set<TextSegment> ?? []
        return set.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    var latestProcessingTask: ProcessingTask? {
        let set = processingTasks as? Set<ProcessingTask> ?? []
        return set.sorted { $0.createdAt > $1.createdAt }.first
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
        let clips = mediaReferencesArray.filter { ($0.createdAt ?? .distantPast) > lastOrganizedAt }
        return clips.count
    }

    /// Count of pre-existing clips whose content was edited after the
    /// last organize. Excludes clips added after the organize — those
    /// already count under `clipsAddedSinceLastOrganize`; double-counting
    /// would lie to the user ("1 new + 1 edited" for the same clip).
    /// Zero when never organized.
    var clipsEditedSinceLastOrganize: Int {
        guard let lastOrganizedAt else { return 0 }
        return mediaReferencesArray.filter { ref in
            // Newly added → counted as "added", not "edited".
            guard (ref.createdAt ?? .distantPast) <= lastOrganizedAt else { return false }
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
    /// card — memory detail header, journal feed snippet. Returns the
    /// summary text from the latest organize pass only when the user
    /// has accepted the summary row; nil otherwise. Storage form uses
    /// the `<user>` token, which `SummaryRenderer.renderForOwner`
    /// substitutes to second-person English.
    var renderedSummary: String? {
        guard let pass = latestOrganizePass,
              pass.acceptedRows.contains(.summary),
              let text = pass.summaryText,
              !text.isEmpty else { return nil }
        return SummaryRenderer.renderForOwner(text)
    }

    @objc(addOrganizePassesObject:)
    @NSManaged func addToOrganizePasses(_ value: OrganizePass)
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
}
