import Testing
import Foundation
import CoreData
@testable import HiMem

/// Characterization tests for `EntryAppendCoordinator` (CRAP audit
/// Batch 2 — pulled out of `EntryExpandedView.handleCapturedItemForAppend`
/// so the per-modality dispatch is unit-testable without rendering).
///
/// The dispatch table is identical to what the view was doing before
/// the extraction: each `CapturedItem` case maps to a `lifecycle.append`
/// call with the right shape, with empty-input guards on `.voice`,
/// `.note`, and `.attach` to prevent no-op appends from polluting the
/// memory.
@MainActor
@Suite(.serialized)
struct EntryAppendCoordinatorTests {

    private func makeContext() -> (StorageService, EntryLifecycleService, JournalEntry, EntryAppendCoordinator) {
        let storage = StorageService(inMemory: true)
        let lifecycle = EntryLifecycleService(storage: storage, processingEngine: nil)
        let entry = try! storage.createEntry(content: "host memory", inputType: .typed)
        try! storage.viewContext.save()
        let coordinator = EntryAppendCoordinator()
        return (storage, lifecycle, entry, coordinator)
    }

    private func fragmentCount(for entry: JournalEntry, in storage: StorageService) -> Int {
        storage.viewContext.refresh(entry, mergeChanges: true)
        // Note + voice + photo + video + attach appends all land as
        // MediaReferences on the entry. Count the set to detect
        // whether the coordinator actually called through to
        // lifecycle.append vs. short-circuited on an empty input.
        return entry.mediaReferencesArray.count
    }

    // MARK: - Voice

    @Test func voice_withFilename_appendsOnce() {
        let (storage, lifecycle, entry, coord) = makeContext()
        let before = fragmentCount(for: entry, in: storage)
        coord.apply(.voice(filename: "rec-001.m4a", transcript: "hello world"),
                    to: entry.id,
                    using: lifecycle,
                    context: storage.viewContext)
        #expect(fragmentCount(for: entry, in: storage) > before)
    }

    @Test func voice_emptyTranscriptNilFilename_doesNotAppend() {
        // Spec: an empty voice payload (no audio + no transcript) is
        // a no-op. The user discarded mid-recording or the recorder
        // produced nothing; the host memory shouldn't get a phantom
        // fragment.
        let (storage, lifecycle, entry, coord) = makeContext()
        let before = fragmentCount(for: entry, in: storage)
        coord.apply(.voice(filename: nil, transcript: "   "),
                    to: entry.id,
                    using: lifecycle,
                    context: storage.viewContext)
        #expect(fragmentCount(for: entry, in: storage) == before)
    }

    @Test func voice_whitespaceOnlyTranscript_butFilenamePresent_doesAppend() {
        // The recording exists even if speech recognition produced
        // nothing useful. Append the audio fragment so the user can
        // play it back later.
        let (storage, lifecycle, entry, coord) = makeContext()
        let before = fragmentCount(for: entry, in: storage)
        coord.apply(.voice(filename: "rec-002.m4a", transcript: "  "),
                    to: entry.id,
                    using: lifecycle,
                    context: storage.viewContext)
        #expect(fragmentCount(for: entry, in: storage) > before)
    }

    // MARK: - Note

    @Test func note_withText_appends() {
        let (storage, lifecycle, entry, coord) = makeContext()
        let before = fragmentCount(for: entry, in: storage)
        coord.apply(.note(text: "a thought"),
                    to: entry.id,
                    using: lifecycle,
                    context: storage.viewContext)
        #expect(fragmentCount(for: entry, in: storage) > before)
    }

    @Test func note_whitespaceOnly_doesNotAppend() {
        let (storage, lifecycle, entry, coord) = makeContext()
        let before = fragmentCount(for: entry, in: storage)
        coord.apply(.note(text: "   \n  "),
                    to: entry.id,
                    using: lifecycle,
                    context: storage.viewContext)
        #expect(fragmentCount(for: entry, in: storage) == before)
    }

    // MARK: - Attach (library multi-select)

    @Test func attach_emptyIds_doesNotAppend() {
        let (storage, lifecycle, entry, coord) = makeContext()
        let before = fragmentCount(for: entry, in: storage)
        coord.apply(.attach(items: []),
                    to: entry.id,
                    using: lifecycle,
                    context: storage.viewContext)
        #expect(fragmentCount(for: entry, in: storage) == before)
    }

    // MARK: - voiceSession (On a roll)

    @Test func voiceSession_emptyClips_doesNotCrash_andDoesNotAppend() {
        // Defensive: an empty session would mean the user finished
        // the composer with nothing recorded. Don't pollute the
        // memory; don't crash on the location-stamp loop.
        let (storage, lifecycle, entry, coord) = makeContext()
        let before = fragmentCount(for: entry, in: storage)
        coord.apply(.voiceSession(clips: [], rollGroupId: UUID()),
                    to: entry.id,
                    using: lifecycle,
                    context: storage.viewContext)
        #expect(fragmentCount(for: entry, in: storage) == before)
    }

    // MARK: - activeCaptureModality state

    @Test func activeModality_clearsWhenSetToNil() {
        // The view drives this binding through the FAB picker; the
        // coordinator just holds the slot. Clearing it must work
        // (CaptureFlowHost dismiss path).
        let coord = EntryAppendCoordinator()
        coord.activeCaptureModality = .voice
        #expect(coord.activeCaptureModality == .voice)
        coord.activeCaptureModality = nil
        #expect(coord.activeCaptureModality == nil)
    }
}
