import Testing
import Foundation
import AVFoundation
@testable import HiMem

/// Money test for the bug Tom observed 2026-05-25: a watch clip
/// transferred to the phone and landed in `InboxManifest`, but the
/// inbox UI stayed stuck on "Transcribing…" forever. The clip's
/// `transcriptionAttempted` never flipped to true because the only
/// places that fired `TranscriptionService.transcribe` were
/// `ClipInboxView.onAppear` (the user wasn't on that view) and the
/// `scenePhase == .active` backstop (the app was already active).
/// Neither path runs when a clip arrives mid-foreground on the
/// session-first SessionListView.
///
/// Fix: `WatchSessionDelegate` exposes a static
/// `transcribePendingInboxClips` that the arrival path can call
/// after `acceptArrivedClip` lands the manifest row, and the
/// existing scene-active backstop now routes through the same
/// function so both paths share one implementation.
///
/// This test plants a known-good speech fixture in the inbox
/// audio directory, registers an `InboxClip` row, runs
/// `transcribePendingInboxClips`, and asserts the clip ends up
/// with `transcriptionAttempted == true` and non-empty text.
@MainActor
struct WatchClipArrivalTranscriptionTests {

    private func fixtureURL() -> URL? {
        Bundle(for: BundleAnchor.self).url(
            forResource: "long-speech-90s",
            withExtension: "caf",
            subdirectory: "Fixtures"
        ) ?? Bundle(for: BundleAnchor.self).url(
            forResource: "long-speech-90s",
            withExtension: "caf"
        )
    }

    @Test func arrivedClip_getsTranscribed_byArrivalHelper() async throws {
        guard let fixture = fixtureURL() else {
            Issue.record("Fixture long-speech-90s.caf missing")
            return
        }
        guard await SpeechAssetGate.canExerciseTranscription(
                "an arrived watch clip is transcribed by the arrival helper"
            ) else { return }

        // Plant the audio in the inbox audio directory. We use a
        // unique filename so we don't collide with real inbox rows
        // on this simulator.
        let filename = "test-watch-arrival-\(UUID().uuidString).caf"
        let destURL = InboxManifest.audioURL(for: filename)
        defer {
            // Best-effort cleanup of file + manifest row.
            try? FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: fixture, to: destURL)

        // Build a clip row matching what WatchSessionDelegate would
        // create on arrival: empty transcript, transcriptionAttempted
        // = false (the default).
        let clipId = UUID()
        let clip = InboxClip(
            clipId: clipId,
            capturedAt: Date(),
            duration: 90,
            transcript: "",
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: filename,
            transcriptionAttempted: false,
            rollGroupId: nil
        )
        InboxManifest.shared.acceptClip(clip)
        defer { InboxManifest.shared.remove(clipId: clipId) }

        // Pre-condition: row is in the manifest, untranscribed.
        let beforeRow = InboxManifest.shared.clips.first { $0.clipId == clipId }
        #expect(beforeRow != nil, "Test setup: row should be in manifest")
        #expect(beforeRow?.transcript.isEmpty == true)
        #expect(beforeRow?.transcriptionAttempted == false)

        // Money call — this is what should be wired into the
        // WatchConnectivity arrival path. If it isn't, the row
        // never transitions out of "pending".
        await WatchSessionDelegate.transcribePendingInboxClips()

        // Post-condition: the same row now has a real transcript
        // and `transcriptionAttempted == true`. The UI flips from
        // "Transcribing…" to the actual transcript line.
        let afterRow = InboxManifest.shared.clips.first { $0.clipId == clipId }
        #expect(afterRow?.transcriptionAttempted == true, "transcriptionAttempted should be true after the helper runs")
        #expect(afterRow?.transcript.isEmpty == false, "transcript should be non-empty for a known-speech fixture; got: \(afterRow?.transcript ?? "<nil>")")
    }
}

private final class BundleAnchor {}
