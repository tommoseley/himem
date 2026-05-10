import SwiftUI
import AVFoundation

/// Section 4F — quick playback peek when the user taps a row in the
/// pending list. Renders a bare waveform glyph + position counter +
/// pause/delete buttons. Audio routes to AirPods if connected, watch
/// speaker otherwise (system handles the routing).
struct WatchPlaybackPeekView: View {
    let clip: WatchPendingClip
    let onClose: () -> Void
    let onDelete: () -> Void

    @State private var player: AVAudioPlayer?
    @State private var positionLabel: String = "0:00 / 0:00"
    @State private var ticker: Timer?

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 4)

            Spacer(minLength: 4)

            // Static waveform glyph — design uses a fake bar pattern;
            // real-time peak meter on watch would be overkill.
            HStack(spacing: 2) {
                ForEach(0..<20, id: \.self) { i in
                    Capsule()
                        .fill(WatchTheme.accent)
                        .frame(width: 2, height: barHeight(at: i))
                }
            }

            Text(positionLabel)
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(.white)

            HStack(spacing: 14) {
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: player?.isPlaying == true ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.10))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WatchTheme.danger)
                        .frame(width: 34, height: 34)
                        .background(WatchTheme.danger.opacity(0.16))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .onAppear { setupPlayer() }
        .onDisappear { teardownPlayer() }
    }

    // Static waveform pattern — same look as the design.
    private func barHeight(at index: Int) -> CGFloat {
        let pattern: [CGFloat] = [6, 11, 14, 8, 13, 6, 9, 14, 11, 7, 12, 9, 5, 11, 14, 8, 6, 10, 13, 7]
        return pattern[index % pattern.count]
    }

    private func setupPlayer() {
        let url = WatchPendingManifest.audioURL(for: clip.audioFilename)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            player = p
            updatePositionLabel()
        } catch {
            // Playback init failed — leave the view in a "no playback" state.
        }
    }

    private func teardownPlayer() {
        ticker?.invalidate()
        ticker = nil
        player?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func togglePlayback() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            ticker?.invalidate()
            ticker = nil
        } else {
            player.play()
            ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
                updatePositionLabel()
            }
        }
    }

    private func updatePositionLabel() {
        guard let player else { return }
        let pos = Int(player.currentTime)
        let total = Int(player.duration)
        positionLabel = String(format: "%d:%02d / %d:%02d", pos / 60, pos % 60, total / 60, total % 60)
    }
}
