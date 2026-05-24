import SwiftUI

/// Founders Lifetime detail screen, drilled into from the Upgrade hub.
///
/// Top: dark hero card with editorial title, $99 one-time, live cap
/// counter, and a status dot.
/// Middle: the 4-perk list — Plus for life · 100 bonus assists ·
/// TestFlight · **Selected** early-access feature flags. The name-credit
/// perk that was here pre-v4 got cut once we realized Apple doesn't
/// hand us a name and free-text would be a UGC moderation problem.
/// Bottom: Studio-not-included disclosure + primary CTA. Closed-state
/// (cap reached): "All seats claimed" + "See Plus plans instead".
///
/// The word "selected" in the early-access flags perk is non-negotiable
/// per the spec's copy rule — it preserves Tom's option to hold some
/// experiments back or broaden them without Founders feeling promised
/// every experimental thing forever.
struct FoundersDetailView: View {
    @ObservedObject var founders: FoundersCounter = .shared
    @ObservedObject var store: StoreKitService = .shared
    @Environment(\.dismiss) private var dismiss
    @State private var purchasing = false
    @State private var purchaseError: String?
    @State private var showPlusPlans = false

    var body: some View {
        ZStack {
            Crucible.Color.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heroCard
                    perksList
                    Text("Studio (multi-memory synthesis) ships post-MVP and isn't included.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Crucible.Color.ink3)
                        .lineSpacing(2)

                    if let purchaseError {
                        Text(purchaseError)
                            .font(.system(size: 12))
                            .foregroundStyle(Crucible.Color.danger)
                    }

                    if founders.capReached {
                        PricingSecondaryButton(title: "See Plus plans instead") {
                            dismiss()
                            showPlusPlans = true
                        }
                    } else {
                        PricingPrimaryButton(title: ctaTitle) {
                            Task { await purchase() }
                        }
                        .disabled(purchasing)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("Founders")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await founders.refresh()
        }
        .sheet(isPresented: $showPlusPlans) {
            NavigationStack {
                UpgradeHubView()
            }
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        let cream = Color(red: 1.0, green: 0.99, blue: 0.96)
        return VStack(alignment: .leading, spacing: 14) {
            Text("HiMem Founders")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(cream.opacity(0.65))

            Text("Pay once.\nHelp early.")
                .font(PricingFonts.serif(32))
                .foregroundStyle(cream)
                .lineSpacing(2)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(displayPrice)
                    .font(PricingFonts.serif(38, weight: .medium))
                    .foregroundStyle(cream)
                Text("one-time")
                    .font(.system(size: 13))
                    .foregroundStyle(cream.opacity(0.65))
            }

            if founders.capReached {
                Text("All 250 Founders seats are claimed. Thank you.")
                    .font(.system(size: 13))
                    .foregroundStyle(cream.opacity(0.7))
                    .lineSpacing(2)
            } else {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.81, blue: 0.6))
                        .frame(width: 6, height: 6)
                    Text("\(founders.remaining) Founder seats remaining")
                        .font(.system(size: 12, design: .monospaced))
                        .tracking(0.3)
                        .foregroundStyle(cream.opacity(0.85))
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Crucible.Color.ink)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var displayPrice: String {
        store.product(for: StoreKitService.ProductID.foundersLifetime)?.displayPrice ?? "$99"
    }

    private var ctaTitle: String {
        "Become a Founder · \(displayPrice)"
    }

    // MARK: - Perks

    private var perksList: some View {
        VStack(alignment: .leading, spacing: 0) {
            PricingEyebrow(text: "What you get")
                .padding(.bottom, 12)

            ForEach(Array(FoundersDetailView.perks.enumerated()), id: \.offset) { index, perk in
                perkRow(title: perk.title, detail: perk.detail, isLast: index == FoundersDetailView.perks.count - 1)
            }
        }
    }

    private func perkRow(title: String, detail: String, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Crucible.Color.Status.confirmedBg)
                    .frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Crucible.Color.success)
            }
            .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Crucible.Color.ink3)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Crucible.Color.divider)
                    .frame(height: 0.5)
            }
        }
    }

    private struct Perk {
        let title: String
        let detail: String
    }

    private static let perks: [Perk] = [
        Perk(
            title: "HiMem Plus, for life",
            detail: "Auto-organize, unlimited projects, 50 assists/mo. No renewal."
        ),
        Perk(
            title: "100 bonus assists at purchase",
            detail: "Into your pack balance. Never expires."
        ),
        Perk(
            title: "TestFlight access",
            detail: "Builds before they ship. See what's coming."
        ),
        Perk(
            // Copy rule: this MUST stay "Selected early-access feature
            // flags" — not "Early-access feature flags." See
            // docs/design/pricing-model.md → Founders copy rule.
            title: "Selected early-access feature flags",
            detail: "Try selected experiments early. Not every new thing, not forever — but a real early-look channel."
        ),
    ]

    // MARK: - Purchase

    private func purchase() async {
        guard let product = store.product(for: StoreKitService.ProductID.foundersLifetime) else {
            purchaseError = "Not available right now."
            return
        }
        purchasing = true
        defer { purchasing = false }
        switch await store.purchase(product) {
        case .success:
            dismiss()
        case .userCancelled:
            purchaseError = nil
        case .pending:
            purchaseError = "Awaiting approval."
        case .failed(let msg):
            purchaseError = msg
        }
    }
}

#Preview {
    NavigationStack {
        FoundersDetailView()
    }
}
