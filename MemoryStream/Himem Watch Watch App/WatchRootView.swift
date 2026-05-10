import SwiftUI

/// Root view of the watch app. Owns the route switch (home → recording →
/// confirmation → pending list) so we don't lean on NavigationStack for
/// every transition; the watch screen is too small for stacked nav, and
/// the recording flow benefits from a clean root replacement on each
/// state change.
struct WatchRootView: View {
    @EnvironmentObject var coordinator: WatchAppCoordinator

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .onOpenURL { url in
            handleURL(url)
        }
    }

    /// Deep-link handler. Complication taps fire `himem://record` URLs
    /// (see HimemComplicationsBundle's `widgetURL`). The user's tap
    /// behavior setting decides whether we land on the recording screen
    /// ready to tap mic, or fire recording immediately.
    private func handleURL(_ url: URL) {
        guard url.scheme == "himem" else { return }
        switch url.host {
        case "record":
            switch WatchSharedState.tapBehavior {
            case .openReadyToRecord:
                coordinator.route = .recording
            case .pressAndHoldToRecord:
                coordinator.route = .recording
                Task { await coordinator.recording.start() }
            }
        case "pending":
            coordinator.route = .pendingList
        default:
            coordinator.route = .home
        }
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.route {
        case .home:
            WatchHomeView(pending: coordinator.pending)
        case .recording:
            WatchRecordingView(recording: coordinator.recording)
        case .confirmation(let confirmation):
            WatchConfirmationView(confirmation: confirmation)
        case .pendingList:
            WatchPendingListView(pending: coordinator.pending)
        }
    }
}
