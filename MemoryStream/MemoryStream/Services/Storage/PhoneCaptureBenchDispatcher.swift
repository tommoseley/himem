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
                // **"Ran and found nothing" is not "still running" (2026-08-22).**
                // These were `!transcript.isEmpty` / `transcript.isEmpty ? .received : .transcribed`,
                // which wrote `false` / `.received` in exactly the case
                // `transcriptionAttempted` exists to record as true — its own doc:
                // *"True after the iPhone-side speech recognizer has run for this
                // clip, EVEN IF IT RETURNED NO TEXT. Combined with
                // `transcript.isEmpty` this distinguishes 'still in flight' from
                // 'ran, found no speech'."* The consequence was not cosmetic:
                // `accidentalClips` needs `transcript.isEmpty && transcriptionAttempted`,
                // so a no-speech phone clip could never be accidental, never
                // rendered "N clips auto-excluded · no speech", and
                // `collapsedBodyVariant` reported `.transcribing` — a finished
                // recording presented as one still being worked on.
                //
                // Unconditional `true` is a precondition of arriving here, not an
                // assumption: `SpeechService.startRecording` returns early — no
                // recording, no file — unless `isAuthorized` AND the analyzer,
                // transcriber and format are prepared, and phone capture
                // transcribes live. Guarded by
                // `PhoneCaptureBenchDispatcherTests.theDispatcherOnlyReceivesPostRecognizerItems`,
                // which fails if a dispatch appears outside the two post-recording
                // call sites.
                transcriptionAttempted: true,
                rollGroupId: nil,
                status: .transcribed
            )
            inbox.acceptClip(clip)

        case .voiceSession(let clips, let rollGroupId):
            // Phone roll — one rollGroupId across all children so
            // `ClipSessionGrouper` bundles them into one session card,
            // matching the watch roll behavior. Reuse the roll id the
            // composer already produced so the phone-splitter side
            // and bench view agree on grouping.
            // Per-clip existence trace so we can see whether the
            // audio file is on disk at the moment the clip enters
            // the manifest. Filter Console for `[HiMem][Dispatcher]`
            // to see the write chain.
            let fm = FileManager.default
            for (idx, c) in clips.enumerated() {
                let url = InboxManifest.audioURL(for: c.audioFilename)
                let voiceURL = SpeechService.audioURL(for: c.audioFilename)
                let inboxExists = fm.fileExists(atPath: url.path)
                let voiceExists = fm.fileExists(atPath: voiceURL.path)
                NSLog("[HiMem][Dispatcher] voiceSession[\(idx)/\(clips.count)] rollGroup=\(rollGroupId.uuidString.prefix(8)) file=\(c.audioFilename) inbox=\(inboxExists) audio=\(voiceExists)")
                let clip = InboxClip(
                    clipId: UUID(),
                    capturedAt: c.capturedAt,
                    duration: c.duration,
                    transcript: c.transcript,
                    latitude: c.latitude,
                    longitude: c.longitude,
                    source: phoneSourceLabel,
                    audioFilename: c.audioFilename,
                    // Same fix as the `.voice` case above, and it must land in
                    // both: the roll splitter re-transcribes every fragment, so
                    // every fragment has been attempted. Fixing one site and not
                    // the other is the near-duplicate-procedure shape F6a names.
                    transcriptionAttempted: true,
                    rollGroupId: rollGroupId,
                    status: .transcribed
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
        // Phone Clips-tab ad-hoc capture — always phone-sourced (B4).
        ref.sourceDevice = JournalEntry.SourceDevice.phone.rawValue
        if let text {
            ref.text = text
        }
        try? context.save()
    }
}
