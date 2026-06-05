import SwiftUI
import AuthenticationServices
import AVFoundation
import CoreData
import Photos
import Speech
import CoreLocation
import UserNotifications

// MARK: - Public entry point
//
// Replaces the old 4-screen OnboardingView. Same callback API
// (`onComplete: () -> Void`) so the swap in `MemoryStreamApp.body` is a
// one-line change. Spec: `docs/design/Himem · Onboarding.html` +
// `screens-onboarding-wizard.jsx` (2026-06-02).
//
// Architecturally important: this view's pacing is the cover for
// CloudKit's first-launch sync (see
// `docs/architecture/cloudkit-cold-launch-investigation.md`). By the
// time the user finishes the 7 permission steps, CloudKit's ~21s
// per-zone setup has completed in the background.

struct PermissionWizardView: View {
    let onComplete: () -> Void

    @ObservedObject private var auth = AuthService.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var step: WizardStep = .apple
    @State private var editedName: String = ""
    @State private var notifyClipsOn: Bool = true   // Channel A, locked notif spec default ON
    @State private var notifyNudgeOn: Bool = false  // Channel B, locked notif spec default OFF
    @State private var blockedReason: RequiredPermission? = nil

    // Restore flow state — populated on the reinstall path. The
    // permission cascade is bypassed entirely for returning users
    // per docs/design spec; we honestly cover the CloudKit catch-up
    // window with a live count instead of theater.
    @State private var restoredCount: Int = 0
    @State private var lastImportEventAt: Date = Date()
    /// Timestamp of the most recent change in `restoredCount`. Used as
    /// a stronger settle signal than CK events alone — events can fire
    /// end-of-import before the relationship records finish writing,
    /// but the visible count won't stabilize until everything's on
    /// disk.
    @State private var lastCountChangeAt: Date = Date()
    /// Flips true the first time we observe evidence that CloudKit has
    /// actually started doing work — either an `.import` event or a
    /// growing entry count. Without this gate, the very first
    /// iteration of the settle-check fires trivially: at t=5s the
    /// event-silence + count-stable conditions are met because nothing
    /// has happened yet, and we'd advance through the restore screen
    /// in the middle of CloudKit's setup phase before any data
    /// arrived. Gating on "we've at least seen CK start" prevents that.
    @State private var hasSeenCloudKitActivity: Bool = false
    /// In-flight `.import` event identifiers (start emitted with
    /// endDate=nil, end emitted with endDate set). When this set
    /// is empty AND silence-since-last-event exceeds the settle
    /// threshold, the restore is considered complete.
    @State private var activeImportIDs: Set<UUID> = []
    @State private var cloudKitEventObserver: NSObjectProtocol? = nil

