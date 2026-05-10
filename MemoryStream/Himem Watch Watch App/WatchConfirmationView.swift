import SwiftUI

/// Section 3 of the watch design — the post-stop confirmation. Three
/// variants per spec: synced (auto-dismiss 2s), saved-on-watch (offline,
/// stays until user taps), storage-full (failed state).
enum WatchConfirmation: Equatable {
    case syncing(duration: TimeInterval)
    case savedOnWatch(duration: TimeInterval)
    case storageFull
}

struct WatchConfirmationView: View {
    @EnvironmentObject var coordinator: WatchAppCoordinator
    let confirmation: WatchConfirmation

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 4)
            iconView
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            if case .savedOnWatch = confirmation {
                pendingChip.padding(.top, 2)
            }
            if case .storageFull = confirmation {
                Button {
                    coordinator.route = .pendingList
                } label: {
                    Text("View pending")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.white.opacity(0.10))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .onAppear {
            if case .syncing = confirmation {
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    coordinator.route = .home
                }
            }
        }
        .onTapGesture {
            // Tap-anywhere dismiss for the offline + storage-full states.
            if case .syncing = confirmation { return }
            coordinator.route = .home
        }
    }

    private var iconView: some View {
        ZStack {
            switch confirmation {
            case .syncing:
                Circle()
                    .fill(Color(red: 31/255, green: 90/255, blue: 53/255))
                    .frame(width: 48, height: 48)
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.white)
            case .savedOnWatch:
                Circle()
                    .fill(WatchTheme.pendingAmber.opacity(0.16))
                    .frame(width: 48, height: 48)
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(WatchTheme.pendingAmber)
            case .storageFull:
                Circle()
                    .fill(WatchTheme.danger.opacity(0.16))
                    .frame(width: 44, height: 44)
                Image(systemName: "exclamationmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(WatchTheme.danger)
            }
        }
    }

    private var title: String {
        switch confirmation {
        case .syncing: return "Saved"
        case .savedOnWatch: return "Saved on Watch"
        case .storageFull: return "Watch is full"
        }
    }

    private var subtitle: String {
        switch confirmation {
        case .syncing(let d):
            return "\(formatDuration(d)) · Syncing now"
        case .savedOnWatch:
            return "Will sync when your\nphone is near"
        case .storageFull:
            return "Free space by syncing\nor open app on phone"
        }
    }

    private var pendingChip: some View {
        HStack(spacing: 4) {
            Circle().fill(WatchTheme.pendingAmber).frame(width: 5, height: 5)
            Text("Pending")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WatchTheme.pendingAmber)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(WatchTheme.pendingAmber.opacity(0.16))
        .clipShape(Capsule())
    }

    private func formatDuration(_ d: TimeInterval) -> String {
        let total = Int(d)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
