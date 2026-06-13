import Foundation
import CoreData

/// Abstraction over the cloud entry analyzer so ProcessingEngine can be
/// driven by a stub in tests (and to keep the fallback-on-failure path
/// exercised without real network access).
///
/// `tier` and `action` plumb through to the server's COGS log (see
/// `docs/api/himem-cost-logging.md`). Tier is the
/// `EntitlementService.Tier` rawValue captured at the moment of the
/// call; action is one of a small locked vocabulary
/// (`memory_organize`, `project_assist`, …). Tests pass any string
/// they like; the protocol only requires the parameters exist so
/// production call sites can't accidentally drop them.
protocol EntryAnalyzer {
    /// `existingMentions` carries the case-folded-deduped entity values
    /// already attached to this entry. Empty on first-organize. Server
    /// is instructed (via `docs/design/mentions-server-prompt.md`) to
    /// reuse these strings verbatim where they still apply rather than
    /// paraphrasing — kills the "Reusable Sausage Process" /
    /// "Sausage making process" / "Develop Reusable Sausage Process"
    /// paraphrase accumulation observed 2026-05-18.
    func analyzeEntry(_ text: String, existingTopics: [String], existingMentions: [String], tier: String, action: String) async throws -> ClaudeAPIService.AnalysisResult
}

extension ClaudeAPIService: EntryAnalyzer {}

final class ProcessingEngine {
    static let shared = ProcessingEngine()

    /// Routes between the on-device and cloud organize paths. Defaults
    /// to true after the assist-quota retirement (PR 8e): Free runs on
    /// Apple Foundation Models, Plus also runs on-device today and gets
    /// the frontier polish in Job 4. Setting the flag false forces the
    /// cloud path for debugging.
    ///   `defaults write com.himem.app himem.organize.useOnDevice -bool NO`
    static let useOnDeviceFlagKey = "himem.organize.useOnDevice"

    static var defaultUseOnDevice: Bool {
        // UserDefaults returns false for an unset bool, so a missing
        // value means "use default" → true.
        let store = UserDefaults.standard
        if store.object(forKey: useOnDeviceFlagKey) == nil { return true }
        return store.bool(forKey: useOnDeviceFlagKey)
    }

    private let storage: StorageService
    private let analyzer: EntryAnalyzer
    private let onDeviceOrganizer: Organizer
    private let localExtractor: EntityExtractor
    private let connectivity: ConnectivityMonitor
    private let useOnDevice: Bool
    /// Injectable tier-read closure. Returns the COGS-log label
    /// (`docs/api/himem-cost-logging.md`) captured at call time so
    /// the report attributes spend to the tier in force. Tests inject
    /// a fixed string for determinism.
    private let readTier: @MainActor () -> String
    /// Whether the on-device organizer is available on this device.
    /// In production reads `OnDeviceOrganizer.availabilityError()`;
    /// tests inject a fixed Bool to exercise the AI-vs-no-AI routing
    /// buckets without depending on the Apple Foundation Models stack
    /// being installed in the test environment.
    private let hasAvailableAI: () -> Bool
    /// Reads `Entitlement.shared.isPlus` in production; tests can
    /// inject a fixed Bool to drive the Plus-vs-Free routing buckets
    /// without touching the shared singleton.
    private let isPlus: @MainActor () -> Bool

    init(
        storage: StorageService = .shared,
        analyzer: EntryAnalyzer = ClaudeAPIService.shared,
        onDeviceOrganizer: Organizer = OnDeviceOrganizer(),
        localExtractor: EntityExtractor = LocalEntityExtractor.shared,
        connectivity: ConnectivityMonitor = .shared,
        useOnDevice: Bool = ProcessingEngine.defaultUseOnDevice,
        readTier: @escaping @MainActor () -> String = { Entitlement.shared.tierLabel },
        hasAvailableAI: @escaping () -> Bool = { OnDeviceOrganizer.availabilityError() == nil },
        isPlus: @escaping @MainActor () -> Bool = { Entitlement.shared.isPlus }
    ) {
        self.storage = storage
        self.analyzer = analyzer
        self.onDeviceOrganizer = onDeviceOrganizer
        self.localExtractor = localExtractor
        self.connectivity = connectivity
        self.useOnDevice = useOnDevice
        self.readTier = readTier
        self.hasAvailableAI = hasAvailableAI
        self.isPlus = isPlus
    }