    var body: some View {
        ZStack {
            Crucible.Color.paper.ignoresSafeArea()

            if let reason = blockedReason {
                ScrRequiredBlock(reason: reason,
                                 onRetry: handleBlockedRetry,
                                 onBack: { withWizardAnim { blockedReason = nil } })
                    .transition(.opacity)
            } else {
                Group {
                    switch step {
                    case .apple:        ScrW1Apple(onSignIn: handleAppleSignIn)
                    case .name:         ScrW1Name(name: $editedName, onContinue: nameComplete)
                    case .mic:          micPage()
                    case .speech:       speechPage()
                    case .photos:       photosPage()
                    case .camera:       cameraPage()
                    case .location:     locationPage()
                    case .notifications: ScrW7Notifications(
                                            clipsOn: $notifyClipsOn,
                                            nudgeOn: $notifyNudgeOn,
                                            onBack: { withWizardAnim { step = .location } },
                                            onSkip: { withWizardAnim { step = .land } },
                                            onContinue: handleNotifications)
                    case .land:         ScrWLand(
                                            name: auth.userName,
                                            onCaptureFirst: handleLandCaptureFirst,
                                            onLookAround: onComplete)
                    case .restoring:    ScrReinstallRestore(
                                            name: auth.userName,
                                            count: restoredCount,
                                            onKeepGoing: onComplete)
                                        .task { await runRestoreStateMachine() }
                                        .onDisappear { teardownCloudKitEventObserver() }
                    case .restoreDone:  ScrReinstallRestoreDone(
                                            finalCount: restoredCount,
                                            onGo: onComplete)
                                        .task { await runRestoreDoneAutoAdvance() }
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
        .onAppear {
            editedName = auth.userName
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Returning from Settings: re-check the blocked permission
            // and advance if granted. Required-block flow uses this hook
            // to let the user resolve denied mic/speech without us forcing
            // them to retry inside the wizard.
            guard newPhase == .active, let reason = blockedReason else { return }
            Task { await recheckBlocked(reason) }
        }
    }

    // MARK: - Step pages (WizardPage helpers)

    @ViewBuilder private func micPage() -> some View {
        WizardPage(
            step: 2, glyph: G.mic, tint: .accent, required: true,
            title: "The fastest way in is to just say it.",
            why: "HiMem captures by voice — on your phone and your Watch.",
            example: "\u{201C}Don\u{2019}t let me forget the pear tree fruited.\u{201D} Tap, talk, done.",
            cta: "Allow microphone",
            showBack: true,
            onBack: { withWizardAnim { step = .name } },
            onSkip: nil,
            onCta: { Task { await handleMic() } }
        )
    }

    @ViewBuilder private func speechPage() -> some View {
        WizardPage(
            step: 3, glyph: G.speech, tint: .accent, required: true,
            title: "So you can find a thought by what you said.",
            why: "Speech turns your voice into words you can search and read back.",
            example: "Search \u{201C}pear tree\u{201D} weeks later and the right memory surfaces.",
            cta: "Allow speech recognition",
            showBack: true,
            onBack: { withWizardAnim { step = .mic } },
            onSkip: nil,
            onCta: { Task { await handleSpeech() } }
        )
    }

    @ViewBuilder private func photosPage() -> some View {
        WizardPage(
            step: 4, glyph: G.photos, tint: .accent, required: false,
            title: "Let a picture ride along with the thought.",
            why: "Add photos from your library to any memory.",
            example: "The recipe you photographed, kept beside the note about it.",
            cta: "Allow photo access",
            showBack: true,
            onBack: { withWizardAnim { step = .speech } },
            onSkip: { withWizardAnim { step = .camera } },
            onCta: { Task { await handlePhotos() } }
        )
    }

    @ViewBuilder private func cameraPage() -> some View {
        WizardPage(
            step: 5, glyph: G.camera, tint: .accent, required: false,
            title: "Catch the moment, not just the words for it.",
            why: "Take a photo or video straight into a memory.",
            example: "Snap the whiteboard before it\u{2019}s erased — it lands in HiMem.",
            cta: "Allow camera",
            showBack: true,
            onBack: { withWizardAnim { step = .photos } },
            onSkip: { withWizardAnim { step = .location } },
            onCta: { Task { await handleCamera() } }
        )
    }

    @ViewBuilder private func locationPage() -> some View {
        WizardPage(
            step: 6, glyph: G.location, tint: .accent, required: false,
            title: "Let a memory remember where you were.",
            why: "HiMem tags captures with a place — only while you\u{2019}re using it.",
            example: "Months later, a note still says \u{201C}Marsh Walk, Murrells Inlet.\u{201D}",
            cta: "Allow location while using",
            showBack: true,
            onBack: { withWizardAnim { step = .camera } },
            onSkip: { withWizardAnim { step = .notifications } },
            onCta: { Task { await handleLocation() } }
        )
    }

    // MARK: - Sign in flow

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        // Capture whether Apple shared fullName THIS sign-in. Apple only
        // returns fullName on the first sign-in ever for an Apple ID +
        // bundle ID combination — subsequent sign-ins (including post-
        // reinstall on the same Apple ID) return fullName=nil. That gives
        // us a reliable returning-user signal independent of any local
        // state that uninstall might or might not wipe.
        let appleSharedName = Self.fullNameProvided(in: result)
        auth.handleSignInResult(result)

        guard auth.isAuthenticated else {
            if case .failure = result {
                // User cancelled or sheet errored. Apple sheet can re-show
                // in place; route to the blocked screen for the warm
                // "Try again with Apple" CTA rather than a stuck page.
                withWizardAnim { blockedReason = .apple }
            }
            return
        }

        if appleSharedName {
            // True first-sign-in to HiMem — Apple just gave us a name to
            // confirm. Run the full wizard: Name → Mic → Speech → Photos
            // → Camera → Location → Notifications → Land.
            withWizardAnim {
                editedName = auth.userName
                step = .name
            }
        } else if !auth.userName.isEmpty {
            // Returning user — Apple won't re-share fullName, but the
            // iCloud KV sidecar (restored via AuthService.loadStoredCredentials)
            // already populated userName from a previous install. Skip
            // the permission cascade entirely per spec; the restore
            // screen covers the CloudKit catch-up window honestly.
            Task { await advance(to: .restoring) }
        } else {
            // Edge case: Apple didn't share a name AND we have no stored
            // name (no KV, never used HiMem on this Apple ID — but Apple
            // returned nil fullName anyway for whatever reason). Treat as
            // fresh user so they can type a name; the full wizard runs.
            withWizardAnim {
                editedName = ""
                step = .name
            }
        }
    }

    /// Returns true if the `ASAuthorization` result contains a non-empty
    /// fullName.givenName. Used by handleAppleSignIn to distinguish a
    /// first-ever sign-in from a returning user's re-authentication.
    private static func fullNameProvided(in result: Result<ASAuthorization, Error>) -> Bool {
        guard case .success(let authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let given = credential.fullName?.givenName?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !given.isEmpty
        else { return false }
        return true
    }

    private func nameComplete() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            // Routes through AuthService.setUserName so the value lands
            // in @Published + Keychain + iCloud KV sidecar in one call.
            // The KV write is what survives uninstall+reinstall.
            auth.setUserName(trimmed)
        }
        Task { await advance(to: .mic) }
    }

    // MARK: - Permission handlers

    private func handleMic() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        if granted {
            await advance(to: .speech)
        } else {
            withWizardAnim { blockedReason = .mic }
        }
    }

    private func handleSpeech() async {
        let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in cont.resume(returning: status) }
        }
        if status == .authorized {
            await advance(to: .photos)
        } else {
            withWizardAnim { blockedReason = .speech }
        }
    }

    private func handlePhotos() async {
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        // Optional permission — advance regardless of grant.
        await advance(to: .camera)
    }

    private func handleCamera() async {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        await advance(to: .location)
    }

    private func handleLocation() async {
        // No async API for location; request and move on. iOS shows the
        // system dialog. Status is read elsewhere when location is used.
        await MainActor.run {
            CLLocationManager().requestWhenInUseAuthorization()
        }
        try? await Task.sleep(nanoseconds: 200_000_000) // brief beat so the user sees the dialog before the transition
        await advance(to: .notifications)
    }

    private func handleNotifications() async {
        if notifyClipsOn || notifyNudgeOn {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        }
        // Persist Channel B preference; Channel A is implicit.
        UserDefaults.standard.set(notifyNudgeOn, forKey: NotificationService.Keys.notifyDailyNudge)
        await advance(to: .land)
    }

    // MARK: - Auto-skip helper
    //
    // Forward-only transitions route through `advance(to:)` which
    // recursively skips any permission step that's already granted —
    // on reinstall iOS keeps mic/speech/photos/camera/location/
    // notification grants, so re-asking them is empty friction.
    // Back navigation and skip-tap navigation should set `step`
    // directly so the user can still review earlier pages on demand.

    /// Async transition that recursively skips already-granted steps.
    /// Lands on the first step that genuinely needs user action, or
    /// `.land` if all permissions on the way are already granted.
    private func advance(to nextStep: WizardStep) async {
        var current = nextStep
        while let skipped = await stepIfShouldSkip(current) {
            current = skipped
        }
        await MainActor.run {
            withWizardAnim { step = current }
        }
    }

    /// Returns the next step if `current` should be skipped (permission
    /// already granted), or nil if `current` is the right step to land
    /// on. Notifications is special-cased: skip only when iOS auth is
    /// granted AND the user previously set the Channel B (inactivity
    /// nudge) preference, since the page is the only surface that
    /// captures Channel B opt-in.
    private func stepIfShouldSkip(_ current: WizardStep) async -> WizardStep? {
        switch current {
        case .mic:
            return AVAudioApplication.shared.recordPermission == .granted ? .speech : nil
        case .speech:
            return SFSpeechRecognizer.authorizationStatus() == .authorized ? .photos : nil
        case .photos:
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            return (status == .authorized || status == .limited) ? .camera : nil
        case .camera:
            return AVCaptureDevice.authorizationStatus(for: .video) == .authorized ? .location : nil
        case .location:
            let status = CLLocationManager().authorizationStatus
            return (status == .authorizedWhenInUse || status == .authorizedAlways) ? .notifications : nil
        case .notifications:
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let hasNudgePref = UserDefaults.standard.object(forKey: NotificationService.Keys.notifyDailyNudge) != nil
            return (settings.authorizationStatus == .authorized && hasNudgePref) ? .land : nil
        case .apple, .name, .land, .restoring, .restoreDone:
            return nil
        }
    }

    /// Wired to the Land screen's primary "Capture your first memory"
    /// CTA. Sets CaptureRequestBus.pendingVoiceRecord BEFORE dismissing
    /// the wizard so the JournalView's onAppear (which checks the bus)
    /// auto-opens the voice composer the moment it mounts. Net effect:
    /// the user's first tap after onboarding lands them already
    /// recording, matching the spec note "capture is the invitation."
    private func handleLandCaptureFirst() {
        CaptureRequestBus.shared.pendingVoiceRecord = true
        onComplete()
    }

    // MARK: - Restore state machine
    //
    // Owned by the parent view so the child screens stay pure
    // presentation. Detection uses NSPersistentCloudKitContainer's
    // .import events directly (start + end notifications) instead of
    // inferring from NSPersistentStoreRemoteChange silence: the
    // silence heuristic fired too early during natural pauses between
    // batches (e.g. Topic records → JournalEntry → relationship
    // records arrive in waves with multi-second gaps).
    //
    // Lifecycle:
    //   .restoring   - poll CD_JournalEntry count every 250ms while
    //                  observing CK import events. "Settled" requires
    //                  BOTH: no in-flight imports AND no import events
    //                  for `settleSilenceSeconds`. Absolute ceiling of
    //                  `maxWaitSeconds` so we never hang forever.
    //   .restoreDone - briefly displays the final count for ~1.5s, then
    //                  auto-advances to Today via onComplete.

    private func runRestoreStateMachine() async {
        installCloudKitEventObserver()
        let now = Date()
        lastImportEventAt = now
        lastCountChangeAt = now
        let pollInterval: UInt64 = 250_000_000   // 0.25s
        // Per the spec ("the rest keep arriving in the background.
        // Nothing waits on this screen."), we advance once the user has
        // seen enough of their data to feel oriented — not when every
        // last record is on disk. Tightened thresholds:
        let settleSilenceSeconds: TimeInterval = 5.0
        let countStableSeconds: TimeInterval = 4.0
        let maxWaitSeconds: TimeInterval = 18.0
        let startedAt = Date()

        while !Task.isCancelled, step == .restoring {
            let count = await fetchEntryCount()
            await MainActor.run {
                if count != restoredCount {
                    restoredCount = count
                    lastCountChangeAt = Date()
                    // Growing count is independent evidence of CK
                    // activity even if we somehow missed the event.
                    hasSeenCloudKitActivity = true
                }
            }

            let totalElapsed = Date().timeIntervalSince(startedAt)
            if totalElapsed > maxWaitSeconds {
                await MainActor.run {
                    withWizardAnim { step = .restoreDone }
                }
                break
            }

            // Settled requires FOUR signals together:
            //  1. hasSeenCloudKitActivity — CK has at least started
            //     doing work. Without this, the t=5s iteration trivially
            //     satisfies the other three conditions (no events, no
            //     count change) during CK's setup phase, before any
            //     data has arrived. Fixed 2026-06-03 after Tom observed
            //     "loading screen vanished but still syncing."
            //  2. activeImportIDs empty — no in-flight import batch.
            //  3. eventSilentFor > silenceThreshold — bridges typical
            //     gaps between batches.
            //  4. countStableFor > stableThreshold — strongest signal;
            //     CK end events can fire before all relationship records
            //     finish writing, but the visible count won't stop
            //     changing until everything's on disk.
            let noActiveImports = activeImportIDs.isEmpty
            let eventSilentFor = Date().timeIntervalSince(lastImportEventAt)
            let countStableFor = Date().timeIntervalSince(lastCountChangeAt)
            if hasSeenCloudKitActivity
                && noActiveImports
                && eventSilentFor > settleSilenceSeconds
                && countStableFor > countStableSeconds {
                await MainActor.run {
                    withWizardAnim { step = .restoreDone }
                }
                break
            }

            try? await Task.sleep(nanoseconds: pollInterval)
        }
        teardownCloudKitEventObserver()
    }

    private func runRestoreDoneAutoAdvance() async {
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s confirmation beat
        guard !Task.isCancelled, step == .restoreDone else { return }
        await MainActor.run { onComplete() }
    }

    private func installCloudKitEventObserver() {
        guard cloudKitEventObserver == nil else { return }
        let observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: nil
        ) { note in
            guard let event = note.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else { return }
            guard event.type == .import else { return }
            let id = event.identifier
            let isStarted = event.endDate == nil
            Task { @MainActor in
                self.lastImportEventAt = Date()
                self.hasSeenCloudKitActivity = true
                if isStarted {
                    self.activeImportIDs.insert(id)
                } else {
                    self.activeImportIDs.remove(id)
                }
            }
        }
        cloudKitEventObserver = observer
    }

    private func teardownCloudKitEventObserver() {
        if let observer = cloudKitEventObserver {
            NotificationCenter.default.removeObserver(observer)
            cloudKitEventObserver = nil
        }
    }

    private func fetchEntryCount() async -> Int {
        let ctx = StorageService.shared.viewContext
        return await ctx.perform {
            let req = NSFetchRequest<NSFetchRequestResult>(entityName: "JournalEntry")
            req.includesSubentities = false
            return (try? ctx.count(for: req)) ?? 0
        }
    }

    // MARK: - Blocked flow

    private func handleBlockedRetry() {
        guard let reason = blockedReason else { return }
        switch reason {
        case .apple:
            withWizardAnim { blockedReason = nil; step = .apple }
        case .mic, .speech:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }

    private func recheckBlocked(_ reason: RequiredPermission) async {
        switch reason {
        case .apple:
            // Apple state is auth.isAuthenticated; user retries inline,
            // not via Settings.
            return
        case .mic:
            if AVAudioApplication.shared.recordPermission == .granted {
                await MainActor.run {
                    withWizardAnim { blockedReason = nil; step = .speech }
                }
            }
        case .speech:
            if SFSpeechRecognizer.authorizationStatus() == .authorized {
                await MainActor.run {
                    withWizardAnim { blockedReason = nil; step = .photos }
                }
            }
        }
    }

    // MARK: - Helpers

    private func withWizardAnim(_ block: () -> Void) {
        withAnimation(.easeInOut(duration: 0.3)) { block() }
    }
}

