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
        let task = entry.latestProcessingTask()
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
            // Dedupe by ref id: the underlying data can hold more than one edge
            // pointing at the same clip within this memory.
            //
            // **CORRECTION (B26, 2026-08-19): this comment used to say
            // `createEdge` is idempotent "so new writes can't produce dupes,
            // but stale records already on-device would still render twice."
            // That framed an ONGOING production mechanism as legacy data.** Two
            // devices each write the edge, each passes its own guard because
            // neither can see the other's yet, and CloudKit converges both —
            // and the model cannot forbid it, since
            // `NSPersistentCloudKitContainer` permits no uniqueness
            // constraints. New writes on two devices produce dupes today.
            //
            // Together with `createEdge`'s docstring claiming coverage of the
            // one case it structurally cannot cover, that is why B26 sat
            // unexamined for six weeks.
            //
            // See MediaReferenceDuplicateRenderingTests and
            // DuplicateEdgeHonestCountTests — the latter pins that the count
            // travelling with each deduped row is itself deduped, which this
            // fix originally left split.
            mediaItems: {
                var seen: Set<UUID> = []
                return entry.mediaReferencesArray.compactMap { ref in
                    guard seen.insert(ref.id).inserted else { return nil }
                    return MediaDisplayItem(
                        id: ref.id,
                        localIdentifier: ref.osIdentifier,
                        mediaType: ref.mediaTypeEnum,
                        thumbnailCacheFilename: ref.thumbnailCacheFilename,
                        isAccessible: ref.isAccessible,
                        transcript: ref.transcript,
                        text: ref.text,
                        mediaDescription: ref.mediaDescription,
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
                        placeName: ref.placeName ?? entry.locationName,
                        referencingMemoryCount: ref.referencingMemoryCount
                    )
                }
            }(),
            recycledAt: entry.recycledAt,
            latitude: entry.latitude?.doubleValue,
            longitude: entry.longitude?.doubleValue,
            locationName: entry.locationName,
            renderedSummary: entry.renderedSummary,
            summaryUserEdited: entry.summaryUserEdited,
            projectMemberships: entry.projectsArray.map {
                ProjectChip(id: $0.id, name: $0.name)
            },
            mentions: entry.mentionsArray.map {
                MentionChip(id: $0.id, name: $0.name, type: $0.mentionType)
            }
        )
    }
}
