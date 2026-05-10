import SwiftUI

/// Section 6 of the watch design — single screen, big mic + conditional
/// pending count below. Tap mic → recording. Tap pending area → list.
struct WatchHomeView: View {
    @EnvironmentObject var coordinator: WatchAppCoordinator
    /// Observed directly so the pending count updates when the manifest
    /// changes (e.g., iPhone confirms a clip and the row is removed).
    @ObservedObject var pending: WatchPendingManifest

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text("HI MEM")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)

            Spacer(minLength: 0)

            Button {
                coordinator.route = .recording
            } label: {
                ZStack {
                    Circle()
                        .fill(WatchTheme.accent)
                        .frame(width: 96, height: 96)
                        .shadow(color: WatchTheme.accent.opacity(0.18), radius: 12, x: 0, y: 0)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Record")
            .accessibilityHint("Tap to start a voice recording.")

            Text("Tap to record")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.6))

            Divider()
                .frame(height: 1)
                .background(Color.white.opacity(0.10))
                .padding(.horizontal, 12)

            pendingRow

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var pendingRow: some View {
        let count = pending.count
        Button {
            if count > 0 {
                coordinator.route = .pendingList
            }
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: 5) {
                    Text("Pending")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.7))
                    Text("·")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.4))
                    Text("\(count)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(count > 0 ? WatchTheme.pendingAmber : Color.white)
                }
                if count > 0 {
                    Text("Tap to view")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
    }
}
