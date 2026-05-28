import Testing
import Foundation

/// **Cross-cutting invariant lints** for the pricing surfaces. Each
/// test corresponds to a Part F invariant in
/// `docs/Pricing · QA test script.md` — but instead of asking a
/// human to walk the canvas reading every CTA, they scan the source
/// files and fail loudly when the invariant is violated.
///
/// These run in the standard test pipeline; treat a failure here the
/// same as any other test failure. Adding a `$` to a Memory Detail
/// view file is now a build break, not a polish backlog item.
///
/// Three invariants covered:
///
///   - **F1** · No dollar amounts on Memory Detail surfaces.
///   - **F6** · No hardcoded color literals in AI-zone view files
///     (forces Crucible token discipline so colors can't drift
///     out of the ochre / AI-blue / warn-tint palette).
///   - **F7** · Voice check — banned phrases (`click here`,
///     `leverage`, `delight`, `ecosystem`, blame language).
///
/// Each test uses `#filePath` to locate the project's view directory
/// without hardcoding an absolute path, so this works on any
/// machine / CI runner that builds the same checkout.
struct PricingQAInvariantsTests {

    /// Files allowed to mention currency — the surfaces where price
    /// reveal is intentional per the pricing spec.
    private static let memoryDetailSurfaceFiles: Set<String> = [
        "EntryExpandedView.swift",
        "OrganizeMemoryCard.swift",
        "AISuggestionsCard.swift",
        "OrganizeMemorySection.swift",
        "OrganizedChip.swift",
    ]

    /// AI-zone view files. Color discipline applies here: no
    /// hardcoded `Color(red:green:blue:)` literals — must go
    /// through `Crucible.Color.*` tokens so palette drifts are
    /// caught at the token level.
    private static let aiZoneFiles: Set<String> = [
        "OrganizeMemoryCard.swift",
        "AISuggestionsCard.swift",
        "OrganizedChip.swift",
    ]

    /// Phrases the voice spec bans in user-facing copy. Case-
    /// insensitive substring match against any string literal in a
    /// view file. Add to this list as the voice rules evolve.
    private static let bannedPhrases: [String] = [
        "click here",
        "leverage",
        "delight",
        "ecosystem",
        "you are offline",
    ]

    // MARK: - Path resolution

    /// Derives the project's `Views/` directory from this test
    /// file's path via `#filePath`. Compile-time path capture is
    /// stable across machines as long as the repo layout doesn't
    /// move.
    private static func viewsDirectory(testFilePath: String = #filePath) -> URL {
        URL(fileURLWithPath: testFilePath)
            .deletingLastPathComponent()  // .../MemoryStreamTests/
            .deletingLastPathComponent()  // .../MemoryStream/ (project root)
            .appendingPathComponent("MemoryStream")
            .appendingPathComponent("Views")
    }

