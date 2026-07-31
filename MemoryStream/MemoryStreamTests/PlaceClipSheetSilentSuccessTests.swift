import Testing
import Foundation
import CoreData
@testable import HiMem

/// F23 · T1.2 — **`PlaceClipSheet` confirmed placements that never happened.**
///
/// `commit()` ran the placement inside a `do` and then fired `onPlaced?()` and
/// `dismiss()` unconditionally. Both write paths bail early when their fetch
/// misses (`PlaceClipSheet.swift:222/:227` pre-fix) — so a target memory that
/// had been deleted, or synced away, while the sheet was open produced: no
/// edge, no error, sheet closed, caller's completion fired. The user is told
/// the clip moved and has no reason to look again. That is worse than a no-op.
///
/// The sibling `PlaceInboxClipSheet.commit()` in the same file has always
/// checked its return code and reported on failure; the older struct predates
/// that contract and was never brought up to it. These tests pin the contract
/// on **both** halves of it:
///
/// - `performPlacement` must answer *did anything get written*, not *did we
///   avoid throwing* — with a non-empty companion so "always false" can't pass.
/// - `commit()` must actually gate its confirmation on that answer. Testing the
///   owner without testing that the caller consults it is the Class-4 #2 shape
///   the same audit flagged (`WatchTransferAudioTranscoderTests`).
@MainActor
@Suite(.serialized)
struct PlaceClipSheetSilentSuccessTests {

    // MARK: - The outcome is honest

    /// THE MONEY TEST. Selected memory no longer exists → nothing is written,
    /// so the placement must report `false`. Pre-fix this path returned
    /// normally and `commit()` confirmed.
    @Test func addToExisting_whenTheTargetMemoryIsGone_reportsNotPlaced() throws {
        let storage = StorageService(inMemory: true)
        let home = try storage.createEntry(content: "", inputType: .typed, title: "Home")
        let ref = try storage.createVoiceFragment(for: home, audioFilename: "a.m4a", transcript: "hi")
        try storage.viewContext.save()
        let edgesBefore = ref.referencingMemoryCount

        let placed = try PlaceClipSheet.performPlacement(
            destination: .existingMemory,
            ref: ref,
            selectedEntryId: UUID(),      // never created — the fetch misses
            sourceMemoryId: nil,
            newMemoryTitle: "",
            storage: storage
        )

        #expect(placed == false, "no edge was created; the sheet must not confirm a placement")
        #expect(ref.referencingMemoryCount == edgesBefore, "nothing may be written on the miss path")
    }

    /// The non-empty companion: the same call against a real memory must
    /// report `true` and create the edge. Without this, `return false`
    /// everywhere would pass the money test.
    @Test func addToExisting_whenTheTargetResolves_reportsPlaced_andCreatesTheEdge() throws {
        let storage = StorageService(inMemory: true)
        let home = try storage.createEntry(content: "", inputType: .typed, title: "Home")
        let ref = try storage.createVoiceFragment(for: home, audioFilename: "a.m4a", transcript: "hi")
        let target = try storage.createEntry(content: "", inputType: .typed, title: "Target")
        try storage.viewContext.save()

        let placed = try PlaceClipSheet.performPlacement(
            destination: .existingMemory,
            ref: ref,
            selectedEntryId: target.id,
            sourceMemoryId: nil,
            newMemoryTitle: "",
            storage: storage
        )

        #expect(placed == true)
        #expect(target.edgesArray.contains { $0.clipId == ref.id }, "the edge the confirmation claims")
    }

    /// "Remove" against an edge that is already gone removed nothing, and
    /// `removeClipFromMemory` returns `Void`, so the sheet used to close on a
    /// removal it never performed.
    @Test func removeFromThisMemory_whenTheEdgeIsAlreadyGone_reportsNotPlaced() throws {
        let storage = StorageService(inMemory: true)
        let home = try storage.createEntry(content: "", inputType: .typed, title: "Home")
        let ref = try storage.createVoiceFragment(for: home, audioFilename: "a.m4a", transcript: "hi")
        let unrelated = try storage.createEntry(content: "", inputType: .typed, title: "Unrelated")
        try storage.viewContext.save()

        let placed = try PlaceClipSheet.performPlacement(
            destination: .removeFromThisMemory,
            ref: ref,
            selectedEntryId: nil,
            sourceMemoryId: unrelated.id,   // holds no edge to this clip
            newMemoryTitle: "",
            storage: storage
        )

        #expect(placed == false, "there was no edge to drop; 'Removed' would be a false claim")
    }

