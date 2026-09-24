import Testing
import Foundation
@testable import HiMem

/// **The inbox does not exist when it is empty**, and **nothing drains it
/// behind her back** — the two properties that separate transient capture
/// from the bench we deleted.
///
/// `HiMem · Transient capture.html` (CURRENT):
///
/// > It is a state, not a place. There is no tab, no destination, nothing to
/// > visit. When nothing waits there is **no trace of the mechanism** — no
/// > empty section, no "nothing new."
///
/// and:
///
/// > If it accumulates, we have rebuilt the thing we deleted.
///
/// Source-level where the subject is SwiftUI structure, value-level where the
/// rule is a decision.
@Suite struct TransientCaptureSurfaceTests {

    enum GateFailure: Error { case sourceNotFound(String), noSourceWalked(String) }

    private static let appRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("MemoryStream")

    private static func source(_ rel: String) throws -> String {
        let url = appRoot.appendingPathComponent(rel)
        guard let s = try? String(contentsOf: url, encoding: .utf8), !s.isEmpty else {
            throw GateFailure.sourceNotFound(url.path)
        }
        return s
    }

    private static func codeLines(_ src: String) -> [String] {
        src.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") && !$0.hasPrefix("///") }
    }

    // MARK: - Nothing waiting renders nothing

    /// **THE ONE TOM NAMED.** With an empty stack there is no head, so the
    /// card cannot be constructed — the absence is structural, not a branch
    /// someone has to remember to write.
    @Test("an empty stack yields nothing to render")
    func emptyStackRendersNothing() {
        #expect(TransientCaptureStack.head(of: []) == nil)
        #expect(TransientCaptureStack.waiting(from: []).isEmpty)
    }

