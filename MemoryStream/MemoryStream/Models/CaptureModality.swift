import SwiftUI

/// One of the five things the FAB action stack can launch. Voice is the
/// privileged primary modality (taller pill, ochre border, leads stagger).
enum CaptureModality: String, CaseIterable, Identifiable {
    case voice
    case photo
    case video
    case note
    case attach

    var id: String { rawValue }

    /// Pill order, top → bottom in the open stack — so the **last element sits
    /// closest to the FAB**, and is the first thing her thumb reaches.
    ///
    /// **Reordered 2026-09-18 (Tom): voice is a recording MECHANISM, like
    /// video — not the product's centre of gravity.** The centre is writing,
    /// with things in it: she writes, and photographs and video sit in the
    /// flow. Voice held the closest-to-thumb slot because the product was
    /// conceived voice-first; `.note` holds it now and voice moves into the
    /// column.
    ///
    /// **This constant is the single owner of that emphasis.** `AppendFAB`
    /// renders it directly and the intro tour renders it `.reversed()`
    /// (per B31, which ruled that page 2 must be DRIVEN by `stackOrder` →
    /// `sfSymbol` + `color` rather than translating canvas glyphs by eye). So
    /// reordering here moves the FAB and the tour together, and nothing else
    /// needs to know.
    ///
    /// **The order is fixed by the TOUR's sequence, not the FAB's** (Tom,
    /// 2026-09-18). Reversed, this reads **pen → camera → camera → microphone
    /// → paperclip**, and the tour is where she learns the order. Putting the
    /// cameras ahead of the microphone IS the demotion — an arrangement that
    /// left voice second would have moved it off the thumb while still
    /// teaching it first, which is half a change.
    static let stackOrder: [CaptureModality] = [.attach, .voice, .video, .photo, .note]

    var label: String {
        switch self {
        case .voice:  return "Voice"
        case .photo:  return "Photo"
        case .video:  return "Video"
        case .note:   return "Note"
        case .attach: return "Attach"
        }
    }

    /// SF Symbol for the pill glyph. Each modality also tints its own glyph.
    var sfSymbol: String {
        switch self {
        case .voice:  return "mic"
        case .photo:  return "camera"
        case .video:  return "video"
        case .note:   return "text.alignleft"
        case .attach: return "photo.on.rectangle"
        }
    }

    var color: Color {
        switch self {
        case .voice:  return Crucible.Color.Media.audio
        case .photo:  return Crucible.Color.Media.photo
        case .video:  return Crucible.Color.Media.video
        case .note:   return Crucible.Color.Media.text
        case .attach: return Crucible.Color.Media.attach
        }
    }

    var isPrimary: Bool { self == .voice }
}

/// What a single-modality capture returns. The host view (JournalView for
/// capture-new, EntryExpandedView for append) maps each variant to the
/// appropriate lifecycle call.
enum CapturedItem {
    case voice(filename: String?, transcript: String)
    case photo(localIdentifier: String)
    case video(localIdentifier: String)
    case note(text: String)
    /// Library attach can return multiple items in a single picker session.
    /// Per `docs/design/Storage architecture · CLAUDE.md` Rule 1, the
    /// picker extracts bytes from each picked PHAsset and writes them
    /// into the ubiquity container; the `localIdentifier` here is the
    /// ubiquity filename, not a `PHAsset.localIdentifier`. The classifier
    /// runs at extraction time, so images and videos can be mixed in
    /// one pick without falsely tagging videos as images.
    case attach(items: [(localIdentifier: String, mediaType: MediaReference.MediaType)])
    /// Multi-clip voice session — produced by the "on a roll" Next
    /// gesture on phone (`docs/design/on-a-roll-spec.md`). The
    /// composer recorded one continuous master file, split it into
    /// N per-clip files at the Next-tap offsets, and re-transcribed
    /// each. All clips share the same `rollGroupId` so the host
    /// attaches them to one Memory.
    case voiceSession(clips: [VoiceClipFragment], rollGroupId: UUID)
}

/// One clip's worth of output from a phone voice session split.
struct VoiceClipFragment: Equatable {
    /// Filename in the SpeechService audio directory.
    let audioFilename: String
    /// Local transcript for this clip alone (re-transcribed
    /// post-split — not a substring of the master transcript).
    let transcript: String
    /// Clip duration in seconds.
    let duration: TimeInterval
    /// Wall-clock time the clip *started* recording — the moment
    /// the user tapped the big mic (clip 1) or the Next button
    /// (subsequent clips). Computed in `VoiceCaptureOrchestrator`
    /// as `recordingStartedAt + nextTapOffsetForThisClip` and
    /// threaded all the way to `MediaReference.createdAt` so the
    /// Memory Detail UI can show one accurate `HH:MM` per row of
    /// a long roll. Before this field shipped (Tom 2026-06-09)
    /// every roll clip inherited the save-time `Date()` and the
    /// Compact transcript view rendered identical timestamps on
    /// every row.
    let capturedAt: Date
    /// Latitude captured at recording-session start (one fix per
    /// session, mirrored across every clip in the session). Nil
    /// when the user denies / hasn't granted location, or the fix
    /// timed out. Powers the Memory Detail v3 clip-row header.
    var latitude: Double? = nil
    var longitude: Double? = nil
}

