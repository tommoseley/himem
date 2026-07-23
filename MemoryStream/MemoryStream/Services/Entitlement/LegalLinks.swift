import Foundation

/// The hosted legal pages linked from the purchase UI. App Review requires a
/// functional **Terms of Use (EULA)** link and a **Privacy Policy** link
/// adjacent to any auto-renewable-subscription CTA — these must resolve when
/// Apple taps them.
///
/// - Important: These point at the AWS-deployed HiMem pages
///   (`docs/design/HiMem · App Info.html` / `HiMem · Privacy Policy.html`).
///   **CONFIRM the exact deployed URLs before submission** — a dead link is a
///   3.1.2 rejection. If HiMem uses Apple's standard EULA rather than a custom
///   one, `terms` may instead point at
///   `https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`.
enum LegalLinks {
    // TODO(tom): confirm these are the live AWS-hosted URLs before TestFlight/submit.
    static let terms = URL(string: "https://himem.app/terms")!
    static let privacy = URL(string: "https://himem.app/privacy")!

    /// Apple's expected auto-renewal disclosure, verbatim. Compliance
    /// boilerplate, not brand voice — do not reword.
    static let renewalDisclosure =
        "Payment will be charged to your Apple Account. Subscription renews " +
        "automatically unless canceled at least 24 hours before the end of the " +
        "period. Manage or cancel in your Apple Account settings."
}