// MARK: - State types

enum WizardStep {
    case apple
    case name
    case mic
    case speech
    case photos
    case camera
    case location
    case notifications
    case land
    /// Returning-user-only steps: reinstall on the same Apple ID.
    /// Bypass the permission cascade per the locked spec — anything
    /// iOS revoked on uninstall is re-asked in context at first
    /// capture, not as a fresh wall of 7 pages.
    case restoring
    case restoreDone

    /// Visible step number on the progress rail (Apple + Name are both step 1).
    /// Restore screens don't render the progress rail (they have their own
    /// layout) so the displayed step doesn't apply.
    var displayedStep: Int {
        switch self {
        case .apple, .name: return 1
        case .mic: return 2
        case .speech: return 3
        case .photos: return 4
        case .camera: return 5
        case .location: return 6
        case .notifications: return 7
        case .land: return 7
        case .restoring, .restoreDone: return 1
        }
    }
}

enum RequiredPermission {
    case apple, mic, speech
}

enum WizardTint {
    case accent, ai, apple

    var foreground: SwiftUI.Color {
        switch self {
        case .accent: return Crucible.Color.accent
        case .ai:     return Crucible.Color.aiBlue
        case .apple:  return .white
        }
    }

    var tintBackground: SwiftUI.Color {
        switch self {
        case .accent: return Crucible.Color.accentTint
        case .ai:     return Crucible.Color.aiBlueTint
        case .apple:  return Crucible.Color.ink
        }
    }

