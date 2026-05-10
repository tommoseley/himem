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
}

