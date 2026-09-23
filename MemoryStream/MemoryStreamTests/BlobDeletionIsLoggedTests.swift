import Testing
import Foundation
@testable import HiMem

/// **Every deletion of a user's file must leave a line saying which file and
/// why.**
///
/// On 2026-09-22 roughly 190 audio files left the iCloud container and the
/// investigation could not name what removed them. The reason was not that
/// the log was lost — it was that `removeFromStore` logged **only** on its
/// refusal and coordination-failure branches. The successful delete, the one
/// that actually destroys a user's file, emitted nothing, and the export
/// emitted nothing at all.
///
/// So a grep across a seven-day device log returned zero lines about the only
/// operation that mattered, and **that silence was evidence of nothing** —
/// the same shape as the `[BinThumb]` misread in CLAUDE.md § A First Reading
/// of an Unfamiliar Log, where a log that fires on one branch was read as an
/// inventory of all of them.
///
/// These are source-level guards: the behaviour is a file-coordinator call
/// against a real ubiquity container, which no unit test can drive. What is
/// assertable — and what actually failed us — is structural.
@Suite struct BlobDeletionIsLoggedTests {

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

    // MARK: - The guards

    /// **THE LOAD-BEARING ASSERTION.** The success path must log. This is the
    /// branch that was silent, and its silence is what cost the investigation.
    @Test("the successful delete logs, not only the failures")
    func theSuccessPathLogs() throws {
        let src = try Self.source("Services/Storage/UbiquityStore.swift")
        let body = try Self.functionBody("func removeFromStore(", in: src)
        let logged = body.split(separator: "\n").filter { $0.contains("DeviceLog.blob(") }.count
        #expect(logged >= 3, """
            `removeFromStore` has \(logged) log site(s). It needs one on every \
            outcome — refused, failed, and SUCCEEDED. Logging only the failure \
            branches is what made ~190 deleted files unattributable.
            """)
        #expect(body.contains("delete OK") || body.contains("gone ?"),
                "the success branch must say so explicitly")
    }

    /// **`reason` has no default, and the compiler is the enforcement.** A
    /// caller that says nothing would produce a line naming a file and no
    /// cause, which is the log we already had.
    @Test("every caller must state why it is deleting")
    func reasonIsForcedOnEveryCaller() throws {
        let src = try Self.source("Services/Storage/UbiquityStore.swift")
        #expect(src.contains("func removeFromStore(reason: String, at url: URL)"),
                "the reason parameter is gone or reordered")
        #expect(!src.contains("reason: String = "),
                "`reason` acquired a default — a delete can now be unexplained again")

        let callers = try Self.filesCalling("removeFromStore(")
        #expect(!callers.isEmpty, "no callers found — the walk or the matcher is broken")
        for (path, line) in callers {
            #expect(line.contains("reason:"), "\(path) deletes a user file without saying why: \(line)")
        }
    }

    /// The export reads the whole media library. It must say so at both ends,
    /// so a future investigation can tell whether it ran at all.
    @Test("the export logs its start and its end")
    func theExportLogsBothEnds() throws {
        let src = try Self.source("Services/Storage/RecordingsExport.swift")
        #expect(src.contains("export START"), "the export must record that it began, and with what scope")
        #expect(src.contains("export END"), "the export must record what it actually did")
    }

    // MARK: - Self-tests

    @Test("the body reader takes the function, not the whole file")
    func bodyReaderIsScoped() throws {
        let src = """
        func other() {
            DeviceLog.blob("a")
        }
        func removeFromStore(reason: String, at url: URL) {
            DeviceLog.blob("b")
        }
        func after() { DeviceLog.blob("c") }
        """
        let body = try Self.functionBody("func removeFromStore(", in: src)
        #expect(body.contains("\"b\""))
        #expect(!body.contains("\"a\""))
        #expect(!body.contains("\"c\""))
    }

    @Test("the body reader fails loudly when the function is gone")
    func bodyReaderThrowsWhenAbsent() {
        #expect(throws: (any Error).self) {
            _ = try Self.functionBody("func removeFromStore(", in: "func somethingElse() {}")
        }
    }

    @Test("the caller matcher ignores the declaration and comments")
    func callerMatcherIgnoresDeclAndComments() {
        let hits = Self.callSites(in: [
            "A.swift": "// removeFromStore( in prose\nfoo.removeFromStore(reason: \"x\", at: u)",
            "B.swift": "    func removeFromStore(reason: String, at url: URL) {",
        ])
        #expect(hits.count == 1)
        #expect(hits.first?.0 == "A.swift")
    }

    @Test("the matcher survives degenerate input")
    func matcherSurvivesDegenerateInput() {
        #expect(Self.callSites(in: [:]).isEmpty)
        #expect(Self.callSites(in: ["a.swift": ""]).isEmpty)
        #expect(Self.callSites(in: ["a.swift": "removeFromStore"]).isEmpty)
    }

    // MARK: - Scanner

    /// Brace-balanced body extraction. Counts braces rather than slicing by
    /// offset, so there is no range to invert (CLAUDE.md § Guard the Caller,
    /// the 2026-08-25 trap).
    static func functionBody(_ signature: String, in source: String) throws -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        guard let start = lines.firstIndex(where: { $0.contains(signature) }) else {
            throw GateFailure.sourceNotFound(signature)
        }
        var depth = 0, started = false
        var body: [String] = []
        for line in lines[start...] {
            for ch in line where ch == "{" || ch == "}" {
                if ch == "{" { depth += 1; started = true } else { depth -= 1 }
            }
            body.append(String(line))
            if started && depth <= 0 { break }
        }
        return body.joined(separator: "\n")
    }

    static func callSites(in sources: [String: String]) -> [(String, String)] {
        var out: [(String, String)] = []
        for (path, text) in sources.sorted(by: { $0.key < $1.key }) {
            for line in text.split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard !t.hasPrefix("//"), t.contains("removeFromStore("),
                      !t.contains("func removeFromStore(") else { continue }
                out.append((path, t))
            }
        }
        return out
    }

    /// Walks the app target. Throws if it reaches no source — "no unguarded
    /// callers" and "zero files scanned" must not read the same.
    static func filesCalling(_ needle: String) throws -> [(String, String)] {
        guard let walker = FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil) else {
            throw GateFailure.sourceNotFound(appRoot.path)
        }
        var sources: [String: String] = [:]
        for case let url as URL in walker where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            sources[url.path.components(separatedBy: "/MemoryStream/MemoryStream/").last ?? url.path] = text
        }
        guard !sources.isEmpty else { throw GateFailure.noSourceWalked(appRoot.path) }
        return callSites(in: sources)
    }
}