    var ctaBackground: SwiftUI.Color {
        switch self {
        case .accent: return Crucible.Color.accent
        case .ai:     return Crucible.Color.aiBlue
        case .apple:  return Crucible.Color.ink
        }
    }

    var ctaForeground: SwiftUI.Color {
        switch self {
        case .accent: return Crucible.Color.accentInk
        case .ai:     return .white
        case .apple:  return .white
        }
    }
}

// MARK: - Shared scaffolding

/// Top bar with back chevron, "N of 7" centered count, optional Skip,
/// and the 7-segment progress rail. Bar is constant height (~50pt) so
/// switching between pages doesn't jiggle the icon.
struct WizardTopBar: View {
    let step: Int
    let skippable: Bool
    let showBack: Bool
    let onBack: (() -> Void)?
    let onSkip: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                Group {
                    if showBack, let onBack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Crucible.Color.ink2)
                        }
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 50, alignment: .leading)

                Text("\(step) of 7")
                    .font(.system(size: 12.5, weight: .semibold))
                    .tracking(0.2)
                    .foregroundStyle(Crucible.Color.ink3)
                    .frame(maxWidth: .infinity)

                Group {
                    if skippable, let onSkip {
                        Button("Skip", action: onSkip)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Crucible.Color.ink2)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 50, alignment: .trailing)
            }
            .frame(height: 34)

            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i < step ? Crucible.Color.accent : Crucible.Color.hairline)
                        .frame(height: 3)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
    }
}

/// Shared body template every standard permission page renders.
/// Custom screens (Apple welcome, Name, Notifications, Land, Blocked)
/// don't go through this — their layouts diverge.
struct WizardPage: View {
    let step: Int
    let glyph: GlyphRef
    let tint: WizardTint
    let required: Bool
    let title: String
    let why: String
    let example: String
    let cta: String
    let showBack: Bool
    let onBack: (() -> Void)?
    let onSkip: (() -> Void)?
    let onCta: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            WizardTopBar(
                step: step,
                skippable: onSkip != nil,
                showBack: showBack,
                onBack: onBack,
                onSkip: onSkip
            )

