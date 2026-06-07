import Testing
import Foundation
import CoreData
@testable import HiMem

/// Characterization tests for `JournalCaptureCoordinator` (CRAP audit
/// Batch 5 — pulled out of `JournalView.handleCapturedItemForNewEntry`
/// so the create-new-memory dispatch is unit-testable).
///
/// Parallel to `EntryAppendCoordinatorTests` (Batch 2) but for the
/// other side of the capture spec: this one creates new memories
/// rather than appending to an existing one. The same empty-input
/// guards apply (no phantom memories from aborted captures), plus a
/// special path for `.note` that prepends an optional seed note
/// (used by the Search → New Memory hand-off where the search query
/// becomes the body of the new note).
@MainActor
@Suite(.serialized)
struct JournalCaptureCoordinatorTests {

    private func makeContext() -> (StorageService, JournalViewModel, JournalCaptureCoordinator) {
        let storage = StorageService(inMemory: true)
        let vm = JournalViewModel(storage: storage, processingEngine: nil)
        let coord = JournalCaptureCoordinator()
        return (storage, vm, coord)
    }

    private func memoryCount(in storage: StorageService) -> Int {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        return (try? storage.viewContext.count(for: request)) ?? 0
    }

    // MARK: - Voice

    @Test func voice_withFilename_createsMemory() {
        let (storage, vm, coord) = makeContext()
        let before = memoryCount(in: storage)
        let id = coord.createNewMemory(
            from: .voice(filename: "rec-001.m4a", transcript: "hello"),
            viewModel: vm,
            seedNote: nil
        )
        #expect(id != nil)
        #expect(memoryCount(in: storage) == before + 1)
    }

    @Test func voice_emptyTranscriptNilFilename_doesNotCreate() {
        let (storage, vm, coord) = makeContext()
        let before = memoryCount(in: storage)
        let id = coord.createNewMemory(
            from: .voice(filename: nil, transcript: "   "),
            viewModel: vm,
            seedNote: nil
        )
        #expect(id == nil)
        #expect(memoryCount(in: storage) == before)
    }

    // MARK: - Note (with optional seed)

    @Test func note_withText_createsMemory() {
        let (storage, vm, coord) = makeContext()
        let before = memoryCount(in: storage)
        let id = coord.createNewMemory(
            from: .note(text: "a thought"),
            viewModel: vm,
            seedNote: nil
        )
        #expect(id != nil)
        #expect(memoryCount(in: storage) == before + 1)
    }

    @Test func note_emptyText_andEmptySeed_doesNotCreate() {
        let (storage, vm, coord) = makeContext()
        let before = memoryCount(in: storage)
        let id = coord.createNewMemory(
            from: .note(text: "  \n  "),
            viewModel: vm,
            seedNote: nil
        )
        #expect(id == nil)
        #expect(memoryCount(in: storage) == before)
    }

    @Test func note_emptyText_butSeedNotePresent_creates() {
        // The Search → New Memory hand-off: the user typed a query,
        // tapped New Memory, and the query becomes the body even if
        // they didn't type anything in the note composer.
        let (storage, vm, coord) = makeContext()
        let before = memoryCount(in: storage)
        let id = coord.createNewMemory(
            from: .note(text: ""),
            viewModel: vm,
            seedNote: "from search"
        )
        #expect(id != nil)
        #expect(memoryCount(in: storage) == before + 1)
    }

    @Test func note_textAndSeed_joinsBoth() {
        // Seed note + composer text — both surface in the body of
        // the new memory. The view layer's caller is responsible
        // for clearing pendingNoteForNewEntry after this returns;
        // the coordinator just composes the body.
        let (storage, vm, coord) = makeContext()
        let id = coord.createNewMemory(
            from: .note(text: "follow-up thought"),
            viewModel: vm,
            seedNote: "seeded query"
        )
        let created = try? storage.viewContext.fetch(NSFetchRequest<JournalEntry>(entityName: "JournalEntry")).first(where: { $0.id == id })
        #expect(created?.content.contains("seeded query") == true)
        #expect(created?.content.contains("follow-up thought") == true)
    }

    // MARK: - Attach

    @Test func attach_emptyIds_doesNotCreate() {
        let (storage, vm, coord) = makeContext()
        let before = memoryCount(in: storage)
        let id = coord.createNewMemory(
            from: .attach(items: []),
            viewModel: vm,
            seedNote: nil
        )
        #expect(id == nil)
        #expect(memoryCount(in: storage) == before)
    }

    // MARK: - voiceSession (On a roll)

    @Test func voiceSession_emptyClips_doesNotCreate() {
        let (storage, vm, coord) = makeContext()
        let before = memoryCount(in: storage)
        let id = coord.createNewMemory(
            from: .voiceSession(clips: [], rollGroupId: UUID()),
            viewModel: vm,
            seedNote: nil
        )
        #expect(id == nil)
        #expect(memoryCount(in: storage) == before)
    }
}
