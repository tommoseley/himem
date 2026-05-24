import SwiftUI
import StoreKit

/// Settings → HiMem Plus (tier-aware Plan Hub).
///
/// Replaces the v3 "always show the upgrade hub" pattern with branches
/// that respect what the user already has:
///
///   • **Free** — editorial headline + Plus monthly/yearly cards +
///     Founders tile (while cap holds) + Pack tiles.
///   • **Plus** — "Your plan" hero with renewal date + Founders tile
///     (Plus → Founders is a legit upgrade) + Pack tiles + Manage
///     section ("Manage in App Store").
///   • **Founders** — dark identity card with the 4 permanent perks +
///     Pack tiles + "Founder · since May 2026" trust footer. No
///     subscription mechanics; cap tile is hidden (they own it).
///   • **Supporter overlay** — small "You support HiMem" heart card
///     pinned at the top of whichever underlying tier they're seeing.
///     Founders don't see this because Founders subsumes Supporter.
///
/// Title swap follows the tier: "Founders" / "Your plan" / "HiMem Plus".
///
/// Filename is kept (UpgradeHubView.swift) to avoid pbxproj churn; the
/// type stays `UpgradeHubView` and other call sites push to it
/// unchanged. The behavior is just tier-aware now.
struct UpgradeHubView: View {
    @ObservedObject var entitlement: EntitlementService = .shared
    @ObservedObject var founders: FoundersCounter = .shared
    @ObservedObject var store: StoreKitService = .shared
    @State private var showPackPurchase = false
    @State private var showFoundersDetail = false
    @State private var purchaseError: String?
    @State private var purchasingID: String?

    private var isFounders: Bool { entitlement.tier == .founders }
    private var isPlus: Bool {
        entitlement.tier == .plusMonthly || entitlement.tier == .plusYearly
    }
    private var isSupporter: Bool { entitlement.isSupporter && !isFounders }

