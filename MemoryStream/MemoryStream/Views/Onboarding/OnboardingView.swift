import SwiftUI
import AuthenticationServices
import AVFoundation
import CoreLocation
import UserNotifications

struct OnboardingView: View {
    let onComplete: () -> Void
    @ObservedObject private var auth = AuthService.shared
    @State private var currentPage = 0
    @State private var selectedTopics: Set<String> = []

    // Design tokens — aliased from the Crucible catalog so
    // onboarding adapts to dark mode automatically.
    private let ink = Crucible.Color.ink
    private let ochre = Crucible.Color.accent
    private let bg = Crucible.Color.paper

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            switch currentPage {
            case 0:
                WelcomeScreen(ink: ink, ochre: ochre) {
                    auth.handleSignInResult($0)
                    if auth.isAuthenticated {
                        withAnimation(.easeInOut(duration: 0.3)) { currentPage = 1 }
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))

            case 1:
                PermissionsScreen(ink: ink, ochre: ochre) {
                    withAnimation(.easeInOut(duration: 0.3)) { currentPage = 2 }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))

            case 2:
                TopicsScreen(ink: ink, ochre: ochre, selectedTopics: $selectedTopics) {
                    saveTopics()
                    withAnimation(.easeInOut(duration: 0.3)) { currentPage = 3 }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))

            case 3:
                LandingScreen(ink: ink, ochre: ochre, userName: auth.userName) {
                    onComplete()
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))

            default:
                EmptyView()
            }
        }
    }

    private func saveTopics() {
        guard !selectedTopics.isEmpty else { return }
        let storage = StorageService.shared
        for name in selectedTopics {
            let paletteKey = TopicPaletteStore.shared.key(for: name)
            let _ = try? storage.findOrCreateTopic(name: name, paletteKey: paletteKey)
        }
    }
}

// MARK: - Screen 1: Welcome

private struct WelcomeScreen: View {
    let ink: Color
    let ochre: Color
    let onSignIn: (Result<ASAuthorization, Error>) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 80)

            // Wordmark
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Hi")
                    .font(.custom("Georgia-Bold", size: 48))
                    .foregroundStyle(ink)
                Text("Mem")
                    .font(.custom("Georgia-Italic", size: 48))
                    .foregroundStyle(ochre)
            }

            Spacer().frame(height: 16)

            // Tagline
            Text("Your bin for half-formed thoughts, voice notes, and the things you\u{2019}ll want to remember.")
                .font(.custom("Georgia-Italic", size: 17))
                .foregroundStyle(ink.opacity(0.72))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 36)

            // Feature pills
            VStack(alignment: .leading, spacing: 16) {
                FeaturePill(
                    title: "Capture anything.",
                    subtitle: "Voice, text, photo, video \u{2014} drop it in.",
                    ink: ink
                )
                FeaturePill(
                    title: "Inferred quietly.",
                    subtitle: "We listen for patterns. You stay in control.",
                    ink: ink
                )
                FeaturePill(
                    title: "Yours, end to end.",
                    subtitle: "Synced privately with iCloud.",
                    ink: ink
                )
            }

            Spacer()

            // Sign in with Apple
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                onSignIn(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 52)
            .cornerRadius(12)

            Spacer().frame(height: 12)

            // Terms & Privacy
            Text("By continuing, you agree to our Terms & Privacy")
                .font(.caption2)
                .foregroundStyle(ink.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .center)

            Spacer().frame(height: 32)
        }
        .padding(.horizontal, 28)
    }
}

private struct FeaturePill: View {
    let title: String
    let subtitle: String
    let ink: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(ink)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(ink.opacity(0.55))
        }
    }
}

// MARK: - Screen 2: Permissions

private struct PermissionsScreen: View {
    let ink: Color
    let ochre: Color
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Skip button
            HStack {
                Spacer()
                Button("Skip") { onContinue() }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(ink.opacity(0.45))
            }
            .padding(.top, 16)

            Spacer().frame(height: 40)

            Text("A few things we\u{2019}ll need.")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(ink)

            Spacer().frame(height: 8)

            Text("Permissions stay between you and your phone. We never see them.")
                .font(.subheadline)
                .foregroundStyle(ink.opacity(0.55))

            Spacer().frame(height: 32)

