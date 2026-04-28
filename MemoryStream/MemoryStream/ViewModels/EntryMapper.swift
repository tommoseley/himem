import Foundation

/// Single source of truth for mapping JournalEntry → EntryDisplayModel.
/// Replaces 3 duplicate mapping implementations.
enum EntryMapper {
    static func mapToDisplayModel(_ entry: JournalEntry) -> EntryDisplayModel {
        let task = entry.latestProcessingTask
        let inference = entry.inferenceSummary

        return EntryDisplayModel(
            id: entry.id,
            displayTitle: entry.displayTitle,
            content: entry.content,
            inputType: entry.inputTypeEnum,
            createdAt: entry.createdAt,
            processingStatus: task?.statusEnum,
            progressDescription: task?.progressDescription,
            tags: entry.entitiesArray.map { entity in
                TagDisplayModel(
                    id: entity.id,
                    value: entity.value,
                    entityType: entity.entityTypeEnum,
                    confidence: entity.confidenceScore
                )
            },
            topicNames: entry.topicsArray.map(\.name),
            audioFilePath: entry.audioFilePath,
            inferenceSummary: inference?.summaryText,
            feedbackState: inference?.feedbackStateEnum,
            userCorrection: inference?.userCorrection,
            mediaItems: entry.mediaReferencesArray.map { ref in
                MediaDisplayItem(
                    id: ref.id,
                    localIdentifier: ref.osIdentifier,
                    mediaType: ref.mediaTypeEnum,
                    thumbnailCacheFilename: ref.thumbnailCacheFilename,
                    isAccessible: ref.isAccessible
                )
            },
            recycledAt: entry.recycledAt
        )
    }
}
