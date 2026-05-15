import SwiftUI

/// Section 4 of the watch design — list of locally-stored, unsynced
/// recordings. Empty state, populated state, swipe-to-delete with
/// confirmation, tap-row → playback peek. Crown scrolls.
struct WatchPendingListView: View {
    @EnvironmentObject var coordinator: WatchAppCoordinator
    /// Observed directly so the list re-renders when clips arrive or get
    /// confirmed-and-removed.
    @ObservedObject var pending: WatchPendingManifest
    /// When embedded inside the home TabView, swipe-back replaces the
    /// chevron — render the header without it. Deep-link entry points
    /// (e.g., `himem://pending`) pass `false` so the explicit back affordance
    /// stays.
    var embedded: Bool = false
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

    /// Inline header for the deep-link route only — `PENDING · <count>`
    /// with a back chevron. Suppressed in the embedded swipe-page
    /// context: there the shared `HIMEM · PENDING` header is provided by
    /// the `EmbeddedHeaderModifier` via `safeAreaInset`.
    @ViewBuilder
    private var header: some View {
        if !embedded {
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
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            header
            Spacer()
            ZStack {
                Circle()
                    .fill(WatchTheme.syncedGreen.opacity(0.14))
                    .frame(width: 28, height: 28)
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(WatchTheme.syncedGreen)
            }
            .transition(.scale(scale: 0.6).combined(with: .opacity))
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
        .padding(.bottom, embedded ? 22 : 0)
    }

    private var populatedList: some View {
        VStack(spacing: 0) {
            header
                .padding(.bottom, 4)
            // List (not LazyVStack) so `.swipeActions(edge: .trailing)`
            // works. watchOS swipe-to-reveal-delete is List-row-only;
            // LazyVStack rows ignore the modifier silently.
            List {
                ForEach(pending.clips) { clip in
                    rowView(for: clip)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                }
                Text("Will sync when phone is near")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    .padding(.bottom, embedded ? 18 : 0)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .animation(.easeOut(duration: 0.3), value: pending.clips.map(\.clipId))
            .animation(.easeOut(duration: 0.3), value: pending.syncingClipIds)
        }
    }

    private func rowView(for clip: WatchPendingClip) -> some View {
        let isSyncing = pending.syncingClipIds.contains(clip.clipId)
        return Button {
            clipForPlayback = clip
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(isSyncing ? WatchTheme.syncedGreen : WatchTheme.accent)
                    .frame(width: 6, height: 6)
                if isSyncing {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .heavy))
                        Text("Synced")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(WatchTheme.syncedGreen)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(timeLabel(for: clip.capturedAt))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 4)
                    Text(durationLabel(clip.duration))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .transition(
            .asymmetric(
                insertion: .opacity,
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
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
