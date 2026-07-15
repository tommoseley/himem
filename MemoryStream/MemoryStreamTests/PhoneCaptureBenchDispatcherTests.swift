import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for `PhoneCaptureBenchDispatcher` — the routing that
/// lands a phone-side `CapturedItem` on the bench (`InboxManifest` for
/// voice, unplaced `MediaReference` for photo/video/note) per the
/// July 10 lock (`CLAUDE.md:142`).
///
/// Before this dispatcher shipped, Clips-tab FAB captures went through
/// `JournalCaptureCoordinator.createNewMemory` and always created a
/// `JournalEntry` — i.e. the "bench" appearance was an illusion; the
/// data landed in Memories. These tests lock in the new contract:
/// voice → bench (as an InboxClip), photo/video/note → bench (as an
/// unplaced MediaReference), and **never** a JournalEntry.
@MainActor
@Suite(.serialized)
struct PhoneCaptureBenchDispatcherTests {

    /// Voice → InboxClip with source="phone", transcript carried,
    /// audioFilename preserved, status inferred from transcript
    /// presence.
    @Test func voice_creates_phoneSourced_inboxClip() async {
        await ManifestTestLock.shared.acquire()
        defer { ManifestTestLock.shared.release() }
        let manifest = InboxManifest.shared
        let prior = manifest.clips
        defer { manifest.debugReplaceClipsForTesting(prior) }
        manifest.debugReplaceClipsForTesting([])

        let filename = "phone-\(UUID().uuidString).m4a"
        PhoneCaptureBenchDispatcher.dispatch(
            .voice(filename: filename, transcript: "Remember the sourdough"),
            inbox: manifest
        )

        #expect(manifest.clips.count == 1, "one clip created")
        let clip = manifest.clips[0]
        #expect(clip.source == "phone", "source stamped phone, not watch")
        #expect(clip.audioFilename == filename)
        #expect(clip.transcript == "Remember the sourdough")
        #expect(clip.transcriptionAttempted == true)
        #expect(clip.status == .transcribed)
    }

    /// Voice with empty filename is a no-op (defensive — the composer
    /// should never emit this, but we don't want a phantom InboxClip
    /// pointing at an empty path).
    @Test func voice_with_no_filename_is_dropped() async {
        await ManifestTestLock.shared.acquire()
        defer { ManifestTestLock.shared.release() }
        let manifest = InboxManifest.shared
        let prior = manifest.clips
        defer { manifest.debugReplaceClipsForTesting(prior) }
        manifest.debugReplaceClipsForTesting([])

        PhoneCaptureBenchDispatcher.dispatch(
            .voice(filename: nil, transcript: "hi"),
            inbox: manifest
        )

        #expect(manifest.clips.isEmpty)
    }

    /// voiceSession (phone "on-a-roll") produces N clips sharing one
    /// rollGroupId — parity with the watch roll behavior so
    /// `ClipSessionGrouper` bundles them into one session card.
    @Test func voiceSession_shares_one_rollGroupId_across_clips() async {
        await ManifestTestLock.shared.acquire()
        defer { ManifestTestLock.shared.release() }
        let manifest = InboxManifest.shared
        let prior = manifest.clips
        defer { manifest.debugReplaceClipsForTesting(prior) }
        manifest.debugReplaceClipsForTesting([])

        let now = Date()
        let clip1 = VoiceClipFragment(
            audioFilename: "roll-1.m4a",
            transcript: "one",
            duration: 3.0,
            capturedAt: now
        )
        let clip2 = VoiceClipFragment(
            audioFilename: "roll-2.m4a",
            transcript: "two",
            duration: 4.0,
            capturedAt: now.addingTimeInterval(6)
        )
        let rollId = UUID()
        PhoneCaptureBenchDispatcher.dispatch(
            .voiceSession(clips: [clip1, clip2], rollGroupId: rollId),
            inbox: manifest
        )

        #expect(manifest.clips.count == 2)
        let rollGroups = Set(manifest.clips.compactMap(\.rollGroupId))
        #expect(rollGroups == [rollId], "all roll clips share the composer's rollGroupId")
        #expect(manifest.clips.allSatisfy { $0.source == "phone" })
    }

    /// Photo → unplaced MediaReference. No JournalEntry. No edges.
    @Test func photo_creates_unplaced_mediaReference() async throws {
        let ctx = try makeInMemoryContext()
        PhoneCaptureBenchDispatcher.dispatch(
            .photo(localIdentifier: "photo-\(UUID().uuidString).jpg"),
            context: ctx
        )
        let refs = try ctx.fetch(NSFetchRequest<MediaReference>(entityName: "MediaReference"))
        #expect(refs.count == 1)
        let ref = refs[0]
        #expect(ref.mediaTypeEnum == .image)
        #expect((ref.edges?.count ?? 0) == 0, "no edge — clip is unplaced on the bench")
    }

    /// Video → unplaced MediaReference.
    @Test func video_creates_unplaced_mediaReference() async throws {
        let ctx = try makeInMemoryContext()
        PhoneCaptureBenchDispatcher.dispatch(
            .video(localIdentifier: "video-\(UUID().uuidString).mov"),
            context: ctx
        )
        let refs = try ctx.fetch(NSFetchRequest<MediaReference>(entityName: "MediaReference"))
        #expect(refs.count == 1)
        #expect(refs[0].mediaTypeEnum == .video)
        #expect((refs[0].edges?.count ?? 0) == 0)
    }

    /// Note → unplaced MediaReference with text populated.
    @Test func note_creates_unplaced_mediaReference_with_text() async throws {
        let ctx = try makeInMemoryContext()
        PhoneCaptureBenchDispatcher.dispatch(
            .note(text: "sourdough starter needs feeding"),
            context: ctx
        )
        let refs = try ctx.fetch(NSFetchRequest<MediaReference>(entityName: "MediaReference"))
        #expect(refs.count == 1)
        #expect(refs[0].mediaTypeEnum == .note)
        #expect(refs[0].text == "sourdough starter needs feeding")
        #expect((refs[0].edges?.count ?? 0) == 0)
    }

    /// Empty note is a no-op — the composer's submit gates should
    /// catch this, but the dispatcher is defensive.
    @Test func empty_note_is_dropped() async throws {
        let ctx = try makeInMemoryContext()
        PhoneCaptureBenchDispatcher.dispatch(.note(text: "   \n  "), context: ctx)
        let refs = try ctx.fetch(NSFetchRequest<MediaReference>(entityName: "MediaReference"))
        #expect(refs.isEmpty)
    }

    // MARK: - Helpers

    /// Spins up an in-memory Core Data stack against the shipping
    /// managed object model — avoids polluting the real store.
    private func makeInMemoryContext() throws -> NSManagedObjectContext {
        // Test-isolation fix (2026-07-15): share the ONE production
        // `cachedModel` via StorageService(inMemory:) instead of a fresh
        // `mergedModel(from:)` — multiple live models for the same entity
        // classes race in Core Data's global registry under parallel @Suite
        // runs. Stores stay per-test isolated; the MODEL shares one instance.
        return StorageService(inMemory: true).viewContext
    }
}
