import SwiftUI
import CoreData

struct LaunchScreenView: View {
    let onStorageReady: () -> Void
    let onComplete: () -> Void

    @State private var syncComplete = false
    @State private var minimumTimeElapsed = false
    @State private var syncProgress: CGFloat = 0
    @State private var epigraph = ""
    @State private var epigraphSource = ""

    // Choreography states
    @State private var showGreeting = false
    @State private var showEpigraph = false
    @State private var showFooter = false

    // Design system colors
    private let ochre = Color(red: 0xC6/255, green: 0x4A/255, blue: 0x1C/255)
    private let ink = Color(red: 0x1A/255, green: 0x16/255, blue: 0x12/255)
    private let bg = Color(red: 0xEF/255, green: 0xEC/255, blue: 0xE5/255)

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let deviceName = UIDevice.current.name
        let isGeneric = deviceName == "iPhone" || deviceName == "iPad"
            || deviceName == "iPod touch"
        let nameClean: String? = isGeneric ? nil : deviceName
            .replacingOccurrences(of: "\u{2019}s iPhone", with: "")
            .replacingOccurrences(of: "'s iPhone", with: "")
            .replacingOccurrences(of: "\u{2019}s iPad", with: "")
            .replacingOccurrences(of: "'s iPad", with: "")
            .trimmingCharacters(in: .whitespaces)
        let time: String
        switch hour {
        case 0..<12: time = "Good morning"
        case 12..<17: time = "Good afternoon"
        default: time = "Good evening"
        }
        if let name = nameClean, !name.isEmpty { return "\(time), \(name)" }
        return time
    }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            // Main content — flex column, left-aligned
            // padding: 70px 28px 36px from design
            VStack(alignment: .leading, spacing: 0) {
                // Greeting — margin-top: 14px, font-size: 13px, weight: 600
                if showGreeting {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(ochre)
                            .frame(width: 5, height: 5)
                        Text(greeting)
                            .font(.system(size: 13, weight: .semibold))
                            .tracking(0.4)
                            .foregroundStyle(ink.opacity(0.55))
                    }
                    .padding(.top, 14)
                    .transition(.opacity)
                }

                // Wordmark — margin-top: 18px, font-size: 64px
                // font: "Source Serif 4", Georgia, serif
                // letter-spacing: -1.6px
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Hi")
                        .font(.custom("Georgia-Bold", size: 64))
                        .tracking(-1.6)
                        .foregroundStyle(ink)
                    Text("Mem")
                        .font(.custom("Georgia-Italic", size: 64))
                        .tracking(-1.6)
                        .foregroundStyle(ochre)
                }
                .padding(.top, 18)

                // Epigraph (moment) — margin-top: 12px, font-size: 19px
                // font: Georgia italic, weight: 300, line-height: 1.45
                // max-width: 280px, color: ink 0.72
                if showEpigraph, !epigraph.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\u{201C}\(epigraph)\u{201D}")
                            .font(.custom("Georgia-Italic", size: 19))
                            .foregroundStyle(ink.opacity(0.72))
                            .lineSpacing(19 * 0.45)
                            .frame(maxWidth: 280, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)

                        // Attribution — font-size: 11px, weight: 600
                        // letter-spacing: 1.4px, uppercase, color: ink 0.42
                        if !epigraphSource.isEmpty {
                            Text(epigraphSource.uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(1.4)
                                .foregroundStyle(ink.opacity(0.42))
                        }
                    }
                    .padding(.top, 12)
                    .transition(.opacity)
                }

                Spacer()

                // Footer — absolute bottom: 36px, left: 28px, right: 28px
                if showFooter {
                    VStack(alignment: .leading, spacing: 12) {
                        // Cloud status — font-size: 12px, weight: 500, color: ink 0.55
                        HStack(spacing: 12) {
                            // Cloud icon placeholder
                            Image(systemName: "cloud")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(ink.opacity(0.42))
                                .frame(width: 22, height: 22)

                            Text(syncComplete
                                 ? "Ready"
                                 : "Syncing your bin \u{00B7} iCloud")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(ink.opacity(0.55))
                        }

                        // Progress hairline — height: 2px, full width
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(ink.opacity(0.08))
                                .frame(height: 2)
                                .overlay(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(
                                            LinearGradient(
                                                colors: [ochre.opacity(0.25), ochre],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: geo.size.width * syncProgress, height: 2)
                                }
                        }
                        .frame(height: 2)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.top, 70)
            .padding(.horizontal, 28)
            .padding(.bottom, 36)
        }
        .onAppear {
            startLaunchSequence()
        }
    }

    // MARK: - Choreography

    private func startLaunchSequence() {
        // Load epigraph from cache (no Core Data needed yet)
        let selected = EpigraphService.shared.todaysEpigraphWithSource(entryCount: 0)
        epigraph = selected.text
        epigraphSource = selected.source

        // Staggered fade-in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeIn(duration: 0.3)) { showGreeting = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeIn(duration: 0.35)) { showEpigraph = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeIn(duration: 0.25)) { showFooter = true }
        }

        // Initialize Core Data + CloudKit on background thread
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            DispatchQueue.global(qos: .userInitiated).async {
                _ = StorageService.shared
                DispatchQueue.main.async {
                    self.initializeStorage()
                }
            }
        }

        // Minimum display
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            minimumTimeElapsed = true
            checkComplete()
        }

        // Maximum wait
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            finishLaunch()
        }
    }

    private func initializeStorage() {
        TopicPaletteStore.shared.loadFromCoreData()
        onStorageReady()

        // Update epigraph with accurate entry count
        let count = EpigraphService.shared.entryCount()
        let accurate = EpigraphService.shared.todaysEpigraphWithSource(entryCount: count)
        if accurate.text != epigraph {
            withAnimation(.easeInOut(duration: 0.3)) {
                epigraph = accurate.text
                epigraphSource = accurate.source
            }
        }
        EpigraphService.shared.refreshFromAPI()

        // Start progress animation
        withAnimation(.easeInOut(duration: 1.5)) {
            syncProgress = 0.7
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
                self.syncComplete = true
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.syncProgress = 1.0
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
