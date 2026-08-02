import Testing
import Foundation
@testable import HiMem

/// **F28 — Learn survived a tab round-trip and re-presented out of context.**
///
/// Observed: open Learn from Clips → switch to Memories without choosing
/// anything → return to Clips → the hub is there again.
///
/// ROOT CAUSE: `showTutorials` was a **tab-local `@State`**, and Learn
/// pushes onto that tab's own `NavigationStack`. A `TabView` keeps every
/// tab alive, so nothing popped the push — the tab simply stopped being
/// visible, then became visible again with its stack exactly as left.
/// **A tab cannot observe that the tab changed; only the shell can.**
///
/// The fix moves ownership to `HiMemTabView.learnOpenOn` (a `Tab?`, not a
/// shared `Bool` — one flag would push Learn onto every stack at once),
/// cleared in the shell's existing `.onChange(of: selection)`.
///
/// Deliberately NOT a new ambient singleton: F6 names that accumulation —
/// "every one of those globals was a locally reasonable call" — as the
/// cost this codebase is already paying. The shell already owns tab
/// selection, so it is the honest owner for "which tab has Learn open".
///
/// These are source-level guards. The behaviour lives in SwiftUI
/// presentation state that no unit test can drive, so the invariants
/// asserted here are structural: **ownership sits above the tabs, and the
/// shell clears it on a tab change.**
@Suite struct LearnStickinessTests {

    /// Neither tab may own the flag again. A tab-local `@State` is the
    /// defect, reintroduced.
    @Test func noTabOwnsTheLearnFlag() throws {
        for path in ["MemoryStream/Views/ClipsTabView.swift",
                     "MemoryStream/Views/Journal/JournalView.swift"] {
            let src = try Self.source(path)
            #expect(src.contains("@Binding var learnPresented"),
                    "\(path) must take Learn presentation from the shell.")
            #expect(src.contains("@State private var showTutorials") == false,
                    "\(path) re-owns Learn as tab-local state — F28 returns.")
        }
    }

    /// The shell must clear it when the tab changes. Without this the
    /// binding alone changes nothing: the push still survives.
    @Test func theShellClearsLearnOnTabChange() throws {
        let src = try Self.source("MemoryStream/Views/HiMemTabView.swift")
        #expect(src.contains("@State private var learnOpenOn: Tab?"),
                "The shell no longer owns which tab has Learn open.")

        let body = try Self.closureBody(after: ".onChange(of: selection)", in: src)
        #expect(body.contains("learnOpenOn = nil"),
                """
                The shell does not clear Learn on a tab change, so the hub \
                still survives a round-trip. Handler was:
                \(body)
                """)
    }

    /// A single shared Bool would push Learn onto every tab's stack at
    /// once. The optional-Tab shape is load-bearing, not incidental.
    @Test func learnOwnershipIsPerTab_notOneSharedFlag() throws {
        let src = try Self.source("MemoryStream/Views/HiMemTabView.swift")
        for tab in ["clips", "memories", "projects"] {
            #expect(src.contains("learnOpenOn == .\(tab)"),
                    "The \(tab) tab is not bound to its own Learn slot.")
        }
    }

    // MARK: - Source access

    /// The body of the first closure following `needle`, brace-matched.
    static func closureBody(after needle: String, in source: String) throws -> String {
        guard let start = source.range(of: needle)?.lowerBound else {
            throw Failure.notFound(needle)
        }
        var depth = 0, started = false
        var out = ""
        for ch in source[start...] {
            if ch == "{" { depth += 1; started = true }
            if ch == "}" { depth -= 1 }
            if started { out.append(ch) }
            if started && depth == 0 { return out }
        }
        throw Failure.notFound(needle)
    }

    static func source(_ relative: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        guard let src = try? String(contentsOf: url, encoding: .utf8), !src.isEmpty else {
            throw Failure.sourceNotFound(url.path)
        }
        return src
    }

    enum Failure: Error { case sourceNotFound(String), notFound(String) }
}
