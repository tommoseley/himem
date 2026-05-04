import Testing
import Foundation
import CoreData
@testable import MemoryStream

@MainActor
@Suite(.serialized)
struct ContributeSessionViewModelTests {

    // MARK: - Setup

    /// Each test gets its own in-memory CoreData stack and a UserDefaults
    /// suite isolated from the host's defaults (so the discard-mute pref
    /// can't leak across tests or into the running simulator).
    private func makeFixture() -> (StorageService, EntryLifecycleService, UserDefaults, ContributeSessionViewModel) {
        let storage = StorageService(inMemory: true)
        let lifecycle = EntryLifecycleService(storage: storage, processingEngine: nil)
        let suiteName = "ContributeSessionViewModelTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let session = ContributeSessionViewModel(lifecycle: lifecycle, userDefaults: defaults)
        return (storage, lifecycle, defaults, session)
    }

    private func entryExists(_ id: UUID, in storage: StorageService) -> Bool {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return ((try? storage.viewContext.fetch(request).first) != nil)
    }

    // MARK: - Enter

    @Test func enter_newMemory_clearsEntryAndCaptures() async {
        let (_, _, _, session) = makeFixture()
        session.enter(anchor: .newMemory)

        #expect(session.isPresented == true)
        #expect(session.entryId == nil)
        #expect(session.sessionCaptures.isEmpty)
        #expect(session.sessionTypedNotes.isEmpty)
        #expect(session.activeCapture == nil)
        #expect(session.anchor == .newMemory)
    }

    @Test func enter_existingMemory_setsEntryIdImmediately() async {
        let (_, _, _, session) = makeFixture()
        let id = UUID()
        session.enter(anchor: .existingMemory(id))

        #expect(session.entryId == id)
        #expect(session.anchor == .existingMemory(id))
    }

    @Test func enter_autoStartVoice_setsActiveCaptureToVoice() async {
        let (_, _, _, session) = makeFixture()
        session.enter(anchor: .newMemory, autoStartVoice: true)
        #expect(session.activeCapture == .voice)
    }

    @Test func enter_withoutAutoStart_leavesActiveCaptureNil() async {
        let (_, _, _, session) = makeFixture()
        session.enter(anchor: .newMemory, autoStartVoice: false)
        #expect(session.activeCapture == nil)
    }

    // MARK: - Lazy entry creation

    @Test func ensureEntryForCapture_lazyCreatesOnFirstCall() async throws {
        let (storage, _, _, session) = makeFixture()
        session.enter(anchor: .newMemory)
        #expect(session.entryId == nil)

        let id = try session.ensureEntryForCapture(inputType: .voiceInApp)

        #expect(session.entryId == id)
        #expect(entryExists(id, in: storage))
    }

    @Test func ensureEntryForCapture_returnsSameIdOnSubsequentCalls() async throws {
        let (_, _, _, session) = makeFixture()
        session.enter(anchor: .newMemory)
        let firstId = try session.ensureEntryForCapture(inputType: .voiceInApp)
        let secondId = try session.ensureEntryForCapture(inputType: .typed)
        #expect(firstId == secondId)
    }

    // MARK: - Done — silent-discard rule

    @Test func exitDone_emptyNewMemorySession_makesNoEntry() async {
        let (storage, _, _, session) = makeFixture()
        session.enter(anchor: .newMemory)
        session.exitDone()

        #expect(session.isPresented == false)
        // Lazy-create never fired — there's nothing to clean up.
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        let count = (try? storage.viewContext.count(for: request)) ?? -1
        #expect(count == 0)
    }

    @Test func exitDone_singleSubTwoSecondVoice_silentlyDiscards() async throws {
        let (storage, _, _, session) = makeFixture()
        session.enter(anchor: .newMemory)
        let entryId = try session.ensureEntryForCapture(inputType: .voiceInApp)
        let captureId = UUID()
        session.trackCapture(id: captureId, mediaType: .voice, osIdentifier: "test-id", duration: 1.4)

        session.exitDone()

        #expect(session.isPresented == false)
        #expect(!entryExists(entryId, in: storage))
    }

