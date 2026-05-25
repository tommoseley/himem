import Testing
import Foundation
@testable import HiMem

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
    ///
    /// Post-fragment-per-capture: the seed's typed-only content ("seed") gets
    /// promoted to its own `.note` fragment when the photo append lands, so
    /// the photo capture's timing isn't conflated with the seed's. Two
    /// chronological panels: the note then the photo.
    @Test func appendToEntry_withSingleMedia_persistsMediaReference() {
        let vm = makeViewModel()
        let entryId = seedEntry(on: vm)

        vm.appendToEntry(
            entryId: entryId,
            additionalContent: "",
            mediaCaptures: [(localIdentifier: "photo-asset-1", mediaType: .image)]
        )

        let updated = vm.currentEntry(id: entryId)
        let photos = updated?.mediaItems.filter { $0.mediaType == .image } ?? []
        #expect(photos.count == 1)
        #expect(photos.first?.localIdentifier == "photo-asset-1")
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
        let ids = Set(updated?.mediaItems.compactMap(\.localIdentifier) ?? [])
        #expect(ids.contains("first"))
        #expect(ids.contains("second"))
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
        // must adopt. Count is non-empty (seed-content promotion + new
        // photo); the specific count isn't the contract this test guards.
        let fresh = vm.currentEntry(id: entryId)
        #expect(!(fresh?.mediaItems.isEmpty ?? true))
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
    ///
    /// Each text-bearing capture becomes its own fragment so the chronological
    /// stream renders one panel per capture event: the seed's text gets
    /// promoted to a `.note`, the assembled-text becomes another `.note`, and
    /// the four media captures each get their own MediaReference.
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
        let voiceItems = updated?.mediaItems.filter { $0.mediaType == .voice } ?? []
        #expect(voiceItems.count == 2)
        let voiceIds = Set(voiceItems.map(\.localIdentifier))
        #expect(voiceIds == ["voice-1.m4a", "voice-2.m4a"])

        let photoItems = updated?.mediaItems.filter { $0.mediaType == .image } ?? []
        #expect(photoItems.map(\.localIdentifier) == ["photo-1"])

        let videoItems = updated?.mediaItems.filter { $0.mediaType == .video } ?? []
        #expect(videoItems.map(\.localIdentifier) == ["video-1"])

        // Seed text promoted + assembled text appended as separate notes.
        let noteTexts = Set(updated?.mediaItems
            .filter { $0.mediaType == .note }
            .compactMap(\.text) ?? [])
        #expect(noteTexts == ["seed note", assembledText])
    }

    /// Composer voice clips persist as `.voice` MediaReferences alongside
    /// any photo/video captures, satisfying the "any type, any count" rule
    /// for new entries.
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
        let voiceItems = entry?.mediaItems.filter { $0.mediaType == .voice } ?? []
        #expect(voiceItems.count == 2)
        #expect(entry?.mediaItems.filter { $0.mediaType == .image }.count == 1)
    }

    /// FAB voice clips land as a `.voice` MediaReference via the
    /// `voiceFilename` parameter; appending a second voice clip creates a
    /// new fragment instead of overwriting the first. Locks in the
    /// post-FragmentMigration single-shape semantics where every voice
    /// capture is its own fragment.
    @Test func saveEntry_withVoiceFilename_createsVoiceFragmentAndAppendsMore() {
        let vm = makeViewModel()
        vm.saveEntry(
            content: "seed transcript",
            inputType: .voiceInApp,
            voiceFilename: "first-voice.m4a"
        )
        let entryId = vm.entries.first!.id

        let initial = vm.currentEntry(id: entryId)
        let initialVoice = initial?.mediaItems.filter { $0.mediaType == .voice } ?? []
        #expect(initialVoice.count == 1)
        #expect(initialVoice.first?.localIdentifier == "first-voice.m4a")

        vm.appendToEntry(
            entryId: entryId,
            additionalContent: "",
            mediaCaptures: [(localIdentifier: "second-voice.m4a", mediaType: .voice)]
        )

        let updated = vm.currentEntry(id: entryId)
        let voiceIds = Set(updated?.mediaItems.filter { $0.mediaType == .voice }.map(\.localIdentifier) ?? [])
        #expect(voiceIds == ["first-voice.m4a", "second-voice.m4a"])
    }
}
