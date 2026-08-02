import Testing
import Foundation
@testable import HiMem

/// **F27 — a breadcrumb that names a place but not the thing to press.**
///
/// Reported as *"Beats say 'Settings → Learn'; there is only 'Show me
/// around'"*, and flagged as the second time a breadcrumb promised a
/// surface that isn't there.
///
/// **Verified enumeration — the premise needed one correction, and the
/// correction matters because acting on the stated version would have
/// been wrong.** `Settings → Learn` *does* exist and does work:
/// `SettingsView` has a live `NavigationLink` labelled "Learn" pushing
/// `TutorialsHubView`, whose `navigationTitle` is "Learn". So the old copy
/// was not false. It failed two other ways:
///
///  1. It stopped at the door. What she taps once inside is a row titled
///     **"Show me around"** (`TutorialCatalog.tour`), and nothing said so.
///  2. It named the LONGER of two routes — there is a `?` in the toolbar
///     of the screen she is already on (Clips and Memories both), which
///     opens the same hub.
///
/// So the fix is to name the control and prefer the nearer path, not to
/// delete a promise that was being kept.
///
/// **The durable half is the binding**: `breadcrumbsNameARowThatExists`
/// ties the copy to the shipped catalogue entry, so renaming the row
/// without updating the copy fails here rather than on a user's screen.
/// That is what makes this the last time rather than the third.
@Suite struct WalkthroughBreadcrumbTests {

    /// THE GUARD. Every breadcrumb must name a control that actually
    /// ships. Bound to `TutorialCatalog.tour.title`, not to a literal, so
    /// the two cannot drift apart silently.
    @Test func breadcrumbsNameARowThatExists() {
        let row = TutorialCatalog.tour.title
        #expect(row == "Show me around", "The tour row was renamed — the breadcrumbs below must move with it.")

        for (label, copy) in [
            ("skipBreadcrumb", WalkthroughOrchestrator.Beat.skipBreadcrumb),
            ("closingLine",    WalkthroughOrchestrator.Beat.closingLine)
        ] {
            #expect(copy.contains(row), "\(label) does not name the control she has to tap (\"\(row)\"): \(copy)")
        }
    }

    /// The hub she is sent to is titled "Learn", so the copy may say
    /// "Learn" — that word is load-bearing and must not drift either.
    @Test func breadcrumbsNameTheHubByItsTitle() {
        #expect(WalkthroughOrchestrator.Beat.skipBreadcrumb.contains("Learn"))
        #expect(WalkthroughOrchestrator.Beat.closingLine.contains("Learn"))
    }

    /// The nearer route is the toolbar `?`, and the breadcrumb she reads
    /// mid-flow should point at the screen she is already on rather than
    /// send her into Settings.
    @Test func skipBreadcrumb_pointsAtTheNearerRoute() {
        let crumb = WalkthroughOrchestrator.Beat.skipBreadcrumb
        #expect(crumb.contains("?"), "The one-tap route (the toolbar ?) is unnamed: \(crumb)")
        #expect(crumb.contains("Settings") == false,
                "Sends her to Settings when a ? is on the screen she's looking at: \(crumb)")
    }

    /// Crucible voice — these are quiet orientation lines, not scolds, and
    /// they never blame.
    @Test func breadcrumbs_keepTheVoice() {
        for copy in [WalkthroughOrchestrator.Beat.skipBreadcrumb,
                     WalkthroughOrchestrator.Beat.closingLine] {
            #expect(copy.hasPrefix("You ") == false || copy.hasPrefix("You'll"),
                    "Second-person accusation: \(copy)")
            #expect(copy.lowercased().contains("part") == false)      // F7g / F13
            #expect(copy.lowercased().contains("evidence") == false)  // F7g
        }
    }

    /// The offer card's decline button carries the same promise and must
    /// keep the same terms.
    @Test func offerDeclineCopy_namesTheSameControl() throws {
        let src = try Self.source("MemoryStream/Views/Components/WalkthroughOverlay.swift")
        #expect(src.contains("Learn → Show me around"),
                "The offer card's 'Not now' still promises a path that doesn't name the control.")
        #expect(src.contains("Settings → Learn") == false,
                "A 'Settings → Learn' promise survives in the overlay.")
    }

    /// No production string may still promise the old path.
    @Test func noWalkthroughCopy_stillSaysSettingsArrowLearn() throws {
        for path in ["MemoryStream/Services/Tutorials/WalkthroughOrchestrator.swift",
                     "MemoryStream/Views/Components/WalkthroughOverlay.swift"] {
            let src = try Self.source(path)
            // Comments legitimately discuss the old wording; only string
            // literals are user-facing.
            let literals = src.split(separator: "\n").filter {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("//") && !t.hasPrefix("///") && t.contains("\"")
            }
            for line in literals {
                #expect(line.contains("Settings → Learn") == false,
                        "A user-facing string still promises 'Settings → Learn' in \(path): \(line)")
            }
        }
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

    enum Failure: Error { case sourceNotFound(String) }
}
