#if DEBUG
import Foundation
import CoreData
import FoundationModels

/// Device-only spike harness for **Memory Polish §3 (auto-correct)**. NOT a
/// shipped feature — wrapped in `#if DEBUG`, triggered from Settings → Debug.
/// It runs the *constrained* on-device ASR-repair pass over a natural sample of
/// real library clips and logs, per `docs/design/Memory Polish · spec.md`:
///   - before → after for each clip,
///   - a word-level diff (the changes), and
///   - a consolidated **proper-noun ledger** (every proper noun the pass
///     touched, before→after) — the Lincoln-in-miniature over-correction risk,
///     surfaced scannably rather than buried in the diff.
///
/// The spike gates the tier: if the pass fixes real errors WITHOUT
/// over-correcting already-correct text (esp. names), §3 can be Free; if it
/// drifts, it moves to Plus/frontier. Governance note (spec §2): `TruthReconciler`
/// cannot gate this — the clip text itself is what changes — so quality is a
/// human read on this output.
enum MemoryPolishSpike {

    /// Repair-only, never-assert instructions (spec §2 governing line).
    static let instructions = """
    You are a careful transcript proofreader for a personal memory app. You are given the raw speech-to-text transcript of one voice clip. Fix ONLY clear transcription errors — misheard words, wrong homophones, obvious word-splits — so the text matches what the person actually said.

    Strict rules:
    - Do NOT add, remove, reorder, or rephrase content. Do NOT restructure, re-paragraph, or summarize.
    - Do NOT "improve" wording that is already correct. Preserve the person's exact words, grammar, filler, and asides.
    - Change a word ONLY when you are highly confident it is a transcription error and you know from context what was actually said.
    - Be especially careful with names and proper nouns: correct one only when the intended word is obvious from context; never invent a name.
    - When unsure, leave the text exactly as it is. Say less before saying false.
    - Output ONLY the corrected transcript text — no preamble, no notes, no quotes.
    """

    struct ClipResult {
        let id: UUID
        let createdAt: Date
        let before: String
        let after: String
    }

    /// Fetch a NATURAL sample of ~count real voice transcripts spread across the
    /// whole library (recent — incl. today's flagged walk clips — AND older
    /// never-complained-about clips), run the repair, and log everything. The
    /// spread is deliberate: over-correction shows up on the clips the user
    /// never noticed, which can't be hand-picked.
    @MainActor
    static func run(count: Int = 8) async {
        NSLog("[PolishSpike] ===== Memory Polish §3 auto-correct spike =====")
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
        NSLog("[PolishSpike] Sampling \(sample.count) of \(all.count) voice clips, spread across the library (newest→oldest).")

        var results: [ClipResult] = []
        for (i, ref) in sample.enumerated() {
            let before = ref.transcript ?? ""
            NSLog("[PolishSpike] repairing \(i + 1)/\(sample.count) (\(before.count) chars)…")
            let after = await repair(before)
            results.append(ClipResult(id: ref.id, createdAt: ref.createdAt ?? .distantPast,
                                      before: before, after: after))
        }
        report(results)
    }

    /// Evenly spaced across the sorted list so the sample isn't all-recent /
    /// all-broken — natural coverage of both error-heavy and clean clips.
    private static func spread(_ all: [MediaReference], count: Int) -> [MediaReference] {
        guard all.count > count else { return all }
        let step = Double(all.count) / Double(count)
        return (0..<count).map { all[min(all.count - 1, Int(Double($0) * step))] }
    }

    private static func repair(_ text: String) async -> String {
        let session = LanguageModelSession(instructions: instructions)
        let prompt = "Transcript:\n\(text)\n\nReturn the corrected transcript."
        do {
            let r = try await session.respond(to: prompt, options: GenerationOptions())
            return r.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            NSLog("[PolishSpike] repair threw: \(error) — leaving text unchanged")
            return text
        }
    }

    // MARK: - Report

    private static func report(_ results: [ClipResult]) {
        var properNounLedger: [(before: String, after: String, clip: UUID)] = []
        for r in results {
            let changed = r.before != r.after
            NSLog("[PolishSpike] ---- clip \(r.id) · \(r.createdAt) · changed=\(changed) · \(r.before.count)→\(r.after.count) chars ----")
            NSLog("[PolishSpike] BEFORE: \(r.before)")
            NSLog("[PolishSpike] AFTER : \(r.after)")
            let blocks = wordChangeBlocks(before: r.before, after: r.after)
            if blocks.isEmpty {
                NSLog("[PolishSpike] DIFF: (no word-level changes)")
            }
            for (rem, add) in blocks {
                NSLog("[PolishSpike] DIFF: \"\(rem)\" → \"\(add)\"")
                if isProperNounish(rem) || isProperNounish(add) {
                    properNounLedger.append((rem, add, r.id))
                }
            }
        }
        NSLog("[PolishSpike] ===== PROPER-NOUN LEDGER (over-correction watch) =====")
        if properNounLedger.isEmpty {
            NSLog("[PolishSpike] (no proper nouns were changed)")
        } else {
            for e in properNounLedger {
                NSLog("[PolishSpike] PN: \"\(e.before)\" → \"\(e.after)\"  (clip \(e.clip))")
            }
        }
        let changedCount = results.filter { $0.before != $0.after }.count
        NSLog("[PolishSpike] ===== SUMMARY: \(changedCount)/\(results.count) clips changed · \(properNounLedger.count) proper-noun edits =====")
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

    /// A change touches a proper noun if either side contains a capitalized
    /// multi-letter word other than the pronoun "I" — over-inclusive on
    /// purpose so a name change is never missed on the ledger.
    static func isProperNounish(_ s: String) -> Bool {
        s.split(whereSeparator: { $0.isWhitespace }).contains { w in
            guard let f = w.first else { return false }
            return f.isUppercase && w.count > 1 && w != "I"
        }
    }
}
#endif
