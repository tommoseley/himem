import Foundation
import CoreData

/// Dispatches a phone-side `CapturedItem` — from the Clips-tab FAB or
/// any surface that captures ad-hoc rather than structured — onto the
/// bench, per the July 10 2026 lock (`CLAUDE.md:142`).
///
/// The bench is source-agnostic — voice clips land in `InboxManifest`
/// as `InboxClip`s with `source == "phone"` (they sit alongside Watch
/// clips in `SessionListView`); photo/video/note captures land as
/// unplaced `MediaReference`s in Core Data (they surface in
/// `ClipsTabView.unplacedDayGroupedStack`).
///
/// Pure staging function — takes a `CapturedItem` and applies the
/// side effects (manifest write, Core Data insert). Returns nothing
/// because the caller (the FAB host) doesn't navigate — the July 10
/// lock says the clip *drops into the list already in view*, so the
/// UI reactively re-renders and no navigation intent is needed.
@MainActor
enum PhoneCaptureBenchDispatcher {

    /// The `source` value stamped on phone-FAB InboxClips. Distinct
    /// from `"watch"` so `SessionListView` (and any future per-source
    /// filter or glyph) can tell them apart.
    static let phoneSourceLabel = "phone"

    /// Route `item` onto the bench. Voice items grow `InboxManifest`;
    /// photo/video/note/attach items create unplaced `MediaReference`s
    /// in `context`.
    ///
    /// - Parameters:
    ///   - item: The captured payload from the composer.
    ///   - inbox: The manifest to write voice clips into. Defaults to
    ///     `.shared`; injectable for tests.
    ///   - context: The Core Data context to insert media refs into.
    ///     Defaults to `StorageService.shared.viewContext`.
    ///   - now: Injectable clock for tests.
    static func dispatch(
        _ item: CapturedItem,
        inbox: InboxManifest = .shared,
        context: NSManagedObjectContext = StorageService.shared.viewContext,
        now: Date = Date()
    ) {
        switch item {
        case .voice(let filename, let transcript):
            let audioFilename = filename ?? ""
            guard !audioFilename.isEmpty else { return }
            let clip = InboxClip(
                clipId: UUID(),
                capturedAt: now,
                duration: 0,
                transcript: transcript,
                latitude: nil,
                longitude: nil,
                source: phoneSourceLabel,
                audioFilename: audioFilename,
                transcriptionAttempted: !transcript.isEmpty,
                rollGroupId: nil,
                status: transcript.isEmpty ? .received : .transcribed
            )
            inbox.acceptClip(clip)

        case .voiceSession(let clips, let rollGroupId):
            // Phone roll — one rollGroupId across all children so
            // `ClipSessionGrouper` bundles them into one session card,
            // matching the watch roll behavior. Reuse the roll id the
            // composer already produced so the phone-splitter side
            // and bench view agree on grouping.
            for c in clips {
                let clip = InboxClip(
                    clipId: UUID(),
                    capturedAt: c.capturedAt,
                    duration: c.duration,
                    transcript: c.transcript,
                    latitude: c.latitude,
                    longitude: c.longitude,
                    source: phoneSourceLabel,
                    audioFilename: c.audioFilename,
                    transcriptionAttempted: !c.transcript.isEmpty,
                    rollGroupId: rollGroupId,
                    status: c.transcript.isEmpty ? .received : .transcribed
                )
                inbox.acceptClip(clip)
            }

        case .photo(let localIdentifier):
            insertUnplacedRef(osIdentifier: localIdentifier, mediaType: .image, text: nil, in: context, now: now)
        case .video(let localIdentifier):
            insertUnplacedRef(osIdentifier: localIdentifier, mediaType: .video, text: nil, in: context, now: now)
        case .note(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            insertUnplacedRef(
                osIdentifier: UUID().uuidString,
                mediaType: .note,
                text: trimmed,
                in: context,
                now: now
            )
        case .attach(let items):
            for (id, type) in items {
                insertUnplacedRef(osIdentifier: id, mediaType: type, text: nil, in: context, now: now)
            }
        }
    }

    /// Insert a `MediaReference` with no edge — it lives in the
    /// unplaced day-grouped stack at the top of the Clips tab
    /// (`ClipsTabView.unplacedDayGroupedStack`) until the user
    /// places it into a memory.
    private static func insertUnplacedRef(
        osIdentifier: String,
        mediaType: MediaReference.MediaType,
        text: String?,
        in context: NSManagedObjectContext,
        now: Date
    ) {
        let ref = MediaReference(context: context)
        ref.id = UUID()
        ref.osIdentifier = osIdentifier
        ref.mediaType = mediaType.rawValue
        ref.createdAt = now
        if let text {
            ref.text = text
        }
        try? context.save()
    }
}
