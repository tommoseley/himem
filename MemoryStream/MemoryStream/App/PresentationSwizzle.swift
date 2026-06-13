import UIKit
import ObjectiveC

/// Diagnostic: swizzles `UIViewController.present(_:animated:completion:)`
/// and `dismiss(animated:completion:)` to log every modal presentation
/// in the process. Used 2026-06-13 to pin down the "Attempt to present
/// X … already presenting Z" rise-and-fall race on the Review-draft
/// button — our walker couldn't find Z in the view hierarchy because
/// it lives in UIKit's `_presentedViewController` slot during the
/// iOS 26 dismissal-coordination window. Every present/dismiss
/// callsite is logged, so we can rebuild the timeline of which sheet
/// owned the slot when the next sheet was rejected.
///
/// **Remove before ship.** This is investigation code; leaving it in
/// adds startup overhead and floods the log.
enum PresentationSwizzle {
    static let install: Void = {
        let cls = UIViewController.self
        guard
            let presentOrig = class_getInstanceMethod(cls, #selector(UIViewController.present(_:animated:completion:))),
            let presentSwiz = class_getInstanceMethod(cls, #selector(UIViewController.himem_present(_:animated:completion:))),
            let dismissOrig = class_getInstanceMethod(cls, #selector(UIViewController.dismiss(animated:completion:))),
            let dismissSwiz = class_getInstanceMethod(cls, #selector(UIViewController.himem_dismiss(animated:completion:)))
        else {
            NSLog("[HiMem][Swizzle] FAILED — could not resolve method selectors")
            return
        }
        method_exchangeImplementations(presentOrig, presentSwiz)
        method_exchangeImplementations(dismissOrig, dismissSwiz)
        NSLog("[HiMem][Swizzle] installed present/dismiss hooks")
    }()
}

private extension UIViewController {

    @objc func himem_present(_ vc: UIViewController, animated: Bool, completion: (() -> Void)?) {
        let presenterAddr = Unmanaged.passUnretained(self).toOpaque()
        let presentedAddr = Unmanaged.passUnretained(vc).toOpaque()
        let currently = self.presentedViewController
        let currentlyDesc: String
        if let c = currently {
            currentlyDesc = "\(type(of: c))@\(Unmanaged.passUnretained(c).toOpaque())"
        } else {
            currentlyDesc = "nil"
        }
        NSLog("[HiMem][Present] presenter=\(type(of: self))@\(presenterAddr) → presented=\(type(of: vc))@\(presentedAddr) currentlyPresenting=\(currentlyDesc)")
        // Call the original implementation (swizzled back to point at it)
        himem_present(vc, animated: animated, completion: completion)
    }

    @objc func himem_dismiss(animated: Bool, completion: (() -> Void)?) {
        let targetAddr = Unmanaged.passUnretained(self).toOpaque()
        let presenter = self.presentingViewController
        let presenterDesc: String
        if let p = presenter {
            presenterDesc = "\(type(of: p))@\(Unmanaged.passUnretained(p).toOpaque())"
        } else {
            presenterDesc = "nil"
        }
        // Capture the call stack so we can see who's invoking the
        // dismiss. Skip the top frames (this method + swizzle trampoline)
        // and trim to the next ~12 frames, which is enough to spot a
        // SwiftUI internal reconciliation vs. a user-code call (e.g.
        // `@Environment(\.dismiss)` from BottomDeleteButton or a back
        // button binding). Filter to lines that mention HiMem, SwiftUI,
        // or UIKit so the noise is bearable.
        let frames = Thread.callStackSymbols.prefix(20).enumerated().compactMap { (i, line) -> String? in
            // Drop the first 2 frames (the swizzle trampoline + this method)
            guard i >= 2 else { return nil }
            return line
        }
        let trace = frames.joined(separator: "\n    ")
        NSLog("[HiMem][Dismiss] target=\(type(of: self))@\(targetAddr) presenter=\(presenterDesc)\n  stack:\n    \(trace)")
        himem_dismiss(animated: animated, completion: completion)
    }
}
