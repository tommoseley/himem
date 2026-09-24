import Testing
import Foundation
@testable import HiMem

/// **A sheet paints its own ground, and a field is not the colour of the page
/// it sits on.**
///
/// `NewProjectSheet` had neither: no background at all, so it borrowed the
/// system sheet colour in both modes while every control inside used Crucible
/// tokens — and its two fields were filled with `paper`, *the page colour*, so
/// a field was the same shade as what it sat on and only a hairline separated
/// them.
///
/// That is the token contract's *"judge a surface against its own column"*
/// missed on one screen. It was logged as "the New Project sheet needs design
/// work" during the 2026-09-20 device pass; it needed no design, only the
/// house shape `EditTextSheet` already uses: **page `paper`, fields `card`.**
///
/// Source-level, because SwiftUI colour resolution is not reachable from a
/// unit test. What is assertable is that the surface names a ground at all —
/// which is the part that was missing.
@Suite struct SheetPaintsItsOwnGroundTests {

    enum GateFailure: Error { case sourceNotFound(String) }

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

    @Test("the New Project sheet paints a Crucible ground")
    func theSheetPaintsItsGround() throws {
        let src = try Self.source("Views/Projects/ProjectListView.swift")
        #expect(src.contains("Crucible.Color.paper.ignoresSafeArea()"), """
            `NewProjectSheet` names no ground, so it borrows the system sheet \
            colour while its contents use Crucible tokens — the surface and \
            what is on it are then judged against different columns.
            """)
    }

    /// A field filled with the page colour is invisible but for its hairline.
    /// The raised colour is `card`, as `EditTextSheet` already does.
    @Test("its fields are raised off the page, not flush with it")
    func fieldsAreRaised() throws {
        let src = try Self.source("Views/Projects/ProjectListView.swift")
        let sheet = try Self.body(after: "private struct NewProjectSheet: View {", in: src)
        #expect(sheet.contains(".background(Crucible.Color.card)"),
                "the fields must sit on the raised colour")
        #expect(!sheet.contains(".padding(12)\n                    .background(Crucible.Color.paper)"),
                "a field filled with the page colour reads as a hairline outline, not a field")
    }

    // MARK: - Scanner

    /// Brace-balanced, so there is no offset slice to invert.
    static func body(after signature: String, in source: String) throws -> String {
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
    func readerIsScoped() throws {
        let src = "struct A: View {\n  let x = 1\n}\nstruct B: View {\n  let y = 2\n}"
        let a = try Self.body(after: "struct A: View {", in: src)
        #expect(a.contains("let x"))
        #expect(!a.contains("let y"))
        #expect(throws: (any Error).self) { _ = try Self.body(after: "struct Z: View {", in: src) }
    }
}
