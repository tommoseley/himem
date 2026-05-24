import SwiftUI

/// Tiny ochre glyph keyed off the user's pricing tier. Renders next
/// to the wordmark on the launch screen and in the Today header so
/// paying users feel seen without ceremony.
///
///   • Founder  → filled diamond (rare, marked)
///   • Plus     → outlined ring with a plus inside (subscriber)
///   • Supporter → outlined heart (patron)
///   • Free     → nothing
///
/// Designed for one shape per tier so the design system stays small —
/// no badges, no levels, no proliferation. Sized in points so it
/// scales with the surrounding text; 10pt reads at chrome-row scale
/// next to caption text, 18pt sits comfortably next to the 56pt
/// launch wordmark.
struct TierMark: View {
    let tier: EntitlementService.Tier
    /// Whether the user is also a Supporter (overlay state). Renders
    /// the supporter heart when tier is Free, otherwise the tier's
    /// own mark wins (Founder already includes everything Supporter
    /// would be acknowledging).
    var supporter: Bool = false
    var size: CGFloat = 14
    var color: Color = Crucible.Color.accent

    var body: some View {
        Group {
            switch tier {
            case .founders:
                foundersDiamond
            case .plusMonthly, .plusYearly:
                plusRing
            case .free:
                if supporter {
                    supporterHeart
                } else {
                    EmptyView()
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(accessibilityLabel)
    }

    private var foundersDiamond: some View {
        // Path: top → right → bottom → left.
        Path { p in
            let s = size
            p.move(to: CGPoint(x: s * 0.5, y: s * 0.06))
            p.addLine(to: CGPoint(x: s * 0.94, y: s * 0.5))
            p.addLine(to: CGPoint(x: s * 0.5, y: s * 0.94))
            p.addLine(to: CGPoint(x: s * 0.06, y: s * 0.5))
            p.closeSubpath()
        }
        .fill(color)
    }

    private var plusRing: some View {
        // Outlined circle with a small "+" cross inside. The cross
        // arms are sized at ~40% of the diameter so they read clearly
        // at chrome-row scale (10pt) and still feel proportionate at
        // launch-screen scale (18pt). Stroke widths match the diamond
        // and heart glyphs so the three tier marks share a visual
        // weight class.
        let dim = size * 0.78
        let strokeRing = max(1, size * 0.10)
        let armLen = dim * 0.40
        let armStroke = max(1, size * 0.13)
        return ZStack {
            Circle()
                .strokeBorder(color, lineWidth: strokeRing)
                .frame(width: dim, height: dim)
            // Horizontal arm
            Capsule()
                .fill(color)
                .frame(width: armLen, height: armStroke)
            // Vertical arm
            Capsule()
                .fill(color)
                .frame(width: armStroke, height: armLen)
        }
    }

    private var supporterHeart: some View {
        Path { p in
            let s = size
            p.move(to: CGPoint(x: s * 0.5, y: s * 0.88))
            p.addCurve(
                to: CGPoint(x: s * 0.5, y: s * 0.30),
                control1: CGPoint(x: s * 0.05, y: s * 0.62),
                control2: CGPoint(x: s * 0.05, y: s * 0.18)
            )
            p.addCurve(
                to: CGPoint(x: s * 0.5, y: s * 0.88),
                control1: CGPoint(x: s * 0.95, y: s * 0.18),
                control2: CGPoint(x: s * 0.95, y: s * 0.62)
            )
            p.closeSubpath()
        }
        .stroke(color, style: StrokeStyle(lineWidth: max(1, size * 0.09), lineJoin: .round))
    }

    private var accessibilityLabel: String {
        switch tier {
        case .founders: return "Founder"
        case .plusMonthly, .plusYearly: return "Plus subscriber"
        case .free: return supporter ? "Supporter" : ""
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        TierMark(tier: .founders)
        TierMark(tier: .plusMonthly)
        TierMark(tier: .free, supporter: true)
        TierMark(tier: .free)
    }
    .padding()
}
