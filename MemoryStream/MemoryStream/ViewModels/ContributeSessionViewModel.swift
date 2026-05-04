import Foundation
import Combine

/// Owns the lifecycle of a single Contribute Mode session.
///
/// Two anchors:
///   - `.newMemory` — entry is lazy-created on the first capture. Done with
///     zero captures = nothing to clean up. X always deletes the entry.
///   - `.existingMemory(UUID)` — captures append to the named entry. Pre-
///     existing captures on the entry are untouched by X.
///
/// The session is **not** where captures happen. The UI layer owns
/// `SpeechService`, the camera picker, and the photo library picker; once a
/// capture lands it calls `trackCapture(...)` so the session knows which IDs
/// belong to it (and can delete them on X). This keeps the session focused
/// on lifecycle decisions rather than duplicating capture plumbing.
@MainActor
final class ContributeSessionViewModel: ObservableObject {

    // MARK: - Types

    enum Anchor: Equatable {
        case newMemory
        case existingMemory(UUID)
    }

    /// Which capture-type button on the Action Box is currently active.
    /// Drives the in-button recording-state UI (red dot, waveform, elapsed).
    enum ActiveCapture: Equatable {
        case voice
        case video
        case text
    }

    struct SessionCapture: Equatable {
        let id: UUID
        let mediaType: MediaReference.MediaType
        /// Duration in seconds for `.voice` / `.video`, `nil` otherwise.
        /// Populated by the UI layer when the recording stops; required for
        /// the silent-discard rule to apply.
        let duration: TimeInterval?
    }

    // MARK: - Published state

    @Published private(set) var isPresented = false
    @Published private(set) var anchor: Anchor = .newMemory
    @Published private(set) var entryId: UUID? = nil
    @Published private(set) var sessionCaptures: [SessionCapture] = []
    @Published private(set) var sessionTextSegments: [String] = []
    @Published private(set) var activeCapture: ActiveCapture? = nil
    @Published var showDiscardConfirmation = false

    // MARK: - Dependencies

    private let lifecycle: EntryLifecycleService
    private let userDefaults: UserDefaults

    /// UserDefaults key for "don't ask me again on X-cancel discard." Lives
    /// here so Settings → Confirmations and the inline checkbox both bind to
    /// the same string.
    static let muteDiscardConfirmationKey = "confirmations.discardContribute.muted"

    init(
        lifecycle: EntryLifecycleService,
        userDefaults: UserDefaults = .standard
    ) {
        self.lifecycle = lifecycle
        self.userDefaults = userDefaults
    }

    // MARK: - Enter / exit

    func enter(anchor: Anchor, autoStartVoice: Bool = false) {
        self.anchor = anchor
        switch anchor {
        case .newMemory:
            self.entryId = nil
        case .existingMemory(let id):
            self.entryId = id
        }
        self.sessionCaptures = []
        self.sessionTextSegments = []
        self.activeCapture = autoStartVoice ? .voice : nil
        self.showDiscardConfirmation = false
        self.isPresented = true
    }

    /// Exits the session, preserving captured content. For new-memory anchors,
    /// applies the silent-discard rule (trivial-clip cases delete the entry
    /// without surfacing anything to the user).
    func exitDone() {
        if shouldSilentlyDiscard {
            performDiscard()
            return
        }
        teardown()
    }

    /// Asks for confirmation if the session created any captures and the user
    /// hasn't muted the prompt. Empty sessions and muted users go straight to
    /// discard.
    func requestExitDiscard() {
        if isSessionEmpty {
            performDiscard()
            return
        }
        if userDefaults.bool(forKey: Self.muteDiscardConfirmationKey) {
            performDiscard()
            return
        }
        showDiscardConfirmation = true
    }

    /// Called when the user taps Discard in the confirmation alert.
    /// `muteFutureConfirmations: true` writes the mute pref so subsequent
    /// X-cancels skip the dialog (unmutable in Settings → Confirmations).
    func confirmDiscard(muteFutureConfirmations: Bool) {
        if muteFutureConfirmations {
            userDefaults.set(true, forKey: Self.muteDiscardConfirmationKey)
        }
        performDiscard()
    }