    // MARK: - Process Entry

    func processEntry(_ entry: JournalEntry) async {
        let objectID = entry.objectID
        let content = entry.content
        let context = storage.backgroundContext()

        // Mark as processing — using the background context's copy.
        // Lazily mints a ProcessingTask when one is missing: free-tier
        // saves don't create a task (would leave the entry stuck on
        // "Queued"), so the manual Organize tap arrives here with no
        // task to advance. Mint it on the spot rather than silently
        // bailing on `guard let task`.
        await context.perform {
            do {
                let bgEntry = try context.existingObject(with: objectID) as! JournalEntry
                if bgEntry.latestProcessingTask() == nil {
                    _ = try self.storage.createProcessingTask(for: bgEntry, context: context)
                }
                guard let task = bgEntry.latestProcessingTask() else { return }
                task.status = ProcessingTask.Status.processing.rawValue
                task.progressDescription = "Raw note saved. The app is extracting entities and content intent."
                try context.save()
            } catch {
                Task { @MainActor in ErrorState.shared.report(.processingFailed(error.localizedDescription)) }
            }
        }

        // Routing matrix (2026-06-06):
        //
        //   tier | hasAI | online | primary    | fallback
        //   -----+-------+--------+------------+-----------------
        //   Plus |  yes  |  yes   | Anthropic  | AI → NLTagger
        //   Plus |  yes  |  no    | AI         | NLTagger
        //   Plus |  no   |  yes   | Anthropic  | NLTagger
        //   Plus |  no   |  no    | NLTagger   | —
        //   Free |  yes  |  yes   | AI         | NLTagger
        //   Free |  yes  |  no    | AI         | NLTagger
        //   Free |  no   |  yes   | Anthropic  | NLTagger
        //   Free |  no   |  no    | NLTagger   | —
        //
        // Condition collapses to: try Anthropic iff
        //   online && (isPlus || !hasAI)
        // Otherwise the hierarchy is AI → NLTagger. Free with AI
        // never sees Anthropic; Plus always sees it when online; Free
        // without AI gets Anthropic as their only AI-quality path.
        //
        // No reprocess-on-reconnect: once an organize runs, it sticks
        // until the user explicitly taps Reorganize (see memory entry
        // `feedback_no_auto_reprocess`).
        let plus = await MainActor.run { self.isPlus() }
        let hasAI = useOnDevice && hasAvailableAI()
        let shouldTryAnthropic = connectivity.isConnected && (plus || !hasAI)
        var cloudAttempted = false

        if shouldTryAnthropic {
            cloudAttempted = true
            let succeeded = await processWithCloud(objectID: objectID, content: content, context: context)
            if succeeded { return }
        }

        if hasAI {
            let succeeded = await processWithOnDevice(objectID: objectID, content: content, context: context)
            if succeeded { return }
        }

        // Cloud as last-resort fallback when we're online and haven't
        // already tried it. Covers the Free + hasAI case where the
        // on-device safety classifier rejects content ("Detected
        // content likely to be unsafe") — Anthropic's policy differs
        // from Apple's, so content the local model refuses often
        // organizes cleanly via cloud. Costs us COGS on Free users
        // but produces honest output instead of mentions-only via
        // NLTagger. Per Tom 2026-06-08.
        if !cloudAttempted && connectivity.isConnected {
            NSLog("[HiMem][Organize] on-device failed; retrying via cloud as last-resort fallback")
            let succeeded = await processWithCloud(objectID: objectID, content: content, context: context, isFallback: true)
            if succeeded { return }
        }

        await processLocally(objectID: objectID, content: content, context: context)
    }

    // MARK: - On-device Processing (PR 8a, debug-gated)

