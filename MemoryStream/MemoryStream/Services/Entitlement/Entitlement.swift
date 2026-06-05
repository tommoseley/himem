import Foundation
import Combine

/// Minimal post-retirement entitlement state. The assist-quota model
/// (counters, tiers, packs, Founders, Supporter, TenureTracker) is
/// gone — see `docs/architecture/assist-quota-retirement-audit.md`.
/// All that survives at this layer is the binary
/// **isPlus** signal that gates the Connect-layer features
/// (Project Assist, auto-organize-on-capture, frontier prompt) per
/// `Pricing model · Capture-Connect-Create.md`.
///
/// `StoreKitService` writes here when subscription state changes;
/// consumers read `isPlus` directly.
@MainActor
final class Entitlement: ObservableObject {
    static let shared = Entitlement()

    /// True while the user has an active HiMem Plus subscription (monthly
    /// or yearly). Driven by `StoreKitService.reconcileCurrentEntitlements`
    /// at launch and by the transaction-listener on each new purchase /
    /// renewal / refund.
    @Published private(set) var isPlus: Bool = false

    #if DEBUG
    /// Developer override — flips `isPlus` for testing the Plus path
    /// locally without an active subscription. Persists across launches
    /// via UserDefaults so a debug toggle survives the relaunch loop.
    @Published var developerOverridePlus: Bool? = nil {
        didSet { recomputeIsPlus() }
    }
    #endif

    /// Raw signal from StoreKit — stored separately from `isPlus` so
    /// the developer override can compose on top without losing the
    /// real subscription state.
    private var storeKitIsPlus: Bool = false {
        didSet { recomputeIsPlus() }
    }

    /// COGS-log label for the AI cost report (`docs/api/himem-cost-logging.md`).
    /// Locked vocabulary: `plus` or `free`. The previous granularity
    /// (`plus_monthly` vs `plus_yearly` vs `founders`) is no longer
    /// meaningful in the Capture · Connect · Create model.
    var tierLabel: String { isPlus ? "plus" : "free" }

    /// Called by StoreKitService when a verified subscription comes in,
    /// renews, refunds, expires.
    func setStoreKitIsPlus(_ value: Bool) {
        storeKitIsPlus = value
    }

    private func recomputeIsPlus() {
        #if DEBUG
        if let override = developerOverridePlus {
            isPlus = override
            return
        }
        #endif
        isPlus = storeKitIsPlus
    }
}
