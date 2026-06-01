import Testing
import Foundation
import CoreData
@testable import HiMem

// Serialized because EntitlementService.shared is a singleton —
// mutating tier / pack balance / threshold across @Test methods
// running in parallel would create cross-talk. The save-and-restore
// `defer` blocks below keep the global state clean across tests.
@MainActor
@Suite(.serialized)
struct PricingV5DecisionTests {

    // MARK: - State helper

    /// Saves the current EntitlementService global state and restores
    /// it on scope exit. Used by every test that mutates entitlements
    /// so the singleton can't leak across `@Test` methods.
    /// `@MainActor` because every `EntitlementService.shared` property
    /// and method is main-actor-isolated.
    @MainActor
    private final class EntitlementSnapshot {
        let priorTier: EntitlementService.Tier
        let priorMonthlyUsed: Int
        let priorPack: Int
        let priorStarter: Int
        let priorStarterGranted: Bool
        let priorFoundersBonus: Bool
        let priorThreshold: Int
        let priorSupporter: Bool

        init() {
            let e = EntitlementService.shared
            priorTier = e.tier
            priorMonthlyUsed = e.monthlyUsed
            priorPack = e.packBalance
            priorStarter = e.starterUsed
            priorStarterGranted = e.starterGranted
            priorFoundersBonus = e.foundersBonusGranted
            priorThreshold = e.autoOrganizeThreshold
            priorSupporter = e.isSupporter
        }

        func restore() {
            let e = EntitlementService.shared
            e.setTier(priorTier)
            e.debugSetMonthlyUsed(priorMonthlyUsed)
            e.debugSetPackBalance(priorPack)
            e.debugSetStarterUsed(priorStarter)
            e.debugSetStarterGranted(priorStarterGranted)
            e.debugSetFoundersBonusGranted(priorFoundersBonus)
            e.debugSetAutoOrganizeThreshold(priorThreshold)
            e.isSupporter = priorSupporter
        }
    }

    // ─────────────────────────────────────────────────────────────
    // EntitlementService — canAutoOrganize gate (the auto-org reserve)
    // ─────────────────────────────────────────────────────────────

    @Test func canAutoOrganize_atZeroThreshold_returnsTrue_whenMonthlyRemainingPositive() {
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        let e = EntitlementService.shared
        e.setTier(.plusMonthly)
        e.debugSetMonthlyUsed(0)
        e.debugSetPackBalance(0)
        e.debugSetAutoOrganizeThreshold(0)

        #expect(e.canAutoOrganize == true)
    }

    @Test func canAutoOrganize_atZeroThreshold_returnsTrue_whenOnlyPackBalance() {
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        let e = EntitlementService.shared
        e.setTier(.plusMonthly)
        e.debugSetMonthlyUsed(50)
        e.debugSetPackBalance(20)
        e.debugSetAutoOrganizeThreshold(0)

        #expect(e.canAutoOrganize == true)
    }

    /// Money test for Tom's 2026-05-27 screenshot: the free user
    /// who created their first memory had it auto-organized on the
    /// background pass, silently burning a starter assist. Per
    /// pricing spec § 2 ("Idle (ambient hint + Organize)") and AI
    /// Organize spec § 9 ("Auto-organize on Plus / Founder…"), Free
    /// is manual-only. The gate must return false regardless of the
    /// starter pack balance.
    @Test func canAutoOrganize_freeTier_alwaysFalse_evenWithStarterPack() {
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        let e = EntitlementService.shared
        e.setTier(.free)
        e.debugSetMonthlyUsed(0)
        e.debugSetPackBalance(3)       // the 3-starter grant
        e.debugSetAutoOrganizeThreshold(0)

        #expect(e.canAutoOrganize == false)
    }

    @Test func canAutoOrganize_freeTier_alwaysFalse_evenWithFullMonthlyBalance() {
        // Defensive: even if someone accidentally credits a free user
        // a full monthly allowance (Plus regression, debug override),
        // the tier itself bars auto-org.
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        let e = EntitlementService.shared
        e.setTier(.free)
        e.debugSetMonthlyUsed(0)
        e.debugSetPackBalance(0)
        e.debugSetAutoOrganizeThreshold(0)

        #expect(e.canAutoOrganize == false)
    }

