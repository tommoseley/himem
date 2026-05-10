import SwiftUI
import AppIntents
import Combine
import UserNotifications

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

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        // Adopt the UNN delegate so foreground deliveries still show banners
        // and so notification taps can be routed to the right surface.
        UNUserNotificationCenter.current().delegate = self
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

    // MARK: - UNUserNotificationCenterDelegate

    /// Without this, foreground deliveries are suppressed (no banner). Banner
    /// + sound matches the lock-screen presentation; `.list` keeps the
    /// notification in Notification Center for in-place updates.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list, .badge])
    }

    /// Tap routing — posts a NotificationCenter event keyed by category. The
    /// JournalView observes the inbox-arrival post and presents the inbox
    /// sheet. Daily nudge taps just open the app (no further routing).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let rawCategory = response.notification.request.content.categoryIdentifier
        switch NotificationService.Category(rawValue: rawCategory) {
        case .inboxArrival:
            NotificationCenter.default.post(name: NotificationService.openInboxNotification, object: nil)
        case .dailyNudge:
            NotificationCenter.default.post(name: NotificationService.dailyNudgeTappedNotification, object: nil)
        case .none:
            break
        }
        completionHandler()
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
    @ObservedObject private var auth = AuthService.shared
    @State private var splashComplete = false
    @State private var storageReady = false
    @State private var onboardingComplete = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        DispatchQueue.main.async {
            HiMemShortcuts.updateAppShortcutParameters()
        }
        // Bring up WatchConnectivity so transferred clips from the watch
        // land in the iPhone's inbox manifest. The session keeps the app
        // wakeable in the background to receive transfers even when HiMem
        // isn't foregrounded.
        WatchSessionDelegate.shared.start()
        // Seed UserDefaults with notification setting defaults (toggles off,
        // 8pm nudge time) before any @AppStorage in SettingsView reads them.
        NotificationService.registerDefaults()
        // Pre-warm the en-US SpeechTranscriber model so the first watch
        // clip transcription isn't a blocking download. Best-effort —
        // logs and moves on if the install fails (no network, etc.); the
        // first transcription will then either retry the install or
        // return empty.
        Task.detached(priority: .background) {
            do {
                try await TranscriptionService.shared.ensureModelReady(for: Locale(identifier: "en-US"))
            } catch {
                NSLog("[Himem][Transcribe] pre-warm failed: \(error.localizedDescription)")
            }
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
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active, storageReady else { return }
                Task { await refreshDailyNudge() }
            }
        }
    }

    /// Asks NotificationService to schedule or cancel today's daily nudge
    /// based on whether the user has created an entry today. Called on every
    /// scene activation so the nudge stays in sync with the user's day.
    @MainActor
    private func refreshDailyNudge() async {
        let hasEntry = StorageService.shared.hasEntryCreatedToday()
        await NotificationService.shared.refreshDailyNudge(hadEntryToday: hasEntry)
    }
}