    // MARK: - Capture tracking

    /// Returns the id of the entry to attach captures to. For new-memory
    /// anchors, lazy-creates the entry on first call and remembers it.
    /// `inputType` is taken from the first capture (so a voice-first session
    /// gets `.voiceInApp`, a typed-first one gets `.typed`, etc.). Subsequent
    /// calls return the same id regardless of inputType.
    func ensureEntryForCapture(inputType: JournalEntry.InputType) throws -> UUID {
        if let id = entryId { return id }
        let entry = try lifecycle.createEmptyEntry(inputType: inputType)
        entryId = entry.id
        return entry.id
    }

    func trackCapture(id: UUID, mediaType: MediaReference.MediaType, duration: TimeInterval? = nil) {
        sessionCaptures.append(SessionCapture(id: id, mediaType: mediaType, duration: duration))
    }

    func trackTextSegment(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sessionTextSegments.append(trimmed)
    }

    /// Persists a voice capture: lazy-creates the entry if needed, attaches a
    /// `.voice` MediaReference, tracks it for X-cleanup, and stores the
    /// transcript as a session text segment. If `saveAudio` is false (user
    /// pref `saveVoiceEntries: false`), the audio file is deleted but the
    /// transcript is still recorded.
    func persistVoiceCapture(audioPath: String?, transcript: String, duration: TimeInterval, saveAudio: Bool) {
        do {
            if let audioPath {
                if saveAudio {
                    let entryId = try ensureEntryForCapture(inputType: .voiceInApp)
                    let ref = try lifecycle.createMediaReference(forEntryId: entryId, localIdentifier: audioPath, mediaType: .voice)
                    trackCapture(id: ref.id, mediaType: .voice, duration: duration)
                } else {
                    AudioPlayerService.deleteAudio(filename: audioPath)
                }
            }
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                trackTextSegment(trimmed)
            }
        } catch {
            ErrorState.shared.report(.saveFailed(error.localizedDescription))
        }
    }

    /// UI sets the active-capture indicator when a recording starts and
    /// clears it when the recording stops. The session view model itself
    /// doesn't manage the recording — it just reflects the state for the
    /// Action Box's per-button UI.
    func setActiveCapture(_ capture: ActiveCapture?) {
        activeCapture = capture
    }

    // MARK: - Predicates

    private var isSessionEmpty: Bool {
        sessionCaptures.isEmpty && sessionTextSegments.isEmpty
    }

    /// Spec: a new-memory session that ends with **exactly one** voice/video
    /// capture, that capture **shorter than 2 seconds**, and **no other
    /// captures** (no photos, no text), is silently discarded. Anything else
    /// is preserved. Existing-memory sessions never silent-discard.
    private var shouldSilentlyDiscard: Bool {
        guard case .newMemory = anchor else { return false }
        guard sessionTextSegments.isEmpty else { return false }
        guard sessionCaptures.count == 1 else { return false }

        let only = sessionCaptures[0]
        let isAVMedia = only.mediaType == .voice || only.mediaType == .video
        let isShort = (only.duration ?? .infinity) < 2.0
        return isAVMedia && isShort
    }

    // MARK: - Private

    private func performDiscard() {
        let captureIds = Set(sessionCaptures.map(\.id))
        if !captureIds.isEmpty {
            lifecycle.deleteMediaReferences(ids: captureIds)
        }
        // For new-memory, the entry only exists because this session created
        // it (lazy-create). Safe to delete unconditionally on discard.
        // For existing-memory, the entry pre-exists; we leave it alone.
        if case .newMemory = anchor, let entryId {
            lifecycle.delete(entryId: entryId)
        }
        teardown()
    }

    private func teardown() {
        isPresented = false
        showDiscardConfirmation = false
        activeCapture = nil
        sessionCaptures = []
        sessionTextSegments = []
        entryId = nil
    }
}
