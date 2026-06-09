import Testing
import Foundation
import CoreData
@testable import HiMem

// Serialized so the in-suite tests don't trample each other's
// fixture state. The NLTagger thread-safety concern that originally
// drove this is no longer a factor for these tests — they now
// inject `StubEntityExtractor` instead of touching the real
// `LocalEntityExtractor` (and its cold-start fragility on the iOS 26
// simulator). Other suites that still use `LocalEntityExtractor.shared`
// remain serialized on their own merits.
@MainActor
@Suite(.serialized)
struct ProcessingEngineFallbackTests {

    /// Stubbed analyzer that throws — simulates a 1-bar/weak-connection
    /// timeout, transient 5xx, or any other cloud failure.
    private struct ThrowingAnalyzer: EntryAnalyzer {
        struct StubError: Error {}
        func analyzeEntry(_ text: String, existingTopics: [String], existingMentions: [String], tier: String, action: String) async throws -> ClaudeAPIService.AnalysisResult {
            throw StubError()
        }
    }

    /// Stub that returns a deterministic cloud-style result.
    private struct SuccessfulAnalyzer: EntryAnalyzer {
        let title: String
        let entityValue: String
        let topic: String
        func analyzeEntry(_ text: String, existingTopics: [String], existingMentions: [String], tier: String, action: String) async throws -> ClaudeAPIService.AnalysisResult {
            ClaudeAPIService.AnalysisResult(
                entities: [.init(type: "person", value: entityValue, confidence: 0.95)],
                topics: [topic],
                summary: "cloud summary",
                title: title,
                nextSteps: nil
            )
        }
    }

    /// Deterministic `EntityExtractor` — returns a fixed list of
    /// entities regardless of input text. Lets the local-fallback
    /// path be exercised without depending on `NLTagger` warming up
    /// in the iOS 26 simulator (which doesn't, on cold boot, tag
    /// `"Met with Sarah at Stanford about the new garden project."`).
    private struct StubEntityExtractor: EntityExtractor {
        let entities: [LocalEntityExtractor.LocalEntity]

        func extractEntities(from text: String) -> LocalEntityExtractor.LocalResult {
            LocalEntityExtractor.LocalResult(entities: entities)
        }

        /// Helper: a single-person stub with value `name`.
        static func person(_ name: String) -> StubEntityExtractor {
            // Range is required by the model but never consumed by
            // `ProcessingEngine.processLocally` outside of an attempt
            // to compute a textRange. Empty string gives a safe range.
            let dummy = ""
            return StubEntityExtractor(entities: [
                LocalEntityExtractor.LocalEntity(
                    type: .person,
                    value: name,
                    confidence: 0.80,
                    range: dummy.startIndex..<dummy.endIndex
                )
            ])
        }
    }

    /// Money test for the "stuck on Queued / Processing" report. When the
    /// cloud call fails (weak connection, server unreachable), the engine
    /// MUST fall back to local extraction so the entry isn't left in a
    /// half-state. Task ends `.completed`; entities exist with
    /// `processingMethod == "local"`.
    @Test func processEntry_cloudFailure_fallsBackToLocal() async throws {
        let storage = StorageService(inMemory: true)
        let engine = ProcessingEngine(
            storage: storage,
            analyzer: ThrowingAnalyzer(),
            localExtractor: StubEntityExtractor.person("Sarah"),
            useOnDevice: false
        )

        let entry = try storage.createEntry(
            content: "Met with Sarah at Stanford about the new garden project.",
            inputType: .typed
        )
        let task = try storage.createProcessingTask(for: entry)
        #expect(task.statusEnum == .pending)

        await engine.processEntry(entry)

        // Refresh from store so we see the background-context updates.
        storage.viewContext.refreshAllObjects()

        let request = NSFetchRequest<ProcessingTask>(entityName: "ProcessingTask")
        request.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        let refreshedTask = try storage.viewContext.fetch(request).first
        #expect(refreshedTask?.statusEnum == .completed)

        let entityRequest = NSFetchRequest<ExtractedEntity>(entityName: "ExtractedEntity")
        entityRequest.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        let entities = try storage.viewContext.fetch(entityRequest)
        #expect(!entities.isEmpty)
        #expect(entities.allSatisfy { $0.processingMethod == "local" })
    }

