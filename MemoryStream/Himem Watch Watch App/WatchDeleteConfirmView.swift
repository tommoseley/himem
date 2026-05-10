import SwiftUI

/// Section 4E — two-tap delete. The audio isn't on the phone yet, so
/// deletion is permanent; the spec says "ask explicitly."
struct WatchDeleteConfirmView: View {
    let clip: WatchPendingClip
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 6)
            Text("Delete this\nrecording?")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            Text("\(durationLabel) · not synced yet")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.5))

            VStack(spacing: 6) {
                Button(action: onConfirm) {
                    Text("Delete")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(red: 0xB8/255, green: 0x32/255, blue: 0x32/255))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            Spacer(minLength: 0)
        }
    }

    private var durationLabel: String {
        String(format: "%d:%02d", Int(clip.duration) / 60, Int(clip.duration) % 60)
    }
}
