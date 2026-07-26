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

    /// Materialize `clip`. Returns the ref id (== clipId) on success, nil if the
    /// audio can't be located anywhere (nothing to materialize). Safe to call
    /// repeatedly — a second call no-ops via the id lookup.
    @discardableResult
    @MainActor
    static func materialize(
        _ clip: InboxClip,
        in context: NSManagedObjectContext,
        moveAudio: (String) -> Bool = moveAudioToVoiceStore
    ) -> UUID? {
        if refExists(id: clip.clipId, in: context) { return clip.clipId }
        guard moveAudio(clip.audioFilename) else { return nil }

        let ref = MediaReference(context: context)
        ref.id = clip.clipId                    // KEY: dedup + cross-device convergence
        ref.osIdentifier = clip.audioFilename
        ref.mediaType = MediaReference.MediaType.voice.rawValue
        ref.createdAt = clip.capturedAt
        ref.transcript = clip.transcript
        ref.rollGroupId = clip.rollGroupId
        ref.latitude = clip.latitude.map { NSNumber(value: $0) }
        ref.longitude = clip.longitude.map { NSNumber(value: $0) }
        ref.sourceDevice = clip.source
        ref.isAccessible = true
        try? context.save()

        // Per-device `reviewed` carries into the ref-keyed store (stays
        // per-device by design — risk-2, not synced).
        if clip.reviewed { BenchClipReviewStore.markReviewed(clip.clipId) }
        // Cache the payload duration (the ref has no duration attribute) so the
        // bench card shows real session length on the originating device.
        BenchClipDurationStore.record(clip.clipId, clip.duration)
        // Demote the manifest active row → ref is now the source of truth.
        // Tombstones the clip, gating a late watch redelivery (risk-3).
        InboxManifest.shared.removeBatch(clipIds: [clip.clipId])
        return clip.clipId
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
        moveAudio: (String) -> Bool = moveAudioToVoiceStore
    ) -> Int {
        let transcribed = InboxManifest.shared.clips.filter { $0.status == .transcribed }
        var count = 0
        for clip in transcribed where materialize(clip, in: context, moveAudio: moveAudio) != nil { count += 1 }
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

    /// True when a `MediaReference` with this id already exists — the
    /// idempotency guard (also the belt against a double-materialize).
    static func refExists(id: UUID, in context: NSManagedObjectContext) -> Bool {
        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return ((try? context.count(for: req)) ?? 0) > 0
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
