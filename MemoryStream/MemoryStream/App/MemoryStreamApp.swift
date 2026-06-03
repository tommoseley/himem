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
    /// Initialized at App-struct creation from `AuthService.shared
    /// .hasCompletedOnboarding`. True for returning users (Keychain
    /// holds their Apple userID), false for fresh installs. The
    /// PermissionWizardView flips it to true on completion.
    @State private var onboardingComplete: Bool = AuthService.shared.hasCompletedOnboarding
    @Environment(\.scenePhase) private var scenePhase
    /// User's appearance choice. Drives the root
    /// `.preferredColorScheme(...)` modifier below; default is
    /// `.system` so unmodified installs follow iOS Settings. See
    /// `Settings → Appearance`.
    @AppStorage("appearance") private var appearanceRaw: String = Appearance.system.rawValue
    private var appearance: Appearance {
        Appearance(rawValue: appearanceRaw) ?? .system
    }

    init() {
        // Phase-1 signpost: wraps the entire App.init body so the next
        // Instruments trace shows whether the 5s "wordmark only" cold-
        // launch phase is iOS storyboard / system framework loading
        // (everything BEFORE this interval), or in-app work
        // (the interval's duration). If the interval is sub-100ms,
        // phase 1 is system-level (dyld, framework loading) and not
        // ours to fix at this layer.
        let appInitState = LaunchSignposter.signposter.beginInterval(
            "app.init",
            id: LaunchSignposter.signposter.makeSignpostID()
        )
        defer { LaunchSignposter.signposter.endInterval("app.init", appInitState) }

        DispatchQueue.main.async {
            HiMemShortcuts.updateAppShortcutParameters()
        }
        // Bring up WatchConnectivity so transferred clips from the watch
        // land in the iPhone's inbox manifest. The session keeps the app
        // wakeable in the background to receive transfers even when HiMem
        // isn't foregrounded. Doesn't touch Core Data.
        WatchSessionDelegate.shared.start()
        // Seed UserDefaults with notification setting defaults (toggles off,
        // 8pm nudge time) before any @AppStorage in SettingsView reads them.
        NotificationService.registerDefaults()
        // EntitlementService / StoreKitService / FoundersCounter /
        // TenureTracker / WatchInboxNotificationCoordinator bootstrap
        // moved to LaunchScreenView.onStorageLoaded — they require
        // viewContext (EntitlementService.init's loadOrCreate fetches
        // the AssistBalance record), and running them here pre-empted
        // LaunchScreenView's off-main storage warm because main.async
        // fires before WindowGroup body evaluation. Net effect was a
        // 2-3s sync loadPersistentStores on the main thread during
        // every cold launch. See feedback_cold_launch_target memory.
        // Pre-warm StorageService.shared on a detached userInitiated task
        // so CloudKit's per-zone setup (~17-21s on Tom's dev container —
        // see docs/architecture/cloudkit-cold-launch-investigation.md)
        // starts as early as possible. Without this prewarm the storage
        // load doesn't begin until LaunchScreenView.onAppear's +0.1s
        // background dispatch, which is ~1.5s later. Every ms helps
        // when the wizard's pacing is the cover for CK's setup window.
        //
        // Safe in tests: Task.detached doesn't block App.init's return,
        // so XCTest's host-app-ready handshake completes normally. Tests
        // use their own StorageService(inMemory:) instance; the lazy
        // static `.shared` instance loading in the background doesn't
        // collide with their fixtures.
        Task.detached(priority: .userInitiated) {
            _ = StorageService.shared
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

                // Splash always runs — does storage warm + post-storage
                // bootstrap. For returning users it's the visible launch
                // surface. For fresh installs it runs invisibly under
                // the wizard, draining storage + bootstrap work while
                // the user moves through permissions. `onboardingComplete`
                // is no longer set by the splash callbacks; the wizard
                // owns that flip exclusively.
                if !splashComplete {
                    LaunchScreenView(
                        onStorageReady: { storageReady = true },
                        onComplete:     { splashComplete = true }
                    )
                }

                // Permission wizard — overlays everything for fresh
                // installs. Runs immediately (no splash gate) so the
                // ~17-21s CloudKit setup happens during the user's
                // natural pace through 7 permission pages. See
                // docs/architecture/cloudkit-cold-launch-investigation.md
                // for why the pacing is the cover. Returning users have
                // onboardingComplete=true at App-struct creation, so
                // this branch is dead for them.
                if !onboardingComplete {
                    PermissionWizardView {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            onboardingComplete = true
                        }
                    }
                    .transition(.opacity)
                }
            }
            .preferredColorScheme(appearance.colorScheme)
            .onAppear {
                auth.verifyCredentialState()
                ConnectivityReprocessor.shared.start()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                // Refresh auth from Keychain on foreground —
                // recovers a stale `isAuthenticated=false` if the
                // AuthService singleton was created during a
                // locked-device background launch (Keychain
                // unreadable then). Runs before the storageReady
                // guard since Keychain is independent of Core Data.
                auth.refresh()
                guard storageReady else { return }
                Task { await refreshDailyNudge() }
                Task { await retryPendingInboxTranscriptions() }
                Task { await promptForNotificationsIfFirstTime() }
                // Re-assert inbox clips to the watch so any ack that was
                // queued in transferUserInfo (because the iPhone was
                // backgrounded when the file arrived) drains immediately
                // when the user opens the app. Watch's `pending.remove`
                // is idempotent — already-removed clips are no-ops.
                WatchSessionDelegate.shared.reconcileWatchAcks()
                // Roll the monthly assist counter if the user crossed
                // a calendar-month boundary while the app was backgrounded.
                EntitlementService.shared.resetMonthlyIfDue()
                // Reset the home-screen icon badge to the live inbox
                // count. Defensive against state drift — push payloads
                // set the badge when they fire, but if the user
                // reviews clips and the badge isn't lowered before
                // the app is killed, the stale count sticks to the
                // icon until the next inbox mutation re-routes
                // through `replace(with:)`.
                InboxManifest.shared.syncBadgeNow()
            }
        }
    }

    /// Asks NotificationService to schedule or cancel today's daily nudge
    /// based on whether the user has created an entry today. Called on every
    /// scene activation so the nudge stays in sync with the user's day.
    @MainActor
    private func refreshDailyNudge() async {
        let lastCapture = StorageService.shared.mostRecentEntryAt()
        await NotificationService.shared.refreshDailyNudge(lastCaptureAt: lastCapture)
    }

    /// Scene-active backstop for inbox transcription. Picks up rows
    /// that the background WatchConnectivity wake-up received but
    /// didn't finish transcribing before iOS re-suspended the app.
    /// The actual transcription dispatch lives in
    /// `WatchSessionDelegate.transcribePendingInboxClips` so the
    /// arrival path and this backstop share one implementation —
    /// idempotent, skips already-attempted clips.
    @MainActor
    private func retryPendingInboxTranscriptions() async {
        await WatchSessionDelegate.transcribePendingInboxClips()
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
