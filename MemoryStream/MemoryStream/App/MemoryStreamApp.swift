import SwiftUI
import AppIntents

@MainActor
final class QuickActionState: ObservableObject {
    static let shared = QuickActionState()
    @Published var pendingAction: String?
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let shortcutItem = options.shortcutItem {
            Task { @MainActor in
                QuickActionState.shared.pendingAction = shortcutItem.type
            }
        }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor in
            QuickActionState.shared.pendingAction = shortcutItem.type
        }
        completionHandler(true)
    }
}

@main
struct MemoryStreamApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let storageService = StorageService.shared

    init() {
        TopicPaletteStore.shared.loadFromCoreData()
        HiMemShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            JournalView()
                .environment(\.managedObjectContext, storageService.viewContext)
                .environmentObject(QuickActionState.shared)
                .preferredColorScheme(.light)
        }
    }
}
