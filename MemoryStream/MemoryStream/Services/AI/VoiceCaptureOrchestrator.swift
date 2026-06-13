import Foundation
import AVFoundation

/// Save-pipeline orchestration for the phone voice composer.
///
/// Extracted from `VoiceCaptureScreen` in the pre-launch repair pass
/// 2026-06-01 (Step 11). The view had grown to 930+ lines with the
/// split / compress / transcribe loop and the offsets-sidecar I/O
/// tangled into the SwiftUI body alongside breath animation and
/// waveform rendering. Pulling the file-and-pipeline work out into
/// statics here:
///
/// - keeps the view a presentation layer (state + layout + gestures);
/// - makes the orchestration testable without standing up
///   `VoiceCaptureScreen` (see `VoiceCaptureOrchestratorTests`);
/// - matches the dependency-injection seam shape from Step 6
///   (`ProcessingEngine.consumeAssist`) — `runSplitAndTranscribe`
///   accepts a `transcribe:` closure with a `TranscriptionService`
///   default so tests can substitute stubbed outcomes without
///   hitting the live SpeechAnalyzer model.
///
/// Per `CLAUDE.md` "no speculative abstractions": these are the
/// pieces that were already tangled. The view's UI helpers
/// (`sampleAt`, `barHeight`, `runBreath`, etc.) are pure SwiftUI
/// concerns and stay in the view.
enum VoiceCaptureOrchestrator {

    // MARK: - Save pipeline

    /// Build the final `[VoiceClipFragment]` for the session.
    ///
    /// Single-clip path (`offsets.isEmpty`): master IS the clip,
    /// compressed in place, live transcript carries forward — no
    /// splitter, no per-clip retranscription.
    ///
    /// Multi-clip path: splitter runs, each split is compressed
    /// then transcribed via the injected `transcribe` closure. If
    /// any clip's outcome is a deferred infrastructure failure
    /// (model not installed, file unreadable, transcriber threw),
    /// a single user-facing deferral toast surfaces after the
    /// loop — empty-transcript clips are honest about being
    /// deferred, not silent.
    ///
    /// Split error (the `catch` arm): falls back to the master as
    /// a single fragment with the live transcript, surfaces an
    /// `.mediaError` so the user knows the multi-clip session
    /// collapsed.
    /// Pure helper: maps a roll's recording-start wall-clock and the
    /// user's Next-tap offsets to one `capturedAt` per resulting clip.
    /// `offsets.count == 0` → one clip at `start`. `offsets.count == N`
    /// → `N+1` clips: clip 1 starts at `start`, clip k+1 at
    /// `start + offsets[k-1]`. Caller is responsible for ordering
    /// offsets (NextClipController appends in tap order).
    ///
    /// Extracted so the timestamp logic — the load-bearing piece for
    /// fixing the "all roll clips show the same time" bug — is testable
    /// without touching disk or the splitter. Money tests in
    /// `VoiceCaptureCapturedAtTests`.
    static func capturedAtSequence(start: Date, offsets: [TimeInterval]) -> [Date] {
        var result: [Date] = [start]
        result.append(contentsOf: offsets.map { start.addingTimeInterval($0) })
        return result
    }

