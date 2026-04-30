import SwiftUI
import AppIntents

@MainActor
final class QuickActionState: ObservableObject {
    static let shared = QuickActionState()
    @Published var pendingAction: String?
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        completionHandler(.newData)
    }

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
    @State private var splashComplete = false
    @AppStorage("lastBackgrounded") private var lastBackgrounded: Double = 0

    init() {
        TopicPaletteStore.shared.loadFromCoreData()
        HiMemShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                JournalView()
                    .environment(\.managedObjectContext, storageService.viewContext)
                    .environmentObject(QuickActionState.shared)
                    .opacity(splashComplete ? 1 : 0)

                if !splashComplete {
                    LaunchScreenView {
                        splashComplete = true
                    }
                    .transition(.opacity)
                }
            }
            .preferredColorScheme(.light)
            .onAppear {
                // Warm start: skip splash if backgrounded < 60s ago
                let elapsed = Date().timeIntervalSince1970 - lastBackgrounded
                if lastBackgrounded > 0 && elapsed < 60 {
                    splashComplete = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                lastBackgrounded = Date().timeIntervalSince1970
            }
        }
    }
}
