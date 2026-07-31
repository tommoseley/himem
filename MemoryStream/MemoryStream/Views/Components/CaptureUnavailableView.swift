import SwiftUI
import UIKit

/// Shown **where the dead interface would have been** when capture can't start
/// (F18, 2026-07-31).
///
/// The defect this replaces: on iPad the camera presented and showed a black
/// preview, and the voice composer presented with a waveform that never moved.
/// The app looked like it was working and wasn't — the same silent no-op
/// rejected twice before (F9's recorder that never started, F6d's delete that
/// destroyed audio without saying so). A capture surface that can't capture
/// must say so, in place, not behind a toast the user never sees.
///
/// Copy is design-authority (Tom, 2026-07-31): Crucible voice — describes the
/// state, never blames the user, no jargon, and offers the way out.
struct CaptureUnavailableView: View {
    /// Camera copy, ruled verbatim. Names the device the user is holding.
    static var cameraMessage: String {
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        return "We couldn't start the camera. Try closing and reopening HiMem — if it keeps happening, restart your \(device)."
    }

    /// Audio copy, ruled verbatim.
    static let audioMessage = "We couldn't start recording."

    let message: String
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Crucible.Color.paper.ignoresSafeArea()

            VStack(spacing: 20) {
                Text(message)
                    .font(.system(size: 17))
                    .foregroundStyle(Crucible.Color.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)

                Button(action: onDismiss) {
                    Text("Close")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .background(Crucible.Color.accent, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
            }
        }
    }
}
