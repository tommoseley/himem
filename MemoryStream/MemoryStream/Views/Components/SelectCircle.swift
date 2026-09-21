import SwiftUI

/// The Photos-style selection circle (mock, July 2026): 22px, hairline
/// ink4 ring at rest → accent fill + white check when selected.
///
/// **Extracted from `ClipsTabView` in I2** (2026-09-20). It was declared
/// alongside the Clips bench, which the descoping retires, but it is not a
/// bench primitive — `AddExistingClipsSheet` draws it, and that sheet is
/// the paperclip's *bring something existing here*, which survives. Moving
/// it here is what makes the bench's deletion a deletion rather than a
/// rewrite of its surviving callers.
struct SelectCircle: View {
    let checked: Bool
    var body: some View {
        ZStack {
            Circle()
                .fill(checked ? Crucible.Color.accent : Color.clear)
            Circle()
                .strokeBorder(checked ? Crucible.Color.accent : Crucible.Color.ink4, lineWidth: 2)
            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityLabel(checked ? "Selected" : "Not selected")
    }
}
