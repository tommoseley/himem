import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money test for the "Start a Memory from N voice clips" path used by
/// `CreateMemoryFromClipsSheet.createMemory()`.
///
/// **The invariant this locks in** — from `HiMem · Locked Decisions.html`
/// § Ontology:
///
/// - **Audio is the source of truth; transcripts are derivative.** A
///   transcript must never be reified as its own clip. Creating a memory
///   from N voice clips leaves exactly N clips — the N voice fragments.
///   No synthesized `.note` MediaReference materialising the joined
///   transcript alongside the voice originals.
///
/// **The defect this reproduces** — dogfood 2026-07-13, Tom's report:
/// starting a memory from a 2-voice-clip session yielded a memory with
/// **three** clips, the third being a `.note` whose text was the
/// concatenation of the two voice transcripts.
///
/// **Root cause chain**:
/// 1. `CreateMemoryFromClipsSheet` sets `entry.content = joinedTranscript`
///    using the clips' **raw** transcripts.
/// 2. It then creates each voice fragment via
///    `StorageService.createVoiceFragment`, which stores
///    `JournalEntry.cleanedTranscript(transcript)` — leading ASR noise
///    (`.`, `,`, `…`, whitespace) stripped. Realistic ASR output almost
///    always carries such noise.
/// 3. `entry.content` (raw) is no longer byte-equal to
///    `EntryLifecycleService.joinedContent(from: entry)` (cleaned +
///    trimmed).
/// 4. `EntryExpandedView.onAppear` calls
///    `EntryLifecycleService.migrateOrphanedContentIfNeeded(entryId:)`.
/// 5. Its equality guard fails; it mints a `.note` MediaReference to
///    "preserve" the orphaned text. Third clip appears in Memory Detail.
///
/// The single-clip `save(voiceFilename:)` path reconciles
/// `entry.content` immediately after minting the voice fragment (`save`
/// line ~425). The multi-clip create-from-sheet path skips that
/// reconcile because it passes `voiceFilename: nil` and creates its
/// fragments after `save` returns. **This test locks the reconcile
/// into the multi-clip path.**
@MainActor
@Suite(.serialized)
struct CreateMemoryFromClipsAssemblyTests {

    // MARK: - Setup (mirrors EntryLifecycleServiceAppendClipsTests)

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

    // MARK: - Money test

    /// Reproduces the 2026-07-13 dogfood defect **and** locks it out.
    ///
    /// Uses one transcript with a leading period + space ("​. first
    /// capture") — a common Apple SpeechAnalyzer artefact and the
    /// specific class `JournalEntry.cleanedTranscript` was written to
    /// strip. The raw joined text (which the sheet writes to
    /// `entry.content`) and the fragments' cleaned transcripts differ,
    /// which is what trips the orphan-content mint.
    @Test func createMemoryFromNVoiceClips_yieldsExactlyNClips_zeroSynthesizedNotes() throws {
        let (storage, service) = makeService()

        let t0 = Date()
        let clips: [(audioFilename: String, transcript: String, capturedAt: Date)] = [
            ("clip-a.caf", ". first capture", t0),
            ("clip-b.caf", "second capture", t0.addingTimeInterval(10)),
        ]

        let newId = try #require(
            service.createMemoryFromVoiceClips(clips, topicName: nil)
        )

        // Simulate detail-view onAppear — the site where the synthesized
        // note materialised in dogfood.
        service.migrateOrphanedContentIfNeeded(entryId: newId)

        let refreshed = try #require(fetchEntry(newId, in: storage))
        let refs = refreshed.mediaReferencesArray
        let voiceRefs = refs.filter { $0.mediaTypeEnum == .voice }
        let noteRefs = refs.filter { $0.mediaTypeEnum == .note }

        #expect(
            voiceRefs.count == 2,
            "expected 2 voice fragments — one per source clip"
        )
        #expect(
            noteRefs.isEmpty,
            "expected 0 synthesized notes — audio is the source of truth; the joined transcript must not be reified as a separate clip"
        )
        #expect(
            refs.count == 2,
            "N voice clips must yield exactly N clips in the memory; no synthesis"
        )
    }

    /// Chronological ordering, mirrored from the append-clips guarantee
    /// — the sheet sorts by `capturedAt` before minting voice fragments
    /// so the ordering matches capture time regardless of how the caller
    /// supplies the list.
    @Test func createMemoryFromVoiceClips_ordersFragmentsByCapturedAt() throws {
        let (storage, service) = makeService()

        let t0 = Date()
        // Out of order — the primitive must sort.
        let clips: [(audioFilename: String, transcript: String, capturedAt: Date)] = [
            ("clip-c.caf", "third", t0.addingTimeInterval(20)),
            ("clip-a.caf", "first", t0),
            ("clip-b.caf", "second", t0.addingTimeInterval(10)),
        ]

        let newId = try #require(
            service.createMemoryFromVoiceClips(clips, topicName: nil)
        )

        let refreshed = try #require(fetchEntry(newId, in: storage))
        let byTime = refreshed.mediaReferencesArray
            .filter { $0.mediaTypeEnum == .voice }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        #expect(byTime.map { $0.osIdentifier } == ["clip-a.caf", "clip-b.caf", "clip-c.caf"])
    }
}
