import Foundation
import CoreData

/// Extracted from JournalViewModel — handles all entry CRUD operations.
/// JournalViewModel becomes a thin orchestrator that calls this service
/// and updates @Published state.
@MainActor
final class EntryLifecycleService {
    private let storage: StorageService
    private let processingEngine: ProcessingEngine?

    init(storage: StorageService = .shared, processingEngine: ProcessingEngine? = .shared) {
        self.storage = storage
        self.processingEngine = processingEngine
    }

    // MARK: - Create

    /// Creates a new JournalEntry with no content and no media. Used by
    /// Contribute Mode when the user enters a new-memory session — the entry
    /// is created lazily on the first capture, populated as captures are
    /// taken, and either preserved on Done or deleted on X.
    ///
    /// Unlike `save(content:inputType:...)`, this does NOT enqueue a
    /// processing task or capture location. Those happen at session end (or
    /// per-capture as appropriate) once we know the entry has real content.
    func createEmptyEntry(inputType: JournalEntry.InputType) throws -> JournalEntry {
        return try storage.createEntry(content: "", inputType: inputType)
    }

    /// Creates a single MediaReference attached to the entry with the given
    /// id. Used by Contribute Mode to persist each capture as it's taken
    /// (rather than buffering and committing in batch like the legacy
    /// composer). For voice refs, optionally stores the speech-recognition
    /// transcript on the ref itself so the audio player can show it
    /// per-clip. Throws if the entry can't be found.
    @discardableResult
    func createMediaReference(
        forEntryId entryId: UUID,
        localIdentifier: String,
        mediaType: MediaReference.MediaType,
        transcript: String? = nil
    ) throws -> MediaReference {
        guard let entry = try fetchEntry(id: entryId) else {
            throw NSError(domain: "EntryLifecycleService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Entry \(entryId) not found"])
        }
        let ref = try storage.createMediaReference(for: entry, localIdentifier: localIdentifier, mediaType: mediaType, sourceDevice: .phone)
        if let transcript, !transcript.isEmpty {
            ref.transcript = transcript
            try storage.save(context: storage.viewContext)
        }
        return ref
    }

    /// Finalizes a Contribute Mode session. Regenerates `entry.content` from
    /// all chronological captures (TextSegments + voice MediaReference
    /// transcripts) so the AI sees a coherent joined text, enqueues a
    /// ProcessingTask, and captures location for new-memory finalization.
    ///
    /// Mirrors `save(...)` for the persist-as-you-go flow: every capture
    /// (voice refs, image/video refs, typed text segments) was already
    /// attached one-by-one as it was taken, so the only work left at
    /// session-end is to derive the joined content + kick off processing.
    func finalizeContribution(entryId: UUID, captureLocation shouldCaptureLocation: Bool) {
        do {
            guard let entry = try fetchEntry(id: entryId) else { return }
            entry.content = Self.joinedContent(from: entry)
            try storage.save(context: storage.viewContext)
            let _ = try storage.createProcessingTask(for: entry)
            processEntry(entry)
            if shouldCaptureLocation {
                captureLocation(for: entry)
            }
            // Channel B nudge-refresh retired 2026-07-07.
        } catch {
            ErrorState.shared.report(.saveFailed(error.localizedDescription))
        }
    }

    /// Creates a `.note` fragment (MediaReference with text body) attached
    /// to the entry. Used by Contribute Mode when the user commits a
    /// typed Note — fragments persist immediately so they show up in the
    /// chronological capture stream alongside voice/photo captures.
    ///
    /// `createdAt` defaults to `Date()` for fresh captures. The detail-view
    /// auto-migration path passes `entry.createdAt` so the converted note
    /// lands at the start of the chronological stream (before any later
    /// appends), matching its original capture order.
    @discardableResult
    func createNoteFragment(forEntryId entryId: UUID, text: String, createdAt: Date = Date()) throws -> MediaReference {
        guard let entry = try fetchEntry(id: entryId) else {
            throw NSError(domain: "EntryLifecycleService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Entry \(entryId) not found"])
        }
        return try storage.createNoteFragment(for: entry, text: text, createdAt: createdAt, sourceDevice: .phone)
    }

    /// Regenerates `entry.content` from the entry's TextSegments + voice
    /// MediaReference transcripts, sorted by `createdAt`. Called after any
    /// add/edit/delete that affects the chronological capture stream — keeps
    /// AI input (which still reads `entry.content`) in sync with what the
    /// user actually captured.
    func regenerateContent(forEntryId entryId: UUID) {
        do {
            guard let entry = try fetchEntry(id: entryId) else { return }
            entry.content = Self.joinedContent(from: entry)
            try storage.save(context: storage.viewContext)
        } catch {
            ErrorState.shared.report(.saveFailed(error.localizedDescription))
        }
    }

    /// On detail-view onAppear, mints a `.note` MediaReference for an entry
    /// whose `content` text exists with no fragment covering it — the last
    /// stop for legacy entries that slipped past `FragmentMigration`. No-op
    /// when the migration isn't required, so it's safe to call on every
    /// open.
    ///
    /// **Critical guard**: skips if the entry already has *any* `.note`
    /// fragment. After a note is edited, `regenerateContent` rewrites
    /// `entry.content` to the joined output of all fragments — the joined
    /// blob no longer matches any single note's text, so an
    /// "exact-match-or-mint" guard mints a duplicate every open, and each
    /// subsequent regen joins the duplicate back in, compounding the
    /// growth. Skipping when any `.note` exists treats `entry.content` as
    /// "joined output, not orphaned" — which it always is post-migration.
    func migrateOrphanedContentIfNeeded(entryId: UUID) {
        do {
            guard let entry = try fetchEntry(id: entryId) else { return }
            let trimmed = entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let refs = entry.mediaReferencesArray
            guard !refs.isEmpty else { return }  // Pure-content entries render `entry.content` directly.

            // Any `.note` fragment present → migration already happened,
            // `entry.content` is the joined output, nothing to do.
            if refs.contains(where: { $0.mediaTypeEnum == .note }) { return }

            // Content is already the joined output of the entry's text
            // fragments (multi-voice transcripts post-regenerate, or
            // content that drifted into the joined shape via the old
            // append path). Not orphan — skip. This is the guard the
            // 3-voice consolidation bug needed: previously each open
            // re-minted a `.note` containing the joined transcripts
            // because no single voice's transcript matched the joined
            // content individually.
            let joined = Self.joinedContent(from: entry)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == joined { return }

            // Single-voice case where the transcript IS the content.
            if refs.contains(where: {
                $0.mediaTypeEnum == .voice
                    && ($0.transcript?.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed)
            }) { return }

            // P3 (2026-07-14, Option A): recognize `entry.content` as the
            // joined VOICE transcripts under the same per-segment ASR-noise
            // normalization used at ingest, even when byte-unequal to
            // `joined` above. Voice fragments store CLEANED transcripts
            // (`StorageService.createVoiceFragment` →
            // `JournalEntry.cleanedTranscript`), so `joined` is the cleaned
            // join; the `077de8c` defect class is a *future* write path that
            // leaves `entry.content` as the RAW join, which the exact
            // `trimmed == joined` check misses. Normalizing both sides the
            // way `cleanedTranscript` does closes that drift WITHOUT
            // suppressing a genuinely-orphaned typed body — that never
            // reduces to the transcripts, so it still mints (see
            // `SynthesizedNoteRenderGuardTests` + the legacy
            // `..._legacyVoiceOnly_mintsNoteForOrphanedContent`). This is
            // the render-seam fail-safe: the point fix cured the current
            // write paths; this guards the next one.
            if refs.contains(where: { $0.mediaTypeEnum == .voice }),
               Self.normalizedTranscriptBlob(trimmed) == Self.normalizedTranscriptBlob(joined) {
                return
            }

            // Genuine orphan content — text in `entry.content` that no
            // fragment covers. Mint a `.note` and regenerate so future
            // calls see content == joined and skip.
            Self.flagAggregateWriteIfNeeded(
                candidateText: entry.content, entry: entry,
                excludingRefId: nil, context: "migrateOrphanedContent"
            )
            _ = try storage.createNoteFragment(
                for: entry,
                text: entry.content,
                createdAt: entry.createdAt
            )
            if let updated = try fetchEntry(id: entryId) {
                updated.content = Self.joinedContent(from: updated)
                try storage.save(context: storage.viewContext)
            }
        } catch {
            ErrorState.shared.report(.saveFailed(error.localizedDescription))
        }
    }

    /// Updates a `.note` MediaReference's text and regenerates the parent
    /// entry's joined content. Used by per-panel inline editing in the
    /// chronological capture stream.
    func updateNoteFragment(id: UUID, text: String, entryId: UUID) {
        do {
            let request = NSFetchRequest<MediaReference>(entityName: "MediaReference")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            guard let ref = try storage.viewContext.fetch(request).first else { return }
            if let entry = try fetchEntry(id: entryId) {
                Self.flagAggregateWriteIfNeeded(
                    candidateText: text, entry: entry,
                    excludingRefId: id, context: "updateNoteFragment"
                )
            }
            ref.text = text
            ref.lastEditedAt = Date()
            try storage.save(context: storage.viewContext)
            regenerateContent(forEntryId: entryId)
        } catch {
            ErrorState.shared.report(.saveFailed(error.localizedDescription))
        }
    }

    /// Writes a user tap-to-edit to `JournalEntry.summary` and flips
    /// the `summaryUserEdited` marker on. Spec: `Memory Detail · unified
    /// editing model.md` §"Where an edited summary lives" (Tom 2026-06-09).
    /// Empty string clears the summary entirely.
    ///
    /// The marker is the load-bearing piece: once true, a Plus
    /// automatic Reorganize pass must not silently overwrite the
    /// summary (`ProcessingEngine` honors this on the auto path).
    /// Manual Reorganize is already safe — it routes through the
    /// review sheet which defaults to current. Editing here never
    /// reverts the "Organized" chip → "Draft organized"; per spec,
    /// editing is an improvement, not an un-organizing.
    func updateSummary(entryId: UUID, summary: String) {
        do {
            guard let entry = try fetchEntry(id: entryId) else { return }
            let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.summary = trimmed.isEmpty ? nil : trimmed
            entry.summaryUserEdited = true
            try storage.save(context: storage.viewContext)
        } catch {
            ErrorState.shared.report(.saveFailed(error.localizedDescription))
        }
    }

    /// Updates a voice MediaReference's transcript and regenerates the
    /// parent entry's joined content. Used by per-panel inline editing of
    /// transcripts in the chronological capture stream.
    func updateMediaTranscript(mediaId: UUID, transcript: String, entryId: UUID) {
        do {
            let request = NSFetchRequest<MediaReference>(entityName: "MediaReference")
            request.predicate = NSPredicate(format: "id == %@", mediaId as CVarArg)
            request.fetchLimit = 1
            guard let ref = try storage.viewContext.fetch(request).first else { return }
            if let entry = try fetchEntry(id: entryId) {
                Self.flagAggregateWriteIfNeeded(
                    candidateText: transcript, entry: entry,
                    excludingRefId: mediaId, context: "updateMediaTranscript"
                )
            }
            ref.transcript = transcript
            ref.lastEditedAt = Date()
            try storage.save(context: storage.viewContext)
            regenerateContent(forEntryId: entryId)
        } catch {
            ErrorState.shared.report(.saveFailed(error.localizedDescription))
        }
    }

    // The inline-mention lifecycle methods (removeMention / renameMention /
    // addMention over ExtractedEntity) were retired with the B4 mentions
    // library — mention management now lives in ManageMentionsSheet over
    // the library-backed `Mention` entity. Removed 2026-07-18.

    /// Updates a photo/video MediaReference's `mediaDescription` and
    /// regenerates the parent entry's joined content so the new text
    /// flows into AI Organize + search. Mirrors `updateMediaTranscript`
    /// for the voice case. Empty string clears the description.
    func updateMediaDescription(mediaId: UUID, description: String, entryId: UUID) {
        do {
            let request = NSFetchRequest<MediaReference>(entityName: "MediaReference")
            request.predicate = NSPredicate(format: "id == %@", mediaId as CVarArg)
            request.fetchLimit = 1
            guard let ref = try storage.viewContext.fetch(request).first else {
                NSLog("[HiMem][MediaDesc] updateMediaDescription MISS mediaId=\(mediaId)")
                return
            }
            let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
            ref.mediaDescription = trimmed.isEmpty ? nil : trimmed
            ref.lastEditedAt = Date()
            try storage.save(context: storage.viewContext)
            regenerateContent(forEntryId: entryId)
            NSLog("[HiMem][MediaDesc] saved mediaId=\(mediaId) chars=\(trimmed.count)")
        } catch {
            NSLog("[HiMem][MediaDesc] save FAILED mediaId=\(mediaId) error=\(error.localizedDescription)")
            ErrorState.shared.report(.saveFailed(error.localizedDescription))
        }
    }

    /// Pure: builds the joined-content string from an entry's fragments —
    /// voice transcripts, note bodies, and image/video descriptions — in
    /// the memory's per-edge order (`edge.orderInMemory` ascending).
    /// Walks `entry.edgesArray` so a clip shared with another memory
    /// can appear in a different position in each memory's joined
    /// content, per the v1 ontology.
    /// Normalizes a joined-transcript blob for orphan-content comparison:
    /// strips leading ASR noise (`.`, `,`, `…`, whitespace) from each
    /// `\n\n`-separated segment — the same cleaning
    /// `JournalEntry.cleanedTranscript` applies at ingest — and drops
    /// empties. Lets `migrateOrphanedContentIfNeeded` recognize
    /// `entry.content` as the joined voice transcripts even when a write
    /// path stored the RAW join while the fragments hold cleaned text (the
    /// `077de8c` drift class). P3 · `Handoff · carry-forward punch list ·
    /// 2026-07-14`.
    static func normalizedTranscriptBlob(_ text: String) -> String {
        text
            .components(separatedBy: "\n\n")
            .map { JournalEntry.cleanedTranscript($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    // MARK: - Aggregate-write arbiter (Finding 1 · 2026-07-16)

    /// The `[HiMem][TranscriptWipe]` arbiter, extended from the empty-over-
    /// non-empty *wipe* signature to the *aggregate-write* signature: a clip
    /// write whose text is the memory's own joined transcript reified into a
    /// single atom (the 077de8c / Finding 1 corruption — worse than the wipe:
    /// the atom now carries the whole memory). Non-blocking, exactly like the
    /// original wipe arbiter — the write proceeds; we only NSLog the signature
    /// + call stack so any *future* path that reifies the aggregate (a
    /// forgotten reconcile, or a seed that pulls the composed memory
    /// transcript and commits it down) is pinned on the next device repro.
    /// Silence on device is the invariant.
    ///
    /// **The predicate mirrors the cleanup-migration predicate EXACTLY** so
    /// detection and cleanup can never drift: `>= 2` non-empty sibling clips
    /// (aggregate means joined-across-multiple — a single sibling that matches
    /// is legitimately-authored content, never flagged) AND exact normalized
    /// equality (the same per-segment ASR-noise normalization used at ingest,
    /// so the RAW↔CLEANED join drift is caught but nothing fuzzy is).
    static func isAggregateWrite(candidateText: String, siblingTexts: [String]) -> Bool {
        let candidate = normalizedTranscriptBlob(candidateText)
        guard !candidate.isEmpty else { return false }
        let nonEmpty = siblingTexts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard nonEmpty.count >= 2 else { return false }
        return normalizedTranscriptBlob(nonEmpty.joined(separator: "\n\n")) == candidate
    }

    /// Near-miss companion to `isAggregateWrite` — the memory's joined
    /// transcript with extra text around it (the "aggregate-plus-a-word" case
    /// exact normalized equality misses). **Diagnostic only**: this drives the
    /// arbiter's `AGGREGATE-NEARMISS` watch-line, NEVER the cleanup delete
    /// predicate — deletion stays exact-equality per the deletion-safety rule
    /// (Tom, 2026-07-16). A clip that fully *contains* its memory's ≥2-sibling
    /// join is almost certainly a reified aggregate that was then edited; we
    /// want it surfaced, not silently deleted.
    static func isNearAggregateWrite(candidateText: String, siblingTexts: [String]) -> Bool {
        let candidate = normalizedTranscriptBlob(candidateText)
        guard !candidate.isEmpty else { return false }
        let nonEmpty = siblingTexts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard nonEmpty.count >= 2 else { return false }
        let joined = normalizedTranscriptBlob(nonEmpty.joined(separator: "\n\n"))
        guard !joined.isEmpty, candidate != joined else { return false }
        return candidate.contains(joined)
    }

    /// Gathers the content of an entry's clips (per the same per-type source
    /// `joinedContent` reads), optionally excluding one ref by id — the atom
    /// being written, which must not count as its own sibling.
    private static func siblingClipTexts(in entry: JournalEntry, excluding refId: UUID?) -> [String] {
        entry.edgesArray.compactMap { edge in
            guard let ref = edge.clip, ref.id != refId, ref.recycledAt == nil else { return nil }
            switch ref.mediaTypeEnum {
            case .voice: return ref.transcript
            case .note:  return ref.text
            case .image, .video: return ref.mediaDescription
            }
        }
    }

    /// Arbiter hook. Call immediately before a clip's transcript/text is set.
    /// Fires the `[HiMem][TranscriptWipe] AGGREGATE-WRITE` device log (with the
    /// call stack) iff the value being written is the memory's own aggregate.
    /// Detection only — never blocks the write.
    static func flagAggregateWriteIfNeeded(
        candidateText: String,
        entry: JournalEntry,
        excludingRefId: UUID?,
        context: String
    ) {
        let siblings = siblingClipTexts(in: entry, excluding: excludingRefId)
        if isAggregateWrite(candidateText: candidateText, siblingTexts: siblings) {
            NSLog("[HiMem][TranscriptWipe] AGGREGATE-WRITE — \(context) siblingCount=\(siblings.count) len=\(candidateText.count)\n\(Thread.callStackSymbols.prefix(14).joined(separator: "\n"))")
        } else if isNearAggregateWrite(candidateText: candidateText, siblingTexts: siblings) {
            // Near-miss: the value contains the memory's full ≥2-sibling join
            // plus extra text. Surfaced, never auto-cleaned.
            NSLog("[HiMem][TranscriptWipe] AGGREGATE-NEARMISS — \(context) siblingCount=\(siblings.count) len=\(candidateText.count)\n\(Thread.callStackSymbols.prefix(14).joined(separator: "\n"))")
        }
    }

    /// One already-stored aggregate `.note` artifact found by the read-only
    /// device scan (Finding 1). Evidence for the pre-approved cleanup — never
    /// a mutation.
    struct AggregateNoteHit {
        let memoryId: UUID
        let memoryTitle: String
        let noteId: UUID
        let siblingCount: Int
        let noteLength: Int
    }

    /// **Read-only** scan for `.note` clips already at rest whose text IS
    /// their memory's aggregate (a note minted before `077de8c` shipped, or
    /// synced from a pre-fix device). Uses the SAME `isAggregateWrite`
    /// predicate the arbiter and the pending cleanup use (>= 2 siblings, exact
    /// normalized equality), so this is the evidence step that proves the
    /// predicate matches a real artifact before anything destructive runs.
    /// Mutates nothing; logs each hit and returns the summary.
    func scanForAggregateNotes() -> [AggregateNoteHit] {
        var hits: [AggregateNoteHit] = []
        do {
            let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            for entry in try storage.viewContext.fetch(req) {
                for edge in entry.edgesArray {
                    guard let ref = edge.clip, ref.mediaTypeEnum == .note else { continue }
                    let noteText = ref.text ?? ""
                    let siblings = Self.siblingClipTexts(in: entry, excluding: ref.id)
                    guard Self.isAggregateWrite(candidateText: noteText, siblingTexts: siblings) else { continue }
                    let nonEmptySiblings = siblings.filter {
                        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }.count
                    let hit = AggregateNoteHit(
                        memoryId: entry.id,
                        memoryTitle: entry.displayTitle,
                        noteId: ref.id,
                        siblingCount: nonEmptySiblings,
                        noteLength: noteText.count
                    )
                    hits.append(hit)
                    NSLog("[HiMem][TranscriptWipe] AGGREGATE-FOUND mem=\(entry.id.uuidString.prefix(8)) title=\"\(entry.displayTitle)\" note=\(ref.id.uuidString.prefix(8)) siblings=\(nonEmptySiblings) len=\(noteText.count)")
                }
            }
        } catch {
            NSLog("[HiMem][TranscriptWipe] scan error: \(error.localizedDescription)")
        }
        return hits
    }

    static func joinedContent(from entry: JournalEntry) -> String {
        var parts: [String] = []
        for edge in entry.edgesArray {
            // P8: a recycled clip (Recently Deleted) contributes nothing to
            // its memory's composed content while it's in the bin.
            guard let ref = edge.clip, ref.recycledAt == nil else { continue }
            let text: String
            switch ref.mediaTypeEnum {
            case .voice:
                text = ref.transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            case .note:
                text = ref.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            case .image, .video:
                // Photo/video descriptions feed into AI Organize and
                // search the same way voice transcripts do — they're
                // the human stand-in for the future visual-analysis
                // pass. See `docs/design/HiMem · Photo Descriptions.html`.
                text = ref.mediaDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
            if !text.isEmpty {
                parts.append(text)
            }
        }
        return parts.joined(separator: "\n\n")
    }

    /// Deletes the specified MediaReferences (and their cached thumbnails, and
    /// for voice refs, the underlying audio file) by id, regardless of which
    /// entry they belong to. Used by Contribute Mode's X-cancel to remove only
    /// this-session captures, leaving any pre-existing captures on an
    /// append-anchor entry untouched.
    func deleteMediaReferences(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        do {
            for id in ids {
                let request = NSFetchRequest<MediaReference>(entityName: "MediaReference")
                request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                request.fetchLimit = 1
                guard let ref = try storage.viewContext.fetch(request).first else { continue }
                if let cacheFile = ref.thumbnailCacheFilename {
                    ThumbnailService.shared.evictThumbnail(filename: cacheFile)
                }
                // RH-8: permanent hard-delete removes the backing blob for
                // EVERY owned media type (voice/photo/video) — the old
                // voice-only guard orphaned photos/videos in iCloud Files. The
                // "photos/videos live in PhotoKit" premise was stale (media
                // moved to the ubiquity container). PhotoKit-referenced media
                // and notes have no owned file → skipped.
                Self.deleteOwnedBlob(for: ref)
                storage.viewContext.delete(ref)
            }
            try storage.save(context: storage.viewContext)
        } catch {
            ErrorState.shared.report(.deleteFailed(error.localizedDescription))
        }
    }

    /// Returns the new entry's id on success. Callers that need to navigate
    /// to the freshly-created memory (FAB capture-new path) consume this;
    /// existing fire-and-forget call sites can ignore it via @discardableResult.
    @discardableResult
    func save(
        content: String,
        inputType: JournalEntry.InputType,
        voiceFilename: String? = nil,
        voiceCapturedAt: Date? = nil,
        mediaCaptures: [(localIdentifier: String, mediaType: MediaReference.MediaType)] = [],
        topicName: String? = nil
    ) -> UUID? {
        do {
            let entry = try storage.createEntry(content: content, inputType: inputType)
            try storage.save(context: storage.viewContext)
            let _ = try storage.createProcessingTask(for: entry)

            // Voice clips from the in-app FAB recorder land as a `.voice`
            // MediaReference — same shape as Contribute Mode + watch
            // promotions. `voiceCapturedAt` is the orchestrator-supplied
            // per-clip wall-clock (master start + Next-tap offset for
            // this clip). Falls back to `Date()` for legacy single-clip
            // callers that don't yet thread it.
            if let voiceFilename, !voiceFilename.isEmpty {
                _ = try storage.createVoiceFragment(
                    for: entry,
                    audioFilename: voiceFilename,
                    transcript: content,
                    createdAt: voiceCapturedAt ?? Date(),
                    sourceDevice: .phone
                )
                // Re-derive `entry.content` from the just-created
                // voice fragment so it matches the cleaned text. The
                // raw `content` we wrote to `entry.content` above may
                // carry ASR leading noise (e.g. ". foo…") that
                // `createVoiceFragment` stripped from the fragment
                // transcript. If we leave `entry.content` raw,
                // `FragmentMigration` sees a mismatch between
                // `entry.content` and the fragments and mints a
                // duplicate `.note` to "preserve" the unfragmented
                // text — Tom's 2026-05-27 screenshot showed the same
                // recording appearing twice on one entry.
                entry.content = Self.joinedContent(from: entry)
                try storage.save(context: storage.viewContext)
            }

            if let topicName {
                let paletteKey = TopicPaletteStore.shared.key(for: topicName)
                let topic = try storage.findOrCreateTopic(name: topicName, paletteKey: paletteKey)
                entry.addToTopics(topic)
                try storage.save(context: storage.viewContext)
            }

            let savedRefs = try createMediaReferences(for: entry, mediaCaptures: mediaCaptures)
            cacheThumbnails(for: savedRefs)
            captureLocation(for: entry)
            processEntry(entry)
            // Channel B nudge-refresh retired 2026-07-07.
            return entry.id
        } catch {
            ErrorState.shared.report(.saveFailed(error.localizedDescription))
            return nil
        }
    }

    // MARK: - Location capture (fire-and-forget, doesn't block save)

    private func captureLocation(for entry: JournalEntry) {
        let entryId = entry.id
        Task { @MainActor in
            let toggleOn = UserDefaults.standard.object(forKey: "tagMemoriesWithLocation") as? Bool ?? true
            guard toggleOn else { return }

            // Existing users who already cleared onboarding never saw the
            // location row, so authorization is still .notDetermined for
            // them. Request it the first time we try to tag — the iOS
            // system prompt fires once per app install.
            let granted = await LocationService.shared.requestWhenInUseAuthorization()
            guard granted else { return }

            guard let fix = await LocationService.shared.currentLocation() else { return }
            guard let entry = try? self.fetchEntry(id: entryId) else { return }
            entry.latitude = NSNumber(value: fix.coordinate.latitude)
            entry.longitude = NSNumber(value: fix.coordinate.longitude)
            try? self.storage.save(context: self.storage.viewContext)

            // Reverse-geocode separately so the lat/lon land immediately even
            // if the network is slow.
            if let name = await LocationService.shared.reverseGeocode(fix) {
                if let refreshed = try? self.fetchEntry(id: entryId) {
                    refreshed.locationName = name
                    try? self.storage.save(context: self.storage.viewContext)
                }
            }
        }
    }

    // MARK: - Edit

    func edit(
        entryId: UUID,
        newContent: String,
        newTitle: String? = nil,
        removedTagIds: Set<UUID> = [],
        removedMediaIds: Set<UUID> = [],
        addedTopicNames: Set<String> = [],
        removedTopicNames: Set<String> = []
    ) {
        do {
            guard let entry = try fetchEntry(id: entryId) else { return }
            let textChanged = entry.content != newContent

            // nil = no change to title; "" = clear (let displayTitle fall back
            // to the AI/derived/input-type ladder); non-empty = explicit set.
            // Any user-side title write clears the `titleSourcedFromAI` flag
            // — the ✦ AI tag next to the title drops honestly once the user
            // has reworded the suggestion.
            if let newTitle {
                entry.title = newTitle.isEmpty ? nil : newTitle
                entry.titleSourcedFromAI = false
            }

            removeEntities(from: entry, ids: removedTagIds)
            removeMedia(from: entry, ids: removedMediaIds)
            removeTopics(from: entry, names: removedTopicNames)
            addTopics(to: entry, names: addedTopicNames)

            if textChanged {
                entry.content = newContent
                clearForReprocessing(entry)
                let _ = try storage.createProcessingTask(for: entry)
                try storage.save(context: storage.viewContext)
                processEntry(entry)
            } else {
                try storage.save(context: storage.viewContext)
            }
        } catch {
            ErrorState.shared.report(.editFailed(error.localizedDescription))
        }
    }

    // MARK: - Append

    /// Adds new captures to an entry as their own fragments — one
    /// MediaReference per call so the chronological capture stream renders
    /// one panel per capture event. Voice with transcript becomes a
    /// `.voice` ref; typed text with no voice becomes a `.note` ref;
    /// photos/videos become `.image` / `.video` refs. Time is the spine
    /// of the memory — concatenating multiple captures into a single
    /// fragment would collapse separate moments into one block.
    ///
    /// `entry.content` is refreshed from the joined fragments after the
    /// new refs are attached so search + AI input see the combined text.
    /// Direct concatenation into `entry.content` is intentionally avoided:
    /// it lost per-capture timing AND, combined with the pre-fix
    /// auto-migrator, caused the joined blob to be re-minted as one giant
    /// `.note` on the next detail-view open.
    func append(
        entryId: UUID,
        additionalContent: String,
        voiceFilename: String? = nil,
        voiceCapturedAt: Date? = nil,
        mediaCaptures: [(localIdentifier: String, mediaType: MediaReference.MediaType)] = []
    ) {
        do {
            guard let entry = try fetchEntry(id: entryId) else { return }

            let trimmed = additionalContent.trimmingCharacters(in: .whitespacesAndNewlines)

            // Promote any text living only in `entry.content` (legacy
            // typed-only `save` calls, or pre-fragment-per-capture entries)
            // to its own `.note` fragment BEFORE adding the new capture.
            // Without this, the regenerate step at the end of `append`
            // would overwrite `entry.content` with just the joined
            // fragment text and silently drop the original.
            //
            // Finding 1 (2026-07-16): promote ONLY genuinely-orphaned typed
            // text. The exact `priorContent != priorJoined` check alone
            // mis-fires on the RAW join of voice transcripts — byte-unequal
            // to the CLEANED `joinedContent` (voice fragments store
            // `cleanedTranscript`), but the *same words* — and reifies the
            // audio's own transcripts as a duplicate `.note`, landing the
            // aggregate at rest in `ref.text`. That's the 077de8c defect
            // class recurring on the write path (the render-seam guard
            // `migrateOrphanedContentIfNeeded` was hardened; this sibling was
            // not). Apply the same Option A normalization so the raw join is
            // recognized as the transcripts and skipped. The raw
            // `entry.content` drift is then cured unconditionally by the
            // `entry.content = joinedContent(from:)` reconcile below, so it
            // stops drifting whether we mint or skip. Money-tested by
            // `SynthesizedNoteRenderGuardTests
            // .append_withRawJoinedContent_doesNotReifyTranscriptsAsNote`.
            let priorContent = entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let priorJoined = Self.joinedContent(from: entry).trimmingCharacters(in: .whitespacesAndNewlines)
            if !priorContent.isEmpty,
               priorContent != priorJoined,
               Self.normalizedTranscriptBlob(priorContent) != Self.normalizedTranscriptBlob(priorJoined) {
                Self.flagAggregateWriteIfNeeded(
                    candidateText: entry.content, entry: entry,
                    excludingRefId: nil, context: "append.promoteOrphan"
                )
                _ = try storage.createNoteFragment(
                    for: entry,
                    text: entry.content,
                    createdAt: entry.createdAt,
                    sourceDevice: .phone
                )
            }

            if let voiceFilename, !voiceFilename.isEmpty {
                _ = try storage.createVoiceFragment(
                    for: entry,
                    audioFilename: voiceFilename,
                    transcript: trimmed,
                    createdAt: voiceCapturedAt ?? Date(),
                    sourceDevice: .phone
                )
            } else if !trimmed.isEmpty {
                _ = try storage.createNoteFragment(for: entry, text: trimmed, sourceDevice: .phone)
            }

            let savedRefs = try createMediaReferences(for: entry, mediaCaptures: mediaCaptures)
            entry.content = Self.joinedContent(from: entry)
            clearForReprocessing(entry)
            let _ = try storage.createProcessingTask(for: entry)
            try storage.save(context: storage.viewContext)
            cacheThumbnails(for: savedRefs)
            processEntry(entry)
        } catch {
            ErrorState.shared.report(.editFailed(error.localizedDescription))
        }
    }

    /// Bulk-appends N inbox-sourced voice clips to an existing entry as
    /// `.voice` MediaReferences in chronological order. Audio files are
    /// assumed to already live in the standard voice store; the caller
    /// (Captured Clips bundle sheet) moves them out of the inbox before
    /// invoking this.
    ///
    /// Crucially: this **does not** trigger re-organization. Per AI
    /// Organize §8 (`docs/design/AI Organize · spec.md`): "Refresh costs
    /// an assist. The previous summary remains visible until the refresh
    /// commits." The append marks the memory stale by adding fragments
    /// whose `createdAt > entry.lastOrganizedAt`, which the memory-view
    /// stale detector reads to render the amber footer `"N new clips ·
    /// Refresh · 1 assist"`. The user spends the assist by tapping
    /// Refresh — never automatically.
    ///
    /// Move a bench clip's audio into the memory store if it isn't already
    /// there — phone clips arrive at the destination, watch clips live in the
    /// inbox store. Returns false only if the audio can't be located anywhere
    /// (nothing to promote). Same dual-store logic as `appendToExistingMemory`.
    private func moveInboxAudioIfNeeded(audioFilename: String) -> Bool {
        let voiceURL = SpeechService.audioURL(for: audioFilename)
        if FileManager.default.fileExists(atPath: voiceURL.path) { return true }
        let inboxURL = InboxManifest.audioURL(for: audioFilename)
        guard FileManager.default.fileExists(atPath: inboxURL.path) else { return false }
        do {
            _ = try UbiquityStore.shared.moveIntoStore(sourceURL: inboxURL, destinationURL: voiceURL)
            return true
        } catch {
            NSLog("[HiMem][PlaceInboxClip] audio move failed for \(audioFilename): \(error.localizedDescription)")
            return false
        }
    }

    /// **Promote-then-place (Tom, July 16; wired 2026-07-25).** Materialize a
    /// bench `InboxClip` into an EXISTING memory: move its audio, mint a
    /// `MediaReference` + edge (via `appendClips`), stamp its location, and drop
    /// the manifest row. Called only ON CONFIRM (the user picked a destination),
    /// so a cancel never leaves an orphan ref. Returns true on success. This is
    /// the fix for the "Add to a memory" placeholder on manifest-backed clips.
    @discardableResult
    func placeInboxClip(_ clip: InboxClip, intoExisting entryId: UUID) -> Bool {
        guard moveInboxAudioIfNeeded(audioFilename: clip.audioFilename) else { return false }
        let written = appendClips(
            entryId: entryId,
            clips: [(clip.audioFilename, clip.transcript, clip.capturedAt)],
            sourceDevice: JournalEntry.SourceDevice(rawValue: clip.source)
        )
        guard written > 0 else { return false }
        ClipLocationResolver.stamp(osIdentifier: clip.audioFilename,
                                   latitude: clip.latitude, longitude: clip.longitude,
                                   in: storage.viewContext)
        InboxManifest.shared.removeBatch(clipIds: [clip.clipId])
        return true
    }

    /// Promote a bench `InboxClip` into a NEW memory (Start a Memory with one
    /// clip). Returns the new memory id. Same materialize-on-confirm contract.
    @discardableResult
    func createMemoryFromInboxClip(_ clip: InboxClip) -> UUID? {
        guard moveInboxAudioIfNeeded(audioFilename: clip.audioFilename) else { return nil }
        guard let id = createMemoryFromVoiceClips(
            [(clip.audioFilename, clip.transcript, clip.capturedAt)],
            topicName: nil,
            sourceDevice: JournalEntry.SourceDevice(rawValue: clip.source)
        ) else { return nil }
        ClipLocationResolver.stamp(osIdentifier: clip.audioFilename,
                                   latitude: clip.latitude, longitude: clip.longitude,
                                   in: storage.viewContext)
        InboxManifest.shared.removeBatch(clipIds: [clip.clipId])
        return id
    }

    /// Returns the count of clips successfully appended.
    @discardableResult
    func appendClips(
        entryId: UUID,
        clips: [(audioFilename: String, transcript: String, capturedAt: Date)],
        sourceDevice: JournalEntry.SourceDevice? = nil
    ) -> Int {
        guard !clips.isEmpty else { return 0 }
        do {
            guard let entry = try fetchEntry(id: entryId) else { return 0 }
            let ordered = clips.sorted { $0.capturedAt < $1.capturedAt }
            for clip in ordered {
                _ = try storage.createVoiceFragment(
                    for: entry,
                    audioFilename: clip.audioFilename,
                    transcript: clip.transcript,
                    createdAt: clip.capturedAt,
                    sourceDevice: sourceDevice
                )
            }
            entry.content = Self.joinedContent(from: entry)
            try storage.save(context: storage.viewContext)
            return ordered.count
        } catch {
            ErrorState.shared.report(.editFailed(error.localizedDescription))
            return 0
        }
    }

    /// Attaches N existing bench clips (loose `MediaReference`s, already
    /// captured and transcribed) to an existing memory as new
    /// `MemoryClipEdge`s in append order, then reconciles `entry.content`.
    /// Backs the Memory Detail FAB's "Add existing clips" path
    /// (`Memory Detail · unified editing model.md` §"Adding clips to a
    /// memory").
    ///
    /// **No re-organization**, exactly like `appendClips`. Each new edge
    /// is stamped `linkedAt = now`, which pushes the memory past its
    /// last-organize watermark (`JournalEntry.clipsAddedSinceLastOrganize`
    /// reads the edge, not the clip's capture time) — so Memory Detail
    /// shows the stale "N new clips · Reorganize" callout and the user
    /// spends the pass on tap, never automatically (AI Organize §8; the
    /// Move/Add spec's "identical to new clips arriving"). This is why
    /// the path must NOT ride `append()` — that queues a ProcessingTask
    /// and (on Plus) auto-organizes.
    ///
    /// Idempotent per (memory, clip) via `createEdge` — re-adding an
    /// already-attached clip is a no-op. Recycled clips are skipped.
    /// `clipIds` order is honored: they attach in the order given, after
    /// the memory's existing clips. Returns the count newly attached.
    @discardableResult
    func attachExistingClips(entryId: UUID, clipIds: [UUID]) -> Int {
        guard !clipIds.isEmpty else { return 0 }
        do {
            guard let entry = try fetchEntry(id: entryId) else { return 0 }
            let ctx = storage.viewContext
            let now = Date()
            // Resolve the selected clips, drop missing/recycled, and
            // append in capturedAt order — spec: "New clips append in
            // orderInMemory/capturedAt order" (`Memory Detail · unified
            // editing model.md` §"Adding clips to a memory"), the same
            // chronological bulk-append `appendClips` does. The order the
            // user tapped clips in the picker does not determine placement.
            let refs: [MediaReference] = clipIds.compactMap { clipId in
                let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
                req.predicate = NSPredicate(format: "id == %@", clipId as CVarArg)
                req.fetchLimit = 1
                guard let ref = try? ctx.fetch(req).first, ref.recycledAt == nil else { return nil }
                return ref
            }.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
            var attached = 0
            for ref in refs {
                let before = entry.edgesArray.count
                try StorageService.createEdge(from: entry, to: ref, linkedAt: now, in: ctx)
                if entry.edgesArray.count > before { attached += 1 }
            }
            entry.content = Self.joinedContent(from: entry)
            try storage.save(context: ctx)
            return attached
        } catch {
            ErrorState.shared.report(.editFailed(error.localizedDescription))
            return 0
        }
    }

    // MARK: - Create memory from N voice clips (Captured Clips → Start a Memory)

    /// Creates a new memory whose evidence is the supplied voice clips.
    /// Used by `CreateMemoryFromClipsSheet` for the "Start a Memory"
    /// path. Absorbed media, project assignment, title, and location
    /// stamping stay in the sheet — this primitive owns only the
    /// entry + voice fragments + reconciled `entry.content`.
    ///
    /// **The reconcile matters.** Voice fragments store
    /// `JournalEntry.cleanedTranscript(transcript)` — leading ASR noise
    /// (`.`, `,`, `…`, whitespace) is stripped at ingest. If we let
    /// `entry.content` remain the raw joined transcript, it drifts
    /// from `joinedContent(from: entry)` (which trims + reads cleaned
    /// fragment text), and `migrateOrphanedContentIfNeeded` — fired on
    /// Memory Detail onAppear — mints a `.note` MediaReference to
    /// "preserve" the orphaned text. Result: N voice clips become N+1
    /// clips in the memory, the extra being a synthesized note
    /// duplicating the audio's own transcripts. Dogfood 2026-07-13.
    /// Money-tested by
    /// `CreateMemoryFromClipsAssemblyTests
    /// .createMemoryFromNVoiceClips_yieldsExactlyNClips_zeroSynthesizedNotes`.
    @discardableResult
    func createMemoryFromVoiceClips(
        _ clips: [(audioFilename: String, transcript: String, capturedAt: Date)],
        topicName: String?,
        sourceDevice: JournalEntry.SourceDevice? = nil
    ) -> UUID? {
        guard !clips.isEmpty else { return nil }
        do {
            // Start with an empty content field — the voice fragments
            // themselves carry the words. Below, `entry.content` is
            // re-derived from the joined-of-fragments so it stays
            // byte-equal to what `joinedContent(from: entry)` returns.
            let entry = try storage.createEntry(content: "", inputType: .voiceInApp)
            try storage.save(context: storage.viewContext)
            let _ = try storage.createProcessingTask(for: entry)

            let ordered = clips.sorted { $0.capturedAt < $1.capturedAt }
            for clip in ordered {
                _ = try storage.createVoiceFragment(
                    for: entry,
                    audioFilename: clip.audioFilename,
                    transcript: clip.transcript,
                    createdAt: clip.capturedAt,
                    sourceDevice: sourceDevice
                )
            }

            // Reconcile — same shape as `save(voiceFilename:)` at ~L425
            // and `appendClips` at ~L624. Without this, orphan-content
            // migration on detail-view open mints a duplicate `.note`
            // to "preserve" `entry.content` — the 2026-07-13 defect.
            entry.content = Self.joinedContent(from: entry)

            if let topicName {
                let paletteKey = TopicPaletteStore.shared.key(for: topicName)
                let topic = try storage.findOrCreateTopic(name: topicName, paletteKey: paletteKey)
                entry.addToTopics(topic)
            }

            try storage.save(context: storage.viewContext)
            processEntry(entry)
            return entry.id
        } catch {
            ErrorState.shared.report(.saveFailed(error.localizedDescription))
            return nil
        }
    }

    // MARK: - Delete / Recycle

    /// Returns true when an entry has no media fragments left — i.e. every
    /// `.note`, `.voice`, `.image`, and `.video` MediaReference has been
    /// removed. Used by the detail view to prompt "delete this empty
    /// memory?" after the user removes the last fragment via swipe-delete.
    /// Returns `false` if the entry can't be found (callers shouldn't
    /// re-prompt on a missing entry).
    func isEntryEmpty(entryId: UUID) -> Bool {
        do {
            guard let entry = try fetchEntry(id: entryId) else { return false }
            return entry.mediaReferencesArray.isEmpty
        } catch {
            return false
        }
    }

    /// Delete a memory — the narrative + all its edges. **Clips
    /// survive** as unplaced evidence (they may still be referenced by
    /// other memories, or become zero-edge unplaced clips visible on
    /// the Clips tab). Post-Phase-8: the clips are never destroyed by
    /// deleting a memory. See `docs/design/HiMem · evidence and context.md`
    /// § Deletion.
    func delete(entryId: UUID) {
        do {
            guard let entry = try fetchEntry(id: entryId) else { return }
            storage.viewContext.delete(entry)
            try storage.save(context: storage.viewContext)
        } catch {
            ErrorState.shared.report(.deleteFailed(error.localizedDescription))
        }
    }

    /// Remove a clip from a specific memory — drops the connecting
    /// `MemoryClipEdge` only. The clip itself survives, still attached
    /// to any other memories it's in; if this was its last edge, it
    /// returns to the Clips tab as unplaced evidence.
    func removeClipFromMemory(edgeId: UUID) {
        do {
            let req = NSFetchRequest<MemoryClipEdge>(entityName: "MemoryClipEdge")
            req.predicate = NSPredicate(format: "id == %@", edgeId as CVarArg)
            req.fetchLimit = 1
            guard let edge = try storage.viewContext.fetch(req).first else { return }
            let detachedRefId = edge.clipId
            storage.viewContext.delete(edge)
            try storage.save(context: storage.viewContext)
            // Mark the clip "was in a memory" (P7-3) — a user detach; the
            // Unconnected row's line only shows once it's at 0 edges.
            PreviouslyConnectedStore.record(detachedRefId)
        } catch {
            ErrorState.shared.report(.deleteFailed(error.localizedDescription))
        }
    }

    /// Drops the `MemoryClipEdge` for `(memoryId, clipId)` — i.e. removes
    /// the clip from this memory without touching the clip itself.
    /// If the clip has no other memory edges after this, it returns to
    /// the Clips bench as unplaced evidence. Wired to the placement
    /// sheet's "Remove from this memory" destination and to the
    /// "Move to another memory" flow's cleanup step.
    ///
    /// Distinct from `deleteMediaReference` (which destroys the clip
    /// itself, cascading edges). Per `Memory Detail · unified editing
    /// model.md:66` (July 5 2026), Delete clip always destroys; Remove
    /// is a placement action.
    func removeClipFromMemory(memoryId: UUID, refId: UUID) {
        do {
            let edgeReq = NSFetchRequest<MemoryClipEdge>(entityName: "MemoryClipEdge")
            edgeReq.predicate = NSPredicate(
                format: "clipId == %@ AND memoryId == %@",
                refId as CVarArg,
                memoryId as CVarArg
            )
            edgeReq.fetchLimit = 1
            guard let edge = try storage.viewContext.fetch(edgeReq).first else { return }
            storage.viewContext.delete(edge)
            try storage.save(context: storage.viewContext)
            PreviouslyConnectedStore.record(refId)
        } catch {
            ErrorState.shared.report(.deleteFailed(error.localizedDescription))
        }
    }

    /// Update an edge's **annotation** — "why this matters here", the
    /// per-edge context in the unified Clip Editor's Zone 2. The clip *atom*
    /// is untouched (that's Zone 1); this writes only the `(clip, memory)`
    /// edge, so the same clip can mean different things in different memories.
    /// An empty/whitespace value clears the annotation back to `nil`.
    func updateEdgeAnnotation(edgeId: UUID, annotation: String) {
        do {
            let req = NSFetchRequest<MemoryClipEdge>(entityName: "MemoryClipEdge")
            req.predicate = NSPredicate(format: "id == %@", edgeId as CVarArg)
            req.fetchLimit = 1
            guard let edge = try storage.viewContext.fetch(req).first else { return }
            let trimmed = annotation.trimmingCharacters(in: .whitespacesAndNewlines)
            edge.annotation = trimmed.isEmpty ? nil : trimmed
            try storage.save(context: storage.viewContext)
        } catch {
            ErrorState.shared.report(.saveFailed(error.localizedDescription))
        }
    }

    /// **Atom-level** transcript edit for the unified Clip Editor (Zone 1).
    /// The clip is stored once, so the edit is true in *every* memory that
    /// references it — this sets the ref's transcript and regenerates the
    /// content of every referencing memory (none, for a loose 0-edge clip).
    /// The empty-over-non-empty wipe guard lives upstream in
    /// `ClipEditorCommitDecision`; this trusts a real committed value.
    func updateClipTranscript(refId: UUID, transcript: String) {
        do {
            let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
            req.predicate = NSPredicate(format: "id == %@", refId as CVarArg)
            req.fetchLimit = 1
            guard let ref = try storage.viewContext.fetch(req).first else { return }
            // Arbiter: a clip can be evidence in many memories; flag if the
            // committed value is the aggregate of ANY referencing memory (the
            // "seed pulled the composed memory transcript then Done committed
            // it down" failure this modal replaces — must never recur here).
            for edge in ref.edgesArray {
                if let entry = try fetchEntry(id: edge.memoryId) {
                    Self.flagAggregateWriteIfNeeded(
                        candidateText: transcript, entry: entry,
                        excludingRefId: refId, context: "updateClipTranscript"
                    )
                }
            }
            ref.transcript = transcript
            ref.lastEditedAt = Date()
            try storage.save(context: storage.viewContext)
            for edge in ref.edgesArray {
                regenerateContent(forEntryId: edge.memoryId)
            }
        } catch {
            ErrorState.shared.report(.saveFailed(error.localizedDescription))
        }
    }

    /// **Atom-level** description edit (photo/video) for the unified Clip
    /// Editor (Zone 1). Same atom-once semantics as `updateClipTranscript`.
    func updateClipDescription(refId: UUID, description: String) {
        do {
            let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
            req.predicate = NSPredicate(format: "id == %@", refId as CVarArg)
            req.fetchLimit = 1
            guard let ref = try storage.viewContext.fetch(req).first else { return }
            let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
            ref.mediaDescription = trimmed.isEmpty ? nil : trimmed
            ref.lastEditedAt = Date()
            try storage.save(context: storage.viewContext)
            for edge in ref.edgesArray {
                regenerateContent(forEntryId: edge.memoryId)
            }
        } catch {
            ErrorState.shared.report(.saveFailed(error.localizedDescription))
        }
    }

    /// **Soft-delete a clip to Recently Deleted (P8, July 19 2026).** The
    /// atom survives 30 days and is restorable — `recycledAt` hides it from
    /// every bench + memory query (via the `recycledAt == nil` predicate and
    /// `mediaReferencesArray`'s filter), so "Delete this Clip" removes it
    /// from *every* referencing memory without touching the edges; restore
    /// returns it to those memories. Audio/thumbnail are left on disk until
    /// purge. Supersedes the old hard-delete body, which lied about the
    /// footnote's "Moves to Recently Deleted · kept for 30 days" promise.
    func recycleClip(refId: UUID) {
        do {
            guard let ref = try fetchRef(refId) else { return }
            ref.recycledAt = Date()
            try storage.save(context: storage.viewContext)
            // Regenerate any live memory that referenced it — the exclusion
            // filter drops the recycled clip from the composed content.
            for edge in ref.edgesArray { regenerateContent(forEntryId: edge.memoryId) }
        } catch {
            ErrorState.shared.report(.deleteFailed(error.localizedDescription))
        }
    }

    /// Batch soft-delete (P8b) — the Unconnected "Delete N" MediaReference
    /// portion. One save for the whole set; each ref's referencing memories
    /// regenerate (the exclusion filter drops the recycled clip).
    func recycleClips(refIds: Set<UUID>) {
        guard !refIds.isEmpty else { return }
        do {
            let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
            req.predicate = NSPredicate(format: "id IN %@", refIds)
            let refs = try storage.viewContext.fetch(req)
            let now = Date()
            for ref in refs { ref.recycledAt = now }
            try storage.save(context: storage.viewContext)
            for ref in refs {
                for edge in ref.edgesArray { regenerateContent(forEntryId: edge.memoryId) }
            }
        } catch {
            ErrorState.shared.report(.deleteFailed(error.localizedDescription))
        }
    }

    /// Restore a clip from Recently Deleted — clears `recycledAt`; kept
    /// edges bring it back to the memories it was in.
    func restoreClip(refId: UUID) {
        do {
            guard let ref = try fetchRef(refId) else { return }
            ref.recycledAt = nil
            try storage.save(context: storage.viewContext)
            for edge in ref.edgesArray { regenerateContent(forEntryId: edge.memoryId) }
        } catch {
            ErrorState.shared.report(.deleteFailed(error.localizedDescription))
        }
    }

    /// **Permanent destruction** — the old hard-delete body. Used by
    /// Recently Deleted's Delete Forever and the 30-day purge. Removes the
    /// cached thumbnail, the audio file (`.voice`), and the row (edges
    /// cascade). Irreversible.
    func purgeClip(refId: UUID) {
        do {
            guard let ref = try fetchRef(refId) else { return }
            if let cacheFile = ref.thumbnailCacheFilename {
                ThumbnailService.shared.evictThumbnail(filename: cacheFile)
            }
            Self.deleteOwnedBlob(for: ref) // RH-8: coordinated blob delete, all media types
            storage.viewContext.delete(ref)
            try storage.save(context: storage.viewContext)
        } catch {
            ErrorState.shared.report(.deleteFailed(error.localizedDescription))
        }
    }

    /// The OWNED iCloud Files URL for a clip's backing blob, or nil when
    /// HiMem owns no deletable file: a **note** (text lives in Core Data) or
    /// a **PhotoKit-referenced** asset (the user's Photos library, never
    /// ours). Voice/photo/video resolve to their ubiquity subdirectory.
    static func ownedBlobURL(for ref: MediaReference) -> URL? {
        guard ref.mediaTypeEnum != .note else { return nil }
        switch MediaResolver.resolve(osIdentifier: ref.osIdentifier, mediaType: ref.mediaTypeEnum) {
        case .ubiquity(let url): return url
        case .photoKit:          return nil
        }
    }

    /// Permanently removes a clip's backing blob from iCloud Files
    /// (NSFileCoordinator-wrapped, no-op if already gone). ONLY the
    /// permanent-purge paths call this; soft-recycle/restore never do.
    static func deleteOwnedBlob(for ref: MediaReference) {
        guard let url = ownedBlobURL(for: ref) else { return }
        UbiquityStore.shared.removeFromStore(at: url)
    }

    /// Recently-Deleted clips (recycledAt != nil), newest-deleted first,
    /// as value snapshots for `RecycleBinView` (no managed-object lifetimes
    /// leak into the list).
    func loadRecycledClips() -> [RecycledClipDisplay] {
        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        req.predicate = NSPredicate(format: "recycledAt != nil")
        req.sortDescriptors = [NSSortDescriptor(key: "recycledAt", ascending: false)]
        let refs = (try? storage.viewContext.fetch(req)) ?? []
        return refs.map { RecycledClipDisplay(ref: $0) }
    }

    /// Purges recycled clips past the 30-day window — the clip-level sibling
    /// of `ProjectViewModel.purgeExpiredRecycledProjects`. Called on
    /// RecycleBin open.
    func purgeExpiredRecycledClips(now: Date = Date()) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        req.predicate = NSPredicate(format: "recycledAt != nil AND recycledAt < %@", cutoff as CVarArg)
        let expired = (try? storage.viewContext.fetch(req)) ?? []
        guard !expired.isEmpty else { return }
        for ref in expired {
            if let cacheFile = ref.thumbnailCacheFilename {
                ThumbnailService.shared.evictThumbnail(filename: cacheFile)
            }
            Self.deleteOwnedBlob(for: ref) // RH-8: coordinated blob delete, all media types
            storage.viewContext.delete(ref)
        }
        try? storage.save(context: storage.viewContext)
    }

    private func fetchRef(_ id: UUID) throws -> MediaReference? {
        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return try storage.viewContext.fetch(req).first
    }

    func recycle(entryId: UUID) {
        do {
            guard let entry = try fetchEntry(id: entryId) else { return }
            let now = Date()
            // P8 last-reference rule (July 19 2026, narrowly reverses the P6
            // "clips always survive Let Go" lock): a clip whose single
            // remaining edge is THIS memory moves to Recently Deleted with
            // it; a clip used elsewhere (edge count > 1) stays. Pure
            // edge-count at delete time — no `everConnected`/history field.
            // Memory-deletion-ONLY: detach-from-last-memory and AI
            // reorganization never route here, so they never auto-retire.
            // recycledAt is a soft flag with edges preserved, so nothing is
            // destroyed here (no transcript write → the aggregate-write
            // arbiter has nothing to guard on this path).
            for edge in entry.edgesArray {
                guard let clip = edge.clip else { continue }
                if clip.referencingMemoryCount == 1 { // this memory is its only edge
                    clip.recycledAt = now
                }
            }
            entry.isRecycled = true
            entry.recycledAt = now
            try storage.save(context: storage.viewContext)
        } catch {
            ErrorState.shared.report(.deleteFailed(error.localizedDescription))
        }
    }

    func restore(entryId: UUID) {
        do {
            guard let entry = try fetchEntry(id: entryId) else { return }
            entry.isRecycled = false
            entry.recycledAt = nil
            // Symmetric with `recycle` (P8): bring back the clips that came
            // down WITH this memory — a recycled clip whose only edge is this
            // (now-restored) memory was auto-retired by the last-reference
            // rule. Derived from the same edge-count, no history field. A clip
            // still used elsewhere was never auto-retired, and a clip the user
            // explicitly deleted stays deleted unless it, too, is only-here —
            // an accepted corner of the no-history design.
            for edge in entry.edgesArray {
                guard let clip = edge.clip, clip.recycledAt != nil else { continue }
                if clip.referencingMemoryCount == 1 {
                    clip.recycledAt = nil
                }
            }
            try storage.save(context: storage.viewContext)
        } catch {
            ErrorState.shared.report(.deleteFailed(error.localizedDescription))
        }
    }

    func emptyRecycleBin() {
        do {
            let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            request.predicate = NSPredicate(format: "isRecycled == YES")
            let entries = try storage.viewContext.fetch(request)
            for entry in entries {
                storage.viewContext.delete(entry)
            }
            try storage.save(context: storage.viewContext)
        } catch {
            ErrorState.shared.report(.deleteFailed(error.localizedDescription))
        }
    }

    // MARK: - Feedback

    func submitFeedback(entryId: UUID, state: InferenceSummary.FeedbackState, correction: String? = nil) {
        do {
            guard let entry = try fetchEntry(id: entryId) else { return }
            guard let summary = entry.inferenceSummary else { return }
            try storage.updateFeedback(summary, state: state, correction: correction)
        } catch {
            ErrorState.shared.report(.saveFailed(error.localizedDescription))
        }
    }

    // MARK: - Private Helpers

    private func fetchEntry(id: UUID) throws -> JournalEntry? {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try storage.viewContext.fetch(request).first
    }

    private func createMediaReferences(
        for entry: JournalEntry,
        mediaCaptures: [(localIdentifier: String, mediaType: MediaReference.MediaType)]
    ) throws -> [MediaReference] {
        var refs: [MediaReference] = []
        for capture in mediaCaptures {
            let ref = try storage.createMediaReference(
                for: entry,
                localIdentifier: capture.localIdentifier,
                mediaType: capture.mediaType,
                sourceDevice: .phone
            )
            refs.append(ref)
        }
        return refs
    }

    private func cacheThumbnails(for refs: [MediaReference]) {
        guard !refs.isEmpty else { return }
        let storage = self.storage
        // Snapshot the (osIdentifier, mediaType) tuples on the main
        // context before the detached task runs — MediaReference is
        // not Sendable, so the detached closure can't access the
        // managed objects directly.
        let payload: [(osIdentifier: String, mediaType: MediaReference.MediaType, ref: MediaReference)] =
            refs.map { ($0.osIdentifier, $0.mediaTypeEnum, $0) }
        Task.detached {
            for entry in payload {
                let filename = await ThumbnailService.shared.cacheThumbnail(
                    for: entry.osIdentifier,
                    mediaType: entry.mediaType
                )
                if let filename {
                    try? storage.updateThumbnailFilename(entry.ref, filename: filename)
                }
            }
        }
    }

    /// Auto-fires the AI processing pipeline if the user's tier allows
    /// it. Free users never auto-run — they tap "Organize with AI" on
    /// individual memories so each consumption is explicit. Plus and
    /// Founders auto-run as long as their monthly allowance + pack
    /// balance has assists left; silently skips when exhausted.
    ///
    /// Per v2 pricing rule, the engine itself deducts the assist only
    /// on a successful pass — failures cost zero. We do a precheck
    /// here (`canConsumeAssist`) so we don't even hit the API when
    /// the user is already at the cap; the engine's post-success
    /// `tryConsumeAssist()` is what actually decrements.
    private func processEntry(_ entry: JournalEntry) {
        guard let processingEngine else { return }
        let entryID = entry.objectID
        Task.detached { [storage] in
            // Plus auto-organizes on capture; Free runs manually from
            // Memory Detail. The mint-and-leave-pending case below
            // handles Free so the task doesn't sit "Queued" forever.
            let shouldProcess: Bool = await MainActor.run { Entitlement.shared.isPlus }
            if !shouldProcess {
                // The save path already minted a `.pending` task on
                // the assumption auto-org would pick it up. For
                // manual-only tiers (Free, or Plus at budget cap),
                // the engine never runs and the task sits pending
                // forever — UI renders "Queued" / "Working…
                // Inquiring with the AI" indefinitely (Tom's
                // 2026-05-27 screenshot). Delete the stale task so
                // the UI shows the "Organize with AI" card. The
                // engine's lazy-create path mints a fresh one when
                // the user actually taps Organize.
                await Self.dropPendingTask(forEntryID: entryID, storage: storage)
                return
            }
            await processingEngine.processEntry(entry)
        }
    }

    private static func dropPendingTask(forEntryID entryID: NSManagedObjectID, storage: StorageService) async {
        await MainActor.run {
            let ctx = storage.viewContext
            guard let entry = try? ctx.existingObject(with: entryID) as? JournalEntry,
                  let task = entry.latestProcessingTask(),
                  task.statusEnum == .pending else { return }
            ctx.delete(task)
            try? storage.save(context: ctx)
        }
    }

    private func removeEntities(from entry: JournalEntry, ids: Set<UUID>) {
        guard !ids.isEmpty, let entities = entry.extractedEntities as? Set<ExtractedEntity> else { return }
        for entity in entities where ids.contains(entity.id) {
            storage.viewContext.delete(entity)
        }
    }

    private func removeMedia(from entry: JournalEntry, ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for ref in entry.mediaReferencesArray where ids.contains(ref.id) {
            if let cacheFile = ref.thumbnailCacheFilename {
                ThumbnailService.shared.evictThumbnail(filename: cacheFile)
            }
            storage.viewContext.delete(ref)
        }
    }

    private func removeTopics(from entry: JournalEntry, names: Set<String>) {
        guard !names.isEmpty, let topics = entry.topics as? Set<Topic> else { return }
        for topic in topics where names.contains(topic.name) {
            entry.removeFromTopics(topic)
        }
    }

    private func addTopics(to entry: JournalEntry, names: Set<String>) {
        for topicName in names {
            let paletteKey = TopicPaletteStore.shared.key(for: topicName)
            if let topic = try? storage.findOrCreateTopic(name: topicName, paletteKey: paletteKey) {
                entry.addToTopics(topic)
            }
        }
    }

    private func clearForReprocessing(_ entry: JournalEntry) {
        if let entities = entry.extractedEntities as? Set<ExtractedEntity> {
            for entity in entities { storage.viewContext.delete(entity) }
        }
        if let summary = entry.inferenceSummary {
            storage.viewContext.delete(summary)
        }
        if let topics = entry.topics as? Set<Topic> {
            for topic in topics { entry.removeFromTopics(topic) }
        }
        // ProcessingTask lives in the Local store (not the Cloud
        // store) per CloudKit cleanup investigation. Query by entryId
        // and delete each one — no relationship to walk.
        let taskRequest = NSFetchRequest<ProcessingTask>(entityName: "ProcessingTask")
        taskRequest.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        if let tasks = try? storage.viewContext.fetch(taskRequest) {
            for task in tasks { storage.viewContext.delete(task) }
        }
    }
}
