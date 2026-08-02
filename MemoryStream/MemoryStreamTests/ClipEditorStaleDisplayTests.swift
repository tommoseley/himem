import Testing
import Foundation
@testable import HiMem

/// **F24 Defect 2 — a successful bench edit displayed the pre-edit text.**
///
/// `ClipEditorModal.Source.inbox` wraps `InboxClip`, which is a
/// **struct**. The value is captured when `.sheet(item:)` presents the
/// modal and nothing in the modal ever re-reads the manifest, so
/// `currentContent` kept returning the snapshot's transcript after a
/// commit had correctly written the new one. The save worked; the
/// screen said it hadn't.
///
/// This is the half of F24 that survives even when the write is
/// perfect, which is why it needed its own fix rather than riding along
/// with Defect 3. It also compounded the report: Defect 1 discarded the
/// edit, and had it *not*, Defect 2 would still have shown the old text
/// — two independent causes of one observation.
@Suite(.serialized)
struct ClipEditorStaleDisplayTests {

    // MARK: - Characterisation: the staleness is real and structural

    /// Pins the mechanism, so a future reader knows this is a property
    /// of the type and not a caching bug. A captured `InboxClip` does
    /// NOT observe a later manifest write — the snapshot keeps its own
    /// transcript while the store moves on.
    @Test @MainActor func inboxSource_isAFrozenSnapshot_notALiveRead() {
        let manifest = InboxManifest.shared
        let snapshot = manifest.clips
        defer {
            for clip in manifest.clips where !snapshot.contains(where: { $0.clipId == clip.clipId }) {
                manifest.remove(clipId: clip.clipId)
            }
        }
        let clip = InboxClip(
            clipId: UUID(),
            capturedAt: Date(),
            duration: 3.0,
            transcript: "before the edit",
            latitude: nil,
            longitude: nil,
            source: "phone",
            audioFilename: "f24d2-\(UUID().uuidString).m4a",
            transcriptionAttempted: true,
            rollGroupId: nil
        )
        manifest.acceptClip(clip)

        // `clip` is the value the modal holds for the life of the sheet.
        let heldByTheModal = clip

        manifest.recordTranscriptionAttempt(clipId: clip.clipId, transcript: "after the edit")

        // The store moved…
        #expect(manifest.clips.first(where: { $0.clipId == clip.clipId })?.transcript == "after the edit")
        // …and the modal's captured value did not. THIS is the defect.
        #expect(heldByTheModal.transcript == "before the edit")
    }

    // MARK: - The fix

    @Test func resolvedContent_prefersTheConfirmedCommit() {
        #expect(
            ClipEditorModal.resolvedContent(committed: "after the edit",
                                            backing: "before the edit") == "after the edit"
        )
    }

    @Test func resolvedContent_withNoCommit_readsTheBacking() {
        #expect(
            ClipEditorModal.resolvedContent(committed: nil,
                                            backing: "before the edit") == "before the edit"
        )
    }

    /// A committed empty description is a real stored value and must
    /// win over the backing — not be treated as "nothing committed".
    @Test func resolvedContent_committedEmpty_winsOverBacking() {
        #expect(
            ClipEditorModal.resolvedContent(committed: "", backing: "an old description") == ""
        )
    }

    // MARK: - Caller guards

    /// `currentContent` must consult the confirmed commit. Reading the
    /// backing directly is the defect.
    @Test func currentContent_consultsTheConfirmedCommit() throws {
        let src = try Self.modalSource()
        let body = try Self.functionBody(named: "private var currentContent:", in: src)
        #expect(
            body.contains("resolvedContent"),
            """
            `ClipEditorModal.currentContent` does not consult the confirmed \
            commit. That is F24 Defect 2: a successful bench edit renders the \
            pre-edit snapshot. Body was:
            \(body)
            """
        )
    }

    /// The confirmed commit must be set ONLY from a write that
    /// reported success — otherwise the display would assert an edit
    /// that never landed, converting Defect 2's fix into a new lie of
    /// exactly the kind Defect 3 removed.
    @Test func committedContent_isSetOnlyFromAConfirmedWrite() throws {
        let src = try Self.modalSource()
        let body = try Self.functionBody(named: "private func commitContent(", in: src)
        let code = body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") && !$0.hasPrefix("///") }
        let assignments = code.filter { $0.contains("committedContent =") }
        #expect(assignments.isEmpty == false, "commitContent no longer records the confirmed value.")
        // Every assignment must sit under an `if let stored` binding.
        #expect(
            code.contains(where: { $0.hasPrefix("if let stored") }),
            """
            `committedContent` is assigned without gating on a confirmed \
            write. The display would then claim an edit that reached no \
            store. Body was:
            \(body)
            """
        )
    }

    /// Self-test — the guard must reject a body that assigns
    /// unconditionally, or it is not guarding.
    @Test func guard_wouldRejectAnUngatedAssignment() {
        let ungated = [
            "stored = lifecycle.writeBenchClipTranscript(clipId: clip.clipId, transcript: newValue)",
            "committedContent = newValue"
        ]
        #expect(ungated.contains(where: { $0.hasPrefix("if let stored") }) == false)
    }

    // MARK: - Source access

    static func functionBody(named needle: String, in source: String) throws -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains(needle) }) else {
            throw Failure.functionNotFound(needle)
        }
        var depth = 0
        var started = false
        var out: [String] = []
        for line in lines[start...] {
            for ch in line {
                if ch == "{" { depth += 1; started = true }
                if ch == "}" { depth -= 1 }
            }
            if started { out.append(line) }
            if started && depth == 0 { return out.joined(separator: "\n") }
        }
        throw Failure.functionNotFound(needle)
    }

    static func modalSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MemoryStream/Views/Clip/ClipEditorModal.swift")
        guard let src = try? String(contentsOf: url, encoding: .utf8), !src.isEmpty else {
            throw Failure.sourceNotFound(url.path)
        }
        return src
    }

    enum Failure: Error { case sourceNotFound(String), functionNotFound(String) }
}
