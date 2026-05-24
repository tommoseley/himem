import SwiftUI

/// Watch-side color tokens, pulled from the watch design spec. Pure black
/// background, ochre accent only, white text — battery-friendly OLED-aware
/// palette. Distinct from the iOS Crucible theme since the watch's surface
/// is uniformly dark; we don't ship the warm paper background to the wrist.
enum WatchTheme {
    /// Brand accent — same #C64A1C as iOS, used on the FAB-equivalent mic
    /// disc, primary buttons, and the active hand on the watchface
    /// complication.
    static let accent = Color(red: 0xC6/255, green: 0x4A/255, blue: 0x1C/255)

    /// "Pressed" tone — the FAB-rotated darker accent.
    static let accentPressed = Color(red: 0x8C/255, green: 0x2F/255, blue: 0x0E/255)

    /// Pending-amber: warm tone for the pending count + offline confirmation.
    /// Per the design spec: "pending is normal, not a problem" — never red.
    static let pendingAmber = Color(red: 0xF0/255, green: 0xB2/255, blue: 0x5A/255)

    /// Confirmed-green: synced confirmation tone.
    static let syncedGreen = Color(red: 0x59/255, green: 0xC8/255, blue: 0x8C/255)

    /// Failure red — only used for storage-full / failed-sync states.
    static let danger = Color(red: 0xFF/255, green: 0x8A/255, blue: 0x75/255)

    /// Recording cream — the Stop & save pill on a black background.
    /// Per the watch spec V1 canonical: "Cream `#F1ECE3` background,
    /// ink `#000` text — the visually heaviest element on the screen."
    /// Distinct from `accent`: ochre is reserved for Next, REC, and the
    /// waveform; the commit button reads heavier *because* it isn't.
    static let cream = Color(red: 0xF1/255, green: 0xEC/255, blue: 0xE3/255)

    /// Warn amber — the timer color shift at 4:45 (30s left). Lifts off
    /// the cream timer without going full danger red, which would feel
    /// like an error state. Used briefly: just the closing window of a
    /// 5-min clip.
    static let warnAmber = Color(red: 0xE8/255, green: 0xA0/255, blue: 0x40/255)
}
