import SwiftUI
import AppIntents
import UserNotifications
import os

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

/// Diagnostic lines that must survive to the DEVICE PERSISTENT LOG STORE.
///
/// **Why this exists rather than `NSLog`.** iOS elides a third-party app's log
/// message bodies to `<private>` **at write time** unless the value is
/// explicitly public. So an `NSLog` line is not merely *hidden* in a collected
/// archive — it was never recorded, and there is no post-hoc recovery.
/// Measured 2026-08-23 while staging the ④ out-of-range provocation: a
/// `log collect --device-udid … --last 15m` archive carried **21 bare
/// `(Foundation) <private>` entries** from HiMem and **zero** readable ones,
/// including the build stamp.
///
/// A logging configuration profile also unredacts, and was rejected: it is a
/// device-wide setting nobody reads, it has to be present *before* the events
/// are logged, and the next person to run ④ hits the same wall. Putting the
/// publicness at the source removes the failure mode instead of asking someone
/// to remember it (CLAUDE.md — *where a rule can be replaced by a mechanism,
/// replace it*).
///
/// **Level matters as much as privacy, and this is the easy half to get
/// wrong.** `Logger`'s `.debug` is never persisted and `.info` is held only in
/// memory — neither survives a `log collect`. Swapping `NSLog` for `.info`
/// would yield lines that are readable in a live stream and still absent from
/// the archive: the same instrument fault wearing a new coat. **Every call
/// here logs at `.notice`**, which is what `NSLog` mapped to.
///
/// **Publicness is a per-CALL-SITE decision, not a file-wide sweep.** Routing a
/// line through `DeviceLog` makes that entire line public. Only lines whose
/// payload is diagnostic — ids, counts, booleans, durations, byte sizes,
/// formats, error descriptions — belong here. **Anything carrying transcript
/// text, note bodies, titles or summaries stays on `NSLog` and stays private**
/// (Tom, 2026-08-23). `WatchSessionDelegate.outcomeLabel` already reduces a
/// transcript to `textLen=<count>` and is safe on that basis.
enum DeviceLog {
    private static let wcLogger    = Logger(subsystem: "com.himem.app", category: "WC")
    private static let inboxLogger = Logger(subsystem: "com.himem.app", category: "Inbox")
    private static let buildLogger = Logger(subsystem: "com.himem.app", category: "Build")

    /// WatchConnectivity: reachability transitions, transfer/ack, dedup verdicts.
    static func wc(_ message: String)    { wcLogger.notice("\(message, privacy: .public)") }
    /// Inbox manifest and sweep accounting: counts, ids, tombstones.
    static func inbox(_ message: String) { inboxLogger.notice("\(message, privacy: .public)") }
    /// The build stamp — which binary produced the evidence.
    static func build(_ message: String) { buildLogger.notice("\(message, privacy: .public)") }
}

