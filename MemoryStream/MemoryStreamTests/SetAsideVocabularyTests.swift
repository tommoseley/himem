import Testing
import Foundation
@testable import HiMem

/// **F43's set-aside vocabulary, guarded at the owner instead of swept twice.**
///
/// F43 (2026-08-02) retired *"Not in this memory"* — memory-detail vocabulary
/// on a bench cluster where no memory exists, and "this memory" implies a
/// container the user has not decided to create. The visible label moved to
/// **"Set aside"**. Its **accessibility labels did not**: ref-backed rows said
/// "Set aside"/"Put back" while manifest-backed rows still said *"Set aside
/// from this memory"* / *"Add back to this memory"*, so VoiceOver users were
/// the only ones still being told about a memory that does not exist. Found
/// 2026-08-18 while answering "what does set aside mean".
///
/// **An accessibility label is user-facing copy.** The ruling was about the
/// vocabulary, not about which layer carries it.
///
/// This is the `.measurement` shape: an invariant applied at one site and left
/// as a literal at its twin. The fix is one owner (`ClusterCardCopy`) plus this
/// guard — a third hand-sweep is the rule that already failed twice.
///
/// **Pinned literals, deliberately** (*Assert the Meaning, Not the Phrasing*):
/// the retired term is the subject of the rule, so a failure here reads as
/// *"the retired vocabulary came back"*, not *"someone reworded a label"*.
struct SetAsideVocabularyTests {

    @Test
    func neitherSetAsideLabelSpeaksOfAMemory() {
        for label in [ClusterCardCopy.setAside, ClusterCardCopy.putBack] {
            #expect(
                !label.lowercased().contains("memory"),
                "A bench cluster is not a memory — \"\(label)\" reintroduces the container noun F43 retired"
            )
        }
    }

    @Test
    func theRetiredWordingIsGone() {
        #expect(ClusterCardCopy.setAside == "Set aside")
        #expect(ClusterCardCopy.putBack == "Put back")
        #expect(ClusterCardCopy.setAside != "Not in this memory")
        #expect(ClusterCardCopy.putBack != "Add back to this memory")
    }

    /// **The guard that matters: every set-aside label in the view must come
    /// from the owner.** Asserting the two constants alone would have passed
    /// for the whole six months the second site was wrong — the constants were
    /// always right; the call site simply didn't use them. Guard the caller,
    /// not just the owner.
    ///
    /// It scans the real file and **throws if it reaches no source**, so it can
    /// never pass by matching nothing.
    @Test
    func noSetAsideLabelIsWrittenAsALiteralAtTheCallSite() throws {
        let source = try Self.clusterCardSource()
        #expect(source.contains("ClusterCardCopy.setAside"), "self-test: the scanner is reading the right file")

        // Line-by-line, skipping comments. The first version of this guard
        // split the file on "/// " and compared counts — but each chunk runs
        // from one doc marker to the NEXT, so it contained the code as well as
        // the prose, and the exclusion count rose with the very literal it was
        // meant to exclude. **A mutation restoring the retired label passed it.**
        // Recorded because the matcher, not the rule, was the defect.
        let codeLines = source
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }

        // Self-test: the filter must not have eaten the code it is meant to
        // inspect. A scanner left with nothing reports a clean sweep forever.
        #expect(
            codeLines.contains(where: { $0.contains("accessibilityLabel") }),
            "self-test: comment-stripping removed the call sites this guard exists to read"
        )

        for retired in ["Set aside from this memory", "Add back to this memory", "Not in this memory"] {
            let offenders = codeLines.filter { $0.contains(retired) }
            #expect(
                offenders.isEmpty,
                "\"\(retired)\" is live code, not prose — F43 retired it and \(offenders.count) call site(s) still speak it"
            )
        }
    }

    private static func clusterCardSource() throws -> String {
        // Walk up from this test file to the repo, then to the view. Throwing
        // when the walk finds nothing is the point: a guard that silently
        // matches an empty string reports a clean sweep forever.
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir
                .appendingPathComponent("MemoryStream/Views/Inbox/ClusterCardStack.swift")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            dir = dir.deletingLastPathComponent()
        }
        throw SourceNotFound()
    }

    private struct SourceNotFound: Error, CustomStringConvertible {
        var description: String {
            "ClusterCardStack.swift was not found — this guard proves nothing when it cannot read the source, so it fails rather than passing vacuously"
        }
    }
}
