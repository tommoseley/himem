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
                    transcript: ref.transcript,
                    text: ref.text,
                    createdAt: ref.createdAt ?? .distantPast,
                    // Per-clip placeName wins when present; otherwise
                    // fall back to the memory's own locationName so
                    // every existing memory with a captured location
                    // lights up on the clip row without waiting for
                    // the per-clip backfill. The two will diverge
                    // only when a memory's clips actually span
                    // places (multi-session memories spanning a
                    // walk/drive) — at which point the per-clip
                    // value renders.
                    placeName: ref.placeName ?? entry.locationName
                )
            },
            recycledAt: entry.recycledAt,
            latitude: entry.latitude?.doubleValue,
            longitude: entry.longitude?.doubleValue,
            locationName: entry.locationName,
            renderedSummary: entry.renderedSummary
        )
    }
}
