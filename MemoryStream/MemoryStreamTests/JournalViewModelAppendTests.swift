import Testing
import Foundation
@testable import MemoryStream

@MainActor
struct JournalViewModelAppendTests {

    private func makeViewModel() -> JournalViewModel {
        let storage = StorageService(inMemory: true)
        return JournalViewModel(storage: storage, processingEngine: nil)
    }

    private func seedEntry(on vm: JournalViewModel, content: String = "seed") -> UUID {
        vm.saveEntry(content: content, inputType: .typed)
        return vm.entries.first!.id
    }

    /// Regression guard for the single-media append path that the new inline
    /// auto-attach UI will drive. The old flow went through Composer staging;
    /// the new flow calls appendToEntry with exactly one media capture.
    @Test func appendToEntry_withSingleMedia_persistsMediaReference() {
        let vm = makeViewModel()
        let entryId = seedEntry(on: vm)

        vm.appendToEntry(
            entryId: entryId,
            additionalContent: "",
            mediaCaptures: [(localIdentifier: "photo-asset-1", mediaType: .image)]
        )

        let updated = vm.currentEntry(id: entryId)
        #expect(updated?.mediaItems.count == 1)
        #expect(updated?.mediaItems.first?.localIdentifier == "photo-asset-1")
        #expect(updated?.mediaItems.first?.mediaType == .image)
    }

    @Test func appendToEntry_preservesExistingMedia() {
        let vm = makeViewModel()
        let entryId = seedEntry(on: vm)

        vm.appendToEntry(
            entryId: entryId,
            additionalContent: "",
            mediaCaptures: [(localIdentifier: "first", mediaType: .image)]
        )
        vm.appendToEntry(
            entryId: entryId,
            additionalContent: "",
            mediaCaptures: [(localIdentifier: "second", mediaType: .video)]
        )

        let updated = vm.currentEntry(id: entryId)
        #expect(updated?.mediaItems.count == 2)
        let ids = Set(updated?.mediaItems.map(\.localIdentifier) ?? [])
        #expect(ids == ["first", "second"])
    }

    /// Money test for Bug 2 (stale snapshot). The view previously held
    /// `selectedEntry: EntryDisplayModel?` — a value snapshot captured at
    /// navigation-push time. After append, viewModel.entries updated but the
    /// snapshot did not, so the expanded view rendered stale media.
    ///
    /// The fix is to expose a live lookup (`currentEntry(id:)`) and have the
    /// view resolve the current entry by id each render. This test locks in
    /// that contract: after append, a fresh lookup reflects the new media
    /// while a captured value snapshot does not.
    @Test func currentEntry_returnsFreshDataAfterAppend() {
        let vm = makeViewModel()
        let entryId = seedEntry(on: vm)

        let snapshot = vm.currentEntry(id: entryId)!
        #expect(snapshot.mediaItems.isEmpty)

        vm.appendToEntry(
            entryId: entryId,
            additionalContent: "",
            mediaCaptures: [(localIdentifier: "new-photo", mediaType: .image)]
        )

        // The captured value snapshot is frozen — this is the root-cause
        // behavior of Bug 2.
        #expect(snapshot.mediaItems.isEmpty)

        // A fresh lookup reflects the append — this is the fix path the view
        // must adopt.
        let fresh = vm.currentEntry(id: entryId)
        #expect(fresh?.mediaItems.count == 1)
    }

    @Test func appendToEntry_appendsTextContent() {
        let vm = makeViewModel()
        let entryId = seedEntry(on: vm, content: "original")

        vm.appendToEntry(entryId: entryId, additionalContent: "more")

        let updated = vm.currentEntry(id: entryId)
        #expect(updated?.content == "original\n\nmore")
    }

    /// Spec for the staging + commit flow on the expanded view. A single commit
    /// carries typed text, concatenated audio transcripts, and a mixed-media
    /// batch (photo + video + voice) — one `appendToEntry` call, so the
    /// downstream ProcessingEngine runs exactly once per user-intent commit,
    /// per the Crucible "one inference per commit" rule.
    @Test func appendToEntry_commitsMixedMediaBatch() {
        let vm = makeViewModel()
        let entryId = seedEntry(on: vm, content: "seed note")

        let assembledText = "a typed note\n\ntranscript from clip 1\n\ntranscript from clip 2"
        vm.appendToEntry(
            entryId: entryId,
            additionalContent: assembledText,
            mediaCaptures: [
                (localIdentifier: "photo-1", mediaType: .image),
                (localIdentifier: "video-1", mediaType: .video),
                (localIdentifier: "voice-1.m4a", mediaType: .voice),
                (localIdentifier: "voice-2.m4a", mediaType: .voice)
            ]
        )

        let updated = vm.currentEntry(id: entryId)
        #expect(updated?.content == "seed note\n\n" + assembledText)
        #expect(updated?.mediaItems.count == 4)

        let voiceItems = updated?.mediaItems.filter { $0.mediaType == .voice } ?? []
        #expect(voiceItems.count == 2)
        let voiceIds = Set(voiceItems.map(\.localIdentifier))
        #expect(voiceIds == ["voice-1.m4a", "voice-2.m4a"])

        // audioFilePath is untouched — Derived vs. primary / no-silent-discard.
        #expect(updated?.audioFilePath == nil)
    }

    /// New memories created from Composer never use the legacy
    /// `audioFilePath` slot. Voice clips captured during composition stage as
    /// mediaCaptures and persist as MediaReference(.voice), keeping the
    /// "any type, any count" rule satisfied for new entries too.
    @Test func saveEntry_withVoiceMediaCaptures_createsVoiceMediaReferences() {
        let vm = makeViewModel()

        vm.saveEntry(
            content: "field notes from the garden",
            inputType: .composed,
            mediaCaptures: [
                (localIdentifier: "clip-1.m4a", mediaType: .voice),
                (localIdentifier: "clip-2.m4a", mediaType: .voice),
                (localIdentifier: "bed-4-photo", mediaType: .image)
            ]
        )

        let entry = vm.entries.first
        #expect(entry?.audioFilePath == nil)
        let voiceItems = entry?.mediaItems.filter { $0.mediaType == .voice } ?? []
        #expect(voiceItems.count == 2)
        #expect(entry?.mediaItems.filter { $0.mediaType == .image }.count == 1)
    }

    /// Voice appends do NOT overwrite an existing `audioFilePath`. If the
    /// entry has a legacy primary audio (from pre-staging days), appending
    /// voice creates a new MediaReference and leaves the original intact.
    @Test func appendToEntry_withVoice_preservesExistingAudioFilePath() {
        let vm = makeViewModel()
        vm.saveEntry(
            content: "seed",
            inputType: .typed,
            audioFilePath: "legacy-audio.m4a"
        )
        let entryId = vm.entries.first!.id

        vm.appendToEntry(
            entryId: entryId,
            additionalContent: "",
            mediaCaptures: [(localIdentifier: "new-voice.m4a", mediaType: .voice)]
        )

        let updated = vm.currentEntry(id: entryId)
        #expect(updated?.audioFilePath == "legacy-audio.m4a")
        #expect(updated?.mediaItems.filter { $0.mediaType == .voice }.count == 1)
    }
}
