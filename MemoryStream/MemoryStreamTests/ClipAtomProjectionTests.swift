import Testing
import Foundation
@testable import HiMem

/// Money tests for the pure projections that drive `ClipAtomView` —
/// content, timing, and evidence transformations from
/// `ClipDisplayModel` + `ClipRegister` into renderable specs.
///
/// Slice 3 of the Clip Model convergence
/// (`docs/architecture/2026-07-11-clip-model-convergence-plan.md`).
/// Every atom render on every surface flows through these three
/// projections — drift here rewrites the chrome contract in one
/// place. Test coverage: 4 media × 3 registers = 12 cells for
/// content and evidence, plus the 13th anti-double-print assertion
/// CD locked in Slice 0.
@Suite(.serialized)
struct ClipAtomProjectionTests {

    // MARK: - Fixtures

    private func voiceModel(transcript: String = "Ben said the Basque cheesecake. Then he explained the temperature.") -> ClipDisplayModel {
        ClipDisplayModel(
            id: UUID(),
            media: .voice,
            capturedAt: Date(timeIntervalSince1970: 1_720_000_000),
            sessionStart: Date(timeIntervalSince1970: 1_720_000_000),
            placeName: "Bishop St, Bluffton",
            content: .transcript(transcript),
            evidence: .audio(duration: 42),
            thumbnailKey: nil,
            failed: false
        )
    }

    private func photoModel(description: String? = nil) -> ClipDisplayModel {
        ClipDisplayModel(
            id: UUID(),
            media: .photo,
            capturedAt: Date(timeIntervalSince1970: 1_720_000_000),
            sessionStart: Date(timeIntervalSince1970: 1_720_000_000),
            placeName: "Bishop St, Bluffton",
            content: .media(description: description),
            evidence: nil,
            thumbnailKey: ClipDisplayModel.ThumbnailKey(osIdentifier: "photo.jpg", mediaType: .image),
            failed: false
        )
    }

    private func videoModel(description: String? = nil) -> ClipDisplayModel {
        ClipDisplayModel(
            id: UUID(),
            media: .video,
            capturedAt: Date(timeIntervalSince1970: 1_720_000_000),
            sessionStart: Date(timeIntervalSince1970: 1_720_000_000),
            placeName: "Bishop St, Bluffton",
            content: .media(description: description),
            evidence: .video(duration: 8),
            thumbnailKey: ClipDisplayModel.ThumbnailKey(osIdentifier: "video.mov", mediaType: .video),
            failed: false
        )
    }

    private func noteModel(text: String = "Sourdough starter needs feeding") -> ClipDisplayModel {
        ClipDisplayModel(
            id: UUID(),
            media: .note,
            capturedAt: Date(timeIntervalSince1970: 1_720_000_000),
            sessionStart: Date(timeIntervalSince1970: 1_720_000_000),
            placeName: nil,
            content: .transcript(text),
            evidence: nil,
            thumbnailKey: nil,
            failed: false
        )
    }

    // MARK: - Content projection — 12-cell matrix

    // Voice content: transcriptFull in operational + reflective, transcriptPreview in reflectiveCompact.

    @Test func voice_content_operational_isFullTranscript() {
        let p = ClipContentProjection.project(content: voiceModel().content, register: .operational)
        #expect(p == .transcriptFull("Ben said the Basque cheesecake. Then he explained the temperature."))
    }

    @Test func voice_content_reflective_isFullTranscript() {
        let p = ClipContentProjection.project(content: voiceModel().content, register: .reflective)
        #expect(p == .transcriptFull("Ben said the Basque cheesecake. Then he explained the temperature."))
    }

    /// **The 13th anti-double-print assertion (CD, Slice 0).**
    /// `reflectiveCompact` projects a first-line preview from the
    /// transcript. `reflective` (above) projects the full transcript.
    /// When the container swaps registers on Compact→Full expand,
    /// the preview line vanishes because the atom's `reflective`
    /// output has no preview cell — closes the double-print bug
    /// documented in `Memory Detail · long-memory navigation.md`
    /// (build bug seen June 9 *and* July 11).
    @Test func voice_content_reflectiveCompact_isFirstLinePreview() {
        let p = ClipContentProjection.project(content: voiceModel().content, register: .reflectiveCompact)
        #expect(p == .transcriptPreview("Ben said the Basque cheesecake"))
    }

    // Note content: same shape as voice (transcript-based).

    @Test func note_content_operational_isFullTranscript() {
        let p = ClipContentProjection.project(content: noteModel().content, register: .operational)
        #expect(p == .transcriptFull("Sourdough starter needs feeding"))
    }

