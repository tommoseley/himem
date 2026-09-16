import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for `updateEdgeAnnotation` — the per-edge "why this matters
/// here" write behind the unified Clip Editor's Zone 2. The annotation is
/// context (per memory), NOT the atom: editing it must never touch the clip's
/// transcript, and the same clip's annotation is independent across memories.
@MainActor
@Suite(.serialized)
struct EdgeAnnotationTests {

    private func makeStore() -> (StorageService, EntryLifecycleService) {
        let storage = StorageService(inMemory: true)
        let service = EntryLifecycleService(storage: storage, processingEngine: nil)
        return (storage, service)
    }

    private func seedMemory(in storage: StorageService, title: String) throws -> JournalEntry {
        let entry = try storage.createEntry(content: "", inputType: .typed)
        entry.title = title
        try storage.viewContext.save()
        return entry
    }

    @Test func updateEdgeAnnotation_writesTrimmed_atomUntouched() throws {
        let (storage, service) = makeStore()
        let mem = try seedMemory(in: storage, title: "Maine trip")
        let ref = try storage.createVoiceFragment(for: mem, audioFilename: "a.caf", transcript: "the plan became real")
        let edge = try #require(ref.edgesArray.first)

        service.updateEdgeAnnotation(edgeId: edge.id, annotation: "  Why it matters here  ")

        #expect(edge.annotation == "Why it matters here", "annotation is trimmed + saved on the edge")
        #expect(ref.transcript == "the plan became real", "the clip atom's transcript is untouched")
    }

    @Test func updateEdgeAnnotation_whitespace_clearsToNil() throws {
        let (storage, service) = makeStore()
        let mem = try seedMemory(in: storage, title: "M")
        let ref = try storage.createVoiceFragment(for: mem, audioFilename: "a.caf", transcript: "T")
        let edge = try #require(ref.edgesArray.first)

        service.updateEdgeAnnotation(edgeId: edge.id, annotation: "note")
        #expect(edge.annotation == "note")
        service.updateEdgeAnnotation(edgeId: edge.id, annotation: "   \n ")
        #expect(edge.annotation == nil, "whitespace-only clears the annotation")
    }

    // `updateEdgeAnnotation_independentAcrossMemories` was RETIRED by the F2
    // ruling (Tom, 2026-09-16), not deleted for convenience.
    //
    // It asserted that one clip's annotation in memory A is independent of the
    // same clip's annotation in memory B — per-edge context, which was the
    // point of the annotation under clip↔memory many-to-many. The vocabulary
    // retirement supersedes that ontology: **a part belongs to exactly one
    // memory**, so "across memories" has no referent. This is a test of a
    // CAPABILITY THE RULING REMOVES, not of data the ruling preserves — the
    // distinction that decided it. Keeping it against historical rows via
    // `HistoricalEdgeFixture` would guard a behaviour nothing can produce.
    //
    // CONSEQUENCE, stated plainly because someone will ask: existing
    // annotations STAY IN THE STORE and become unread. `annotation` is still on
    // `MemoryClipEdge` (F2 is write-side only — no schema change, no
    // migration), `createEdge` has always written it nil, and the sole reader
    // is `ClipEditorModal:912`, which I2 deletes with the clip-atom editor.
    // Nothing displays them; nothing destroys them. That is the honest
    // position, and it is deliberate rather than overlooked.
    //
    // The two surviving tests above still guard `updateEdgeAnnotation` itself
    // (trimming, whitespace-clears-to-nil) for as long as the writer exists.
}