    /// Happy path: cloud analyzer succeeds → entry gets entities, topics,
    /// and an inference summary; task ends .completed with method=cloud.
    @Test func processEntry_cloudSuccess_storesEverything() async throws {
        let storage = StorageService(inMemory: true)
        let engine = ProcessingEngine(
            storage: storage,
            analyzer: SuccessfulAnalyzer(title: "Garden meeting", entityValue: "Sarah", topic: "Garden"),
            localExtractor: LocalEntityExtractor(), useOnDevice: false,
        )

        let entry = try storage.createEntry(
            content: "Met with Sarah about the garden.",
            inputType: .typed
        )
        _ = try storage.createProcessingTask(for: entry)

        await engine.processEntry(entry)
        storage.viewContext.refreshAllObjects()

        let request = NSFetchRequest<ProcessingTask>(entityName: "ProcessingTask")
        request.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        let task = try storage.viewContext.fetch(request).first
        #expect(task?.statusEnum == .completed)

        let entityRequest = NSFetchRequest<ExtractedEntity>(entityName: "ExtractedEntity")
        entityRequest.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        let entities = try storage.viewContext.fetch(entityRequest)
        #expect(entities.count == 1)
        #expect(entities.first?.value == "Sarah")
        #expect(entities.first?.processingMethod == "cloud")

        let summaryRequest = NSFetchRequest<InferenceSummary>(entityName: "InferenceSummary")
        summaryRequest.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        let summary = try storage.viewContext.fetch(summaryRequest).first
        #expect(summary?.summaryText == "cloud summary")

        // v5 pricing-UX change: AI-suggested titles no longer auto-write
        // into `entry.title`. They land on `OrganizePass.suggestedTitle`
        // and flow into the entry only when the user accepts via the
        // Title row of the AISuggestionsCard.
        let entryRequest = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        entryRequest.predicate = NSPredicate(format: "id == %@", entry.id as CVarArg)
        let refreshed = try storage.viewContext.fetch(entryRequest).first
        #expect(refreshed?.title == nil)
        #expect(refreshed?.titleSourcedFromAI == false)

        let passRequest = NSFetchRequest<OrganizePass>(entityName: "OrganizePass")
        passRequest.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        let pass = try storage.viewContext.fetch(passRequest).first
        #expect(pass?.suggestedTitle == "Garden meeting")
        #expect(pass?.summaryText == "cloud summary")
        #expect(pass?.suggestedTopics == ["Garden"])
        #expect(pass?.dismissedAt == nil)
        // lastOrganizedAt is set so the "N new clips since last
        // organize" Re-organize callout can fire.
        #expect(refreshed?.lastOrganizedAt != nil)
    }

    /// processPendingTasks fetches pending ProcessingTasks and runs them.
    /// Useful for entries created before the engine was ready (e.g. during
    /// the brief startup window) — they shouldn't sit pending forever.
    @Test func processPendingTasks_picksUpQueuedEntries() async throws {
        let storage = StorageService(inMemory: true)
        let engine = ProcessingEngine(
            storage: storage,
            analyzer: SuccessfulAnalyzer(title: "Note", entityValue: "Bob", topic: "Work"),
            localExtractor: LocalEntityExtractor(), useOnDevice: false,
        )

        let entry = try storage.createEntry(content: "Coffee with Bob.", inputType: .typed)
        _ = try storage.createProcessingTask(for: entry)

        await engine.processPendingTasks()
        storage.viewContext.refreshAllObjects()

        let request = NSFetchRequest<ProcessingTask>(entityName: "ProcessingTask")
        request.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        let task = try storage.viewContext.fetch(request).first
        #expect(task?.statusEnum == .completed)
    }

