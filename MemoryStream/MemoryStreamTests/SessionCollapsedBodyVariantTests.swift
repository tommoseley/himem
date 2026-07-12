import Testing
import Foundation
@testable import HiMem

/// Money tests for the collapsed-card body variant on Captured Clips.
///
/// The bug (2026-05-29): a session containing exactly one accidental
/// clip (transcript empty, transcriptionAttempted true) was rendering
/// "Transcribing…" in the body AND "1 clip auto-excluded · no speech"
/// in the footer simultaneously. The two strings contradict each
/// other — a clip cannot be "still in flight" AND "ran and found
/// nothing" at the same moment.
///
/// Root cause: `joinedPreview` returns nil whenever no clip has a
/// non-empty transcript. The collapsed body's `else` branch then
/// renders the generic "Transcribing…" placeholder without checking
/// whether the session is actually all-accidental.
///
/// Fix: expose a `CollapsedBodyVariant` computed property on
/// `ClipGroup` that the view consumes verbatim — `.preview(text)`
/// when there's something to show, `.allAccidental` when every clip
/// has been attempted and produced nothing (footer takes over the
/// messaging), `.transcribing` only when at least one clip is still
/// genuinely pending.
@MainActor
@Suite(.serialized)
struct SessionCollapsedBodyVariantTests {

    private func makeClip(
        transcript: String,
        attempted: Bool,
        capturedAt: Date = Date()
    ) -> InboxClip {
        InboxClip(
            clipId: UUID(),
            capturedAt: capturedAt,
            duration: 10,
            transcript: transcript,
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: "test-\(UUID().uuidString).caf",
            transcriptionAttempted: attempted,
            rollGroupId: nil
        )
    }

    private func makeGroup(_ clips: [InboxClip]) -> ClipGroup {
        ClipGroup(clips: clips)
    }

    // MARK: - .preview when a clip has text

    @Test func singleClipWithTranscript_rendersPreview() {
        let group = makeGroup([makeClip(transcript: "hello world", attempted: true)])
        guard case .preview(let text) = group.collapsedBodyVariant else {
            Issue.record("Expected .preview, got \(group.collapsedBodyVariant)")
            return
        }
        #expect(text == "hello world")
    }

    @Test func mixOfTranscribedAndAccidental_rendersOnlyTheTranscribed() {
        let group = makeGroup([
            makeClip(transcript: "real thought", attempted: true),
            makeClip(transcript: "", attempted: true)
        ])
        guard case .preview(let text) = group.collapsedBodyVariant else {
            Issue.record("Expected .preview, got \(group.collapsedBodyVariant)")
            return
        }
        #expect(text == "real thought")
    }

    /// Money test for `Clip model · spec.md` §Model (July 12 2026):
    /// > "preview of the FIRST clip's words (capture order, never a
    /// > concatenation of all clips)."
    ///
    /// The pre-July-12 grouper joined every clip's transcript with
    /// " … " into a single preview string — a stack of quoted lines
    /// that read out of order (the grouper stores clips newest-first
    /// while a reader expects the sitting to unfold oldest-first).
    /// Dogfood pain: a three-clip sitting where clip 3 said "and
    /// finally…" opened the preview, not "the whole thing started
    /// like this…" from clip 1.
    ///
    /// This test fails pre-fix because the pre-fix preview reads
    /// "third … second … first" (concatenated in array order), and
    /// passes post-fix because the preview reads "first" — the
    /// earliest clip's words alone.
    @Test func multipleClipsWithTranscripts_previewShowsFirstClipOnly_notConcatenation() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        // Grouper stores clips newest-first — mirror that array
        // order in the fixture so `ClipGroup(clips:)` receives what
        // production would hand it.
        let group = makeGroup([
            makeClip(transcript: "third", attempted: true, capturedAt: t0.addingTimeInterval(240)),
            makeClip(transcript: "second", attempted: true, capturedAt: t0.addingTimeInterval(120)),
            makeClip(transcript: "first", attempted: true, capturedAt: t0)
        ])
        guard case .preview(let text) = group.collapsedBodyVariant else {
            Issue.record("Expected .preview, got \(group.collapsedBodyVariant)")
            return
        }
        #expect(text == "first",
                "preview must be the FIRST clip's words in capture order — never a concatenation")
    }

    /// When the earliest clip has no transcript, the preview falls
    /// through to the next earliest clip with words. Same
    /// no-concatenation rule — just picking the earliest fragment,
    /// never joining across clips.
    @Test func firstClipMissingTranscript_previewFallsThroughToNextEarliest() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let group = makeGroup([
            makeClip(transcript: "third", attempted: true, capturedAt: t0.addingTimeInterval(240)),
            makeClip(transcript: "middle words", attempted: true, capturedAt: t0.addingTimeInterval(120)),
            makeClip(transcript: "", attempted: true, capturedAt: t0)
        ])
        guard case .preview(let text) = group.collapsedBodyVariant else {
            Issue.record("Expected .preview, got \(group.collapsedBodyVariant)")
            return
        }
        #expect(text == "middle words",
                "empty earliest → fall through to the next earliest clip with words — still no join")
    }

    // MARK: - .allAccidental — the bug case

    /// THE BUG: one clip, attempted, empty transcript. Pre-fix
    /// rendered "Transcribing…" alongside "1 clip auto-excluded ·
    /// no speech." Post-fix must report `.allAccidental` so the view
    /// shows only the accidental note.
    @Test func singleAccidentalClip_isAllAccidental_notTranscribing() {
        let group = makeGroup([makeClip(transcript: "", attempted: true)])
        #expect(group.collapsedBodyVariant == .allAccidental)
    }

    @Test func multipleAccidentalClips_isAllAccidental() {
        let group = makeGroup([
            makeClip(transcript: "", attempted: true),
            makeClip(transcript: "", attempted: true),
            makeClip(transcript: "", attempted: true)
        ])
        #expect(group.collapsedBodyVariant == .allAccidental)
    }

    // MARK: - .transcribing when at least one clip is still pending

    @Test func singlePendingClip_rendersTranscribing() {
        // Empty transcript, NOT yet attempted — recognizer still
        // in flight (or queued for the next sweep). This is the
        // legitimate "Transcribing…" state and must survive the fix.
        let group = makeGroup([makeClip(transcript: "", attempted: false)])
        #expect(group.collapsedBodyVariant == .transcribing)
    }

    @Test func mixOfPendingAndAccidental_rendersTranscribing() {
        // One clip is still pending, one already came back empty.
        // The session is not "all accidental" — there's still hope
        // for the pending clip — so render Transcribing… until
        // the pending one resolves.
        let group = makeGroup([
            makeClip(transcript: "", attempted: false),
            makeClip(transcript: "", attempted: true)
        ])
        #expect(group.collapsedBodyVariant == .transcribing)
    }
}
