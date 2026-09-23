import Foundation
import CoreData

/// Materializes a fully-received + transcribed bench `InboxClip` into a
/// **zero-edge `MediaReference`** — the P0-3 single-source-of-truth move
/// (`docs/architecture/2026-07-25-clip-sync-single-source-of-truth.md`). The
/// ref CloudKit-syncs, so the clip reaches every device (fixes the
/// iPad-invisible bench). Runs on transcription-complete: a materialized ref is
/// by definition post-attempt, and in-flight/transcribing clips stay in the
/// manifest — so the accidental/transcribing/failed state is *derived from
/// which store the clip lives in*, never a stored flag that can disagree
/// (Tom, 2026-07-25: a design improvement, the same discipline as edge-derived
/// connection count).
///
/// - **Idempotent on `id == clipId`.** The clip's own id becomes the ref's id,
///   so the same clip materialized on two devices (or replayed on reinstall)
///   converges to one CloudKit record (last-writer-wins on the record id).
/// - **Manifest demoted.** `removeBatch` drops the active row AND leaves a
///   `.disposed` tombstone — the exact "promote + gate watch redelivery"
///   pattern placement already uses (risk-3: the tombstone survives; the
///   manifest is retained purely as a tombstone ledger).
enum ArrivedClipMaterializer {

    /// Materialize `clip` into a memory, joining its **roll** if it has one.
    /// Returns the memory's id, or nil if there was nothing to materialize.
    /// Safe to call repeatedly.
    ///
    /// **A roll is one memory** (`On a roll · spec.md`, CURRENT): every tap of
    /// *Next* commits a recording and starts another without stopping the
    /// waveform, and all of them share a `rollGroupId` stamped at session
    /// start. On arrival that id is *"a deterministic override of the time/place
    /// session heuristics — same roll, same memory"*, and the tap boundaries
    /// become paragraph breaks, which is what she meant by tapping.
    ///
    /// **The defect this replaces.** §1 created one memory per arrived clip and
    /// never read `rollGroupId`, so four taps of Next produced five memories —
    /// the feature that exists to keep one train of thought together was the
    /// thing that scattered it. Money-tested by
    /// `WatchRollArrivesAsOneMemoryTests`.
    ///
    /// **Why the roll key is the memory's id.** Each tap is its own transfer
    /// unit with no transaction around the roll, so taps land one at a time and
    /// *"if 3 of 5 arrive, they form the memory and the remaining 2 join it
    /// when they land."* Keying the memory on `rollGroupId` makes that join a
    /// lookup rather than a reconciliation: whichever tap lands first creates
    /// the memory, every later one finds it. Keying on the first clip's id
    /// could not — "first" is not known until the roll is complete.
    @discardableResult
    @MainActor
    static func materialize(
        _ clip: InboxClip,
        in context: NSManagedObjectContext,
        deleteAudio: (String) -> Bool = deleteArrivedAudio
    ) -> UUID? {
        let memoryId = memoryId(for: clip)

        if let existing = entry(id: memoryId, in: context) {
            // **An un-rolled clip whose memory already exists is a REPLAY**,
            // and there is no other way for that memory to exist — its id is
            // this clip's id. Return without side effects, exactly as the
            // pre-roll code did: `idempotentPassDoesNotRedelete` caught the
            // first version of this fix deleting the audio a second time.
            guard clip.rollGroupId != nil else { return memoryId }

            // A later tap of a roll she is still on. Append rather than skip —
            // returning here is what would make taps 2..n vanish once the
            // first had created the memory.
            append(clip, to: existing)
        } else {
            let entry = JournalEntry(context: context)
            // **KEY: the memory takes the ROLL's id, or the clip's own when
            // there is no roll**, for the two reasons the clip id was used
            // before — the drain can run repeatedly without duplicating, and
            // two devices materializing the same arrival converge on ONE
            // CloudKit record rather than racing to create two memories.
            // `StorageService.createEntry` mints its own UUID, so this path
            // builds the entry directly: the id is the invariant, not the
            // convenience.
            entry.id = memoryId
            entry.content = clip.transcript
            entry.inputType = JournalEntry.InputType.voiceInApp.rawValue
            entry.sourceDevice = clip.source
            entry.createdAt = clip.capturedAt
            // `title` is DELIBERATELY NOT TOUCHED, not even to nil. This is an
            // automatic path, and `TitleAuthorshipTests.noAutomaticPathWritesTheTitle`
            // scans for any write to `entry.title` outside a user-initiated one —
            // there is no `titleUserEdited` marker to fall back on, so that scan is
            // the only guarantee. Writing nil would satisfy the intent and still
            // break the property the scanner reports. Core Data leaves it nil;
            // Organize names the memory, when she asks.
        }
        try? context.save()

        // **The audio is discarded — this is the point of the change.** It was
        // moved into the voice store here; now it is deleted, because the words
        // are the artifact and the recording is how they arrived. Ordered AFTER
        // the save so a crash between the two loses the file rather than the
        // words, which is the survivable direction.
        _ = deleteAudio(clip.audioFilename)

        // Demote the manifest active row → the memory is now the only record.
        // Tombstones the clip, gating a late watch redelivery (risk-3).
        InboxManifest.shared.removeBatch(clipIds: [clip.clipId])
        return memoryId
    }

