import SwiftUI

@main
struct Himem_Watch_Watch_AppApp: App {
    /// Single shared instance so navigation, recording state, and the
    /// pending list survive across screens. Lives for the lifetime of the
    /// watch app process.
    @StateObject private var coordinator = WatchAppCoordinator()

    /// Observed so we can re-kick the pending-transfer queue when the
    /// user raises wrist into HiMem after a long disconnect. Without
    /// this, the only retry triggers are app init (one-shot at cold
    /// launch) and `sessionReachabilityDidChange` (which iOS may not
    /// fire if reachability never visibly flipped). Money 2026-06-18:
    /// matches the symptom Tom saw — paired watch reports unreachable
    /// after a BT wedge, queue stuck until next cold launch.
    @Environment(\.scenePhase) private var scenePhase

    /// Stamps which binary this is at launch — the watch's only guard against
    /// reading a device pass off a stale install. See `WatchBuildStamp`.
    init() {
        WatchBuildStamp.log()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(coordinator)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            NSLog("[HiMem][WC] watch — scenePhase=.active, re-kicking pending transfers")
            Task { await coordinator.retryPendingTransfers() }
        }
    }
}