    /// Runs the entry through `OnDeviceOrganizer` and, on success,
    /// commits the result via the same storage helpers as the cloud
    /// path. Returns true if the AI call + Core Data save committed
    /// cleanly. Returns false on any failure so the caller can fall
    /// through to the existing connectivity-based routing.
    ///
    /// Skips the assist debit — on-device organize is unmetered.
    private func processWithOnDevice(objectID: NSManagedObjectID, content: String, context: NSManagedObjectContext) async -> Bool {
        let (existingTopics, existingMentions) = await readExistingOrganizeContext(objectID: objectID, context: context)
        do {
            let result = try await onDeviceOrganizer.organize(
                content: content,
                existingTopics: existingTopics,
                existingMentions: existingMentions
            )
            return await applyAnalysisResult(result, existingTopics: existingTopics, to: objectID, in: context)
        } catch {
            // Detailed diagnostic logging — Apple's Foundation Models
            // errors are opaque ("Detected content likely to be unsafe"
            // tells us a filter tripped but not which kind, on which
            // content). We dump every signal available so failures
            // can be correlated against content patterns.
            let typeStr = String(describing: type(of: error))
            let desc = error.localizedDescription
            let contentLen = content.count
            NSLog("[HiMem][Organize] on-device pass failed, falling through: \(desc) [type=\(typeStr) contentChars=\(contentLen)]")
            let nsErr = error as NSError
            NSLog("[HiMem][Organize]   domain=\(nsErr.domain) code=\(nsErr.code)")
            if !nsErr.userInfo.isEmpty {
                NSLog("[HiMem][Organize]   userInfo=\(nsErr.userInfo)")
            }
            return false
        }
    }

    // MARK: - Cloud Processing