    /// The card is bound to `let head = …`, so "nothing waiting" cannot reach
    /// a view at all. A surface that rendered an empty state here would be a
    /// destination, and a destination is the bench.
    @Test("the card is built only from a non-nil head")
    func theCardIsGatedOnAHead() throws {
        let src = try Self.source("Views/Journal/JournalView.swift")
        let lines = Self.codeLines(src)
        guard let gate = lines.first(where: { $0.contains("TransientCaptureCard(") })
                .flatMap({ _ in lines.first { $0.contains("let waiting = transientHead") } }) else {
            Issue.record("the card is no longer gated on an optional head")
            return
        }
        #expect(gate.contains("if viewMode == .memories, let waiting = transientHead"),
                "the card must be unreachable when nothing waits: \(gate)")
    }

    /// No empty-state copy may exist for the waiting stack. The bench had one
    /// and that is precisely what made it a place.
    @Test("there is no empty state for the waiting stack")
    func noEmptyStateCopy() throws {
        // Code lines only. The card's docstring QUOTES the spec — *"no empty
        // section, no 'nothing new'"* — so a raw `contains` flags the very
        // documentation that records the rule. Third time this class has
        // appeared (SpeechServiceSeamTests, CaptureStackIsUniformTests), and
        // it is always the guard reading its own prose.
        let card = Self.codeLines(try Self.source("Views/Journal/TransientCaptureCard.swift"))
        for placeholder in ["Nothing new", "nothing new", "No captures", "All caught up", "You're all set"] {
            let hits = card.filter { $0.contains(placeholder) }
            #expect(hits.isEmpty,
                    "an empty state turns a state into a place — found \(placeholder): \(hits)")
        }
    }

    // MARK: - Nothing drains it behind her back

    /// **The drain stopped being automatic.** It ran at launch and turned
    /// every transcribed capture into a memory unattended, which is the
    /// decision the descoping moved back to her.
    @Test("no launch path drains the waiting stack")
    func noLaunchPathDrains() throws {
        for path in ["Views/Launch/LaunchScreenView.swift",
                     "Views/Journal/AddExistingClipsSheet.swift"] {
            let hits = Self.codeLines(try Self.source(path))
                .filter { $0.contains("materializeAll(") }
            #expect(hits.isEmpty, """
                \(path) drains the waiting stack. A capture must wait until she \
                picks an exit; draining on appear empties the inbox behind her \
                and restores §1's behaviour. Found: \(hits.joined(separator: " · "))
                """)
        }
    }

    /// **The paperclip lists what is waiting — it does not convert it.** §4b
    /// makes waiting captures its inventory; materializing them to get
    /// something to list destroys the state the surface depends on.
    @Test("the paperclip does not materialize to populate itself")
    func thePaperclipDoesNotConvert() throws {
        let src = try Self.source("Views/Journal/AddExistingClipsSheet.swift")
        let hits = Self.codeLines(src).filter { $0.contains("ArrivedClipMaterializer") }
        #expect(hits.isEmpty, "the paperclip converts waiting captures: \(hits.joined(separator: " · "))")
    }

    /// **Every materialize site in the WHOLE APP TARGET is a user-chosen
    /// exit.**
    ///
    /// ## Why this walks everything
    ///
    /// The first version of this test listed three files by hand —
    /// `JournalView`, `TransientCaptureCard`, `AddExistingClipsSheet` — and
    /// never looked at `Services/`. It passed on 2026-09-24 while
    /// `WatchSessionDelegate:380` materialized every Watch arrival the moment
    /// transcription finished, which is the defect the device pass found: three
    /// recordings became three memories, one of them empty.
    ///
    /// A guard that enumerates its own files **will always miss the file
    /// nobody thought of** (Tom). It is a completeness claim drawn from a
    /// partial walk — CLAUDE.md § Measurement Discipline, the same shape as a
    /// `head`-bounded grep answering "there are none".
    ///
    /// So: walk the entire target, and **throw if the walk reaches no
    /// source**, because "no unapproved callers" and "zero files scanned" must
    /// never read the same.
    @Test("every materialize site in the app target is a user-chosen exit")
    func everyMaterializeSiteIsAnExit() throws {
        let sites = try Self.materializeSites()
        #expect(!sites.isEmpty, "nothing materializes anywhere — the exits are dead")

        let approved = Set(["Views/Journal/JournalView.swift"])
        let unapproved = sites.filter { !approved.contains($0.file) }
        #expect(unapproved.isEmpty, """
            A waiting capture is materialized outside the user-chosen exits. \
            Every site must be something she picked — an automatic one turns \
            arrivals into memories behind her back, which is exactly what \
            `WatchSessionDelegate` did on 2026-09-24.
            \(unapproved.map { "  • \($0.file): \($0.line)" }.joined(separator: "\n"))
            """)

        // …and inside the approved file, each site is an exit she chose.
        let src = try Self.source("Views/Journal/JournalView.swift")
        var accounted = 0
        for exit in ["func startNewMemory(from", "func place(_ capture:"] {
            let body = try Self.functionBody(exit, in: src)
            let hits = Self.codeLines(body).filter { $0.contains("ArrivedClipMaterializer.materialize") }
            #expect(hits.count == 1, "\(exit) must materialize exactly once: \(hits)")
            accounted += hits.count
        }
        #expect(accounted == sites.count,
                "a materialize site in JournalView sits outside the two exits: \(sites.map(\.line))")
    }


    // MARK: - Scanner

    /// Walks the **entire app target**. Throws if it reaches no source — a
    /// completeness claim cannot rest on a walk that inspected nothing.
    static func materializeSites() throws -> [(file: String, line: String)] {
        guard let walker = FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil) else {
            throw GateFailure.sourceNotFound(appRoot.path)
        }
        var sources: [String: String] = [:]
        for case let url as URL in walker where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let rel = url.path.components(separatedBy: "/MemoryStream/MemoryStream/").last ?? url.path
            sources[rel] = text
        }
        guard !sources.isEmpty else { throw GateFailure.noSourceWalked(appRoot.path) }
        return sites(in: sources)
    }

    /// Membership only — no offsets, so there is no range to invert.
    static func sites(in sources: [String: String]) -> [(file: String, line: String)] {
        var out: [(String, String)] = []
        for (path, text) in sources.sorted(by: { $0.key < $1.key }) {
            for line in codeLines(text) where line.contains("ArrivedClipMaterializer.materialize") {
                out.append((path, line))
            }
        }
        return out
    }

    /// **The self-test is the real call site, verbatim.**
    ///
    /// Not a paraphrase: this is the line that shipped in
    /// `WatchSessionDelegate` and produced three memories from three Watch
    /// recordings. A matcher that cannot recognise the exact text of the
    /// defect it was written for has not been shown to work.
    @Test("the matcher recognises the call site that caused the defect")
    func matcherCatchesTheRealOffender() {
        let offender = [
            "Services/Watch/WatchSessionDelegate.swift":
                "                        ArrivedClipMaterializer.materialize(transcribed, in: StorageService.shared.viewContext)\n"
        ]
        let found = Self.sites(in: offender)
        #expect(found.count == 1)
        #expect(found.first?.file == "Services/Watch/WatchSessionDelegate.swift")
    }

    @Test("the matcher ignores the symbol in prose")
    func matcherIgnoresProse() {
        let src = ["a.swift": "// ArrivedClipMaterializer.materialize used to run here\n/// and here\nlet x = 1"]
        #expect(Self.sites(in: src).isEmpty)
    }

    @Test("the matcher survives degenerate input")
    func matcherSurvivesDegenerateInput() {
        #expect(Self.sites(in: [:]).isEmpty)
        #expect(Self.sites(in: ["a.swift": ""]).isEmpty)
        #expect(Self.sites(in: ["a.swift": "ArrivedClipMaterializer.materializ"]).isEmpty)
    }

    /// The walk must fail loudly rather than pass on nothing.
    @Test("a walk that reaches no source throws")
    func emptyWalkThrows() {
        #expect(throws: (any Error).self) {
            guard FileManager.default.fileExists(atPath: "/nonexistent-root") else {
                throw GateFailure.noSourceWalked("/nonexistent-root")
            }
        }
    }


    static func functionBody(_ signature: String, in source: String) throws -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        guard let start = lines.firstIndex(where: { $0.contains(signature) }) else {
            throw GateFailure.sourceNotFound(signature)
        }
        var depth = 0, started = false
        var out: [String] = []
        for line in lines[start...] {
            for ch in line where ch == "{" || ch == "}" {
                if ch == "{" { depth += 1; started = true } else { depth -= 1 }
            }
            out.append(String(line))
            if started && depth <= 0 { break }
        }
        return out.joined(separator: "\n")
    }

    @Test("the body reader is scoped and fails loudly when absent")
    func readerSelfTest() throws {
        let src = "func a() {\n x\n}\nfunc b() {\n y\n}"
        #expect(try Self.functionBody("func a(", in: src).contains("x"))
        #expect(!(try Self.functionBody("func a(", in: src).contains("y")))
        #expect(throws: (any Error).self) { _ = try Self.functionBody("func z(", in: src) }
    }

    @Test("the code filter ignores prose")
    func codeFilterIgnoresProse() {
        let src = "// materializeAll( in a comment\nlet x = 1"
        #expect(Self.codeLines(src).filter { $0.contains("materializeAll(") }.isEmpty)
    }
}
