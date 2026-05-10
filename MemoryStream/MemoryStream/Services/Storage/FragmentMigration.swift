import Foundation
import CoreData
import CryptoKit

/// Migration that collapses the historic dual-fragment model into a single
/// shape: every captured piece becomes a `MediaReference`.
///
/// Pre-migration model:
/// - `JournalEntry.audioFilePath`: legacy single-voice-clip path used by
///   the in-app FAB voice recorder.
/// - `TextSegment` entity: typed-note bodies in the chronological stream.
/// - `MediaReference`: photo/video/voice fragments from later capture
///   flows (Contribute Mode, watch promotions).
///
/// Post-migration model: `MediaReference` carries every fragment kind via
/// its `mediaType` enum (`.image`, `.video`, `.voice`, `.note`).
///
/// **Idempotent every call.** Per-entry `alreadyMigrated` checks make
/// re-running a fast no-op for entries that are already in the new shape.
/// We rely on this to handle CloudKit's gradual import — an entry that
/// arrives via a later import batch will get migrated by the next call.
///
/// A UserDefaults flag short-circuits launches where we've previously
/// confirmed there's nothing more to migrate. The flag is set ONLY when
/// we've walked at least one entry and found nothing to do — that's the
/// signal that the steady state has been reached. A "ran with 0 entries
/// fetched" outcome (CloudKit hasn't imported yet) does NOT set the flag,
/// so the next launch tries again.
enum FragmentMigration {
    /// v4 adds a per-entry dedup pass + deterministic UUIDs for migration-
    /// created MediaReferences. Two devices migrating the same legacy
    /// entry independently used to mint two separate `.note` rows with
    /// identical text; after CloudKit settled, the user saw doubles.
    /// Bumping the key forces every device to re-evaluate, which runs
    /// the dedup pass and cleans up any existing duplicates.
    private static let completionFlagKey = "fragmentMigration.v4.completed"

    /// Runs the migration on the supplied context. Cheap (idempotent fetch
    /// + per-entry no-op) when called repeatedly — `LaunchScreenView`
    /// invokes this on every CloudKit `.import .succeeded` event so any
    /// entry CloudKit eventually delivers will get migrated.
    ///
    /// **Caller is responsible for the CloudKit-import gate.** Running
    /// this DURING import (rather than after `.succeeded`) races
    /// against the importer's NSManagedObjectModel and raises a Core Data
    /// NSException (`_PFManagedObject_coerceValueForKeyWithDescription`)
    /// that Swift's `do/catch` cannot intercept.
    ///
    /// **Skipped under XCTest.** The test host app shares the binary with
    /// the live MemoryStream app, so its launch screen would otherwise
    /// fire migration mid-test against the user's real store. Each
    /// `@Test` constructs its own `StorageService(inMemory: true)`.
    static func runIfNeeded(in context: NSManagedObjectContext) {
        if isRunningTests { return }
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: completionFlagKey) { return }

        // Re-entrancy guard. `LaunchScreenView` calls this on every
        // `.import .succeeded` event, which can fire several times in
        // quick succession during a multi-batch initial sync. The lock is
        // process-local — concurrent runs on the same store would fight
        // for context.save and waste CPU.
        runQueue.sync {
            guard !inFlight else { return }
            inFlight = true
        }
        defer { runQueue.sync { inFlight = false } }