    /// Money test for the duplicated-mentions bug: when processEntry runs a
    /// second time on the same entry without a clearForReprocessing in
    /// between (e.g. CloudKit re-import after a Change Token Expired reset,
    /// or any other unforeseen re-trigger), the existing entities must NOT
    /// be re-created. storeEntities has to be idempotent on (entry, type, value).
    @Test func processEntry_runTwice_doesNotDuplicateEntities() async throws {
        let storage = StorageService(inMemory: true)
        let engine = ProcessingEngine(
            storage: storage,
            analyzer: SuccessfulAnalyzer(title: "Garden meeting", entityValue: "Sarah", topic: "Garden"),
        )

        let entry = try storage.createEntry(content: "Met with Sarah", inputType: .typed)
        _ = try storage.createProcessingTask(for: entry)
        await engine.processEntry(entry)
        storage.viewContext.refreshAllObjects()

        // Sanity: first pass produced exactly one Sarah entity.
        let firstFetch = NSFetchRequest<ExtractedEntity>(entityName: "ExtractedEntity")
        firstFetch.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        #expect((try storage.viewContext.fetch(firstFetch)).count == 1)

        // Re-trigger processing with no clearForReprocessing between runs.
        _ = try storage.createProcessingTask(for: entry)
        await engine.processEntry(entry)
        storage.viewContext.refreshAllObjects()

        let request = NSFetchRequest<ExtractedEntity>(entityName: "ExtractedEntity")
        request.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        let entities = try storage.viewContext.fetch(request)
        #expect(entities.count == 1, "storeEntities must be idempotent on (entry, type, value)")
    }

    /// Sweep test: existing duplicate ExtractedEntity rows (same entry, type,
    /// value) get collapsed to one canonical row. Mirrors mergeDuplicateTopics.
    @Test func mergeDuplicateEntities_collapsesDuplicates() throws {
        let storage = StorageService(inMemory: true)
        let entry = try storage.createEntry(content: "test", inputType: .typed)

        _ = try storage.createEntity(entryId: entry.id, type: .person, value: "Sarah", confidence: 0.9, method: "cloud", entry: entry)
        _ = try storage.createEntity(entryId: entry.id, type: .person, value: "Sarah", confidence: 0.9, method: "cloud", entry: entry)
        _ = try storage.createEntity(entryId: entry.id, type: .nextAction, value: "Plant potatoes", confidence: 0.85, method: "cloud", entry: entry)
        _ = try storage.createEntity(entryId: entry.id, type: .nextAction, value: "Plant potatoes", confidence: 0.85, method: "cloud", entry: entry)
        try storage.viewContext.save()

        try storage.mergeDuplicateEntities()

        let request = NSFetchRequest<ExtractedEntity>(entityName: "ExtractedEntity")
        request.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        let entities = try storage.viewContext.fetch(request)
        #expect(entities.count == 2, "Two unique (type, value) pairs collapse to two entities")
    }

    // MARK: - Tier × AI routing (#39)
    //
    // Matrix being tested:
    //
    //   tier | hasAI | online | expected primary
    //   -----+-------+--------+-----------------
    //   Plus |  yes  |  yes   | Anthropic
    //   Plus |  yes  |  no    | AI (NLTagger here — no real AI in tests)
    //   Plus |  no   |  yes   | Anthropic (covered by existing tests)
    //   Free |  yes  |  yes   | AI (never Anthropic)
    //   Free |  no   |  yes   | Anthropic (covered by existing tests)
    //
    // The "no real AI" reality of the test environment is handled by
    // injecting `hasAvailableAI: { Bool }` — `true` simulates an Apple
    // FM device, `false` simulates an older device. With `hasAvailableAI`
    // true, we still route as if AI is available; the onDeviceOrganizer
    // stub decides whether it succeeds.

    /// Stub Organizer for routing tests — returns a deterministic
    /// `AnalysisResult` so the engine commits via `applyAnalysisResult`
    /// (which writes `processingMethod = "cloud"` regardless of which
    /// path produced it).
    private struct SuccessfulOnDeviceOrganizer: Organizer {
        let title: String
        let entityValue: String
        let topic: String
        func organize(content: String, existingTopics: [String], existingMentions: [String]) async throws -> ClaudeAPIService.AnalysisResult {
            ClaudeAPIService.AnalysisResult(
                entities: [.init(type: "person", value: entityValue, confidence: 0.95)],
                topics: [topic],
                summary: "on-device summary",
                title: title,
                nextSteps: nil
            )
        }
    }