    /// Materialize a batch, **sorted so a roll's paragraphs land in capture
    /// order** rather than in whatever order the transfers completed. Arrival
    /// order is not a promise the transport makes; capture time is.
    @MainActor
    static func materialize(
        _ clips: [InboxClip],
        in context: NSManagedObjectContext,
        deleteAudio: (String) -> Bool = deleteArrivedAudio
    ) {
        for clip in clips.sorted(by: { $0.capturedAt < $1.capturedAt }) {
            _ = materialize(clip, in: context, deleteAudio: deleteAudio)
        }
    }

    /// The memory a clip belongs to. **Pure** — the whole roll rule in one
    /// line, so it can be asserted without a Core Data stack.
    static func memoryId(for clip: InboxClip) -> UUID {
        clip.rollGroupId ?? clip.clipId
    }

    /// Adds a later tap's words to the roll's memory as a new paragraph.
    ///
    /// - **A silent tap adds nothing.** An empty transcript would otherwise
    ///   open a blank paragraph — a gap she did not make.
    /// - **Already-present text is not re-appended.** The drain is safe to call
    ///   repeatedly by design, and a replayed tap must not double its words.
    ///   Matched on whole paragraphs, the same shape of dedup
    ///   `FragmentMigration` uses, because there is nowhere to store a
    ///   per-paragraph ledger without a CloudKit schema change — and that
    ///   change costs a Production deploy and a migration to buy nothing the
    ///   user can see.
    ///
    ///   **The limit, stated rather than discovered later:** two taps in one
    ///   roll whose transcripts are byte-identical ("okay" … "okay") collapse
    ///   to one paragraph. Replay-safety is load-bearing and this edge is not,
    ///   so the trade is deliberate.
    /// - **An out-of-order tap pulls `createdAt` back.** The memory is stamped
    ///   when the roll began, not when its stragglers landed. Its words still
    ///   append at the end; within a single batch that never arises, because
    ///   the batch path sorts first.
    @MainActor
    private static func append(_ clip: InboxClip, to entry: JournalEntry) {
        let words = clip.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let already = entry.content.components(separatedBy: "\n\n").contains(words)
        if !words.isEmpty && !already {
            entry.content = entry.content.isEmpty ? words : entry.content + "\n\n" + words
        }
        if clip.capturedAt < entry.createdAt { entry.createdAt = clip.capturedAt }
    }

    /// The memory with this id, if it exists.
    @MainActor
    private static func entry(id: UUID, in context: NSManagedObjectContext) -> JournalEntry? {
        let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return (try? context.fetch(req))?.first
    }

    /// Drain every fully-transcribed manifest row into a zero-edge ref. This is
    /// the choke point: it doubles as the **one-shot launch migration** (first
    /// call after upgrade sweeps every pre-existing `.transcribed` clip) and the
    /// **catch-up** for a clip that finished transcribing while the bench was
    /// closed. Idempotent and cheap — only `.transcribed` rows are eligible, and
    /// each is guarded by `refExists`. In-flight/transcribing rows and disposed
    /// tombstones are untouched (manifest = in-flight transfer state only).
    ///
    /// Called before the bench first renders (piece B) so a clip is only ever in
    /// ONE store at read time — the structural guarantee against double-render
    /// (risk-1), backing the id-keyed dedup belt at the compose layer.
    /// Returns the number of clips materialized this pass.
    @discardableResult
    @MainActor
    static func materializeAll(
        in context: NSManagedObjectContext,
        deleteAudio: (String) -> Bool = deleteArrivedAudio
    ) -> Int {
        // **Sorted by capture time**, because this is the path that drains a
        // whole roll at once — the launch migration and the catch-up after the
        // app was closed while taps were landing. Feeding it in manifest order
        // would join a roll's paragraphs in whatever order the rows happen to
        // sit in `manifest.json`.
        let transcribed = InboxManifest.shared.clips
            .filter { $0.status == .transcribed }
            .sorted { $0.capturedAt < $1.capturedAt }
        var count = 0
        for clip in transcribed where materialize(clip, in: context, deleteAudio: deleteAudio) != nil { count += 1 }
        return count
    }

