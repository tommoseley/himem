import AppIntents
import Foundation

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

        Task.detached {
            await ProcessingEngine.shared.processEntry(entry)
        }

        return .result(dialog: "Got it. Saved to HiMem.")
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
                "Note in \(.applicationName)",
                "New entry in \(.applicationName)",
                "Record in \(.applicationName)",
            ],
            shortTitle: "Capture a thought",
            systemImageName: "text.bubble"
        )
    }
}
