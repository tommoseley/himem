import Testing
import Foundation
@testable import HiMem

/// Money tests for `CompositionModel` — the shared summary primitive
/// every collection view (`ClipCollection`, session card meta,
/// memory card meta, transcript-header eyebrow) reads.
///
/// Slice 4 of the Clip Model convergence
/// (`docs/architecture/2026-07-11-clip-model-convergence-plan.md`).
/// The pure `CompositionModel.from(clips:)` computation is the
/// single source of truth for "how a collection summarises itself"
/// — drift here rewrites session-card meta, memory-card meta, and
/// the transcript header at once.
@Suite(.serialized)
struct ClipCompositionTests {

    // MARK: - Fixtures

    private func voice(capturedAt: Date, transcript: String = "hi", duration: TimeInterval = 3) -> ClipDisplayModel {
        ClipDisplayModel(
            id: UUID(),
            media: .voice,
            capturedAt: capturedAt,
            sessionStart: nil,
            placeName: nil,
            content: .transcript(transcript),
            evidence: .audio(duration: duration),
            thumbnailKey: nil,
            failed: false
        )
    }

    private func photo(capturedAt: Date, description: String? = nil) -> ClipDisplayModel {
        ClipDisplayModel(
            id: UUID(),
            media: .photo,
            capturedAt: capturedAt,
            sessionStart: nil,
            placeName: nil,
            content: .media(description: description),
            evidence: nil,
            thumbnailKey: ClipDisplayModel.ThumbnailKey(osIdentifier: "p", mediaType: .image),
            failed: false
        )
    }

    private func video(capturedAt: Date, description: String? = nil, duration: TimeInterval = 8) -> ClipDisplayModel {
        ClipDisplayModel(
            id: UUID(),
            media: .video,
            capturedAt: capturedAt,
            sessionStart: nil,
            placeName: nil,
            content: .media(description: description),
            evidence: .video(duration: duration),
            thumbnailKey: ClipDisplayModel.ThumbnailKey(osIdentifier: "v", mediaType: .video),
            failed: false
        )
    }

    private func note(capturedAt: Date, text: String) -> ClipDisplayModel {
        ClipDisplayModel(
            id: UUID(),
            media: .note,
            capturedAt: capturedAt,
            sessionStart: nil,
            placeName: nil,
            content: .transcript(text),
            evidence: nil,
            thumbnailKey: nil,
            failed: false
        )
    }

    // MARK: - Timespan

    /// A mixed 3-voice / 1-photo / 1-video sitting produces a
    /// timespan from the earliest to the latest capture. Locks the
    /// primary summary contract per the plan doc's money test.
    @Test func timespan_spans_earliest_to_latest_across_media_kinds() {
        let start = Date(timeIntervalSince1970: 1_720_000_000)
        let clips: [ClipDisplayModel] = [
            voice(capturedAt: start),
            voice(capturedAt: start.addingTimeInterval(60)),
            photo(capturedAt: start.addingTimeInterval(120)),
            video(capturedAt: start.addingTimeInterval(180)),
            voice(capturedAt: start.addingTimeInterval(240)),
        ]
        let comp = CompositionModel.from(clips: clips)
        #expect(comp.timespan?.start == start)
        #expect(comp.timespan?.end == start.addingTimeInterval(240))
    }

    /// Single-clip case: start == end (the summary reads "one
    /// moment," not a range).
    @Test func timespan_single_clip_start_equals_end() {
        let t = Date(timeIntervalSince1970: 1_720_000_000)
        let comp = CompositionModel.from(clips: [voice(capturedAt: t)])
        #expect(comp.timespan?.start == comp.timespan?.end)
    }

    /// Empty input: no timespan. The view chooses whether to render
    /// a placeholder or nothing; the model stays honest.
    @Test func timespan_empty_input_is_nil() {
        let comp = CompositionModel.from(clips: [])
        #expect(comp.timespan == nil)
    }

    // MARK: - Media counts

    @Test func counts_tally_by_media_kind() {
        let t = Date(timeIntervalSince1970: 1_720_000_000)
        let clips: [ClipDisplayModel] = [
            voice(capturedAt: t),
            voice(capturedAt: t.addingTimeInterval(60)),
            voice(capturedAt: t.addingTimeInterval(120)),
            photo(capturedAt: t.addingTimeInterval(180)),
            video(capturedAt: t.addingTimeInterval(240)),
        ]
        let comp = CompositionModel.from(clips: clips)
        #expect(comp.mediaCounts.voice == 3)
        #expect(comp.mediaCounts.photo == 1)
        #expect(comp.mediaCounts.video == 1)
        #expect(comp.mediaCounts.note == 0)
        #expect(comp.mediaCounts.total == 5)
    }

