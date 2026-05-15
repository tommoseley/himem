import SwiftUI
import WatchConnectivity

/// Section 2 V1 of the watch design — pulsing ochre mic disc, monospace
/// timer, side-by-side Cancel + Stop & save buttons. Auto-starts
/// recording on appear.
struct WatchRecordingView: View {
    @EnvironmentObject var coordinator: WatchAppCoordinator
    /// Observed directly so `elapsed` ticks update the timer label every
    /// 500ms. Accessing `coordinator.recording` would only re-render when
    /// the coordinator itself publishes — `@Published` changes on the
    /// nested service don't cascade.
    @ObservedObject var recording: WatchRecordingService
    @State private var didAutoStart = false
    @State private var showDiscardConfirm = false

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 14)
            meterRing
            Text(timeString)
                .font(.system(size: 13, weight: .regular).monospacedDigit())
                .foregroundStyle(Color.white)
                .tracking(1)
            // Stop & save is the primary, full-width minus the quiet ✕.
            // The ✕ is a small (38pt) secondary chip — destructive but
            // visually quieted (card background + hairline stroke, no
            // fill, no peer weight). The "Peer actions" rule from the
            // design system forbids destructive actions sitting beside
            // primary as equal-weight peers; this keeps Stop & save as
            // the unambiguous primary.
            HStack(spacing: 6) {
                Button {
                    stopAndSave()
                } label: {
                    Text("Stop & save")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(WatchTheme.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    // Skip the confirm in two no-content cases:
                    //   1. Under a second of audio — almost always an
                    //      accidental quick-tap, not worth a modal.
                    //   2. No real audio captured (peak level never
                    //      crossed the speech floor) — recording was
                    //      effectively silence even if elapsed time is
                    //      long, e.g. wrist down for 30s with no
                    //      conversation. Threshold 0.1 ≈ -50 dB, which
                    //      sits below typical room tone and well below
                    //      speech level (0.4–0.7).
                    // Anything else gets the explicit confirm.
                    if recording.elapsed < 1.0 || recording.peakAudioLevel < 0.1 {
                        discard()
                    } else {
                        showDiscardConfirm = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.10))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Discard recording")
            }
            // Wider horizontal inset clears the watch case's rounded
            // corners — the right-edge ✕ otherwise gets visibly clipped
            // on Ultra-class hardware where the screen curves at the
            // corners.
            .padding(.horizontal, 14)
            Spacer(minLength: 0)
        }
        // Bottom padding lifts the button row off the bottom-corner
        // curve. Without it the row hugs the screen edge and clips on
        // the actual device even though the simulator looks fine.
        .padding(.bottom, 14)
        .onAppear {
            if !didAutoStart {
                didAutoStart = true
                Task { await recording.start() }
            }
        }
        .onDisappear {
            // Belt-and-braces — if the user navigates away without using
            // Stop & save or the discard confirm (e.g., wrist drop),
            // auto-save.
            if recording.isRecording {
                _ = recording.stop(save: true)
            }
        }
        .alert("Discard recording?", isPresented: $showDiscardConfirm) {
            Button("Discard", role: .destructive) { discard() }
            Button("Keep recording", role: .cancel) {}
        } message: {
            Text("This audio won't be saved.")
        }
    }

    /// The recording disc with two outer rings that pulse from mic input.
    /// Replaces the prior decorative pulse — when the watch is "hearing"
    /// you, the outer ring breathes with the audio level so the user has
    /// real confidence the mic is hot.
    private var meterRing: some View {
        // Baseline pulse so a quiet room still looks alive; level adds
        // amplitude on top. Linear interpolation keeps the motion gentle
        // — the AVAudioRecorder meters can be jumpy.
        let level = recording.audioLevel
        let outerScale: CGFloat = 1.0 + 0.18 * level
        let middleScale: CGFloat = 1.0 + 0.10 * level
        return ZStack {
            Circle()
                .fill(WatchTheme.accent.opacity(0.08 + 0.10 * Double(level)))
                .frame(width: 130, height: 130)
                .scaleEffect(outerScale)
            Circle()
                .fill(WatchTheme.accent.opacity(0.18 + 0.08 * Double(level)))
                .frame(width: 110, height: 110)
                .scaleEffect(middleScale)
            Circle()
                .fill(WatchTheme.accent)
                .frame(width: 86, height: 86)
            Image(systemName: "mic.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.white)
        }
        .animation(.easeOut(duration: 0.12), value: level)
    }

    private var timeString: String {
        let total = Int(recording.elapsed)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func stopAndSave() {
        guard let clip = recording.stop(save: true) else {
            coordinator.route = .home
            return
        }
        coordinator.transfer.send(clip: clip)
        // Confirmation state — online vs offline detected by WCSession.
        let isReachable = WCSessionReachable.isReachable
        let isStorageFull = coordinator.pending.isAtCap
        let confirmation: WatchConfirmation
        if isStorageFull {
            confirmation = .storageFull
        } else if isReachable {
            confirmation = .syncing(duration: clip.duration)
        } else {
            confirmation = .savedOnWatch(duration: clip.duration)
        }
        coordinator.route = .confirmation(confirmation)
    }

    private func discard() {
        _ = recording.stop(save: false)
        coordinator.route = .home
    }
}

/// Tiny indirection so the view can read iPhone reachability inline.
enum WCSessionReachable {
    static var isReachable: Bool {
        guard WCSession.isSupported() else { return false }
        return WCSession.default.isReachable
    }
}