    @available(iOS 26.0, *)
    static func runSplitAndTranscribe(
        masterURL: URL,
        offsets: [TimeInterval],
        rollGroupId: UUID,
        liveTranscript: String,
        recordingStartedAt: Date,
        sessionLatitude: Double?,
        sessionLongitude: Double?,
        transcribe: @Sendable (URL) async -> TranscriptionService.Outcome = { url in
            await TranscriptionService.shared.transcribe(audioURL: url)
        }
    ) async -> [VoiceClipFragment] {
        let lat = sessionLatitude
        let lon = sessionLongitude
        let capturedAts = capturedAtSequence(start: recordingStartedAt, offsets: offsets)

        if offsets.isEmpty {
            await compressIfPossible(at: masterURL, label: "phone single-clip master")
            let duration = audioDuration(at: masterURL)
            return [VoiceClipFragment(
                audioFilename: masterURL.lastPathComponent,
                transcript: liveTranscript,
                duration: duration,
                capturedAt: capturedAts[0],
                latitude: lat,
                longitude: lon
            )]
        }

        do {
            let outputDir = masterURL.deletingLastPathComponent()
            let splits = try await VoiceClipSplitter.split(
                masterURL: masterURL,
                nextTapOffsets: offsets,
                outputDir: outputDir,
                rollGroupId: rollGroupId
            )
            var fragments: [VoiceClipFragment] = []
            // Track whether any clip's transcription deferred due to
            // an infrastructure failure. The save path can't retry —
            // user is foreground, recording is over — so surface a
            // single user-facing message after the loop. Each split
            // with a deferral lands with `outcome.textOrEmpty` (empty);
            // the toast tells the user the empty-ness is a deferral,
            // not genuine silence.
            var transcriptionDeferred = false
            for (idx, split) in splits.enumerated() {
                let url = SpeechService.audioURL(for: split.audioFilename)
                // Compress each split before transcribing — saves
                // disk, and SpeechAnalyzer reads AAC fine.
                await compressIfPossible(at: url, label: "phone split \(split.audioFilename)")
                let outcome = await transcribe(url)
                if outcome.userFacingDeferralMessage != nil {
                    transcriptionDeferred = true
                }
                // Defensive clamp: if the splitter ever emits more
                // pieces than our capturedAtSequence accounted for
                // (shouldn't happen — splits.count == offsets.count + 1),
                // fall back to the last computed timestamp rather than
                // crash on an out-of-range read.
                let capturedAt = idx < capturedAts.count ? capturedAts[idx] : capturedAts.last ?? recordingStartedAt
                fragments.append(VoiceClipFragment(
                    audioFilename: split.audioFilename,
                    transcript: outcome.textOrEmpty,
                    duration: split.duration,
                    capturedAt: capturedAt,
                    latitude: lat,
                    longitude: lon
                ))
            }
            if transcriptionDeferred,
               let message = TranscriptionService.Outcome.modelNotInstalled.userFacingDeferralMessage {
                await MainActor.run {
                    ErrorState.shared.report(.mediaError(message))
                }
            }
            return fragments
        } catch {
            await MainActor.run {
                ErrorState.shared.report(.mediaError("Voice clip split failed: \(error.localizedDescription)"))
            }
            // Split failed — surface the unsplit master as one fragment.
            // Compress it so the fallback isn't penalized by size either.
            await compressIfPossible(at: masterURL, label: "phone split-fallback master")
            let duration = audioDuration(at: masterURL)
            return [VoiceClipFragment(
                audioFilename: masterURL.lastPathComponent,
                transcript: liveTranscript,
                duration: duration,
                capturedAt: recordingStartedAt,
                latitude: lat,
                longitude: lon
            )]
        }
    }

    /// Fallback path for pre-iOS-26 callers (the project's mixed
    /// deployment targets include iOS 17). Runs the splitter so
    /// per-clip files exist on disk, but doesn't transcribe — every
    /// fragment lands with an empty transcript. On the dominant
    /// (iOS 26+) path callers should use `runSplitAndTranscribe`.
    static func runSplitWithoutTranscription(
        masterURL: URL,
        offsets: [TimeInterval],
        rollGroupId: UUID,
        liveTranscript: String,
        recordingStartedAt: Date,
        sessionLatitude: Double?,
        sessionLongitude: Double?
    ) async -> [VoiceClipFragment] {
        let capturedAts = capturedAtSequence(start: recordingStartedAt, offsets: offsets)
        if offsets.isEmpty {
            await compressIfPossible(at: masterURL, label: "phone single-clip master (no transcribe)")
            let duration = audioDuration(at: masterURL)
            return [VoiceClipFragment(
                audioFilename: masterURL.lastPathComponent,
                transcript: liveTranscript,
                duration: duration,
                capturedAt: capturedAts[0],
                latitude: sessionLatitude,
                longitude: sessionLongitude
            )]
        }
        do {
            let outputDir = masterURL.deletingLastPathComponent()
            let splits = try await VoiceClipSplitter.split(
                masterURL: masterURL,
                nextTapOffsets: offsets,
                outputDir: outputDir,
                rollGroupId: rollGroupId
            )
            return splits.enumerated().map { idx, split in
                let capturedAt = idx < capturedAts.count ? capturedAts[idx] : capturedAts.last ?? recordingStartedAt
                return VoiceClipFragment(
                    audioFilename: split.audioFilename,
                    transcript: "",
                    duration: split.duration,
                    capturedAt: capturedAt,
                    latitude: sessionLatitude,
                    longitude: sessionLongitude
                )
            }
        } catch {
            await MainActor.run {
                ErrorState.shared.report(.mediaError("Voice clip split failed: \(error.localizedDescription)"))
            }
            await compressIfPossible(at: masterURL, label: "phone split-fallback master (no transcribe)")
            let duration = audioDuration(at: masterURL)
            return [VoiceClipFragment(
                audioFilename: masterURL.lastPathComponent,
                transcript: liveTranscript,
                duration: duration,
                capturedAt: recordingStartedAt,
                latitude: sessionLatitude,
                longitude: sessionLongitude
            )]
        }
    }

