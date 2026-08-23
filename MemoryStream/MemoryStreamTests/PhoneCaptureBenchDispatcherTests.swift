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

    // MARK: - "Ran and found nothing" is not "still running" (2026-08-22)

    /// **MONEY TEST.** A phone voice capture whose recognizer ran and found no
    /// words must be recorded as ATTEMPTED, not as still pending.
    ///
    /// `PhoneCaptureBenchDispatcher` derived both fields from the transcript:
    /// `transcriptionAttempted: !transcript.isEmpty` and
    /// `status: transcript.isEmpty ? .received : .transcribed`. So the one case
    /// the field exists to record — *ran, found nothing* — was written as
    /// `false` / `.received`, indistinguishable from a clip whose transcription
    /// has not started. `InboxClip.transcriptionAttempted`'s own doc says the
    /// opposite: *"True after the iPhone-side speech recognizer has run for this
    /// clip, **even if it returned no text**. Combined with `transcript.isEmpty`
    /// this distinguishes 'still in flight' from 'ran, found no speech'."*
    /// A phantom comment over a live defect (F23 class).
    ///
    /// **The inference is safe, and this is why.** `SpeechService.startRecording`
    /// returns early — no recording, no file — unless `isAuthorized` AND the
    /// analyzer, transcriber and format are all prepared. Phone capture
    /// transcribes live during the recording. So a `.voice` item reaching this
    /// dispatcher *always* comes from a session where the recogniser ran;
    /// "attempted" is not a guess here, it is a precondition of arriving.
    /// Guarded by `theDispatcherOnlyReceivesPostRecognizerItems` below.
    @Test func voice_whenTheRecognizerFoundNoWords_isAttemptedNotPending() async {
        await ManifestTestLock.shared.acquire()
        defer { ManifestTestLock.shared.release() }
        let manifest = InboxManifest.shared
        let prior = manifest.clips
        defer { manifest.debugReplaceClipsForTesting(prior) }
        manifest.debugReplaceClipsForTesting([])

        PhoneCaptureBenchDispatcher.dispatch(
            .voice(filename: "phone-\(UUID().uuidString).m4a", transcript: ""),
            inbox: manifest
        )

        #expect(manifest.clips.count == 1)
        let clip = manifest.clips[0]
        #expect(clip.transcriptionAttempted == true,
                "the recogniser ran and found nothing — that is ATTEMPTED. false here means the app reports work still in flight that has finished.")
        #expect(clip.status == .transcribed,
                "InboxClip.Status.transcribed is documented as 'attempt completed (transcript may be empty if the recognizer found no speech)'")
    }

    /// The consequence at the surface: the honest label can never fire.
    ///
    /// `accidentalClips` requires `transcript.isEmpty && transcriptionAttempted`,
    /// so with `attempted == false` a no-speech phone clip is never accidental —
    /// it cannot reach `.allAccidental`, never renders *"1 clip auto-excluded ·
    /// no speech"*, and `collapsedBodyVariant` classifies it as `.transcribing`.
    /// A finished recording presented as one still being worked on.
    @Test func aNoSpeechPhoneClipReachesTheHonestLabelNotTheTranscribingState() async {
        await ManifestTestLock.shared.acquire()
        defer { ManifestTestLock.shared.release() }
        let manifest = InboxManifest.shared
        let prior = manifest.clips
        defer { manifest.debugReplaceClipsForTesting(prior) }
        manifest.debugReplaceClipsForTesting([])

        PhoneCaptureBenchDispatcher.dispatch(
            .voice(filename: "phone-\(UUID().uuidString).m4a", transcript: ""),
            inbox: manifest
        )
        let clip = manifest.clips[0]

        #expect(ClipGroup.collapsedBodyVariant(of: [clip]) == .allAccidental,
                "a finished no-speech recording must read as 'no speech', not as still transcribing")
        #expect(ClipGroup.accidentalClips(in: [clip]).count == 1,
                "it must be classifiable as accidental at all — that is what carries the auto-excluded line")
    }

    /// Same defect on the on-a-roll path, which builds its clips in a second
    /// place with the identical derivation (`:89`/`:91`). Fixing one site and
    /// not the other is the near-duplicate-procedure shape F6a names.
    @Test func voiceSession_whenAClipFoundNoWords_isAttemptedNotPending() async {
        await ManifestTestLock.shared.acquire()
        defer { ManifestTestLock.shared.release() }
        let manifest = InboxManifest.shared
        let prior = manifest.clips
        defer { manifest.debugReplaceClipsForTesting(prior) }
        manifest.debugReplaceClipsForTesting([])

        let silent = VoiceClipFragment(
            audioFilename: "roll-a.m4a", transcript: "", duration: 3,
            capturedAt: Date(), latitude: nil, longitude: nil
        )
        let spoken = VoiceClipFragment(
            audioFilename: "roll-b.m4a", transcript: "the second one had words", duration: 4,
            capturedAt: Date(), latitude: nil, longitude: nil
        )
        PhoneCaptureBenchDispatcher.dispatch(
            .voiceSession(clips: [silent, spoken], rollGroupId: UUID()),
            inbox: manifest
        )

        #expect(manifest.clips.count == 2)
        let quiet = manifest.clips.first { $0.audioFilename == "roll-a.m4a" }
        #expect(quiet?.transcriptionAttempted == true,
                "the roll splitter re-transcribes every fragment, so every fragment has been attempted")
        #expect(quiet?.status == .transcribed)
    }

    /// **Guards the inference, not the owner** (CLAUDE.md § Guard the Caller).
    /// The fix is only correct while every `.voice`/`.voiceSession` item reaches
    /// the dispatcher from a completed recording. If a future caller dispatches
    /// a voice item that has NOT been through the recogniser, "attempted = true"
    /// becomes a lie and this test names where to look.
    @Test func theDispatcherOnlyReceivesPostRecognizerItems() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // MemoryStreamTests
            .deletingLastPathComponent()      // MemoryStream
            .appendingPathComponent("MemoryStream")
        var scanned = 0
        var callSites: [String] = []
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            scanned += 1
            for line in text.split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard !t.hasPrefix("//"), !t.hasPrefix("///") else { continue }
                guard t.contains("PhoneCaptureBenchDispatcher.dispatch") else { continue }
                callSites.append("\(url.lastPathComponent): \(t)")
            }
        }
        // The walk must reach source, or it passes by matching nothing.
        #expect(scanned > 50, "the source walk found only \(scanned) files — it did not reach the app target")
        #expect(callSites.count == 2,
                "expected the two known HiMemTabView call sites, both post-recording; found \(callSites.count):\n\(callSites.joined(separator: "\n"))")
        #expect(callSites.allSatisfy { $0.hasPrefix("HiMemTabView.swift") },
                "a dispatch from outside HiMemTabView may not have been through the recogniser: \(callSites)")
    }

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
