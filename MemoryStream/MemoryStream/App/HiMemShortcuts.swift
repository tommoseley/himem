import AppIntents
import Foundation

// MARK: - Create Entry Intent

struct CreateEntryIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture a thought in Hi Mem"
    static var description: IntentDescription = "Save a journal entry to Hi Mem"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "What happened?", requestValueDialog: "What do you want to remember?")
    var text: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let storage = StorageService.shared

        let entry = try storage.createEntry(
            content: text,
            inputType: .siri
        )
        let _ = try storage.createProcessingTask(for: entry)

        Task.detached {
            await ProcessingEngine.shared.processEntry(entry)
        }

        return .result(dialog: "Got it. Saved to Hi Mem.")
    }
}

// MARK: - App Shortcuts

struct HiMemShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateEntryIntent(),
            phrases: [
                "Capture in \(.applicationName)",
                "Log in \(.applicationName)",
                "Save to \(.applicationName)",
                "Remember in \(.applicationName)",
                "New entry in \(.applicationName)",
            ],
            shortTitle: "Capture a thought",
            systemImageName: "text.bubble"
        )
    }
}
