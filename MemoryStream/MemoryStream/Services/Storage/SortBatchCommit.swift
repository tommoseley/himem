import Foundation
import CoreData

/// Batch commit for the Captured Clips workbench Sort layer. Given
/// N `ClusterProposal`s + their live `InboxClip`s, creates N draft
/// Memories in one call — no post-commit sheets, no per-cluster
/// review dialog. Per `docs/design/Captured Clips · session-first ·
/// spec.md` v3 § "Sort is the moment":
///
/// > One tap makes each cluster its own draft Memory, batched — no
/// > confirmation sheet(s) after. The Sort screen was the review.
///
/// Each new entry:
/// - Title = **none** — a memory made from a proposal arrives untitled (B17(a))
/// - Content = clips' transcripts joined
/// - Media = one `.voice` MediaReference per clip, with per-clip
///   transcripts + lat/lon stamped
/// - Committed via `EntryLifecycleService.save` through the same
///   `JournalViewModel.saveEntry` path as `CreateMemoryFromClipsSheet`
///
/// After the commit, the source clipIds leave the inbox manifest —
/// their dismissal records (if any) get pruned automatically by
/// `InboxManifest.replace(with:)`'s prune-on-write hook.
///
/// Best-effort: individual proposal failures don't abort the batch;
/// each cluster is independent. Returns the entry IDs of the
/// successful commits.
enum SortBatchCommit {

    /// Commits N clusters as N draft Memories. Callers pass a
    /// resolved `[(ClusterProposal, [InboxClip])]` pair list so the
    /// service doesn't need to reach into the manifest itself —
    /// keeps the commit pure over its inputs.
    @MainActor
    @discardableResult
    static func commit(
        _ proposals: [(proposal: ClusterProposal, clips: [InboxClip])],
        viewModel: JournalViewModel,
        storage: StorageService
    ) -> [UUID] {
        var newEntryIds: [UUID] = []
        for (proposal, clips) in proposals {
            guard !clips.isEmpty else { continue }
            if let id = commitOne(proposal: proposal, clips: clips, viewModel: viewModel, storage: storage) {
                newEntryIds.append(id)
            }
        }
        // Any clip that got successfully committed (i.e. its audio
        // file moved out of the inbox) leaves the manifest. Skipped
        // clips stay put for the next attempt.
        let committedClipIds = proposals
            .flatMap { pair -> [UUID] in
                // Only remove clips whose file made it into the
                // voice store — matches the `captures` filter
                // inside `commitOne`.
                let clipsWithMovedAudio = pair.clips.filter { clip in
                    FileManager.default.fileExists(atPath: SpeechService.audioURL(for: clip.audioFilename).path)
                }
                return clipsWithMovedAudio.map(\.clipId)
            }
        if !committedClipIds.isEmpty {
            InboxManifest.shared.removeBatch(clipIds: committedClipIds)
        }
        return newEntryIds
    }

    /// Commits a single cluster proposal as one draft Memory.
    /// Extracted so the loop above stays legible.
    ///
    /// Post-Phase-2+3: each clip is written directly via
    /// `storage.createVoiceFragment(createdAt:)` which creates the
    /// `MediaReference` + its `MemoryClipEdge` atomically with the
    /// clip's actual `capturedAt`. The pre-Phase-2+3 post-save fixup
    /// loop that patched `ref.createdAt` after `saveEntry` is retired
    /// (root cause was the `mediaCaptures` tuple's missing capturedAt
    /// slot; this path bypasses the tuple entirely).
    @MainActor
    private static func commitOne(
        proposal: ClusterProposal,
        clips: [InboxClip],
        viewModel: JournalViewModel,
        storage: StorageService
    ) -> UUID? {
        // Move audio files out of the inbox into the voice store —
        // same handoff as `CreateMemoryFromClipsSheet.commit`. Failed
        // moves skip the clip; its inbox row stays for retry on the
        // next attempt.
        //
        // **Where the audio lives depends on source.** Watch clips
        // land at `InboxManifest.audioURL` (`Documents/Inbox/`) and
        // need the move to `SpeechService.audioURL` (`Documents/
        // Audio/`). Phone clips are written directly at
        // `SpeechService.audioURL` — they were never in the inbox
        // directory. Pre-fix (July 2026 troika-diagnosed data-loss
        // bug) this code assumed every clip was watch-origin: it
        // unconditionally `removeItem(voiceURL)` before the move.
        // For phone clips `voiceURL` IS the actual audio, so the
        // pre-move remove deleted the user's recording; the move
        // then failed silently because `inboxURL` never existed.
        // Net effect: audio lost, clip silently dropped from the
        // batch, memory created with no fragments (or Sort commit
        // silently no-oped).
        var movedClips: [InboxClip] = []
        let fm = FileManager.default
        for clip in clips {
            let inboxURL = InboxManifest.audioURL(for: clip.audioFilename)
            let voiceURL = SpeechService.audioURL(for: clip.audioFilename)
            if fm.fileExists(atPath: voiceURL.path) {
                // Already at the destination (phone clip, or a prior
                // partial run). No file move needed.
                movedClips.append(clip)
                continue
            }
            do {
                try fm.moveItem(at: inboxURL, to: voiceURL)
                movedClips.append(clip)
            } catch {
                NSLog("[HiMem][SortBatch] move failed for clip=\(clip.clipId.uuidString.prefix(8)) source=\(clip.source) file=\(clip.audioFilename) error=\(error.localizedDescription)")
                continue
            }
        }
        guard !movedClips.isEmpty else { return nil }

        let joinedTranscript = movedClips
            .map(\.transcript)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")

        // Create the entry with no mediaCaptures — voice fragments are
        // written explicitly below so their per-clip capturedAt lands
        // on the ref at creation time (and creates the edge atomically).
        let newId = viewModel.saveEntry(
            content: joinedTranscript,
            inputType: .voiceInApp,
            topicName: nil
        )
        guard let newId else { return nil }

        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "id == %@", newId as CVarArg)
        request.fetchLimit = 1
        guard let entry = try? storage.viewContext.fetch(request).first else { return nil }
        // **B17(a), ruled 2026-08-18: no title from the proposal.** A memory
        // made from a proposal arrives untitled so Organize or the user names
        // it. Fixed here even though this file has **zero production callers**
        // today (J2 retired the single batch commit) — an unreachable file that
        // still assigns the title is exactly how a retired behaviour returns
        // when someone revives it, which is the `UnifiedBenchGrouper` /
        // `MediaBlobOrphanSweep` shape this project keeps paying for.

        for clip in movedClips.sorted(by: { $0.capturedAt < $1.capturedAt }) {
            _ = try? storage.createVoiceFragment(
                for: entry,
                audioFilename: clip.audioFilename,
                transcript: clip.transcript,
                createdAt: clip.capturedAt,
                // Carry the inbox clip's origin onto the ref (B4) — a watch
                // clip promoted to a memory keeps its applewatch glyph.
                sourceDevice: JournalEntry.SourceDevice(rawValue: clip.source)
            )
        }
        try? storage.save(context: storage.viewContext)

        // Stamp per-clip location.
        for clip in movedClips {
            ClipLocationResolver.stamp(
                osIdentifier: clip.audioFilename,
                latitude: clip.latitude,
                longitude: clip.longitude,
                in: storage.viewContext
            )
        }

        return newId
    }
}
