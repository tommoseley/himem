import Testing
import Foundation
@testable import HiMem

/// F23 · T2.1 — **which strictness the pipeline actually passes.**
///
/// `TruthReconcilerTests` has 32 assertions proving the *library's* `.strict`
/// and `.relaxed` modes behave as specified. Nothing asserted **which mode the
/// callers ask for.** That gap is exactly why three doc headers could claim
/// `.strict` grounding on-device for a week after the pipeline stopped passing
/// it — the owner was tested, the caller's use of it wasn't. Same shape as
/// `WatchTransferAudioTranscoderTests` (audit Class 4 #2).
///
/// So this suite pins the wiring, in **both** directions, so neither the code
/// nor the prose can drift alone:
///
/// 1. The organize pipeline grounds summary and title at `.relaxed` on both
///    tiers. Strict exact-substring was removed 2026-07-24 because it flagged
///    legitimate name expansions ("Abraham Lincoln" where the clips say
///    "Lincoln") and discarded the whole summary for a bare-quote extractive.
/// 2. The ungrounded-**mention** drop is the real per-tier difference, gated on
///    `strictness == .strict`.
/// 3. `ProjectAssistViewModel.deriveShortSummary` grounds at `.strict`, and
///    that is correct — its source is the long summary itself, so exact
///    substring is the right test and expansion cannot arise. Pinned so nobody
///    "unifies" it toward relaxed on the strength of rule 1.
/// 4. The two modes genuinely differ. Without this, rules 1–3 could all hold
///    vacuously if someone collapsed `.strict` into `.relaxed`.
@Suite
struct GroundingStrictnessWiringTests {

    // MARK: - 1 · The organize pipeline grounds relaxed, both tiers

    @Test func organizePipelineGroundsSummaryAndTitleRelaxed() throws {
        let calls = try Self.groundingCalls(in: "ProcessingEngine.swift")
        #expect(!calls.isEmpty, "no grounding calls found — the scanner or the file moved")
        let strict = calls.filter { $0.strictness == ".strict" }
        #expect(
            strict.isEmpty,
            """
            `ProcessingEngine` grounds summary/title at `.strict` at line(s) \
            \(strict.map { String($0.line) }.joined(separator: ", ")).

            Strict exact-substring was removed on 2026-07-24: it flagged the \
            model expanding "Lincoln" (in the clips) to "Abraham Lincoln" and \
            threw away the whole summary for a bare-quote extractive. \
            `TruthReconcilerTests.relaxedGrounding_allowsParaphraseOfInSourceName` \
            pins that behaviour. If this is a deliberate reversal it needs a \
            ruling, not a parameter change.
            """
        )
    }

    // MARK: - 2 · The mention drop is the real per-tier difference

    @Test func theMentionDropIsGatedOnStrict() throws {
        let src = try Self.source("ProcessingEngine.swift")
        #expect(
            src.contains("guard strictness == .strict else { return reconciled }"),
            """
            The ungrounded-mention drop is no longer gated on `.strict`. That \
            gate IS the per-tier difference the docs describe — on-device gets \
            the palette-bleed guard, the frontier does not. If it is gone, the \
            tier line the Honest-Label argument rests on is gone with it.
            """
        )
    }

    // MARK: - 3 · Project Assist's strict grounding is deliberate

    @Test func projectAssistShortSummaryStaysStrict() throws {
        let calls = try Self.groundingCalls(in: "ProjectAssistViewModel.swift")
        #expect(
            calls.contains { $0.strictness == ".strict" },
            """
            `deriveShortSummary` no longer grounds at `.strict`. This one is \
            correct as strict and must not be relaxed to match the organize \
            pipeline: its source text is the LONG summary itself, so exact \
            substring is the right test — the short summary may add nothing \
            the long doesn't already say, and there is no paraphrase-expansion \
            case to accommodate.
            """
        )
    }

    // MARK: - 4 · The modes are not the same mode

    /// Non-vacuity. If `.strict` and `.relaxed` ever behaved identically, every
    /// assertion above would still pass while meaning nothing.
    @Test func strictAndRelaxedGenuinelyDiffer() {
        let clips = "Reading Lincoln tonight — the second inaugural still lands."
        let expansion = "Abraham Lincoln"
        #expect(!TruthReconciler.isGrounded(expansion, in: clips, strictness: .strict),
                "strict rejects the expansion — that is what made it unusable in the pipeline")
        #expect(TruthReconciler.isGrounded(expansion, in: clips, strictness: .relaxed),
                "relaxed grounds it via the shared distinctive token")
        #expect(!TruthReconciler.isGrounded("Frederick Douglass", in: clips, strictness: .relaxed),
                "relaxed is not a no-op: a name sharing no token still fails")
    }

    // MARK: - Scanner

    struct GroundingCall { let line: Int; let strictness: String }

    /// `violates(` / `titleViolates(` call sites and the strictness each asks
    /// for. Deliberately does NOT include `isGrounded(` — that is the mention
    /// drop's primitive, covered by test 2.
    static func groundingCalls(in filename: String) throws -> [GroundingCall] {
        let src = try source(filename)
        var out: [GroundingCall] = []
        for (i, line) in src.components(separatedBy: "\n").enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.hasPrefix("//"), !t.hasPrefix("///") else { continue }
            guard t.contains("TruthReconciler.violates(") || t.contains("TruthReconciler.titleViolates(")
            else { continue }
            let mode = t.contains("strictness: .strict") ? ".strict"
                     : t.contains("strictness: .relaxed") ? ".relaxed" : "unknown"
            out.append(GroundingCall(line: i + 1, strictness: mode))
        }
        return out
    }

    /// Guards the guard: the matcher must be able to read a strictness off a
    /// call, and must ignore prose and declarations.
    @Test func theScannerCanReadAStrictnessOffACall() throws {
        // Exercised against the real files rather than synthetic strings, so a
        // rename breaks this rather than passing on a fabricated sample.
        let engine = try Self.groundingCalls(in: "ProcessingEngine.swift")
        #expect(engine.count >= 4, "the engine has four summary/title gate calls plus the append path")
        #expect(engine.allSatisfy { $0.strictness != "unknown" },
                "every call must state its strictness explicitly — an inferred default is how this drifted")
    }

    static func source(_ filename: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MemoryStream")
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { throw Failure.rootNotFound(root.path) }
        var sawAnySwift = false
        for case let url as URL in walker where url.pathExtension == "swift" {
            sawAnySwift = true
            guard url.lastPathComponent == filename else { continue }
            guard let src = try? String(contentsOf: url, encoding: .utf8), !src.isEmpty else { continue }
            return src
        }
        // The `fcb378b` pattern: never conclude from a walk that read nothing.
        throw sawAnySwift ? Failure.fileNotFound(filename) : Failure.walkFoundNoSource(root.path)
    }

    enum Failure: Error {
        case rootNotFound(String), walkFoundNoSource(String), fileNotFound(String)
    }
}
