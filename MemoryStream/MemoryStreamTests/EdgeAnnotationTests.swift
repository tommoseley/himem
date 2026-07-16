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

    @Test func updateEdgeAnnotation_independentAcrossMemories() throws {
        let (storage, service) = makeStore()
        let memA = try seedMemory(in: storage, title: "A")
        let memB = try seedMemory(in: storage, title: "B")
        let shared = try storage.createVoiceFragment(for: memA, audioFilename: "s.caf", transcript: "T")
        try StorageService.createEdge(from: memB, to: shared, linkedAt: Date(), in: storage.viewContext)
        try storage.save(context: storage.viewContext)
        let edgeA = try #require(shared.edgesArray.first { $0.memoryId == memA.id })
        let edgeB = try #require(shared.edgesArray.first { $0.memoryId == memB.id })

        service.updateEdgeAnnotation(edgeId: edgeA.id, annotation: "means X in A")

        #expect(edgeA.annotation == "means X in A")
        #expect(edgeB.annotation == nil, "the same clip's annotation in memory B is independent (per-edge context)")
    }
}