    // MARK: - File / I/O helpers

    /// Compress a finalized audio file in place to AAC. Failure is
    /// logged and swallowed — losing the size win is better than
    /// losing the clip. Mirrors `WatchSessionDelegate
    /// .compressIfPossible`.
    static func compressIfPossible(at url: URL, label: String) async {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let before = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        do {
            try await AudioCompressor.compressInPlace(at: url)
            let after = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            let ratio = before > 0 && after > 0 ? Double(before) / Double(after) : 0
            NSLog("[HiMem][Compress] \(label): \(before)→\(after) bytes (\(String(format: "%.1fx", ratio)))")
        } catch {
            NSLog("[HiMem][Compress] failed for \(label): \(error.localizedDescription) — keeping raw PCM")
        }
    }

    /// Returns the duration in seconds of the audio file at `url`,
    /// or 0 if the file is missing / unreadable.
    static func audioDuration(at url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let sampleRate = file.processingFormat.sampleRate
        return TimeInterval(file.length) / sampleRate
    }

    /// Crash-safety sidecar — JSON file `<sessionId>.offsets.json`
    /// next to the master audio file. Recovery on relaunch: if both
    /// master file and sidecar exist for an in-progress session, the
    /// orchestrator can run the split + transcribe pass and surface
    /// the clips. (Recovery wiring is forward-looking; this method
    /// writes the sidecar.)
    static func writeOffsetsSidecar(
        masterURL: URL,
        rollGroupId: UUID?,
        offsets: [TimeInterval]
    ) {
        let sidecarURL = masterURL.deletingPathExtension().appendingPathExtension("offsets.json")
        let payload: [String: Any] = [
            "rollGroupId": rollGroupId?.uuidString ?? "",
            "offsets": offsets
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: []) {
            try? data.write(to: sidecarURL, options: [.atomic])
        }
    }

    /// Deletes the offsets sidecar (if present) for the given master
    /// audio file. Called from the save and discard branches of the
    /// composer's `finishOrAbandon` so a successful or canceled
    /// session doesn't leave a stale sidecar behind.
    static func deleteOffsetsSidecarIfAny(masterURL: URL) {
        let sidecarURL = masterURL.deletingPathExtension().appendingPathExtension("offsets.json")
        try? FileManager.default.removeItem(at: sidecarURL)
    }

    /// True iff the master audio file at `masterFilename` is safe to
    /// delete given the returned fragments. The single-clip path and
    /// the split-fallback path both reuse the master as the fragment
    /// file (compressed in place); a fragment whose `audioFilename`
    /// equals `masterFilename` means the master IS the persisted
    /// audio. Deleting it would orphan the `MediaReference`
    /// downstream, producing the 2026-06-07 "voice clip shows 0:00 +
    /// won't play" regression.
    static func shouldDeleteMaster(masterFilename: String, fragments: [VoiceClipFragment]) -> Bool {
        !fragments.contains { $0.audioFilename == masterFilename }
    }
}
