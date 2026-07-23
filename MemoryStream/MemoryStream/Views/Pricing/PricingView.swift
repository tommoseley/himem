import SwiftUI
import StoreKit

/// "See Plans" — the canonical pricing page per
/// `docs/design/pricing-screens.jsx` `ScrPricing`. Presented as a
/// modal sheet from Settings (always available) and from upgrade
/// triggers (C1 after-a-glance, ProjectListView at-cap,
/// ProjectDetailView Find-the-thread for Free).
///
/// Structure:
///   1. Close × (top-right)
///   2. Serif headline + private-by-default lead
///   3. Capture section — free, always — three bullets
///   4. Connect section — Plus — copy + `MagicTile` proof + bullets
///   5. Create section — *coming later*
///   6. Pinned footer: monthly price + yearly subline + "Try Plus
///      free for a week" CTA
///
/// Plus users land on a state-aware variant: the CTA becomes
/// "You're on Plus" (informational) and points to iOS Settings →
/// Apple ID for management since cancellations live there.
struct PricingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject private var storeKit = StoreKitService.shared
    @ObservedObject private var entitlement = Entitlement.shared
    @State private var purchaseError: String?
    @State private var isPurchasing: Bool = false
    @State private var selectedPlan: Plan = .monthly
    @State private var isRestoring: Bool = false
    @State private var restoreNotice: String?
    @State private var showManageSubscriptions: Bool = false

    /// Which subscription the CTA buys. Monthly and yearly are upgrade/
    /// downgrade peers in one group, so the toggle just picks which product
    /// `purchase(_:)` receives.
    private enum Plan { case monthly, yearly }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            Spacer(minLength: 8)
            footer
        }
        .background(Crucible.Color.paper)
        .alert("Purchase failed", isPresented: errorBinding) {
            Button("OK", role: .cancel) { purchaseError = nil }
        } message: {
            Text(purchaseError ?? "")
        }
        .alert("Restore Purchases", isPresented: restoreBinding) {
            Button("OK", role: .cancel) { restoreNotice = nil }
        } message: {
            Text(restoreNotice ?? "")
        }
        .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        .task {
            // Refresh metadata on appear so prices reflect the
            // user's locale even on first reach.
            if storeKit.loadedProducts.isEmpty {
                await storeKit.loadProducts()
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { purchaseError != nil }, set: { if !$0 { purchaseError = nil } })
    }

    private var restoreBinding: Binding<Bool> {
        Binding(get: { restoreNotice != nil }, set: { if !$0 { restoreNotice = nil } })
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink3)
                    .frame(width: 30, height: 30)
                    .background(Crucible.Color.sunk)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                lead
                captureSection
                connectSection
                createSection
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var lead: some View {
        Text("Your memories stay\nyours. Even offline.")
            .font(.system(size: 28, weight: .semibold, design: .serif))
            .foregroundStyle(Crucible.Color.ink)
            .padding(.top, 6)
        (Text("HiMem keeps and organizes everything ")
            .foregroundColor(Crucible.Color.ink2)
         + Text("privately, on your device").fontWeight(.semibold).foregroundColor(Crucible.Color.ink)
         + Text(" — no account needed to hold a thought. Plus helps your memories find each other.")
            .foregroundColor(Crucible.Color.ink2))
            .font(.system(size: 13.5))
            .lineSpacing(2)
            .padding(.top, 10)
    }

    @ViewBuilder
    private var captureSection: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text("Capture")
                .font(.system(size: 19, weight: .semibold, design: .serif))
                .foregroundStyle(Crucible.Color.ink)
            Text("· free, always")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink3)
        }
        .padding(.top, 18)
        VStack(alignment: .leading, spacing: 5) {
            bulletRow(symbolColor: Crucible.Color.accent, marker: "—", text: "Capture and keep everything")
            bulletRow(symbolColor: Crucible.Color.accent, marker: "—", text: "Organize by hand, on your device")
            bulletRow(symbolColor: Crucible.Color.accent, marker: "—", text: "Three projects · search · fully offline")
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var connectSection: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text("Connect")
                .font(.system(size: 19, weight: .semibold, design: .serif))
                .foregroundStyle(Crucible.Color.accent)
            Text("· Plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink3)
        }
        .padding(.top, 18)
        Text("The library starts working for you — surfacing and connecting what belongs together.")
            .font(.system(size: 13))
            .foregroundStyle(Crucible.Color.ink2)
            .lineSpacing(2)
            .padding(.top, 7)
            .padding(.bottom, 11)
        MagicTile()
        VStack(alignment: .leading, spacing: 5) {
            bulletRow(symbolColor: Crucible.Color.aiBlue, marker: "+", text: "Surfaces what you've already said")
            bulletRow(symbolColor: Crucible.Color.aiBlue, marker: "+", text: "Connects the memories that belong together")
            bulletRow(symbolColor: Crucible.Color.aiBlue, marker: "+", text: "Organizes automatically · unlimited projects")
        }
        .padding(.top, 11)
    }

    @ViewBuilder
    private var createSection: some View {
        Divider()
            .background(Crucible.Color.divider)
            .padding(.top, 16)
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text("Create")
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(Crucible.Color.ink3)
            (Text("· turn memories into something — ")
                + Text("coming later").italic())
                .font(.system(size: 12))
                .foregroundStyle(Crucible.Color.ink3)
        }
        .padding(.top, 13)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func bulletRow(symbolColor: Color, marker: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(symbolColor)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Crucible.Color.ink2)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 0) {
            if entitlement.isPlus {
                plusFooter
            } else {
                priceAndPurchase
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var priceAndPurchase: some View {
        // Monthly / Annual selector — both products are purchasable; the
        // toggle picks which one the CTA buys.
        HStack(spacing: 8) {
            planOption(.monthly, price: monthlyPrice, period: "/ month", note: nil)
            planOption(.yearly, price: yearlyPrice, period: "/ year", note: yearlySavingsNote)
        }
        .padding(.bottom, 10)

        Button(action: handlePurchase) {
            HStack(spacing: 8) {
                if isPurchasing {
                    ProgressView().tint(.white)
                }
                Text(isPurchasing ? "Working…" : "Start Plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Crucible.Color.accent)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing || selectedProduct == nil)

        // Auto-renewal disclosure — required adjacent to the CTA. Compliance
        // boilerplate, verbatim (`LegalLinks.renewalDisclosure`).
        Text(LegalLinks.renewalDisclosure)
            .font(.system(size: 10.5))
            .foregroundStyle(Crucible.Color.ink3)
            .multilineTextAlignment(.center)
            .lineSpacing(1.5)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

        // Restore + Terms/Privacy — the required functional links.
        HStack(spacing: 6) {
            Button(action: handleRestore) {
                if isRestoring {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("Restore Purchases")
                }
            }
            .disabled(isRestoring)
            legalDot
            Button("Terms") { openURL(LegalLinks.terms) }
            legalDot
            Button("Privacy") { openURL(LegalLinks.privacy) }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(Crucible.Color.aiBlue)
        .frame(maxWidth: .infinity)
        .padding(.top, 9)

        Text("Keep using Free for as long as you like.")
            .font(.system(size: 11.5))
            .foregroundStyle(Crucible.Color.ink3)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
    }

    private var legalDot: some View {
        Text("·").foregroundStyle(Crucible.Color.ink4)
    }

    /// One selectable plan card in the Monthly/Annual toggle.
    @ViewBuilder
    private func planOption(_ plan: Plan, price: String, period: String, note: String?) -> some View {
        let selected = selectedPlan == plan
        Button {
            selectedPlan = plan
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(price)
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .foregroundStyle(Crucible.Color.ink)
                    Text(period)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Crucible.Color.ink3)
                }
                Text(note ?? " ")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Crucible.Color.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(selected ? Crucible.Color.accentTint : Crucible.Color.card)
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(selected ? Crucible.Color.accent : Crucible.Color.divider,
                            lineWidth: selected ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var plusFooter: some View {
        VStack(spacing: 8) {
            Text("You're on Plus.")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink)
            Button("Manage subscription") { showManageSubscriptions = true }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Crucible.Color.aiBlue)
            HStack(spacing: 6) {
                Button("Restore Purchases", action: handleRestore).disabled(isRestoring)
                legalDot
                Button("Terms") { openURL(LegalLinks.terms) }
                legalDot
                Button("Privacy") { openURL(LegalLinks.privacy) }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Crucible.Color.aiBlue)
        }
        .padding(.vertical, 12)
    }

    // MARK: - StoreKit binding

    private var monthlyProduct: Product? {
        storeKit.product(for: StoreKitService.ProductID.plusMonthly)
    }

    private var yearlyProduct: Product? {
        storeKit.product(for: StoreKitService.ProductID.plusYearly)
    }

    /// The product the CTA will purchase, per the toggle.
    private var selectedProduct: Product? {
        selectedPlan == .monthly ? monthlyProduct : yearlyProduct
    }

    /// Localized prices, or a serif em-dash placeholder while StoreKit loads
    /// — never a hardcoded number that could flash wrong.
    private var monthlyPrice: String { monthlyProduct?.displayPrice ?? "—" }
    private var yearlyPrice: String { yearlyProduct?.displayPrice ?? "—" }

    /// "Save 17%" style note on the annual card, computed from the live
    /// StoreKit prices (12× monthly vs yearly) — nil until both load, so we
    /// never assert a discount the prices don't support.
    private var yearlySavingsNote: String? {
        guard let m = monthlyProduct?.price, let y = yearlyProduct?.price else { return nil }
        let fullYear = m * 12
        guard fullYear > 0, y < fullYear else { return nil }
        let pct = Int((((fullYear - y) / fullYear) as NSDecimalNumber).doubleValue * 100)
        return pct > 0 ? "Save \(pct)%" : nil
    }

    private func handlePurchase() {
        guard let product = selectedProduct else { return }
        Task {
            isPurchasing = true
            defer { isPurchasing = false }
            let result = await storeKit.purchase(product)
            switch result {
            case .success:
                // StoreKitService.applyTransaction reconciles
                // Entitlement.isPlus; dismiss so the user lands back
                // where they were already.
                dismiss()
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Purchase pending approval (e.g. Ask to Buy). You'll be notified when it clears."
            case .failed(let msg):
                purchaseError = msg
            }
        }
    }

    private func handleRestore() {
        Task {
            isRestoring = true
            defer { isRestoring = false }
            switch await storeKit.restorePurchases() {
            case .restored:
                dismiss()
            case .nothingToRestore:
                restoreNotice = "No active HiMem Plus subscription was found on this Apple Account."
            case .failed(let msg):
                restoreNotice = msg
            }
        }
    }
}

// MARK: - MagicTile

/// AI-blue proof-of-Connect tile per `pricing-screens.jsx` MagicTile.
/// Shows a fake "8 memories may belong here" suggestion list — the
/// concrete "show don't tell" of what auto-organize feels like. Used
/// inline in PricingView and in the C1 after-a-glance nudge.
struct MagicTile: View {
    private struct DemoRow: Identifiable {
        let id = UUID()
        let title: String
        let topic: String
    }

    private let demoRows: [DemoRow] = [
        DemoRow(title: "The pear tree, three years on", topic: "Garden"),
        DemoRow(title: "What I keep coming back to", topic: "How We Work"),
        DemoRow(title: "Frost notes — late October", topic: "Garden"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Crucible.Color.aiBlue)
                        .frame(width: 22, height: 22)
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text("8 memories may belong here")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.2)
                    .foregroundStyle(Crucible.Color.aiBlue)
            }

            VStack(spacing: 6) {
                ForEach(demoRows) { row in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Crucible.Color.aiBlue)
                            .frame(width: 5, height: 5)
                        Text(row.title)
                            .font(.system(size: 12))
                            .foregroundStyle(Crucible.Color.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(row.topic)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Crucible.Color.ink3)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(Crucible.Color.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(Crucible.Color.aiBlueTint, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                }
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .background(Crucible.Color.aiBlueTint)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Crucible.Color.aiBlue, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
