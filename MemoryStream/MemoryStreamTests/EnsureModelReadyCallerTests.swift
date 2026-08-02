import Testing
import Foundation
@testable import HiMem

/// F23 · B10 — **`ensureModelReady` now throws; every caller must handle it
/// where it is called.**
///
/// The method used to return normally on three paths where the model was not
/// ready: an unsupported locale, a `.supported` status yielding no
/// installation request, and an unknown status. It reported success while the
/// model could never be ready — against its own doc claiming it "throws on
/// download failure".
///
/// Making it throw is only safe because both call sites absorb the throw *at
/// the call*. That is the load-bearing part, so it is what this guard pins —
/// per CLAUDE.md §"Guard the Caller, Not Just the Owner": testing that
/// `ensureModelReady` throws correctly says nothing about whether a caller
/// still works.
///
/// **Why "at the call" and not merely "inside some do/catch".**
/// `SpeechService.prepareAnalyzerIfNeeded` builds the live analyzer inside one
/// large `do` block. A bare `try` there would technically be "handled" — by an
/// outer `catch` that abandons the whole setup, leaving
/// `analyzer`/`transcriber`/`bestFormat` unset and live capture unconfigured
/// on exactly the systems where the locale's asset is unsupported. Capture is
/// the product's reason to exist; that regression must be impossible to
/// reintroduce by accident. So the catch must sit within a few lines of the
/// call, which is what a dedicated wrapper looks like and what an accidental
/// bare `try` does not.
@Suite
struct EnsureModelReadyCallerTests {

    /// THE GATE.
    @Test func everyCallerAbsorbsTheThrowAtTheCallSite() throws {
        let bare = try Self.bareCallSites()
        #expect(
            bare.isEmpty,
            """
            `ensureModelReady` is called without handling its throw at the call \
            site: \(bare.map { "\($0.file):\($0.line)" }.joined(separator: ", ")).

            If this is `SpeechService`, the consequence is concrete: the throw \
            unwinds the analyzer-setup `do` block, `prepareToAnalyze` never \
            runs, and live capture is never configured on systems whose locale \
            asset is unsupported — silently, because the outer catch just logs.

            Either wrap the call in its own do/catch (stating why proceeding is \
            correct) or use `try?` deliberately.
            """
        )
    }

    /// Non-vacuity: there are call sites to guard. Without this the gate
    /// passes trivially the moment the method is renamed or the walk breaks.
    @Test func thereAreCallersToGuard() throws {
        let all = try Self.allCallSites()
        #expect(all.count >= 2,
                "expected the pre-warm and the live-analyzer callers; found \(all.count)")
        let files = Set(all.map(\.file))
        #expect(files.contains("MemoryStreamApp.swift"))
        #expect(files.contains("SpeechService.swift"))
    }

    /// Guards the guard: the matcher must see a bare call and clear a handled
    /// one — including the trap case, a bare `try` sitting inside a large
    /// outer `do` whose `catch` is far below.
    @Test func theScannerCanSeeABareCall() {
        let wrapped = """
            do {
                try await TranscriptionService.shared.ensureModelReady(for: locale)
            } catch {
                NSLog("continuing")
            }
            """
        #expect(Self.bareCalls(in: wrapped, file: "X.swift").isEmpty)

        let tryOptional = """
            try? await TranscriptionService.shared.ensureModelReady(for: locale)
            """
        #expect(Self.bareCalls(in: tryOptional, file: "X.swift").isEmpty,
                "an explicit `try?` is a deliberate discard, not an oversight")

        let bare = """
            do {
                let transcriber = SpeechTranscriber(locale: locale)
                try await TranscriptionService.shared.ensureModelReady(for: locale)
                let bestFormat = await SpeechAnalyzer.bestAvailableAudioFormat()
                try await analyzer.prepareToAnalyze(in: bestFormat)
                self.analyzer = analyzer
                self.bestFormat = bestFormat
                startConsumer()
            } catch {
                NSLog("setup failed")
            }
            """
        #expect(Self.bareCalls(in: bare, file: "X.swift").count == 1,
                "the trap: handled by a distant outer catch that abandons the setup")
    }

    struct Site: Equatable { let file: String; let line: Int }

    /// A call is "bare" when it neither uses `try?` nor has a `catch` within a
    /// few lines below — i.e. nothing absorbs the throw *here*.
    static func bareCalls(in source: String, file: String) -> [Site] {
        let lines = source.components(separatedBy: "\n")
        var out: [Site] = []
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.hasPrefix("//"), !t.hasPrefix("///") else { continue }
            guard t.contains("ensureModelReady(for:") else { continue }
            if t.contains("try?") { continue }
            let window = lines[i..<min(i + 4, lines.count)].joined(separator: "\n")
            if !window.contains("catch") { out.append(Site(file: file, line: i + 1)) }
        }
        return out
    }

    static func allCallSites() throws -> [Site] { try scan(bareOnly: false) }
    static func bareCallSites() throws -> [Site] { try scan(bareOnly: true) }

    private static func scan(bareOnly: Bool) throws -> [Site] {
        var out: [Site] = []
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MemoryStream")
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { throw Failure.rootNotFound(root.path) }
        var sawAnySwift = false
        for case let url as URL in walker where url.pathExtension == "swift" {
            sawAnySwift = true
            // The declaration itself is not a call site.
            guard url.lastPathComponent != "TranscriptionService.swift" else { continue }
            guard let src = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let file = url.lastPathComponent
            if bareOnly {
                out += bareCalls(in: src, file: file)
            } else {
                for (i, line) in src.components(separatedBy: "\n").enumerated() {
                    let t = line.trimmingCharacters(in: .whitespaces)
                    guard !t.hasPrefix("//"), !t.hasPrefix("///") else { continue }
                    if t.contains("ensureModelReady(for:") { out.append(Site(file: file, line: i + 1)) }
                }
            }
        }
        // Never conclude "no bare callers" from a walk that read nothing.
        guard sawAnySwift else { throw Failure.walkFoundNoSource(root.path) }
        return out
    }

    enum Failure: Error { case rootNotFound(String), walkFoundNoSource(String) }
}
