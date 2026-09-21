import Testing
import Foundation
@testable import HiMem

/// **THE LOAD-BEARING GUARD for "Save a copy of your recordings".**
///
/// The export exists for one stated reason: *"Judi's recordings are a person's
/// memories rather than development fixtures"* (descoping ADR, ruled 2026-09-21).
/// Judi is on TestFlight. **TestFlight ships Release.**
///
/// Every other data tool in `SettingsView` — the orphan sweep, both fixture
/// seeders, the scans — lives inside `#if DEBUG`. So the gravity on this file
/// is entirely one way, and the failure it produces is the worst kind
/// available: behind `#if DEBUG` this row **builds, tests, demos and reviews
/// perfectly** while being structurally incapable of reaching the only library
/// it was written for. There is no error, no warning, and nothing on screen —
/// the section simply is not there in the build that matters, and the defect
/// surfaces as *"I never got my recordings"* after the audio is gone.
///
/// **This is not hypothetical.** The first draft of the feature put its four
/// `@State` properties one line under `showSweepAlert`, inside the `#if DEBUG`
/// block, purely because that is where the neighbouring state lived. Caught
/// before it compiled; this test is why it cannot come back.
///
/// Same idiom as `SpeechServiceSeamTests`: membership only — **no offsets and
/// no slicing**, so there is no range to invert (CLAUDE.md § Guard the Caller,
/// the 2026-08-25 trap) — with a walk that throws if it reaches no source.
@Suite struct RecordingsExportReleaseReachabilityTests {

    enum GateFailure: Error { case sourceNotFound(String) }

    private static let settings = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("MemoryStream/Views/Components/SettingsView.swift")

    private static func settingsSource() throws -> String {
        guard let s = try? String(contentsOf: settings, encoding: .utf8), !s.isEmpty else {
            throw GateFailure.sourceNotFound(settings.path)
        }
        return s
    }

    // MARK: - The guard

