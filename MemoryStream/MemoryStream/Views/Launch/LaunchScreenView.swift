import SwiftUI
import CoreData

struct LaunchScreenView: View {
    let onStorageReady: () -> Void
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
    @State private var showEpigraph = false
    @State private var showSyncBar = false

    private let ochre = Color(red: 0xC6/255, green: 0x4A/255, blue: 0x1C/255)

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        // iOS 16+ returns just "iPhone"/"iPad" for privacy.
        // Use first name from device owner if available, otherwise omit name.
        let deviceName = UIDevice.current.name
        let isGeneric = deviceName == "iPhone" || deviceName == "iPad"
            || deviceName == "iPod touch"

        let nameClean: String? = isGeneric ? nil : deviceName
            .replacingOccurrences(of: "\u{2019}s iPhone", with: "")
            .replacingOccurrences(of: "'s iPhone", with: "")
            .replacingOccurrences(of: "\u{2019}s iPad", with: "")
            .replacingOccurrences(of: "'s iPad", with: "")
            .trimmingCharacters(in: .whitespaces)

        let timeGreeting: String
        switch hour {
        case 0..<12: timeGreeting = "Good morning"
        case 12..<17: timeGreeting = "Good afternoon"
        default: timeGreeting = "Good evening"
        }

        if let name = nameClean, !name.isEmpty {
            return "\(timeGreeting), \(name)."
        }
        return "\(timeGreeting)."
    }

    var body: some View {
        ZStack {
            Color(red: 0xEF/255, green: 0xEC/255, blue: 0xE5/255)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top spacing — push content to ~35% from top
                Spacer().frame(height: UIScreen.main.bounds.height * 0.22)

                // Greeting with ochre dot
                if showGreeting {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ochre)
                            .frame(width: 5, height: 5)
                        Text(greeting)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(red: 0x1A/255, green: 0x16/255, blue: 0x12/255).opacity(0.5))
                    }
                    .transition(.opacity)
                }

                Spacer().frame(height: 20)

                // Wordmark — always visible (matches static launch screen)
                HStack(spacing: 0) {
                    Text("Hi")
                        .font(.custom("Georgia-Bold", size: 64))
                        .foregroundStyle(Color(red: 0x1A/255, green: 0x16/255, blue: 0x12/255))
                    Text("Mem")
                        .font(.custom("Georgia-Italic", size: 64))
                        .foregroundStyle(ochre)
                }

                Spacer().frame(height: 28)

                // Epigraph
                if showEpigraph, !epigraph.isEmpty {
                    VStack(spacing: 10) {
                        Text("\u{201C}\(epigraph)\u{201D}")
                            .font(.custom("Georgia-Italic", size: 15))
                            .foregroundStyle(Color(red: 0x1A/255, green: 0x16/255, blue: 0x12/255).opacity(0.55))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 48)

                        if !epigraphSource.isEmpty {
                            Text(epigraphSource.uppercased())
                                .font(.system(size: 9, weight: .medium))
                                .tracking(2)
                                .foregroundStyle(Color(red: 0x1A/255, green: 0x16/255, blue: 0x12/255).opacity(0.3))
                        }
                    }
                    .transition(.opacity)
                }

                Spacer()

                // Sync status + progress hairline at bottom
                if showSyncBar {
                    VStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text(syncStatus)
                                .font(.system(size: 11))
                                .foregroundStyle(Color(red: 0x1A/255, green: 0x16/255, blue: 0x12/255).opacity(0.3))
                            if !syncDetail.isEmpty {
                                Text("\u{00B7}")
                                    .foregroundStyle(Color(red: 0x1A/255, green: 0x16/255, blue: 0x12/255).opacity(0.3))
                                Text(syncDetail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(red: 0x1A/255, green: 0x16/255, blue: 0x12/255).opacity(0.3))
                            }
                        }

                        // Progress hairline
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Color(red: 0x1A/255, green: 0x16/255, blue: 0x12/255).opacity(0.08))
                                .frame(height: 1)
                                .overlay(alignment: .leading) {
                                    Rectangle()
                                        .fill(ochre.opacity(0.6))
                                        .frame(width: geo.size.width * syncProgress, height: 1)
                                }
                        }
                        .frame(height: 1)
                    }
                    .padding(.horizontal, 40)
                    .transition(.opacity)
                }

                Spacer().frame(height: 48)
            }
        }
        .onAppear {
            startLaunchSequence()
        }
    }

    // MARK: - Choreography

    private func startLaunchSequence() {
        // Load epigraph from cache first (no Core Data needed)
        let selected = EpigraphService.shared.todaysEpigraphWithSource(entryCount: 0)
        epigraph = selected.text
        epigraphSource = selected.source

        // Staggered fade-in — choreography starts immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeIn(duration: 0.3)) { showGreeting = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeIn(duration: 0.35)) { showEpigraph = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeIn(duration: 0.25)) { showSyncBar = true }
        }

        // Initialize Core Data + CloudKit on a background thread
        // so the UI choreography isn't blocked by store loading.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            DispatchQueue.global(qos: .userInitiated).async {
                // loadPersistentStores is synchronous and can take 1-2s
                _ = StorageService.shared
                DispatchQueue.main.async {
                    self.initializeStorage()
                }
            }
        }

        // Minimum display: full choreography + time to read epigraph
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            minimumTimeElapsed = true
            checkComplete()
        }

        // Maximum wait — never hold longer than 5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            finishLaunch()
        }
    }

    private func initializeStorage() {
        // StorageService.shared already initialized on background thread
        TopicPaletteStore.shared.loadFromCoreData()
        onStorageReady()

        // Update epigraph with accurate entry count
        let count = EpigraphService.shared.entryCount()
        let accurate = EpigraphService.shared.todaysEpigraphWithSource(entryCount: count)
        if accurate.text != epigraph {
            epigraph = accurate.text
            epigraphSource = accurate.source
        }
        EpigraphService.shared.refreshFromAPI()

        // Start progress animation
        withAnimation(.easeInOut(duration: 1.5)) {
            syncProgress = 0.7
        }

        // Observe CloudKit sync — all StorageService refs are safe now
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: StorageService.shared.container,
            queue: .main
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
            if event.type.rawValue == 1 && event.succeeded {
                self.syncComplete = true
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.syncProgress = 1.0
                    self.syncStatus = "Ready"
                    self.syncDetail = ""
                }
            }
        }

        // Check if sync already completed during store loading
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !self.syncComplete {
                let entryCount = EpigraphService.shared.entryCount()
                if entryCount > 0 {
                    self.syncComplete = true
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.syncProgress = 1.0
                        self.syncStatus = "Ready"
                        self.syncDetail = ""
                    }
                }
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
