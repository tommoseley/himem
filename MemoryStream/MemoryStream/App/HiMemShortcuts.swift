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
    /// Legacy Siri flag — kept for the `StartVoiceRecordingIntent`
    /// backward-compat path. New code should prefer `pendingModality`
    /// which carries the modality explicitly.
    @Published var pendingVoiceRecord: Bool = false
    /// Any modality request from a shared surface (the tab-level
    /// AppendFAB, Siri, App Shortcuts). The HiMemTabView owns the
    /// capture flow now — per the July 10 2026 lock in
    /// `HiMem · evidence and context.md:143`, capture floats on
    /// every tab and returns to Clips on commit.
    @Published var pendingModality: CaptureModality? = nil
    /// Set by `StopVoiceRecordingIntent` ("Hey Siri, stop recording in HiMem")
    /// so the phone isn't the only way to stop a hands-free recording. The live
    /// voice composer observes this and stops-and-saves (never discards). No-op
    /// when no recording is in flight.
    @Published var stopRequested: Bool = false
    /// Stamped by the composer the moment it stops-and-saves a hands-free
    /// recording (Siri stop or cap), so `StopVoiceRecordingIntent` can speak the
    /// real duration. Rounded minutes (min 1). Nil = nothing saved yet.
    var lastSavedMinutes: Int? = nil
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

// MARK: - Stop Voice Recording Intent

/// "Hey Siri, stop recording in HiMem" — stops and saves the in-flight voice
/// recording (never discards, same rule as watch wrist-off). `openAppWhenRun`
/// so the intent runs in the app process and the in-memory `CaptureRequestBus`
/// reaches the live composer; the app is already foreground while recording, so
/// this doesn't yank the user anywhere.
struct StopVoiceRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop recording in HiMem"
    static var description: IntentDescription = "Stop and save the voice recording HiMem is capturing."
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let bus = CaptureRequestBus.shared
        bus.lastSavedMinutes = nil
        bus.stopRequested = true
        // Wait briefly for the live composer to stop-and-stamp the duration, so
        // the spoken confirmation carries the real length (same string a
        // cap-triggered save uses — the limit never reads as an error).
        for _ in 0..<30 {
            if let minutes = bus.lastSavedMinutes {
                return .result(dialog: "\(VoiceCaptureScreen.savedConfirmation(minutes: minutes))")
            }
            try? await Task.sleep(nanoseconds: 50_000_000) // 50 ms × 30 = 1.5 s
        }
        // Nothing was recording — don't claim a save.
        return .result(dialog: "Nothing was recording.")
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
            intent: StopVoiceRecordingIntent(),
            phrases: [
                "Stop recording in \(.applicationName)",
                "Stop the recording in \(.applicationName)",
                "Finish recording in \(.applicationName)",
            ],
            shortTitle: "Stop recording",
            systemImageName: "stop.fill"
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
