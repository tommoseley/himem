import SwiftUI
import AVFoundation

/// Sheet-presented audio player + transcript editor. Tap a voice tile in
/// an entry's media grid to open this sheet; play the clip via
/// AudioPlayerService.shared (existing inline waveforms update too) and
/// edit the transcript inline.
///
/// The transcript area is the edit control. Cancel discards changes;
/// Done saves the (trimmed) text via `onSaveTranscript` if it differs
/// from the initial value.
struct AudioPlayerSheet: View {
    let filename: String
    let recordedAt: Date?
    /// Transcript to seed the editor with. Pass the per-clip transcript
    /// stored on MediaReference for new captures; for legacy voice refs
    /// that predate the per-clip transcript field, pass `entry.content`.
    let initialTranscript: String
    /// Persists the edited transcript. Called on Done if the trimmed text
    /// differs from `initialTranscript`. Skipped on Cancel and on Done
    /// with no changes.
    let onSaveTranscript: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var totalDuration: TimeInterval = 0
    @State private var currentTime: TimeInterval = 0
    @State private var tickTimer: Timer?
    @State private var draftTranscript: String = ""
    @State private var isRetryingTranscription = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                header
                playerControls
                Divider()
                transcriptEditor
            }
            .padding(20)
            .background(Crucible.Color.paper)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Crucible.Color.ink2)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        commitIfChanged()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Crucible.Color.accent)
                }
            }
            .navigationTitle("Voice clip")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            draftTranscript = initialTranscript
            await loadDuration()
            startTicking()
        }
        .onDisappear {
            tickTimer?.invalidate()
            tickTimer = nil
            // If this clip is what's playing, stop it on dismiss so the
            // user isn't surprised by audio continuing without a UI.
            if player.currentFile == filename {
                player.stop()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let recordedAt {
                Text(Self.timestampFormatter.string(from: recordedAt))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Crucible.Color.ink2)
            }
            Text(durationLabel)
                .font(.system(size: 28, weight: .semibold).monospacedDigit())
                .foregroundStyle(Crucible.Color.ink)
        }
    }

    // MARK: - Player controls

    private var playerControls: some View {
        VStack(spacing: 12) {
            ProgressView(value: progress)
                .tint(Crucible.Color.Media.audio)

            HStack {
                Text(formatTime(currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Crucible.Color.ink3)
                Spacer()
                Button { togglePlay() } label: {
                    Image(systemName: isPlayingThisClip ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Crucible.Color.Media.audio)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlayingThisClip ? "Pause" : "Play")
                Spacer()
                Text(formatTime(totalDuration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Crucible.Color.ink3)
            }
        }
    }

    // MARK: - Transcript editor

    private var transcriptEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TRANSCRIPT")
                .font(.caption2.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(Crucible.Color.ink3)

            TextEditor(text: $draftTranscript)
                .font(.callout)
                .foregroundStyle(Crucible.Color.ink)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .background(Crucible.Color.paper)

            Button {
                retryTranscription()
            } label: {
                if isRetryingTranscription {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Retrying…")
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry transcription")
                    }
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Crucible.Color.accent)
            .buttonStyle(.plain)
            .disabled(isRetryingTranscription)
            .padding(.top, 2)
        }
    }

    /// Re-runs `TranscriptionService` against this clip's audio file and
    /// replaces the draft transcript with the result. The user can still
    /// edit the result before tapping Done, or hit Cancel to revert
    /// everything (including the retry) and keep the original transcript.
    private func retryTranscription() {
        isRetryingTranscription = true
        Task {
            let url = SpeechService.audioURL(for: filename)
            // `.textOrEmpty` preserves the pre-2026-05-29 behavior
            // here: manual retry that hits a transient failure
            // (model not ready) silently clears the draft. Known
            // follow-up: show an inline error so the user knows
            // it didn't actually run. Out of scope for hero fix.
            let outcome = await TranscriptionService.shared.transcribe(audioURL: url)
            await MainActor.run {
                draftTranscript = outcome.textOrEmpty
                isRetryingTranscription = false
            }
        }
    }

    // MARK: - Save

    private func commitIfChanged() {
        let trimmed = draftTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = initialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != original else { return }
        onSaveTranscript(trimmed)
    }

    // MARK: - Playback state

    private var isPlayingThisClip: Bool {
        player.isPlaying && player.currentFile == filename
    }

    private var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return min(1.0, max(0.0, currentTime / totalDuration))
    }

    private var durationLabel: String {
        formatTime(totalDuration)
    }

    private func togglePlay() {
        if isPlayingThisClip {
            player.stop()
        } else {
            player.play(filename: filename)
        }
    }

    // MARK: - Time tracking

    private func loadDuration() async {
        // 2026-06-06 diagnostic: Tom reported every voice clip showing
        // 0:00 + no playback. Format-mismatch hypothesis ruled out by
        // AudioCompressorTests.compressInPlace_AVURLAssetCanReadDuration.
        // These NSLogs surface the actual failure mode on device so the
        // money test can target it. Revert when fixed.
        let url = SpeechService.audioURL(for: filename)
        let exists = FileManager.default.fileExists(atPath: url.path)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? -1
        let asset = AVURLAsset(url: url)
        do {
            let cm = try await asset.load(.duration)
            let seconds = cm.seconds
            NSLog("[HiMem][AudioPlayerSheet] loadDuration filename=\(filename) exists=\(exists) size=\(size) duration=\(seconds) isFinite=\(seconds.isFinite)")
            if seconds.isFinite {
                totalDuration = seconds
            }
        } catch {
            NSLog("[HiMem][AudioPlayerSheet] loadDuration FAILED filename=\(filename) exists=\(exists) size=\(size) error=\(error.localizedDescription)")
        }
    }

    /// AudioPlayerService doesn't expose a currentTime stream, so we tick a
    /// timer at 4Hz and ask the underlying player. Cheap; this view is on
    /// screen briefly.
    private func startTicking() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            Task { @MainActor in
                if player.isPlaying && player.currentFile == filename,
                   let avPlayer = AudioPlayerService.shared.currentAVPlayer {
                    currentTime = avPlayer.currentTime
                } else if !player.isPlaying {
                    // Reset to 0 when not playing this clip.
                    currentTime = 0
                }
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let m = max(0, total) / 60
        let s = max(0, total) % 60
        return String(format: "%d:%02d", m, s)
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