    var body: some View {
        ZStack {
            Crucible.Color.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Supporter overlay pins at the very top regardless
                    // of underlying tier. Founders never see it (their
                    // perks include everything Supporter would be
                    // acknowledging).
                    if isSupporter {
                        SupporterOverlayCard()
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                            .padding(.bottom, 12)
                    }

                    tierHero
                        .padding(.bottom, 18)

                    if !storeReady && !isFounders {
                        storeKitNotice
                            .padding(.horizontal, 14)
                            .padding(.bottom, 12)
                    }

                    // Plan cards only for non-subscribers
                    if !isPlus && !isFounders {
                        plansSection
                            .padding(.horizontal, 14)
                            .padding(.bottom, 18)
                    }

                    // Founders tile hidden if already a Founder;
                    // eyebrow copy varies based on whether the user
                    // is on Plus already.
                    if !isFounders && !founders.capReached && founders.hasLoaded {
                        foundersSection
                            .padding(.horizontal, 14)
                            .padding(.bottom, 22)
                    }

                    packsSection
                        .padding(.horizontal, 14)

                    if isPlus {
                        manageSection
                            .padding(.horizontal, 14)
                            .padding(.top, 22)
                    }

                    Text(trustFooter)
                        .font(.system(size: 11))
                        .foregroundStyle(Crucible.Color.ink3)
                        .lineSpacing(2)
                        .padding(.horizontal, 22)
                        .padding(.top, 22)
                        .padding(.bottom, 28)
                }
            }
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPackPurchase) {
            AIPackPurchaseSheet()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showFoundersDetail) {
            NavigationStack { FoundersDetailView() }
        }
        .task {
            await founders.refresh()
            // Reload products on hub appear — gives users a second
            // chance when StoreKit didn't load at launch (config not
            // wired in dev, network slow on cold start, etc.).
            await store.loadProducts()
        }
        .alert("Purchase", isPresented: Binding(
            get: { purchaseError != nil },
            set: { if !$0 { purchaseError = nil } }
        )) {
            Button("OK", role: .cancel) { purchaseError = nil }
        } message: {
            Text(purchaseError ?? "")
        }
    }

    private var navTitle: String {
        if isFounders { return "Founders" }
        if isPlus { return "Your plan" }
        return "HiMem Plus"
    }

    private var trustFooter: String {
        if isFounders {
            return "Founder · since May 2026."
        }
        return "Your memories are always yours. Free works forever. Cancel any time — capture and storage keep going."
    }

    // MARK: - Tier-specific hero

    @ViewBuilder
    private var tierHero: some View {
        if isFounders {
            FoundersIdentityHero()
                .padding(.horizontal, 14)
                .padding(.top, 14)
        } else if isPlus {
            PlusPlanHero(tier: entitlement.tier)
                .padding(.horizontal, 20)
                .padding(.top, 14)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Plus adds AI\nand unlimited projects.")
                    .font(PricingFonts.serif(30))
                    .foregroundStyle(Crucible.Color.ink)
                    .lineSpacing(2)
                Text("Storage and capture stay free, forever. Plus lets HiMem help organize what you've captured and removes the one-project limit.")
                    .font(.system(size: 14))
                    .foregroundStyle(Crucible.Color.ink2)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
        }
    }

    // MARK: - StoreKit readiness banner

    private var storeReady: Bool {
        store.product(for: StoreKitService.ProductID.plusMonthly) != nil &&
        store.product(for: StoreKitService.ProductID.plusYearly) != nil
    }

    private var storeKitNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: store.isLoading ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Crucible.Color.warning)
                Text(store.isLoading ? "Loading prices…" : "Plans aren't available right now.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink)
                Spacer()
            }
            if !store.isLoading {
                Text(noticeDetail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Crucible.Color.ink3)
                    .lineSpacing(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Crucible.Color.Status.inferringBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var noticeDetail: String {
        #if DEBUG
        return "Debug build: pick `Products.storekit` in Edit Scheme → Run → Options → StoreKit Configuration. Without that, no products load."
        #else
        return "Try again in a moment — your network may be slow, or the App Store is briefly unavailable."
        #endif
    }

    // MARK: - Plans (Free only)

    private var plansSection: some View {
        VStack(spacing: 10) {
            planCard(
                title: "Plus · Monthly",
                productID: StoreKitService.ProductID.plusMonthly,
                fallbackPrice: "$4.99",
                unit: "/month",
                sub: nil,
                featured: false
            )
            planCard(
                title: "Plus · Yearly",
                productID: StoreKitService.ProductID.plusYearly,
                fallbackPrice: "$39.99",
                unit: "/year",
                sub: "Two months free · $3.33/mo",
                featured: true
            )
        }
    }

    private func planCard(
        title: String,
        productID: String,
        fallbackPrice: String,
        unit: String,
        sub: String?,
        featured: Bool
    ) -> some View {
        let product = store.product(for: productID)
        let price = product?.displayPrice ?? fallbackPrice
        let available = product != nil
        let inFlight = purchasingID == productID
        let foreground: Color = featured ? Color(red: 1.0, green: 0.99, blue: 0.96) : Crucible.Color.ink
        let background: Color = featured ? Crucible.Color.ink : Crucible.Color.card
        let opacity: Double = featured ? 0.9 : 0.85

        return Button {
            Task { await purchase(productID) }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    if inFlight {
                        ProgressView()
                            .controlSize(.small)
                            .tint(foreground)
                    }
                    Text(price)
                        .font(PricingFonts.serif(22, weight: .medium))
                    Text(unit)
                        .font(.system(size: 13))
                        .opacity(0.65)
                }
                if let sub {
                    Text(sub)
                        .font(.system(size: 12))
                        .opacity(0.6)
                        .padding(.top, -6)
                }
                VStack(alignment: .leading, spacing: 6) {
                    planFeature("50 AI assists / month", featured: featured)
                    planFeature("Unlimited projects", featured: featured)
                    planFeature("Auto-organize", featured: featured)
                }
                .opacity(opacity)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(foreground)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(featured ? Color.clear : Crucible.Color.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .opacity(available ? 1.0 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!available || purchasingID != nil)
    }

    private func planFeature(_ text: String, featured: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(featured ? Color(red: 1.0, green: 0.81, blue: 0.6) : Crucible.Color.success)
            Text(text)
                .font(.system(size: 13))
        }
    }

    // MARK: - Founders tile

    private var foundersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PricingEyebrow(text: isPlus ? "Want more? One-time deal." : "Or, one-time")
                .padding(.horizontal, 8)
            Button {
                showFoundersDetail = true
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Founders Lifetime")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Crucible.Color.ink)
                            Text("\(founders.remaining) remaining")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Crucible.Color.warning)
                        }
                        Text("$99 once · Plus for life · TestFlight + 100 bonus assists")
                            .font(.system(size: 13))
                            .foregroundStyle(Crucible.Color.ink2)
                            .lineSpacing(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Crucible.Color.ink4)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
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

    // MARK: - Pack tiles

    private var packsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PricingEyebrow(text: packsEyebrow)
                .padding(.horizontal, 8)
            HStack(spacing: 10) {
                packTile(assists: 20, price: "$4.99", per: "$0.25 each", tag: nil)
                packTile(assists: 100, price: "$19.99", per: "$0.20 each", tag: "Better value")
            }
        }
    }

    private var packsEyebrow: String {
        if isFounders || isPlus { return "Top up assists" }
        return "Or top up without a subscription"
    }

    private func packTile(assists: Int, price: String, per: String, tag: String?) -> some View {
        Button {
            showPackPurchase = true
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(assists)")
                    .font(PricingFonts.serif(26, weight: .medium))
                    .foregroundStyle(Crucible.Color.ink)
                Text("assists")
                    .font(.system(size: 12))
                    .foregroundStyle(Crucible.Color.ink3)
                    .padding(.bottom, 2)
                Text(price)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink)
                Text(per)
                    .font(.system(size: 11))
                    .foregroundStyle(Crucible.Color.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Crucible.Color.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Crucible.Color.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .topTrailing) {
                if let tag {
                    Text(tag)
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(0.3)
                        .textCase(.uppercase)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Crucible.Color.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .offset(x: -10, y: -8)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Manage section (Plus only)

    private var manageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PricingEyebrow(text: "Manage")
                .padding(.horizontal, 8)
            Button {
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Crucible.Color.accent)
                        .frame(width: 26, height: 26)
                        .background(Crucible.Color.accentTint)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Manage in App Store")
                            .font(.system(size: 15))
                            .foregroundStyle(Crucible.Color.ink)
                        Text(planRenewalCopy)
                            .font(.system(size: 12))
                            .foregroundStyle(Crucible.Color.ink3)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Crucible.Color.ink4)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
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

    private var planRenewalCopy: String {
        switch entitlement.tier {
        case .plusMonthly: return "$4.99/month · subscription"
        case .plusYearly: return "$39.99/year · subscription"
        case .founders: return "Lifetime · no renewal"
        case .free: return ""
        }
    }

    // MARK: - Purchase

    private func purchase(_ productID: String) async {
        guard let product = store.product(for: productID) else {
            #if DEBUG
            purchaseError = "Product not loaded. Edit Scheme → Run → Options → StoreKit Configuration → pick Products.storekit."
            #else
            purchaseError = "Plus isn't available right now. Try again in a moment."
            #endif
            return
        }
        purchasingID = productID
        defer { purchasingID = nil }
        switch await store.purchase(product) {
        case .success, .userCancelled:
            purchaseError = nil
        case .pending:
            purchaseError = "Awaiting approval. We'll grant Plus once it's approved."
        case .failed(let msg):
            purchaseError = msg
        }
    }
}

// MARK: - Tier-specific hero subviews

/// Plus user's "Your plan" hero. Editorial, no upsell language.
private struct PlusPlanHero: View {
    let tier: EntitlementService.Tier

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PricingEyebrow(text: "Your plan")
            Text(headline)
                .font(PricingFonts.serif(32))
                .foregroundStyle(Crucible.Color.ink)
                .lineSpacing(2)
            Text("AI organization and unlimited projects, included.")
                .font(.system(size: 13.5))
                .foregroundStyle(Crucible.Color.ink2)
                .lineSpacing(2)
        }
    }

    private var headline: String {
        switch tier {
        case .plusYearly: return "HiMem Plus · Yearly"
        default: return "HiMem Plus · Monthly"
        }
    }
}

