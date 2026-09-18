import Testing
import Foundation
import CoreData
@testable import HiMem

/// **§1 · a Watch arrival becomes a memory whose writing is the transcript.**
///
/// Ruled 2026-09-17/18 (Tom). The Watch is a *recording mechanism, not a
/// store*: it captures because speaking is the only practical input on a
/// wrist, the audio crosses to the phone, the phone transcribes, **the audio
/// is discarded**, and the words are the artifact.
///
/// So an arrival no longer produces a `MediaReference`. A recording that
/// arrived, transcribed, and left a media-shaped object behind would have been
/// *stored* — just with the bytes missing, which is the worst of both, and
/// leaves `osIdentifier` pointing at nothing while `isAccessible` is
/// permanently false. That is the phantom-state shape: an object claiming to
/// reference media that cannot exist.
///
/// It takes the same `createEntry(content:inputType:)` path Siri text already
/// uses — **one code path for both**, which is also why
/// `StartVoiceRecordingIntent` folds into `CreateEntryIntent`.
@MainActor
@Suite(.serialized)
struct ArrivedRecordingBecomesMemoryTests {

    private func clip(
        transcript: String,
        id: UUID = UUID(),
        source: String = "watch"
    ) -> InboxClip {
        InboxClip(
            clipId: id,
            capturedAt: Date(timeIntervalSinceNow: -60),
            duration: 12,
            transcript: transcript,
            latitude: nil,
            longitude: nil,
            source: source,
            audioFilename: "\(id.uuidString).m4a",
            transcriptionAttempted: true,
            rollGroupId: nil,
            status: .transcribed
        )
    }

    private func entries(in storage: StorageService) -> [JournalEntry] {
        let r = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        return (try? storage.viewContext.fetch(r)) ?? []
    }

    private func refs(in storage: StorageService) -> [MediaReference] {
        let r = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        return (try? storage.viewContext.fetch(r)) ?? []
    }

    // MARK: - The shape of the arrival

    @Test("the transcript becomes the memory's writing")
    func transcriptBecomesTheWriting() throws {
        let storage = StorageService(inMemory: true)
        let c = clip(transcript: "the waiter said something about cheesecake")

        _ = ArrivedClipMaterializer.materialize(c, in: storage.viewContext, deleteAudio: { _ in true })

        let all = entries(in: storage)
        #expect(all.count == 1)
        #expect(all.first?.content == "the waiter said something about cheesecake")
    }

