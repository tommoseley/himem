import Testing
import Foundation
@testable import HiMem

/// **F24 Defect 3 — an edit that reached no store reported success.**
///
/// `ClipEditorModal.commitContent` called a writer and closed. The
/// writers all ended a miss in a bare `return`:
///
///   - `EntryLifecycleService.updateClipTranscript`  — `guard let ref … else { return }`
///   - `EntryLifecycleService.updateClipDescription` — same
///   - `InboxManifest.recordTranscriptionAttempt`    — `guard let idx … else { return }`
///
/// and `writeBenchClipTranscript` stacked two of them, so a clip that
/// was neither a live `MediaReference` nor a manifest row lost the edit
/// with no error, no log, and a sheet that closed as though it saved.
/// A silent failed save is worse than a wipe: the user believes it took.
///
/// **Honest labelling of what these tests are.** The writer tests below
/// are *contract* tests — they were written alongside the signature
/// change and passed immediately, so they did not have a red-first
/// cycle (ADR-050; the same disclosure made for four of the five tests
/// in the F6f orphan-reclaim fix). They pin the contract going forward;
/// they are not reproductions.
///
/// **The reproduction is `commitContent_checksThatTheWriteLanded`** —
/// the caller guard, mutation-verified against the shipped body.
@Suite(.serialized)
struct ClipEditorSilentSaveTests {

    // MARK: - Writers report a miss (contract, not reproduction)

    @Test @MainActor func recordTranscriptionAttempt_unknownClip_returnsNil() {
        let manifest = InboxManifest.shared
        let absent = UUID()
        #expect(manifest.clips.contains(where: { $0.clipId == absent }) == false)
        #expect(manifest.recordTranscriptionAttempt(clipId: absent, transcript: "typed by hand") == nil)
    }

    @Test @MainActor func recordTranscriptionAttempt_knownClip_returnsStoredText() {
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
            transcript: "",
            latitude: nil,
            longitude: nil,
            source: "phone",
            audioFilename: "f24-\(UUID().uuidString).m4a",
            transcriptionAttempted: false,
            rollGroupId: nil
        )
        manifest.acceptClip(clip)

        let stored = manifest.recordTranscriptionAttempt(clipId: clip.clipId, transcript: "typed by hand")
        #expect(stored == "typed by hand")
        #expect(manifest.clips.first(where: { $0.clipId == clip.clipId })?.transcript == "typed by hand")
    }

    /// The exact F24 shape: a clip in **neither** store. Both branches
    /// of `writeBenchClipTranscript` miss, and the caller must be able
    /// to tell.
    @Test @MainActor func writeBenchClipTranscript_clipInNeitherStore_returnsNil() {
        let service = EntryLifecycleService()
        let absent = UUID()
        #expect(InboxManifest.shared.clips.contains(where: { $0.clipId == absent }) == false)
        #expect(service.writeBenchClipTranscript(clipId: absent, transcript: "typed by hand") == nil)
    }

    // MARK: - The message

    /// Parallel construction with the approved family (2026-07-31).
    /// Pinned as a literal because the wording IS the promise here —
    /// Crucible voice: name the state, never blame the user, offer the
    /// one useful action. A failure of this test means the promise
    /// moved, not that phrasing drifted.
    @Test func saveFailedMessage_isTheApprovedString() {
        #expect(ClipEditorModal.saveFailedMessage == "Couldn't save your edit. Try again.")
        // Parallel construction with the approved family: the app owns
        // the failure ("Couldn't…"), and the user is offered the one
        // useful action ("Try again."). Never "You…" as the actor —
        // possessive "your edit" is the user's *thing*, not their fault.
        #expect(ClipEditorModal.saveFailedMessage.hasPrefix("Couldn't "))
        #expect(ClipEditorModal.saveFailedMessage.hasSuffix("Try again."))
        #expect(ClipEditorModal.saveFailedMessage.hasPrefix("You") == false)
    }

    // MARK: - The caller guard (the reproduction)

    /// `commitContent` must consult what the writer returned. Ignoring
    /// it is the defect, and it is invisible at the writer level: every
    /// writer test above stays green while the modal confirms a save
    /// that never happened.
    @Test func commitContent_checksThatTheWriteLanded() throws {
        let src = try Self.modalSource()
        let body = try Self.functionBody(named: "private func commitContent(", in: src)
        #expect(
            Self.ignoresTheWriteResult(body: body) == false,
            """
            `ClipEditorModal.commitContent` calls a writer and never checks \
            whether the edit landed. That is F24 Defect 3: the sheet confirms \
            a save that reached no store. Body was:
            \(body)
            """
        )
    }

    /// Self-test — the scanner must flag the shape that shipped.
    @Test func scanner_flagsThePreFixBody() {
        let shipped = """
                switch source {
                case .inbox(let clip):
                    lifecycle.writeBenchClipTranscript(clipId: clip.clipId, transcript: newValue)
                case .managed(let ref):
                    if ref.mediaTypeEnum == .image || ref.mediaTypeEnum == .video {
                        lifecycle.updateClipDescription(refId: ref.id, description: newValue)
                    } else {
                        lifecycle.updateClipTranscript(refId: ref.id, transcript: newValue)
                    }
                }
        """
        #expect(Self.ignoresTheWriteResult(body: shipped) == true)
    }

    /// Self-test the other way, so the guard cannot fail permanently.
    @Test func scanner_acceptsACheckingBody() {
        let fixed = """
                let stored: String?
                switch source {
                case .inbox(let clip):
                    stored = lifecycle.writeBenchClipTranscript(clipId: clip.clipId, transcript: newValue)
                case .managed(let ref):
                    stored = lifecycle.updateClipTranscript(refId: ref.id, transcript: newValue)
                }
                saveError = (stored == nil) ? Self.saveFailedMessage : nil
        """
        #expect(Self.ignoresTheWriteResult(body: fixed) == false)
    }

    // MARK: - Scanner

    /// A body ignores the result when it calls a writer but never binds
    /// or tests what came back.
    static func ignoresTheWriteResult(body: String) -> Bool {
        let code = body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") && !$0.hasPrefix("///") }
            .joined(separator: "\n")
        let writers = ["writeBenchClipTranscript", "updateClipTranscript", "updateClipDescription"]
        let callsAWriter = writers.contains { code.contains($0) }
        guard callsAWriter else { return false }
        // Every writer call must be bound (`stored = lifecycle.write…`),
        // not fired as a bare statement (`lifecycle.write…`).
        let bare = code
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .contains { line in
                writers.contains { line.contains("lifecycle.\($0)") } && !line.contains("=")
            }
        return bare || !code.contains("saveError")
    }

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
