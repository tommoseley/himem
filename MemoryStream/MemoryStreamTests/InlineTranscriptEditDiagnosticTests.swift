import Testing
import Foundation
@testable import HiMem

/// Diagnostic (P0 2026-07-16) — pin down the inline expanded-clip editor
/// transcript-wipe: is the compact projection rendering "(no transcript)"
/// when a transcript exists (display bug), and does the inline commit
/// decision skip a no-op (commit guard)?
@Suite
struct InlineTranscriptEditDiagnosticTests {

    private func voiceItem(transcript: String?) -> MediaDisplayItem {
        MediaDisplayItem(
            id: UUID(),
            localIdentifier: "clip.m4a",
            mediaType: .voice,
            thumbnailCacheFilename: nil,
            isAccessible: true,
            transcript: transcript
        )
    }

    // (b) — compact projection: does the row render the transcript, or "(no transcript)"?
    @Test func compactPreview_rendersTranscript_whenPresent() {
        let item = voiceItem(transcript: "Ben said the Basque cheesecake")
        let preview = CompactClipRow.previewLine(for: item)
        #expect(preview.contains("Ben said the Basque cheesecake"),
                "compact preview must render the transcript, not (no transcript) — preview=\(preview)")
    }

    @Test func compactExpandedBody_returnsTranscript_whenPresent() {
        let item = voiceItem(transcript: "Ben said the Basque cheesecake")
        let body = CompactClipRow.expandedBody(for: item)
        #expect(body == "Ben said the Basque cheesecake")
    }

    @Test func compactPreview_saysNoTranscript_onlyWhenEmpty() {
        let item = voiceItem(transcript: "")
        #expect(CompactClipRow.previewLine(for: item) == "(no transcript)")
    }

    // (a) — the inline commit decision: a no-op Done skips (T survives).
    @Test func inlineDecision_noOp_skips() {
        let T = "Ben said the Basque cheesecake"
        #expect(ClipEditorCommitDecision.decide(initial: T, draft: T, field: .transcript) == .skip)
    }

    // The wipe guard (P0 2026-07-16): an empty draft against a real initial
    // now SKIPS — it never commits "" over a non-empty transcript. This is
    // the fix for the CompactClipRow onDone wipe the [TranscriptWipe]
    // instrumentation pinned.
    @Test func inlineDecision_emptyDraftAgainstReal_skips() {
        let T = "Ben said the Basque cheesecake"
        #expect(ClipEditorCommitDecision.decide(initial: T, draft: "", field: .transcript) == .skip)
    }
}
