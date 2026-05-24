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

    /// Pill order, top → bottom in the open stack. Voice sits closest to the
    /// FAB (bottom of the column, last in the array) per the Append spec.
    static let stackOrder: [CaptureModality] = [.attach, .note, .video, .photo, .voice]

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
    case attach(localIdentifiers: [String])
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
    /// Latitude captured at recording-session start (one fix per
    /// session, mirrored across every clip in the session). Nil
    /// when the user denies / hasn't granted location, or the fix
    /// timed out. Powers the Memory Detail v3 clip-row header.
    var latitude: Double? = nil
    var longitude: Double? = nil
}

