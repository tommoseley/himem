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

    /// Without this, foreground deliveries are suppressed (no banner).
    /// For the watch-inbox category specifically, we suppress the banner
    /// when the app is foregrounded *or* when the coordinator's
    /// re-evaluation says the trigger no longer holds (stale clip got
    /// reviewed before the 24h fire, etc.). For everything else, we
    /// show the standard banner + sound presentation.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let cat = notification.request.content.categoryIdentifier
        let userInfo = notification.request.content.userInfo
        if cat == WatchInboxNotificationCoordinator.categoryIdentifier {
            let reason = userInfo["reason"] as? String
            if reason == "stale",
               let clipIdString = userInfo["clipId"] as? String,
               let clipId = UUID(uuidString: clipIdString) {
                Task { @MainActor in
                    let shouldPresent = WatchInboxNotificationCoordinator.shared
                        .handleStaleFire(clipId: clipId, now: Date())
                    completionHandler(shouldPresent ? [.banner, .sound, .list, .badge] : [.badge])
                }
                return
            }
            // App in foreground = no push (banner on Today does the work).
            completionHandler([.badge])
            return
        }
        completionHandler([.banner, .sound, .list, .badge])
    }

    /// Tap and inline-action routing.
    ///   - Tap on the inbox-arrival push (any reason) → open the inbox.
    ///   - Snooze 4h / Mute for today → coordinator records the state.
    ///   - Legacy `inboxArrival` category from `NotificationService` is
    ///     kept for backward compatibility but the coordinator's new
    ///     `watch_inbox_arrival` category supersedes it in new code.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let rawCategory = response.notification.request.content.categoryIdentifier
        let actionId = response.actionIdentifier

        if rawCategory == WatchInboxNotificationCoordinator.categoryIdentifier {
            Task { @MainActor in
                if actionId == WatchInboxNotificationCoordinator.actionSnooze4hIdentifier
                    || actionId == WatchInboxNotificationCoordinator.actionMuteTodayIdentifier {
                    WatchInboxNotificationCoordinator.shared.handleAction(identifier: actionId)
                } else {
                    // Default tap (or `UNNotificationDefaultActionIdentifier`):
                    // route to inbox.
                    NotificationCenter.default.post(name: NotificationService.openInboxNotification, object: nil)
                }
                completionHandler()
            }
            return
        }

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
        // Register the inbox-arrival notification category + inline
        // actions (Snooze 4h / Mute for today) so when the coordinator
        // fires a push, the actions are surfaced.
        DispatchQueue.main.async {
            WatchInboxNotificationCoordinator.shared.registerCategories()
        }
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
                Task { await retryPendingInboxTranscriptions() }
                Task { await promptForNotificationsIfFirstTime() }
                // Re-assert inbox clips to the watch so any ack that was
                // queued in transferUserInfo (because the iPhone was
                // backgrounded when the file arrived) drains immediately
                // when the user opens the app. Watch's `pending.remove`
                // is idempotent — already-removed clips are no-ops.
                WatchSessionDelegate.shared.reconcileWatchAcks()
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

    /// Picks up inbox clips that the background WatchConnectivity wake-up
    /// received but didn't finish transcribing before iOS re-suspended
    /// the app. The `WatchSessionDelegate.didReceive` path kicks off a
    /// transcribeAsync Task when each clip arrives; if the system only
    /// gave us a short background slice, that Task gets cancelled before
    /// the speech analyzer can complete, leaving the clip with
    /// `transcript=""` and `transcriptionAttempted=false`. On next
    /// foreground we sweep those rows and retry — cheap (typically 0
    /// clips), idempotent (skips already-attempted), and fixes the
    /// "still pending after watch came back in range" symptom.
    @MainActor
    private func retryPendingInboxTranscriptions() async {
        let pending = InboxManifest.shared.clips.filter {
            $0.transcript.isEmpty && !$0.transcriptionAttempted
        }
        guard !pending.isEmpty else { return }
        NSLog("[Himem][Inbox] foreground: retrying \(pending.count) pending transcription\(pending.count == 1 ? "" : "s")")
        for clip in pending {
            let url = InboxManifest.audioURL(for: clip.audioFilename)
            let result = await TranscriptionService.shared.transcribe(audioURL: url)
            InboxManifest.shared.recordTranscriptionAttempt(clipId: clip.clipId, transcript: result.text)
        }
    }

    /// Fires the iOS notification permission prompt exactly once per
    /// install, the first time the app becomes active in a state where
    /// it could plausibly post a notification. `requestPermissionIfNeeded`
    /// is idempotent — iOS only ever shows the system dialog when status
    /// is `.notDetermined`. After Allow / Don't Allow, future calls
    /// return the existing status without re-prompting, so calling this
    /// on every scene-activation is harmless and ensures users who
    /// installed before the watch-clip notification path was wired up
    /// still get the prompt.
    @MainActor
    private func promptForNotificationsIfFirstTime() async {
        _ = await NotificationService.shared.requestPermissionIfNeeded()
    }
}
