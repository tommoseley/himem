import SwiftUI
import AuthenticationServices
import AVFoundation
import UserNotifications

struct OnboardingView: View {
    let onComplete: () -> Void
    @StateObject private var auth = AuthService.shared
    @State private var currentPage = 0
    @State private var selectedTopics: Set<String> = []

    private let ink = Color(red: 0x1A/255, green: 0x16/255, blue: 0x12/255)
    private let ochre = Color(red: 0xC6/255, green: 0x4A/255, blue: 0x1C/255)
    private let bg = Color(red: 0xEF/255, green: 0xEC/255, blue: 0xE5/255)

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
                .font(.system(size: 11))
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ink)
            Text(subtitle)
                .font(.system(size: 14))
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
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ink.opacity(0.45))
            }
            .padding(.top, 16)

            Spacer().frame(height: 40)

            Text("A few things we\u{2019}ll need.")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(ink)

            Spacer().frame(height: 8)

            Text("Permissions stay between you and your phone. We never see them.")
                .font(.system(size: 15))
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
                    .font(.system(size: 17, weight: .semibold))
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
                    .font(.system(size: 18))
                    .foregroundStyle(ochre)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(ink)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(ochre)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(ochre.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 13))
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
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ink.opacity(0.45))
            }
            .padding(.top, 16)

            Spacer().frame(height: 40)

            Text("What\u{2019}s on your mind these days?")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(ink)

            Spacer().frame(height: 8)

            Text("Pick a few. We\u{2019}ll group your captures by these. You can change them anytime.")
                .font(.system(size: 15))
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
                .font(.system(size: 13))
                .foregroundStyle(ink.opacity(0.4))

            Spacer()

            // Continue button
            Button(action: onContinue) {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold))
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
                .font(.system(size: 15, weight: .medium))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 100)

            // Welcome
            Text("Hi \(userName),")
                .font(.custom("Georgia-Italic", size: 32))
                .foregroundStyle(ink)
            Text("welcome.")
                .font(.custom("Georgia-Italic", size: 32))
                .foregroundStyle(ink)

            Spacer().frame(height: 20)

            Text("Your bin is empty. The best first capture is the one closest to your tongue right now.")
                .font(.system(size: 16))
                .foregroundStyle(ink.opacity(0.6))
                .lineSpacing(4)

            Spacer().frame(height: 32)

            // Prompt card
            VStack(alignment: .leading, spacing: 12) {
                Text("A small prompt")
                    .font(.system(size: 12, weight: .medium))
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(ochre)
                    .cornerRadius(12)
            }

            Spacer().frame(height: 12)

            Button(action: onContinue) {
                Text("Later \u{2014} let me look around")
                    .font(.system(size: 14))
                    .foregroundStyle(ink.opacity(0.4))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            Spacer().frame(height: 32)
        }
        .padding(.horizontal, 28)
    }
}
