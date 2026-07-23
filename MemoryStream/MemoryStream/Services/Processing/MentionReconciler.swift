import Foundation

/// Conservative in-code reconciliation of a model's freely-extracted
/// mention names against the user's existing library names (palette-bleed
/// fix #2, 2026-07-23).
///
/// **Why this exists.** The library-wide mentions palette used to be placed
/// in the organize prompt so the model would reuse existing names (§2c
/// anti-fragmentation). But a 3B on-device model treated that list as
/// participants and **fabricated** library people (Darlene, Ben) into
/// memories that never named them — a Lincoln quote became "You, Darlene,
/// shared…". So the palette is no longer put in front of the model: it
/// extracts mentions from THIS memory's clips only (nothing foreign to
/// parrot), and this maps near-identical variants onto the existing library
/// name in code — keeping the dedup benefit WITHOUT ever inventing a name or
/// merging onto a different person.
///
/// **Conservative by design** (guardrail: "when unsure, keep as-is — a wrong
/// merge is the same fabrication one layer down"):
/// - Exact match modulo case/whitespace → reuse the library's stored spelling.
/// - Near-identical **variant** (one name's whitespace tokens are a strict
///   prefix of the other's — "Darlene" ⊂ "Darlene G.") → collapse to the
///   library name, but ONLY when exactly one library name qualifies. Two
///   candidates ("Darlene G." AND "Darlene P.") → ambiguous → keep as-is.
/// - Different token ("Ben" vs "Benjamin") or no match → keep as-is (New).
enum MentionReconciler {

    /// Maps each extracted name to its canonical library form (or itself).
    /// Order preserved; the caller dedups downstream via `findOrCreateMention`.
    static func reconcile(extracted: [String], library: [String]) -> [String] {
        extracted.map { canonicalize($0, library: library) }
    }

    static func canonicalize(_ name: String, library: [String]) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = normalize(trimmed)
        guard !key.isEmpty else { return trimmed }

        // 1. Exact match modulo case/whitespace → reuse library spelling.
        if let exact = library.first(where: { normalize($0) == key }) {
            return exact
        }
        // 2. Near-identical variant — collapse ONLY when unambiguous.
        let variants = library.filter { areVariants(trimmed, $0) }
        if variants.count == 1 {
            return variants[0]
        }
        // 3. No confident match (none, or ambiguous) → keep as-is (New).
        return trimmed
    }

    /// Two names are near-identical variants when their whitespace tokens,
    /// compared case-insensitively, have one a STRICT PREFIX of the other
    /// ("Darlene" ⊂ "Darlene G."). Equal-length token lists are the
    /// exact-match rule's job, not this one.
    private static func areVariants(_ a: String, _ b: String) -> Bool {
        let ta = tokens(a), tb = tokens(b)
        guard !ta.isEmpty, !tb.isEmpty, ta.count != tb.count else { return false }
        let (short, long) = ta.count < tb.count ? (ta, tb) : (tb, ta)
        return Array(long.prefix(short.count)) == short
    }

    private static func tokens(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
