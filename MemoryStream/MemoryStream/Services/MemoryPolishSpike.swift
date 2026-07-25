#if DEBUG
import Foundation
import CoreData
import FoundationModels

/// Device-only spike harness for **Memory Polish §3 (auto-correct)**. NOT a
/// shipped feature — `#if DEBUG`, triggered from Settings → Debug. Runs the
/// *constrained* on-device ASR-repair pass over a natural sample of real
/// library clips and logs, per `docs/design/Memory Polish · spec.md`:
///   - before → after (only for clips it changed),
///   - a word-level diff, and
///   - a consolidated **proper-noun ledger** (every proper noun the pass
///     touched, before→after) — the over-correction / Lincoln-in-miniature risk.
///
/// v2 (2026-07-25), fixing three harness bugs the first run exposed:
///  1. **Format** — uses `@Generable` guided generation so the runtime shapes
///     the response; v1's plain-text prompt made the model hand-format a JSON
///     string and leak `{"corrected_transcript": …}` / ```` ```json ```` fences
///     INTO the transcript. That would have written braces into a user's words.
///  2. **Scope** — the prompt now forbids ALL punctuation / sentence-boundary /
///     grammar changes (v1 did "alcohol."→"alcohol?", "trip. And"→"trip, and").
///     Word-level substitutions and obviously-dropped words only.
///  3. **Honest categorization** — v1 counted a clean clip's *decline to change*
///     as a failure ("Session ended…"). Outcomes are now split into
///     **changed / unchanged (nothing to fix) / errored**, and char length is
///     logged so the "short + already-clean → no-op" hypothesis is checkable.
///
/// Governance note (spec §2): `TruthReconciler` cannot gate this — the clip text
/// itself is what changes — so this output is a human quality read that gates
/// the tier. No UI, no tier lock: the spike reports first.
enum MemoryPolishSpike {

    /// Word-level, repair-only instructions (spec §2 governing line; scope
    /// tightened after run 1). Punctuation/sentence structure is off-limits.
    static let instructions = """
    You correct clear speech-to-text errors in a voice-clip transcript so the words match what the person actually said. Work at the WORD level only.

    Rules:
    - Replace only words the transcriber clearly got wrong — misheard words, wrong homophones — with the word actually spoken. You may also restore a word the transcriber obviously dropped (a missing "it", "the", etc.) when the intended phrase is unambiguous.
    - Do NOT change punctuation, capitalization, spacing, or sentence boundaries — leave them exactly as given. Never turn a statement into a question, never merge or split sentences, never "clean up" grammar or wording.
    - Correct a name or proper noun only when the intended word is obvious from context; never invent one. When unsure about any word, leave it exactly as written — say less before saying false.
    - If nothing is clearly wrong, return the transcript unchanged.
    """

    /// Guided-generation schema. The runtime fills `transcript` — the model
    /// never hand-formats a wrapper, so no envelope can leak into the text.
    @Generable
    struct Corrected {
        @Guide(description: "The transcript with only clear word-level transcription errors fixed, and punctuation, capitalization, and sentence boundaries left exactly as in the input. Identical to the input when nothing is clearly wrong.")
        var transcript: String
    }

    enum Outcome {
        case changed(String)
        case unchanged
        case errored(String)
    }

    struct ClipResult {
        let id: UUID
        let createdAt: Date
        let chars: Int
        let before: String
        let outcome: Outcome
    }