    /// Walks `Views/` and returns every `.swift` file's URL.
    private static func enumerateViewFiles() throws -> [URL] {
        let root = viewsDirectory()
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw InvariantError.directoryNotFound(root.path)
        }
        var out: [URL] = []
        for case let url as URL in enumerator
            where url.pathExtension == "swift" {
            out.append(url)
        }
        return out
    }

    enum InvariantError: Error, CustomStringConvertible {
        case directoryNotFound(String)
        var description: String {
            switch self {
            case .directoryNotFound(let path):
                return "Views directory not found at \(path) — did the project layout move?"
            }
        }
    }

    // MARK: - Line-level scanning

    /// Reads a file and returns `[(lineNumber, lineText)]`. Strips
    /// nothing — comments included, since we scan for `$` patterns
    /// inside string literals using a heuristic and want to be able
    /// to whitelist comment text when needed.
    private static func lines(of url: URL) throws -> [(Int, String)] {
        let body = try String(contentsOf: url, encoding: .utf8)
        return body.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { ($0.offset + 1, String($0.element)) }
    }

    /// True when the line contains a `$` followed by a digit inside
    /// a string literal — the currency pattern (`$4.99`, `$0.25`,
    /// `$19.99`). Avoids the SwiftUI binding syntax (`$variableName`
    /// always followed by a letter / underscore, never a digit).
    private static func lineContainsCurrencyLiteral(_ line: String) -> Bool {
        // Match `$\d` only when the `$` is between double-quotes,
        // i.e., we're in a string literal. Cheap heuristic: any
        // occurrence of `"..."` with `$\d` inside on the same line.
        guard let dollarRange = line.range(of: #"\$\d"#, options: .regularExpression) else {
            return false
        }
        // Confirm `$\d` sits inside a `"…"` literal on this line.
        // Count quotes before `$` — odd count means we're inside a
        // string. Naive but enough for one-line literals (the only
        // ones we care about in view code).
        let prefix = line[..<dollarRange.lowerBound]
        let quoteCount = prefix.filter { $0 == "\"" }.count
        return quoteCount % 2 == 1
    }

    /// True when the line contains a hardcoded `Color(red:green:blue:)`
    /// or `Color(red:green:blue:opacity:)` literal in user code (not
    /// a comment).
    private static func lineContainsHardcodedColorLiteral(_ line: String) -> Bool {
        // Strip leading whitespace + comment-only lines.
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") { return false }
        // Drop any trailing comment on the line so the regex
        // doesn't false-positive on documentation snippets.
        let codeOnly: String
        if let commentRange = trimmed.range(of: "//") {
            codeOnly = String(trimmed[..<commentRange.lowerBound])
        } else {
            codeOnly = trimmed
        }
        return codeOnly.range(of: #"Color\(\s*red\s*:"#, options: .regularExpression) != nil
    }

    /// Returns every (lineNumber, matchedPhrase) hit in a file for
    /// banned phrases, scanning string-literal content only.
    /// Heuristic: extract `"..."` segments per line and match
    /// case-insensitively against the banned list.
    private static func bannedPhraseHits(in line: String) -> [String] {
        // Skip comment-only lines.
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") { return [] }
        // Find string-literal segments on the line.
        guard let regex = try? NSRegularExpression(pattern: "\"([^\"]*)\"") else { return [] }
        let nsLine = line as NSString
        let matches = regex.matches(
            in: line,
            range: NSRange(location: 0, length: nsLine.length)
        )
        var hits: [String] = []
        for m in matches where m.numberOfRanges >= 2 {
            let inner = nsLine.substring(with: m.range(at: 1)).lowercased()
            for phrase in bannedPhrases where inner.contains(phrase) {
                hits.append(phrase)
            }
        }
        return hits
    }

    // MARK: - F1 · No dollar amounts on Memory Detail

    /// Walks every Memory Detail surface file (per
    /// `memoryDetailSurfaceFiles`) and fails if any line contains a
    /// currency-pattern string literal. Per QA script F1 — dollar
    /// amounts appear only on AIPackPurchaseSheet, Upgrade Hub,
    /// and Founders detail, never on Memory Detail.
    @Test func f1_noDollarSignsOnMemoryDetailSurfaces() throws {
        let files = try Self.enumerateViewFiles()
            .filter { Self.memoryDetailSurfaceFiles.contains($0.lastPathComponent) }
        // Sanity: at least some of the named files must exist;
        // otherwise the path resolver broke and the test is silently
        // passing.
        #expect(!files.isEmpty,
                "Could not find any Memory Detail surface files — path resolver broken?")

        var violations: [String] = []
        for url in files {
            for (lineNumber, line) in try Self.lines(of: url) {
                if Self.lineContainsCurrencyLiteral(line) {
                    violations.append("\(url.lastPathComponent):\(lineNumber): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(violations.isEmpty,
                """
                F1 invariant violated — found currency literals on Memory Detail surfaces.
                Spec: dollar amounts appear only on AIPackPurchaseSheet, Upgrade Hub, and
                Founders detail. Move the copy or remove the literal:

                \(violations.joined(separator: "\n"))
                """)
    }

    // MARK: - F6 · AI color discipline (no hardcoded color literals)

    /// AI-zone view files must use `Crucible.Color.*` tokens, never
    /// raw `Color(red:green:blue:…)` literals. Catches the kind of
    /// drift that produced the old `Color(red: 0.96, green: 0.91,
    /// blue: 0.82)` icon background — a hardcoded warm beige that
    /// should have been `Crucible.Color.sunk` so dark mode auto-
    /// flipped.
    @Test func f6_aiZoneFilesUseNoHardcodedColorLiterals() throws {
        let files = try Self.enumerateViewFiles()
            .filter { Self.aiZoneFiles.contains($0.lastPathComponent) }
        #expect(!files.isEmpty,
                "Could not find any AI-zone files — path resolver broken?")

        var violations: [String] = []
        for url in files {
            for (lineNumber, line) in try Self.lines(of: url) {
                if Self.lineContainsHardcodedColorLiteral(line) {
                    violations.append("\(url.lastPathComponent):\(lineNumber): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(violations.isEmpty,
                """
                F6 invariant violated — hardcoded color literals in AI-zone files.
                Use `Crucible.Color.*` tokens instead so palette + dark-mode flip
                propagate uniformly:

                \(violations.joined(separator: "\n"))
                """)
    }

    // MARK: - F7 · Voice check

    /// Scans every view file's string literals for the banned voice
    /// phrases. Designed to fail loudly on the corporate-speak
    /// regression (`leverage`, `delight`, `ecosystem`), lazy CTAs
    /// (`click here`), and blame language (`you are offline`).
    /// Adding to the banned list is a one-line change in the array
    /// above this test.
    @Test func f7_noBannedPhrasesInViewStringLiterals() throws {
        let files = try Self.enumerateViewFiles()
        #expect(!files.isEmpty, "No view files found — path resolver broken?")

        var violations: [String] = []
        for url in files {
            for (lineNumber, line) in try Self.lines(of: url) {
                let hits = Self.bannedPhraseHits(in: line)
                for hit in hits {
                    violations.append("\(url.lastPathComponent):\(lineNumber) — `\(hit)` in: \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(violations.isEmpty,
                """
                F7 invariant violated — banned voice phrases in user-facing string literals.
                Refer to `docs/design/CLAUDE.md` § Voice for the rules. If the phrase is
                intentional (e.g., quoting an OS string), wrap in a non-Text literal or
                move to a constant outside the view layer:

                \(violations.joined(separator: "\n"))
                """)
    }

    // MARK: - Self-test: confirm the scanners actually work

    /// The lint is only useful if it catches violations when they
    /// exist. These self-tests construct synthetic input and assert
    /// the scanners flag it. Without these, an accidentally broken
    /// regex would silently green-light every PR.

    @Test func selfTest_currencyLiteralIsDetected() {
        #expect(Self.lineContainsCurrencyLiteral(#"Text("Buy 100 assists · $19.99")"#))
        #expect(Self.lineContainsCurrencyLiteral(#"let title = "Just $4.99/mo""#))
    }

    @Test func selfTest_swiftUIBindingIsNotFlaggedAsCurrency() {
        // `$selected` (binding) followed by a letter — must not
        // trip the currency check.
        #expect(!Self.lineContainsCurrencyLiteral("Toggle(isOn: $selected) { ... }"))
        #expect(!Self.lineContainsCurrencyLiteral("@State var $foo = 0"))
    }

    @Test func selfTest_hardcodedColorIsDetected() {
        #expect(Self.lineContainsHardcodedColorLiteral(
            #".fill(Color(red: 0.96, green: 0.91, blue: 0.82))"#
        ))
    }

    @Test func selfTest_crucibleTokenIsNotFlaggedAsHardcodedColor() {
        #expect(!Self.lineContainsHardcodedColorLiteral(
            #".fill(Crucible.Color.sunk)"#
        ))
        #expect(!Self.lineContainsHardcodedColorLiteral(
            "// Color(red: 0.5, green: 0.5, blue: 0.5)  — historical note"
        ))
    }

    @Test func selfTest_bannedPhraseIsDetected() {
        let hits = Self.bannedPhraseHits(in: #"Text("Click here to upgrade")"#)
        #expect(hits.contains("click here"))
    }

    @Test func selfTest_bannedPhraseInCommentIsIgnored() {
        // Comments don't carry user-facing voice — the lint only
        // cares about string literals.
        let hits = Self.bannedPhraseHits(in: "// We used to say click here, now we say tap")
        #expect(hits.isEmpty)
    }
}
