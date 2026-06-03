import SwiftUI
import AuthenticationServices
import AVFoundation
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
                    case .land:         ScrWLand(name: auth.userName, onEnter: onComplete)
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
            why: "Himem captures by voice — on your phone and your Watch.",
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
            example: "Snap the whiteboard before it\u{2019}s erased — it lands in Himem.",
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
            why: "Himem tags captures with a place — only while you\u{2019}re using it.",
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
        auth.handleSignInResult(result)
        if auth.isAuthenticated {
            withWizardAnim {
                editedName = auth.userName.isEmpty ? "" : auth.userName
                step = .name
            }
        } else if case .failure = result {
            // User cancelled or sheet errored. The Apple sheet can be
            // re-presented in place; route to the blocked screen so the
            // user gets the calm "try again" surface rather than a stuck
            // first page.
            withWizardAnim { blockedReason = .apple }
        }
    }

    private func nameComplete() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            auth.userName = trimmed
            _ = KeychainService.shared.save(key: "userName", value: trimmed)
        }
        withWizardAnim { step = .mic }
    }

    // MARK: - Permission handlers

    private func handleMic() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        if granted {
            withWizardAnim { step = .speech }
        } else {
            withWizardAnim { blockedReason = .mic }
        }
    }

    private func handleSpeech() async {
        let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in cont.resume(returning: status) }
        }
        if status == .authorized {
            withWizardAnim { step = .photos }
        } else {
            withWizardAnim { blockedReason = .speech }
        }
    }

    private func handlePhotos() async {
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        // Optional permission — advance regardless of grant.
        withWizardAnim { step = .camera }
    }

    private func handleCamera() async {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        withWizardAnim { step = .location }
    }

    private func handleLocation() async {
        // No async API for location; request and move on. iOS shows the
        // system dialog. Status is read elsewhere when location is used.
        await MainActor.run {
            CLLocationManager().requestWhenInUseAuthorization()
        }
        try? await Task.sleep(nanoseconds: 200_000_000) // brief beat so the user sees the dialog before the transition
        withWizardAnim { step = .notifications }
    }

    private func handleNotifications() async {
        if notifyClipsOn || notifyNudgeOn {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        }
        // Persist Channel B preference; Channel A is implicit.
        UserDefaults.standard.set(notifyNudgeOn, forKey: NotificationService.Keys.notifyDailyNudge)
        withWizardAnim { step = .land }
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

    /// Visible step number on the progress rail (Apple + Name are both step 1).
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
                    Text("Required to use Himem")
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
            WizardTopBar(step: 1, skippable: false, showBack: false, onBack: nil, onSkip: nil)

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
                .padding(.top, 48)

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
                           body: "Himem listens for the thread. You stay in control.")
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

struct ScrWLand: View {
    let name: String
    let onEnter: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text("You\u{2019}re all set, ").foregroundColor(Crucible.Color.ink)
             + Text("\(name.isEmpty ? "" : name).").italic().foregroundColor(Crucible.Color.accent))
                .font(.system(size: 29, design: .serif))
                .lineSpacing(2)
                .padding(.top, 60)

            Text("Your bin is empty — which is exactly right. The best first capture is the one closest to your tongue right now.")
                .font(.system(size: 14.5))
                .foregroundStyle(Crucible.Color.ink2)
                .lineSpacing(4)
                .padding(.top, 12)
                .frame(maxWidth: 280, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
                Text("A SMALL PROMPT")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(Crucible.Color.ink3)
                Text("\u{201C}What\u{2019}s something you don\u{2019}t want to forget today?\u{201D}")
                    .font(.system(size: 16, design: .serif))
                    .italic()
                    .foregroundStyle(Crucible.Color.ink)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Crucible.Color.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Crucible.Color.hairline, lineWidth: 1)
                    )
            )
            .padding(.top, 28)

            Spacer(minLength: 0)

            Button("Later — let me look around", action: onEnter)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Crucible.Color.ink2)
                .padding(.bottom, 26)
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
                why: "Himem keeps your memories private and synced through your Apple account. Without it, there\u{2019}s nowhere safe to put them.",
                cta: "Try again with Apple",
                foot: "Cancelled by mistake? One tap and you\u{2019}re back.",
                fix: .retry
            )
        case .mic:
            return BlockedCopy(
                step: 2, glyph: G.mic.image,
                title: "Himem can\u{2019}t hear you yet.",
                why: "The microphone is how every memory gets captured. There\u{2019}s no version of Himem without it.",
                cta: "Open Settings",
                foot: "Switch it on, come back, and we\u{2019}ll pick up right where you left off.",
                fix: .settings(label: "Microphone")
            )
        case .speech:
            return BlockedCopy(
                step: 3, glyph: G.speech.image,
                title: "Your words need transcription.",
                why: "Speech recognition turns what you say into text you can read and search. It\u{2019}s core to how Himem works.",
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
            settingsRow(index: 1, leading: "Settings", trailing: "Himem")
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
