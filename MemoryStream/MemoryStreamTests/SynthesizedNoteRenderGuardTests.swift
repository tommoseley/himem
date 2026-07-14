import Testing
import Foundation
import CoreData
@testable import HiMem

/// P3 (Option A) money tests — render-side fail-safe against the
/// synthesized-note defect class (`Handoff · carry-forward punch list ·
/// 2026-07-14`).
///
/// `077de8c` cured the three *current* write paths that assemble voice
/// fragments and reconcile `entry.content` to the joined transcript. But
/// the defect recurs the instant any *future* path assembles voice
/// fragments without that reconcile: voice fragments store **cleaned**
/// transcripts (`StorageService.createVoiceFragment` →
/// `JournalEntry.cleanedTranscript`), so `joinedContent(from:)` is the
/// *cleaned* join; a path that leaves `entry.content` as the **raw** join
/// is byte-unequal to it, the exact `content == joined` guard misses, and
/// `migrateOrphanedContentIfNeeded` mints a `.note` duplicating the
/// audio's own transcripts.
///
/// Option A (the narrow fix Tom chose over a blanket "any voice → skip",
/// which would have regressed
/// `EntryLifecycleServiceTests.migrateOrphanedContentIfNeeded_legacyVoiceOnly_mintsNoteForOrphanedContent`):
/// recognize `entry.content` as the joined transcripts under the *same*
/// per-segment ASR-noise normalization used at ingest — closing the
/// raw↔cleaned drift **without** suppressing a genuinely-orphaned typed
/// body.
///
/// Serialized — exercises Core Data through the shared storage stack.
@MainActor
@Suite(.serialized)
struct SynthesizedNoteRenderGuardTests {

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

    // MARK: - The fail-safe

    /// The money test. A memory whose voice fragments hold **cleaned**
    /// transcripts but whose `entry.content` drifted to the **raw** join
    /// (leading ASR noise intact) must NOT synthesize a duplicate `.note`
    /// — even though `content != joinedContent(from:)` byte-wise. This is
    /// the `077de8c` defect class reproduced for a *future* write path
    /// that forgets the reconcile; the render seam must fail safe.
    @Test func migrate_voiceFragmentsWithRawJoinedContent_doesNotSynthesizeNote() throws {
        let (storage, service) = makeService()

        let t0 = Date()
        let newId = try #require(
            service.createMemoryFromVoiceClips(
                [
                    ("a.caf", ". first capture", t0),               // leading ASR noise
                    ("b.caf", "second capture", t0.addingTimeInterval(10)),
                ],
                topicName: nil
            )
        )

        // Simulate a FUTURE write path that leaves `entry.content` as the
        // RAW join (the reconcile `077de8c` added is absent), while the
        // fragments store cleaned transcripts.
        let entry = try #require(fetchEntry(newId, in: storage))
        entry.content = ". first capture\n\nsecond capture"
        try storage.viewContext.save()

        service.migrateOrphanedContentIfNeeded(entryId: newId)

        let refs = try #require(fetchEntry(newId, in: storage)).mediaReferencesArray
        #expect(
            refs.filter { $0.mediaTypeEnum == .voice }.count == 2,
            "the two source voice fragments must survive"
        )
        #expect(
            refs.filter { $0.mediaTypeEnum == .note }.isEmpty,
            "render-side fail-safe must not reify the raw joined transcript as a duplicate note"
        )
    }

    // MARK: - The guard rail (Option A must not over-suppress)

    /// The reason we rejected the blanket "any voice → skip" rule: a
    /// GENUINELY orphaned typed body alongside a voice clip is real user
    /// content and must STILL be promoted to a `.note`. It never reduces
    /// to the transcripts under normalization, so Option A leaves it
    /// alone. Mirrors — and must stay consistent with —
    /// `EntryLifecycleServiceTests.migrateOrphanedContentIfNeeded_legacyVoiceOnly_mintsNoteForOrphanedContent`.
    @Test func migrate_voiceWithGenuinelyOrphanedTypedBody_stillMints() throws {
        let (storage, service) = makeService()

        let entry = try service.createEmptyEntry(inputType: .composed)
        let voice = try storage.createMediaReference(for: entry, localIdentifier: "v.caf", mediaType: .voice)
        voice.transcript = "voice words"
        entry.content = "a totally separate typed thought"
        try storage.viewContext.save()

        service.migrateOrphanedContentIfNeeded(entryId: entry.id)

        let noteRefs = entry.mediaReferencesArray.filter { $0.mediaTypeEnum == .note }
        #expect(noteRefs.count == 1)
        #expect(noteRefs.first?.text == "a totally separate typed thought")
    }
}
