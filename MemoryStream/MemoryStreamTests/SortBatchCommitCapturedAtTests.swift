import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money test for the Captured-Clips-import capturedAt bug Tom observed
/// 2026-07-06: a batch of watch clips captured over weeks was promoted
/// to Memories at home, and every clip's stored timestamp became the
/// import time instead of its actual recording time.
///
/// Root cause: `SortBatchCommit.commit` (and its clone in
/// `CreateMemoryFromClipsSheet.createMemory`) hands
/// `viewModel.saveEntry` a `mediaCaptures` tuple whose shape is
/// `(localIdentifier: String, mediaType: MediaReference.MediaType)` —
/// no `capturedAt` slot. `StorageService.createMediaReference` then
/// sets `ref.createdAt = Date()` unconditionally. Task #96
/// ("Voice roll clips inherit per-clip capturedAt") fixed the
/// direct-voice/on-a-roll path via the separate `voiceCapturedAt`
/// parameter, but the batch-commit path was never touched.
///
/// This is a first-principles data-integrity failure: it *destroys*
/// the moment of recording, not just hides it. No downstream feature
/// (Season aggregates, timeline scrolling, memory ordering) can ever
/// be right for these clips. And it survives the entire dogfood loop
/// silently because same-day import hides it — the QA behavior that
/// catches it is exactly the "capture now, sort later" flow the
/// product is designed to encourage.
///
/// The failing assertion: `mediaRef.createdAt` must equal
/// `clip.capturedAt`, not the import wall-clock.
@MainActor
@Suite(.serialized)
struct SortBatchCommitCapturedAtTests {

    private func makeViewModel() -> (StorageService, JournalViewModel) {
        let storage = StorageService(inMemory: true)
        let vm = JournalViewModel(storage: storage, processingEngine: nil)
        return (storage, vm)
    }

    /// Writes a few bytes to the inbox audio directory so
    /// `SortBatchCommit.commitOne`'s `moveItem(at:to:)` succeeds.
    /// The test doesn't play or transcribe the audio; only the file
    /// system move matters here.
    @discardableResult
    private func plantInboxStubFile(filename: String) throws -> URL {
        let url = InboxManifest.audioURL(for: filename)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: url)
        return url
    }

    /// Removes the file the batch-commit path moved from the inbox
    /// to the voice store, so the next test run starts clean.
    private func cleanupVoiceStore(filename: String) {
        let voiceURL = SpeechService.audioURL(for: filename)
        try? FileManager.default.removeItem(at: voiceURL)
    }

    private func fetchEntry(_ id: UUID, in storage: StorageService) -> JournalEntry? {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? storage.viewContext.fetch(request).first
    }

    /// The money assertion. If this fails, Tom's screenshot repeats —
    /// clips imported after a week land with a today-timestamp and
    /// the original moment is gone.
    @Test func sortBatchCommit_preservesClipCapturedAt_onCreatedMediaReferences() throws {
        let (storage, vm) = makeViewModel()

        // Two clips recorded at known historical moments — a real
        // "captured weeks ago" scenario. Any drift from these
        // timestamps in the resulting MediaReferences is the bug.
        let clipATime = Date(timeIntervalSinceNow: -7 * 86_400)  // 7 days ago
        let clipBTime = Date(timeIntervalSinceNow: -3 * 86_400)  // 3 days ago

        let filenameA = "test-batch-a-\(UUID().uuidString).caf"
        let filenameB = "test-batch-b-\(UUID().uuidString).caf"
        try plantInboxStubFile(filename: filenameA)
        try plantInboxStubFile(filename: filenameB)
        defer {
            cleanupVoiceStore(filename: filenameA)
            cleanupVoiceStore(filename: filenameB)
        }

        let clipA = InboxClip(
            clipId: UUID(),
            capturedAt: clipATime,
            duration: 12,
            transcript: "first",
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: filenameA,
            transcriptionAttempted: true,
            rollGroupId: nil
        )
        let clipB = InboxClip(
            clipId: UUID(),
            capturedAt: clipBTime,
            duration: 8,
            transcript: "second",
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: filenameB,
            transcriptionAttempted: true,
            rollGroupId: nil
        )

        let proposal = ClusterProposal(
            clipIds: [clipA.clipId, clipB.clipId],
            ruleTag: .timePlace,
            whyText: "test",
            proposedName: "Test cluster",
            previewLines: []
        )

        let entryIds = SortBatchCommit.commit(
            [(proposal: proposal, clips: [clipA, clipB])],
            viewModel: vm,
            storage: storage
        )
        #expect(entryIds.count == 1, "Batch commit should produce one entry for one cluster")

        let entry = try #require(fetchEntry(entryIds.first!, in: storage))
        let voiceRefs = entry.mediaReferencesArray.filter { $0.mediaTypeEnum == .voice }
        #expect(voiceRefs.count == 2, "Both clips should promote to voice MediaReferences")

        // The core assertion. Match refs to clips by osIdentifier
        // (the audio filename) and prove createdAt tracks the
        // clip's original capturedAt within a second, not the
        // import wall-clock.
        let refA = try #require(voiceRefs.first { $0.osIdentifier == filenameA })
        let refB = try #require(voiceRefs.first { $0.osIdentifier == filenameB })

        let deltaA = abs((refA.createdAt ?? .distantPast).timeIntervalSince(clipATime))
        let deltaB = abs((refB.createdAt ?? .distantPast).timeIntervalSince(clipBTime))

        #expect(
            deltaA < 1.0,
            "Ref A createdAt should match clip A capturedAt (\(clipATime)); got \(refA.createdAt ?? .distantPast), Δ=\(deltaA)s"
        )
        #expect(
            deltaB < 1.0,
            "Ref B createdAt should match clip B capturedAt (\(clipBTime)); got \(refB.createdAt ?? .distantPast), Δ=\(deltaB)s"
        )
    }
}
