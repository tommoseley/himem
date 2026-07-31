import Testing
import Foundation

/// F17 · **structural guard for the tap-target class.**
///
/// SwiftUI hit-tests *drawn content*. A button decorated with a stroke and no
/// fill has a transparent interior, so only its glyph and label are tappable —
/// the padding inside the pill is not. The button looks full-width and responds
/// only where the words are.
///
/// This defect has now been fixed three times by hand:
///   1. four solid-stroke Delete buttons (Clip Editor, Clip Detail ×2, the
///      Clips selection bar);
///   2. the dashed add affordances;
///   3. F17 — seven more (four blue AI, two neutral, one ochre), found only
///      because Tom and Judi independently hit "Apply range" in Search.
///
/// Each sweep fixed the instances in front of it and the class came back,
/// because **the invariant lived in every author's head instead of in one
/// owner** (the F6a thesis). The right long-term fix is a shared button
/// primitive carrying the hit region by construction — deferred post-tag, since
/// `HiMem · Buttons & Actions` defines four ranks across three colours and that
/// is real surface area to route nine days from submit (Tom, 2026-07-31).
///
/// So this test is the structural guard in the meantime: it fails on the
/// *fourth* occurrence rather than waiting for a user to find it. It is a
/// source scan, which is unusual for a unit test — that is deliberate. The
/// invariant is a property of how views are written, and nothing else in the
/// suite can observe it.
///
/// **If this fails, do not add a background just to make the button tappable**
/// — that changes the visual rank the design system assigns (filled = primary,
/// bordered = secondary). Add `.contentShape(Rectangle())`, which makes the
/// whole pill hit-testable and changes nothing on screen.
@Suite
struct ButtonHitRegionTests {

    /// A `Button` whose label is decorated with a stroke, carries no fill, and
    /// declares no `contentShape` — i.e. a pill that only responds where its
    /// text is drawn.
    struct Offender: CustomStringConvertible {
        let file: String
        let line: Int
        var description: String { "\(file):\(line)" }
    }

    /// THE GUARD. Every stroke-decorated button must declare a hit region.
    @Test func everyStrokedButtonDeclaresAHitRegion() throws {
        let root = try Self.viewsRoot()
        let offenders = Self.scan(root: root)

        #expect(
            offenders.isEmpty,
            """
            Stroke-decorated button(s) with a transparent interior and no hit region — \
            these respond only where the text is drawn, not across the pill:
            \(offenders.map { "  • \($0)" }.joined(separator: "\n"))

            Fix: add `.contentShape(Rectangle())` to the button's label. Do NOT add \
            a background — that changes the rank the design system assigns.
            """
        )
    }

    /// Guards the guard: the scanner must actually find offenders when they
    /// exist. Without this, a regex that silently matches nothing would report
    /// a clean sweep forever — the "green for the wrong reason" failure this
    /// project has already hit twice.
    @Test func scannerDetectsAKnownOffendingShape() {
        let synthetic = """
        Button {
            act()
        } label: {
            Text("Apply range")
                .padding(.horizontal, 14)
                .overlay(Capsule().stroke(Color.gray, lineWidth: 1))
        }
        """
        #expect(
            Self.isOffending(block: synthetic),
            "Scanner failed to flag a stroked, unfilled, unshaped button — the guard is not guarding"
        )
    }

    /// And the converse: a filled button, or one that already declares a hit
    /// region, must NOT be flagged. Catches a scanner so eager it reports
    /// everything (equally useless, and noisier).
    @Test func scannerIgnoresFilledAndAlreadyShapedButtons() {
        let filled = """
        Button { act() } label: {
            Text("Attach")
                .frame(maxWidth: .infinity)
                .background(Crucible.Color.accent)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.clear))
        }
        """
        let ternaryFilled = """
        Button { act() } label: {
            Text("Toggle")
                .background(isActive ? Crucible.Color.accent : Crucible.Color.card)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Crucible.Color.hairline))
        }
        """
        let shaped = """
        Button { act() } label: {
            Text("Delete")
                .padding()
                .overlay(Capsule().stroke(Crucible.Color.danger))
                .contentShape(Rectangle())
        }
        """
        #expect(!Self.isOffending(block: filled), "a filled button is hit-testable")
        #expect(!Self.isOffending(block: ternaryFilled),
                "ternary backgrounds are still fills — missing this over-reported 16 candidates as 7 (2026-07-31)")
        #expect(!Self.isOffending(block: shaped), "an explicit contentShape is the fix, not a violation")
    }

    // MARK: - Scanner

    /// The predicate, isolated so the two scanner tests above can exercise it
    /// directly rather than through the filesystem.
    static func isOffending(block: String) -> Bool {
        let stroked = block.range(of: #"\.stroke\(|\.strokeBorder\("#, options: .regularExpression) != nil
        // ANY fill counts, including a ternary — `.background(isActive ? a : b)`.
        let filled  = block.range(of: #"\.background\(|\.fill\("#, options: .regularExpression) != nil
        let shaped  = block.contains("contentShape")
        return stroked && !filled && !shaped
    }

    /// Walks the shipped view sources and returns every offending button.
    static func scan(root: URL) -> [Offender] {
        var out: [Offender] = []
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil
        ) else { return out }

        for case let url as URL in walker where url.pathExtension == "swift" {
            guard let src = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = src.components(separatedBy: "\n")
            for (i, line) in lines.enumerated() {
                guard line.range(of: #"\bButton\b\s*(\{|\()"#, options: .regularExpression) != nil
                else { continue }
                // A button's label rarely exceeds ~32 lines; a wider window
                // starts bleeding into the next declaration and under-reports.
                let block = lines[i..<min(i + 32, lines.count)].joined(separator: "\n")
                if isOffending(block: block) {
                    out.append(Offender(file: url.lastPathComponent, line: i + 1))
                }
            }
        }
        return out
    }

    /// Locates `MemoryStream/Views/` from this file's own path — the test
    /// bundle does not carry sources, so `#filePath` is the only anchor that
    /// works both locally and in CI.
    static func viewsRoot() throws -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)          // …/MemoryStreamTests/ButtonHitRegionTests.swift
        let projectRoot = thisFile
            .deletingLastPathComponent()                        // …/MemoryStreamTests
            .deletingLastPathComponent()                        // …/MemoryStream (project dir)
        let views = projectRoot
            .appendingPathComponent("MemoryStream")
            .appendingPathComponent("Views")
        guard FileManager.default.fileExists(atPath: views.path) else {
            throw ScanError.viewsDirectoryNotFound(views.path)
        }
        return views
    }

    enum ScanError: Error, CustomStringConvertible {
        case viewsDirectoryNotFound(String)
        var description: String {
            switch self {
            case .viewsDirectoryNotFound(let p):
                return "Views/ not found at \(p) — the scan anchor moved; fix `viewsRoot()` rather than deleting this guard."
            }
        }
    }
}