    @Test func exitDone_singleSubTwoSecondVideo_silentlyDiscards() async throws {
        let (storage, _, _, session) = makeFixture()
        session.enter(anchor: .newMemory)
        let entryId = try session.ensureEntryForCapture(inputType: .camera)
        session.trackCapture(id: UUID(), mediaType: .video, osIdentifier: "test-id", duration: 1.0)

        session.exitDone()
        #expect(!entryExists(entryId, in: storage))
    }

    @Test func exitDone_voiceOverTwoSeconds_keepsEntry() async throws {
        let (storage, _, _, session) = makeFixture()
        session.enter(anchor: .newMemory)
        let entryId = try session.ensureEntryForCapture(inputType: .voiceInApp)
        session.trackCapture(id: UUID(), mediaType: .voice, osIdentifier: "test-id", duration: 5.2)

        session.exitDone()
        #expect(entryExists(entryId, in: storage))
    }

    @Test func exitDone_shortVoiceWithPhoto_keepsEntry() async throws {
        let (storage, _, _, session) = makeFixture()
        session.enter(anchor: .newMemory)
        let entryId = try session.ensureEntryForCapture(inputType: .voiceInApp)
        session.trackCapture(id: UUID(), mediaType: .voice, osIdentifier: "test-id", duration: 1.4)
        session.trackCapture(id: UUID(), mediaType: .image, osIdentifier: "test-id", duration: nil)

        session.exitDone()
        #expect(entryExists(entryId, in: storage))
    }

    @Test func exitDone_shortVoiceWithText_keepsEntry() async throws {
        let (storage, _, _, session) = makeFixture()
        session.enter(anchor: .newMemory)
        let entryId = try session.ensureEntryForCapture(inputType: .voiceInApp)
        session.trackCapture(id: UUID(), mediaType: .voice, osIdentifier: "test-id", duration: 1.4)
        session.trackTypedNote("a thought")

        session.exitDone()
        #expect(entryExists(entryId, in: storage))
    }

    @Test func exitDone_existingMemoryAnchor_neverSilentlyDiscards() async throws {
        // Prove an existing-memory anchor is immune to the silent-discard rule
        // even with a sub-2s lone clip — pre-existing entries belong to the user.
        let (storage, lifecycle, _, session) = makeFixture()
        let preExisting = try lifecycle.createEmptyEntry(inputType: .typed)
        session.enter(anchor: .existingMemory(preExisting.id))
        session.trackCapture(id: UUID(), mediaType: .voice, osIdentifier: "test-id", duration: 0.5)

        session.exitDone()
        #expect(entryExists(preExisting.id, in: storage))
    }

    // MARK: - X — discard with confirmation

    @Test func requestExitDiscard_emptySession_exitsSilently() async {
        let (_, _, _, session) = makeFixture()
        session.enter(anchor: .newMemory)
        session.requestExitDiscard()

        #expect(session.isPresented == false)
        #expect(session.showDiscardConfirmation == false)
    }

    @Test func requestExitDiscard_trivialAutostartVoice_exitsSilently() async throws {
        // Tap FAB → autostart voice → immediately tap X (no transcript,
        // <2s clip). Should NOT prompt — we're not losing real work.
        let (_, _, _, session) = makeFixture()
        session.enter(anchor: .newMemory, autoStartVoice: true)
        _ = try session.ensureEntryForCapture(inputType: .voiceInApp)
        session.trackCapture(id: UUID(), mediaType: .voice, osIdentifier: "trivial.m4a", duration: 0.4, transcript: nil)

        session.requestExitDiscard()

        #expect(session.showDiscardConfirmation == false)
        #expect(session.isPresented == false)
    }

    @Test func requestExitDiscard_voiceWithTranscript_promptsEvenIfShort() async throws {
        // A short voice clip with a transcript still represents real
        // intent — confirm before discarding.
        let (_, _, _, session) = makeFixture()
        session.enter(anchor: .newMemory)
        _ = try session.ensureEntryForCapture(inputType: .voiceInApp)
        session.trackCapture(id: UUID(), mediaType: .voice, osIdentifier: "short.m4a", duration: 1.2, transcript: "Mulch bed 3")

        session.requestExitDiscard()

        #expect(session.showDiscardConfirmation == true)
    }

