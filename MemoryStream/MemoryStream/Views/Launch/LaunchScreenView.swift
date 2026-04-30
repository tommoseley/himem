import SwiftUI
import CoreData

struct LaunchScreenView: View {
    let onComplete: () -> Void

    @State private var syncComplete = false
    @State private var minimumTimeElapsed = false
    @State private var syncProgress: CGFloat = 0
    @State private var syncStatus = "Syncing your bin"
    @State private var syncDetail = "Cloud"
    @State private var epigraph = ""
    @State private var epigraphSource = ""

    // Choreography states
    @State private var showGreeting = false
    @State private var showWordmark = false
    @State private var showEpigraph = false
    @State private var showSyncBar = false

    private let ochre = Color(red: 0xC6/255, green: 0x4A/255, blue: 0x1C/255)
    private let ochreLight = Color(red: 0xD4/255, green: 0xA5/255, blue: 0x74/255)

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
            Crucible.Color.sunk
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Greeting with ochre dot
                if showGreeting {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ochre)
                            .frame(width: 6, height: 6)
                        Text(greeting)
                            .font(.subheadline)
                            .foregroundStyle(Crucible.Color.ink3)
                    }
                    .transition(.opacity)
                }

                Spacer().frame(height: 28)

                // Wordmark
                if showWordmark {
                    HStack(spacing: 0) {
                        Text("Hi")
                            .font(.custom("Georgia-Bold", size: 56))
                            .foregroundStyle(Crucible.Color.ink)
                        Text("Mem")
                            .font(.custom("Georgia-Italic", size: 56))
                            .foregroundStyle(ochre)
                    }
                    .transition(.opacity)
                }

                Spacer().frame(height: 24)

                // Epigraph
                if showEpigraph, !epigraph.isEmpty {
                    VStack(spacing: 8) {
                        Text("\u{201C}\(epigraph)\u{201D}")
                            .font(.custom("Georgia-Italic", size: 15))
                            .foregroundStyle(Crucible.Color.ink2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 44)

                        if !epigraphSource.isEmpty {
                            Text(epigraphSource.uppercased())
                                .font(.system(size: 10, weight: .medium))
                                .tracking(1.5)
                                .foregroundStyle(Crucible.Color.ink4)
                        }
                    }
                    .transition(.opacity)
                }

                Spacer()

                // Sync status + progress hairline
                if showSyncBar {
                    VStack(spacing: 10) {
                        HStack(spacing: 4) {
                            Text(syncStatus)
                                .font(.caption2)
                                .foregroundStyle(Crucible.Color.ink4)
                            Text("·")
                                .foregroundStyle(Crucible.Color.ink4)
                            Text(syncDetail)
                                .font(.caption2)
                                .foregroundStyle(Crucible.Color.ink4)
                        }

                        // Progress hairline — full width
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Crucible.Color.ink4.opacity(0.2))
                                .frame(height: 1)
                                .overlay(alignment: .leading) {
                                    Rectangle()
                                        .fill(ochre)
                                        .frame(width: geo.size.width * syncProgress, height: 1)
                                }
                        }
                        .frame(height: 1)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    .transition(.opacity)
                }
            }
            .padding(.bottom, 40)
        }
        .onAppear {
            startLaunchSequence()
        }
    }

    // MARK: - Choreography

    private func startLaunchSequence() {
        // Load epigraph data
        let count = EpigraphService.shared.entryCount()
        let selected = EpigraphService.shared.todaysEpigraphWithSource(entryCount: count)
        epigraph = selected.text
        epigraphSource = selected.source
        EpigraphService.shared.refreshFromAPI()

        // Staggered fade-in (~1500ms total)
        // Greeting: 50ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeIn(duration: 0.25)) { showGreeting = true }
        }

        // Wordmark: 200ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeIn(duration: 0.4)) { showWordmark = true }
        }

        // Epigraph: 650ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            withAnimation(.easeIn(duration: 0.3)) { showEpigraph = true }
        }

        // Sync bar: 950ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            withAnimation(.easeIn(duration: 0.2)) { showSyncBar = true }
        }

        // Progress animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 1.2)) {
                syncProgress = 0.7
            }
        }

        // Minimum display time
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            minimumTimeElapsed = true
            checkComplete()
        }

        // Maximum wait
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            finishLaunch()
        }

        // Observe CloudKit sync
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
                    syncDetail = ""
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
