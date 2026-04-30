import SwiftUI
import CoreData

struct LaunchScreenView: View {
    let onComplete: () -> Void

    @State private var syncComplete = false
    @State private var minimumTimeElapsed = false
    @State private var syncProgress: CGFloat = 0
    @State private var syncStatus: String = "Syncing..."
    @State private var epigraph: String = ""
    @State private var showContent = false

    private let ochre = Color(red: 0xD4/255, green: 0xA5/255, blue: 0x74/255)

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = UIDevice.current.name
            .replacingOccurrences(of: "\u{2019}s iPhone", with: "")
            .replacingOccurrences(of: "'s iPhone", with: "")
            .replacingOccurrences(of: "\u{2019}s iPad", with: "")
            .replacingOccurrences(of: "'s iPad", with: "")
        switch hour {
        case 0..<12: return "Good morning, \(name)."
        case 12..<17: return "Good afternoon, \(name)."
        default: return "Good evening, \(name)."
        }
    }

    var body: some View {
        ZStack {
            Crucible.Color.paper
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Greeting
                if showContent {
                    Text(greeting)
                        .font(.subheadline)
                        .foregroundStyle(Crucible.Color.ink3)
                        .transition(.opacity)
                }

                Spacer().frame(height: 24)

                // Wordmark
                HStack(spacing: 0) {
                    Text("Hi")
                        .font(.custom("Iowan Old Style Bold", size: 48))
                        .foregroundStyle(Crucible.Color.ink)
                    Text("Mem")
                        .font(.custom("Iowan Old Style Italic", size: 48))
                        .foregroundStyle(ochre)
                }

                Spacer().frame(height: 20)

                // Epigraph
                if showContent, !epigraph.isEmpty {
                    Text("\u{201C}\(epigraph)\u{201D}")
                        .font(.custom("Iowan Old Style Italic", size: 14))
                        .foregroundStyle(Crucible.Color.ink3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .transition(.opacity)
                }

                Spacer()

                // Progress hairline
                GeometryReader { geo in
                    Rectangle()
                        .fill(ochre.opacity(0.3))
                        .frame(height: 1.5)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(ochre)
                                .frame(width: geo.size.width * syncProgress, height: 1.5)
                        }
                }
                .frame(height: 1.5)
                .padding(.horizontal, 60)

                Spacer().frame(height: 16)

                // Sync status
                if showContent {
                    Text(syncStatus)
                        .font(.caption2)
                        .foregroundStyle(Crucible.Color.ink4)
                        .transition(.opacity)
                }

                Spacer().frame(height: 60)
            }
        }
        .onAppear {
            startLaunchSequence()
        }
    }

    private func startLaunchSequence() {
        // Load epigraph
        let count = EpigraphService.shared.entryCount()
        epigraph = EpigraphService.shared.todaysEpigraph(entryCount: count)
        EpigraphService.shared.refreshFromAPI()

        // Fade in content
        withAnimation(.easeIn(duration: 0.4)) {
            showContent = true
        }

        // Animate progress
        withAnimation(.easeInOut(duration: 1.5)) {
            syncProgress = 0.7
        }

        // Minimum display time
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            minimumTimeElapsed = true
            checkComplete()
        }

        // Maximum wait — don't hold longer than 3s
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            finishLaunch()
        }

        // Observe CloudKit sync completion
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: StorageService.shared.container,
            queue: .main
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
            if event.type.rawValue == 1 && event.succeeded {
                syncComplete = true
                withAnimation(.easeInOut(duration: 0.3)) {
                    syncProgress = 1.0
                    syncStatus = "Ready"
                }
                checkComplete()
            }
        }
    }

    private func checkComplete() {
        guard minimumTimeElapsed, syncComplete else { return }
        finishLaunch()
    }

    private func finishLaunch() {
        withAnimation(.easeInOut(duration: 0.3)) {
            syncProgress = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeInOut(duration: 0.3)) {
                onComplete()
            }
        }
    }
}
