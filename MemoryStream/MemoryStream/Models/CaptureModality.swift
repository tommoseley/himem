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
    /// **`.voice` left the stack in §5.4 (2026-09-24).** Phone voice capture
    /// retired as a *part*: speech used to enter words is the system
    /// keyboard's microphone, an input method the OS already provides, not a
    /// kind of content HiMem models.
    ///
    /// The case itself is deliberately **kept** on the enum. The descoping is
    /// explicit that HiMem's own microphone survives as *"record sound into
    /// this memory"* — deliberate audio, where the sound is the thing being
    /// kept — and that *"whether deliberate audio capture ships in 1.0 is a
    /// scheduling question; it is not something to architecturally
    /// foreclose."*
    ///
    /// So this is an array entry, one line to reverse, rather than a type
    /// change. What it must NOT come back as is a surface rebuilt from the
    /// file-writing half §5.4 retires — that would drag the retired half
    /// forward to keep a tool alive. It returns as canvas work, built for
    /// recording sound rather than for talking instead of typing.
    static let stackOrder: [CaptureModality] = [.attach, .video, .photo, .note]

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

    // `isPrimary` was deleted 2026-09-24. It read `self == .voice` and drove
    // NINE visual properties in `AppendFAB` — pill height 64 vs 52, label 17
    // vs 15, glyph chip 44 vs 36, glyph 22 vs 18, trailing pad, an accent
    // ring, and three shadow values.
    //
    // §6 (2026-09-18) demoted voice by reordering `stackOrder`, moving it off
    // the thumb and behind the cameras in the tour — but left this, so voice
    // went on being *rendered* as the primary tool. Half a change, and the
    // visible symptom was a taller voice pill, logged as a cosmetic during the
    // device pass when it was actually the demotion not landing.
    //
    // It is deleted rather than repointed at another modality: the descoping
    // specifies **five tools in a fixed bar, all visible**, verbs rather than
    // content types. Nothing is primary, and naming a new favourite would be
    // inventing a hierarchy no ruling asked for.
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
    // `case voiceSession(clips:rollGroupId:)` retired in §5.4 (2026-09-24).
    // It carried the PHONE's on-a-roll output: one continuous master file,
    // split at the Next-tap offsets and re-transcribed per clip. The phone no
    // longer records, so nothing can produce it.
    //
    // The roll itself is untouched and CURRENT — `On a roll · spec.md` is
    // Watch-only, and a Watch roll arrives as `InboxClip`s that
    // `ArrivedClipMaterializer` joins into one memory by `rollGroupId`. It
    // never travelled through this type.
}