    /// Stub Organizer that throws — exercises the AI-failed-fall-through
    /// path without depending on Apple FM behavior.
    private struct ThrowingOnDeviceOrganizer: Organizer {
        struct StubError: Error {}
        func organize(content: String, existingTopics: [String], existingMentions: [String]) async throws -> ClaudeAPIService.AnalysisResult {
            throw StubError()
        }
    }

    /// Plus + online → Anthropic runs primary, AI is never called.
    /// Verifies the cloud summary lands and the on-device stub doesn't
    /// (it would have written "on-device summary" if it had).
    @Test func processEntry_plus_online_hitsAnthropicNotAI() async throws {
        let storage = StorageService(inMemory: true)
        let engine = ProcessingEngine(
            storage: storage,
            analyzer: SuccessfulAnalyzer(title: "Garden meeting", entityValue: "Sarah", topic: "Garden"),
            onDeviceOrganizer: SuccessfulOnDeviceOrganizer(title: "Should not appear", entityValue: "WrongName", topic: "WrongTopic"),
            localExtractor: StubEntityExtractor.person("Sarah"),
            useOnDevice: true,
            hasAvailableAI: { true },
            isPlus: { true }
        )

        let entry = try storage.createEntry(content: "Met with Sarah about the garden.", inputType: .typed)
        _ = try storage.createProcessingTask(for: entry)
        await engine.processEntry(entry)
        storage.viewContext.refreshAllObjects()

        let summaryRequest = NSFetchRequest<InferenceSummary>(entityName: "InferenceSummary")
        summaryRequest.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        let summary = try storage.viewContext.fetch(summaryRequest).first
        #expect(summary?.summaryText == "cloud summary", "Plus online must route to Anthropic, not the on-device organizer")
    }

    /// Free + AI available → on-device runs, Anthropic is never called.
    /// If Anthropic ran the summary would say "cloud summary"; instead it
    /// must say "on-device summary".
    @Test func processEntry_free_withAI_hitsAINotAnthropic() async throws {
        let storage = StorageService(inMemory: true)
        let engine = ProcessingEngine(
            storage: storage,
            analyzer: SuccessfulAnalyzer(title: "Should not appear", entityValue: "WrongName", topic: "WrongTopic"),
            onDeviceOrganizer: SuccessfulOnDeviceOrganizer(title: "Garden meeting", entityValue: "Sarah", topic: "Garden"),
            localExtractor: StubEntityExtractor.person("Sarah"),
            useOnDevice: true,
            hasAvailableAI: { true },
            isPlus: { false }
        )

        let entry = try storage.createEntry(content: "Met with Sarah about the garden.", inputType: .typed)
        _ = try storage.createProcessingTask(for: entry)
        await engine.processEntry(entry)
        storage.viewContext.refreshAllObjects()

        let summaryRequest = NSFetchRequest<InferenceSummary>(entityName: "InferenceSummary")
        summaryRequest.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        let summary = try storage.viewContext.fetch(summaryRequest).first
        #expect(summary?.summaryText == "on-device summary", "Free with AI must never hit Anthropic")
    }

    /// Plus + AI available + Anthropic fails → falls through to AI.
    /// "AI offline fallback" path: simulates the user being online but the
    /// cloud call failing (server hiccup, auth refresh in flight, etc.).
    @Test func processEntry_plus_cloudFails_fallsBackToAI() async throws {
        let storage = StorageService(inMemory: true)
        let engine = ProcessingEngine(
            storage: storage,
            analyzer: ThrowingAnalyzer(),
            onDeviceOrganizer: SuccessfulOnDeviceOrganizer(title: "Garden meeting", entityValue: "Sarah", topic: "Garden"),
            localExtractor: StubEntityExtractor.person("Sarah"),
            useOnDevice: true,
            hasAvailableAI: { true },
            isPlus: { true }
        )

        let entry = try storage.createEntry(content: "Met with Sarah about the garden.", inputType: .typed)
        _ = try storage.createProcessingTask(for: entry)
        await engine.processEntry(entry)
        storage.viewContext.refreshAllObjects()

        let summaryRequest = NSFetchRequest<InferenceSummary>(entityName: "InferenceSummary")
        summaryRequest.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        let summary = try storage.viewContext.fetch(summaryRequest).first
        #expect(summary?.summaryText == "on-device summary", "Plus when Anthropic fails must fall through to AI")
    }

