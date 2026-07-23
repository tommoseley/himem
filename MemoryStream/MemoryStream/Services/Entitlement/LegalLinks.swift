import Foundation

/// The hosted legal pages linked from the purchase UI. App Review requires a
/// functional **Terms of Use (EULA)** link and a **Privacy Policy** link
/// adjacent to any auto-renewable-subscription CTA — these must resolve when
/// Apple taps them.
///
/// - Important: These are the live Kingfisher Studio pages. App Review taps
///   them, so if either is ever renamed/moved the link must be updated here in
///   the same change — a dead link is a 3.1.2 rejection.
enum LegalLinks {
    /// The License Agreement (EULA).
    static let terms = URL(string: "https://kingfisherstudio.co/himem-license-agreement.html")!
    static let privacy = URL(string: "https://kingfisherstudio.co/himem-privacy-policy.html")!

    /// Apple's expected auto-renewal disclosure, verbatim. Compliance
    /// boilerplate, not brand voice — do not reword.
    static let renewalDisclosure =
        "Payment will be charged to your Apple Account. Subscription renews " +
        "automatically unless canceled at least 24 hours before the end of the " +
        "period. Manage or cancel in your Apple Account settings."
}
