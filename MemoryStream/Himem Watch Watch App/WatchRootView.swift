import SwiftUI

/// Root view of the watch app. Owns the route switch (home → recording →
/// confirmation → pending list) so we don't lean on NavigationStack for
/// every transition; the watch screen is too small for stacked nav, and
/// the recording flow benefits from a clean root replacement on each
/// state change.
struct WatchRootView: View {
    @EnvironmentObject var coordinator: WatchAppCoordinator
    /// Siri "Record in HiMem" sets this via `StartVoiceRecordingIntent`.
    /// We observe it here so an intent firing during cold launch
    /// (bus flag already set before this view appears) and an intent
    /// firing while the app is foreground (flag flips after appear)
    /// both route into the recording screen.
    @ObservedObject private var captureRequests = WatchCaptureRequestBus.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .onOpenURL { url in
            handleURL(url)
        }
        .onAppear { handlePendingVoiceRecordRequest() }
        .onChange(of: captureRequests.pendingVoiceRecord) { _, pending in
            if pending { handlePendingVoiceRecordRequest() }
        }
    }

    /// Drains a Siri voice-record request by routing into the
    /// recording screen. `WatchRecordingView.onAppear` calls
    /// `recording.start()` itself, so flipping the route is enough
    /// to land in mic-hot state. Distinct from the complication path
    /// (`himem://record` → `.home`), which leaves recording to the
    /// user's explicit mic tap.
    private func handlePendingVoiceRecordRequest() {
        guard captureRequests.pendingVoiceRecord else { return }
        captureRequests.pendingVoiceRecord = false
        coordinator.route = .recording
    }

    /// Deep-link handler. Complication taps fire `himem://record` URLs
    /// (see HimemComplicationsBundle's `widgetURL`). The complication
    /// lands the user on the home page (Capture/Tap-to-Record) — it
    /// never auto-starts the recorder. Recording only begins after the
    /// user explicitly taps the mic on the capture page; that lets a
    /// stray wrist-bump open the app without committing a clip to
    /// pending.
    private func handleURL(_ url: URL) {
        guard url.scheme == "himem" else { return }
        switch url.host {
        case "record":
            coordinator.route = .home
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