    @Test func note_content_reflective_isFullTranscript() {
        let p = ClipContentProjection.project(content: noteModel().content, register: .reflective)
        #expect(p == .transcriptFull("Sourdough starter needs feeding"))
    }

    @Test func note_content_reflectiveCompact_isFirstLinePreview() {
        let p = ClipContentProjection.project(content: noteModel().content, register: .reflectiveCompact)
        #expect(p == .transcriptPreview("Sourdough starter needs feeding"))
    }

    // Photo content: media with optional description in all three registers.

    @Test func photo_content_operational_isMedia() {
        let p = ClipContentProjection.project(content: photoModel(description: "my new camera").content, register: .operational)
        #expect(p == .media(description: "my new camera"))
    }

    @Test func photo_content_reflective_isMedia() {
        let p = ClipContentProjection.project(content: photoModel(description: "my new camera").content, register: .reflective)
        #expect(p == .media(description: "my new camera"))
    }

    @Test func photo_content_reflectiveCompact_isMedia() {
        let p = ClipContentProjection.project(content: photoModel().content, register: .reflectiveCompact)
        #expect(p == .media(description: nil))
    }

    // Video content: same shape as photo.

    @Test func video_content_operational_isMedia() {
        let p = ClipContentProjection.project(content: videoModel().content, register: .operational)
        #expect(p == .media(description: nil))
    }

    @Test func video_content_reflective_isMedia() {
        let p = ClipContentProjection.project(content: videoModel().content, register: .reflective)
        #expect(p == .media(description: nil))
    }

    @Test func video_content_reflectiveCompact_isMedia() {
        let p = ClipContentProjection.project(content: videoModel().content, register: .reflectiveCompact)
        #expect(p == .media(description: nil))
    }

    // MARK: - Evidence projection — 12-cell matrix

    // Voice evidence: compactPlay operational, namedPlay reflective, none reflectiveCompact.

    @Test func voice_evidence_operational_isCompactPlay() {
        let p = ClipEvidenceProjection.project(model: voiceModel(), register: .operational)
        #expect(p == .compactPlay(durationString: "0:42"))
    }

    @Test func voice_evidence_reflective_isNamedPlay() {
        let p = ClipEvidenceProjection.project(model: voiceModel(), register: .reflective)
        #expect(p == .namedPlay(label: "Original recording", durationString: "0:42"))
    }

    /// `reflectiveCompact` renders no evidence on the row — spec
    /// §Chrome table row: "none on the row (expanding delegates to
    /// the reflective body, which carries Play)."
    @Test func voice_evidence_reflectiveCompact_isNone() {
        let p = ClipEvidenceProjection.project(model: voiceModel(), register: .reflectiveCompact)
        #expect(p == .none)
    }

    // Video evidence: same shape as voice, with "Video" label instead of "Original recording."

    @Test func video_evidence_operational_isCompactPlay() {
        let p = ClipEvidenceProjection.project(model: videoModel(), register: .operational)
        #expect(p == .compactPlay(durationString: "0:08"))
    }

    @Test func video_evidence_reflective_isNamedPlay() {
        let p = ClipEvidenceProjection.project(model: videoModel(), register: .reflective)
        #expect(p == .namedPlay(label: "Video", durationString: "0:08"))
    }

    @Test func video_evidence_reflectiveCompact_isNone() {
        let p = ClipEvidenceProjection.project(model: videoModel(), register: .reflectiveCompact)
        #expect(p == .none)
    }

    // Photo evidence: always none (thumbnail IS the evidence).

    @Test func photo_evidence_is_none_in_all_registers() {
        for register in ClipRegister.allCases {
            let p = ClipEvidenceProjection.project(model: photoModel(), register: register)
            #expect(p == .none, "photo evidence must be .none in \(register)")
        }
    }

    // Note evidence: always none (text IS the clip).

    @Test func note_evidence_is_none_in_all_registers() {
        for register in ClipRegister.allCases {
            let p = ClipEvidenceProjection.project(model: noteModel(), register: register)
            #expect(p == .none, "note evidence must be .none in \(register)")
        }
    }

    // MARK: - Timing projection — register-specific shape

    /// Operational timing = offset + duration (`+128s · 0:03` for the
    /// second clip in a session; `0:00 · 0:03` for the first).
    @Test func timing_operational_is_offset_form() {
        let sessionStart = Date(timeIntervalSince1970: 1_720_000_000)
        let clip = ClipDisplayModel(
            id: UUID(),
            media: .voice,
            capturedAt: sessionStart.addingTimeInterval(128),
            sessionStart: sessionStart,
            placeName: nil,
            content: .transcript("hi"),
            evidence: .audio(duration: 3),
            thumbnailKey: nil,
            failed: false
        )
        let p = ClipTimingProjection.project(model: clip, register: .operational)
        #expect(p.offsetString == "+128s")
        #expect(p.durationString == "0:03")
        #expect(p.dateTimePlace == nil)
        #expect(p.timeOnly == nil)
    }

