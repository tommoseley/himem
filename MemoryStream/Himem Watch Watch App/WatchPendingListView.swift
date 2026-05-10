import SwiftUI

/// Section 4 of the watch design — list of locally-stored, unsynced
/// recordings. Empty state, populated state, swipe-to-delete with
/// confirmation, tap-row → playback peek. Crown scrolls.
struct WatchPendingListView: View {
    @EnvironmentObject var coordinator: WatchAppCoordinator
    /// Observed directly so the list re-renders when clips arrive or get
    /// confirmed-and-removed.
    @ObservedObject var pending: WatchPendingManifest
    @State private var clipPendingDelete: WatchPendingClip?
    @State private var clipForPlayback: WatchPendingClip?

    var body: some View {
        Group {
            if let clip = clipPendingDelete {
                WatchDeleteConfirmView(clip: clip) {
                    pending.userDelete(clipId: clip.clipId)
                    clipPendingDelete = nil
                } onCancel: {
                    clipPendingDelete = nil
                }
            } else if let clip = clipForPlayback {
                WatchPlaybackPeekView(clip: clip,
                                     onClose: { clipForPlayback = nil },
                                     onDelete: {
                                         clipForPlayback = nil
                                         clipPendingDelete = clip
                                     })
            } else {
                listBody
            }
        }
    }

    @ViewBuilder
    private var listBody: some View {
        if pending.isEmpty {
            emptyState
        } else {
            populatedList
        }
    }

    private var header: some View {
        HStack {
            Text("PENDING")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.55))
            if !pending.isEmpty {
                Text("· \(pending.count)")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            Spacer()
            Button {
                coordinator.route = .home
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            header
            Spacer()
            ZStack {
                Circle()
                    .fill(WatchTheme.syncedGreen.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(WatchTheme.syncedGreen)
            }
            Text("All caught up")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
            Text("Recordings appear here\nwhen phone isn't near.")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            Spacer()
        }
    }

    private var populatedList: some View {
        VStack(spacing: 0) {
            header
                .padding(.bottom, 4)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(pending.clips) { clip in
                        rowView(for: clip)
                    }
                    Text("Will sync when phone is near")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .padding(.top, 6)
                }
            }
        }
    }

    private func rowView(for clip: WatchPendingClip) -> some View {
        Button {
            clipForPlayback = clip
        } label: {
            HStack(spacing: 8) {
                Circle().fill(WatchTheme.accent).frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(timeLabel(for: clip.capturedAt))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Saved on watch")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                Spacer(minLength: 4)
                Text(durationLabel(clip.duration))
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                clipPendingDelete = clip
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Formatters

    private func timeLabel(for date: Date) -> String {
        let cal = Calendar.current
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "h:mm a"
        let timePart = timeFmt.string(from: date)
        if cal.isDateInToday(date) { return "\(timePart) · today" }
        if cal.isDateInYesterday(date) { return "\(timePart) · yesterday" }
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "MMM d"
        return "\(timePart) · \(dayFmt.string(from: date))"
    }

    private func durationLabel(_ d: TimeInterval) -> String {
        String(format: "%d:%02d", Int(d) / 60, Int(d) % 60)
    }
}
