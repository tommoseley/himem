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
        /// PhotoKit local identifier (image / video) or audio file path
        /// (voice). Used to render the tile (look up the asset) and play
        /// audio for voice captures.
        let osIdentifier: String
        /// Duration in seconds for `.voice` / `.video`, `nil` otherwise.
        /// Populated by the UI layer when the recording stops; required for
        /// the silent-discard rule to apply.
        let duration: TimeInterval?
        /// For `.voice` captures only: the transcript produced by SFSpeech.
        /// Travels with the voice clip — the discard summary counts a voice
        /// capture as one "voice clip", not as a "note", so transcripts are
        /// not double-counted.
        let transcript: String?
    }

    // MARK: - Published state

    /// Public-set so SwiftUI's `.sheet(isPresented:)` Binding can write back
    /// when the sheet dismisses on its own (rare with interactiveDismissDisabled
    /// on the host, but the compiler needs write access for the binding type).
    @Published var isPresented = false
    @Published private(set) var anchor: Anchor = .newMemory
    @Published private(set) var entryId: UUID? = nil
    @Published private(set) var sessionCaptures: [SessionCapture] = []
    /// Notes added via the **Note** button. Voice transcripts live on the
    /// voice SessionCapture itself, not here, so a voice clip with a
    /// transcript is counted as one capture (not as a clip + a note) in the
    /// discard summary.
    @Published private(set) var sessionTypedNotes: [String] = []
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
        self.sessionTypedNotes = []
        self.activeCapture = autoStartVoice ? .voice : nil
        self.showDiscardConfirmation = false
        self.isPresented = true
    }

    /// Exits the session, preserving captured content. For new-memory anchors,
    /// applies the silent-discard rule (trivial-clip cases delete the entry
    /// without surfacing anything to the user).
    ///
    /// On the keep path, folds all in-session voice transcripts + typed notes
    /// into entry.content and enqueues a ProcessingTask so the AI engine
    /// extracts entities/topics. Without this step the entry would land in
    /// the journal feed with no content text and no inferences.
    func exitDone() {
        if shouldSilentlyDiscard {
            performDiscard()
            return
        }
        if let entryId {
            let added = finalizeContent
            // captureLocation only on new-memory finalization — append flows
            // already inherit the existing entry's location (or its absence).
            let isNewMemoryAnchor: Bool = { if case .newMemory = anchor { return true } else { return false } }()
            lifecycle.finalizeContribution(entryId: entryId, addedContent: added, captureLocation: isNewMemoryAnchor)
        }
        teardown()
    }

    /// Joins voice-capture transcripts and typed notes into a single string
    /// to fold into entry.content. Voice transcripts come first (since
    /// short-press auto-starts voice — they tend to be the user's first
    /// thought), then typed notes in capture order.
    private var finalizeContent: String {
        var parts: [String] = []
        for capture in sessionCaptures {
            if let transcript = capture.transcript, !transcript.isEmpty {
                parts.append(transcript)
            }
        }
        parts.append(contentsOf: sessionTypedNotes)
        return parts.joined(separator: "\n\n")
    }

    /// Asks for confirmation if the session has substantive content and the
    /// user hasn't muted the prompt. Sessions with only trivial captures
    /// (e.g. an autostart-voice clip <2s with no transcript that landed
    /// because the user immediately tapped X) discard silently — the
    /// confirmation exists to prevent losing real work, not to interrogate
    /// fat-fingers.
    func requestExitDiscard() {
        if !hasSubstantiveContent {
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

    func trackCapture(
        id: UUID,
        mediaType: MediaReference.MediaType,
        osIdentifier: String,
        duration: TimeInterval? = nil,
        transcript: String? = nil
    ) {
        sessionCaptures.append(SessionCapture(
            id: id,
            mediaType: mediaType,
            osIdentifier: osIdentifier,
            duration: duration,
            transcript: transcript
        ))
    }

    /// Adds a typed note (Note button). Voice transcripts are NOT routed here
    /// — they travel with the voice SessionCapture so the discard summary
    /// can count voice clips and notes separately.
    func trackTypedNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sessionTypedNotes.append(trimmed)
    }

    /// Persists a photo or video capture: lazy-creates the entry if needed,
    /// attaches the corresponding MediaReference, tracks it for X-cleanup.
    /// `localIdentifier` is the PhotoKit asset id returned by
    /// `CameraService.savePhoto` / `saveVideo`. `duration` is non-nil for
    /// videos so the silent-discard rule can apply.
    func persistMediaCapture(localIdentifier: String, mediaType: MediaReference.MediaType, duration: TimeInterval? = nil) {
        do {
            let entryId = try ensureEntryForCapture(inputType: .camera)
            let ref = try lifecycle.createMediaReference(forEntryId: entryId, localIdentifier: localIdentifier, mediaType: mediaType)
            trackCapture(id: ref.id, mediaType: mediaType, osIdentifier: localIdentifier, duration: duration)
        } catch {
            ErrorState.shared.report(.mediaError(error.localizedDescription))
        }
    }

    /// Persists a voice capture: lazy-creates the entry if needed, attaches a
    /// `.voice` MediaReference whose transcript travels with it on the
    /// SessionCapture struct (so the discard summary can count clips and
    /// notes separately). If `saveAudio` is false (user pref
    /// `saveVoiceEntries: false`), the audio file is deleted and the
    /// transcript is stored as a typed note instead — there's no voice
    /// capture for it to attach to.
    func persistVoiceCapture(audioPath: String?, transcript: String, duration: TimeInterval, saveAudio: Bool) {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let audioPath, saveAudio {
                let entryId = try ensureEntryForCapture(inputType: .voiceInApp)
                let ref = try lifecycle.createMediaReference(
                    forEntryId: entryId,
                    localIdentifier: audioPath,
                    mediaType: .voice,
                    transcript: trimmedTranscript.isEmpty ? nil : trimmedTranscript
                )
                trackCapture(
                    id: ref.id,
                    mediaType: .voice,
                    osIdentifier: audioPath,
                    duration: duration,
                    transcript: trimmedTranscript.isEmpty ? nil : trimmedTranscript
                )
            } else {
                if let audioPath { AudioPlayerService.deleteAudio(filename: audioPath) }
                if !trimmedTranscript.isEmpty {
                    // No voice clip to attach to → the transcript becomes
                    // a standalone typed note.
                    trackTypedNote(trimmedTranscript)
                }
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
        sessionCaptures.isEmpty && sessionTypedNotes.isEmpty
    }

    /// True if the session contains anything the user would care about
    /// losing on X. Photos, videos, and typed notes always count
    /// (deliberate gestures). Voice clips count when they have a
    /// transcript OR ran for at least 2 seconds — a short transcript-less
    /// voice clip is the auto-start-then-immediate-X failure mode and
    /// shouldn't trigger a confirmation.
    private var hasSubstantiveContent: Bool {
        if !sessionTypedNotes.isEmpty { return true }
        for capture in sessionCaptures {
            switch capture.mediaType {
            case .image, .video:
                return true
            case .voice:
                if let transcript = capture.transcript, !transcript.isEmpty { return true }
                if let duration = capture.duration, duration >= 2.0 { return true }
            }
        }
        return false
    }

    /// Spec: a new-memory session that ends with **exactly one** voice/video
    /// capture, that capture **shorter than 2 seconds**, and **no other
    /// captures** (no photos, no notes), is silently discarded. Anything else
    /// is preserved. Existing-memory sessions never silent-discard.
    private var shouldSilentlyDiscard: Bool {
        guard case .newMemory = anchor else { return false }
        guard sessionTypedNotes.isEmpty else { return false }
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
        sessionTypedNotes = []
        entryId = nil
    }
}
