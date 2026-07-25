import SwiftUI

/// Single source of truth for Left-Handed FAB layout resolution.
///
/// A floating action button has two layout responsibilities that MUST agree:
/// its *container placement* (the `ZStack`/overlay that anchors it on a FAB
/// surface) and its *internal* layout (the modality VStack + anchor padding
/// inside `AppendFAB`/`NewProjectFAB`). When the container hardcodes
/// `.bottomTrailing` but the internals honor the preference, a left-handed FAB
/// anchors right when closed and jumps left on open. Both sides resolve here so
/// a new FAB surface can't silently re-hardcode the trailing edge.
///
/// The preference is the `@AppStorage("fabHandednessLeft")` bool written by the
/// Settings "Left-handed FAB" toggle.
enum FABHandedness {
    /// The `@AppStorage` key the Settings toggle writes and every FAB reads.
    static let storageKey = "fabHandednessLeft"

    /// Alignment for the container (`ZStack`/`.overlay`) that positions a FAB.
    static func containerAlignment(leftHanded: Bool) -> Alignment {
        leftHanded ? .bottomLeading : .bottomTrailing
    }

    /// Horizontal alignment for the FAB's internal modality VStack, so the
    /// expanded pills stack flush to the same edge the FAB anchors on.
    static func horizontalEdge(leftHanded: Bool) -> HorizontalAlignment {
        leftHanded ? .leading : .trailing
    }

    /// The edge the FAB's anchor padding sits on.
    static func paddingEdge(leftHanded: Bool) -> Edge.Set {
        leftHanded ? .leading : .trailing
    }
}
