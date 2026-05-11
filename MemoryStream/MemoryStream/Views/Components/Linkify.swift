import Foundation
import SwiftUI

extension String {
    /// Returns an `AttributedString` where URL-shaped substrings carry the
    /// `.link` attribute, so a SwiftUI `Text` renders them as tappable links
    /// that open via `UIApplication.shared.open` on tap. Used to make URLs
    /// in dictated transcripts and typed notes clickable without altering
    /// the underlying stored text — detection runs at render time.
    ///
    /// Catches the full `NSDataDetector` link family: `http(s)://`, bare
    /// domains (`example.com`), `mailto:` (`hi@example.com`), and `tel:`.
    func attributedWithLinks() -> AttributedString {
        guard !isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else {
            return AttributedString(self)
        }
        let mutable = NSMutableAttributedString(string: self)
        let range = NSRange(location: 0, length: (self as NSString).length)
        detector.enumerateMatches(in: self, options: [], range: range) { match, _, _ in
            guard let match, let url = match.url else { return }
            mutable.addAttribute(.link, value: url, range: match.range)
        }
        return AttributedString(mutable)
    }
}
