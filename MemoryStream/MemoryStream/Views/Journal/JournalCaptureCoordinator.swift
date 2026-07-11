import Foundation
import SwiftUI

/// Per-modality dispatch for the "create new memory from this
/// captured item" path. Extracted from `JournalView` in the CRAP
/// audit 2026-05-28 (Batch 5) so the host body no longer carries a
/// 100-line switch and the create-spec is unit-testable.
///
/// Parallel to `EntryAppendCoordinator` (which routes captures into
/// an *existing* memory). Same modality coverage, same empty-input
/// guards — different terminal call (`viewModel.saveEntry` vs.
/// `lifecycle.append`).
///
/// **Stateless** by design — the view holds the modality binding
/// (`activeCaptureModality`) and the navigation target
/// (`selectedEntryId`). The coordinator is a pure dispatch surface;
/// caller seeds + clears any pendingNote state.
@MainActor
struct JournalCaptureCoordinator {

    init() {}

    /// Routes a captured item to the right `viewModel.saveEntry`
    /// call, returning the new entry's UUID for the caller to use
    /// for navigation (`selectedEntryId = newId`). Returns `nil`
    /// when the input is empty / would produce a phantom memory.
    ///
    /// - Parameter seedNote: optional text to prepend onto the
    ///   `.note` case body. Used by the Search → New Memory hand-
    ///   off (`pendingNoteForNewEntry`). For other cases, the seed
    ///   is ignored. Caller is responsible for clearing its own
    ///   `pendingNoteForNewEntry` state after a successful
    ///   `.note` dispatch.
    @discardableResult
    func createNewMemory(
        from item: CapturedItem,
        viewModel: JournalViewModel,
        seedNote: String?
    ) -> UUID? {
        switch item {
        case .voice(let filename, let transcript):
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard filename != nil || !trimmed.isEmpty else { return nil }
            return viewModel.saveEntry(
                content: trimmed,
                inputType: .voiceInApp,
                voiceFilename: filename
            )

        case .photo(let id):
            return viewModel.saveEntry(
                content: "",
                inputType: .camera,
                mediaCaptures: [(id, .image)]
            )

        case .video(let id):
            return viewModel.saveEntry(
                content: "",
                inputType: .camera,
                mediaCaptures: [(id, .video)]
            )

        case .note(let text):
            // Compose body from optional seed + composer text. The
            // caller (JournalView) tracks `pendingNoteForNewEntry`
            // and is expected to clear it after a successful
            // create — we don't want side effects in a pure
            // dispatch struct.
            let body: String
            if let pending = seedNote, !pending.isEmpty {
                body = pending + (text.isEmpty ? "" : "\n\n" + text)
            } else {
                body = text
            }
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let newId = viewModel.saveEntry(content: body, inputType: .typed)
            // Also create a `.note` MediaReference so the text shows
            // up in the chronological capture stream alongside any
            // later appends. Without this, the detail view would
            // only show photos/videos and the typed text would be
            // invisible until the user enters edit mode.
            if let id = newId {
                viewModel.createNoteFragment(forEntryId: id, text: body)
            }
            return newId

        case .attach(let items):
            guard !items.isEmpty else { return nil }
            // PHPicker import now classifies image-vs-video at
            // extraction time (see PhotoLibraryPicker.importToUbiquity)
            // and writes bytes directly to the ubiquity container. The
            // items carry the right `mediaType` per file — no more
            // "everything is .image" approximation.
            return viewModel.saveEntry(content: "", inputType: .camera, mediaCaptures: items)

        case .voiceSession(let clips, _):
            // "On a roll" — multi-clip phone voice session. First
            // clip creates the Memory; subsequent clips append
            // voice fragments to that same Memory so the whole
            // roll lands as one entry. `rollGroupId` is
            // informational; on phone the create-then-append path
            // is already in one memory by construction, so we
            // don't need to stamp it.
            guard let first = clips.first else { return nil }
            let newId = viewModel.saveEntry(
                content: first.transcript,
                inputType: .voiceInApp,
                voiceFilename: first.audioFilename,
                voiceCapturedAt: first.capturedAt
            )
            if let entryId = newId {
                for clip in clips.dropFirst() {
                    viewModel.appendToEntry(
                        entryId: entryId,
                        additionalContent: clip.transcript,
                        voiceFilename: clip.audioFilename,
                        voiceCapturedAt: clip.capturedAt
                    )
                }
            }
            // Stamp the session's location fix onto every fragment's
            // MediaReference + kick off reverse-geocode for the
            // clip-row header (Memory Detail v3). All clips in a
            // phone roll share the one session-start fix.
            for clip in clips {
                ClipLocationResolver.stamp(
                    osIdentifier: clip.audioFilename,
                    latitude: clip.latitude,
                    longitude: clip.longitude,
                    in: StorageService.shared.viewContext
                )
            }
            return newId
        }
    }

    /// Same dispatch as `createNewMemory(from:viewModel:seedNote:)`
    /// but routes through `EntryLifecycleService` directly. Used by
    /// the tab-level `HiMemTabView` capture flow, which shouldn't own
    /// a `JournalViewModel` (a second VM instance duplicates the
    /// `NSManagedObjectContextObjectsDidChange` observer and forces
    /// a redundant main-thread `loadEntries()` on every Core Data
    /// change — noticeably harmful during CloudKit import churn).
    ///
    /// The `viewModel`-based variant above updates the feed via
    /// `viewModel.loadEntries()` for its own subscribers; this variant
    /// relies on `JournalView`'s own viewModel to observe the Core
    /// Data change and refresh — one observer, one fetch.
    @discardableResult
    func createNewMemory(
        from item: CapturedItem,
        lifecycle: EntryLifecycleService,
        seedNote: String?
    ) -> UUID? {
        switch item {
        case .voice(let filename, let transcript):
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard filename != nil || !trimmed.isEmpty else { return nil }
            return lifecycle.save(
                content: trimmed,
                inputType: .voiceInApp,
                voiceFilename: filename
            )
        case .photo(let id):
            return lifecycle.save(
                content: "",
                inputType: .camera,
                mediaCaptures: [(id, .image)]
            )
        case .video(let id):
            return lifecycle.save(
                content: "",
                inputType: .camera,
                mediaCaptures: [(id, .video)]
            )
        case .note(let text):
            let body: String
            if let pending = seedNote, !pending.isEmpty {
                body = pending + (text.isEmpty ? "" : "\n\n" + text)
            } else {
                body = text
            }
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let newId = lifecycle.save(content: body, inputType: .typed)
            if let id = newId {
                _ = try? lifecycle.createNoteFragment(forEntryId: id, text: body)
            }
            return newId
        case .attach(let items):
            guard !items.isEmpty else { return nil }
            return lifecycle.save(content: "", inputType: .camera, mediaCaptures: items)
        case .voiceSession(let clips, _):
            guard let first = clips.first else { return nil }
            let newId = lifecycle.save(
                content: first.transcript,
                inputType: .voiceInApp,
                voiceFilename: first.audioFilename,
                voiceCapturedAt: first.capturedAt
            )
            if let entryId = newId {
                for clip in clips.dropFirst() {
                    lifecycle.append(
                        entryId: entryId,
                        additionalContent: clip.transcript,
                        voiceFilename: clip.audioFilename,
                        voiceCapturedAt: clip.capturedAt
                    )
                }
            }
            for clip in clips {
                ClipLocationResolver.stamp(
                    osIdentifier: clip.audioFilename,
                    latitude: clip.latitude,
                    longitude: clip.longitude,
                    in: StorageService.shared.viewContext
                )
            }
            return newId
        }
    }
}
