import Testing
import Foundation
@testable import HiMem

/// Money test for the 2026-05-27 "every recording merges into one
/// session" bug. The phone-side transcription completes for each
/// arrived clip and calls `InboxManifest.recordTranscriptionAttempt`,
/// which rebuilt the `InboxClip` row. Before this fix the rebuild
/// omitted the `rollGroupId:` parameter, leaving it at its default
/// nil — silently stripping the on-a-roll session signal from every
/// transcribed clip.
///
/// Downstream `ClipSessionGrouper` then fell back to its time +
/// location heuristic and merged unrelated recordings together (Tom
/// recorded 4 separate Record→Stop cycles → got one session card
/// with 7 clips).
///
/// Contract: `rollGroupId` survives a transcription update unchanged.
@MainActor
struct InboxManifestTranscriptionPreservesRollGroupIdTests {

    @Test func recordTranscriptionAttempt_preservesRollGroupId() {
        let manifest = InboxManifest.shared
        // Snapshot existing inbox so the test can restore it.
        let snapshot = manifest.clips
        defer {
            for clip in manifest.clips where !snapshot.contains(where: { $0.clipId == clip.clipId }) {
                manifest.remove(clipId: clip.clipId)
            }
        }

        let rollGroupId = UUID()
        let clip = InboxClip(
            clipId: UUID(),
            capturedAt: Date(),
            duration: 4.0,
            transcript: "",
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: "test-\(UUID().uuidString).caf",
            transcriptionAttempted: false,
            rollGroupId: rollGroupId
        )
        manifest.acceptClip(clip)

        manifest.recordTranscriptionAttempt(
            clipId: clip.clipId,
            transcript: "transcribed text"
        )

        guard let updated = manifest.clips.first(where: { $0.clipId == clip.clipId }) else {
            Issue.record("Clip missing from manifest after transcription update")
            return
        }
        #expect(updated.transcript == "transcribed text")
        #expect(updated.transcriptionAttempted == true)
        // The load-bearing assertion: the on-a-roll session signal
        // survives the transcription update. Before the fix this was
        // nil; after the fix it equals the original rollGroupId.
        #expect(updated.rollGroupId == rollGroupId)
    }

    @Test func recordTranscriptionAttempt_preservesNilRollGroupId() {
        // Pre-on-a-roll clips have nil rollGroupId. Transcription
        // shouldn't synthesize one — nil stays nil.
        let manifest = InboxManifest.shared
        let snapshot = manifest.clips
        defer {
            for clip in manifest.clips where !snapshot.contains(where: { $0.clipId == clip.clipId }) {
                manifest.remove(clipId: clip.clipId)
            }
        }

        let clip = InboxClip(
            clipId: UUID(),
            capturedAt: Date(),
            duration: 4.0,
            transcript: "",
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: "test-\(UUID().uuidString).caf",
            transcriptionAttempted: false,
            rollGroupId: nil
        )
        manifest.acceptClip(clip)

        manifest.recordTranscriptionAttempt(
            clipId: clip.clipId,
            transcript: "some text"
        )

        let updated = manifest.clips.first(where: { $0.clipId == clip.clipId })
        #expect(updated?.rollGroupId == nil)
    }
}
