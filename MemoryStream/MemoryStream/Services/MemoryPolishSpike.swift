#if DEBUG
import Foundation
import CoreData
import FoundationModels

/// Device-only spike harness for **Memory Polish §3 (auto-correct)**. NOT a
/// shipped feature — `#if DEBUG`, triggered from Settings → Debug.
///
/// **v3 (2026-07-25) — substitution-pairs, not free text.** Runs 1 and 2 both
/// showed the on-device 3B ignores a punctuation prohibition and (v2) edits
/// punctuation/whitespace of already-correct text — including a quotation —
/// while making zero real word repairs. You can't prompt a 3B out of an
/// ingrained behavior. So v3 applies our own principle — *models are advisory,
/// code is authoritative*:
///   - the model returns ONLY a list of `{wrong, right}` word-substitution
///     pairs, never the transcript;
///   - **code** performs the swaps, so the model structurally cannot reformat,
///     strip punctuation, collapse whitespace, or change sentence boundaries;
///   - a pair is REJECTED if its two sides differ only in punctuation /
///     whitespace / case, or if `wrong` is not found verbatim in the source.
///
/// This also yields the §3 diff UI for free: a list of proposed corrections the
/// user could accept individually. `TruthReconciler` still can't gate the text,
/// but the swap-only + verbatim-source constraints are the code-authoritative
/// guard the spec §2 calls for. No UI, no tier lock — the spike reports first.
///
/// Bar (Tom): re-catch the compost clip's craps→scraps / diary→dairy /
/// compos→compost, leave the Lincoln quote and the lemons byte-identical, and
/// produce zero punctuation-only edits. If v3 fails, auto-correct is
/// frontier/Plus and the on-device attempt is logged as a documented ceiling.
enum MemoryPolishSpike {

    static let instructions = """
    You are given the raw speech-to-text transcript of one voice clip. Your job is to find words the transcriber clearly got WRONG — misheard words, wrong homophones, or a word split/joined incorrectly — and list the corrections.

    For each correction, output a pair: `wrong` = the incorrect text exactly as it appears in the transcript, and `right` = the word(s) the person actually said.

    Rules:
    - List ONLY clear word errors. Do NOT list punctuation, capitalization, spacing, or grammar changes — those are not your job.
    - `wrong` must be copied verbatim from the transcript.
    - Only correct a name or proper noun when the intended word is obvious from context; never invent one.
    - When unsure about a word, do not list it. Say less before saying false.
    - If nothing is clearly wrong, return an empty list.
    """

    @Generable
    struct Substitution: Equatable {
        @Guide(description: "The incorrect word or short phrase, copied verbatim from the transcript.")
        var wrong: String
        @Guide(description: "The word or short phrase the person actually said, to replace it with.")
        var right: String
    }

    @Generable
    struct Corrections {
        @Guide(description: "Only clear speech-to-text word errors as {wrong, right} pairs. Empty if nothing is clearly wrong.")
        var substitutions: [Substitution]
    }

    enum RejectReason: String { case punctuationOrCaseOnly, notInSource }

    struct ClipResult {
        let id: UUID
        let chars: Int
        let before: String
        let accepted: [Substitution]
        let rejected: [(Substitution, RejectReason)]
        let after: String
        let errored: String?
    }

