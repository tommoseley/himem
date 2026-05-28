import SwiftUI

/// Single-line pinned banner above the topic filter when watch clips
/// are waiting in the inbox. Per the Watch → Memory flow spec: count-
/// leading, dot-separated, no emoji, no app subtitle. The host shows
/// it only in memories mode and only when `InboxManifest.shared.count > 0`.
/// Tapping fires `onTap`, which `JournalView` routes to the inbox
/// navigation destination.
///
/// Extracted from `JournalView.body` in the CRAP audit 2026-05-28
/// (Batch 1) so the host body shrinks and the banner can evolve
/// independently (e.g., a future per-source breakdown).
struct JournalInboxBanner: View {
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "applewatch")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Crucible.Color.accent)
                Text("\(count) new from Apple Watch")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Crucible.Color.ink)
                Text("·")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Crucible.Color.ink4)
                Text("Tap to review")
                    .font(.subheadline)
                    .foregroundStyle(Crucible.Color.ink3)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Crucible.Color.ink3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Crucible.Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14).stroke(Crucible.Color.accent.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) new clip\(count == 1 ? "" : "s") from Apple Watch")
        .accessibilityHint("Opens the inbox to review and process pending watch recordings.")
    }
}
