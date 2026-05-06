import SwiftUI
import AppIntents
import Combine

@MainActor
final class QuickActionState: ObservableObject {
    static let shared = QuickActionState()
    @Published var pendingAction: String?
}

/// Process-global orientation lock. The CameraPickerView flips this on
/// while the picker is mounted so the AppDelegate's
/// `supportedInterfaceOrientationsFor` returns `.portrait` and iOS rotates
/// the picker to portrait regardless of device orientation. Without this,
/// SwiftUI's `.fullScreenCover` host overrides any
/// `supportedInterfaceOrientations` the picker view controller declares
/// for itself, leaving us with the broken landscape camera viewport.
final class OrientationLock {
    static let shared = OrientationLock()
    /// Set to true while a screen wants to clamp the device to portrait.
    /// Read by `AppDelegate.application(_:supportedInterfaceOrientationsFor:)`.
    var portraitOnly: Bool = false
    private init() {}
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        completionHandler(.newData)
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.shared.portraitOnly ? .portrait : .allButUpsideDown
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

@MainActor
private final class ConnectivityReprocessor {
    static let shared = ConnectivityReprocessor()
    private var cancellable: AnyCancellable?

    func start() {
        guard cancellable == nil else { return }
        cancellable = ConnectivityMonitor.shared.$isConnected
            .removeDuplicates()
            .dropFirst() // skip the initial value; only act on real transitions
            .filter { $0 } // only when connectivity returns
            .sink { _ in
                Task { await ProcessingEngine.shared.reprocessLocallyHandledEntries() }
            }
    }
}

@main
struct MemoryStreamApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var auth = AuthService.shared
    @State private var splashComplete = false
    @State private var storageReady = false
    @State private var onboardingComplete = false

    init() {
        DispatchQueue.main.async {
            HiMemShortcuts.updateAppShortcutParameters()
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if storageReady && onboardingComplete {
                    JournalView()
                        .environment(\.managedObjectContext, StorageService.shared.viewContext)
                        .environmentObject(QuickActionState.shared)
                }

                if !splashComplete {
                    LaunchScreenView(onStorageReady: {
                        storageReady = true
                        // Check if onboarding was already completed
                        if auth.hasCompletedOnboarding {
                            onboardingComplete = true
                        }
                    }, onComplete: {
                        splashComplete = true
                        // Show onboarding if needed, otherwise go to feed
                        if auth.hasCompletedOnboarding {
                            onboardingComplete = true
                        }
                    })
                }

                // Onboarding — shown after splash if user hasn't signed in
                if splashComplete && !onboardingComplete {
                    OnboardingView {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            onboardingComplete = true
                        }
                    }
                    .transition(.opacity)
                }
            }
            .preferredColorScheme(.light)
            .onAppear {
                auth.verifyCredentialState()
                ConnectivityReprocessor.shared.start()
            }
        }
    }
}
