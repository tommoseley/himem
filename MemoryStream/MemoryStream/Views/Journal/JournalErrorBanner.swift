import SwiftUI

/// Top-aligned error banner overlay. Renders when `ErrorState.shared`
/// has a current error; tapping the close glyph dismisses it. Extracted
/// from `JournalView.body` in the CRAP audit 2026-05-28 (Batch 1) so
/// the host body shrinks and the overlay can evolve independently
/// (e.g., a future Sentry-style auto-dismiss timer).
struct JournalErrorBanner: View {
    @ObservedObject private var errorState = ErrorState.shared

    var body: some View {
        if let error = errorState.current {
            VStack {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Crucible.Color.danger)
                        .accessibilityHidden(true)
                    Text(error.errorDescription ?? "Something went wrong")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        errorState.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss error")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Crucible.Color.ink)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                Spacer()
            }
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.3), value: errorState.current?.id)
        }
    }
}