    /// Compose the unified bench list from the two stores, deduped by clipId —
    /// a materialized **ref WINS** over a stale manifest row. This is the
    /// compose-layer double-render guard (risk-1, P0): during the migration
    /// window a clip can transiently exist as both a manifest row and its ref;
    /// keying by id collapses them to one, and the ref (the source of truth)
    /// is the survivor. Pure + order-independent so it's directly testable.
    @MainActor
    static func composeBenchClips(manifestClips: [InboxClip], refs: [MediaReference]) -> [InboxClip] {
        var byId: [UUID: InboxClip] = [:]
        for clip in manifestClips { byId[clip.clipId] = clip }
        for ref in refs { let synth = syntheticClip(from: ref); byId[synth.clipId] = synth }
        return Array(byId.values)
    }

    /// Read-side bridge (piece B): map a materialized zero-edge voice ref back
    /// to a synthetic `InboxClip` so the existing bench grouper / proposer /
    /// absorber / render path runs UNCHANGED against the ref store. The inverse
    /// of `materialize` — same `id`, so the compose-layer dedup stays id-keyed.
    ///
    /// - `transcriptionAttempted: true` — a materialized ref is post-attempt by
    ///   construction (design decision #1: state derived from store position).
    /// - `status: .transcribed` — likewise.
    /// - `duration` — read from the per-device `BenchClipDurationStore` (the
    ///   ref has no duration attribute). Real on the originating device; a
    ///   receive-only device degrades to 0 (ruling a) until an async
    ///   `AVURLAsset.load(.duration)` follow-up lands.
    /// - `reviewed` — read from the per-device `BenchClipReviewStore` (risk-2).
    static func syntheticClip(from ref: MediaReference) -> InboxClip {
        InboxClip(
            clipId: ref.id,
            capturedAt: ref.createdAt ?? Date(timeIntervalSince1970: 0),
            duration: BenchClipDurationStore.duration(ref.id) ?? 0,
            transcript: ref.transcript ?? "",
            latitude: ref.latitude?.doubleValue,
            longitude: ref.longitude?.doubleValue,
            source: ref.sourceDevice ?? "",
            audioFilename: ref.osIdentifier,
            transcriptionAttempted: true,
            rollGroupId: ref.rollGroupId,
            status: .transcribed,
            reviewed: BenchClipReviewStore.isReviewed(ref.id)
        )
    }

    /// True when a memory with this id already exists — the idempotency guard,
    /// and the belt against a double-materialize or a cross-device race.
    static func entryExists(id: UUID, in context: NSManagedObjectContext) -> Bool {
        let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return ((try? context.count(for: req)) ?? 0) > 0
    }

    /// True when a `MediaReference` with this id already exists — the
    /// idempotency guard (also the belt against a double-materialize).
    static func refExists(id: UUID, in context: NSManagedObjectContext) -> Bool {
        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return ((try? context.count(for: req)) ?? 0) > 0
    }

    /// **Discard the arrived audio.** It has been transcribed; the words are in
    /// the memory; the recording has done its job.
    ///
    /// Supersedes `moveAudioToVoiceStore`, which moved the file `Inbox/ →
    /// Audio/` so a voice ref could resolve it. There is no voice ref and no
    /// playback: *audio is not stored, anywhere* (2026-09-17, retiring "audio
    /// is the source of truth"). A bad transcription is corrected by editing
    /// the text.
    ///
    /// Tries both locations because a redelivery can land a fresh copy in
    /// `Inbox/` after an earlier pass, and historical installs may still hold
    /// files under `Audio/`. Returns true when nothing remains either way —
    /// absence is success here, not failure.
    @discardableResult
    static func deleteArrivedAudio(_ filename: String) -> Bool {
        guard !filename.isEmpty else { return true }
        // `removeFromStore` refuses anything outside our own store root, which
        // is the guard that keeps this from ever reaching a foreign URL.
        for url in [InboxManifest.audioURL(for: filename), SpeechService.audioURL(for: filename)]
        where FileManager.default.fileExists(atPath: url.path) {
            UbiquityStore.shared.removeFromStore(reason: "watch-arrival-transcribed-audio-discarded", at: url)
        }
        return true
    }

    /// Move the clip's audio `Inbox/ → Audio/` so `MediaResolver` finds it
    /// (voice refs resolve from the Audio dir). Both dirs are in the ubiquity
    /// container, so this is an intra-container rename, not a blob relocation.
    static func moveAudioToVoiceStore(_ filename: String) -> Bool {
        let voiceURL = SpeechService.audioURL(for: filename)
        if FileManager.default.fileExists(atPath: voiceURL.path) { return true }
        let inboxURL = InboxManifest.audioURL(for: filename)
        guard FileManager.default.fileExists(atPath: inboxURL.path) else { return false }
        do {
            _ = try UbiquityStore.shared.moveIntoStore(sourceURL: inboxURL, destinationURL: voiceURL)
            return true
        } catch {
            NSLog("[HiMem][Materialize] audio move failed for \(filename): \(error.localizedDescription)")
            return false
        }
    }
}