    /// Companion: a real edge is dropped and reported.
    @Test func removeFromThisMemory_whenTheEdgeExists_reportsPlaced_andDropsIt() throws {
        let storage = StorageService(inMemory: true)
        let home = try storage.createEntry(content: "", inputType: .typed, title: "Home")
        let ref = try storage.createVoiceFragment(for: home, audioFilename: "a.m4a", transcript: "hi")
        try storage.viewContext.save()

        let placed = try PlaceClipSheet.performPlacement(
            destination: .removeFromThisMemory,
            ref: ref,
            selectedEntryId: nil,
            sourceMemoryId: home.id,
            newMemoryTitle: "",
            storage: storage
        )

        #expect(placed == true)
        #expect(!home.edgesArray.contains { $0.clipId == ref.id }, "the edge is gone")
    }

    // MARK: - The caller consults the outcome

    /// THE GATE. Every `onPlaced?()` in the file must sit behind the placement
    /// result. An honest `performPlacement` that `commit()` ignores rebuilds
    /// the exact defect.
    @Test func everyConfirmationIsGatedOnThePlacementResult() throws {
        let source = try Self.placeClipSheetSource()
        let ungated = Self.ungatedConfirmations(in: source)
        #expect(
            ungated.isEmpty,
            """
            `onPlaced?()` is reached without checking whether the placement \
            happened, at line(s) \(ungated.map(String.init).joined(separator: ", ")).

            That is F23 T1.2 rebuilt: the fetch misses, nothing is written, and \
            the UI confirms the move anyway. Gate the confirmation on the \
            placement result and report the failure instead (the contract \
            `PlaceInboxClipSheet.commit()` already honors).
            """
        )
    }

    /// Guards the guard: the scanner must be able to see an ungated
    /// confirmation, or it passes by recognizing nothing.
    @Test func theGateScannerCanSeeAnUngatedConfirmation() {
        let ungated = """
            private func commit() {
                do {
                    try addToExisting()
                    onPlaced?()
                    dismiss()
                } catch {}
            }
            """
        #expect(Self.ungatedConfirmations(in: ungated) == [4], "the shipped defect, verbatim")

        let gatedByResult = """
            private func commit() {
                do {
                    guard try Self.performPlacement(destination: destination) else { return }
                    onPlaced?()
                } catch {}
            }
            """
        #expect(Self.ungatedConfirmations(in: gatedByResult).isEmpty)

        let gatedByFlag = """
            private func commit() {
                let ok = lifecycle.attachExistingClips(entryId: id, clipIds: [c]) > 0
                if ok {
                    onPlaced?()
                }
            }
            """
        #expect(Self.ungatedConfirmations(in: gatedByFlag).isEmpty, "the sibling's shape")
    }

    /// 1-indexed lines where `onPlaced?()` is reached without the enclosing
    /// `commit()` first branching on whether the placement happened.
    static func ungatedConfirmations(in source: String) -> [Int] {
        let lines = source.components(separatedBy: "\n")
        var enclosingCommit: Int? = nil
        var out: [Int] = []
        for (i, line) in lines.enumerated() {
            if line.contains("func commit()") { enclosingCommit = i }
            guard line.contains("onPlaced?()") else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { continue }
            guard let start = enclosingCommit else { out.append(i + 1); continue }
            let body = lines[start...i].joined(separator: "\n")
            let gated = (body.contains("guard try Self.performPlacement") && body.contains("else {"))
                || (body.contains("if ok {"))
            if !gated { out.append(i + 1) }
        }
        return out
    }

    static func placeClipSheetSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // MemoryStreamTests
            .deletingLastPathComponent()          // MemoryStream (project dir)
            .appendingPathComponent("MemoryStream/Views/Inbox/PlaceClipSheet.swift")
        guard let src = try? String(contentsOf: url, encoding: .utf8), !src.isEmpty else {
            // The sibling scanners hardened on 2026-07-31 all throw rather than
            // pass on an empty read; a moved file must break the guard loudly.
            throw Failure.sourceNotFound(url.path)
        }
        return src
    }

    enum Failure: Error { case sourceNotFound(String) }
}
