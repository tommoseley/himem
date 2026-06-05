import SwiftUI

/// Tiny ochre glyph showing whether the user has HiMem Plus. Renders
/// next to the wordmark on the launch screen and in the Today header
/// so subscribers feel seen without ceremony.
///
///   • Plus  → outlined ring with a plus inside
///   • Free  → nothing
///
/// Simplified for the Capture · Connect · Create model — the
/// previous Founder diamond and Supporter heart are retired with
/// their respective tiers.
struct TierMark: View {
    let isPlus: Bool
    var size: CGFloat = 14
    var color: Color = Crucible.Color.accent

    var body: some View {
        Group {
            if isPlus {
                plusRing
            } else {
                EmptyView()
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(isPlus ? "Plus subscriber" : "")
    }

    private var plusRing: some View {
        // Outlined circle with a small "+" cross inside. The cross
        // arms are sized at ~40% of the diameter so they read clearly
        // at chrome-row scale (10pt) and still feel proportionate at
        // launch-screen scale (18pt).
        let dim = size * 0.78
        let strokeRing = max(1, size * 0.10)
        let armLen = dim * 0.40
        let armStroke = max(1, size * 0.13)
        return ZStack {
            Circle()
                .strokeBorder(color, lineWidth: strokeRing)
                .frame(width: dim, height: dim)
            Capsule()
                .fill(color)
                .frame(width: armLen, height: armStroke)
            Capsule()
                .fill(color)
                .frame(width: armStroke, height: armLen)
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        TierMark(isPlus: true)
        TierMark(isPlus: false)
    }
    .padding()
}
