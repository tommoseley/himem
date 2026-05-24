import SwiftUI

/// Upgrade prompt — the one-time 3-starter + 5-memories conversion
/// moment.
///
/// **Variant A primary (per spec):** honest two-path. No per-assist
/// math at this emotional moment — math belongs in Settings and the
/// pack purchase sheet.
///
/// Fires once per install when both conditions are true. The trigger
/// state is persisted by `UpgradePromptCoordinator`.
struct UpgradePromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = StoreKitService.shared
    @State private var purchasing = false
    @State private var purchaseError: String?

    var body: some View {
        ZStack {
            Crucible.Color.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Crucible.Color.accent)
                        .frame(width: 36, height: 36)
                    AISparkleGlyph(size: 20, color: .white)
                }
                .padding(.bottom, 18)

                Text("You've built a HiMem habit.")
                    .font(PricingFonts.serif(26))
                    .foregroundStyle(Crucible.Color.ink)
                    .lineSpacing(2)
                    .padding(.bottom, 10)

                Text("You're out of starter AI assists. Keep going?")
                    .font(.system(size: 14.5))
                    .foregroundStyle(Crucible.Color.ink2)
                    .lineSpacing(2)
                    .padding(.bottom, 22)

                // Pack option
                Button {
                    Task { await purchase(StoreKitService.ProductID.assistPack20) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Add 20 AI assists")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Crucible.Color.ink)
                            Spacer()
                            Text(store.product(for: StoreKitService.ProductID.assistPack20)?.displayPrice ?? "$4.99")
                                .font(PricingFonts.serif(18, weight: .medium))
                                .foregroundStyle(Crucible.Color.ink)
                        }
                        Text("One-time. Never expires.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Crucible.Color.ink3)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Crucible.Color.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Crucible.Color.hairline, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 10)

                // Plus option (featured dark)
                Button {
                    Task { await purchase(StoreKitService.ProductID.plusMonthly) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Subscribe to HiMem Plus")
                                .font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Text("\(store.product(for: StoreKitService.ProductID.plusMonthly)?.displayPrice ?? "$4.99")/mo")
                                .font(PricingFonts.serif(18, weight: .medium))
                        }
                        Text("50 assists / month · unlimited projects · auto-organize.")
                            .font(.system(size: 12.5))
                            .opacity(0.65)
                            .lineSpacing(2)
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.99, blue: 0.96))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Crucible.Color.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 14)

                Spacer()

                if let purchaseError {
                    Text(purchaseError)
                        .font(.system(size: 12))
                        .foregroundStyle(Crucible.Color.danger)
                        .padding(.bottom, 8)
                }

                PricingGhostButton(title: "Not now") {
                    dismiss()
                }
                Text("Free keeps working forever. You can buy assists later from Settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(Crucible.Color.ink3)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .disabled(purchasing)
    }

    private func purchase(_ productID: String) async {
        guard let product = store.product(for: productID) else {
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

/// Decides when to fire the upgrade prompt. Single-source-of-truth for
/// the 3+5 trigger, the once-per-install fire guard, and the
/// "shown but not converted" follow-up suppression.
@MainActor
final class UpgradePromptCoordinator: ObservableObject {
    static let shared = UpgradePromptCoordinator()

    @Published var shouldShow: Bool = false

    private enum Keys {
        static let hasShown = "upgradePrompt.hasShown"
    }

    private init() {}

    /// Asks the coordinator to check whether the trigger conditions are
    /// met. Call this after any event that could move the user across
    /// the threshold — entry creation, assist consumption, scene-active.
    /// Idempotent.
    func evaluate() {
        guard !UserDefaults.standard.bool(forKey: Keys.hasShown) else { return }
        let e = EntitlementService.shared
        guard e.tier == .free else { return }
        guard e.starterUsed >= EntitlementService.starterTotal else { return }
        let memoriesSaved = countMemories()
        guard memoriesSaved >= 5 else { return }
        shouldShow = true
    }

    func markShown() {
        UserDefaults.standard.set(true, forKey: Keys.hasShown)
        shouldShow = false
    }

    #if DEBUG
    /// Clears the "already shown" UserDefaults pin so the prompt can
    /// fire again on the next `evaluate()` that meets the trigger
    /// conditions.
    func debugClearShownFlag() {
        UserDefaults.standard.removeObject(forKey: Keys.hasShown)
    }

    /// Forces the sheet open right now, regardless of trigger
    /// conditions. Useful for previewing the surface without
    /// constructing 5 memories + 3 starter consumptions first.
    func debugForceShow() {
        shouldShow = true
    }
    #endif

    private func countMemories() -> Int {
        let ctx = StorageService.shared.viewContext
        let request = JournalEntry.fetchAllChronological(limit: 6)
        return (try? ctx.count(for: request)) ?? 0
    }
}

#Preview {
    UpgradePromptSheet()
}
