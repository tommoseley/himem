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


    // MARK: - F29-sequel self-tests (the extension must be able to fail)

    /// The shipped shape: a closure-label button whose fill and stroke attach
    /// to the Button. This is `tourCard` as it shipped.
    @Test func scanner_flagsAClosureLabelWithOutsideDecoration() {
        let shipped = """
        Button {
            WalkthroughOrchestrator.shared.start()
            dismiss()
        } label: {
            TutorialsHubRow(entry: TutorialCatalog.tour)
        }
        .buttonStyle(.plain)
        .background(Crucible.Color.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
        """
        #expect(Self.isOffendingClosureLabelOutsideDecoration(block: shipped),
                "Decoration outside a closure label leaves the tap region at the glyphs — the F29 mechanism.")
    }

    /// The fix is accepted, so the guard cannot fail permanently.
    @Test func scanner_acceptsAnOutsideDecoratedButtonWithAShapedLabel() {
        let fixed = """
        Button {
            act()
        } label: {
            TutorialsHubRow(entry: TutorialCatalog.tour)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Crucible.Color.card)
        """
        #expect(!Self.isOffendingClosureLabelOutsideDecoration(block: fixed))
    }

    /// And the converse: decoration INSIDE the label is the shape F17 verified
    /// as hit-testable. It must not be convicted by this scanner, or the
    /// extension re-reports everything F17 cleared.
    @Test func scanner_ignoresDecorationInsideTheLabel() {
        let inside = """
        Button {
            act()
        } label: {
            Text("Save")
                .frame(maxWidth: .infinity)
                .background(Crucible.Color.accent)
        }
        .buttonStyle(.plain)
        """
        #expect(!Self.isOffendingClosureLabelOutsideDecoration(block: inside))
    }


    /// **The over-report this scanner committed on its first run.** A label
    /// whose own `HStack` carries the fill and stroke is CORRECT — the
    /// decoration is inside the label. Convicting it flags five shipped views
    /// that were never defective.
    @Test func scanner_doesNotConvictALabelOfItsOwnInnerDecoration() {
        let correct = """
        Button {
            act()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "plus")
                Text("New project")
            }
            .padding(.horizontal, 10)
            .background(Crucible.Color.card)
            .overlay(Capsule().stroke(Crucible.Color.hairline, lineWidth: 1))
        }
        """
        #expect(!Self.isOffendingClosureLabelOutsideDecoration(block: correct),
                "The HStack's own decoration is inside the label — this is the correct shape, not a defect.")
    }


    /// **The second over-report.** `Button { act() } label: {` opens and closes
    /// its action closure on one line; the label's fill lives on the ENCLOSING
    /// container, not on the button. Convicting it repeats the
    /// container-attribution error the String-label scanner already guards
    /// against — SearchView's "When" chip, 2026-08-23.
    @Test func scanner_doesNotConvictAOneLineButtonOfItsContainersFill() {
        let chip = """
            Button { showWhen = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                    Text("When")
                }
                .padding(.leading, 12)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showWhen) {
                WhenPopover(viewModel: viewModel, isPresented: $showWhen)
            }
        }
        .background(active ? Crucible.Color.accent : Crucible.Color.sunk)
        .clipShape(Capsule())
        """
        #expect(!Self.isOffendingClosureLabelOutsideDecoration(block: chip),
                "The enclosing HStack's background is not this button's fill.")
    }


    /// **THE SHAPE THAT CRASHED THE HOST** (2026-08-25). A button whose label
    /// OPENS AND CLOSES ON THE SAME LINE makes `close == labelIdx`, so the
    /// label-body slice became `lines[(n+1)...n]` — lower bound above upper
    /// bound — and Swift traps: *"Range requires lowerBound <= upperBound"*.
    ///
    /// A trap is not an assertion failure. It kills the PROCESS, so 196
    /// unrelated suites came down with it and the run reported 199 failures
    /// for one defect.
    ///
    /// **The scanner never had to be pointed at anything — being read as source
    /// text was enough.** `SettingsView.swift` is under `Views/`, which this
    /// suite walks; a `#if DEBUG` probe that no test constructs supplied the
    /// shape just by existing. *A scanner's input is not what runs; it is what
    /// exists.*
    @Test func scanner_survivesALabelThatOpensAndClosesOnOneLine() {
        let oneLine = """
        Button { a += 1 } label: { pill("A — default") }
        """
        // The assertion is that this RETURNS. Before the fix it trapped.
        #expect(!Self.isOffendingClosureLabelOutsideDecoration(block: oneLine),
                "A one-line label with no decoration on the button is not an offender.")
    }

    /// The same shape WITH outside decoration is a genuine offender and must
    /// still be caught — bounding the slice must not blind the scanner.
    @Test func scanner_flagsAOneLineLabelThatIsDecoratedOutside() {
        let oneLineDecorated = """
        Button { a += 1 } label: { pill("A") }
        .buttonStyle(.plain)
        .background(Crucible.Color.card)
        """
        #expect(Self.isOffendingClosureLabelOutsideDecoration(block: oneLineDecorated))
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


    /// **F29 SEQUEL · the intersection two guards each had a reason to pass.**
    ///
    /// F17 cleared closure-label buttons on the finding that they *"fill inside
    /// the label, so the whole pill already carries taps"* — and encoded that
    /// as `isOffending`'s exoneration on ANY `.background(`. F29 then found
    /// that decoration attaching to the **Button** rather than its label leaves
    /// the tap region at the glyphs, and fixed it — but only for **String**
    /// labels, because that was the shape in front of it.
    ///
    /// Nobody covered **closure label + decoration outside the label**. It fell
    /// between the two: `isOffending` sees a fill and exonerates,
    /// `isOffendingStringLabelButton` sees no `Button("` and declines. The
    /// shipped `tourCard` in the Learn hub had this shape and both guards
    /// cleared it for as long as it has existed.
    ///
    /// Shape: `Button { … } label: { … }` where the closing `}` of the label is
    /// followed by a modifier chain carrying a fill or stroke, and neither the
    /// label nor the chain declares a `contentShape`.

    /// **A BOUNDED SLICE. Source scanners must not be able to trap.**
    ///
    /// A source-scanning guard walks every file under `Views/`, so its input is
    /// *whatever anyone writes*, not what any test constructs. A malformed
    /// index therefore does not misreport — it traps, and a trap kills the test
    /// HOST, taking every unrelated suite with it. On 2026-08-25 one such slice
    /// reported 199 failures across 110 suites for a single defect.
    ///
    /// Returns an empty array rather than trapping when the bounds are
    /// nonsensical. A scanner that sees nothing under-reports, which a
    /// self-test can catch; a scanner that traps takes down the run, which
    /// nothing can.
    static func slice(_ lines: [String], from lower: Int, through upper: Int) -> [String] {
        guard lower <= upper, lower >= 0, upper < lines.count else { return [] }
        return Array(lines[lower...upper])
    }

    static func isOffendingClosureLabelOutsideDecoration(block: String) -> Bool {
        let lines = block.components(separatedBy: "\n")
        guard let head = lines.first,
              head.range(of: #"\bButton\s*\{"#, options: .regularExpression) != nil
        else { return false }
        guard let labelIdx = lines.firstIndex(where: {
            $0.range(of: #"\}\s*label:\s*\{"#, options: .regularExpression) != nil
        }) else { return false }

        // **Find the label's close by BRACE DEPTH, not by the first line that
        // looks like a closing brace.** The naive version took the inner
        // `HStack`'s `}` as the label's end and then read the label's OWN
        // `.background`/`.overlay` as the Button's chain — convicting five
        // shipped views that decorate correctly inside their labels
        // (`EntryExpandedView`, `CreateMemoryFromClipsSheet`, `SessionListView`,
        // `ClipAtomView`, `ProjectDetailView`). That is the same over-report
        // F17 hit at 16→7 and F29 at 11→2, and the same remedy applies:
        // check the candidate, never trust the count.
        var depth = 0
        var closeIdx: Int? = nil
        for i in labelIdx..<lines.count {
            let line = lines[i]
            let openers = line.filter { $0 == "{" }.count
            let closers = line.filter { $0 == "}" }.count
            if i == labelIdx {
                // **Count only what follows `label: {` on this line.** The
                // one-line form `Button { act() } label: {` opens and closes
                // the ACTION closure before the label even begins, so counting
                // the whole line starts the depth two too high and the label
                // never appears to close — which convicted SearchView's "When"
                // chip of its enclosing HStack's fill, the same
                // container-attribution error the String-label scanner already
                // guards against.
                guard let r = line.range(of: #"label:\s*\{"#, options: .regularExpression)
                else { return false }
                let tail = line[r.upperBound...]
                depth = 1 + tail.filter { $0 == "{" }.count - tail.filter { $0 == "}" }.count
            } else {
                depth += openers - closers
            }
            if depth <= 0 { closeIdx = i; break }
        }
        guard let close = closeIdx, close + 1 < lines.count else { return false }

        // `close == labelIdx` when the label opens AND closes on one line —
        // `Button { a += 1 } label: { pill("A") }`. The body is then the tail of
        // that same line, and the old `(labelIdx + 1)...close` was inverted.
        let labelBody = close > labelIdx
            ? Self.slice(lines, from: labelIdx + 1, through: close).joined(separator: "\n")
            : String(lines[labelIdx][(lines[labelIdx].range(of: #"label:\s*\{"#, options: .regularExpression)?.upperBound ?? lines[labelIdx].startIndex)...])
        if labelBody.contains("contentShape") { return false }

        var chain = ""
        for line in lines[(close + 1)...] {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("//") { continue }
            guard t.hasPrefix(".") else { break }
            chain += t + "\n"
        }
        let decorated = chain.range(
            of: #"\.background\(|\.fill\(|\.stroke\(|\.strokeBorder\("#,
            options: .regularExpression
        ) != nil
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
                if isOffending(block: block)
                    || isOffendingStringLabelButton(block: block)
                    || isOffendingClosureLabelOutsideDecoration(block: block) {
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
