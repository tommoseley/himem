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
/// - Title = `proposal.proposedName`
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
    @MainActor
    private static func commitOne(
        proposal: ClusterProposal,
        clips: [InboxClip],
        viewModel: JournalViewModel,
        storage: StorageService
    ) -> UUID? {
        // Move audio files out of the inbox into the voice store —
        // same handoff as `CreateMemoryFromClipsSheet.commit`.
        // Failed moves skip the clip; its inbox row stays for
        // retry on the next attempt.
        var captures: [(localIdentifier: String, mediaType: MediaReference.MediaType)] = []
        for clip in clips {
            let inboxURL = InboxManifest.audioURL(for: clip.audioFilename)
            let voiceURL = SpeechService.audioURL(for: clip.audioFilename)
            do {
                if FileManager.default.fileExists(atPath: voiceURL.path) {
                    try FileManager.default.removeItem(at: voiceURL)
                }
                try FileManager.default.moveItem(at: inboxURL, to: voiceURL)
                captures.append((clip.audioFilename, .voice))
            } catch {
                continue
            }
        }
        guard !captures.isEmpty else { return nil }

        let joinedTranscript = clips
            .map(\.transcript)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")

        let newId = viewModel.saveEntry(
            content: joinedTranscript,
            inputType: .voiceInApp,
            mediaCaptures: captures,
            topicName: nil
        )

        guard let newId else { return nil }

        // Post-save fixups — same shape as CreateMemoryFromClipsSheet.
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "id == %@", newId as CVarArg)
        request.fetchLimit = 1
        if let entry = try? storage.viewContext.fetch(request).first {
            entry.title = proposal.proposedName
        }
        for clip in clips where !clip.transcript.isEmpty {
            let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
            req.predicate = NSPredicate(format: "osIdentifier == %@", clip.audioFilename)
            req.fetchLimit = 1
            if let ref = try? storage.viewContext.fetch(req).first {
                ref.transcript = clip.transcript
            }
        }
        try? storage.save(context: storage.viewContext)

        // Stamp per-clip location.
        for clip in clips {
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