    /// Free + AI available + AI fails → NLTagger fallback (no Anthropic).
    /// Edge case: AI is "available" per the static check but throws at
    /// runtime. Free must not silently escalate to Anthropic just because
    /// Updated 2026-06-08: Free + on-device failure + online now
    /// escalates to Anthropic as a last-resort fallback rather than
    /// going straight to NLTagger. The prior "Free never sees
    /// Anthropic" rule was based on COGS discipline, but in practice
    /// it produced mentions-only output (NLTagger doesn't generate
    /// titles or summaries) whenever Apple's on-device safety
    /// classifier rejected content — a silent UX failure. Tom 2026-06-08:
    /// "imo it should have (if internet available) gone to anthropic."
    /// NLTagger remains the offline last-resort.
    @Test func processEntry_free_withAI_failure_fallsToCloudAsLastResort() async throws {
        let storage = StorageService(inMemory: true)
        let engine = ProcessingEngine(
            storage: storage,
            analyzer: SuccessfulAnalyzer(title: "Garden talk with Sarah", entityValue: "Sarah", topic: "Garden"),
            onDeviceOrganizer: ThrowingOnDeviceOrganizer(),
            localExtractor: StubEntityExtractor.person("Should not appear"),
            useOnDevice: true,
            hasAvailableAI: { true },
            isPlus: { false }
        )

        let entry = try storage.createEntry(content: "Met with Sarah about the garden.", inputType: .typed)
        _ = try storage.createProcessingTask(for: entry)
        await engine.processEntry(entry)
        storage.viewContext.refreshAllObjects()

        let entityRequest = NSFetchRequest<ExtractedEntity>(entityName: "ExtractedEntity")
        entityRequest.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        let entities = try storage.viewContext.fetch(entityRequest)
        #expect(!entities.isEmpty)
        #expect(entities.allSatisfy { $0.processingMethod == "cloud" }, "Free with AI failure should now escalate to Anthropic (cloud) when online, recovering from on-device safety rejections")
    }

    // MARK: - Reorganize (PR 8g.1)

    // MARK: - Haiku routing for AI-failure fallback (#92)
    //
    // Per Tom 2026-06-08: "for the ones that fail AI, just send then
    // to Haiku." When on-device organize throws and we fall through to
    // cloud as a last resort, the action label distinguishes it from
    // primary cloud traffic so the proxy can map it to Claude Haiku
    // (cheaper) instead of the standard model. Primary cloud calls
    // (Plus tier, or Free without AI) keep using "memory_organize" so
    // the user experience for those isn't downgraded.

    /// Records the `action` arg on every `analyzeEntry` call so the
    /// tests can assert routing labels rather than only output.
    private final class ActionRecordingAnalyzer: EntryAnalyzer, @unchecked Sendable {
        var actionsReceived: [String] = []
        let title: String
        init(title: String) { self.title = title }
        func analyzeEntry(_ text: String, existingTopics: [String], existingMentions: [String], tier: String, action: String) async throws -> ClaudeAPIService.AnalysisResult {
            actionsReceived.append(action)
            return ClaudeAPIService.AnalysisResult(
                entities: [.init(type: "person", value: "Sarah", confidence: 0.95)],
                topics: ["Garden"],
                summary: "cloud summary",
                title: title,
                nextSteps: nil
            )
        }
    }

