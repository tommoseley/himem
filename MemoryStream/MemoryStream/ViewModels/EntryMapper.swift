import Foundation

/// Single source of truth for mapping JournalEntry → EntryDisplayModel.
/// Replaces 3 duplicate mapping implementations.
enum EntryMapper {
    /// Removes duplicate topic names (CloudKit merge conflicts can produce
    /// multiple Topic entities with the same name; ForEach keys on the name
    /// and warns about duplicate IDs).
    private static func dedupedNames(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        return names.compactMap { seen.insert($0).inserted ? $0 : nil }
    }

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
            topicNames: dedupedNames(entry.topicsArray.map(\.name)),
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
                    isAccessible: ref.isAccessible,
                    transcript: ref.transcript
                )
            },
            recycledAt: entry.recycledAt,
            latitude: entry.latitude?.doubleValue,
            longitude: entry.longitude?.doubleValue,
            locationName: entry.locationName
        )
    }
}