    @Test func requestExitDiscard_longVoiceNoTranscript_promptsAnyway() async throws {
        // Speech recognition can fail on a real recording. A 5-second clip
        // with no transcript is still real audio the user produced.
        let (_, _, _, session) = makeFixture()
        session.enter(anchor: .newMemory)
        _ = try session.ensureEntryForCapture(inputType: .voiceInApp)
        session.trackCapture(id: UUID(), mediaType: .voice, osIdentifier: "long.m4a", duration: 5.4, transcript: nil)

        session.requestExitDiscard()

        #expect(session.showDiscardConfirmation == true)
    }

    @Test func requestExitDiscard_nonEmptySession_opensConfirmation() async throws {
        let (_, _, _, session) = makeFixture()
        session.enter(anchor: .newMemory)
        _ = try session.ensureEntryForCapture(inputType: .voiceInApp)
        session.trackCapture(id: UUID(), mediaType: .voice, osIdentifier: "test-id", duration: 5.0)

        session.requestExitDiscard()

        #expect(session.isPresented == true)        // still visible behind the alert
        #expect(session.showDiscardConfirmation == true)
    }

    @Test func requestExitDiscard_mutedPref_skipsConfirmation() async throws {
        let (storage, _, defaults, session) = makeFixture()
        defaults.set(true, forKey: ContributeSessionViewModel.muteDiscardConfirmationKey)
        session.enter(anchor: .newMemory)
        let entryId = try session.ensureEntryForCapture(inputType: .voiceInApp)
        session.trackCapture(id: UUID(), mediaType: .voice, osIdentifier: "test-id", duration: 5.0)

        session.requestExitDiscard()

        #expect(session.showDiscardConfirmation == false)
        #expect(session.isPresented == false)
        #expect(!entryExists(entryId, in: storage))
    }

    @Test func confirmDiscard_writesPref_whenAsked() async throws {
        let (_, _, defaults, session) = makeFixture()
        session.enter(anchor: .newMemory)
        _ = try session.ensureEntryForCapture(inputType: .voiceInApp)
        session.trackCapture(id: UUID(), mediaType: .voice, osIdentifier: "test-id", duration: 5.0)
        session.requestExitDiscard()

        session.confirmDiscard(muteFutureConfirmations: true)

        #expect(defaults.bool(forKey: ContributeSessionViewModel.muteDiscardConfirmationKey) == true)
    }

    @Test func confirmDiscard_doesNotWritePref_whenNotAsked() async throws {
        let (_, _, defaults, session) = makeFixture()
        session.enter(anchor: .newMemory)
        _ = try session.ensureEntryForCapture(inputType: .voiceInApp)
        session.trackCapture(id: UUID(), mediaType: .voice, osIdentifier: "test-id", duration: 5.0)
        session.requestExitDiscard()

        session.confirmDiscard(muteFutureConfirmations: false)

        #expect(defaults.bool(forKey: ContributeSessionViewModel.muteDiscardConfirmationKey) == false)
    }

    /// VM-level invariant: discard on an existing-memory anchor must NOT
    /// delete the entry. Pre-existing-vs-session media partitioning is
    /// covered by EntryLifecycleServiceTests.deleteMediaReferences_*.
    @Test func confirmDiscard_existingMemory_keepsTheEntry() async throws {
        let (storage, lifecycle, _, session) = makeFixture()
        let preExisting = try lifecycle.createEmptyEntry(inputType: .typed)
        session.enter(anchor: .existingMemory(preExisting.id))
        // Track a synthetic capture id — VM doesn't need a real Core Data
        // row to make its keep-or-delete-the-entry decision.
        session.trackCapture(id: UUID(), mediaType: .image, osIdentifier: "test-id")

        session.requestExitDiscard()
        session.confirmDiscard(muteFutureConfirmations: false)

        #expect(entryExists(preExisting.id, in: storage))
        #expect(session.isPresented == false)
    }
}
