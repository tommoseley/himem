import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for RH-8 (July 20 2026) — a permanent clip purge must delete
/// the backing blob from the iCloud Files ubiquity container
/// (NSFileCoordinator-wrapped), for EVERY owned media type, and must NOT
/// delete anything HiMem doesn't own (PhotoKit-referenced assets) or has no
/// file for (notes). The device symptom this closes: 80 audio + 21 photos
/// + 6 videos orphaned after deleting everything.
@MainActor
@Suite(.serialized)
struct MediaBlobPurgeTests {

    // MARK: - Coordinated delete primitive

    @Test func removeFromStore_deletesContainerFile_thenNoopsGracefully() throws {
        let store = UbiquityStore.shared
        let url = store.audioURL(for: "rh8-\(UUID().uuidString).caf")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x00, 0x01]).write(to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))

        store.removeFromStore(at: url)
        #expect(!FileManager.default.fileExists(atPath: url.path), "coordinated delete must remove the blob")

        // Idempotent: a second delete (already gone) is a graceful no-op.
        store.removeFromStore(at: url)
    }

    @Test func removeFromStore_refusesFileOutsideContainer() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("rh8-outside-\(UUID().uuidString).caf")
        try Data([0x00]).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }

        UbiquityStore.shared.removeFromStore(at: outside)
        #expect(FileManager.default.fileExists(atPath: outside.path),
                "must refuse to coordinate-delete a file outside the ubiquity container (e.g. a PhotoKit URL)")
    }

    // MARK: - Owned-blob URL decision (which file a purge deletes)

    private func makeRef(_ storage: StorageService, type: MediaReference.MediaType, osIdentifier: String) -> MediaReference {
        let ref = MediaReference(context: storage.viewContext)
        ref.id = UUID()
        ref.mediaType = type.rawValue
        ref.osIdentifier = osIdentifier
        return ref
    }

    @Test func ownedBlobURL_resolvesPerMediaType() {
        let storage = StorageService(inMemory: true)
        // Voice / photo / video → their own ubiquity subdirectory.
        #expect(EntryLifecycleService.ownedBlobURL(for: makeRef(storage, type: .voice, osIdentifier: "a.caf"))
                == UbiquityStore.shared.audioURL(for: "a.caf"))
        #expect(EntryLifecycleService.ownedBlobURL(for: makeRef(storage, type: .image, osIdentifier: "p.heic"))
                == UbiquityStore.shared.photoURL(for: "p.heic"))
        #expect(EntryLifecycleService.ownedBlobURL(for: makeRef(storage, type: .video, osIdentifier: "v.mov"))
                == UbiquityStore.shared.videoURL(for: "v.mov"))
    }

    @Test func ownedBlobURL_nilForNoteAndPhotoKit() {
        let storage = StorageService(inMemory: true)
        // A note has no external file.
        #expect(EntryLifecycleService.ownedBlobURL(for: makeRef(storage, type: .note, osIdentifier: "note-marker")) == nil)
        // A PhotoKit-referenced asset (osIdentifier has a slash) is the user's
        // Photos library, never ours to delete.
        #expect(EntryLifecycleService.ownedBlobURL(for: makeRef(storage, type: .image, osIdentifier: "ABCD-1234/L0/001")) == nil)
    }

    // MARK: - Orphan-sweep predicate (the destructive migration's decision)

    /// The sweep predicate: sweep only files that are BOTH unreferenced AND
    /// older than the age guard. A referenced file (incl. a recycled clip's
    /// blob) is kept; a recent unreferenced file (a possible in-flight
    /// arrival with no DB/manifest row yet) is kept.
    @Test func orphanSweep_sweepsOldUnreferenced_keepsReferencedAndRecent() {
        let now = Date()
        let old = now.addingTimeInterval(-3600)     // 1h ago
        let recent = now.addingTimeInterval(-60)    // 1m ago
        let cutoff = now.addingTimeInterval(-1800)  // 30m age guard

        func cand(_ name: String, _ at: Date) -> MediaBlobOrphanSweep.Candidate {
            .init(url: URL(fileURLWithPath: "/c/\(name)"), filename: name, modifiedAt: at)
        }
        let referenced = cand("kept.caf", old)          // referenced → keep
        let orphan = cand("orphan.caf", old)            // unreferenced + old → sweep
        let inflight = cand("inflight.caf", recent)     // unreferenced but recent → keep

        let result = MediaBlobOrphanSweep.orphans(
            candidates: [referenced, orphan, inflight],
            referencedFilenames: ["kept.caf"],
            olderThan: cutoff
        )
        #expect(result == [orphan.url])
    }
}
