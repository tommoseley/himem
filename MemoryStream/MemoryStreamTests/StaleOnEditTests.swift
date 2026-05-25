import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for the 2026-05-15 gap: Tom edited two existing clips in
/// an already-organized memory and the AI Suggestions card never offered
/// the Refresh affordance because `clipsAddedSinceLastOrganize` only
/// counts clips whose `createdAt > lastOrganizedAt`. Edits don't bump
/// `createdAt`, so the stale signal stayed at zero.
///
/// Two halves to the fix:
///   • Data layer — `MediaReference.lastEditedAt` bumped by every
///     `EntryLifecycleService` edit path that mutates clip content.
///   • Derived layer — `JournalEntry.clipsEditedSinceLastOrganize`
///     (count of edits after the organize) and
///     `JournalEntry.hasChangesSinceLastOrganize` (Bool combining
///     both add and edit signals — the gate the card consults).
///
/// `@Suite(.serialized)` because StorageService(inMemory:) creates a
/// dedicated NSPersistentContainer per test, but EntryLifecycleService
/// has `@MainActor` plumbing that doesn't play well with parallel test
/// invocations.
@MainActor
@Suite(.serialized)
struct StaleOnEditTests {

    // MARK: - Setup helpers (parallel to EntryLifecycleServiceTests)

    private func makeService() -> (StorageService, EntryLifecycleService) {
        let storage = StorageService(inMemory: true)
        let service = EntryLifecycleService(storage: storage, processingEngine: nil)
        return (storage, service)
    }

    private func fetchEntry(_ id: UUID, in storage: StorageService) -> JournalEntry? {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? storage.viewContext.fetch(request).first
    }

    private func fetchMediaRef(_ id: UUID, in storage: StorageService) -> MediaReference? {
        let request = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? storage.viewContext.fetch(request).first
    }

    // MARK: - Edit-path lastEditedAt bumping

    /// Money test 1: editing a `.note` fragment's text bumps
    /// `lastEditedAt`. Without this, the stale signal stays nil for the
    /// life of the clip and the Refresh affordance never surfaces.
    @Test func updateNoteFragment_bumpsLastEditedAt() throws {
        let (storage, service) = makeService()
        let entry = try service.createEmptyEntry(inputType: .composed)
        let note = try storage.createNoteFragment(
            for: entry,
            text: "original",
            createdAt: Date(timeIntervalSinceReferenceDate: 0)
        )
        try storage.viewContext.save()
        #expect(note.lastEditedAt == nil)
        let before = Date()

        service.updateNoteFragment(id: note.id, text: "edited", entryId: entry.id)

        let refreshed = try #require(fetchMediaRef(note.id, in: storage))
        #expect(refreshed.text == "edited")
        let bumped = try #require(refreshed.lastEditedAt)
        #expect(bumped >= before)
    }

    /// Money test 2: editing a voice fragment's transcript bumps
    /// `lastEditedAt`. Transcript edits are the other clip-content
    /// mutation path the user can drive from the detail view.
    @Test func updateMediaTranscript_bumpsLastEditedAt() throws {
        let (storage, service) = makeService()
        let entry = try service.createEmptyEntry(inputType: .composed)
        let voice = try storage.createMediaReference(
            for: entry,
            localIdentifier: "clip.m4a",
            mediaType: .voice
        )
        voice.transcript = "original transcript"
        voice.createdAt = Date(timeIntervalSinceReferenceDate: 0)
        try storage.viewContext.save()
        #expect(voice.lastEditedAt == nil)
        let before = Date()

        service.updateMediaTranscript(
            mediaId: voice.id,
            transcript: "edited transcript",
            entryId: entry.id
        )

        let refreshed = try #require(fetchMediaRef(voice.id, in: storage))
        #expect(refreshed.transcript == "edited transcript")
        let bumped = try #require(refreshed.lastEditedAt)
        #expect(bumped >= before)
    }

    // MARK: - Derived stale signal