        NSLog("[Himem][Migration] starting fragment migration v4")
        let stats = MigrationStats()
        context.performAndWait {
            do {
                try migrate(in: context, stats: stats)
                // Steady state requires: walked entries AND nothing left
                // to migrate AND no duplicates were merged. A 0-entry
                // fetch (CloudKit hasn't synced yet) or any work done
                // leaves the flag unset so the next launch tries again.
                if stats.entriesFetched > 0
                    && stats.entriesTouched == 0
                    && stats.entriesSkipped == 0
                    && stats.duplicatesRemoved == 0 {
                    defaults.set(true, forKey: completionFlagKey)
                    NSLog("[Himem][Migration] steady state — flag set")
                }
                NSLog(
                    "[Himem][Migration] completed: fetched=\(stats.entriesFetched) voice=\(stats.voiceCreated) note=\(stats.noteCreated) entriesTouched=\(stats.entriesTouched) skipped=\(stats.entriesSkipped) duplicatesRemoved=\(stats.duplicatesRemoved)"
                )
            } catch {
                NSLog("[Himem][Migration] fetch failed: \(error.localizedDescription)")
            }
        }
    }

    /// Returns true once the migration flag has been set — meaning at
    /// least one launch has confirmed the local store is fully migrated.
    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: completionFlagKey)
    }

    private static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || NSClassFromString("Testing.Test") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static let runQueue = DispatchQueue(label: "com.himem.fragmentMigration.guard")
    private static var inFlight = false

    // MARK: - Internals

    private final class MigrationStats {
        var entriesFetched = 0
        var voiceCreated = 0
        var noteCreated = 0
        var entriesTouched = 0
        var entriesSkipped = 0
        var duplicatesRemoved = 0
    }

    /// Stable UUID derived from the supplied seed strings. Two devices
    /// fed the same seed (e.g. "fragment-migration-v4|note-content|<entry.id>")
    /// produce identical UUIDs, so a multi-device migration of the same
    /// legacy entry yields MediaReferences with matching application-level
    /// `id`s. Doesn't dedupe at the CloudKit-record-name layer (Core Data
    /// derives those from internal object IDs), but gives the dedup pass
    /// a stable application key and helps debugging.
    private static func deterministicUUID(_ inputs: String...) -> UUID {
        let seed = inputs.joined(separator: "|")
        let digest = SHA256.hash(data: Data(seed.utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func migrate(in context: NSManagedObjectContext, stats: MigrationStats) throws {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        let entries = try context.fetch(request)
        stats.entriesFetched = entries.count
        for entry in entries {
            // Each entry is processed + saved independently. Throws roll
            // back the changes we made for this row only; the loop
            // continues to the next entry.
            do {
                let touched = try migrateOne(entry, in: context, stats: stats)
                if context.hasChanges {
                    try context.save()
                }
                if touched { stats.entriesTouched += 1 }
            } catch {
                NSLog(
                    "[Himem][Migration] skipped entry \(entry.id): \(error.localizedDescription)"
                )
                context.rollback()
                stats.entriesSkipped += 1
            }
        }

        // Per-entry dedup pass: removes duplicate `.note` (same text) and
        // `.voice` (same audio path) MediaReferences within each entry.
        // Multi-device migration races cause this — both devices migrate
        // the same legacy entry independently before CloudKit has synced
        // the conversion. After both writes propagate, the entry has two
        // refs with identical content. Keep the oldest by `createdAt`.
        try dedupeWithinEntries(entries, in: context, stats: stats)
    }

    private static func dedupeWithinEntries(
        _ entries: [JournalEntry],
        in context: NSManagedObjectContext,
        stats: MigrationStats
    ) throws {
        for entry in entries {
            let refs = (entry.mediaReferences as? Set<MediaReference>) ?? []

            // Notes: dedupe by text. Empty text counts as a single bucket
            // — two empty notes on the same entry are still duplicates.
            let notes = refs.filter { $0.mediaTypeEnum == .note }
            let notesByText = Dictionary(grouping: notes) { $0.text ?? "" }
            for (_, group) in notesByText where group.count > 1 {
                let sorted = group.sorted {
                    ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
                }
                for duplicate in sorted.dropFirst() {
                    context.delete(duplicate)
                    stats.duplicatesRemoved += 1
                }
            }

            // Voice: dedupe by `osIdentifier` (audio filename). Two
            // MediaReferences pointing at the same file ARE duplicates by
            // definition. Don't delete the file — the kept ref still
            // references it.
            let voices = refs.filter { $0.mediaTypeEnum == .voice }
            let voicesByPath = Dictionary(grouping: voices) { $0.osIdentifier }
            for (_, group) in voicesByPath where group.count > 1 {
                let sorted = group.sorted {
                    ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
                }
                for duplicate in sorted.dropFirst() {
                    context.delete(duplicate)
                    stats.duplicatesRemoved += 1
                }
            }
        }
        if context.hasChanges {
            try context.save()
        }
    }

    /// Returns true if any new MediaReference was added for this entry.
    private static func migrateOne(
        _ entry: JournalEntry,
        in context: NSManagedObjectContext,
        stats: MigrationStats
    ) throws -> Bool {
        var touched = false
        let existingRefs = (entry.mediaReferences as? Set<MediaReference>) ?? []

        // 1. Legacy audioFilePath → .voice MediaReference.
        //    The transcript becomes entry.content (which historically
        //    held the voice transcript for these entries).
        if let audioPath = entry.audioFilePath, !audioPath.isEmpty {
            let alreadyMigrated = existingRefs
                .contains { $0.osIdentifier == audioPath && $0.mediaTypeEnum == .voice }
            if !alreadyMigrated {
                let ref = MediaReference(context: context)
                ref.id = deterministicUUID("fragment-migration-v4", "voice", entry.id.uuidString, audioPath)
                ref.entryId = entry.id
                ref.mediaType = MediaReference.MediaType.voice.rawValue
                ref.osIdentifier = audioPath
                ref.isAccessible = true
                ref.createdAt = entry.createdAt
                ref.transcript = entry.content
                ref.entry = entry
                stats.voiceCreated += 1
                touched = true
            }
        }

        // 2. TextSegment rows → .note MediaReference rows. Original
        //    TextSegments left in place for safety.
        let segments = (entry.textSegments as? Set<TextSegment>) ?? []
        for segment in segments {
            let alreadyMigrated = existingRefs
                .contains { ref in
                    ref.mediaTypeEnum == .note
                        && ref.text == segment.text
                        && ref.createdAt == segment.createdAt
                }
            if !alreadyMigrated {
                let ref = MediaReference(context: context)
                ref.id = deterministicUUID("fragment-migration-v4", "note-segment", segment.id.uuidString)
                ref.entryId = entry.id
                ref.mediaType = MediaReference.MediaType.note.rawValue
                ref.osIdentifier = ""
                ref.isAccessible = true
                ref.createdAt = segment.createdAt
                ref.text = segment.text
                ref.entry = entry
                stats.noteCreated += 1
                touched = true
            }
        }

        // 3. Pure-content entries (no audioFile, no segments) →
        //    single `.note` MediaReference holding entry.content. This
        //    covers Siri intents, AI-generated test entries, and any
        //    other path that wrote directly to `entry.content`.
        let trimmedContent = entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAudio = (entry.audioFilePath?.isEmpty == false)
        let hasSegments = !segments.isEmpty
        let alreadyHasContentNote = existingRefs.contains { ref in
            ref.mediaTypeEnum == .note && ref.text == entry.content
        }
        if !trimmedContent.isEmpty
            && !hasAudio
            && !hasSegments
            && !alreadyHasContentNote {
            let ref = MediaReference(context: context)
            ref.id = deterministicUUID("fragment-migration-v4", "note-content", entry.id.uuidString)
            ref.entryId = entry.id
            ref.mediaType = MediaReference.MediaType.note.rawValue
            ref.osIdentifier = ""
            ref.isAccessible = true
            ref.createdAt = entry.createdAt
            ref.text = entry.content
            ref.entry = entry
            stats.noteCreated += 1
            touched = true
        }

        return touched
    }
}