    /// Returns `true` if the cloud call succeeded and the result was
    /// committed. Returns `false` on any failure — connectivity drop,
    /// timeout, server error, save failure — and leaves the caller to
    /// route the fallback. The caller is responsible for trying the
    /// on-device organizer next, then `processLocally` as the last
    /// resort.
    ///
    /// `isFallback` distinguishes the AI-failure → cloud recovery path
    /// from the primary cloud path. Fallback traffic sends
    /// `action="memory_organize_fallback"` so the proxy routes it to
    /// Claude Haiku — cheap recovery on content the on-device model
    /// couldn't handle (long transcripts, safety classifier rejects,
    /// etc.) without bloating COGS at the standard-model rate. Per Tom
    /// 2026-06-08 after the 25-min composting transcript blew the 4k
    /// on-device context window.
    private func processWithCloud(
        objectID: NSManagedObjectID,
        content: String,
        context: NSManagedObjectContext,
        isFallback: Bool = false
    ) async -> Bool {
        do {
            let (existingTopics, existingMentions) = await readExistingOrganizeContext(objectID: objectID, context: context)

            // Capture the tier at the moment of the call — if the user
            // upgrades / downgrades mid-pass, the COGS log attributes
            // spend to the tier that authorized the assist, not the
            // tier they end up at.
            let tier = await MainActor.run { self.readTier() }
            let action = isFallback ? "memory_organize_fallback" : "memory_organize"
            let result = try await analyzer.analyzeEntry(
                content,
                existingTopics: existingTopics,
                existingMentions: existingMentions,
                tier: tier,
                action: action
            )

            return await applyAnalysisResult(result, existingTopics: existingTopics, to: objectID, in: context)
        } catch {
            NSLog("[HiMem][Organize] cloud pass failed, falling through: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Local Processing

    private func processLocally(objectID: NSManagedObjectID, content: String, context: NSManagedObjectContext) async {
        let localResult = localExtractor.extractEntities(from: content)

        await context.perform {
            do {
                let entryInContext = try context.existingObject(with: objectID) as! JournalEntry

                for localEntity in localResult.entities {
                    let entity = ExtractedEntity(context: context)
                    entity.id = UUID()
                    entity.entryId = entryInContext.id
                    entity.entityType = localEntity.type.rawValue
                    entity.value = localEntity.value
                    entity.confidenceScore = localEntity.confidence
                    entity.processingMethod = "local"
                    entity.createdAt = Date()
                    entity.entry = entryInContext

                    if let nsRange = content.range(of: localEntity.value).map({ NSRange($0, in: content) }) {
                        entity.textRangeLocation = Int32(nsRange.location)
                        entity.textRangeLength = Int32(nsRange.length)
                    }
                }

                // Mark completed
                if let task = entryInContext.latestProcessingTask() {
                    task.status = ProcessingTask.Status.completed.rawValue
                    task.progressDescription = "Processed locally. Connect to the internet for richer analysis."
                    task.processedAt = Date()
                }

                try context.save()
            } catch {
                self.markFailed(objectID: objectID, error: error, context: context)
            }
        }
    }

    // MARK: - Reorganize (PR 8g)

    /// Runs a reorganize pass — **title and summary only**. Topics,
    /// mentions, album sync, and the inference graph are deliberately
    /// not touched per `AI Organize · spec.md` §8.0 (June 6 2026):
    /// reorganize rethinks the *interpretation* fields; the *fact*
    /// fields (topics, mentions) are user-managed and stable.
    ///
    /// Routing matches `processEntry` (see the matrix there): try
    /// Anthropic iff `online && (isPlus || !hasAI)`; otherwise AI
    /// when available. NLTagger is *not* a fallback for reorganize —
    /// the spec's "failed passes change nothing" overrides the
    /// last-resort tier, since NLTagger can't produce a summary or
    /// title and reorganize only writes those two fields.
    ///
    /// Any topics or mentions the analyzer returns are discarded
    /// silently. The resulting `OrganizePass` enters the standard
    /// draft lifecycle (`dismissedAt = nil` → `isReviewed = false` →
    /// chip flips to *"Draft organized"*); the ReorganizeReviewSheet
    /// handles per-field accept-or-keep.
    func processReorganize(_ entry: JournalEntry) async {
        let objectID = entry.objectID
        let content = entry.content
        let context = storage.backgroundContext()
        let (existingTopics, existingMentions) = await readExistingOrganizeContext(objectID: objectID, context: context)

        let plus = await MainActor.run { self.isPlus() }
        let hasAI = useOnDevice && hasAvailableAI()
        let shouldTryAnthropic = connectivity.isConnected && (plus || !hasAI)

        var cloudAttempted = false
        var result: ClaudeAPIService.AnalysisResult?
        if shouldTryAnthropic {
            cloudAttempted = true
            let tier = await MainActor.run { self.readTier() }
            result = try? await analyzer.analyzeEntry(
                content,
                existingTopics: existingTopics,
                existingMentions: existingMentions,
                tier: tier,
                action: "memory_organize"
            )
        }
        if result == nil, hasAI {
            result = try? await onDeviceOrganizer.organize(
                content: content,
                existingTopics: existingTopics,
                existingMentions: existingMentions
            )
        }

        // Cloud as last-resort fallback — mirrors `processEntry`'s
        // post-yesterday routing. Free + AI-available + online but
        // on-device threw (guardrail-violation on long content, etc.)
        // would otherwise leave the entry's stale prior pass in place.
        // Tagged "memory_organize_fallback" so COGS reports attribute
        // recovery spend separately. Per Tom 2026-06-09: the
        // composting transcript reorganize was silently failing on
        // Free until this parity fix.
        if result == nil, !cloudAttempted, connectivity.isConnected {
            NSLog("[HiMem][Reorganize] on-device failed; retrying via cloud as last-resort fallback")
            let tier = await MainActor.run { self.readTier() }
            result = try? await analyzer.analyzeEntry(
                content,
                existingTopics: existingTopics,
                existingMentions: existingMentions,
                tier: tier,
                action: "memory_organize_fallback"
            )
        }

        guard let result else { return }

        await context.perform { [self] in
            do {
                let entry = try context.existingObject(with: objectID) as! JournalEntry
                storeReorganizePass(title: result.title, summaryText: result.summary, for: entry, in: context)
                try context.save()
            } catch {
                // Swallow — spec §8: failed passes change nothing.
                NSLog("[HiMem][Organize] reorganize storeReorganizePass failed: \(error.localizedDescription)")
            }
        }
    }

    /// Writes a new `OrganizePass` for a reorganize call. Mirrors
    /// `storeOrganizePass` but skips topics, related entries, and
    /// next-steps — only title and summary are recorded.
    private func storeReorganizePass(title: String?, summaryText: String, for entry: JournalEntry, in context: NSManagedObjectContext) {
        let pass = OrganizePass(context: context)
        pass.id = UUID()
        pass.entryId = entry.id
        pass.createdAt = Date()
        pass.summaryText = summaryText
        pass.suggestedTitle = title
        pass.suggestedTopicsJSON = nil
        pass.relatedEntryIDsJSON = nil
        pass.dismissedAt = nil
        pass.entry = entry
        entry.lastOrganizedAt = pass.createdAt
    }

    // MARK: - Queue Processing

    func processPendingTasks() async {
        let context = storage.backgroundContext()
        let request = NSFetchRequest<ProcessingTask>(entityName: "ProcessingTask")
        request.predicate = NSPredicate(format: "status == %@", ProcessingTask.Status.pending.rawValue)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ProcessingTask.createdAt, ascending: true)]
        request.fetchLimit = 10

        do {
            let tasks = try context.performAndWait { try context.fetch(request) }
            for task in tasks {
                // ProcessingTask no longer has a relationship to
                // JournalEntry (stores split, see task #19). Fetch the
                // entry by entryId on the same context — the Cloud
                // store is loaded on the same coordinator.
                let entry: JournalEntry? = context.performAndWait {
                    let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
                    req.predicate = NSPredicate(format: "id == %@", task.entryId as CVarArg)
                    req.fetchLimit = 1
                    return try? context.fetch(req).first
                }
                guard let entry else { continue }
                await processEntry(entry)
            }
        } catch {
            Task { @MainActor in ErrorState.shared.report(.processingFailed(error.localizedDescription)) }
        }
    }

    // MARK: - Shared Organize Helpers

    /// Reads existing topic names + this-entry mentions used to seed an
    /// organize pass. Cloud and on-device paths both consume this so
    /// the model refines vs. paraphrases on re-organize.
    private func readExistingOrganizeContext(objectID: NSManagedObjectID, context: NSManagedObjectContext) async -> (topics: [String], mentions: [String]) {
        let existingTopics: [String] = await context.perform {
            let request = NSFetchRequest<Topic>(entityName: "Topic")
            let topics = (try? context.fetch(request)) ?? []
            return topics.map(\.name)
        }
        let existingMentions: [String] = await context.perform {
            guard let entry = try? context.existingObject(with: objectID) as? JournalEntry,
                  let entities = entry.extractedEntities as? Set<ExtractedEntity> else { return [] }
            var seen: Set<String> = []
            var out: [String] = []
            for e in entities {
                let trimmed = e.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let key = trimmed.lowercased()
                if seen.insert(key).inserted {
                    out.append(trimmed)
                }
            }
            return out
        }
        return (existingTopics, existingMentions)
    }

    /// Applies a successful `AnalysisResult` to the entry — stores
    /// entities, assigns topics (queueing unknowns for approval),
    /// triggers album sync, writes the inference summary and
    /// `OrganizePass`, marks the task complete, saves. Returns true
    /// if the save committed cleanly; false if `markFailed` was
    /// invoked. Shared by the on-device and cloud paths.
    ///
    /// Topics are canonicalized against `existingTopics` first
    /// (per AI Organize spec §2c) — a model returning "garden" when
    /// the user's palette already has "Garden" gets the palette's
    /// casing, not the model's. Without this step the model's case
    /// variants could leak into `OrganizePass.suggestedTopics` and
    /// surface to the user as fake "different" topic suggestions.
    private func applyAnalysisResult(_ result: ClaudeAPIService.AnalysisResult, existingTopics: [String], to objectID: NSManagedObjectID, in context: NSManagedObjectContext) async -> Bool {
        let canonicalResult = Self.canonicalizeTopics(result: result, against: existingTopics)
        return await context.perform { [self] in
            do {
                let entry = try context.existingObject(with: objectID) as! JournalEntry
                storeEntities(from: canonicalResult, for: entry, in: context)
                // `assignTopics` still attaches existing-palette
                // matches to the entry; the returned `newTopics` list
                // is the names that didn't match any existing Topic.
                // Per AI Organize spec §2c: NEW topics are no longer
                // auto-promoted to the palette via a popup approval
                // sheet. They live only on `OrganizePass.suggestedTopicsJSON`
                // until the user reviews the draft (DraftReviewSheet
                // commits them). The old `queueNewTopics(...)` call
                // and its TopicApprovalService backing are retired.
                _ = assignTopics(from: canonicalResult, for: entry, in: context)
                storeInference(from: canonicalResult, for: entry, in: context)
                storeOrganizePass(from: canonicalResult, for: entry, in: context)
                markCompleted(entry)
                try context.save()
                return true
            } catch {
                self.markFailed(objectID: objectID, error: error, context: context)
                return false
            }
        }
    }

    /// Pure topic-canonicalization wrapper around `TopicPalette.partition`.
    /// Returned topics that match an existing palette entry (case-
    /// insensitive, whitespace-trimmed) are rewritten to the palette's
    /// canonical casing; non-matches pass through unchanged. Other
    /// fields on `AnalysisResult` (entities, summary, title,
    /// nextSteps) are preserved bit-for-bit. The "matches first,
    /// novelties next" ordering matches `TopicPalette.Partition`'s
    /// own ordering — the review UI can derive the NEW vs existing
    /// split by re-running the partition at render time.
    static func canonicalizeTopics(
        result: ClaudeAPIService.AnalysisResult,
        against existingTopics: [String]
    ) -> ClaudeAPIService.AnalysisResult {
        let partition = TopicPalette.partition(returned: result.topics, existing: existingTopics)
        let canonicalTopics = partition.existing + partition.new
        return ClaudeAPIService.AnalysisResult(
            entities: result.entities,
            topics: canonicalTopics,
            summary: result.summary,
            title: result.title,
            nextSteps: result.nextSteps
        )
    }

    // MARK: - Cloud Processing Helpers

    private func storeEntities(from result: ClaudeAPIService.AnalysisResult, for entry: JournalEntry, in context: NSManagedObjectContext) {
        // Snapshot existing (type, normalizedValue) on the entry so a second
        // processing pass — whether from a CloudKit re-import after Change
        // Token Expired, an unforeseen re-trigger, or a bg/view race —
        // doesn't double-insert mentions the user already has.
        let existingKeys: Set<String> = {
            guard let entities = entry.extractedEntities as? Set<ExtractedEntity> else { return [] }
            return Set(entities.map { Self.entityKey(type: $0.entityType, value: $0.value) })
        }()

        for entityResult in result.entities {
            guard let type = ExtractedEntity.EntityType(rawValue: entityResult.type) else { continue }
            let key = Self.entityKey(type: type.rawValue, value: entityResult.value)
            if existingKeys.contains(key) { continue }
            let entity = ExtractedEntity(context: context)
            entity.id = UUID()
            entity.entryId = entry.id
            entity.entityType = type.rawValue
            entity.value = entityResult.value
            entity.confidenceScore = entityResult.confidence
            entity.processingMethod = "cloud"
            entity.createdAt = Date()
            entity.entry = entry
        }
    }

    /// Normalized key for entity-dedup: case-folded, trimmed value
    /// only. Type is intentionally excluded — the same string with
    /// different types ("Bob" classified as `person` in pass A and
    /// `project` in pass B) is the same entity, just classified
    /// inconsistently. Type accepts the `type` param to preserve the
    /// call-site shape; it does not affect the key.
    static func entityKey(type: String, value: String) -> String {
        _ = type
        return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Returns names of topics that need user approval (don't exist yet).
    private func assignTopics(from result: ClaudeAPIService.AnalysisResult, for entry: JournalEntry, in context: NSManagedObjectContext) -> [String] {
        var newTopicNames: [String] = []
        for topicName in result.topics {
            let slug = TopicSlugHelper.slugify(topicName)
            let request = NSFetchRequest<Topic>(entityName: "Topic")
            request.predicate = NSPredicate(format: "slug == %@", slug)
            request.fetchLimit = 1
            if let existing = try? context.fetch(request).first {
                entry.addToTopics(existing)
            } else {
                newTopicNames.append(topicName)
            }
        }
        return newTopicNames
    }

    private func storeInference(from result: ClaudeAPIService.AnalysisResult, for entry: JournalEntry, in context: NSManagedObjectContext) {
        let summary = InferenceSummary(context: context)
        summary.id = UUID()
        summary.entryId = entry.id
        summary.summaryText = result.summary
        summary.createdAt = Date()
        summary.entry = entry
        // Per v5 pricing UX: AI-suggested titles no longer auto-write
        // into `entry.title`. They land on `OrganizePass.suggestedTitle`
        // (see `storeOrganizePass` below) and flow into the entry only
        // when the user accepts via the Title row of the
        // AISuggestionsCard. This prevents silent overwrites of
        // user-authored titles by background auto-org passes.
    }

    /// Writes the per-pass `OrganizePass` record alongside the legacy
    /// `InferenceSummary`. The two coexist for now — the new memory
    /// detail Done state reads from `OrganizePass`, but old entries
    /// without one fall back to the legacy `InferenceCard` which reads
    /// `InferenceSummary`. When the prompt is updated to return Next
    /// steps and Related memories, those fields populate here.
    private func storeOrganizePass(
        from result: ClaudeAPIService.AnalysisResult,
        for entry: JournalEntry,
        in context: NSManagedObjectContext
    ) {
        let pass = OrganizePass(context: context)
        pass.id = UUID()
        pass.entryId = entry.id
        pass.createdAt = Date()
        pass.summaryText = result.summary
        pass.suggestedTitle = result.title
        pass.setSuggestedTopics(result.topics)
        // Related memories isn't yet returned by the server prompt
        // and was deliberately cut from the v5 Review card (the
        // Review card is the contract for "this memory"; other-memory
        // discovery happens elsewhere — search, tag drilldown).
        // Field reserved for future use; not populated.
        pass.relatedEntryIDsJSON = nil
        pass.dismissedAt = nil
        pass.entry = entry
        // The lastOrganizedAt timestamp drives the "N new clips since
        // last organize" Re-organize callout. Set on every successful
        // pass — Free manual taps and Plus auto-runs both qualify.
        entry.lastOrganizedAt = pass.createdAt
    }

    private func markCompleted(_ entry: JournalEntry) {
        if let task = entry.latestProcessingTask() {
            task.status = ProcessingTask.Status.completed.rawValue
            task.progressDescription = nil
            task.processedAt = Date()
        }
    }

    private func markFailed(objectID: NSManagedObjectID, error: Error, context: NSManagedObjectContext) {
        do {
            let entryInContext = try context.existingObject(with: objectID) as! JournalEntry
            if let task = entryInContext.latestProcessingTask() {
                task.status = ProcessingTask.Status.failed.rawValue
                task.errorMessage = error.localizedDescription
                task.progressDescription = error.localizedDescription
                task.processedAt = Date()
            }
            try context.save()
        } catch {
            Task { @MainActor in ErrorState.shared.report(.processingFailed(error.localizedDescription)) }
        }
    }
}

// MARK: - Core Data Relationship Helpers

extension JournalEntry {
    @objc(addTopicsObject:)
    @NSManaged func addToTopics(_ value: Topic)

    @objc(removeTopicsObject:)
    @NSManaged func removeFromTopics(_ value: Topic)
}