            VStack(alignment: .leading, spacing: 0) {
                RoundedRectangle(cornerRadius: 19)
                    .fill(tint.tintBackground)
                    .frame(width: 68, height: 68)
                    .overlay(
                        glyph.image.foregroundStyle(tint.foreground)
                    )
                    .padding(.top, 40)

                Text(title)
                    .font(.system(size: 27, design: .serif))
                    .fontWeight(.regular)
                    .lineSpacing(2)
                    .foregroundStyle(Crucible.Color.ink)
                    .padding(.top, 22)

                Text(why)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Crucible.Color.ink2)
                    .lineSpacing(4)
                    .padding(.top, 12)
                    .frame(maxWidth: 280, alignment: .leading)

                if required {
                    Text("Required to use HiMem")
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Crucible.Color.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Crucible.Color.accentTint)
                        )
                        .padding(.top, 16)
                }

                exampleCard
                    .padding(.top, 22)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 26)

            ctaButton
                .padding(.horizontal, 26)
                .padding(.bottom, 30)
        }
    }

    private var exampleCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("WHAT THIS IS FOR")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(Crucible.Color.ink3)
            Text(example)
                .font(.system(size: 16, design: .serif))
                .italic()
                .foregroundStyle(Crucible.Color.ink)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 15)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Crucible.Color.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Crucible.Color.hairline, lineWidth: 1)
                )
        )
    }

    private var ctaButton: some View {
        Button(action: onCta) {
            Text(cta)
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14).fill(tint.ctaBackground)
                )
                .foregroundStyle(tint.ctaForeground)
        }
    }
}

// MARK: - Glyphs (SF Symbol references)

struct GlyphRef {
    let image: AnyView
}

enum G {
    static let mic = GlyphRef(image: AnyView(
        Image(systemName: "mic.fill")
            .font(.system(size: 30, weight: .semibold))
    ))
    static let speech = GlyphRef(image: AnyView(
        Image(systemName: "waveform")
            .font(.system(size: 30, weight: .semibold))
    ))
    static let photos = GlyphRef(image: AnyView(
        Image(systemName: "photo.fill.on.rectangle.fill")
            .font(.system(size: 28, weight: .semibold))
    ))
    static let camera = GlyphRef(image: AnyView(
        Image(systemName: "camera.fill")
            .font(.system(size: 28, weight: .semibold))
    ))
    static let location = GlyphRef(image: AnyView(
        Image(systemName: "mappin.and.ellipse")
            .font(.system(size: 28, weight: .semibold))
    ))
    static let bell = GlyphRef(image: AnyView(
        Image(systemName: "bell.fill")
            .font(.system(size: 28, weight: .semibold))
    ))
}

// MARK: - Page 1 · Welcome + Sign in with Apple

struct ScrW1Apple: View {
    let onSignIn: (Result<ASAuthorization, Error>) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // No WizardTopBar on the entry page — the "N of 7" progress
            // rail makes a hard promise about flow length before we know
            // whether the user is heading down the 7-step fresh-user path
            // or the 2-step reinstall restore. The counter starts on
            // ScrW1Name (fresh user) where the 7-step flow is committed.
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("Hi")
                        .font(.system(size: 52, design: .serif))
                        .fontWeight(.regular)
                        .foregroundStyle(Crucible.Color.ink)
                    Text("Mem")
                        .font(.system(size: 52, design: .serif))
                        .italic()
                        .foregroundStyle(Crucible.Color.accent)
                }
                .padding(.top, 80) // ~48 + ~32 to preserve the wordmark's
                                   // approximate Y-position without the
                                   // (removed) top bar.

                Text("A quiet place for the thoughts you don\u{2019}t want to lose.")
                    .font(.system(size: 21, design: .serif))
                    .italic()
                    .lineSpacing(3)
                    .foregroundStyle(Crucible.Color.ink2)
                    .frame(maxWidth: 270, alignment: .leading)
                    .padding(.top, 20)

                VStack(alignment: .leading, spacing: 13) {
                    bullet(headline: "Capture anything.",
                           body: "Voice, photo, video — on your phone or your Watch.")
                    bullet(headline: "Organized quietly.",
                           body: "HiMem listens for the thread. You stay in control.")
                    bullet(headline: "Yours, end to end.",
                           body: "Synced privately through your own iCloud.")
                }
                .padding(.top, 26)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 26)

            VStack(spacing: 12) {
                SignInWithAppleButton(
                    .continue,
                    onRequest: { request in request.requestedScopes = [.fullName] },
                    onCompletion: onSignIn
                )
                .signInWithAppleButtonStyle(.black)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                Text("One tap with Face ID. No password to set, no email to verify. Your name comes from Apple — we never ask for it twice.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Crucible.Color.ink3)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 10)
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 30)
        }
    }

    private func bullet(headline: String, body: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 11) {
            Circle()
                .fill(Crucible.Color.accent)
                .frame(width: 6, height: 6)
                .padding(.top, 5)
            (Text(headline).fontWeight(.semibold).foregroundColor(Crucible.Color.ink)
             + Text(" \(body)").foregroundColor(Crucible.Color.ink2))
                .font(.system(size: 13.5))
                .lineSpacing(3)
        }
    }
}

// MARK: - Page 1b · Name confirmation

