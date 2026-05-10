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
}