    @Test func canAutoOrganize_thresholdEqualToRemaining_returnsFalse() {
        // remaining = 50 monthly + 0 packs = 50. Threshold = 50. The
        // semantic is "fire while remaining > threshold" — equal
        // doesn't qualify.
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        let e = EntitlementService.shared
        e.setTier(.plusMonthly)
        e.debugSetMonthlyUsed(0)
        e.debugSetPackBalance(0)
        e.debugSetAutoOrganizeThreshold(50)

        #expect(e.canAutoOrganize == false)
    }

    @Test func canAutoOrganize_thresholdGreaterThanRemaining_returnsFalse() {
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        let e = EntitlementService.shared
        e.setTier(.plusMonthly)
        e.debugSetMonthlyUsed(40)
        e.debugSetPackBalance(0)
        e.debugSetAutoOrganizeThreshold(20)
        // remaining = 50-40 = 10, threshold = 20 → false

        #expect(e.canAutoOrganize == false)
    }

    @Test func canAutoOrganize_thresholdReservingPacks_pausesWhenMonthlyExhausted() {
        // Plus user with 100 pack assists, threshold = 100 — auto-org
        // runs while remaining > 100. With monthly at 50 remaining +
        // 100 packs = 150 total, runs initially. As monthly is
        // consumed, remaining drops to 100 (50 + 100=150 → 100+100
        // unused) — actually 50 used → 0 monthly + 100 packs = 100
        // total — threshold 100 → not > → stops. The emergent rule
        // "set threshold = pack count to preserve packs" works.
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        let e = EntitlementService.shared
        e.setTier(.plusMonthly)
        e.debugSetPackBalance(100)
        e.debugSetAutoOrganizeThreshold(100)

        e.debugSetMonthlyUsed(0)
        #expect(e.canAutoOrganize == true)   // 50 + 100 = 150 > 100

        e.debugSetMonthlyUsed(50)
        #expect(e.canAutoOrganize == false)  // 0 + 100 = 100, not > 100
    }

    // ─────────────────────────────────────────────────────────────
    // EntitlementService — setAutoOrganizeThreshold clamping
    // ─────────────────────────────────────────────────────────────

    @Test func setAutoOrganizeThreshold_clampedToMonthlyAllowance() {
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        let e = EntitlementService.shared
        e.setTier(.plusMonthly)
        e.setAutoOrganizeThreshold(999)

        #expect(e.autoOrganizeThreshold == 50)  // Plus monthly allowance
    }

    @Test func setAutoOrganizeThreshold_negativeClampedToZero() {
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        let e = EntitlementService.shared
        e.setTier(.plusMonthly)
        e.setAutoOrganizeThreshold(-7)

        #expect(e.autoOrganizeThreshold == 0)
    }

    // ─────────────────────────────────────────────────────────────
    // EntitlementService — consume semantics
    // ─────────────────────────────────────────────────────────────

    @Test func tryConsumeAssist_drainsMonthlyFirstThenPacks() throws {
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        let e = EntitlementService.shared
        e.setTier(.plusMonthly)
        e.debugSetMonthlyUsed(48)   // 2 left this month
        e.debugSetPackBalance(5)
        e.debugSetAutoOrganizeThreshold(0)

        try e.tryConsumeAssist()    // monthly drops to 1 remaining
        #expect(e.monthlyUsed == 49)
        #expect(e.packBalance == 5)

        try e.tryConsumeAssist()    // monthly drops to 0
        #expect(e.monthlyUsed == 50)
        #expect(e.packBalance == 5)

        try e.tryConsumeAssist()    // monthly exhausted, packs drain
        #expect(e.monthlyUsed == 50)
        #expect(e.packBalance == 4)
    }