/// Founder's permanent identity card. Dark, ceremonial, lists the four
/// perks with the cream-ochre treatment from the design.
private struct FoundersIdentityHero: View {
    private let cream = Color(red: 1.0, green: 0.99, blue: 0.96)
    private let pale = Color(red: 1.0, green: 0.81, blue: 0.6)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Founder")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(cream.opacity(0.6))

            Text("Plus, forever.")
                .font(PricingFonts.serif(30))
                .foregroundStyle(cream)
                .lineSpacing(2)

            Text("One of the first 250. Thank you for showing up early.")
                .font(.system(size: 13))
                .foregroundStyle(cream.opacity(0.7))
                .lineSpacing(2)

            VStack(alignment: .leading, spacing: 7) {
                perkRow(title: "50 AI assists / month", detail: "Plus monthly allowance, included")
                perkRow(title: "TestFlight access", detail: "Builds before they ship")
                perkRow(title: "Selected early-access flags", detail: "New things, before everyone else")
                perkRow(title: "100 bonus assists", detail: "In your pack balance, never expires")
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Crucible.Color.ink)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func perkRow(title: String, detail: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(pale)
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(cream.opacity(0.92))
            Spacer()
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(cream.opacity(0.5))
        }
    }
}

/// Compact "You support HiMem" card pinned on top of any Plan Hub view
/// when the user is also a Supporter. Acknowledgment without ceremony.
private struct SupporterOverlayCard: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Crucible.Color.accentTint)
                    .frame(width: 36, height: 36)
                Image(systemName: "heart.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Crucible.Color.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("You support HiMem")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink)
                Text("Thanks for keeping this independent.")
                    .font(.system(size: 12))
                    .foregroundStyle(Crucible.Color.ink3)
            }
            Spacer()
            Text("Manage")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Crucible.Color.accent)
        }
        .padding(14)
        .background(Crucible.Color.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    NavigationStack {
        UpgradeHubView()
    }
}
