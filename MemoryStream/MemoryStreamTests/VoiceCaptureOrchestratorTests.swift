import Testing
import Foundation
import AVFoundation
@testable import HiMem

/// Money tests for `VoiceCaptureOrchestrator` — the save-pipeline
/// extraction from `VoiceCaptureScreen` (Step 11 of the pre-launch
/// repair pass).
///
/// The contract: the orchestrator handles the post-recording sequence
/// (compress, split, transcribe, build fragments, surface deferral
/// messages on infrastructure failures, fall back on split errors).
/// The view holds observable state (`isFinalizing`, `dismiss`,
/// `onFinish` callback); the orchestrator does the work.
///
/// Existing tests that exercise the SAME behavior through the view's
/// composer flow stay green with zero assertion changes — verified
/// after the extraction lands. New tests below pin the orchestrator
/// directly so regressions land at the smallest scope.
struct VoiceCaptureOrchestratorTests {

    // MARK: - Fixtures + helpers

    private func fixtureURL() -> URL? {
        Bundle(for: OrchestratorBundleAnchor.self).url(
            forResource: "long-speech-90s",
            withExtension: "caf",
            subdirectory: "Fixtures"
        ) ?? Bundle(for: OrchestratorBundleAnchor.self).url(
            forResource: "long-speech-90s",
            withExtension: "caf"
        )
    }

