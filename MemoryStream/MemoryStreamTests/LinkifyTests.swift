import Testing
import Foundation
@testable import MemoryStream

@Suite struct LinkifyTests {

    /// Collects every distinct URL referenced via `.link` runs in an
    /// `AttributedString`, in order of appearance.
    private func extractLinks(_ attr: AttributedString) -> [URL] {
        var urls: [URL] = []
        for run in attr.runs {
            if let url = run.link, urls.last != url {
                urls.append(url)
            }
        }
        return urls
    }

    @Test func plainText_hasNoLinks() {
        let result = "Just a normal note with no URLs.".attributedWithLinks()
        #expect(extractLinks(result).isEmpty)
    }

    @Test func emptyString_returnsEmptyAttributedString() {
        let result = "".attributedWithLinks()
        #expect(String(result.characters) == "")
        #expect(extractLinks(result).isEmpty)
    }

    @Test func httpsURL_isDetected() {
        let result = "See https://example.com for details".attributedWithLinks()
        let links = extractLinks(result)
        #expect(links.count == 1)
        #expect(links.first?.absoluteString == "https://example.com")
    }

    @Test func bareDomain_isDetected() {
        let result = "Visit example.com today".attributedWithLinks()
        let links = extractLinks(result)
        #expect(links.count == 1)
        // NSDataDetector normalises bare domains to `http://example.com`.
        #expect(links.first?.host == "example.com")
    }

    @Test func mailtoAddress_isDetected() {
        let result = "Email hi@example.com please".attributedWithLinks()
        let links = extractLinks(result)
        #expect(links.count == 1)
        #expect(links.first?.scheme == "mailto")
    }

    @Test func multipleURLs_allDetected() {
        let result = "Two: https://a.com and https://b.com here.".attributedWithLinks()
        let links = extractLinks(result)
        #expect(links.count == 2)
        #expect(links.map(\.absoluteString) == ["https://a.com", "https://b.com"])
    }

    @Test func nonLinkText_aroundURL_isUnchanged() {
        let source = "Visit https://example.com today"
        let result = source.attributedWithLinks()
        // Character content round-trips unchanged.
        #expect(String(result.characters) == source)
    }
}
