import Testing
import Foundation
@testable import HiMem

/// Money tests for `MentionReconciler` (palette-bleed fix #2, 2026-07-23).
/// The guardrail is the whole point: collapse only near-identical variants,
/// NEVER merge onto a different person; when unsure, keep as-is (a wrong
/// merge is the same fabrication one layer down).
@Suite
struct MentionReconcilerTests {

    // MARK: - The dedup it SHOULD do

    @Test func variant_collapsesToTheSingleLibraryName() {
        #expect(MentionReconciler.reconcile(extracted: ["Darlene"], library: ["Darlene G."]) == ["Darlene G."])
        #expect(MentionReconciler.reconcile(extracted: ["Darlene G."], library: ["Darlene"]) == ["Darlene"])
        #expect(MentionReconciler.reconcile(extracted: ["Ben"], library: ["Ben Carter"]) == ["Ben Carter"])
    }

    @Test func exactMatch_reusesLibrarySpellingModuloCase() {
        #expect(MentionReconciler.reconcile(extracted: ["darlene"], library: ["Darlene"]) == ["Darlene"])
        #expect(MentionReconciler.reconcile(extracted: ["  BEN  "], library: ["Ben"]) == ["Ben"])
    }

    // MARK: - The merges it MUST NOT do (the conservative guardrail)

    @Test func ambiguousVariant_keptAsIs_neverGuessed() {
        // Two library people share the first name — merging would fabricate
        // which one. Keep the extracted name as its own (New) mention.
        let out = MentionReconciler.reconcile(extracted: ["Darlene"], library: ["Darlene G.", "Darlene P."])
        #expect(out == ["Darlene"])
    }

    @Test func differentPerson_neverMerged() {
        // Different token — not a variant, not the same person.
        #expect(MentionReconciler.reconcile(extracted: ["Ben"], library: ["Benjamin"]) == ["Ben"])
        #expect(MentionReconciler.reconcile(extracted: ["Ben"], library: ["Bob"]) == ["Ben"])
        // Equal-length token lists are never "variants" (Ben vs Benjamin
        // are both one token) — only exact match or keep-as-is.
        #expect(MentionReconciler.reconcile(extracted: ["Jon Smith"], library: ["Joe Smith"]) == ["Jon Smith"])
    }

    @Test func noMatch_keptAsNew() {
        #expect(MentionReconciler.reconcile(extracted: ["Abraham Lincoln"], library: ["Darlene", "Ben"]) == ["Abraham Lincoln"])
    }

    @Test func emptyLibrary_everythingKeptAsIs() {
        #expect(MentionReconciler.reconcile(extracted: ["Ben", "Darlene"], library: []) == ["Ben", "Darlene"])
    }

    @Test func multipleExtracted_mappedIndependently_orderPreserved() {
        let out = MentionReconciler.reconcile(
            extracted: ["darlene", "Ben", "Sarah"],
            library: ["Darlene G.", "Ben Carter"]
        )
        // darlene → Darlene G. (variant), Ben → Ben Carter (variant),
        // Sarah → Sarah (New).
        #expect(out == ["Darlene G.", "Ben Carter", "Sarah"])
    }
}
