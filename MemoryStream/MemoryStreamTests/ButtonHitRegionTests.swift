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

    // MARK: - F29 self-tests (the extension must be able to fail)

    /// Flags the exact shipped shape: a String-label Button wearing a fill
    /// with no contentShape.
    @Test func scanner_flagsAFilledStringLabelButton() {
        let shipped = """
                Button("Got it", action: orchestrator.gotIt)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Crucible.Color.accentInk)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(Crucible.Color.accent, in: RoundedRectangle(cornerRadius: 10))
        """
        #expect(Self.isOffendingStringLabelButton(block: shipped),
                "A filled String-label button draws a pill but only taps on its text — the F29 defect.")
    }

    /// A bare-text action (the nav/sheet top-bar exception) is NOT a
    /// violation — its hit region should be its text.
    @Test func scanner_ignoresAnUndecoratedTextButton() {
        let plain = """
                Button("Cancel") { player.stop(); dismiss() }
                    .font(.system(size: 15.5))
                    .foregroundStyle(Crucible.Color.ink2)
        """
        #expect(!Self.isOffendingStringLabelButton(block: plain))
    }

    /// And the fix is accepted, so the guard cannot fail permanently.
    @Test func scanner_acceptsAShapedStringLabelButton() {
        let fixed = """
                Button("Got it", action: orchestrator.gotIt)
                    .background(Crucible.Color.accent, in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
        """
        #expect(!Self.isOffendingStringLabelButton(block: fixed))
    }

    /// Closure-label buttons stay exempt — F17 verified those fill inside the
    /// label, so the whole pill already carries taps.
    @Test func scanner_ignoresAClosureLabelFilledButton() {
        let closure = """
                Button { act() } label: {
                    Text("Save")
                        .frame(maxWidth: .infinity)
                        .background(Crucible.Color.accent)
                }
        """
        #expect(!Self.isOffendingStringLabelButton(block: closure))
    }

    /// Regression for the over-report: a bare-text top-bar button must NOT be
    /// convicted by its enclosing container's fill. This is the assertion that
    /// turns "11 candidates" into "2 defects".
    @Test func scanner_doesNotConvictAButtonOfItsContainersFill() {
        let topBar = """
                Button("Cancel") { player.stop(); dismiss() }
                    .font(.system(size: 15.5))
                    .foregroundStyle(Crucible.Color.ink2)
                Spacer()
                Text(Self.editorTitle)
            }
            .frame(height: 52)
            .background(Crucible.Color.paper)
        """
        #expect(!Self.isOffendingStringLabelButton(block: topBar),
                "The HStack's background is not this button's fill.")
    }

    // MARK: - Scanner

    /// The predicate, isolated so the two scanner tests above can exercise it
    /// directly rather than through the filesystem.
    /// **F29 · the shape the original guard could not see.**
    ///
    /// F17 swept STROKED, unfilled pills and explicitly cleared the filled
    /// ochre primaries — correctly, because those apply `.frame`/`.background`
    /// **inside a label closure**, so the whole pill is hit-testable.
    ///
    /// But `Button("Got it", action:)` takes a **String label**. There is no
    /// label closure, so every modifier below attaches to the *Button*, not to
    /// its label: the fill draws a 40pt ochre pill while the tap region stays
    /// the glyph-width of the text. Visually identical to a correct primary,
    /// and dead everywhere but the letters — which is exactly how the
    /// walkthrough's "Got it" reached a dogfooder.
    ///
    /// `filled` was the original predicate's *exoneration*, which is why it
    /// scored this button clean forever. Here a fill is evidence of the
    /// defect, not against it.
    static func isOffendingStringLabelButton(block: String) -> Bool {
        let lines = block.components(separatedBy: "\n")
        guard let head = lines.first,
              head.range(of: #"\bButton\s*\(\s*["]"#, options: .regularExpression) != nil
        else { return false }

        // **Attribute the decoration to THIS button's own modifier chain.**
        // A fixed line window bled into whatever enclosing container came
        // next: a first pass flagged 11 sites, of which validation found 2 —
        // `Button("Cancel")` in a top bar was "filled" by the HStack's
        // `.background` eight lines below it. Same over-report F17 hit (16 →
        // 7), same remedy: check the candidate, never trust the count. The
        // chain is the contiguous run of lines that begin with `.`.
        var chain = ""
        for line in lines.dropFirst() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("//") { continue }
            guard t.hasPrefix(".") else { break }
            chain += t + "\n"
        }

        let decorated = chain.range(
            of: #"\.background\(|\.fill\(|\.stroke\(|\.strokeBorder\("#,
            options: .regularExpression
        ) != nil
        // An undecorated `Button("Cancel", action:)` is a legitimate bare-text
        // action (nav/sheet top bar) — its hit region SHOULD be its text.
        return decorated && !chain.contains("contentShape")
    }

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
                if isOffending(block: block) || isOffendingStringLabelButton(block: block) {
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