struct ScrW1Name: View {
    @Binding var name: String
    let onContinue: () -> Void
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            WizardTopBar(step: 1, skippable: false, showBack: false, onBack: nil, onSkip: nil)

            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Crucible.Color.confirmedTint)
                        .frame(width: 68, height: 68)
                    Image(systemName: "checkmark")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Crucible.Color.confirmed)
                }
                .padding(.top, 52)
                .frame(maxWidth: .infinity, alignment: .leading)

                (Text("You\u{2019}re in. ").foregroundColor(Crucible.Color.ink)
                 + Text("What should we call you?").italic().foregroundColor(Crucible.Color.accent))
                    .font(.system(size: 29, design: .serif))
                    .lineSpacing(2)
                    .padding(.top, 22)

                Text("YOUR NAME")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Crucible.Color.ink3)
                    .padding(.top, 24)
                    .padding(.bottom, 7)

                TextField("Tom", text: $name)
                    .font(.system(size: 17))
                    .foregroundStyle(Crucible.Color.ink)
                    .focused($fieldFocused)
                    .submitLabel(.continue)
                    .onSubmit(onContinue)
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12).fill(Crucible.Color.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Crucible.Color.accent, lineWidth: 1)
                            )
                    )

                Text("Apple shared this with your sign-in. Change it to anything you like.")
                    .font(.system(size: 12))
                    .foregroundStyle(Crucible.Color.ink3)
                    .padding(.top, 8)
                    .lineSpacing(3)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 26)

            Button(action: onContinue) {
                Text("Continue")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Crucible.Color.accent))
                    .foregroundStyle(Crucible.Color.accentInk)
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 30)
        }
        .onAppear { fieldFocused = true }
    }
}

// MARK: - Page 7 · Notifications (two-channel)

struct ScrW7Notifications: View {
    @Binding var clipsOn: Bool
    @Binding var nudgeOn: Bool
    let onBack: () -> Void
    let onSkip: () -> Void
    let onContinue: () async -> Void

    var body: some View {
        VStack(spacing: 0) {
            WizardTopBar(step: 7, skippable: true, showBack: true, onBack: onBack, onSkip: onSkip)

            VStack(alignment: .leading, spacing: 0) {
                RoundedRectangle(cornerRadius: 19)
                    .fill(Crucible.Color.accentTint)
                    .frame(width: 68, height: 68)
                    .overlay(G.bell.image.foregroundStyle(Crucible.Color.accent))
                    .padding(.top, 36)

                Text("Two kinds of nudge. You choose both.")
                    .font(.system(size: 26, design: .serif))
                    .fontWeight(.regular)
                    .lineSpacing(2)
                    .foregroundStyle(Crucible.Color.ink)
                    .padding(.top, 20)

                VStack(spacing: 9) {
                    channelRow(
                        on: $clipsOn,
                        title: "When clips arrive",
                        body: "A quiet, silent note when Watch clips are waiting. No buzz."
                    )
                    channelRow(
                        on: $nudgeOn,
                        title: "If it\u{2019}s been a while",
                        body: "An optional reminder after a quiet stretch. Off unless you want it."
                    )
                }
                .padding(.top, 18)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 26)

            VStack(spacing: 10) {
                Text("iOS will ask once. You can change either of these in Settings later.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Crucible.Color.ink3)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 8)

                Button(action: { Task { await onContinue() } }) {
                    Text("Turn on notifications")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Crucible.Color.accent))
                        .foregroundStyle(Crucible.Color.accentInk)
                }
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 30)
        }
    }

    private func channelRow(on: Binding<Bool>, title: String, body: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink)
                Text(body)
                    .font(.system(size: 12))
                    .foregroundStyle(Crucible.Color.ink2)
                    .lineSpacing(3)
            }
            Toggle("", isOn: on)
                .labelsHidden()
                .tint(Crucible.Color.confirmed)
                .padding(.top, 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Crucible.Color.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Crucible.Color.hairline, lineWidth: 1)
                )
        )
    }
}

// MARK: - Land

/// Spec update 2026-06-03: action-first footer. Replaces the earlier
/// FAB-hint+text-link footer with a two-button stack — ochre primary
/// "Capture your first memory" (wires to CaptureRequestBus so the
/// voice composer auto-opens in JournalView) and outlined secondary
/// "Later — let me look around" (just dismisses the wizard to the
/// empty Today). The body copy + prompt-card eyebrow also shifted.
struct ScrWLand: View {
    let name: String
    let onCaptureFirst: () -> Void
    let onLookAround: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Empty name → "You're all set." (no trailing comma + bare
            // period). Filled name → "You're all set, Tom." with italic
            // ochre on the name.
            Group {
                if name.isEmpty {
                    Text("You\u{2019}re all set.")
                        .foregroundColor(Crucible.Color.ink)
                } else {
                    Text("You\u{2019}re all set, ").foregroundColor(Crucible.Color.ink)
                    + Text("\(name).").italic().foregroundColor(Crucible.Color.accent)
                }
            }
            .font(.system(size: 30, design: .serif))
            .lineSpacing(2)
            .padding(.top, 58)

            Text("HiMem works best when capture is easy. Start with the thought closest to your tongue — or look around first.")
                .font(.system(size: 14.5))
                .foregroundStyle(Crucible.Color.ink2)
                .lineSpacing(4)
                .padding(.top, 12)
                .frame(maxWidth: 280, alignment: .leading)

            VStack(alignment: .leading, spacing: 9) {
                Text("TO GET YOU GOING")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(Crucible.Color.ink3)
                Text("\u{201C}What\u{2019}s something you don\u{2019}t want to forget today?\u{201D}")
                    .font(.system(size: 18, design: .serif))
                    .italic()
                    .foregroundStyle(Crucible.Color.ink)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Crucible.Color.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Crucible.Color.hairline, lineWidth: 1)
                    )
            )
            .padding(.top, 26)

            Spacer(minLength: 0)

            // Action-first footer. Primary: ochre fill + mic + shadow.
            // Secondary: hairline-outlined transparent. Stacked, 12pt gap.
            VStack(spacing: 12) {
                Button(action: onCaptureFirst) {
                    HStack(spacing: 10) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 19, weight: .semibold))
                        Text("Capture your first memory")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Crucible.Color.accent)
                    )
                    .foregroundStyle(Crucible.Color.accentInk)
                    .shadow(color: Crucible.Color.accent.opacity(0.28), radius: 12, x: 0, y: 8)
                }

                Button(action: onLookAround) {
                    Text("Later — let me look around")
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 15)
                                .stroke(Crucible.Color.hairline, lineWidth: 1)
                        )
                        .foregroundStyle(Crucible.Color.ink2)
                }
            }
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Required blocked

