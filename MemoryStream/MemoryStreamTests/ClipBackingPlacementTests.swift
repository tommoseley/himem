import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for TestFlight (2026-07-25): the "Add to a memory" placeholder
/// and "Transcribe again does nothing" on manifest-backed (`InboxClip`) clips.
/// Both were the **manifest-vs-ref backing split silently diverging** — ref
/// clips worked (PlaceClipSheet / memory-store audio), manifest clips hit a
/// dev-text placeholder / an early `return`. These lock BOTH backings on BOTH
/// actions so the split can't diverge again.
@MainActor
@Suite(.serialized)
struct ClipBackingPlacementTests {

    // MARK: - Transcribe again — both backings resolve a real audio URL

    /// Before the fix, `.inbox` re-transcribe early-returned (silent no-op).
    /// Now the URL resolves per backing — managed → memory store; inbox →
    /// memory store if a phone clip already sits there, else the inbox store.
    /// Never nil, never the wrong store.
    @Test func retranscribeAudioURL_resolvesPerBacking_neverNoOp() {
        let voice = SpeechService.audioURL(for: "clip.m4a")
        let inbox = InboxManifest.audioURL(for: "clip.m4a")
        #expect(voice != inbox, "the two stores must be distinct for this test to mean anything")
        // Managed (ref-backed) → always the memory store.
        #expect(ClipEditorModal.retranscribeAudioURL(isInbox: false, filename: "clip.m4a", fileExists: { _ in false }) == voice)
        // Inbox (manifest-backed), phone clip already in the memory store.
        #expect(ClipEditorModal.retranscribeAudioURL(isInbox: true, filename: "clip.m4a", fileExists: { $0 == voice }) == voice)
        // Inbox, watch clip only in the inbox store → resolves there (NOT the
        // old no-op).
        #expect(ClipEditorModal.retranscribeAudioURL(isInbox: true, filename: "clip.m4a", fileExists: { _ in false }) == inbox)
    }

    // MARK: - Add to a memory — both backings place (not a placeholder / no-op)

    /// Managed backing: adding a ref-backed clip to another memory creates an
    /// edge (the PlaceClipSheet path — the one that already worked).
    @Test func managedClip_addToExisting_createsEdge() throws {
        let storage = StorageService(inMemory: true)
        let target = try storage.createEntry(content: "", inputType: .typed, title: "First")
        let ref = try storage.createVoiceFragment(for: target, audioFilename: "a.m4a", transcript: "hi")
        let other = try storage.createEntry(content: "", inputType: .typed, title: "Other")
        try StorageService.createEdge(from: other, to: ref, linkedAt: Date(), in: storage.viewContext)
        try storage.viewContext.save()
        #expect(ref.referencingMemoryCount == 2, "managed clip placed into a second memory via an edge")
    }

    /// Inbox backing: promoting a bench clip into an existing memory (the core
    /// of `EntryLifecycleService.placeInboxClip`, via `appendClips`)
    /// materializes a `MediaReference` + edge — the thing the placeholder used
    /// to stub out.
    @Test func inboxClip_promoteIntoMemory_materializesRefAndEdge() throws {
        let storage = StorageService(inMemory: true)
        let lifecycle = EntryLifecycleService(storage: storage, processingEngine: .shared)
        let target = try storage.createEntry(content: "", inputType: .typed, title: "Target")

        let written = lifecycle.appendClips(
            entryId: target.id,
            clips: [("bench.m4a", "a bench clip transcript", Date())],
            sourceDevice: .phone
        )
        #expect(written == 1, "the manifest-backed clip is materialized, not stubbed")

        storage.viewContext.refreshAllObjects()
        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        req.predicate = NSPredicate(format: "osIdentifier == %@", "bench.m4a")
        let ref = try storage.viewContext.fetch(req).first
        #expect(ref != nil, "a MediaReference now backs the promoted clip")
        #expect(ref?.referencingMemoryCount == 1, "edged to the target memory")
    }
}
