import SwiftUI

/// Single-modality voice capture, presented when the user picks the Voice
/// pill from the Append FAB. Records via SpeechService, shows the live
/// transcript, finishes with the audio filename + transcript.
///
/// On Done the host appends/saves the result. On Cancel the host discards.
struct VoiceCaptureScreen: View {
    /// Fired when the user finishes a recording. Empty filename or transcript
    /// is possible if the user hits Done before saying anything; the host
    /// decides whether to drop or persist a degenerate capture.
    let onFinish: (_ audioFilename: String?, _ transcript: String) -> Void
    let onCancel: () -> Void

    @ObservedObject var speechService: SpeechService
    @Environment(\.dismiss) private var dismiss
    @State private var startedAt: Date? = nil
    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer? = nil
    @State private var didAutoStart = false
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                transcriptArea
                Spacer(minLength: 0)
                recordButton
                Text(timerLabel)
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Crucible.Color.ink3)
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Crucible.Color.paper)
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        finishOrAbandon(saveResult: false)
                    }
                    .foregroundStyle(Crucible.Color.ink2)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        finishOrAbandon(saveResult: true)
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Crucible.Color.accent)
                }
            }
        }
        .onAppear {
            // Auto-start recording on first appearance — the user picked
            // Voice; they want to talk, not tap a second button.
            if !didAutoStart {
                didAutoStart = true
                startRecording()
            }
        }
        .onDisappear {
            stopTimer()
            // Belt-and-braces: if the host dismisses us without going
            // through Cancel/Done (rare), don't leave the recorder running.
            if speechService.isRecording {
                speechService.stopRecording()
            }
        }
        .onChange(of: speechService.isRecording) { _, recording in
            if recording {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    pulseScale = 1.18
                }
            } else {
                withAnimation(.easeInOut(duration: 0.3)) {
                    pulseScale = 1.0
                }
            }
        }
    }

    // MARK: - Subviews

    private var transcriptArea: some View {
        ScrollView {
            Text(speechService.transcribedText.isEmpty
                 ? "Listening…"
                 : speechService.transcribedText)
                .font(.system(size: 22))
                .foregroundStyle(speechService.transcribedText.isEmpty ? Crucible.Color.ink4 : Crucible.Color.ink)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .frame(minHeight: 180)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Watch-style record button: solid ochre mic disc, pulsing
    /// concentric rings while recording, mic.fill / stop.fill icon morph
    /// so a single tap stays unambiguous (mic = start, stop = stop).
    private var recordButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            if speechService.isRecording {
                speechService.stopRecording()
                stopTimer()
            } else {
                startRecording()
            }
        } label: {
            ZStack {
                if speechService.isRecording {
                    Circle()
                        .fill(Crucible.Color.accent.opacity(0.18))
                        .frame(width: 130, height: 130)
                        .scaleEffect(pulseScale)
                    Circle()
                        .fill(Crucible.Color.accent.opacity(0.08))
                        .frame(width: 160, height: 160)
                        .scaleEffect(pulseScale)
                }
                Circle()
                    .fill(Crucible.Color.accent)
                    .frame(width: 100, height: 100)
                    .shadow(color: Crucible.Color.accent.opacity(0.32), radius: 16, x: 0, y: 4)
                Image(systemName: speechService.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(speechService.isRecording ? "Stop recording" : "Start recording")
    }

    // MARK: - Timer / lifecycle

    private var timerLabel: String {
        let total = Int(elapsed)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func startRecording() {
        speechService.startRecording()
        startedAt = Date()
        elapsed = 0
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            if let s = startedAt { elapsed = Date().timeIntervalSince(s) }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func finishOrAbandon(saveResult: Bool) {
        if speechService.isRecording {
            speechService.stopRecording()
        }
        stopTimer()
        if saveResult {
            onFinish(speechService.lastRecordingPath, speechService.transcribedText)
        } else {
            // Discard the audio file from disk so we don't leak abandoned
            // recordings into the app sandbox.
            if let path = speechService.lastRecordingPath {
                AudioPlayerService.deleteAudio(filename: path)
            }
            onCancel()
        }
        dismiss()
    }
}