struct ScrRequiredBlock: View {
    let reason: RequiredPermission
    let onRetry: () -> Void
    let onBack: () -> Void

    private var copy: BlockedCopy {
        switch reason {
        case .apple:
            return BlockedCopy(
                step: 1, glyph: AnyView(Image(systemName: "applelogo").font(.system(size: 28, weight: .semibold))),
                title: "Let\u{2019}s finish signing in.",
                why: "HiMem keeps your memories private and synced through your Apple account. Without it, there\u{2019}s nowhere safe to put them.",
                cta: "Try again with Apple",
                foot: "Cancelled by mistake? One tap and you\u{2019}re back.",
                fix: .retry
            )
        case .mic:
            return BlockedCopy(
                step: 2, glyph: G.mic.image,
                title: "HiMem can\u{2019}t hear you yet.",
                why: "The microphone is how every memory gets captured. There\u{2019}s no version of HiMem without it.",
                cta: "Open Settings",
                foot: "Switch it on, come back, and we\u{2019}ll pick up right where you left off.",
                fix: .settings(label: "Microphone")
            )
        case .speech:
            return BlockedCopy(
                step: 3, glyph: G.speech.image,
                title: "Your words need transcription.",
                why: "Speech recognition turns what you say into text you can read and search. It\u{2019}s core to how HiMem works.",
                cta: "Open Settings",
                foot: "Switch it on, come back, and we\u{2019}ll pick up right where you left off.",
                fix: .settings(label: "Speech Recognition")
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            WizardTopBar(step: copy.step, skippable: false, showBack: true, onBack: onBack, onSkip: nil)

            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 19)
                        .fill(Crucible.Color.warnTint)
                        .frame(width: 68, height: 68)
                        .overlay(copy.glyph.foregroundStyle(Crucible.Color.warn))
                    Circle()
                        .fill(Crucible.Color.warn)
                        .frame(width: 26, height: 26)
                        .overlay(
                            Circle()
                                .stroke(Crucible.Color.paper, lineWidth: 2.5)
                        )
                        .overlay(
                            Text("!")
                                .font(.system(size: 15, weight: .heavy, design: .serif))
                                .foregroundStyle(.white)
                        )
                        .offset(x: 5, y: 5)
                }
                .padding(.top, 40)

                Text(copy.title)
                    .font(.system(size: 27, design: .serif))
                    .fontWeight(.regular)
                    .lineSpacing(2)
                    .foregroundStyle(Crucible.Color.ink)
                    .padding(.top, 22)

                Text(copy.why)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Crucible.Color.ink2)
                    .lineSpacing(4)
                    .padding(.top, 12)
                    .frame(maxWidth: 280, alignment: .leading)

                Text("Needed to continue")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Crucible.Color.warnInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Crucible.Color.warnTint))
                    .padding(.top, 16)

                if case .settings(let label) = copy.fix {
                    settingsExplainer(label: label)
                        .padding(.top, 22)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 26)

            VStack(spacing: 10) {
                Text(copy.foot)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Crucible.Color.ink3)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)

                Button(action: onRetry) {
                    Text(copy.cta)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 14)
                            .fill(copy.fix.ctaBackground))
                        .foregroundStyle(copy.fix.ctaForeground)
                }
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 30)
        }
    }

    private func settingsExplainer(label: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("TWO TAPS IN SETTINGS")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(Crucible.Color.ink3)
            settingsRow(index: 1, leading: "Settings", trailing: "HiMem")
            settingsRow(index: 2, leading: label, trailing: "On")
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Crucible.Color.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Crucible.Color.hairline, lineWidth: 1)
                )
        )
    }

    private func settingsRow(index: Int, leading: String, trailing: String) -> some View {
        HStack(spacing: 9) {
            Text("\(index)")
                .font(.system(size: 10, weight: .bold))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Crucible.Color.sunk))
                .foregroundStyle(Crucible.Color.ink3)
            (Text("Tap ").foregroundColor(Crucible.Color.ink2)
             + Text(leading).fontWeight(.semibold).foregroundColor(Crucible.Color.ink)
             + Text(" → turn ").foregroundColor(Crucible.Color.ink2)
             + Text(trailing).fontWeight(.semibold).foregroundColor(Crucible.Color.ink))
                .font(.system(size: 13))
        }
    }
}

private struct BlockedCopy {
    let step: Int
    let glyph: AnyView
    let title: String
    let why: String
    let cta: String
    let foot: String
    let fix: BlockedFix

    enum BlockedFix {
        case retry
        case settings(label: String)
    }
}

private extension BlockedCopy.BlockedFix {
    var ctaBackground: SwiftUI.Color {
        switch self {
        case .retry: return Crucible.Color.ink
        case .settings: return Crucible.Color.accent
        }
    }
    var ctaForeground: SwiftUI.Color {
        switch self {
        case .retry: return .white
        case .settings: return Crucible.Color.accentInk
        }
    }
}

