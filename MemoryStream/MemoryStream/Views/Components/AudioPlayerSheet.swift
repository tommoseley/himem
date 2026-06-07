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
///
/// **Three media states** (per `docs/design/Storage architecture · CLAUDE.md`
/// Rule 4 — be honest in UX):
/// - `.ready`: file is downloaded, normal player UI.
/// - `.downloading`: file is in iCloud but not yet local. Spinner +
///   "Downloading from iCloud" label replaces the play button. Polls
///   every 1s until ready or missing.
/// - `.missing`: file is neither local nor in iCloud (deleted by the
///   user via Files.app, or never made it to iCloud). Honest
///   "Original audio is not available" label; transcript editor still
///   surfaces the memory itself.
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
    @State private var mediaState: MediaState = .checking
    @State private var totalDuration: TimeInterval = 0
    @State private var currentTime: TimeInterval = 0
    @State private var tickTimer: Timer?
    @State private var downloadPollTimer: Timer?
    @State private var draftTranscript: String = ""
    @State private var isRetryingTranscription = false

    enum MediaState: Equatable {
        case checking
        case downloading
        case ready
        case missing
    }

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
            await resolveMediaState()
            startTicking()
        }
        .onDisappear {
            tickTimer?.invalidate()
            tickTimer = nil
            downloadPollTimer?.invalidate()
            downloadPollTimer = nil
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

    @ViewBuilder
    private var playerControls: some View {
        switch mediaState {
        case .checking:
            checkingControls
        case .downloading:
            downloadingControls
        case .ready:
            readyControls
        case .missing:
            missingControls
        }
    }

    private var checkingControls: some View {
        HStack {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Spacer()
        }
        .frame(height: 80)
    }

    private var downloadingControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Downloading from iCloud")
                    .font(.subheadline)
                    .foregroundStyle(Crucible.Color.ink2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
        }
        .accessibilityLabel("Downloading audio from iCloud")
    }

    private var missingControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "icloud.slash")
                    .foregroundStyle(Crucible.Color.ink3)
                Text("Original audio is not available")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Crucible.Color.ink2)
            }
            Text("The transcript below is the saved memory. The original recording isn't on this device or in your iCloud.")
                .font(.caption)
                .foregroundStyle(Crucible.Color.ink3)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .accessibilityLabel("Original audio is not available; transcript is the saved memory")
    }

    private var readyControls: some View {
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
            .disabled(isRetryingTranscription || mediaState != .ready)
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
        switch mediaState {
        case .ready:
            return formatTime(totalDuration)
        case .downloading, .checking:
            return "…"
        case .missing:
            return "—"
        }
    }

    private func togglePlay() {
        guard mediaState == .ready else { return }
        if isPlayingThisClip {
            player.stop()
        } else {
            player.play(filename: filename)
        }
    }

    // MARK: - Media-state resolution

    /// Reads the ubiquity download status and either kicks off a
    /// download (and starts polling) or loads the duration directly.
    /// Called from `.task` on appear.
    private func resolveMediaState() async {
        let url = SpeechService.audioURL(for: filename)
        let status = UbiquityStore.shared.downloadStatus(at: url)
        switch status {
        case .downloaded:
            await loadReady(url: url)
        case .notDownloaded:
            UbiquityStore.shared.startDownload(at: url)
            mediaState = .downloading
            startDownloadPolling(url: url)
        case .downloading:
            mediaState = .downloading
            startDownloadPolling(url: url)
        case .missing:
            mediaState = .missing
        }
    }

    private func loadReady(url: URL) async {
        let asset = AVURLAsset(url: url)
        if let cm = try? await asset.load(.duration), cm.seconds.isFinite {
            totalDuration = cm.seconds
        }
        mediaState = .ready
    }

    /// Polls the download status every 1s. Cancels itself when the
    /// state resolves to `.ready` or `.missing`. The view's
    /// `.onDisappear` invalidates the timer if the user closes the
    /// sheet during download.
    private func startDownloadPolling(url: URL) {
        downloadPollTimer?.invalidate()
        downloadPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            Task { @MainActor in
                let status = UbiquityStore.shared.downloadStatus(at: url)
                switch status {
                case .downloaded:
                    timer.invalidate()
                    await loadReady(url: url)
                case .missing:
                    timer.invalidate()
                    mediaState = .missing
                case .downloading, .notDownloaded:
                    // Keep polling.
                    break
                }
            }
        }
    }

    // MARK: - Time tracking

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
