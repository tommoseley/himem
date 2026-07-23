import Testing
import Foundation
@testable import HiMem

/// Config-invariant guards for the IAP/subscription surface (2026-07-23).
/// These are deterministic, no-StoreKit-session checks — the parts of the
/// subscription-wiring audit a refactor could silently break: the product-ID
/// contract with App Store Connect, and the verbatim compliance copy.
@Suite
struct SubscriptionConfigTests {

    /// The app's product IDs MUST exactly match the ASC subscription
    /// identifiers, or `Product.products(for:)` returns nothing and every
    /// price shows "—". `everything` is what `loadProducts` requests, so it
    /// must be exactly the two Plus subs (guards against a retired product
    /// creeping back into the request set).
    @Test func productIDs_matchAppStoreConnect() {
        #expect(StoreKitService.ProductID.plusMonthly == "com.himem.plus.monthly")
        #expect(StoreKitService.ProductID.plusYearly == "com.himem.plus.yearly")
        #expect(StoreKitService.ProductID.allSubscriptions == ["com.himem.plus.monthly", "com.himem.plus.yearly"])
        #expect(StoreKitService.ProductID.everything == StoreKitService.ProductID.allSubscriptions)
    }

    /// The auto-renewal disclosure adjacent to the CTA is Apple's expected
    /// standard, verbatim — compliance boilerplate, not brand voice. A reword
    /// is a 3.1.2 risk, so pin it.
    @Test func renewalDisclosure_isAppleStandardVerbatim() {
        #expect(LegalLinks.renewalDisclosure == "Payment will be charged to your Apple Account. Subscription renews automatically unless canceled at least 24 hours before the end of the period. Manage or cancel in your Apple Account settings.")
    }

    /// The required legal links must be well-formed https URLs (App Review
    /// taps them; a malformed URL is a dead link).
    @Test func legalLinks_areHTTPS() {
        #expect(LegalLinks.terms.scheme == "https")
        #expect(LegalLinks.privacy.scheme == "https")
        #expect(LegalLinks.terms.host?.isEmpty == false)
        #expect(LegalLinks.privacy.host?.isEmpty == false)
    }
}
