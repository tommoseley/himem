import Testing
import Foundation
import CoreData
@testable import HiMem

/// Phase 2+3 money tests for the atomic read+write flip to edges.
/// See `docs/architecture/2026-07-08-evidence-context-ontology-plan.md`
/// § Phase 2+3. Every test asserts an invariant that would have caught
/// a real bug — happy-path-only tests are not accepted per the plan's
/// test strategy.
@MainActor
@Suite(.serialized)
struct EvidenceEdgeReadWriteTests {

    private func makeStore() -> StorageService {
        StorageService(inMemory: true)
    }

    private func seedMemory(in storage: StorageService, title: String, createdAt: Date = Date()) throws -> JournalEntry {
        let entry = try storage.createEntry(content: "", inputType: .typed)
        entry.title = title
        entry.createdAt = createdAt
        try storage.viewContext.save()
        return entry
    }

    private func fetchEdges(memoryId: UUID? = nil, clipId: UUID? = nil, in storage: StorageService) throws -> [MemoryClipEdge] {
        let request = NSFetchRequest<MemoryClipEdge>(entityName: "MemoryClipEdge")
        var preds: [NSPredicate] = []
        if let memoryId { preds.append(NSPredicate(format: "memoryId == %@", memoryId as CVarArg)) }
        if let clipId { preds.append(NSPredicate(format: "clipId == %@", clipId as CVarArg)) }
        if !preds.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: preds)
        }
        return try storage.viewContext.fetch(request)
    }

    // MARK: - Money invariants

    /// The ontology's core promise. Same clip, two memories, one
    /// evidence record, two edges. If this fails the many-to-many
    /// story is broken and the whole plan is worthless.
    @Test func clipReferencedByTwoMemoriesRemainsOneEvidence() throws {
        let storage = makeStore()
        let memA = try seedMemory(in: storage, title: "Memory A")
        let memB = try seedMemory(in: storage, title: "Memory B")

        let ref = try storage.createVoiceFragment(
            for: memA,
            audioFilename: "shared.caf",
            transcript: "the waiter said something about cheesecake",
            createdAt: Date(timeIntervalSinceNow: -100)
        )

        // Attach the same ref to memory B via a second edge — the
        // schema move that makes "one clip cited by many memories"
        // possible. Uses the storage helper directly since v1 UI
        // doesn't yet expose this affordance.
        try StorageService.createEdge(
            from: memB,
            to: ref,
            linkedAt: Date(),
            in: storage.viewContext
        )
        try storage.save(context: storage.viewContext)

        let refs = try storage.viewContext.fetch(NSFetchRequest<MediaReference>(entityName: "MediaReference"))
        #expect(refs.count == 1, "Attaching the same ref to a second memory must NOT duplicate the ref — evidence stored once")

        let edgesA = try fetchEdges(memoryId: memA.id, in: storage)
        let edgesB = try fetchEdges(memoryId: memB.id, in: storage)
        #expect(edgesA.count == 1)
        #expect(edgesB.count == 1)
        #expect(edgesA.first?.clip?.id == ref.id)
        #expect(edgesB.first?.clip?.id == ref.id)

        // Both memories' `mediaReferencesArray` return the same ref
        // by identity — the read-through-edges path is honest.
        let clipViaA = memA.mediaReferencesArray.first
        let clipViaB = memB.mediaReferencesArray.first
        #expect(clipViaA?.objectID == clipViaB?.objectID)
    }

    /// `createMediaReference` accepts `capturedAt` and stamps
    /// `ref.createdAt` at creation time — the root fix that retires
    /// the 2026-07-07 post-save fixup pattern.
    @Test func createMediaReferenceStampsClipCapturedAt() throws {
        let storage = makeStore()
        let mem = try seedMemory(in: storage, title: "Historical")
        let clipTime = Date(timeIntervalSinceNow: -7 * 86_400)

        let ref = try storage.createMediaReference(
            for: mem,
            localIdentifier: "week-old.caf",
            mediaType: .voice,
            capturedAt: clipTime
        )

        let delta = abs((ref.createdAt ?? .distantPast).timeIntervalSince(clipTime))
        #expect(delta < 1.0, "createMediaReference must stamp the passed capturedAt, not Date()")

        // And the edge's linkedAt inherits too — the "added later"
        // timeline shows the actual capture moment, not the import.
        let edges = try fetchEdges(memoryId: mem.id, in: storage)
        let edge = try #require(edges.first)
        let edgeDelta = abs((edge.linkedAt ?? .distantPast).timeIntervalSince(clipTime))
        #expect(edgeDelta < 1.0)
    }

    /// Every write path creates the edge in the same transaction as
    /// the ref. Guards the temporary v1 invariant: no MediaReference
    /// exists with zero edges until Phase 6 lands.
    @Test func everyWritePathCreatesAtLeastOneEdge() throws {
        let storage = makeStore()
        let mem = try seedMemory(in: storage, title: "Invariant memory")

        // createMediaReference (generic media)
        let mediaRef = try storage.createMediaReference(
            for: mem,
            localIdentifier: "photo-1",
            mediaType: .image
        )
        #expect(!mediaRef.edgesArray.isEmpty, "createMediaReference must create at least one edge")

        // createVoiceFragment
        let voiceRef = try storage.createVoiceFragment(
            for: mem,
            audioFilename: "voice-1.caf",
            transcript: "hello world"
        )
        #expect(!voiceRef.edgesArray.isEmpty, "createVoiceFragment must create at least one edge")

        // createNoteFragment
        let noteRef = try storage.createNoteFragment(
            for: mem,
            text: "typed note"
        )
        #expect(!noteRef.edgesArray.isEmpty, "createNoteFragment must create at least one edge")

        // Every ref in the store has ≥ 1 edge — the invariant holds.
        let allRefs = try storage.viewContext.fetch(NSFetchRequest<MediaReference>(entityName: "MediaReference"))
        for ref in allRefs {
            #expect(!ref.edgesArray.isEmpty, "Ref \(ref.osIdentifier) has zero edges — temporary v1 invariant violated")
        }
    }

    /// `mediaReferencesArray` walks edges sorted by `orderInMemory`,
    /// not by `ref.createdAt`. Prove the read source is the edge.
    @Test func mediaReferencesArrayOrderedByEdgeOrderInMemory() throws {
        let storage = makeStore()
        let mem = try seedMemory(in: storage, title: "Ordered")

        // Create three refs in order. `createVoiceFragment` sets
        // `orderInMemory` from the current edge count, so insertion
        // order == chronological order for this memory.
        let refA = try storage.createVoiceFragment(for: mem, audioFilename: "a.caf", transcript: "A", createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000))
        let refB = try storage.createVoiceFragment(for: mem, audioFilename: "b.caf", transcript: "B", createdAt: Date(timeIntervalSinceReferenceDate: 800_000_100))
        let refC = try storage.createVoiceFragment(for: mem, audioFilename: "c.caf", transcript: "C", createdAt: Date(timeIntervalSinceReferenceDate: 800_000_200))

        // Now scramble the edges' orderInMemory to prove reads go
        // through the edge, not `ref.createdAt`.
        let edges = mem.edgesArray
        edges[0].orderInMemory = 2 // refA → last
        edges[1].orderInMemory = 0 // refB → first
        edges[2].orderInMemory = 1 // refC → middle
        try storage.viewContext.save()

        let arr = mem.mediaReferencesArray
        #expect(arr.count == 3)
        #expect(arr[0].id == refB.id, "orderInMemory=0 comes first")
        #expect(arr[1].id == refC.id, "orderInMemory=1 second")
        #expect(arr[2].id == refA.id, "orderInMemory=2 last")
    }

    /// `MediaReference.memoriesArray` returns all memories referencing
    /// this clip, sorted by `linkedAt` descending. Powers the
    /// "Referenced in" list on Clip Detail (Phase 7).
    @Test func memoriesArrayReflectsAllMemoriesReferencingClip() throws {
        let storage = makeStore()
        let memA = try seedMemory(in: storage, title: "First")
        let memB = try seedMemory(in: storage, title: "Second")
        let memC = try seedMemory(in: storage, title: "Third")

        let ref = try storage.createVoiceFragment(
            for: memA,
            audioFilename: "widely-cited.caf",
            transcript: "shared evidence"
        )

        // Force explicit linkedAt on all three edges so the
        // descending sort is deterministic — createVoiceFragment
        // set memA's edge to ~now, which would race with memC's
        // linkedAt.
        let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
        try StorageService.createEdge(from: memB, to: ref, linkedAt: base.addingTimeInterval(100), in: storage.viewContext)
        try StorageService.createEdge(from: memC, to: ref, linkedAt: base.addingTimeInterval(200), in: storage.viewContext)

        // Stamp memA's auto-created edge with a distinct timestamp.
        let memAEdges = try fetchEdges(memoryId: memA.id, clipId: ref.id, in: storage)
        try #require(memAEdges.first).linkedAt = base // earliest
        try storage.save(context: storage.viewContext)

        let memories = ref.memoriesArray
        #expect(memories.count == 3)
        // Descending: memC (base+200), memB (base+100), memA (base).
        #expect(memories[0].id == memC.id)
        #expect(memories[1].id == memB.id)
        #expect(memories[2].id == memA.id)
    }

    /// A ref with no `MemoryClipEdge` must NOT surface in
    /// `entry.mediaReferencesArray`. Post-Phase-4 the legacy relationship
    /// is gone, so a zero-edge ref is the only way to construct this
    /// state — the invariant is that reads walk edges, period.
    @Test func edgelessRefDoesNotSurfaceInMediaReferencesArray() throws {
        let storage = makeStore()
        let mem = try seedMemory(in: storage, title: "Orphan probe")

        // Bypass createMediaReference to plant a ref with no edges
        // (the state that would exist if a future write path forgot
        // to call `createEdge`).
        let orphan = MediaReference(context: storage.viewContext)
        orphan.id = UUID()
        orphan.osIdentifier = "orphan.caf"
        orphan.mediaType = MediaReference.MediaType.voice.rawValue
        orphan.isAccessible = true
        orphan.createdAt = Date()
        try storage.viewContext.save()

        let arr = mem.mediaReferencesArray
        #expect(arr.isEmpty, "The read path must walk edges — a ref with no edges must not appear in any memory")
    }

    /// SortBatchCommit produces one draft Memory per cluster, each
    /// with N edges linking to the cluster's clips in capturedAt order.
    /// End-to-end coverage of the ontology's Sort→commit path.
    @Test func sortBatchCommitCreatesEdgesForEachClipInCluster() throws {
        let storage = StorageService(inMemory: true)
        let vm = JournalViewModel(storage: storage, processingEngine: nil)

        let clipTimes = (0..<4).map { Date(timeIntervalSinceNow: -Double($0 * 60)) }
        let filenames = clipTimes.enumerated().map { i, _ in "sort-\(i)-\(UUID().uuidString).caf" }
        defer {
            for name in filenames {
                try? FileManager.default.removeItem(at: SpeechService.audioURL(for: name))
            }
        }

        for name in filenames {
            let url = InboxManifest.audioURL(for: name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0]).write(to: url)
        }

        let clips = zip(filenames, clipTimes).map { name, time in
            InboxClip(
                clipId: UUID(),
                capturedAt: time,
                duration: 5,
                transcript: "clip at \(time)",
                latitude: nil,
                longitude: nil,
                source: "watch",
                audioFilename: name,
                transcriptionAttempted: true,
                rollGroupId: nil
            )
        }

        let proposal = ClusterProposal(
            clipIds: clips.map(\.clipId),
            ruleTag: .timePlace,
            whyText: "4 clips · same evening",
            proposedName: "Sort test batch",
            previewLines: []
        )

        let entryIds = SortBatchCommit.commit(
            [(proposal: proposal, clips: clips)],
            viewModel: vm,
            storage: storage
        )
        #expect(entryIds.count == 1)

        let entry = try #require(vm.currentEntry(id: entryIds[0]).flatMap { model in
            try storage.viewContext.fetch({
                let r = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
                r.predicate = NSPredicate(format: "id == %@", model.id as CVarArg)
                r.fetchLimit = 1
                return r
            }()).first
        })

        let edges = entry.edgesArray
        #expect(edges.count == 4, "Cluster of 4 clips → 4 edges on the resulting memory")

        // Each edge is bound to one of our clips' audio filenames.
        let edgedFilenames = Set(edges.compactMap { $0.clip?.osIdentifier })
        #expect(edgedFilenames == Set(filenames))

        // And `ref.createdAt` on each equals the clip's capturedAt —
        // the fixup pattern is truly retired.
        for edge in edges {
            let clipTime = try #require(clips.first(where: { $0.audioFilename == edge.clip?.osIdentifier })).capturedAt
            let delta = abs((edge.clip?.createdAt ?? .distantPast).timeIntervalSince(clipTime))
            #expect(delta < 1.0, "SortBatchCommit must stamp ref.createdAt = clip.capturedAt at creation time")
        }
    }

    /// `EntryLifecycleService.joinedContent` must walk edges and
    /// respect each memory's per-edge `orderInMemory` — not `ref.createdAt`.
    /// Proves the joined-content read path is edge-driven.
    @Test func joinedContentUsesPerMemoryEdgeOrder() throws {
        let storage = makeStore()
        let mem = try seedMemory(in: storage, title: "Joined content")

        let refA = try storage.createVoiceFragment(for: mem, audioFilename: "a.caf", transcript: "aaa", createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000))
        _ = try storage.createVoiceFragment(for: mem, audioFilename: "b.caf", transcript: "bbb", createdAt: Date(timeIntervalSinceReferenceDate: 800_000_100))
        let refC = try storage.createVoiceFragment(for: mem, audioFilename: "c.caf", transcript: "ccc", createdAt: Date(timeIntervalSinceReferenceDate: 800_000_200))

        // Reverse the order: C first, A last.
        let edges = mem.edgesArray
        for edge in edges {
            switch edge.clip?.id {
            case refC.id: edge.orderInMemory = 0
            case refA.id: edge.orderInMemory = 2
            default: edge.orderInMemory = 1
            }
        }
        try storage.viewContext.save()

        let joined = EntryLifecycleService.joinedContent(from: mem)
        #expect(joined == "ccc\n\nbbb\n\naaa", "joinedContent must reflect the per-memory edge order, not ref.createdAt")
    }
}