    /// Money test 3 — the exact scenario Tom hit on 2026-05-15. An
    /// entry was organized, no new clips were added, but two existing
    /// clips' transcripts were edited. The chip + card must report
    /// stale; `hasChangesSinceLastOrganize` is the gate they consult.
    @Test func hasChangesSinceLastOrganize_trueAfterTwoTranscriptEdits() throws {
        let (storage, service) = makeService()
        let entry = try service.createEmptyEntry(inputType: .composed)
        let v1 = try storage.createMediaReference(for: entry, localIdentifier: "v1.m4a", mediaType: .voice)
        v1.transcript = "first"
        v1.createdAt = Date(timeIntervalSinceReferenceDate: 0)
        let v2 = try storage.createMediaReference(for: entry, localIdentifier: "v2.m4a", mediaType: .voice)
        v2.transcript = "second"
        v2.createdAt = Date(timeIntervalSinceReferenceDate: 1)
        // Organize ran AFTER both clips were captured but BEFORE the user
        // came back to edit them.
        entry.lastOrganizedAt = Date(timeIntervalSinceReferenceDate: 10)
        try storage.viewContext.save()

        // No edits yet — clean.
        #expect(entry.hasChangesSinceLastOrganize == false)
        #expect(entry.clipsEditedSinceLastOrganize == 0)

        // User edits both transcripts after the organize.
        service.updateMediaTranscript(mediaId: v1.id, transcript: "first edited", entryId: entry.id)
        service.updateMediaTranscript(mediaId: v2.id, transcript: "second edited", entryId: entry.id)

        let refreshed = try #require(fetchEntry(entry.id, in: storage))
        #expect(refreshed.clipsEditedSinceLastOrganize == 2)
        #expect(refreshed.hasChangesSinceLastOrganize == true)
        // Add count stays zero — no new clips were captured.
        #expect(refreshed.clipsAddedSinceLastOrganize == 0)
    }

    /// Edits older than the last organize don't count — the user already
    /// got the benefit of the organize after the edit, so the stale
    /// signal is dead until the next mutation.
    @Test func clipsEditedSinceLastOrganize_ignoresEditsPriorToOrganize() throws {
        let (storage, _) = makeService()
        let entry = try storage.createEntry(content: "x", inputType: .typed)
        let note = try storage.createNoteFragment(
            for: entry,
            text: "before",
            createdAt: Date(timeIntervalSinceReferenceDate: 0)
        )
        note.lastEditedAt = Date(timeIntervalSinceReferenceDate: 5)
        entry.lastOrganizedAt = Date(timeIntervalSinceReferenceDate: 10)
        try storage.viewContext.save()

        #expect(entry.clipsEditedSinceLastOrganize == 0)
        #expect(entry.hasChangesSinceLastOrganize == false)
    }

    /// A clip that was both added AND edited after the last organize
    /// counts once in the "added" bucket, not twice. The card subtitle
    /// shouldn't say "1 new, 1 edited" for the same clip — the add
    /// already implies the content is post-organize, so we don't
    /// double-charge.
    @Test func clipsEditedSinceLastOrganize_excludesNewlyAddedClips() throws {
        let (storage, _) = makeService()
        let entry = try storage.createEntry(content: "x", inputType: .typed)
        entry.lastOrganizedAt = Date(timeIntervalSinceReferenceDate: 10)
        let note = try storage.createNoteFragment(
            for: entry,
            text: "added then edited",
            createdAt: Date(timeIntervalSinceReferenceDate: 20)  // after organize
        )
        note.lastEditedAt = Date(timeIntervalSinceReferenceDate: 30)
        try storage.viewContext.save()

        #expect(entry.clipsAddedSinceLastOrganize == 1)
        #expect(entry.clipsEditedSinceLastOrganize == 0)
        #expect(entry.hasChangesSinceLastOrganize == true)
    }

    /// Never-organized entries shouldn't surface "stale" — there's
    /// nothing to be stale against. The first-organize path uses a
    /// different affordance ("Organize with AI").
    @Test func hasChangesSinceLastOrganize_falseWhenNeverOrganized() throws {
        let (storage, _) = makeService()
        let entry = try storage.createEntry(content: "x", inputType: .typed)
        let note = try storage.createNoteFragment(for: entry, text: "n", createdAt: Date())
        note.lastEditedAt = Date()
        try storage.viewContext.save()

        #expect(entry.lastOrganizedAt == nil)
        #expect(entry.hasChangesSinceLastOrganize == false)
        #expect(entry.clipsEditedSinceLastOrganize == 0)
    }

    /// Mixed signal: 1 new clip + 1 edited existing clip → both
    /// counters fire, gate is true. The subtitle layer will use the
    /// pair to render "1 new, 1 edited."
    @Test func hasChangesSinceLastOrganize_combinesAddedAndEdited() throws {
        let (storage, _) = makeService()
        let entry = try storage.createEntry(content: "x", inputType: .typed)
        // Original clip — pre-organize creation, post-organize edit.
        let original = try storage.createNoteFragment(
            for: entry,
            text: "old",
            createdAt: Date(timeIntervalSinceReferenceDate: 0)
        )
        entry.lastOrganizedAt = Date(timeIntervalSinceReferenceDate: 10)
        original.lastEditedAt = Date(timeIntervalSinceReferenceDate: 20)
        // New clip — captured after organize.
        _ = try storage.createNoteFragment(
            for: entry,
            text: "fresh",
            createdAt: Date(timeIntervalSinceReferenceDate: 30)
        )
        try storage.viewContext.save()

        #expect(entry.clipsAddedSinceLastOrganize == 1)
        #expect(entry.clipsEditedSinceLastOrganize == 1)
        #expect(entry.hasChangesSinceLastOrganize == true)
    }
}