// MARK: - Reinstall · Restore from iCloud
//
// Shown only on the reinstall path (Apple Sign In returned nil
// fullName + iCloud KV had a stored userName). The permission cascade
// is bypassed entirely per the locked spec — anything iOS revoked on
// uninstall is re-requested in context at first capture, not as a
// fresh wall of 7 pages. The restore screen honestly covers the
// CloudKit catch-up window by showing the user the true thing:
// memories coming back, counted as they land.

/// Restoring state — live count + indeterminate progress bar. Auto-
/// advances to ScrReinstallRestoreDone when 5s pass with no
/// `NSPersistentStoreRemoteChange` events; the parent runs that state
/// machine via `.task { runRestoreStateMachine() }`.
struct ScrReinstallRestore: View {
    let name: String
    let count: Int
    let onKeepGoing: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Crucible.Color.accentTint)
                    .frame(width: 64, height: 64)
                restoreGlyph
                    .foregroundStyle(Crucible.Color.accent)
            }
            .padding(.top, 56)

            (Text("Welcome back, ").foregroundColor(Crucible.Color.ink)
             + Text(displayName).italic().foregroundColor(Crucible.Color.accent))
                .font(.system(size: 30, design: .serif))
                .lineSpacing(2)
                .padding(.top, 22)

            Text("Bringing your memories back from iCloud. They\u{2019}ll keep arriving even after you go in.")
                .font(.system(size: 14.5))
                .foregroundStyle(Crucible.Color.ink2)
                .lineSpacing(4)
                .padding(.top, 12)
                .frame(maxWidth: 280, alignment: .leading)

            // Hero count — the true, reassuring thing.
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(count)")
                        .font(.system(size: 56, design: .serif))
                        .fontWeight(.regular)
                        .monospacedDigit()
                        .foregroundStyle(Crucible.Color.ink)
                    Text("memories back so far")
                        .font(.system(size: 15))
                        .foregroundStyle(Crucible.Color.ink2)
                }
                IndeterminateBar()
                    .frame(height: 4)
                Text("Counting up as they land — on a new device this can take a moment.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Crucible.Color.ink3)
                    .lineSpacing(2)
            }
            .padding(.top, 34)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button(action: onKeepGoing) {
                    Text("Keep going while it finishes")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(RoundedRectangle(cornerRadius: 15)
                            .fill(Crucible.Color.accent))
                        .foregroundStyle(Crucible.Color.accentInk)
                }
                Text("The rest keep arriving in the background. Nothing waits on this screen.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Crucible.Color.ink3)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 8)
            }
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity)
    }

    private var displayName: String {
        name.isEmpty ? "you" : "\(name)."
    }

    private var restoreGlyph: some View {
        // Soft cloud + downward return arrow — memories coming home.
        // Matches the SVG geometry in the spec's RestoreGlyph component.
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: 7, y: 18))
                p.addCurve(to: CGPoint(x: 6.5, y: 10.03),
                           control1: CGPoint(x: 4.5, y: 18),
                           control2: CGPoint(x: 3, y: 13))
                p.addCurve(to: CGPoint(x: 17.1, y: 8.48),
                           control1: CGPoint(x: 7.5, y: 5),
                           control2: CGPoint(x: 15.5, y: 5))
                p.addCurve(to: CGPoint(x: 17.5, y: 16),
                           control1: CGPoint(x: 20, y: 10),
                           control2: CGPoint(x: 21, y: 14))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
            Path { p in
                p.move(to: CGPoint(x: 12, y: 11))
                p.addLine(to: CGPoint(x: 12, y: 18))
                p.move(to: CGPoint(x: 9, y: 15))
                p.addLine(to: CGPoint(x: 12, y: 18))
                p.addLine(to: CGPoint(x: 15, y: 15))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 32, height: 32)
    }
}

/// Settled state — restore quieted (no remote-change events for 5s).
/// Parent auto-advances to Today via `.task { runRestoreDoneAutoAdvance }`
/// after a brief confirmation beat. The "Go to HiMem" button is the
/// user's manual shortcut for the same advance.
struct ScrReinstallRestoreDone: View {
    let finalCount: Int
    let onGo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Crucible.Color.confirmedTint)
                    .frame(width: 64, height: 64)
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Crucible.Color.confirmed)
            }
            .padding(.top, 56)

            Text("That\u{2019}s everything.")
                .font(.system(size: 30, design: .serif))
                .fontWeight(.regular)
                .lineSpacing(2)
                .foregroundStyle(Crucible.Color.ink)
                .padding(.top, 22)

            Text("Your Memory Box is whole again. Picking up right where you left off.")
                .font(.system(size: 14.5))
                .foregroundStyle(Crucible.Color.ink2)
                .lineSpacing(4)
                .padding(.top, 12)
                .frame(maxWidth: 280, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(finalCount)")
                    .font(.system(size: 56, design: .serif))
                    .fontWeight(.regular)
                    .monospacedDigit()
                    .foregroundStyle(Crucible.Color.ink)
                Text("memories restored")
                    .font(.system(size: 15))
                    .foregroundStyle(Crucible.Color.ink2)
            }
            .padding(.top, 34)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button(action: onGo) {
                    Text("Go to HiMem")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(RoundedRectangle(cornerRadius: 15)
                            .fill(Crucible.Color.accent))
                        .foregroundStyle(Crucible.Color.accentInk)
                }
                Text("Taking you in\u{2026}")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Crucible.Color.ink3)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity)
    }
}

/// Indeterminate-progress bar — slides a fixed-width capsule across the
/// track on infinite repeat. No percent, no fake countdown. Matches the
/// spec's `wrBar` keyframe animation.
private struct IndeterminateBar: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Crucible.Color.sunk)
                Capsule()
                    .fill(Crucible.Color.accent)
                    .frame(width: geo.size.width * 0.32)
                    .offset(x: geo.size.width * phase)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.0
                }
            }
        }
    }
}