    @Test func tryConsumeAssist_throwsWhenEverythingZero() {
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        let e = EntitlementService.shared
        e.setTier(.plusMonthly)
        e.debugSetMonthlyUsed(50)
        e.debugSetPackBalance(0)

        #expect(throws: EntitlementService.ConsumeError.self) {
            try e.tryConsumeAssist()
        }
    }

    // ─────────────────────────────────────────────────────────────
    // OrganizedChip — variant resolution (precedence tree)
    // ─────────────────────────────────────────────────────────────

    @Test func chip_default_returnsReviewVariant() {
        let v = OrganizedChip.Variant.resolve(
            isStale: false, canRefresh: true, nextStepsCount: 0
        )
        #expect(v == .default)
        #expect(v.labelText(nextStepsCount: 0) == "Organized · review")
    }

    @Test func chip_withNextStepsButNotStale_returnsCountVariant() {
        let v = OrganizedChip.Variant.resolve(
            isStale: false, canRefresh: true, nextStepsCount: 3
        )
        #expect(v == .nextStepsCount)
        #expect(v.labelText(nextStepsCount: 3) == "Organized · 3 next steps")
    }

    @Test func chip_singularNextStep_usesSingular() {
        let v = OrganizedChip.Variant.resolve(
            isStale: false, canRefresh: true, nextStepsCount: 1
        )
        #expect(v.labelText(nextStepsCount: 1) == "Organized · 1 next step")
    }

    @Test func chip_staleWithAssists_returnsRefreshVariant() {
        let v = OrganizedChip.Variant.resolve(
            isStale: true, canRefresh: true, nextStepsCount: 0
        )
        #expect(v == .refreshStale)
        #expect(v.labelText(nextStepsCount: 0) == "Organized · refresh")
    }

    @Test func chip_staleNoAssists_returnsStaleVariant() {
        let v = OrganizedChip.Variant.resolve(
            isStale: true, canRefresh: false, nextStepsCount: 0
        )
        #expect(v == .staleNoAssists)
        #expect(v.labelText(nextStepsCount: 0) == "Organized · stale")
    }

    @Test func chip_stalePrecedenceWinsOverNextSteps() {
        // Memory has both new clips AND next steps in the existing
        // pass — stale wins because the user should refresh before
        // they trust the steps.
        let v = OrganizedChip.Variant.resolve(
            isStale: true, canRefresh: true, nextStepsCount: 5
        )
        #expect(v == .refreshStale)
        #expect(v.labelText(nextStepsCount: 5) == "Organized · refresh")
    }

    @Test func chip_stalePrecedenceWinsEvenWithoutAssists() {
        let v = OrganizedChip.Variant.resolve(
            isStale: true, canRefresh: false, nextStepsCount: 7
        )
        #expect(v == .staleNoAssists)
    }


    // ─────────────────────────────────────────────────────────────
    // JournalEntry — stale detection (clipsAddedSinceLastOrganize)
    // ─────────────────────────────────────────────────────────────

    @Test func clipsAddedSinceLastOrganize_zeroWhenNeverOrganized() throws {
        let storage = StorageService(inMemory: true)
        let entry = try storage.createEntry(content: "test", inputType: .typed)
        // No media yet → 0.
        #expect(entry.clipsAddedSinceLastOrganize == 0)
        // With media but no `lastOrganizedAt`, still 0 — there's no
        // baseline timestamp to count from.
        let media = MediaReference(context: storage.viewContext)
        media.id = UUID()
        media.entryId = entry.id
        media.mediaType = "text"
        media.osIdentifier = ""
        media.createdAt = Date()
        media.entry = entry
        try storage.save(context: storage.viewContext)
        #expect(entry.clipsAddedSinceLastOrganize == 0)
    }

    @Test func clipsAddedSinceLastOrganize_countsOnlyMediaAfterPassDate() throws {
        let storage = StorageService(inMemory: true)
        let entry = try storage.createEntry(content: "test", inputType: .typed)

        // Build a timeline: media at t0, lastOrganizedAt at t1, two
        // media at t2/t3. Only the two-after-t1 should count.
        let t0 = Date(timeIntervalSinceNow: -300)
        let t1 = Date(timeIntervalSinceNow: -200)
        let t2 = Date(timeIntervalSinceNow: -100)
        let t3 = Date()
        for (i, ts) in [t0, t2, t3].enumerated() {
            let m = MediaReference(context: storage.viewContext)
            m.id = UUID()
            m.entryId = entry.id
            m.mediaType = "text"
            m.osIdentifier = "m\(i)"
            m.createdAt = ts
            m.entry = entry
        }
        entry.lastOrganizedAt = t1
        try storage.save(context: storage.viewContext)

        #expect(entry.clipsAddedSinceLastOrganize == 2)
    }

    // ─────────────────────────────────────────────────────────────
    // ProcessingEngine — v5 semantics (title to pass, not entry)
    // ─────────────────────────────────────────────────────────────

    // ─────────────────────────────────────────────────────────────
    // ProcessingEngine — nextSteps wiring (Pass A)
    // ─────────────────────────────────────────────────────────────

    @Test func processEntry_withNextSteps_writesMarkdownBullets() async throws {
        let storage = StorageService(inMemory: true)
        let engine = ProcessingEngine(
            storage: storage,
            analyzer: V5SuccessAnalyzer(
                title: "Garden plans",
                entityValue: "Sarah",
                topics: ["Garden"],
                nextSteps: ["Call Sarah about the garden", "Pick up tomatoes Tuesday"]
            ),
            localExtractor: LocalEntityExtractor(),
            consumeAssist: { /* test doesn't exercise the debit path */ }
        )

        let entry = try storage.createEntry(content: "Notes.", inputType: .typed)
        _ = try storage.createProcessingTask(for: entry)

        await engine.processEntry(entry)
        storage.viewContext.refreshAllObjects()

        let pass = try storage.viewContext.fetch(NSFetchRequest<OrganizePass>(entityName: "OrganizePass")).first
        let bullets = pass?.nextStepsItems ?? []
        #expect(bullets.count == 2)
        #expect(bullets.contains("Call Sarah about the garden"))
        #expect(bullets.contains("Pick up tomatoes Tuesday"))
    }

    @Test func processEntry_withoutNextSteps_leavesNextStepsMarkdownNil() async throws {
        let storage = StorageService(inMemory: true)
        let engine = ProcessingEngine(
            storage: storage,
            analyzer: V5SuccessAnalyzer(
                title: "Reflection",
                entityValue: "Sarah",
                topics: ["Garden"],
                nextSteps: nil
            ),
            localExtractor: LocalEntityExtractor(),
            consumeAssist: { /* test doesn't exercise the debit path */ }
        )

        let entry = try storage.createEntry(content: "The light hit the kitchen at sunset.", inputType: .typed)
        _ = try storage.createProcessingTask(for: entry)

        await engine.processEntry(entry)
        storage.viewContext.refreshAllObjects()

        let pass = try storage.viewContext.fetch(NSFetchRequest<OrganizePass>(entityName: "OrganizePass")).first
        #expect(pass?.nextStepsMarkdown == nil)
        #expect(pass?.nextStepsItems.isEmpty == true)
    }

    // ─────────────────────────────────────────────────────────────
    // OrganizePass — acceptedRows persistence (2026-05-18 regression)
    // ─────────────────────────────────────────────────────────────

    @Test func acceptedRows_emptyByDefault() throws {
        let storage = StorageService(inMemory: true)
        let ctx = storage.viewContext
        let pass = OrganizePass(context: ctx)
        pass.id = UUID()
        pass.entryId = UUID()
        pass.createdAt = Date()
        #expect(pass.acceptedRows.isEmpty)
    }

    @Test func markRowAccepted_persistsAcrossReads() throws {
        let storage = StorageService(inMemory: true)
        let ctx = storage.viewContext
        let pass = OrganizePass(context: ctx)
        pass.id = UUID()
        pass.entryId = UUID()
        pass.createdAt = Date()

        pass.markRowAccepted(.title)
        pass.markRowAccepted(.summary)
        try ctx.save()

        // Re-fetch to simulate a fresh card open.
        ctx.refreshAllObjects()
        let req = NSFetchRequest<OrganizePass>(entityName: "OrganizePass")
        let refetched = try ctx.fetch(req).first
        #expect(refetched?.acceptedRows == Set([.title, .summary]))
    }

    @Test func markRowAccepted_isIdempotent() throws {
        let storage = StorageService(inMemory: true)
        let ctx = storage.viewContext
        let pass = OrganizePass(context: ctx)
        pass.id = UUID()
        pass.entryId = UUID()
        pass.createdAt = Date()

        pass.markRowAccepted(.title)
        pass.markRowAccepted(.title)
        pass.markRowAccepted(.title)
        #expect(pass.acceptedRows == Set([.title]))
    }

    @Test func markRowsAccepted_unionsExistingSet() throws {
        let storage = StorageService(inMemory: true)
        let ctx = storage.viewContext
        let pass = OrganizePass(context: ctx)
        pass.id = UUID()
        pass.entryId = UUID()
        pass.createdAt = Date()

        pass.markRowAccepted(.title)
        pass.markRowsAccepted([.summary, .mentions])
        #expect(pass.acceptedRows == Set([.title, .summary, .mentions]))
    }

    @Test func acceptedRows_decodesAllFiveKeys() throws {
        let storage = StorageService(inMemory: true)
        let ctx = storage.viewContext
        let pass = OrganizePass(context: ctx)
        pass.id = UUID()
        pass.entryId = UUID()
        pass.createdAt = Date()

        pass.markRowsAccepted([.title, .summary, .topics, .mentions, .nextSteps])
        #expect(pass.acceptedRows.count == 5)
    }

    @Test func processEntry_emptyNextStepsArray_leavesMarkdownNil() async throws {
        // Server returns `[]` rather than omitting the field — same
        // outcome: empty markdown.
        let storage = StorageService(inMemory: true)
        let engine = ProcessingEngine(
            storage: storage,
            analyzer: V5SuccessAnalyzer(
                title: "Reflection",
                entityValue: "Sarah",
                topics: ["Garden"],
                nextSteps: []
            ),
            localExtractor: LocalEntityExtractor(),
            consumeAssist: { /* test doesn't exercise the debit path */ }
        )

        let entry = try storage.createEntry(content: "test", inputType: .typed)
        _ = try storage.createProcessingTask(for: entry)
        await engine.processEntry(entry)
        storage.viewContext.refreshAllObjects()

        let pass = try storage.viewContext.fetch(NSFetchRequest<OrganizePass>(entityName: "OrganizePass")).first
        #expect(pass?.nextStepsMarkdown == nil)
    }

    @Test func analysisResult_decodesWithoutNextStepsField() throws {
        // Server response from BEFORE the prompt change — no nextSteps
        // key at all. Decoder must accept this and treat as nil.
        let json = """
        {
          "entities": [],
          "topics": ["Garden"],
          "summary": "test",
          "title": "Garden notes"
        }
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(ClaudeAPIService.AnalysisResult.self, from: json)
        #expect(result.nextSteps == nil)
    }

    @Test func analysisResult_decodesWithNextStepsField() throws {
        let json = """
        {
          "entities": [],
          "topics": ["Garden"],
          "summary": "test",
          "title": "Garden notes",
          "nextSteps": ["Call Sarah", "Email Mike"]
        }
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(ClaudeAPIService.AnalysisResult.self, from: json)
        #expect(result.nextSteps == ["Call Sarah", "Email Mike"])
    }

    @Test func processEntry_success_writesSuggestedTitleNotEntryTitle() async throws {
        let storage = StorageService(inMemory: true)
        let engine = ProcessingEngine(
            storage: storage,
            analyzer: V5SuccessAnalyzer(title: "Garden meeting", entityValue: "Sarah", topics: ["Garden", "Backyard"]),
            localExtractor: LocalEntityExtractor(),
            consumeAssist: { /* test doesn't exercise the debit path */ }
        )

        let entry = try storage.createEntry(content: "Met with Sarah.", inputType: .typed)
        _ = try storage.createProcessingTask(for: entry)

        await engine.processEntry(entry)
        storage.viewContext.refreshAllObjects()

        let refreshedEntry = try storage.viewContext.fetch(NSFetchRequest<JournalEntry>(entityName: "JournalEntry")).first
        #expect(refreshedEntry?.title == nil)
        #expect(refreshedEntry?.titleSourcedFromAI == false)
        #expect(refreshedEntry?.lastOrganizedAt != nil)

        let passes = try storage.viewContext.fetch(NSFetchRequest<OrganizePass>(entityName: "OrganizePass"))
        #expect(passes.count == 1)
        #expect(passes.first?.suggestedTitle == "Garden meeting")
        #expect(passes.first?.summaryText == "cloud summary")
        #expect(passes.first?.suggestedTopics == ["Garden", "Backyard"])
        #expect(passes.first?.dismissedAt == nil)
    }

    // ─────────────────────────────────────────────────────────────
    // EntryLifecycleService — titleSourcedFromAI clears on manual edit
    // ─────────────────────────────────────────────────────────────

    @Test func edit_manualTitle_clearsTitleSourcedFromAI() throws {
        let storage = StorageService(inMemory: true)
        let lifecycle = EntryLifecycleService(storage: storage)
        let entry = try storage.createEntry(content: "Garden notes", inputType: .typed)
        entry.title = "AI title"
        entry.titleSourcedFromAI = true
        try storage.save(context: storage.viewContext)

        lifecycle.edit(entryId: entry.id, newContent: entry.content, newTitle: "User title")
        storage.viewContext.refreshAllObjects()

        let refreshed = try storage.viewContext.fetch(NSFetchRequest<JournalEntry>(entityName: "JournalEntry")).first
        #expect(refreshed?.title == "User title")
        #expect(refreshed?.titleSourcedFromAI == false)
    }

    @Test func edit_titleNilArgument_preservesTitleSourcedFromAI() throws {
        let storage = StorageService(inMemory: true)
        let lifecycle = EntryLifecycleService(storage: storage)
        let entry = try storage.createEntry(content: "Garden notes", inputType: .typed)
        entry.title = "AI title"
        entry.titleSourcedFromAI = true
        try storage.save(context: storage.viewContext)

        // newTitle: nil = "don't touch title" — flag should survive.
        lifecycle.edit(entryId: entry.id, newContent: entry.content, newTitle: nil)
        storage.viewContext.refreshAllObjects()

        let refreshed = try storage.viewContext.fetch(NSFetchRequest<JournalEntry>(entityName: "JournalEntry")).first
        #expect(refreshed?.title == "AI title")
        #expect(refreshed?.titleSourcedFromAI == true)
    }

    @Test func edit_emptyStringTitle_clearsBothTitleAndFlag() throws {
        let storage = StorageService(inMemory: true)
        let lifecycle = EntryLifecycleService(storage: storage)
        let entry = try storage.createEntry(content: "Garden notes", inputType: .typed)
        entry.title = "AI title"
        entry.titleSourcedFromAI = true
        try storage.save(context: storage.viewContext)

        // newTitle: "" = "user clears" → title goes nil, flag clears.
        lifecycle.edit(entryId: entry.id, newContent: entry.content, newTitle: "")
        storage.viewContext.refreshAllObjects()

        let refreshed = try storage.viewContext.fetch(NSFetchRequest<JournalEntry>(entityName: "JournalEntry")).first
        #expect(refreshed?.title == nil)
        #expect(refreshed?.titleSourcedFromAI == false)
    }
}

// ─────────────────────────────────────────────────────────────
// Test analyzer that returns a full AnalysisResult with topics.
// ─────────────────────────────────────────────────────────────
private struct V5SuccessAnalyzer: EntryAnalyzer {
    let title: String
    let entityValue: String
    let topics: [String]
    var nextSteps: [String]? = nil

    func analyzeEntry(_ text: String, existingTopics: [String], existingMentions: [String]) async throws -> ClaudeAPIService.AnalysisResult {
        ClaudeAPIService.AnalysisResult(
            entities: [.init(type: "person", value: entityValue, confidence: 0.95)],
            topics: topics,
            summary: "cloud summary",
            title: title,
            nextSteps: nextSteps
        )
    }
}
