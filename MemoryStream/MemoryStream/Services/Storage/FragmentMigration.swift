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
    /// v5 (2026-05-11) bump: previous versions could resurrect deleted
    /// `.note` fragments every launch because (a) the strict flag-set
    /// condition kept the migration re-running indefinitely on stores
    /// with any legacy work, and (b) path 3 minted a fresh `.note`
    /// whenever a pure-content entry had no matching note — including
    /// entries where the user had intentionally deleted the prior mint.
    /// Across multiple relaunches, a new `.note` was created each time,
    /// piling up as visible duplicate panels. v5 relaxes the flag-set
    /// to fire after any successful walk and guards path 3 to truly
    /// empty entries; bumping the key forces every device to re-walk
    /// once with the new logic so the dedup pass clears existing
    /// duplicates and the new flag locks future launches out.
    internal static let completionFlagKey = "fragmentMigration.v5.completed"

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
    static func runIfNeeded(in context: NSManagedObjectContext, force: Bool = false) {
        if isRunningTests && !force { return }
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

        NSLog("[HiMem][Migration] starting fragment migration v5")
        let stats = MigrationStats()
        context.performAndWait {
            do {
                try migrate(in: context, stats: stats)
                // Flag set after any walk where CloudKit had actually
                // delivered entries — the migration's per-entry idempotency
                // means a single successful walk is enough; subsequent
                // launches with the flag set short-circuit. The earlier
                // condition (`touched == 0 && skipped == 0 && duplicates == 0`)
                // kept the flag unset on every launch where any legacy work
                // happened, which caused user-deleted fragments to resurrect:
                // path 3 sees pure-content + no `.note` and re-mints. Flagged
                // launches don't re-mint because they don't run migration.
                // Empty-store launches (CloudKit hasn't synced yet) still
                // leave the flag unset so the next launch retries the walk.
                if stats.entriesFetched > 0 {
                    defaults.set(true, forKey: completionFlagKey)
                    NSLog("[HiMem][Migration] flag set after walk of \(stats.entriesFetched) entries")
                }
                NSLog(
                    "[HiMem][Migration] completed: fetched=\(stats.entriesFetched) voice=\(stats.voiceCreated) note=\(stats.noteCreated) entriesTouched=\(stats.entriesTouched) skipped=\(stats.entriesSkipped) duplicatesRemoved=\(stats.duplicatesRemoved)"
                )
            } catch {
                NSLog("[HiMem][Migration] fetch failed: \(error.localizedDescription)")
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
                    "[HiMem][Migration] skipped entry \(entry.id): \(error.localizedDescription)"
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
            let refs = Set(entry.mediaReferencesArray)

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
        let existingRefs = Set(entry.mediaReferencesArray)

        // 1. Legacy audioFilePath → .voice MediaReference.
        //    The transcript becomes entry.content (which historically
        //    held the voice transcript for these entries).
        if let audioPath = entry.audioFilePath, !audioPath.isEmpty {
            let alreadyMigrated = existingRefs
                .contains { $0.osIdentifier == audioPath && $0.mediaTypeEnum == .voice }
            if !alreadyMigrated {
                let ref = MediaReference(context: context)
                ref.id = deterministicUUID("fragment-migration-v4", "voice", entry.id.uuidString, audioPath)
                ref.mediaType = MediaReference.MediaType.voice.rawValue
                ref.osIdentifier = audioPath
                ref.isAccessible = true
                ref.createdAt = entry.createdAt
                ref.transcript = entry.content
                try StorageService.createEdge(from: entry, to: ref, linkedAt: entry.createdAt, in: context)
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
                ref.mediaType = MediaReference.MediaType.note.rawValue
                ref.osIdentifier = ""
                ref.isAccessible = true
                ref.createdAt = segment.createdAt ?? entry.createdAt
                ref.text = segment.text
                try StorageService.createEdge(from: entry, to: ref, linkedAt: segment.createdAt ?? entry.createdAt, in: context)
                stats.noteCreated += 1
                touched = true
            }
        }

        // Path 3 (pure-content → single `.note` mint) removed 2026-05-11.
        // It was the consolidation source the user complained about: every
        // launch saw a pure-content entry with no `.note`, minted one
        // containing the whole `entry.content` (often multi-paragraph
        // from an old concat-into-content append flow), and when the user
        // deleted it, the next launch resurrected it. With path 3 gone,
        // pure-content entries render via the detail view's plain-text
        // fallback (`entry.mediaItems.isEmpty → Text(entry.content)`),
        // and `EntryLifecycleService.append` already creates per-capture
        // fragments for new typed text so no path produces consolidated
        // notes anymore.

        return touched
    }
}
