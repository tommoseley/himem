import SwiftUI

/// "Support HiMem" — the post-trust gratitude screen.
///
/// Surfaces only when `TenureTracker.shared.isTenured` is true
/// (≥30 days + ≥10 memories + Free tier). Never appears in onboarding
/// or upgrade hub. Settings-only entry under "Behind HiMem."
///
/// Single price (per locked spec): **$2.99/mo or $29.99/yr**. No tier
/// ladder, no Custom, no feature unlocks. The amount is private — all
/// supporters get the same small heart in Settings.
///
/// SKUs (post-MVP, to be added to App Store Connect when this ships):
///   `com.himem.supporter.monthly`, `com.himem.supporter.yearly`.
struct SupporterDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMonthly: Bool = true

    var body: some View {
        ZStack {
            Crucible.Color.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroIcon
                        .padding(.bottom, 18)

                    Text("Help us keep building,\non your terms.")
                        .font(PricingFonts.serif(26))
                        .foregroundStyle(Crucible.Color.ink)
                        .lineSpacing(2)
                        .padding(.bottom, 12)

                    Text("HiMem is small, independent, and has no ads. If it's earning its place on your phone, you can chip in.")
                        .font(.system(size: 14))
                        .foregroundStyle(Crucible.Color.ink2)
                        .lineSpacing(2)
                        .padding(.bottom, 8)

                    (Text("This unlocks nothing.").foregroundColor(Crucible.Color.ink).fontWeight(.semibold)
                     + Text(" Free stays free. Plus stays Plus. Supporters just help cover the bill."))
                        .font(.system(size: 13.5))
                        .foregroundStyle(Crucible.Color.ink2)
                        .lineSpacing(2)
                        .padding(.bottom, 22)

                    pricePicker
                        .padding(.bottom, 22)

                    whatYouGet
                        .padding(.bottom, 18)

                    PricingPrimaryButton(title: ctaTitle) {
                        // Supporter SKUs are deferred to v1.1 — the
                        // App Store Connect products are not yet
                        // registered. This dismisses for now; replace
                        // with StoreKitService.purchase when SKUs land.
                        dismiss()
                    }

                    Text("Cancel any time. Nothing about HiMem changes if you do.")
                        .font(.system(size: 11))
                        .foregroundStyle(Crucible.Color.ink3)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                        .lineSpacing(2)
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("Support HiMem")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var heroIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11)
                .fill(Crucible.Color.accentTint)
                .frame(width: 38, height: 38)
            Image(systemName: "heart.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Crucible.Color.accent)
        }
    }

    private var pricePicker: some View {
        VStack(spacing: 10) {
            priceCard(label: "Monthly", price: "$2.99", unit: "/month", selected: selectedMonthly) {
                selectedMonthly = true
            }
            priceCard(
                label: "Yearly",
                price: "$29.99",
                unit: "/year",
                hint: "The two-months-free option.",
                selected: !selectedMonthly
            ) {
                selectedMonthly = false
            }
        }
    }

    private func priceCard(label: String, price: String, unit: String, hint: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Crucible.Color.ink)
                    Spacer()
                    Text(price)
                        .font(PricingFonts.serif(22, weight: .medium))
                        .foregroundStyle(Crucible.Color.ink)
                    Text(unit)
                        .font(.system(size: 12))
                        .foregroundStyle(Crucible.Color.ink3)
                }
                if let hint {
                    Text(hint)
                        .font(.system(size: 12))
                        .foregroundStyle(Crucible.Color.ink3)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Crucible.Color.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? Crucible.Color.accent : Crucible.Color.hairline, lineWidth: selected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var whatYouGet: some View {
        VStack(alignment: .leading, spacing: 4) {
            PricingEyebrow(text: "What you get")
                .padding(.bottom, 4)
            Text("Our thanks. A small heart in Settings. The knowledge that an indie app you like keeps shipping. That's it.")
                .font(.system(size: 12.5))
                .foregroundStyle(Crucible.Color.ink2)
                .lineSpacing(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Crucible.Color.sunk)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var ctaTitle: String {
        if selectedMonthly { return "Become a supporter · $2.99/mo" }
        return "Become a supporter · $29.99/yr"
    }
}

#Preview {
    NavigationStack {
        SupporterDetailView()
    }
}
