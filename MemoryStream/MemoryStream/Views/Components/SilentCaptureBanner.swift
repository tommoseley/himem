import SwiftUI

/// Shown **where the saved-clip confirmation would have been** when a
/// recording lands at peak zero (ruled 2026-08-02).
///
/// The sibling of `CaptureUnavailableView`, one step later in the flow:
/// that one speaks when capture cannot *start*, this one when capture ran
/// and heard nothing. Both exist because a capture surface that produces
/// nothing must say so — the silent no-op this project has now rejected
/// four times (F9's stranded recorder, F6d's silent delete, F23's confirmed
/// move that never happened, and this).
///
/// **Not a toast, deliberately.** `CreationToast` confirms a success and
/// auto-dismisses at 3.5s; this reports a failure the user has to act on,
/// so it stays until dismissed. A failure message on a timer is the class
/// of defect this gate was built to close, one layer up. *(That the toast's
/// slot is shared is ruled; that this one does not expire is an
/// implementation call — flagged as such, not as a ruling.)*
///
/// **No action beyond dismissal.** The copy asks her to check a permission;
/// a deep link into Settings would be a new *what*, so it is not invented
/// here.
struct SilentCaptureBanner: View {

    let message: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            // Status is never colour alone (Crucible): the glyph and the
            // sentence both carry it. Warn amber, not danger red — nothing
            // was destroyed; the recording is kept.
            Image(systemName: "waveform.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Crucible.Color.warn)
                .padding(.top, 1)

            Text(message)
                .font(.system(size: 14.5))
                .foregroundStyle(Crucible.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Crucible.Color.ink3)
                    // 44px hit-target floor, no exceptions.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
            .padding(.trailing, -12)
            .padding(.top, -11)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Crucible.Color.card)
                .shadow(color: Color.black.opacity(0.18), radius: 12, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}