            // Permission rows
            VStack(spacing: 0) {
                PermissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    subtitle: "So we can capture what you say.",
                    badge: "Required",
                    ink: ink, ochre: ochre
                ) {
                    AVAudioSession.sharedInstance().requestRecordPermission { _ in }
                }

                Divider().padding(.leading, 52)

                PermissionRow(
                    icon: "camera.fill",
                    title: "Camera",
                    subtitle: "Snap a photo or video into a memory.",
                    badge: nil,
                    ink: ink, ochre: ochre
                ) {
                    AVCaptureDevice.requestAccess(for: .video) { _ in }
                }

                Divider().padding(.leading, 52)

                PermissionRow(
                    icon: "bell.fill",
                    title: "Notifications",
                    subtitle: "A small nudge when an inference needs you.",
                    badge: nil,
                    ink: ink, ochre: ochre
                ) {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
                }

                Divider().padding(.leading, 52)

                PermissionRow(
                    icon: "location.fill",
                    title: "Location",
                    subtitle: "Tag where you were so you can find memories by place.",
                    badge: nil,
                    ink: ink, ochre: ochre
                ) {
                    Task { await LocationService.shared.requestWhenInUseAuthorization() }
                }

                Divider().padding(.leading, 52)

                PermissionRow(
                    icon: "photo.fill",
                    title: "Photo library",
                    subtitle: "Pull in pictures alongside your notes.",
                    badge: nil,
                    ink: ink, ochre: ochre
                ) {
                    // Deferred — iOS prompts on first use
                }
            }

            Spacer()

            // Continue button
            Button(action: onContinue) {
                Text("Continue")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(ink)
                    .cornerRadius(12)
            }

            Spacer().frame(height: 32)
        }
        .padding(.horizontal, 28)
        .task {
            await cascadePermissionPrompts()
        }
    }

    /// Walks the permissions list serially so iOS shows one system prompt at
    /// a time. Tapping a row remains a manual fallback; this just removes the
    /// "user hits Continue and nothing was actually asked" failure mode.
    private func cascadePermissionPrompts() async {
        for prompt in Self.permissionPrompts {
            if await prompt.isUndetermined() {
                await prompt.request()
            }
        }
        // Photo library remains deferred — iOS prompts on first picker use.
    }

    /// Table-driven permission cascade. Each entry exposes its own
    /// "is undetermined?" check and request callback so the loop above
    /// stays a 4-line walker; adding a new prompt is one entry, no branch.
    private static let permissionPrompts: [PermissionPrompt] = [
        PermissionPrompt(
            label: "microphone",
            isUndetermined: { AVAudioApplication.shared.recordPermission == .undetermined },
            request: { _ = await AVAudioApplication.requestRecordPermission() }
        ),
        PermissionPrompt(
            label: "camera",
            isUndetermined: { AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined },
            request: { _ = await AVCaptureDevice.requestAccess(for: .video) }
        ),
        PermissionPrompt(
            label: "notifications",
            isUndetermined: {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                return settings.authorizationStatus == .notDetermined
            },
            request: {
                _ = try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .badge, .sound])
            }
        ),
        PermissionPrompt(
            label: "location",
            isUndetermined: { CLLocationManager().authorizationStatus == .notDetermined },
            request: { _ = await LocationService.shared.requestWhenInUseAuthorization() }
        )
    ]
}

struct PermissionPrompt: Sendable {
    let label: String
    let isUndetermined: @Sendable () async -> Bool
    let request: @Sendable () async -> Void
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let badge: String?
    let ink: Color
    let ochre: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18)) // design-token size
                    .foregroundStyle(ochre)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(ink)
                        if let badge {
                            Text(badge)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(ochre)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(ochre.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(ink.opacity(0.5))
                }

                Spacer()
            }
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Screen 3: Topics

private struct TopicsScreen: View {
    let ink: Color
    let ochre: Color
    @Binding var selectedTopics: Set<String>
    let onContinue: () -> Void

