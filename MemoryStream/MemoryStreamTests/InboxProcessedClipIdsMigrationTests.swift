import Testing
import Foundation
@testable import HiMem

/// Money tests for the one-time migration that absorbs the legacy
/// `InboxProcessedClipIds.json` file into the manifest as `.disposed`
/// tombstones.
///
/// The legacy store (Step C lineage of `InboxProcessedClipIds`) lived
/// at `Documents/InboxProcessedClipIds.json` as a plain JSON array of
/// UUIDs. With the unified status model the manifest itself
/// remembers disposed clips; the migration moves those clipIds into
/// the manifest as `.disposed` rows so the new B5 gate
/// (`status(for: clipId) == .disposed`) catches every clip the
/// legacy store would have caught.
///
/// Pure function tested here: `InboxManifest.migrateLegacyDisposedSet`.
/// The integration with `load()` is exercised by the on-device smoke
/// in §  Verification of the plan.
struct InboxProcessedClipIdsMigrationTests {

    /// A legacy file containing N clipIds → N tombstone rows in the
    /// `[InboxClip]` return value, each with `status = .disposed` and
    /// a `disposedAt` timestamp.
    @Test func legacyFile_withClipIds_producesTombstones() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("InboxProcessedClipIds.json")
        let ids = [UUID(), UUID(), UUID()]
        try JSONEncoder().encode(ids).write(to: url)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let tombstones = InboxManifest.migrateLegacyDisposedSet(legacyURL: url, now: now)

        #expect(tombstones.count == 3)
        let tombstoneIds = Set(tombstones.map(\.clipId))
        #expect(tombstoneIds == Set(ids))
        for tombstone in tombstones {
            #expect(tombstone.status == .disposed)
            #expect(tombstone.disposedAt == now)
            #expect(tombstone.audioFilename == "", "Tombstone shouldn't claim audio it doesn't have")
        }
    }

    /// Absent file is a no-op — returns empty list, nothing thrown.
    @Test func legacyFile_absent_returnsEmpty() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("InboxProcessedClipIds.json")
        // file doesn't exist
        let tombstones = InboxManifest.migrateLegacyDisposedSet(legacyURL: url, now: Date())
        #expect(tombstones.isEmpty)
    }

    /// Corrupt file decodes to nothing → empty list, no throw. The
    /// migration is "best effort, don't block startup."
    @Test func legacyFile_corrupt_returnsEmpty() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("InboxProcessedClipIds.json")
        try Data("not valid json".utf8).write(to: url)
        let tombstones = InboxManifest.migrateLegacyDisposedSet(legacyURL: url, now: Date())
        #expect(tombstones.isEmpty)
    }

    /// After migration runs, the legacy file is deleted so subsequent
    /// loads skip the work and the disposed set has one home.
    @Test func legacyFile_isDeletedAfterMigration() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("InboxProcessedClipIds.json")
        try JSONEncoder().encode([UUID()]).write(to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
        _ = InboxManifest.migrateLegacyDisposedSet(legacyURL: url, now: Date())
        #expect(FileManager.default.fileExists(atPath: url.path) == false)
    }

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("InboxProcessedMigrationTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
