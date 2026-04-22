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
    let audioFilePath: String?
    let inferenceSummary: String?
    let feedbackState: InferenceSummary.FeedbackState?
    let mediaItems: [MediaDisplayItem]

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
        guard let processingStatus else { return nil }
        switch processingStatus {
        case .pending:
            return DisplayStatus(text: "Queued", style: .processing)
        case .processing:
            return DisplayStatus(text: "Parsing now", style: .processing)
        case .completed:
            if inferenceSummary != nil, feedbackState == nil {
                return nil // Show inference card instead
            }
            return DisplayStatus(text: "Processed", style: .confirmed)
        case .failed:
            return DisplayStatus(text: "Failed", style: .failed)
        }
    }

    var mediaSummary: String? {
        var parts: [String] = []
        if audioFilePath != nil { parts.append("1 audio") }
        let photoCount = mediaItems.filter { $0.mediaType == .image }.count
        let videoCount = mediaItems.filter { $0.mediaType == .video }.count
        if photoCount > 0 { parts.append("\(photoCount) photo\(photoCount == 1 ? "" : "s")") }
        if videoCount > 0 { parts.append("\(videoCount) video\(videoCount == 1 ? "" : "s")") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var hasAudio: Bool { audioFilePath != nil }
    var photoCount: Int { mediaItems.filter { $0.mediaType == .image }.count }
    var videoCount: Int { mediaItems.filter { $0.mediaType == .video }.count }
}

extension EntryDisplayModel: Hashable {
    static func == (lhs: EntryDisplayModel, rhs: EntryDisplayModel) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct DisplayStatus {
    let text: String
    let style: StatusBadge.BadgeStyle
}

// MARK: - Media Display Model

struct MediaDisplayItem: Identifiable {
    let id: UUID
    let localIdentifier: String
    let mediaType: MediaReference.MediaType
    let thumbnailCacheFilename: String?
    let isAccessible: Bool
}

// MARK: - Tag Display Model

struct TagDisplayModel: Identifiable {
    let id: UUID
    let value: String
    let entityType: ExtractedEntity.EntityType
    let confidence: Double
}
