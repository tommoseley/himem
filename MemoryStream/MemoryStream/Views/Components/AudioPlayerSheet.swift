import SwiftUI
import AVFoundation

/// Sheet-presented audio player + transcript editor for a voice clip.
/// Built on top of the shared `EditTextSheet` template so the chrome
/// (grabber, Cancel · title · Done bar, metadata line, ochre-ring
/// field) matches the photo description editor exactly — per
/// `docs/design/HiMem · Edit Sheet.html` June 2026. The two editors do
/// the same job (edit the words on a media item) and read as siblings.
///
/// The hero block houses the audio player (scrubber + play / pause).
/// The footer slot houses *Retry transcription*. Everything else is
/// shared chrome.
///
/// **Three media states** (per `docs/design/Storage architecture · CLAUDE.md`
/// Rule 4 — be honest in UX) drive what the hero shows:
/// - `.ready`: file is downloaded, normal player UI.
/// - `.downloading`: file is in iCloud but not yet local. Spinner +
///   "Downloading from iCloud" label replaces the play button. Polls
///   every 1s until ready, missing, or the poll ceiling.
/// - `.missing`: file is neither local nor in iCloud (deleted by the
///   user via Files.app, never made it to iCloud, or download
///   timed out). Honest "Original audio is not available" label; the
///   transcript editor still surfaces the memory itself.
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
    /// Number of `.downloading` polls without a state change. Once this
    /// exceeds `downloadPollCeiling` we give up and treat the file as
    /// `.missing` — catches the case where iCloud Drive has metadata
    /// for a path but the bytes were never uploaded.
    @State private var downloadPollCount = 0
    @State private var draftTranscript: String = ""
    @State private var isRetryingTranscription = false
    /// Surfaces the outcome of a retry that didn't overwrite the draft —
    /// either a failure (model not installed, transcriber threw) or a
    /// genuine empty success. Cleared on the next user edit or after a
    /// short delay so it doesn't linger.
    @State private var retryStatusMessage: String? = nil

    private let downloadPollCeiling = 10  // 10 polls at 1s = ~10 seconds

    enum MediaState: Equatable {
        case checking
        case downloading
        case ready
        case missing
    }

    var body: some View {
        EditTextSheet(
            title: "Voice clip",
            metadata: metadataLine,
            fieldLabel: "Transcript",
            text: $draftTranscript,
            onCancel: { dismiss() },
            onDone: {
                commitIfChanged()
                dismiss()
            },
            hero: { hero },
            footer: { footer }
        )
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

    // MARK: - Metadata line

    private var metadataLine: String {
        var parts: [String] = []
        if let recordedAt {
            parts.append(Self.timestampFormatter.string(from: recordedAt))
        }
        switch mediaState {
        case .ready where totalDuration > 0:
            parts.append(formatTime(totalDuration))
        case .downloading, .checking:
            parts.append("…")
        case .missing:
            parts.append("—")
        case .ready:
            break
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Hero (state-driven)

    @ViewBuilder
    private var hero: some View {
        switch mediaState {
        case .checking:
            heroChecking
        case .downloading:
            heroDownloading
        case .ready:
            heroReady
        case .missing:
            heroMissing
        }
    }

    private var heroChecking: some View {
        HStack {
            Spacer()
            ProgressView().controlSize(.small)
            Spacer()
        }
        .frame(height: 92)
    }

    private var heroDownloading: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Downloading from iCloud")
                .font(.subheadline)
                .foregroundStyle(Crucible.Color.ink2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 92)
        .accessibilityLabel("Downloading audio from iCloud")
    }

    private var heroMissing: some View {
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

    /// Scrubber + current time | play button | total time. Matches the
    /// design's hero for the transcript editor.
    private var heroReady: some View {
        VStack(spacing: 12) {
            ProgressView(value: progress)
                .tint(Crucible.Color.Media.audio)
            HStack {
                Text(formatTime(currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Crucible.Color.ink3)
                Spacer()
                Button { togglePlay() } label: {
                    Image(systemName: isPlayingThisClip ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Crucible.Color.accent)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlayingThisClip ? "Pause" : "Play")
                Spacer()
                Text(formatTime(totalDuration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Crucible.Color.ink3)
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Inline link per `HiMem · Buttons & Actions §2`: blue,
            // no border, no pill, ≥44pt tap target. "Retry
            // transcription" is the canonical mockup example in
            // the standard. The leading arrow glyph stays as the
            // verb-icon; AI sparkle is reserved for the quiet AI
            // status label above the footer, not for this link.
            Button(action: retryTranscription) {
                if isRetryingTranscription {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Retrying…")
                            .font(.system(size: 13, weight: .semibold))
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Retry transcription")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
            }
            .foregroundStyle(Crucible.Color.aiBlue)
            .frame(minHeight: 44, alignment: .leading)
            .buttonStyle(.plain)
            .disabled(isRetryingTranscription)

            // Honest-label retry status. Shown ONLY when a retry
            // landed on `.keepDraft` (failure or empty recognition);
            // an auto-clear in `applyRetryOutcome` removes it after
            // a few seconds so it doesn't linger.
            if let message = retryStatusMessage {
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Crucible.Color.ink3)
                    .accessibilityLabel(message)
            }
        }
    }

    /// Re-runs `TranscriptionService` against this clip's audio file. On
    /// success with non-empty text, replaces the draft. On any failure
    /// or genuine empty result, keeps the draft and surfaces a short
    /// status message — the user's typed words are protected from
    /// recognizer failure modes.
    @available(iOS 26.0, *)
    private func retryTranscription() {
        isRetryingTranscription = true
        retryStatusMessage = nil
        Task {
            let url = SpeechService.audioURL(for: filename)
            let outcome = await TranscriptionService.shared.transcribe(audioURL: url)
            await MainActor.run {
                applyRetryOutcome(outcome)
                isRetryingTranscription = false
            }
        }
    }

    /// MainActor side of `retryTranscription` — separated so the
    /// outcome handling can be exercised without standing up a
    /// SpeechAnalyzer pipeline. Pairs with the pure
    /// `decideRetryAction` decision function for testability.
    @available(iOS 26.0, *)
    private func applyRetryOutcome(_ outcome: TranscriptionService.Outcome) {
        switch Self.decideRetryAction(outcome: outcome) {
        case .overwriteDraft(let newText):
            draftTranscript = newText
            retryStatusMessage = nil
        case .keepDraft(let reason):
            retryStatusMessage = reason
            // Auto-clear the status line after a few seconds so it
            // doesn't linger. The draft itself stays untouched.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if retryStatusMessage == reason {
                    retryStatusMessage = nil
                }
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
    /// state resolves to `.ready`, `.missing`, or the poll counter
    /// exceeds `downloadPollCeiling` — the latter catches paths that
    /// iCloud knows about but never received bytes for.
    private func startDownloadPolling(url: URL) {
        downloadPollTimer?.invalidate()
        downloadPollCount = 0
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
                    downloadPollCount += 1
                    if downloadPollCount >= downloadPollCeiling {
                        timer.invalidate()
                        NSLog("[HiMem][AudioPlayerSheet] download timeout for \(filename) — falling back to .missing after \(downloadPollCount) polls")
                        mediaState = .missing
                    }
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

    // MARK: - Retry decision (pure, testable)

    /// Outcome of `decideRetryAction(outcome:)` — separates the
    /// destination-changing case (overwrite the user's draft) from
    /// the preserve-draft case (failure or recognizer-said-silence).
    enum RetryAction: Equatable {
        case overwriteDraft(String)
        case keepDraft(reason: String)
    }

    /// Decides what to do with the retry outcome. Extracted as a
    /// static pure function so the test suite can exercise every
    /// outcome variant without standing up a SpeechAnalyzer pipeline.
    ///
    /// Contract:
    /// - `.transcribed` with non-empty (post-trim) text → overwrite.
    /// - `.transcribed` with empty / whitespace text → keep draft.
    ///   Genuine silence is a definitive recognizer answer, but the
    ///   user's typed words are probably better than the silence
    ///   verdict; let them decide whether to clear it themselves.
    /// - Any failure variant (`modelNotInstalled`, `fileUnreadable`,
    ///   `transcriberFailed`) → keep draft. The pre-2026-06-07
    ///   regression here was that `outcome.textOrEmpty` returned
    ///   `""` for these and silently wiped the draft.
    @available(iOS 26.0, *)
    static func decideRetryAction(outcome: TranscriptionService.Outcome) -> RetryAction {
        if case .transcribed(let result) = outcome {
            let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return .overwriteDraft(result.text)
            }
            return .keepDraft(reason: "Retry returned no speech — kept your text")
        }
        return .keepDraft(reason: "Couldn't retranscribe — kept your text")
    }
}