    private func copyFixtureToTemp(name: String = UUID().uuidString) throws -> URL {
        guard let fixture = fixtureURL() else {
            Issue.record("Fixture long-speech-90s.caf missing")
            return URL(fileURLWithPath: "/dev/null")
        }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name).caf")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: fixture, to: dest)
        return dest
    }

    private func fileSize(_ url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.size] as? Int) ?? 0
    }

    // MARK: - compressIfPossible

    @Test func compressIfPossible_existingFile_shrinksInPlace() async throws {
        let url = try copyFixtureToTemp(name: "compress-shrinks")
        defer { try? FileManager.default.removeItem(at: url) }
        let before = try fileSize(url)
        await VoiceCaptureOrchestrator.compressIfPossible(at: url, label: "test")
        let after = try fileSize(url)
        #expect(after > 0, "Compressed file is zero-length")
        #expect(after < before, "Compressed file should be smaller than the PCM source (\(after) vs \(before))")
    }

    @Test func compressIfPossible_missingFile_isNoOp() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("definitely-missing-\(UUID().uuidString).caf")
        // Should not throw, should not crash, should silently no-op.
        await VoiceCaptureOrchestrator.compressIfPossible(at: url, label: "missing")
        #expect(FileManager.default.fileExists(atPath: url.path) == false)
    }

    // MARK: - audioDuration

    @Test func audioDuration_validFile_returnsPositiveSeconds() throws {
        let url = try copyFixtureToTemp(name: "duration-valid")
        defer { try? FileManager.default.removeItem(at: url) }
        let duration = VoiceCaptureOrchestrator.audioDuration(at: url)
        #expect(duration > 0, "Fixture duration is \(duration); expected > 0")
    }

    @Test func audioDuration_missingFile_returnsZero() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).caf")
        let duration = VoiceCaptureOrchestrator.audioDuration(at: url)
        #expect(duration == 0)
    }

    // MARK: - Offsets sidecar

    @Test func writeOffsetsSidecar_writesParsableJSON() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sidecar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let masterPath = dir.appendingPathComponent("master.caf")
        FileManager.default.createFile(atPath: masterPath.path, contents: Data())
        // Override the audio root resolution by computing the sidecar
        // URL the same way the orchestrator does, then read it.
        let rollGroupId = UUID()
        VoiceCaptureOrchestrator.writeOffsetsSidecar(
            masterURL: masterPath,
            rollGroupId: rollGroupId,
            offsets: [3.5, 7.2]
        )
        let sidecarURL = masterPath.deletingPathExtension().appendingPathExtension("offsets.json")
        let data = try Data(contentsOf: sidecarURL)
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(payload?["rollGroupId"] as? String == rollGroupId.uuidString)
        #expect(payload?["offsets"] as? [TimeInterval] == [3.5, 7.2])
    }

    @Test func deleteOffsetsSidecarIfAny_existingFile_deletes() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sidecar-del-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let masterPath = dir.appendingPathComponent("master.caf")
        FileManager.default.createFile(atPath: masterPath.path, contents: Data())
        let sidecarURL = masterPath.deletingPathExtension().appendingPathExtension("offsets.json")
        try Data("{}".utf8).write(to: sidecarURL)
        VoiceCaptureOrchestrator.deleteOffsetsSidecarIfAny(masterURL: masterPath)
        #expect(FileManager.default.fileExists(atPath: sidecarURL.path) == false)
    }

    @Test func deleteOffsetsSidecarIfAny_missingFile_isNoOp() {
        let masterPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-sidecar-\(UUID().uuidString).caf")
        // Should not throw, should not crash.
        VoiceCaptureOrchestrator.deleteOffsetsSidecarIfAny(masterURL: masterPath)
    }

    // MARK: - runSplitAndTranscribe (iOS 26+)

    /// Single-clip session (no Next-tap offsets): the master IS the
    /// clip, no splitter runs, live transcript carries forward.
    @available(iOS 26.0, *)
    @Test func runSplitAndTranscribe_noOffsets_returnsSingleFragmentWithLiveTranscript() async throws {
        let url = try copyFixtureToTemp(name: "single-clip")
        defer { try? FileManager.default.removeItem(at: url) }
        let rollGroupId = UUID()
        let transcribeCalled = TestTranscribeCounter()
        let fragments = await VoiceCaptureOrchestrator.runSplitAndTranscribe(
            masterURL: url,
            offsets: [],
            rollGroupId: rollGroupId,
            liveTranscript: "live test transcript",
            sessionLatitude: 37.0,
            sessionLongitude: -122.0,
            transcribe: { _ in
                transcribeCalled.increment()
                return .modelNotInstalled // would never be called in single-clip path
            }
        )
        #expect(fragments.count == 1)
        #expect(fragments.first?.transcript == "live test transcript")
        #expect(fragments.first?.latitude == 37.0)
        #expect(fragments.first?.longitude == -122.0)
        #expect(transcribeCalled.count == 0, "Single-clip path should not invoke the transcriber")
    }

    /// Multi-clip session: splitter runs, transcribe closure invoked
    /// once per split, fragments carry the injected transcripts.
    @available(iOS 26.0, *)
    @Test func runSplitAndTranscribe_withOffsets_emitsFragmentPerSplitWithInjectedTranscript() async throws {
        let url = try copyFixtureToTemp(name: "multi-clip")
        defer { try? FileManager.default.removeItem(at: url) }
        let rollGroupId = UUID()
        let transcripts = ["clip-1", "clip-2", "clip-3"]
        let callCounter = TestTranscribeCounter()
        let fragments = await VoiceCaptureOrchestrator.runSplitAndTranscribe(
            masterURL: url,
            offsets: [30.0, 60.0], // 3 clips
            rollGroupId: rollGroupId,
            liveTranscript: "ignored on multi-clip path",
            sessionLatitude: nil,
            sessionLongitude: nil,
            transcribe: { _ in
                let idx = callCounter.incrementAndReturn()
                let text = idx <= transcripts.count ? transcripts[idx - 1] : "extra"
                return .transcribed(TranscriptionService.Result(
                    text: text,
                    coverageSeconds: 30,
                    fileDurationSeconds: 30,
                    segmentCount: 1
                ))
            }
        )
        #expect(fragments.count == 3, "2 offsets should produce 3 fragments")
        // Clean up split files
        for fragment in fragments {
            let splitURL = url.deletingLastPathComponent().appendingPathComponent(fragment.audioFilename)
            try? FileManager.default.removeItem(at: splitURL)
        }
        #expect(callCounter.count == 3, "Each split should invoke the transcriber once")
        let fragmentTranscripts = fragments.map(\.transcript)
        #expect(fragmentTranscripts == ["clip-1", "clip-2", "clip-3"])
    }

    /// Any clip failing transcription (model not installed, etc.)
    /// surfaces a single user-facing deferral message — the user
    /// learns the empty-transcript clips are deferred, not silent.
    @available(iOS 26.0, *)
    @MainActor
    @Test func runSplitAndTranscribe_anyClipFailsToTranscribe_surfacesDeferralAndEmptyTranscripts() async throws {
        let url = try copyFixtureToTemp(name: "deferral")
        defer { try? FileManager.default.removeItem(at: url) }
        ErrorState.shared.dismiss()
        let fragments = await VoiceCaptureOrchestrator.runSplitAndTranscribe(
            masterURL: url,
            offsets: [30.0],
            rollGroupId: UUID(),
            liveTranscript: "",
            sessionLatitude: nil,
            sessionLongitude: nil,
            transcribe: { _ in .modelNotInstalled }
        )
        // Clean up
        for fragment in fragments {
            let splitURL = url.deletingLastPathComponent().appendingPathComponent(fragment.audioFilename)
            try? FileManager.default.removeItem(at: splitURL)
        }
        #expect(fragments.allSatisfy { $0.transcript.isEmpty })
        guard case .mediaError(let message)? = ErrorState.shared.current else {
            Issue.record("Expected a .mediaError on ErrorState; got \(String(describing: ErrorState.shared.current))")
            return
        }
        #expect(message.contains("Transcription deferred"))
    }

    // MARK: - shouldDeleteMaster — 2026-06-07 voice-clip 0:00 regression

    /// Money test for Tom's QA 2026-06-07: every voice clip showed 0:00
    /// in `MediaTile` and `AudioPlayerSheet`; `Documents/VoiceEntries`
    /// was empty. Root cause: `VoiceCaptureScreen.finishOrAbandon` ran
    /// `AudioPlayerService.deleteAudio(filename: masterFilename)`
    /// unconditionally after the orchestrator returned, but the
    /// orchestrator's single-clip path returns the master itself as
    /// the fragment (`audioFilename = masterURL.lastPathComponent`).
    /// Deleting the master orphaned the persisted `MediaReference` at
    /// a phantom path. This helper encodes the "did the orchestrator
    /// reuse the master?" question so the view can ask before
    /// deleting.
    @Test func shouldDeleteMaster_singleClip_keepsMaster() {
        let master = "abc.caf"
        let fragments = [
            VoiceClipFragment(audioFilename: master, transcript: "t", duration: 1.0)
        ]
        #expect(
            VoiceCaptureOrchestrator.shouldDeleteMaster(masterFilename: master, fragments: fragments) == false,
            "single-clip path returns the master as the fragment — deleting it loses the audio"
        )
    }

    @Test func shouldDeleteMaster_splitFallback_keepsMaster() {
        let master = "abc.caf"
        // Split-fallback path also returns the master as the single
        // fragment (after `compressIfPossible` runs in-place).
        let fragments = [
            VoiceClipFragment(audioFilename: master, transcript: "t", duration: 1.0)
        ]
        #expect(
            VoiceCaptureOrchestrator.shouldDeleteMaster(masterFilename: master, fragments: fragments) == false,
            "split-fallback path also reuses the master as the fragment"
        )
    }

    @Test func shouldDeleteMaster_multiClipSplits_deletesMaster() {
        let master = "abc.caf"
        // Multi-clip success: the splitter wrote N separate files;
        // none equals the master's filename. The master is now an
        // orphan that should be cleaned up.
        let fragments = [
            VoiceClipFragment(audioFilename: "split1.caf", transcript: "t", duration: 0.5),
            VoiceClipFragment(audioFilename: "split2.caf", transcript: "t", duration: 0.5)
        ]
        #expect(
            VoiceCaptureOrchestrator.shouldDeleteMaster(masterFilename: master, fragments: fragments) == true,
            "multi-clip success path produces separate split files; the master is left orphaned and must be cleaned up"
        )
    }
}

/// Anchor for `Bundle(for:)` so the test target's resource bundle
/// (with the `Fixtures/` audio sample) is the search root.
private final class OrchestratorBundleAnchor {}

/// Mutable counter the test closures can capture by reference to
/// observe call cardinality / order. `final class` so async closures
/// see a stable reference.
private final class TestTranscribeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return _count
    }
    func increment() {
        lock.lock(); defer { lock.unlock() }
        _count += 1
    }
    func incrementAndReturn() -> Int {
        lock.lock(); defer { lock.unlock() }
        _count += 1
        return _count
    }
}