    /// **THE MONEY ASSERTION.** A media-shaped object with no bytes is the
    /// phantom-state shape the ruling exists to prevent.
    @Test("no MediaReference is left behind")
    func noPartIsCreated() throws {
        let storage = StorageService(inMemory: true)
        _ = ArrivedClipMaterializer.materialize(clip(transcript: "hello"),
                                                in: storage.viewContext,
                                                deleteAudio: { _ in true })
        #expect(refs(in: storage).isEmpty,
                "an arrival must leave no part — bytes are discarded, so a media object would reference nothing")
    }

    @Test("the audio is deleted, and the filename it deletes is the clip's")
    func theAudioIsDiscarded() throws {
        let storage = StorageService(inMemory: true)
        let c = clip(transcript: "hello")
        var deleted: [String] = []

        _ = ArrivedClipMaterializer.materialize(c, in: storage.viewContext,
                                                deleteAudio: { name in deleted.append(name); return true })

        #expect(deleted == [c.audioFilename], "the audio is discarded once, by name")
    }

    @Test("the manifest row is tombstoned so a late redelivery cannot re-add it")
    func theManifestRowIsTombstoned() async throws {
        await ManifestTestLock.shared.acquire()
        defer { ManifestTestLock.shared.release() }
        let manifest = InboxManifest.shared
        let prior = manifest.clips
        defer { manifest.debugReplaceClipsForTesting(prior) }

        let storage = StorageService(inMemory: true)
        let c = clip(transcript: "hello")
        manifest.debugReplaceClipsForTesting([c])

        _ = ArrivedClipMaterializer.materialize(c, in: storage.viewContext, deleteAudio: { _ in true })

        #expect(manifest.clips.first(where: { $0.clipId == c.clipId })?.status != .transcribed,
                "the active row must not survive as transcribed — a redelivery would arrive twice")
    }

    // MARK: - Identity, which is what makes it safe to run twice

    /// The entry takes the CLIP's id. That is what the ref used to do, for the
    /// same two reasons: the drain can run repeatedly without duplicating, and
    /// two devices materializing the same arrival converge on one CloudKit
    /// record rather than racing to create two memories.
    @Test("the memory takes the clip's id")
    func theMemoryTakesTheClipId() throws {
        let storage = StorageService(inMemory: true)
        let c = clip(transcript: "hello")
        _ = ArrivedClipMaterializer.materialize(c, in: storage.viewContext, deleteAudio: { _ in true })
        #expect(entries(in: storage).first?.id == c.clipId)
    }

    @Test("materializing twice creates one memory")
    func materializeIsIdempotent() throws {
        let storage = StorageService(inMemory: true)
        let c = clip(transcript: "hello")
        _ = ArrivedClipMaterializer.materialize(c, in: storage.viewContext, deleteAudio: { _ in true })
        _ = ArrivedClipMaterializer.materialize(c, in: storage.viewContext, deleteAudio: { _ in true })
        #expect(entries(in: storage).count == 1)
    }

    @Test("a second pass does not delete audio again")
    func idempotentPassDoesNotRedelete() throws {
        let storage = StorageService(inMemory: true)
        let c = clip(transcript: "hello")
        var deletions = 0
        _ = ArrivedClipMaterializer.materialize(c, in: storage.viewContext,
                                                deleteAudio: { _ in deletions += 1; return true })
        _ = ArrivedClipMaterializer.materialize(c, in: storage.viewContext,
                                                deleteAudio: { _ in deletions += 1; return true })
        #expect(deletions == 1)
    }

    // MARK: - §4 · heard nothing

    /// **A recording that found no speech becomes an EMPTY memory, not an
    /// error and not a discard** (Tom, 2026-09-17). She spoke; we heard
    /// nothing; the memory exists and she can type what she meant. *We never
    /// discard work the user walked away from* still holds — what we kept is
    /// the memory, not the silence.
    @Test("a silent recording still becomes a memory")
    func silenceStillBecomesAMemory() throws {
        let storage = StorageService(inMemory: true)
        _ = ArrivedClipMaterializer.materialize(clip(transcript: ""),
                                                in: storage.viewContext,
                                                deleteAudio: { _ in true })
        let all = entries(in: storage)
        #expect(all.count == 1, "silence is not a reason to throw her recording away")
        #expect(all.first?.content == "", "the writing is empty — she fills it, we do not fill it for her")
    }

    /// The honest-absence copy is chosen from state that ALREADY EXISTS —
    /// `sourceDevice` plus an empty body. Ruled "copy, not schema", so no new
    /// field carries it, and she never has to delete a sentence of ours before
    /// typing her own.
    @Test("an empty watch arrival gets the heard-nothing invite, and a typed blank does not")
    func heardNothingInviteIsScopedToRecordings() throws {
        let fromWatch = EmptyWritingInvite.text(
            isEmpty: true, sourceDevice: .watch, inputType: .voiceInApp
        )
        #expect(fromWatch != nil)
        #expect(fromWatch?.lowercased().contains("didn't catch") == true)

        #expect(EmptyWritingInvite.text(isEmpty: true, sourceDevice: .phone, inputType: .typed) == nil,
                "a memory she deliberately left blank is not told we heard nothing")
        #expect(EmptyWritingInvite.text(isEmpty: false, sourceDevice: .watch, inputType: .voiceInApp) == nil,
                "a memory with writing in it needs no invite")
    }

    @Test("the invite never blames her and never reads as an error")
    func invitePosture() throws {
        let text = try #require(EmptyWritingInvite.text(
            isEmpty: true, sourceDevice: .watch, inputType: .voiceInApp
        )).lowercased()
        // NOT a blanket ban on "you" — the invite has to address her ("write
        // what you meant to"). What is banned is BLAME and the error register.
        for banned in ["sorry", "failed", "error", "couldn't understand", "try again",
                       "you didn't", "you were", "your recording was"] {
            #expect(!text.contains(banned), "honest absence, never blame or error: \(text)")
        }
        // We own the miss on our side rather than describing hers.
        #expect(text.contains("we didn't"), "the app takes the miss: \(text)")
        #expect(text.contains("write"), "it must hand her the next action")
    }
}
