import SwiftUI

/// One-time sheet shown the first time a Free user encounters the
/// "Organize with AI" affordance. Plants the 3 starter assists into
/// the pack balance so the first explicit consumption succeeds.
///
/// Idempotent — `EntitlementService.grantStarterIfNeeded()` only grants
/// once. Subsequent dismissals don't re-add assists.
///
/// Surfaces from `EntryExpandedView`'s Organize button (Phase 1) and is
/// gated on `EntitlementService.shared.starterGranted == false`.
struct OnboardingStarterCard: View {
    @ObservedObject var entitlement: EntitlementService = .shared
    @Environment(\.dismiss) private var dismiss
    var onTry: () -> Void = {}

    var body: some View {
        ZStack {
            Crucible.Color.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                // Eyebrow icon
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Crucible.Color.AI.base)
                        .frame(width: 56, height: 56)
                    AISparkleGlyph(size: 26, color: .white)
                }
                .padding(.bottom, 24)

                Text("AI can help organize your memories.")
                    .font(PricingFonts.serif(28))
                    .foregroundStyle(Crucible.Color.ink)
                    .padding(.bottom, 14)

                Text("It suggests titles, groups related entries, and finds patterns you've written about. You stay in control — every suggestion is yours to accept or skip.")
                    .font(.system(size: 15))
                    .foregroundStyle(Crucible.Color.ink2)
                    .lineSpacing(2)
                    .padding(.bottom, 22)

                // Starter grant card
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text("3")
                            .font(PricingFonts.serif(22, weight: .semibold))
                            .foregroundStyle(Crucible.Color.ink)
                        Text("starter AI assists, on the house")
                            .font(.system(size: 14))
                            .foregroundStyle(Crucible.Color.ink2)
                    }
                    Text("Try it on a few memories. After that, you can add more or subscribe to Plus for 50 every month.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Crucible.Color.ink3)
                        .lineSpacing(2)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Crucible.Color.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Crucible.Color.hairline, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.bottom, 10)

                Text("Your memories stay yours — AI is the helper, never the keeper. You can use HiMem without it for as long as you like.")
                    .font(.system(size: 11))
                    .foregroundStyle(Crucible.Color.ink3)
                    .lineSpacing(2)
                    .padding(.horizontal, 4)

                Spacer()

                VStack(spacing: 8) {
                    PricingPrimaryButton(title: "Try it on a memory") {
                        entitlement.grantStarterIfNeeded()
                        onTry()
                        dismiss()
                    }
                    PricingGhostButton(title: "Not now") {
                        entitlement.grantStarterIfNeeded()
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 40)
            .padding(.bottom, 28)
        }
    }
}

#Preview {
    OnboardingStarterCard()
}
