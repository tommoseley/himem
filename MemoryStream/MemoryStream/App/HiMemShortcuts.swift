import AppIntents
import Foundation
import Combine

// MARK: - Capture-request bus

/// In-process signal that a shared surface asked HiMem to open a composer.
///
/// **The Siri RECORDING flags are gone (2026-09-18).** `pendingVoiceRecord`,
/// `stopRequested` and `lastSavedMinutes` existed for
/// `StartVoiceRecordingIntent` / `StopVoiceRecordingIntent`, which folded into
/// `CreateEntryIntent` — Siri already transcribes, so a spoken capture keeps
/// the words and discards the recording, which is what `CreateEntryIntent`
/// has always done.
///
/// Lives in-process because AppIntents with `openAppWhenRun: true` run in the
/// app's main process after launch — no cross-process plumbing needed.
@MainActor
final class CaptureRequestBus: ObservableObject {
    static let shared = CaptureRequestBus()
    /// Any modality request from a shared surface (the tab-level AppendFAB,
    /// App Shortcuts). `HiMemTabView` owns the capture flow.
    @Published var pendingModality: CaptureModality? = nil
    private init() {}
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
            intent: CreateEntryIntent(),
            // **The recording phrases folded in here (2026-09-18).** They
            // belonged to `StartVoiceRecordingIntent`, which opened the app and
            // ran the recorder. The words are the artifact and Siri already
            // transcribes, so "Record in HiMem" and "Capture in HiMem" are one
            // operation — and this one is BETTER at it: `openAppWhenRun: false`
            // means it works from the lock screen without HiMem coming
            // forward, which is closer to the perishability principle than
            // launching an app to hold a microphone.
            phrases: [
                "Capture in \(.applicationName)",
                "Log in \(.applicationName)",
                "Save to \(.applicationName)",
                "Remember in \(.applicationName)",
                "Note in \(.applicationName)",
                "New entry in \(.applicationName)",
                "Record in \(.applicationName)",
                "Record a memory in \(.applicationName)",
                "Voice memo in \(.applicationName)",
            ],
            shortTitle: "Capture a thought",
            systemImageName: "text.bubble"
        )
    }
}