    /// Reflective timing = full `Sun May 17 · 6:12 PM · Bishop St,
    /// Bluffton` — matches the format `CaptureTimestampLabel`
    /// already ships at `ChronologicalCaptureStream.swift:842-890`.
    @Test func timing_reflective_is_full_dateTimePlace() {
        let p = ClipTimingProjection.project(model: voiceModel(), register: .reflective)
        #expect(p.dateTimePlace != nil, "reflective must produce a full date+time+place string")
        #expect(p.offsetString == nil)
        #expect(p.timeOnly == nil)
        // Format verification: contains all three parts joined by " · "
        let s = p.dateTimePlace ?? ""
        #expect(s.contains(" · "), "reflective format joins with ' · '")
        #expect(s.contains("Bishop St, Bluffton"), "reflective includes placeName when present")
    }

    /// Reflective timing without a place omits the trailing `·
    /// place` (matches `CaptureTimestampLabel`'s nil-guard).
    @Test func timing_reflective_without_place_omits_place() {
        let clip = ClipDisplayModel(
            id: UUID(),
            media: .voice,
            capturedAt: Date(timeIntervalSince1970: 1_720_000_000),
            sessionStart: nil,
            placeName: nil,
            content: .transcript("hi"),
            evidence: .audio(duration: 3),
            thumbnailKey: nil,
            failed: false
        )
        let p = ClipTimingProjection.project(model: clip, register: .reflective)
        let s = p.dateTimePlace ?? ""
        #expect(!s.contains("Bishop"), "no place → no place suffix")
        // Still has date and time
        let dots = s.components(separatedBy: " · ").count
        #expect(dots == 2, "date · time with no place → two parts, one separator")
    }

    /// Reflective Compact timing = time only (`6:12 PM`) + a leading
    /// media-glyph projection. Long-memory nav spec: "media-icon ·
    /// time · first-line · chevron" for the collapsed row.
    @Test func timing_reflectiveCompact_is_time_only_with_glyph() {
        let p = ClipTimingProjection.project(model: voiceModel(), register: .reflectiveCompact)
        #expect(p.timeOnly != nil, "reflectiveCompact must produce a time-only string")
        #expect(p.mediaGlyph == .voice, "reflectiveCompact carries the media kind for the leading glyph")
        #expect(p.offsetString == nil)
        #expect(p.dateTimePlace == nil)
        // Format check
        let s = p.timeOnly ?? ""
        #expect(s.contains("AM") || s.contains("PM"), "time-only format uses 12-hour clock")
    }

    /// Compact's media glyph is a projection of `model.media` (no
    /// new field). Invariant #2 from Slice 0's guardrail: Compact
    /// shares the same `ClipDisplayModel` as the other two — if a
    /// Compact-only field ever appears, this test won't need to
    /// change but its intent gets undermined.
    @Test func timing_reflectiveCompact_glyph_projects_media_kind() {
        for media in [ClipDisplayModel.Media.voice, .photo, .video, .note] {
            let clip = ClipDisplayModel(
                id: UUID(),
                media: media,
                capturedAt: Date(timeIntervalSince1970: 1_720_000_000),
                sessionStart: nil,
                placeName: nil,
                content: media == .photo || media == .video ? .media(description: nil) : .transcript("x"),
                evidence: media == .voice ? .audio(duration: 1) : (media == .video ? .video(duration: 1) : nil),
                thumbnailKey: nil,
                failed: false
            )
            let p = ClipTimingProjection.project(model: clip, register: .reflectiveCompact)
            #expect(p.mediaGlyph == media, "compact glyph projection should mirror media kind")
        }
    }

    // MARK: - Edge cases

    /// A note with a multi-line body previews as its first line only
    /// — closes the "wall of text on the compact row" failure mode.
    @Test func note_multiline_body_previews_first_line_only() {
        let p = ClipContentProjection.project(
            content: .transcript("First line here.\nSecond line here.\nThird."),
            register: .reflectiveCompact
        )
        #expect(p == .transcriptPreview("First line here"))
    }

    /// An empty transcript projects to empty preview (not crash, not
    /// placeholder). The atom's view chooses whether to render
    /// "(no transcript)" or the transcribing spinner based on other
    /// flags; the projection stays pure.
    @Test func empty_transcript_previews_as_empty_string() {
        let p = ClipContentProjection.project(
            content: .transcript(""),
            register: .reflectiveCompact
        )
        #expect(p == .transcriptPreview(""))
    }
}
