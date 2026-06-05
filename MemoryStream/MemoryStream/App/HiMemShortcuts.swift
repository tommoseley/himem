import AppIntents
import Foundation
import Combine

// MARK: - Capture-request bus

/// In-process signal that something (today: a Siri AppIntent) asked
/// HiMem to open its voice composer. `JournalView` observes
/// `pendingVoiceRecord` and, when it flips true, presents the voice
/// composer (which auto-starts recording on appear). View clears the
/// flag after handling so the next intent invocation re-triggers.
///
/// Lives in-process because AppIntents with `openAppWhenRun: true`
/// run in the app's main process after launch — no cross-process /
/// UserDefaults plumbing is necessary.
@MainActor
final class CaptureRequestBus: ObservableObject {
    static let shared = CaptureRequestBus()
    @Published var pendingVoiceRecord: Bool = false
    private init() {}
}

// MARK: - Start Voice Recording Intent

struct StartVoiceRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Record a memory in HiMem"
    static var description: IntentDescription = "Open HiMem and start recording a voice memory."
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        CaptureRequestBus.shared.pendingVoiceRecord = true
        return .result(dialog: "Recording.")
    }
}

// MARK: - Create Entry Intent

struct CreateEntryIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture a thought in HiMem"
    static var description: IntentDescription = "Save a journal entry to HiMem"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "What happened?")
    var text: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let content: String
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            content = text
        } else {
            content = try await $text.requestValue("What do you want to remember?")
        }

        let storage = StorageService.shared
        let entry = try storage.createEntry(
            content: content,
            inputType: .siri
        )
        let _ = try storage.createProcessingTask(for: entry)

        // Auto-organize the captured note for Plus subscribers; Free
        // users keep manual control via the Memory Detail Organize
        // button.
        Task.detached {
            let shouldProcess: Bool = await MainActor.run { Entitlement.shared.isPlus }
            guard shouldProcess else { return }
            await ProcessingEngine.shared.processEntry(entry)
        }

        return .result(dialog: "Got it. Saved to HiMem.")
    }
}

// MARK: - App Shortcuts

struct HiMemShortcuts: AppShortcutsProvider {
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
        AppShortcut(
            intent: CreateEntryIntent(),
            phrases: [
                "Capture in \(.applicationName)",
                "Log in \(.applicationName)",
                "Save to \(.applicationName)",
                "Remember in \(.applicationName)",
                "Note in \(.applicationName)",
                "New entry in \(.applicationName)",
            ],
            shortTitle: "Capture a thought",
            systemImageName: "text.bubble"
        )
    }
}
