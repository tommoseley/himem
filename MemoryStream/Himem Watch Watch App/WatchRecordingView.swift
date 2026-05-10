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
    @State private var pulseScale: CGFloat = 1.0
    @State private var didAutoStart = false

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 4)

            ZStack {
                // Pulsing ring
                Circle()
                    .fill(WatchTheme.accent.opacity(0.18))
                    .frame(width: 110, height: 110)
                    .scaleEffect(pulseScale)
                Circle()
                    .fill(WatchTheme.accent.opacity(0.08))
                    .frame(width: 130, height: 130)
                    .scaleEffect(pulseScale)
                Circle()
                    .fill(WatchTheme.accent)
                    .frame(width: 86, height: 86)
                Image(systemName: "mic.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    pulseScale = 1.18
                }
            }

            Text(timeString)
                .font(.system(size: 13, weight: .regular).monospacedDigit())
                .foregroundStyle(Color.white)
                .tracking(1)

            HStack(spacing: 6) {
                Button {
                    stopAndSave()
                } label: {
                    Text("Stop & save")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(WatchTheme.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    cancel()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.14))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)

            Spacer(minLength: 0)
        }
        .onAppear {
            if !didAutoStart {
                didAutoStart = true
                Task { await recording.start() }
            }
        }
        .onDisappear {
            // Belt-and-braces — if the user navigates away without using
            // Stop & save or Cancel (e.g., wrist drop), auto-save.
            if recording.isRecording {
                _ = recording.stop(save: true)
            }
        }
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

    private func cancel() {
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
