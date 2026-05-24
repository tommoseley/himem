import SwiftUI

/// Single labeled output from an `OrganizePass` (Summary, Next steps,
/// or Related memories). Matches the v2 design's section primitive:
/// small uppercase eyebrow with an optional `✦ AI` tag, then the body
/// content underneath in Source Serif.
struct OrganizedSection<Content: View>: View {
    let label: String
    var byAI: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Crucible.Color.ink3)
                if byAI {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9, weight: .semibold))
                        Text("AI")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Crucible.Color.aiBlue.opacity(0.8))
                }
            }
            content
                .font(PricingFonts.serif(13.5))
                .foregroundStyle(Crucible.Color.ink)
                .lineSpacing(2)
        }
    }
}
