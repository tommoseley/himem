import Testing
import Foundation
@testable import HiMem

/// Money tests for `VoiceClipPanel.displayText(transcript:audioStatus:)`
/// — the pure function the voice-clip row body funnels through to
/// choose its label.
///
/// Before 2026-06-07 the panel rendered "(no transcript)" for every
/// empty-transcript voice clip, regardless of whether the audio file
/// was waiting on iCloud download or genuinely silent. On fresh
/// second-device installs (CloudKit ships the MediaReference before
/// the audio file), users saw an unactionable "(no transcript)" with
/// no signal that bytes were still arriving — the watch-side spec's
/// honesty contract called out as broken by the Troika UX reviewer.
///
/// Contract:
/// - Non-empty transcript → render the transcript itself.
/// - Empty transcript + status downloading/notDownloaded → render
///   "Audio downloading from iCloud…" so the user knows to wait.
/// - Empty transcript + status missing → render "Audio no longer
///   in iCloud." — honest, not blame-tossing.
/// - Empty transcript + status downloaded → "(no transcript)" —
///   the recognizer ran and heard nothing.
/// - Empty transcript + nil status (status not yet checked) →
///   "(no transcript)" as the safe default; the .task will resolve
///   the status shortly and re-render.
@Suite
struct VoiceClipPanelDisplayTextTests {

    @Test func nonEmptyTranscript_renderedDirectly_regardlessOfStatus() {
        let text = VoiceClipPanel.displayText(transcript: "hello world", audioStatus: .downloading)
        #expect(text == "hello world")
    }

    @Test func nonEmptyTranscript_takesPriorityEvenOverMissing() {
        let text = VoiceClipPanel.displayText(transcript: "hello", audioStatus: .missing)
        #expect(text == "hello")
    }

    @Test func emptyTranscript_downloading_showsHonestDownloadingLabel() {
        let text = VoiceClipPanel.displayText(transcript: "", audioStatus: .downloading)
        #expect(text.contains("Downloading") || text.contains("downloading"))
    }

    @Test func emptyTranscript_notDownloaded_showsDownloadingLabel() {
        let text = VoiceClipPanel.displayText(transcript: "", audioStatus: .notDownloaded)
        #expect(text.contains("Downloading") || text.contains("downloading"))
    }

    @Test func nilTranscript_downloading_showsDownloadingLabel() {
        let text = VoiceClipPanel.displayText(transcript: nil, audioStatus: .downloading)
        #expect(text.contains("Downloading") || text.contains("downloading"))
    }

    @Test func emptyTranscript_missing_showsHonestMissingLabel() {
        let text = VoiceClipPanel.displayText(transcript: "", audioStatus: .missing)
        // Must NOT use blame-tossing language. Spec calls for "no
        // longer in iCloud" — the file's gone, not the user's fault.
        #expect(text.contains("no longer") || text.contains("not available"))
    }

    @Test func emptyTranscript_downloaded_showsNoTranscriptLabel() {
        let text = VoiceClipPanel.displayText(transcript: "", audioStatus: .downloaded)
        #expect(text == "(no transcript)")
    }

    @Test func emptyTranscript_nilStatus_defaultsToNoTranscript() {
        let text = VoiceClipPanel.displayText(transcript: "", audioStatus: nil)
        // Status hasn't been checked yet — safe default until the
        // .task lands the real status and triggers a re-render.
        #expect(text == "(no transcript)")
    }
}
