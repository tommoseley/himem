import AppIntents
import Foundation
import Combine

/// Watch-side capture-request bus. Same purpose as the iPhone's
/// `CaptureRequestBus`: lets a Siri AppIntent ("Record in HiMem")
/// flip a flag that `WatchRootView` observes to route into the
/// recording screen (which auto-starts the recorder on appear).
///
/// In-process because watchOS App Intents with `openAppWhenRun: true`
/// run in the watch app's main process after launch — no shared
/// UserDefaults plumbing required for the intent ↔ view handoff.
@MainActor
final class WatchCaptureRequestBus: ObservableObject {
    static let shared = WatchCaptureRequestBus()
    @Published var pendingVoiceRecord: Bool = false
    private init() {}
}

/// Siri-invokable intent that opens the watch app and lands on the
/// recording surface with the mic hot. Distinct from the complication
/// tap, which deliberately stops at the Tap-to-Record page so a
/// stray wrist-bump on the watch face never commits audio to the
/// pending list. A voice command is deliberate, so we auto-start.
struct StartVoiceRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Record a memory in HiMem"
    static var description: IntentDescription = "Open HiMem and start recording a voice memory."
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        WatchCaptureRequestBus.shared.pendingVoiceRecord = true
        return .result(dialog: "Recording.")
    }
}

struct WatchHimemShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartVoiceRecordingIntent(),
            phrases: [
                "Record in \(.applicationName)",
                "Record a memory in \(.applicationName)",
                "Start recording in \(.applicationName)",
                "Voice memo in \(.applicationName)",
            ],
            shortTitle: "Record a memory",
            systemImageName: "mic.fill"
        )
    }
}