/// **Which build is this?** — logged first thing at launch.
///
/// A whole diagnostic pass (2026-08-01/02) was spent on a device failure
/// where the leading hypothesis was "the running build isn't the code we
/// think it is", and nothing in the console could confirm or deny it.
/// This retires that question for ten seconds of work.
///
/// The executable's modification date is the load-bearing field: version
/// and build number often DON'T change between dogfood installs, so they
/// cannot distinguish "I just installed this" from "this is yesterday's
/// build". The binary's mtime always moves.
enum BuildStamp {
    static func log() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var built = "unknown"
        if let exe = Bundle.main.executableURL,
           let date = (try? FileManager.default.attributesOfItem(atPath: exe.path))?[.modificationDate] as? Date {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            built = f.string(from: date)
        }
        DeviceLog.build("[HiMem][Build] v\(version) (\(build)) · binary built \(built)")
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BuildStamp.log()
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
        if cat == WatchInboxNotificationCoordinator.categoryIdentifier {
            // Passive-only Captured-Clips arrivals (RH-1): in the foreground
            // the in-app Clips dot does the work — present nothing, no badge.
            completionHandler([])
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


@main
struct MemoryStreamApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var auth = AuthService.shared
    @State private var splashComplete = false
    @State private var storageReady = false
    /// Initialized at App-struct creation from `AuthService.shared
    /// .hasCompletedOnboardingWizard` — UserDefaults-backed. True
    /// when the user finished the PermissionWizard end-to-end on
    /// this install, false otherwise. Use this instead of
    /// `hasCompletedOnboarding` (which is the Keychain
    /// `appleUserID` check — that flips true after Page 1's Apple
    /// sign-in and would skip the wizard mid-flow if a user bails
    /// after only signing in). UserDefaults is also wiped on
    /// uninstall reliably; Keychain has been observed persisting
    /// across uninstall on real devices despite ThisDeviceOnly
    /// access class, which made the previous Keychain gate skip
    /// the wizard for reinstalled users who needed to re-grant
    /// permissions.
    @State private var onboardingComplete: Bool = AuthService.shared.hasCompletedOnboardingWizard
    /// The intro tour runs once, straight after the wizard, above the tab
    /// shell. Read once at App-struct creation like `onboardingComplete`, so a
    /// returning user never mounts it.
    @State private var introTourComplete: Bool = IntroTourStore.hasSeen
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
        // Mirror the Left-Handed FAB preference through iCloud KVS so it
        // follows the person across devices. No CloudKit schema — KVS is the
        // separate iCloud key-value bag; entitlement already present. Cheap,
        // non-blocking (a synchronize() just schedules). See FABHandednessSync.
        FABHandednessSync.shared.start()
        // Seed UserDefaults with notification setting defaults (toggles off,
        // 8pm nudge time) before any @AppStorage in SettingsView reads them.
        // NotificationService.registerDefaults() retired 2026-07-07 with
        // Channel B. Only Channel A remains and has no persisted defaults.
        // Entitlement / StoreKitService / WatchInboxNotificationCoordinator
        // bootstrap moved to LaunchScreenView.onStorageLoaded so cold
        // launches don't block on a sync loadPersistentStores. See
        // feedback_cold_launch_target memory.
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
        // Under XCTest / Swift Testing the shared production container
        // races the test hosts' persistent-store lock during Core Data
        // lightweight migration and Xcode kills the losers as preflight
        // timeouts. Tests never touch `.shared` directly — they use
        // `StorageService(inMemory: true)`. See troika review 2026-07-09.
        if !StorageService.isRunningTests {
            Task.detached(priority: .userInitiated) {
                _ = StorageService.shared
            }
        }
        // Resolve the iCloud Drive ubiquity container off-main during
        // launch. Apple's docs (FileManager.url(forUbiquityContainerIdentifier:))
        // require this to run on a background queue — the first call
        // after a fresh install or restore can take seconds to return
        // while iCloud configures the container. See
        // `docs/design/Storage architecture · CLAUDE.md`.
        Task.detached(priority: .userInitiated) {
            await UbiquityStore.shared.warmUp()
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
                NSLog("[HiMem][Transcribe] pre-warm failed: \(error.localizedDescription)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if storageReady && onboardingComplete {
                    HiMemTabView()
                        .environment(\.managedObjectContext, StorageService.shared.viewContext)
                        .environmentObject(QuickActionState.shared)
                        // Mount the auto-fire tutorial overlay here, on
                        // the authenticated journal only. Onboarding
                        // and the splash never trigger tutorials per
                        // the spec ("Never during onboarding, never on
                        // cold launch") and the orchestrator's
                        // `isArmed` gate enforces this; mounting on
                        // the wizard would make the overlay even
                        // structurally reachable from those surfaces,
                        // which is what we don't want.
                        .tutorialAutoFireOverlay()
                        // Replay from the `?` on any screen, or Settings →
                        // Learn. The root owns presentation so one view serves
                        // both first-run and replay.
                        .onReceive(IntroTourReplayBus.shared.$replayRequested) { requested in
                            guard requested else { return }
                            IntroTourReplayBus.shared.replayRequested = false
                            withAnimation(.easeInOut(duration: 0.3)) { introTourComplete = false }
                        }
                }

                // Intro tour — once, after the wizard, above the tab shell.
                // Mounted here rather than inside the wizard so the same view
                // serves the replay entry from `?` and Settings → Learn.
                if storageReady && onboardingComplete && !introTourComplete {
                    IntroTourView(
                        onFinish: {
                            IntroTourStore.markSeenAndRetireDuplicates()
                            withAnimation(.easeInOut(duration: 0.3)) { introTourComplete = true }
                        },
                        onStartWalkthrough: {
                            IntroTourStore.markSeenAndRetireDuplicates()
                            withAnimation(.easeInOut(duration: 0.3)) { introTourComplete = true }
                            WalkthroughOrchestrator.shared.startAtFirstBeat()
                        }
                    )
                    .transition(.opacity)
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
                        onStorageReady: {
                            NSLog("[HiMem][LifeDx] storageReady → true")
                            storageReady = true
                        },
                        onComplete:     { splashComplete = true }
                    )
                }

                // Permission wizard — overlays everything for fresh
                // installs. Runs immediately (no splash gate).
                //
                // **It is no longer the CloudKit cover** (ruled 2026-08-23).
                // The ~17-21s floor is O(1) in record count and hits
                // populated-account users; a genuinely new account's zone is
                // empty and the spike measured ~1.5s against one. The cover
                // and the wait were on opposite branches — returning users,
                // the only ones who need it, already bypass the cascade for
                // the honest live-count restore screen. So the wizard is four
                // steps (apple · name · mic · speech) and nothing branches on
                // a prediction: CloudKit reveals itself, and the restore
                // screen shows if activity appears. See
                // docs/architecture/cloudkit-cold-launch-investigation.md. Returning users have
                // onboardingComplete=true at App-struct creation, so
                // this branch is dead for them.
                if !onboardingComplete {
                    PermissionWizardView {
                        // Persist the completion to UserDefaults BEFORE
                        // flipping local state, so a force-quit during
                        // the fade animation still leaves us in the
                        // "wizard done" state for the next launch.
                        auth.markOnboardingWizardComplete()
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
            }
            #if DEBUG
            // Debug-only — `Settings → Debug → Run onboarding test`
            // bumps `onboardingTestRunRequestCount`. Drop back into the
            // wizard mid-session by flipping `onboardingComplete` and
            // `splashComplete` back to false so the full sequence
            // (splash + wizard) replays from the top.
            .onChange(of: auth.onboardingTestRunRequestCount) { _, _ in
                withAnimation(.easeInOut(duration: 0.25)) {
                    splashComplete = false
                    storageReady = false
                    onboardingComplete = false
                }
            }
            #endif
            .onChange(of: storageReady) { _, ready in
                NSLog("[HiMem][LifeDx] storageReady onChange → \(ready)")
                guard ready else { return }
                // Money 2026-06-18: cold-launch race — `.onChange(of:
                // scenePhase)` fires once at the first `.active`
                // transition, which often beats `LaunchScreenView`'s
                // async `onStorageReady` callback. When that
                // happened the scene-active backstop took the
                // `storageReady=false` exit and the retry path never
                // ran. The fix: also sweep when storage transitions
                // ready, regardless of where scenePhase is.
                Task { await retryPendingInboxTranscriptions() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                NSLog("[HiMem][LifeDx] scenePhase → \(newPhase) storageReady=\(storageReady)")
                guard newPhase == .active else { return }
                // Refresh auth from Keychain on foreground —
                // recovers a stale `isAuthenticated=false` if the
                // AuthService singleton was created during a
                // locked-device background launch (Keychain
                // unreadable then). Runs before the storageReady
                // guard since Keychain is independent of Core Data.
                auth.refresh()
                guard storageReady else {
                    NSLog("[HiMem][LifeDx] scene-active backstop SKIPPED — storage not ready yet")
                    return
                }
                NSLog("[HiMem][LifeDx] scene-active backstop firing retry path")
                Task { await retryPendingInboxTranscriptions() }
                Task { await promptForNotificationsIfFirstTime() }
                // Re-assert inbox clips to the watch so any ack that was
                // queued in transferUserInfo (because the iPhone was
                // backgrounded when the file arrived) drains immediately
                // when the user opens the app. Watch's `pending.remove`
                // is idempotent — already-removed clips are no-ops.
                WatchSessionDelegate.shared.reconcileWatchAcks()
                // P1 (2026-07-14): opening the phone is the other cue to
                // kick a backgrounded watch's stalled transfer queue.
                // Gated on an actual pending inbound transfer inside the
                // call, so this is a cheap no-op when the inbox is empty.
                WatchSessionDelegate.shared.kickWatchIfPendingInbound()
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

    /// Scene-active backstop for inbox transcription. Picks up rows
    /// that the background WatchConnectivity wake-up received but
    /// didn't finish transcribing before iOS re-suspended the app.
    /// The actual transcription dispatch lives in
    /// `WatchSessionDelegate.transcribePendingInboxClips` so the
    /// arrival path and this backstop share one implementation —
    /// idempotent, skips already-attempted clips.
    @MainActor
    private func retryPendingInboxTranscriptions() async {
        await WatchSessionDelegate.transcribePendingInboxClips(trigger: "scene-active")
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