    @Test("the row ships in Release")
    func theRowIsOutsideDebug() throws {
        let src = try Self.settingsSource()
        #expect(Self.isOutsideDebug(#"Text("Save a copy of your recordings")"#, in: src), """
            The "Save a copy of your recordings" row is inside `#if DEBUG`, or gone. \
            TestFlight ships Release, so a DEBUG-only export cannot reach the library \
            it was built to preserve — and it fails silently, with nothing on screen.
            """)
    }

    @Test("the promise that nothing is destroyed ships with it")
    func theSubLineIsOutsideDebug() throws {
        let src = try Self.settingsSource()
        #expect(Self.isOutsideDebug(#"Nothing is removed from HiMem."#, in: src), """
            The sub-line is missing or DEBUG-only. It is the Let Go lesson applied: \
            a label naming something precious must leave zero doubt whether the thing \
            survives, and this sentence is where that doubt is answered.
            """)
    }

    @Test("the action that does the work ships in Release too")
    func theActionIsOutsideDebug() throws {
        let src = try Self.settingsSource()
        #expect(Self.isOutsideDebug("func saveACopyOfRecordings()", in: src))
        #expect(Self.isOutsideDebug("RecordingsExport.snapshot(", in: src),
                "the row must actually reach the exporter, not just render")
    }

    /// **The label is the contract, so it is pinned literally** — this is the
    /// case CLAUDE.md § Assert the Meaning names as the exception, where the
    /// wording *is* the promise. Tom, 2026-09-21: *"Not 'Export.' Export
    /// invites 'to where, and does it delete anything?'"*
    @Test("the label never becomes Export")
    func theLabelIsNotExport() throws {
        let src = try Self.settingsSource()
        #expect(!src.contains(#"Text("Export"#),
                "'Export' leaves open where it goes and whether the original survives — the July 28 lock")
        #expect(src.contains(#"Text("Save a copy of your recordings")"#))
        #expect(src.contains(#"Text("Your data")"#), "the section header Tom ruled")
    }

    // MARK: - Self-tests — the matcher must be able to fail, and survive junk

    @Test("the matcher catches a row hidden inside #if DEBUG")
    func flagsTheDebugOffender() {
        let src = """
        struct V {
            #if DEBUG
            Text("Save a copy of your recordings")
            #endif
        }
        """
        #expect(Self.isOutsideDebug(#"Text("Save a copy of your recordings")"#, in: src) == false)
    }

    @Test("the matcher accepts the shipping shape")
    func acceptsTheCleanShape() {
        let src = """
        struct V {
            Text("Save a copy of your recordings")
            #if DEBUG
            Text("Seed QA fixtures")
            #endif
        }
        """
        #expect(Self.isOutsideDebug(#"Text("Save a copy of your recordings")"#, in: src))
    }

    /// The near-miss that a naive depth counter gets wrong: DEBUG nested one
    /// level down inside another conditional still hides what it contains.
    @Test("the matcher sees through nested conditionals")
    func handlesNesting() {
        let src = """
        #if os(iOS)
        #if DEBUG
        Text("Save a copy of your recordings")
        #endif
        Text("visible")
        #endif
        """
        #expect(Self.isOutsideDebug(#"Text("Save a copy of your recordings")"#, in: src) == false)
        #expect(Self.isOutsideDebug(#"Text("visible")"#, in: src))
    }

    /// `#else` of a DEBUG branch is the *Release* side — code there does ship,
    /// and a matcher that treated the whole conditional as hidden would report
    /// a false alarm on a legitimate shape.
    @Test("the #else of a DEBUG branch is Release")
    func debugElseIsRelease() {
        let src = """
        #if DEBUG
        Text("dev only")
        #else
        Text("Save a copy of your recordings")
        #endif
        """
        #expect(Self.isOutsideDebug(#"Text("Save a copy of your recordings")"#, in: src))
    }

    /// **Prose about the row is not the row.** The source carries several
    /// comments naming this label — including the ones explaining why it must
    /// stay in Release — and a matcher that counted those would pass by reading
    /// its own documentation. Exactly the false positive `SpeechServiceSeamTests`
    /// hit on its first run.
    @Test("the matcher ignores the label in comments")
    func ignoresComments() {
        let src = """
        #if DEBUG
        // Text("Save a copy of your recordings") must not live here
        /// nor here: Text("Save a copy of your recordings")
        #endif
        """
        #expect(Self.isOutsideDebug(#"Text("Save a copy of your recordings")"#, in: src) == false)
    }

    /// **A scanner's input is not what any test constructs — it is whatever
    /// anyone writes next.** A malformed directive must return an answer, not
    /// take down the test host (CLAUDE.md § Guard the Caller, 2026-08-25:
    /// three self-tests covered offender / fix / near-miss and the fourth
    /// shape killed 110 suites).
    @Test("the matcher survives degenerate input")
    func survivesDegenerateInput() {
        #expect(Self.isOutsideDebug("x", in: "") == false)
        #expect(Self.isOutsideDebug("x", in: "#endif\n#endif\nx") )          // unbalanced #endif
        #expect(Self.isOutsideDebug("x", in: "#if DEBUG\nx") == false)        // never closed
        #expect(Self.isOutsideDebug("x", in: "#else\nx"))                     // orphan #else
        // Empty needle: `String.contains("")` is `false` in Swift, so this
        // answers "no" rather than "everything matches". Pinned because the
        // first draft of this test asserted the opposite and the mutation run
        // caught it — a degenerate query has no meaningful answer, and the
        // property that matters is that it returns one instead of trapping.
        #expect(Self.isOutsideDebug("", in: "anything") == false)
    }

    // MARK: - Scanner

    /// True when `needle` appears in code that a **Release** build compiles.
    ///
    /// Membership only. Tracks `#if` nesting depth and remembers the depth at
    /// which a `DEBUG` branch opened; anything read while that branch is open
    /// is Release-invisible. Comment lines are skipped — see `ignoresComments`.
    /// An unbalanced directive clamps rather than traps.
    static func isOutsideDebug(_ needle: String, in source: String) -> Bool {
        var depth = 0
        var debugAt: Int?
        for raw in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#if") {
                depth += 1
                if debugAt == nil && t.contains("DEBUG") { debugAt = depth }
            } else if t.hasPrefix("#endif") {
                if debugAt == depth { debugAt = nil }
                depth = max(0, depth - 1)
            } else if t.hasPrefix("#else") || t.hasPrefix("#elseif") {
                if debugAt == depth { debugAt = nil }
            } else if debugAt == nil, !t.hasPrefix("//"), t.contains(needle) {
                return true
            }
        }
        return false
    }
}
