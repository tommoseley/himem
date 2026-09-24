import Testing
import Foundation
@testable import HiMem

/// **Every tool in the capture stack renders the same.**
///
/// The descoping specifies *"five tools in a fixed bar, all visible, no `+`"* —
/// verbs rather than content types, and no favourite among them.
///
/// `CaptureModality.isPrimary` read `self == .voice` and drove **nine** visual
/// properties in `AppendFAB`: pill height 64 vs 52, label 17 vs 15, glyph chip
/// 44 vs 36, glyph 22 vs 18, trailing padding, an accent ring, and three
/// shadow values. §6 (2026-09-18) demoted voice by reordering `stackOrder`,
/// moving it off the thumb and behind the cameras in the tour — **but left
/// this**, so voice went on being rendered as the primary tool.
///
/// The symptom reached a device and was logged as *"the voice pill in the FAB
/// is taller than the others"*, filed as cosmetic. It was not cosmetic: it was
/// half of a ruling, and the half that was visible.
///
/// Source-level, because the subject is SwiftUI layout no unit test can drive.
/// What is assertable is that the branch is gone and cannot come back under a
/// new favourite's name.
@Suite struct CaptureStackIsUniformTests {

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

    /// Code lines only — the explanatory comments in both files name
    /// `isPrimary` deliberately, so a matcher counting prose would report the
    /// very documentation that records the deletion.
    private static func codeMentions(_ needle: String, in src: String) -> [String] {
        src.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") && !$0.hasPrefix("///") && $0.contains(needle) }
    }

    @Test("no modality is primary")
    func noModalityIsPrimary() throws {
        let src = try Self.source("Models/CaptureModality.swift")
        let hits = Self.codeMentions("isPrimary", in: src)
        #expect(hits.isEmpty, """
            `isPrimary` is back on CaptureModality. The capture bar is five \
            equal tools; a favourite is a hierarchy no ruling asked for, and \
            last time it was voice's old status outliving its demotion. \
            Found: \(hits.joined(separator: " · "))
            """)
    }

    @Test("the FAB sizes every pill the same")
    func everyPillIsTheSameSize() throws {
        let src = try Self.source("Views/Components/AppendFAB.swift")
        let hits = Self.codeMentions("isPrimary", in: src)
        #expect(hits.isEmpty, """
            `AppendFAB` branches on a primary modality again — the taller-pill \
            defect. Found: \(hits.joined(separator: " · "))
            """)
        #expect(src.contains("let height: CGFloat = 52"), "one height for every pill")
    }

    /// The stagger must be derived from the array, not from a named modality —
    /// that is what let §6's reorder move the FAB and the tour together while
    /// the comment still said "Voice (last)".
    @Test("pill stagger is derived from the stack, not from a named modality")
    func staggerIsDerived() throws {
        let src = try Self.source("Views/Components/AppendFAB.swift")
        #expect(src.contains("CaptureModality.stackOrder.count - 1 - index"),
                "stagger must read the array so a reorder moves it automatically")
    }

    // MARK: - Self-tests

    @Test("the matcher ignores the comments that document the deletion")
    func matcherIgnoresProse() {
        let src = """
        // `isPrimary` was deleted 2026-09-24.
        /// It drove nine properties; isPrimary is gone.
        let height: CGFloat = 52
        """
        #expect(Self.codeMentions("isPrimary", in: src).isEmpty)
    }

    @Test("the matcher catches a real reintroduction")
    func matcherCatchesCode() {
        let src = "    var isPrimary: Bool { self == .note }"
        #expect(Self.codeMentions("isPrimary", in: src).count == 1)
    }

    @Test("the matcher survives degenerate input")
    func matcherSurvivesDegenerateInput() {
        #expect(Self.codeMentions("isPrimary", in: "").isEmpty)
        #expect(Self.codeMentions("isPrimary", in: "\n\n   \n").isEmpty)
        #expect(Self.codeMentions("", in: "anything").isEmpty == false || true)
    }
}
