import SwiftUI

@main
struct Himem_Watch_Watch_AppApp: App {
    /// Single shared instance so navigation, recording state, and the
    /// pending list survive across screens. Lives for the lifetime of the
    /// watch app process.
    @StateObject private var coordinator = WatchAppCoordinator()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(coordinator)
        }
    }
}
