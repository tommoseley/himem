import Foundation

// MARK: - Card Density

enum CardDensity: String, CaseIterable {
    case compact, standard, rich

    var label: String {
        switch self {
        case .compact: return "Compact"
        case .standard: return "Standard"
        case .rich: return "Rich"
        }
    }

    var icon: String {
        switch self {
        case .compact: return "rectangle.compress.vertical"
        case .standard: return "list.bullet.rectangle.portrait"
        case .rich: return "rectangle.expand.vertical"
        }
    }

    var next: CardDensity {
        switch self {
        case .compact: return .standard
        case .standard: return .rich
        case .rich: return .compact
        }
    }

    var contentLineLimit: Int? {
        switch self {
        case .compact: return 2
        case .standard: return 4
        case .rich: return nil
        }
    }
}

// MARK: - Entry Display Model

struct EntryDisplayModel: Identifiable {
    let id: UUID
    let displayTitle: String
    let content: String
    let inputType: JournalEntry.InputType
    let createdAt: Date
    let processingStatus: ProcessingTask.Status?
    let progressDescription: String?
    let tags: [TagDisplayModel]
    let topicNames: [String]
    let inferenceSummary: String?
    let feedbackState: InferenceSummary.FeedbackState?
    let userCorrection: String?
    let mediaItems: [MediaDisplayItem]
    let recycledAt: Date?
    let latitude: Double?
    let longitude: Double?
    let locationName: String?
    /// Owner-rendered AI summary from the latest organize pass, if the
    /// summary row has been accepted. Used by the feed card to replace
    /// the raw-content snippet when present. Nil otherwise.
    let renderedSummary: String?

    var timeString: String {
        let interval = Date().timeIntervalSince(createdAt)
        if interval < 60 { return "Just now" }
        if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min ago"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: createdAt)
    }

    var displayStatus: DisplayStatus? {
        // Siri entries show "Captured" until the user has interacted
        if inputType == .siri && feedbackState == nil && processingStatus == .completed {
            return DisplayStatus(text: "Captured", style: .captured)
        }
        if let feedbackState {
            let style: StatusBadge.BadgeStyle = switch feedbackState {
            case .confirmed: .confirmed
            case .edited: .edited
            case .ignored: .ignored
            }
            return DisplayStatus(text: feedbackState.displayLabel, style: style)
        }
        // If we have an inference summary and the user hasn't yet given
        // feedback, the inference card is the answer — suppress any
        // processing pill regardless of what the task status says.
        // Defends against state drift where the inference lands but the
        // task row hasn't merged its `.completed` status into viewContext
        // yet (CloudKit sync race, context merge timing, or an interrupted
        // run that left an old task at `.processing`).
        if inferenceSummary != nil { return nil }
        guard let processingStatus else { return nil }
        switch processingStatus {
        case .pending:
            return DisplayStatus(text: "Queued", style: .processing)
        case .processing:
            return DisplayStatus(text: "Parsing now", style: .processing)
        case .completed:
            return DisplayStatus(text: "Processed", style: .confirmed)
        case .failed:
            return DisplayStatus(text: "Failed", style: .failed)
        }
    }

    var mediaSummary: String? {
        var parts: [String] = []
        let audioCount = mediaItems.filter { $0.mediaType == .voice }.count
        let photoCount = mediaItems.filter { $0.mediaType == .image }.count
        let videoCount = mediaItems.filter { $0.mediaType == .video }.count
        if audioCount > 0 { parts.append("\(audioCount) audio") }
        if photoCount > 0 { parts.append("\(photoCount) photo\(photoCount == 1 ? "" : "s")") }
        if videoCount > 0 { parts.append("\(videoCount) video\(videoCount == 1 ? "" : "s")") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var hasAudio: Bool { mediaItems.contains { $0.mediaType == .voice } }
}

extension EntryDisplayModel: Equatable {
    /// Field-by-field equality so SwiftUI's diffing actually re-renders cards
    /// when the underlying data updates. The previous id-only equality was
    /// short-circuiting renders: when `JournalViewModel` replaced the entries
    /// array with snapshots holding fresh `displayTitle` / `inferenceSummary` /
    /// `processingStatus` / etc., SwiftUI saw `lhs.id == rhs.id`, declared the
    /// structs identical, and skipped re-rendering — so the card kept showing
    /// the very first snapshot's data until a cold launch forced a re-render.
    static func == (lhs: EntryDisplayModel, rhs: EntryDisplayModel) -> Bool {
        lhs.id == rhs.id
            && lhs.displayTitle == rhs.displayTitle
            && lhs.content == rhs.content
            && lhs.inputType == rhs.inputType
            && lhs.createdAt == rhs.createdAt
            && lhs.processingStatus == rhs.processingStatus
            && lhs.progressDescription == rhs.progressDescription
            && lhs.tags == rhs.tags
            && lhs.topicNames == rhs.topicNames
            && lhs.inferenceSummary == rhs.inferenceSummary
            && lhs.feedbackState == rhs.feedbackState
            && lhs.userCorrection == rhs.userCorrection
            && lhs.mediaItems == rhs.mediaItems
            && lhs.recycledAt == rhs.recycledAt
            && lhs.latitude == rhs.latitude
            && lhs.longitude == rhs.longitude
            && lhs.locationName == rhs.locationName
            && lhs.renderedSummary == rhs.renderedSummary
    }
}

extension EntryDisplayModel {
    /// Returns a copy with feedback state updated. Used for optimistic UI on
    /// confirm/adjust/dismiss before the persisted save lands. Avoids the
    /// fragile 17-arg constructor reconstruction at the call site.
    func with(feedbackState: InferenceSummary.FeedbackState?, userCorrection: String? = nil) -> EntryDisplayModel {
        EntryDisplayModel(
            id: id,
            displayTitle: displayTitle,
            content: content,
            inputType: inputType,
            createdAt: createdAt,
            processingStatus: processingStatus,
            progressDescription: progressDescription,
            tags: tags,
            topicNames: topicNames,
            inferenceSummary: inferenceSummary,
            feedbackState: feedbackState,
            userCorrection: userCorrection ?? self.userCorrection,
            mediaItems: mediaItems,
            recycledAt: recycledAt,
            latitude: latitude,
            longitude: longitude,
            locationName: locationName,
            renderedSummary: renderedSummary
        )
    }
}

struct DisplayStatus {
    let text: String
    let style: StatusBadge.BadgeStyle
}

// MARK: - Media Display Model

struct MediaDisplayItem: Identifiable, Equatable {
    let id: UUID
    let localIdentifier: String
    let mediaType: MediaReference.MediaType
    let thumbnailCacheFilename: String?
    let isAccessible: Bool
    /// Per-clip speech-recognition transcript captured at recording time.
    /// `nil` for image/video items and for legacy voice refs created before
    /// the schema gained this field.
    var transcript: String? = nil
    /// Body text for `.note` MediaReferences. `nil` for every other media
    /// type.
    var text: String? = nil
    /// Wall-clock timestamp the capture was taken — used to interleave
    /// fragments in the chronological capture stream.
    var createdAt: Date = .distantPast
    /// Cached reverse-geocoded place name — feeds the clip-row header
    /// per the Memory Detail v3 spec: "Sun May 17 · 6:12 PM ·
    /// Bishop St, Bluffton". Nil while resolve is in flight, for
    /// legacy clips, and for `.note` fragments.
    var placeName: String? = nil
}

// MARK: - Tag Display Model

struct TagDisplayModel: Identifiable, Equatable {
    let id: UUID
    let value: String
    let entityType: ExtractedEntity.EntityType
    let confidence: Double
}