    @MainActor
    static func run(count: Int = 8) async {
        NSLog("[PolishSpike] ===== Memory Polish §3 auto-correct spike (v3 · substitution pairs, code-applied) =====")
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
            NSLog("[PolishSpike] proposing \(i + 1)/\(sample.count) (\(before.count) chars)…")
            results.append(await process(id: ref.id, before: before))
        }
        report(results)
    }

    private static func spread(_ all: [MediaReference], count: Int) -> [MediaReference] {
        guard all.count > count else { return all }
        let step = Double(all.count) / Double(count)
        return (0..<count).map { all[min(all.count - 1, Int(Double($0) * step))] }
    }

    /// Ask the model for pairs, validate them in code, apply the survivors.
    private static func process(id: UUID, before: String) async -> ClipResult {
        let session = LanguageModelSession(instructions: instructions)
        let prompt = "Transcript:\n\(before)\n\nList the clear word errors as {wrong, right} pairs, or an empty list if there are none."
        let proposed: [Substitution]
        do {
            let response = try await session.respond(to: prompt, generating: Corrections.self, options: GenerationOptions())
            proposed = response.content.substitutions
        } catch {
            return ClipResult(id: id, chars: before.count, before: before, accepted: [], rejected: [],
                              after: before, errored: String(describing: error))
        }
        var accepted: [Substitution] = []
        var rejected: [(Substitution, RejectReason)] = []
        var text = before
        for sub in proposed {
            if core(sub.wrong) == core(sub.right) {
                rejected.append((sub, .punctuationOrCaseOnly)); continue   // differ only in punct/case/space
            }
            guard text.contains(sub.wrong) || before.contains(sub.wrong) else {
                rejected.append((sub, .notInSource)); continue            // model didn't copy verbatim
            }
            accepted.append(sub)
            text = text.replacingOccurrences(of: sub.wrong, with: sub.right)  // CODE performs the swap
        }
        return ClipResult(id: id, chars: before.count, before: before, accepted: accepted,
                          rejected: rejected, after: text, errored: nil)
    }

    /// Letters+digits, lowercased — two sides that match here differ only in
    /// punctuation / whitespace / case, which is NOT a word repair.
    private static func core(_ s: String) -> String {
        s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    // MARK: - Report

    private static func report(_ results: [ClipResult]) {
        var properNounLedger: [(String, String, UUID)] = []
        var changedClips = 0, cleanClips = 0, erroredClips = 0
        var acceptedTotal = 0, rejPunct = 0, rejNotFound = 0

        for r in results {
            if let err = r.errored {
                erroredClips += 1
                NSLog("[PolishSpike] ---- clip \(r.id) · \(r.chars) chars · ERRORED: \(err) ----")
                continue
            }
            let changed = r.after != r.before
            if changed { changedClips += 1 } else { cleanClips += 1 }
            acceptedTotal += r.accepted.count
            rejPunct += r.rejected.filter { $0.1 == .punctuationOrCaseOnly }.count
            rejNotFound += r.rejected.filter { $0.1 == .notInSource }.count

            NSLog("[PolishSpike] ---- clip \(r.id) · \(r.chars) chars · \(changed ? "CHANGED" : "UNCHANGED") · \(r.accepted.count) applied, \(r.rejected.count) rejected ----")
            for s in r.accepted {
                NSLog("[PolishSpike] APPLY:  \"\(s.wrong)\" → \"\(s.right)\"")
                if isProperNounish(s.wrong) || isProperNounish(s.right) {
                    properNounLedger.append((s.wrong, s.right, r.id))
                }
            }
            for (s, reason) in r.rejected {
                NSLog("[PolishSpike] REJECT[\(reason.rawValue)]: \"\(s.wrong)\" → \"\(s.right)\"")
            }
            if changed {
                NSLog("[PolishSpike] BEFORE: \(r.before)")
                NSLog("[PolishSpike] AFTER : \(r.after)")
            }
        }

        NSLog("[PolishSpike] ===== PROPER-NOUN LEDGER (over-correction watch) =====")
        if properNounLedger.isEmpty {
            NSLog("[PolishSpike] (no proper nouns were changed)")
        } else {
            for e in properNounLedger { NSLog("[PolishSpike] PN: \"\(e.0)\" → \"\(e.1)\"  (clip \(e.2))") }
        }
        NSLog("[PolishSpike] ===== SUMMARY: \(changedClips) changed · \(cleanClips) clean · \(erroredClips) errored · \(acceptedTotal) swaps applied · rejected \(rejPunct) punct-only + \(rejNotFound) not-in-source · \(properNounLedger.count) proper-noun edits =====")
    }

    /// Over-inclusive proper-noun flag: any capitalized multi-letter word other
    /// than "I", so a name change can't slip past the ledger.
    static func isProperNounish(_ s: String) -> Bool {
        s.split(whereSeparator: { $0.isWhitespace }).contains { w in
            guard let f = w.first else { return false }
            return f.isUppercase && w.count > 1 && w != "I"
        }
    }
}
#endif
