import SwiftUI
import CoreData

struct LaunchScreenView: View {
    let onStorageReady: () -> Void
    let onComplete: () -> Void

    @State private var storageLoaded = false
    @State private var syncProgress: CGFloat = 0
    @State private var syncDone = false
    @State private var epigraph = ""
    @State private var epigraphSource = ""

    // Choreography — all start false, fade in on schedule
    @State private var showGreeting = false
    @State private var showMoment = false
    @State private var showProgress = false
    @State private var showFooter = false

    // Design tokens
    private let ochre = Color(red: 0xC6/255, green: 0x4A/255, blue: 0x1C/255)
    private let ink = Color(red: 0x1A/255, green: 0x16/255, blue: 0x12/255)
    private let bg = Color(red: 0xEF/255, green: 0xEC/255, blue: 0xE5/255)

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let time: String
        switch hour {
        case 0..<12: time = "Good morning"
        case 12..<17: time = "Good afternoon"
        default: time = "Good evening"
        }
        let name = AuthService.shared.userName
        if !name.isEmpty && name != "there" {
            return "\(time), \(name)"
        }
        return time
    }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Greeting — 0ms start
                HStack(spacing: 8) {
                    Circle()
                        .fill(ochre)
                        .frame(width: 5, height: 5)
                    Text(greeting)
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(ink.opacity(0.55))
                }
                .opacity(showGreeting ? 1 : 0)
                .padding(.top, 14)

                // Wordmark — 80ms start (always structurally present for layout)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Hi")
                        .font(.custom("Georgia-Bold", size: 64))
                        .foregroundStyle(ink)
                    Text("Mem")
                        .font(.custom("Georgia-Italic", size: 64))
                        .foregroundStyle(ochre)
                }
                .padding(.top, 18)

                // Moment (epigraph) — 220ms start
                VStack(alignment: .leading, spacing: 10) {
                    if !epigraph.isEmpty {
                        Text("\u{201C}\(epigraph)\u{201D}")
                            .font(.custom("Georgia-Italic", size: 19))
                            .foregroundStyle(ink.opacity(0.72))
                            .lineSpacing(19 * 0.45)
                            .frame(maxWidth: 280, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !epigraphSource.isEmpty {
                        Text(epigraphSource.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(ink.opacity(0.42))
                    }
                }
                .opacity(showMoment ? 1 : 0)
                .padding(.top, 12)

                Spacer()

                // Footer: cloud status + progress hairline — 520ms start
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "cloud")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(ink.opacity(0.42))
                            .frame(width: 22, height: 22)

                        Text(syncDone
                             ? "Ready"
                             : "Syncing your bin \u{00B7} iCloud")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ink.opacity(0.55))
                    }

                    // Progress hairline — 360ms start
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
                    .opacity(showProgress ? 1 : 0)
                }
                .opacity(showFooter ? 1 : 0)
            }
            .padding(.top, 70)
            .padding(.horizontal, 28)
            .padding(.bottom, 36)
        }
        .onAppear { runChoreography() }
    }

    // MARK: - Choreography: ~1500ms sequence

    private func runChoreography() {
        // Load epigraph from cache immediately (no storage needed)
        let selected = EpigraphService.shared.todaysEpigraphWithSource(entryCount: 0)
        epigraph = selected.text
        epigraphSource = selected.source

        // Greeting — 0ms
        withAnimation(.easeIn(duration: 0.2)) { showGreeting = true }

        // Wordmark is always visible (matches storyboard)

        // Moment — 220ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.easeIn(duration: 0.25)) { showMoment = true }
        }

        // Progress hairline — 360ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            withAnimation(.easeIn(duration: 0.2)) { showProgress = true }
        }

        // Footer (cloud status) — 520ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
            withAnimation(.easeIn(duration: 0.2)) { showFooter = true }
        }

        // Start loading storage on background thread at 100ms
        // This is the real work the hairline tracks
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            DispatchQueue.global(qos: .userInitiated).async {
                _ = StorageService.shared
                DispatchQueue.main.async { onStorageLoaded() }
            }
        }
    }

    // MARK: - Storage Ready

    private func onStorageLoaded() {
        storageLoaded = true
        TopicPaletteStore.shared.loadFromCoreData()
        onStorageReady()

        // Update epigraph with real entry count
        let count = EpigraphService.shared.entryCount()
        let accurate = EpigraphService.shared.todaysEpigraphWithSource(entryCount: count)
        if accurate.text != epigraph {
            epigraph = accurate.text
            epigraphSource = accurate.source
        }
        EpigraphService.shared.refreshFromAPI()

        // Animate progress to 70%
        withAnimation(.easeInOut(duration: 0.8)) { syncProgress = 0.7 }

        // Watch for CloudKit import completion — this drives the handoff
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: StorageService.shared.container,
            queue: .main
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
            // type 1 = import
            if event.type.rawValue == 1 && event.succeeded {
                completeSync()
            }
        }

        // If entries already exist (sync happened during store load), complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if !syncDone && EpigraphService.shared.entryCount() > 0 {
                completeSync()
            }
        }

        // Safety net — if CloudKit never reports, hand off after 4s total
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if !syncDone { completeSync() }
        }
    }

    // MARK: - Handoff

    private func completeSync() {
        guard !syncDone else { return }
        syncDone = true
        withAnimation(.easeInOut(duration: 0.3)) { syncProgress = 1.0 }

        // Brief hold so the user sees "Ready", then fade to feed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeInOut(duration: 0.3)) {
                onComplete()
            }
        }
    }
}
