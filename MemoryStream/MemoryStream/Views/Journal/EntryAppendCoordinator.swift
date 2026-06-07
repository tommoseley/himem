import Foundation
import CoreData
import SwiftUI

/// Owns the append-spec capture cycle for a single Memory Detail.
/// Extracted from `EntryExpandedView` in the CRAP audit 2026-05-28
/// (Batch 2) so the per-modality dispatch is unit-testable without
/// rendering and the host view no longer carries `CaptureModality?`
/// state alongside its read/edit-mode state cluster.
///
/// **State held here:**
///   - `activeCaptureModality` — drives `.captureFlowHost(...)` from
///     the view. The FAB selects a modality, the flow host presents,
///     the result lands in `apply(...)` which calls `lifecycle.append`.
///
/// **Logic held here:**
///   - `apply(_:to:using:context:)` — per-modality dispatch, with
///     empty-input guards so an aborted/empty capture doesn't
///     pollute the host memory with a no-op fragment.
///
/// The view keeps the per-panel sheet bindings (audioPlayerForFile,
/// noteEditorTarget) for now — moving those into
/// `ChronologicalCaptureStream` is a separate restructuring of the
/// SwiftUI hierarchy and was deferred from this batch.
@MainActor
final class EntryAppendCoordinator: ObservableObject {

    /// The capture modality the user picked from the FAB. The host
    /// view binds this to `.captureFlowHost(activeModality: $...)`
    /// which presents the right composer / picker. Cleared by the
    /// flow host on dismiss.
    @Published var activeCaptureModality: CaptureModality?

    init() {}

    /// Routes a captured item to the right `lifecycle.append` call
    /// for the given entry. Guards on empty inputs (`.voice` with
    /// no audio + no transcript, `.note` whitespace, `.attach`
    /// empty list, `.voiceSession` empty clips) so the host memory
    /// doesn't accrete phantom fragments.
    ///
    /// For `.voiceSession` (On a roll), each clip becomes its own
    /// voice fragment AND the session's location fix is stamped
    /// onto every appended clip via `ClipLocationResolver` so the
    /// clip-row header (Memory Detail v3) can render the place.
    func apply(
        _ item: CapturedItem,
        to entryId: UUID,
        using lifecycle: EntryLifecycleService,
        context: NSManagedObjectContext
    ) {
        switch item {
        case .voice(let filename, let transcript):
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard filename != nil || !trimmed.isEmpty else { return }
            lifecycle.append(
                entryId: entryId,
                additionalContent: trimmed,
                voiceFilename: filename
            )

        case .photo(let id):
            lifecycle.append(
                entryId: entryId,
                additionalContent: "",
                mediaCaptures: [(id, .image)]
            )

        case .video(let id):
            lifecycle.append(
                entryId: entryId,
                additionalContent: "",
                mediaCaptures: [(id, .video)]
            )

        case .note(let text):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            lifecycle.append(entryId: entryId, additionalContent: text)

        case .attach(let items):
            guard !items.isEmpty else { return }
            // PHPicker import now classifies image-vs-video at
            // extraction time (see PhotoLibraryPicker.importToUbiquity).
            lifecycle.append(entryId: entryId, additionalContent: "", mediaCaptures: items)

        case .voiceSession(let clips, _):
            // "On a roll" — append every clip in the session as its
            // own voice fragment on this Memory.
            for clip in clips {
                lifecycle.append(
                    entryId: entryId,
                    additionalContent: clip.transcript,
                    voiceFilename: clip.audioFilename
                )
            }
            // Stamp the session's location fix onto every appended
            // fragment + kick off reverse-geocode for the clip-row
            // header (Memory Detail v3). Mirrors the watch's
            // location-stamp pattern.
            for clip in clips {
                ClipLocationResolver.stamp(
                    osIdentifier: clip.audioFilename,
                    latitude: clip.latitude,
                    longitude: clip.longitude,
                    in: context
                )
            }
        }
    }
}
