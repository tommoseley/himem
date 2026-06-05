import Foundation
import StoreKit

/// StoreKit 2 wrapper. Loads HiMem's Plus subscription products on
/// startup, listens for transactions, and pushes the resulting Plus
/// state to `Entitlement.shared`.
///
/// Product IDs are intentionally string-stable — they match what we
/// register in App Store Connect. Local testing uses the bundled
/// `Products.storekit` configuration.
///
/// Architecture:
///   • App calls `start()` once at launch.
///   • UI reads `loadedProducts` for prices/labels.
///   • UI calls `purchase(_:)` which returns a `PurchaseResult`.
///   • Transaction observer reconciles entitlements regardless of where
///     the purchase originated (in-app sheet, App Store refund, etc.) —
///     so a refund in iOS Settings demotes the user automatically.
@MainActor
final class StoreKitService: ObservableObject {
    static let shared = StoreKitService()

    // MARK: - Product IDs

    enum ProductID {
        static let plusMonthly = "com.himem.plus.monthly"
        static let plusYearly = "com.himem.plus.yearly"

        static let allSubscriptions: [String] = [plusMonthly, plusYearly]
        static let everything: [String] = allSubscriptions
    }

    // MARK: - Published state

    @Published private(set) var loadedProducts: [String: Product] = [:]
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: String?

    private var transactionListener: Task<Void, Never>?

    // MARK: - Public API

    enum PurchaseResult {
        case success
        case userCancelled
        case pending
        case failed(String)
    }

    /// One-shot start. Loads product catalog and begins listening for
    /// out-of-band transactions (renewals, refunds, family sharing).
    func start() {
        Task { await loadProducts() }
        transactionListener = listenForTransactions()
        Task { await reconcileCurrentEntitlements() }
    }

    /// Loads product metadata from StoreKit. Idempotent — call any time
    /// the user opens a purchase surface, but most surfaces should just
    /// read `loadedProducts` after the initial launch load.
    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let products = try await Product.products(for: ProductID.everything)
            var byID: [String: Product] = [:]
            for product in products {
                byID[product.id] = product
            }
            self.loadedProducts = byID
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func product(for id: String) -> Product? { loadedProducts[id] }

    /// Initiates a purchase. UI presents whatever the App Store shows;
    /// on completion we resolve into a `PurchaseResult` so the calling
    /// view can route (success → dismiss, pending → toast, etc.).
    func purchase(_ product: Product) async -> PurchaseResult {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await applyTransaction(transaction)
                await transaction.finish()
                return .success
            case .userCancelled:
                return .userCancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed("Unknown purchase result")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Transaction routing

    /// Long-running task that delivers transactions arriving outside an
    /// in-app purchase flow (e.g., a renewal, a family-shared purchase,
    /// or an Ask to Buy that gets approved later).
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await update in Transaction.updates {
                guard let self else { continue }
                do {
                    let transaction = try await self.checkVerified(update)
                    await self.applyTransaction(transaction)
                    await transaction.finish()
                } catch {
                    NSLog("[HiMem][StoreKit] Transaction verification failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Walks `Transaction.currentEntitlements` at startup to compute
    /// active Plus state. Idempotent — running after sign-in or
    /// reinstall rebuilds the entitlement.
    func reconcileCurrentEntitlements() async {
        var hasActiveSubscription = false
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                if ProductID.allSubscriptions.contains(transaction.productID) {
                    hasActiveSubscription = true
                }
            } catch {
                continue
            }
        }
        Entitlement.shared.setStoreKitIsPlus(hasActiveSubscription)
    }

    /// Routes a verified transaction into the Plus signal.
    private func applyTransaction(_ transaction: Transaction) async {
        guard ProductID.allSubscriptions.contains(transaction.productID) else { return }
        // Subscription state may have changed (purchase, renewal,
        // refund, expiration). Rebuild from currentEntitlements so the
        // refund/expiration case demotes the user correctly.
        await reconcileCurrentEntitlements()
    }

    enum StoreKitError: Error { case unverified }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): return value
        case .unverified: throw StoreKitError.unverified
        }
    }
}
