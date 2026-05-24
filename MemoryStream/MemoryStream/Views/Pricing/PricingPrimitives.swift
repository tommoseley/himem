import SwiftUI

/// Shared UI primitives used across the pricing surfaces.
/// Crucible-aware: cream paper, ochre accent, Source Serif headlines,
/// SF Pro body.
enum PricingFonts {
    /// Source Serif 4 — editorial display. Falls back to system serif
    /// if the font isn't loaded (default for iOS host fonts).
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

/// Small ochre sparkle glyph — the AI consumption point.
struct AISparkleGlyph: View {
    var size: CGFloat = 18
    var color: Color = .white
    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: size * 0.85, weight: .semibold))
            .foregroundStyle(color)
    }
}

/// Section eyebrow — small uppercase tracked label.
struct PricingEyebrow: View {
    let text: String
    var color: Color = Crucible.Color.ink3
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

/// "Add 20 assists / $4.99" style pack picker row used in the pack
/// purchase sheet and inline hard-100 panel.
struct PackPickRow: View {
    let assists: Int
    let price: String
    let perAssist: String
    var featured: Bool = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(featured ? Crucible.Color.accent : Crucible.Color.accentTint)
                        .frame(width: 44, height: 44)
                    AISparkleGlyph(size: 20, color: featured ? .white : Crucible.Color.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(assists)")
                            .font(PricingFonts.serif(20, weight: .medium))
                            .foregroundStyle(Crucible.Color.ink)
                        Text("assists")
                            .font(PricingFonts.sans(13))
                            .foregroundStyle(Crucible.Color.ink2)
                    }
                    Text(perAssist)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Crucible.Color.ink3)
                }
                Spacer()
                Text(price)
                    .font(PricingFonts.serif(20, weight: .medium))
                    .foregroundStyle(Crucible.Color.ink)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(featured ? Crucible.Color.accentTint : Crucible.Color.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(featured ? Crucible.Color.accent.opacity(0.3) : Crucible.Color.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Quiet "rate note" callout used at the bottom of pack purchase to
/// nudge toward Plus. Designed to be honest, not pushy.
struct RateNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PricingEyebrow(text: "A note on rates")
            (Text("Plus is ")
                + Text("$0.10 / assist").fontWeight(.semibold).foregroundColor(Crucible.Color.ink)
                + Text(" at the same monthly cost as a 20-pack. If you find yourself buying packs often, Plus saves money."))
                .font(.system(size: 13))
                .foregroundStyle(Crucible.Color.ink2)
                .lineSpacing(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Crucible.Color.sunk)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Primary action button — dark ink fill, cream label.
struct PricingPrimaryButton: View {
    let title: String
    var subtitle: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .opacity(0.75)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Crucible.Color.ink)
            .foregroundStyle(Color(red: 1.0, green: 0.99, blue: 0.96))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

/// Secondary action — card-on-paper with hairline.
struct PricingSecondaryButton: View {
    let title: String
    var subtitle: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .opacity(0.65)
                }
            }
            .foregroundStyle(Crucible.Color.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Crucible.Color.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Crucible.Color.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

/// Ghost button — text-only, dismissible-style.
struct PricingGhostButton: View {
    let title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Crucible.Color.ink2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}