    /// Fetch a NATURAL sample of ~count real voice transcripts spread across the
    /// whole library (recent + older), run the repair, log everything.
    @MainActor
    static func run(count: Int = 8) async {
        NSLog("[PolishSpike] ===== Memory Polish §3 auto-correct spike (v2 · @Generable) =====")
        if let err = OnDeviceOrganizer.availabilityError() {
            NSLog("[PolishSpike] Foundation Models unavailable: \(err). Run on a device with Apple Intelligence enabled.")
            return
        }
        let ctx = StorageService.shared.viewContext
        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        req.predicate = NSPredicate(format: "mediaType == %@ AND recycledAt == nil",
                                    MediaReference.MediaType.voice.rawValue)
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let all = ((try? ctx.fetch(req)) ?? []).filter {
            !(($0.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        guard !all.isEmpty else { NSLog("[PolishSpike] No voice transcripts found in the store."); return }
        let sample = spread(all, count: count)
        NSLog("[PolishSpike] Sampling \(sample.count) of \(all.count) voice clips, spread newest→oldest.")

        var results: [ClipResult] = []
        for (i, ref) in sample.enumerated() {
            let before = (ref.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            NSLog("[PolishSpike] repairing \(i + 1)/\(sample.count) (\(before.count) chars)…")
            let outcome = await repair(before)
            results.append(ClipResult(id: ref.id, createdAt: ref.createdAt ?? .distantPast,
                                      chars: before.count, before: before, outcome: outcome))
        }
        report(results)
    }

    private static func spread(_ all: [MediaReference], count: Int) -> [MediaReference] {
        guard all.count > count else { return all }
        let step = Double(all.count) / Double(count)
        return (0..<count).map { all[min(all.count - 1, Int(Double($0) * step))] }
    }

    private static func repair(_ input: String) async -> Outcome {
        let session = LanguageModelSession(instructions: instructions)
        let prompt = "Transcript:\n\(input)\n\nReturn the corrected transcript, or the same transcript unchanged if nothing is clearly wrong."
        do {
            let response = try await session.respond(to: prompt, generating: Corrected.self, options: GenerationOptions())
            let out = response.content.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            return out == input ? .unchanged : .changed(out)
        } catch {
            return .errored(String(describing: error))
        }
    }

    // MARK: - Report

    private static func report(_ results: [ClipResult]) {
        var properNounLedger: [(before: String, after: String, clip: UUID)] = []
        var changed = 0, unchanged = 0, errored = 0

        for r in results {
            switch r.outcome {
            case .unchanged:
                unchanged += 1
                NSLog("[PolishSpike] ---- clip \(r.id) · \(r.chars) chars · UNCHANGED (nothing to fix) ----")
            case .errored(let msg):
                errored += 1
                NSLog("[PolishSpike] ---- clip \(r.id) · \(r.chars) chars · ERRORED: \(msg) ----")
            case .changed(let after):
                changed += 1
                NSLog("[PolishSpike] ---- clip \(r.id) · \(r.chars)→\(after.count) chars · CHANGED ----")
                NSLog("[PolishSpike] BEFORE: \(r.before)")
                NSLog("[PolishSpike] AFTER : \(after)")
                let blocks = wordChangeBlocks(before: r.before, after: after)
                if blocks.isEmpty { NSLog("[PolishSpike] DIFF: (whitespace/punctuation only — no word blocks)") }
                for (rem, add) in blocks {
                    NSLog("[PolishSpike] DIFF: \"\(rem)\" → \"\(add)\"")
                    if isProperNounish(rem) || isProperNounish(add) {
                        properNounLedger.append((rem, add, r.id))
                    }
                }
            }
        }

        NSLog("[PolishSpike] ===== PROPER-NOUN LEDGER (over-correction watch) =====")
        if properNounLedger.isEmpty {
            NSLog("[PolishSpike] (no proper nouns were changed)")
        } else {
            for e in properNounLedger { NSLog("[PolishSpike] PN: \"\(e.before)\" → \"\(e.after)\"  (clip \(e.clip))") }
        }

        // Throw-vs-length investigation (run-1 hypothesis: errors were clean
        // short clips the model declined on — should now read UNCHANGED).
        let erroredChars = results.compactMap { if case .errored = $0.outcome { return $0.chars } else { return nil } }
        NSLog("[PolishSpike] ===== SUMMARY: \(changed) changed · \(unchanged) unchanged (clean) · \(errored) errored · \(properNounLedger.count) proper-noun edits =====")
        if !erroredChars.isEmpty {
            NSLog("[PolishSpike] errored clip lengths (chars): \(erroredChars.sorted())")
        }
    }

    /// Word-level change blocks via LCS — each block is (removed-run →
    /// added-run). Compact, deterministic; good enough for a spike diff.
    static func wordChangeBlocks(before: String, after: String) -> [(String, String)] {
        let a = before.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let b = after.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let n = a.count, m = b.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        var i = 0, j = 0
        var blocks: [(String, String)] = []
        var rem: [String] = [], add: [String] = []
        func flush() {
            if !rem.isEmpty || !add.isEmpty {
                blocks.append((rem.joined(separator: " "), add.joined(separator: " ")))
                rem = []; add = []
            }
        }
        while i < n && j < m {
            if a[i] == b[j] { flush(); i += 1; j += 1 }
            else if dp[i + 1][j] >= dp[i][j + 1] { rem.append(a[i]); i += 1 }
            else { add.append(b[j]); j += 1 }
        }
        while i < n { rem.append(a[i]); i += 1 }
        while j < m { add.append(b[j]); j += 1 }
        flush()
        return blocks
    }

    /// A change touches a proper noun if either side has a capitalized
    /// multi-letter word other than "I" — over-inclusive on purpose so a name
    /// change is never missed on the ledger.
    static func isProperNounish(_ s: String) -> Bool {
        s.split(whereSeparator: { $0.isWhitespace }).contains { w in
            guard let f = w.first else { return false }
            return f.isUppercase && w.count > 1 && w != "I"
        }
    }
}
#endif
