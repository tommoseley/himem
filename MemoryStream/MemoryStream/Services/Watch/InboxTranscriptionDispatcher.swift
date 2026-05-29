import Foundation

/// Pure decision surface for "given a `TranscriptionService.Outcome`,
/// should the inbox manifest mark this clip as `transcriptionAttempted`?"
///
/// Extracted from `WatchSessionDelegate.transcribePendingInboxClips`
/// 2026-05-29 after the hero-path bug where the prior code marked
/// every empty result as attempted — silently burning real clips
/// whose transcription failed for infrastructure reasons (model
/// install not yet complete, file open failed, transcriber threw).
///
/// **Rule:** only `.transcribed` flips the flag. Every other
/// outcome leaves the clip pending so the next sweep retries.
/// This means a corrupt audio file (`.fileUnreadable`) will be
/// re-attempted on every sweep, which is wasted work but not
/// data loss — better than marking it accidental forever and
/// losing the user's content.
///
/// Pure and stateless on purpose so the contract is testable
/// without spinning up the manifest or the transcription stack.
@available(iOS 26.0, *)
enum InboxTranscriptionDispatcher {

    /// `true` when the outcome represents a definitive answer from
    /// the recognizer (success or genuine silence). `false` for
    /// every transient failure — caller leaves the manifest row
    /// untouched so the next sweep retries.
    static func shouldMarkAttempted(for outcome: TranscriptionService.Outcome) -> Bool {
        if case .transcribed = outcome { return true }
        return false
    }

    /// The text to write into the manifest when marking attempted.
    /// Returns `""` for failure cases (caller shouldn't be writing
    /// at all in that path — see `shouldMarkAttempted` — but if it
    /// does, the empty string is the safe default).
    static func transcriptForMark(from outcome: TranscriptionService.Outcome) -> String {
        if case .transcribed(let r) = outcome { return r.text }
        return ""
    }
}
