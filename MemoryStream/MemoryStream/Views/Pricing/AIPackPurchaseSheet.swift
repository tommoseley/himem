import SwiftUI
import StoreKit

/// AI Pack purchase sheet. Reachable from:
///   • `Settings → Your AI → Add more`
///   • The Hard 100% inline panel on a memory detail
///   • The Upgrade hub (Settings → HiMem Plus) Pack tiles
///
/// Shows the two pack sizes ($4.99/20 and $19.99/100), the per-assist
/// math, and a quiet rate-note nudging toward Plus when the user finds
/// themselves repeatedly here.
struct AIPackPurchaseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = StoreKitService.shared
    @State private var selectedID: String = StoreKitService.ProductID.assistPack100
    @State private var purchasing = false
    @State private var purchaseError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Crucible.Color.paper.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 0) {
                    Text("Pack assists never expire and are used after any included monthly assists.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Crucible.Color.ink2)
                        .lineSpacing(2)
                        .padding(.bottom, 18)

                    VStack(spacing: 10) {
                        PackPickRow(
                            assists: 20,
                            price: pricedPack(id: StoreKitService.ProductID.assistPack20, fallback: "$4.99"),
                            perAssist: "$0.25 / assist",
                            featured: selectedID == StoreKitService.ProductID.assistPack20,
                            action: { selectedID = StoreKitService.ProductID.assistPack20 }
                        )
                        PackPickRow(
                            assists: 100,
                            price: pricedPack(id: StoreKitService.ProductID.assistPack100, fallback: "$19.99"),
                            perAssist: "$0.20 / assist · 20% off",
                            featured: selectedID == StoreKitService.ProductID.assistPack100,
                            action: { selectedID = StoreKitService.ProductID.assistPack100 }
                        )
                    }
                    .padding(.bottom, 18)

                    RateNote()

                    Spacer(minLength: 16)

                    if let purchaseError {
                        Text(purchaseError)
                            .font(.system(size: 12))
                            .foregroundStyle(Crucible.Color.danger)
                            .padding(.bottom, 8)
                    }

                    PricingPrimaryButton(title: buyTitle) {
                        Task { await buy() }
                    }
                    .disabled(purchasing)

                    Text("One-time purchase via App Store. Restore Purchases in Settings.")
                        .font(.system(size: 11))
                        .foregroundStyle(Crucible.Color.ink3)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                        .lineSpacing(2)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .navigationTitle("Add AI assists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Crucible.Color.accent)
                }
            }
        }
    }

    private var buyTitle: String {
        let pack = selectedID == StoreKitService.ProductID.assistPack20 ? "20" : "100"
        let price = pricedPack(id: selectedID, fallback: selectedID == StoreKitService.ProductID.assistPack20 ? "$4.99" : "$19.99")
        return "Buy \(pack) assists · \(price)"
    }

    private func pricedPack(id: String, fallback: String) -> String {
        guard let product = store.product(for: id) else { return fallback }
        return product.displayPrice
    }

    private func buy() async {
        guard let product = store.product(for: selectedID) else {
            purchaseError = "Pack not available right now."
            return
        }
        purchasing = true
        defer { purchasing = false }
        switch await store.purchase(product) {
        case .success:
            dismiss()
        case .userCancelled:
            break
        case .pending:
            purchaseError = "Awaiting approval. We'll add the assists once approved."
        case .failed(let message):
            purchaseError = message
        }
    }
}

#Preview {
    AIPackPurchaseSheet()
}