    @Test func counts_all_zero_for_empty_input() {
        let comp = CompositionModel.from(clips: [])
        #expect(comp.mediaCounts.total == 0)
        #expect(comp.mediaCounts.voice == 0)
        #expect(comp.mediaCounts.photo == 0)
        #expect(comp.mediaCounts.video == 0)
        #expect(comp.mediaCounts.note == 0)
    }

    // MARK: - Word count

    /// Word count sums transcript words from voice + note clips.
    /// Photo/video contribute zero (their description lives on the
    /// clip's evidence slot, not the collection's word count —
    /// mirrors how the JSX side counts).
    @Test func words_sum_transcript_words_from_voice_and_note() {
        let t = Date(timeIntervalSince1970: 1_720_000_000)
        let clips: [ClipDisplayModel] = [
            voice(capturedAt: t, transcript: "one two three"),           // 3
            voice(capturedAt: t.addingTimeInterval(60), transcript: "four five"), // 2
            photo(capturedAt: t.addingTimeInterval(120), description: "ignored words"), // 0
            note(capturedAt: t.addingTimeInterval(180), text: "six seven eight nine"), // 4
        ]
        let comp = CompositionModel.from(clips: clips)
        #expect(comp.words == 9)
    }

    /// A collection with only media/description clips has zero
    /// words — matches the spec's "transcript-header" role where
    /// word count is meaningless without transcripts.
    @Test func words_zero_when_only_media_clips() {
        let t = Date(timeIntervalSince1970: 1_720_000_000)
        let comp = CompositionModel.from(clips: [
            photo(capturedAt: t),
            video(capturedAt: t.addingTimeInterval(60)),
        ])
        #expect(comp.words == 0)
    }

    @Test func words_empty_input_is_zero() {
        let comp = CompositionModel.from(clips: [])
        #expect(comp.words == 0)
    }

    /// Whitespace-only transcripts don't count as words — matches
    /// the shipped word-count behavior of `EntryMapper`'s summary
    /// path (splitting on non-empty tokens).
    @Test func words_ignore_whitespace_only_transcripts() {
        let t = Date(timeIntervalSince1970: 1_720_000_000)
        let comp = CompositionModel.from(clips: [
            voice(capturedAt: t, transcript: "   "),
            note(capturedAt: t.addingTimeInterval(60), text: "\n\n\n"),
        ])
        #expect(comp.words == 0)
    }

    // MARK: - The full plan-doc money test (mixed 3-voice/1-photo/1-video)

    /// From the plan doc §Slice 4 · money test:
    ///   > pure `CompositionModel.from(clips:)` for a mixed 3-voice
    ///   > / 1-photo / 1-video sitting yields expected
    ///   > timespan/counts/words.
    @Test func mixed_sitting_yields_expected_timespan_counts_words() {
        let start = Date(timeIntervalSince1970: 1_720_000_000)
        let clips: [ClipDisplayModel] = [
            voice(capturedAt: start,                        transcript: "Ben said the Basque cheesecake"),      // 5 words
            voice(capturedAt: start.addingTimeInterval(60), transcript: "starts hot then drops to two fifty"),  // 7 words
            voice(capturedAt: start.addingTimeInterval(180), transcript: "no performance just how it works"),   // 6 words
            photo(capturedAt: start.addingTimeInterval(120), description: "the finished cake"),                 // 0 (media)
            video(capturedAt: start.addingTimeInterval(240), description: "him plating"),                       // 0 (media)
        ]
        let comp = CompositionModel.from(clips: clips)
        #expect(comp.timespan?.start == start)
        #expect(comp.timespan?.end == start.addingTimeInterval(240))
        #expect(comp.mediaCounts.voice == 3)
        #expect(comp.mediaCounts.photo == 1)
        #expect(comp.mediaCounts.video == 1)
        #expect(comp.mediaCounts.note == 0)
        #expect(comp.mediaCounts.total == 5)
        #expect(comp.words == 5 + 7 + 6)
    }

    // MARK: - MediaCounts helper

    /// `MediaCounts.nonZeroKinds` returns only the kinds that
    /// actually have a count > 0 — the view iterates this to
    /// render the media-count row without hard-coding all four.
    @Test func nonZeroKinds_lists_only_present_media() {
        let counts = MediaCounts(voice: 3, photo: 1, video: 0, note: 0)
        let kinds = counts.nonZeroKinds
        #expect(kinds.count == 2)
        #expect(kinds.first?.kind == .voice)
        #expect(kinds.first?.count == 3)
        #expect(kinds.last?.kind == .photo)
        #expect(kinds.last?.count == 1)
    }

    @Test func nonZeroKinds_ordering_is_deterministic() {
        // Same content → same output → same render order.
        let a = MediaCounts(voice: 1, photo: 1, video: 1, note: 1)
        let b = MediaCounts(voice: 1, photo: 1, video: 1, note: 1)
        #expect(a.nonZeroKinds.map(\.kind) == b.nonZeroKinds.map(\.kind))
    }
}