    private let topics = ["Content", "Cooking", "Garden", "Work", "Family",
                          "Books", "Travel", "Ideas", "Health", "Money"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Skip button
            HStack {
                Spacer()
                Button("Skip") { onContinue() }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(ink.opacity(0.45))
            }
            .padding(.top, 16)

            Spacer().frame(height: 40)

            Text("What\u{2019}s on your mind these days?")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(ink)

            Spacer().frame(height: 8)

            Text("Pick a few. We\u{2019}ll group your captures by these. You can change them anytime.")
                .font(.subheadline)
                .foregroundStyle(ink.opacity(0.55))

            Spacer().frame(height: 28)

            // Topic grid
            FlowLayout(spacing: 10) {
                ForEach(topics, id: \.self) { topic in
                    TopicChip(
                        name: topic,
                        isSelected: selectedTopics.contains(topic),
                        ink: ink, ochre: ochre
                    ) {
                        if selectedTopics.contains(topic) {
                            selectedTopics.remove(topic)
                        } else if selectedTopics.count < 6 {
                            selectedTopics.insert(topic)
                        }
                    }
                }
            }

            Spacer().frame(height: 20)

            // Count
            Text("\(selectedTopics.count) selected \u{00B7} pick up to 6")
                .font(.caption)
                .foregroundStyle(ink.opacity(0.4))

            Spacer()

            // Continue button
            Button(action: onContinue) {
                Text("Continue")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(ink)
                    .cornerRadius(12)
            }

            Spacer().frame(height: 32)
        }
        .padding(.horizontal, 28)
    }
}

private struct TopicChip: View {
    let name: String
    let isSelected: Bool
    let ink: Color
    let ochre: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(isSelected ? .white : ink.opacity(0.7))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(isSelected ? ochre : ink.opacity(0.06))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// FlowLayout is defined in EntryCardView.swift — reused here

// MARK: - Screen 4: Land in Today

private struct LandingScreen: View {
    let ink: Color
    let ochre: Color
    let userName: String
    let onContinue: () -> Void

    @State private var nameInput: String = ""
    @State private var displayName: String = ""
    @FocusState private var nameFieldFocused: Bool

    private var needsName: Bool {
        userName.isEmpty || userName == "there"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 100)

            // Ask for name if Apple didn't provide it
            if needsName && displayName.isEmpty {
                Text("One quick thing \u{2014}")
                    .font(.custom("Georgia-Italic", size: 24))
                    .foregroundStyle(ink)

                Spacer().frame(height: 12)

                Text("What should we call you?")
                    .font(.subheadline)
                    .foregroundStyle(ink.opacity(0.6))

                Spacer().frame(height: 16)

                TextField("Your first name", text: $nameInput)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(ink)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color.white.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .focused($nameFieldFocused)
                    .onAppear { nameFieldFocused = true }
                    .submitLabel(.done)
                    .onSubmit { saveName() }

                Spacer().frame(height: 16)

                Button(action: saveName) {
                    Text("Continue")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(nameInput.trimmingCharacters(in: .whitespaces).isEmpty ? ink.opacity(0.3) : ink)
                        .cornerRadius(12)
                }
                .disabled(nameInput.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()
            } else {
                // Welcome with name
                let name = displayName.isEmpty ? userName : displayName
                Text("Hi \(name),")
                    .font(.custom("Georgia-Italic", size: 32))
                    .foregroundStyle(ink)
                Text("welcome.")
                    .font(.custom("Georgia-Italic", size: 32))
                    .foregroundStyle(ink)

            Spacer().frame(height: 20)

            Text("Your bin is empty. The best first capture is the one closest to your tongue right now.")
                .font(.subheadline)
                .foregroundStyle(ink.opacity(0.6))
                .lineSpacing(4)

            Spacer().frame(height: 32)

            // Prompt card
            VStack(alignment: .leading, spacing: 12) {
                Text("A small prompt")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(ink.opacity(0.4))
                    .tracking(0.5)

                Text("\u{201C}What\u{2019}s something you don\u{2019}t want to forget today?\u{201D}")
                    .font(.custom("Georgia-Italic", size: 17))
                    .foregroundStyle(ink.opacity(0.72))
                    .lineSpacing(4)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer()

            // CTA
            Button(action: onContinue) {
                Text("Tap to capture")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(ochre)
                    .cornerRadius(12)
            }

            Spacer().frame(height: 12)

            Button(action: onContinue) {
                Text("Later \u{2014} let me look around")
                    .font(.footnote)
                    .foregroundStyle(ink.opacity(0.4))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            Spacer().frame(height: 32)
            } // else (has name)
        }
        .padding(.horizontal, 28)
    }

    private func saveName() {
        let name = nameInput.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        displayName = name
        let _ = KeychainService.shared.save(key: "userName", value: name)
        AuthService.shared.userName = name
    }
}