    /// Money test for the Haiku routing change. Free + AI available +
    /// AI throws → cloud fallback fires with action="memory_organize_fallback"
    /// so the proxy can route it to Haiku. Without this label, every
    /// AI failure escalates to the standard model and bloats COGS on
    /// content the on-device model couldn't handle anyway.
    @Test func processEntry_aiFailure_cloudFallback_usesHaikuActionLabel() async throws {
        let storage = StorageService(inMemory: true)
        let recorder = ActionRecordingAnalyzer(title: "Recovered title")
        let engine = ProcessingEngine(
            storage: storage,
            analyzer: recorder,
            onDeviceOrganizer: ThrowingOnDeviceOrganizer(),
            localExtractor: StubEntityExtractor.person("Sarah"),
            useOnDevice: true,
            hasAvailableAI: { true },
            isPlus: { false }
        )

        let entry = try storage.createEntry(content: "Met with Sarah.", inputType: .typed)
        _ = try storage.createProcessingTask(for: entry)
        await engine.processEntry(entry)

        #expect(recorder.actionsReceived == ["memory_organize_fallback"],
                "Cloud-as-fallback after on-device failure must use the fallback action label so the proxy routes to Haiku, not the standard model")
    }

    /// Regression: Plus tier + online primary cloud call must NOT use the
    /// fallback label. Plus users pay for the standard-model polish; if
    /// we mistakenly tag their primary calls as fallback, the proxy
    /// would silently downgrade them to Haiku.
    @Test func processEntry_plus_online_primaryCloud_usesStandardActionLabel() async throws {
        let storage = StorageService(inMemory: true)
        let recorder = ActionRecordingAnalyzer(title: "Primary title")
        let engine = ProcessingEngine(
            storage: storage,
            analyzer: recorder,
            onDeviceOrganizer: SuccessfulOnDeviceOrganizer(title: "Should not appear", entityValue: "WrongName", topic: "WrongTopic"),
            localExtractor: StubEntityExtractor.person("Sarah"),
            useOnDevice: true,
            hasAvailableAI: { true },
            isPlus: { true }
        )

        let entry = try storage.createEntry(content: "Met with Sarah.", inputType: .typed)
        _ = try storage.createProcessingTask(for: entry)
        await engine.processEntry(entry)

        #expect(recorder.actionsReceived == ["memory_organize"],
                "Plus primary cloud calls must keep the standard action label so the proxy routes to the standard model")
    }

    /// Money test for the scope contract from `AI Organize · spec.md`
    /// §8.0: reorganize writes a new `OrganizePass` with title + summary
    /// only. Topics and mentions from the new analyzer pass are
    /// discarded; the entity and topic graphs are left untouched.
    @Test func reorganize_writesNewPass_titleAndSummaryOnly() async throws {
        let storage = StorageService(inMemory: true)

        // Pre-create both topics so `assignTopics` attaches them
        // directly. ProcessingEngine routes unknown topic names through
        // `TopicApprovalService` (user approval gate) rather than
        // minting Topic rows itself, so the test seeds the rows up
        // front to exercise the attach path.
        _ = try storage.findOrCreateTopic(name: "Garden")
        _ = try storage.findOrCreateTopic(name: "Kitchen")

        // First pass: classic organize via SuccessfulAnalyzer. Writes
        // pass #1, plus mentions, and attaches the Garden topic.
        let firstAnalyzer = SuccessfulAnalyzer(
            title: "Garden meeting",
            entityValue: "Sarah",
            topic: "Garden"
        )
        let firstEngine = ProcessingEngine(
            storage: storage,
            analyzer: firstAnalyzer,
            localExtractor: StubEntityExtractor.person("Sarah"),
            useOnDevice: false
        )
        let entry = try storage.createEntry(
            content: "Garden notes from today.",
            inputType: .typed
        )
        _ = try storage.createProcessingTask(for: entry)
        await firstEngine.processEntry(entry)
        storage.viewContext.refreshAllObjects()

        // Sanity: pass #1 wrote the title/summary, attached Sarah, and
        // attached the Garden topic to the entry.
        #expect(entry.latestOrganizePass?.suggestedTitle == "Garden meeting")
        #expect(entry.latestOrganizePass?.summaryText == "cloud summary")
        let firstEntities = try storage.viewContext.fetch(NSFetchRequest<ExtractedEntity>(entityName: "ExtractedEntity"))
        #expect(firstEntities.contains { $0.value == "Sarah" })
        #expect((entry.topics as? Set<Topic>)?.contains(where: { $0.name == "Garden" }) == true)
        let firstPassCount: Int = {
            let req = NSFetchRequest<OrganizePass>(entityName: "OrganizePass")
            return (try? storage.viewContext.count(for: req)) ?? -1
        }()
        #expect(firstPassCount == 1)

        // Reorganize with an analyzer that proposes a DIFFERENT title,
        // summary, entity ("Maria"), and topic ("Kitchen"). The contract
        // says only title + summary cross over to the new pass.
        let secondAnalyzer = SuccessfulAnalyzer(
            title: "A fresh take on the garden",
            entityValue: "Maria",
            topic: "Kitchen"
        )
        let secondEngine = ProcessingEngine(
            storage: storage,
            analyzer: secondAnalyzer,
            localExtractor: StubEntityExtractor.person("Maria"),
            useOnDevice: false
        )
        await secondEngine.processReorganize(entry)
        storage.viewContext.refreshAllObjects()

        // A new OrganizePass exists with the reorganize title/summary.
        let allPassesReq = NSFetchRequest<OrganizePass>(entityName: "OrganizePass")
        allPassesReq.sortDescriptors = [NSSortDescriptor(keyPath: \OrganizePass.createdAt, ascending: true)]
        let allPasses = try storage.viewContext.fetch(allPassesReq)
        #expect(allPasses.count == 2)
        #expect(allPasses.last?.suggestedTitle == "A fresh take on the garden")
        #expect(allPasses.last?.summaryText == "cloud summary")
        // Draft state: unreviewed by default — chip will read "Draft organized".
        #expect(allPasses.last?.dismissedAt == nil)
        #expect(allPasses.last?.acceptedRows.isEmpty == true)

        // Spec contract: topics and mentions are not touched.
        let postEntities = try storage.viewContext.fetch(NSFetchRequest<ExtractedEntity>(entityName: "ExtractedEntity"))
        #expect(postEntities.contains { $0.value == "Sarah" })
        #expect(!postEntities.contains { $0.value == "Maria" })

        // The Garden topic stays attached; Kitchen is never attached.
        let entryTopics = (entry.topics as? Set<Topic>) ?? []
        #expect(entryTopics.contains { $0.name == "Garden" })
        #expect(!entryTopics.contains { $0.name == "Kitchen" })
    }

    /// Failed reorganize must leave prior state intact — no partial
    /// write, no pass record. Spec §8: "failed passes change nothing."
    @Test func reorganize_failure_leavesPriorStateIntact() async throws {
        let storage = StorageService(inMemory: true)

        // Seed with one successful organize.
        let firstEngine = ProcessingEngine(
            storage: storage,
            analyzer: SuccessfulAnalyzer(title: "Original", entityValue: "Sarah", topic: "Garden"),
            localExtractor: StubEntityExtractor.person("Sarah"),
            useOnDevice: false
        )
        let entry = try storage.createEntry(content: "Garden notes from today.", inputType: .typed)
        _ = try storage.createProcessingTask(for: entry)
        await firstEngine.processEntry(entry)
        storage.viewContext.refreshAllObjects()

        let priorPassCount: Int = {
            let req = NSFetchRequest<OrganizePass>(entityName: "OrganizePass")
            return (try? storage.viewContext.count(for: req)) ?? -1
        }()
        #expect(priorPassCount == 1)
        let priorTitle = entry.latestOrganizePass?.suggestedTitle

        // Reorganize with a throwing analyzer — both on-device and
        // cloud fail (on-device is unavailable in simulator anyway).
        let throwingEngine = ProcessingEngine(
            storage: storage,
            analyzer: ThrowingAnalyzer(),
            localExtractor: StubEntityExtractor.person("Sarah"),
            useOnDevice: false
        )
        await throwingEngine.processReorganize(entry)
        storage.viewContext.refreshAllObjects()

        // No new pass written; the prior pass is still the latest.
        let postPassCount: Int = {
            let req = NSFetchRequest<OrganizePass>(entityName: "OrganizePass")
            return (try? storage.viewContext.count(for: req)) ?? -1
        }()
        #expect(postPassCount == 1)
        #expect(entry.latestOrganizePass?.suggestedTitle == priorTitle)
    }
}
