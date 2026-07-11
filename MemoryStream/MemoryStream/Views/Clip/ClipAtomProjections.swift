import Foundation

/// Pure projections from `ClipDisplayModel` + `ClipRegister` into
/// register-specific renderable specs. Every atom render on every
/// surface routes through these three types — drift here rewrites
/// the chrome contract in one place. Tested at value-level
/// (`ClipAtomProjectionTests`) so the atom view stays a thin
/// wrapper around them.

// MARK: - Content projection

/// What the atom's content slot draws for a given `(content,
/// register)` combination. Voice/note in the two full-content
/// registers render the full transcript; voice/note in
/// `reflectiveCompact` render a **first-line preview** (which
/// vanishes when the container swaps to `.reflective` on expand —
/// CD's Slice 0 anti-double-print guarantee against the June/July
/// double-print bug documented in `Memory Detail · long-memory
/// navigation.md`).
///
/// Photo/video always project as `.media(description:)`; the
/// thumbnail is the content, and the description is the media
/// clip's *words* (`Captured Clips · session-first · spec.md`
/// July 11 bullet).
enum ClipContentProjection: Equatable {
    case transcriptFull(String)
    case transcriptPreview(String)
    case media(description: String?)

    /// Deterministic mapping — same input, same output. No `now`
    /// or side channels.
    static func project(content: ClipDisplayModel.Content, register: ClipRegister) -> ClipContentProjection {
        switch (content, register) {
        case (.transcript(let text), .reflectiveCompact):
            return .transcriptPreview(firstLinePreview(from: text))
        case (.transcript(let text), _):
            return .transcriptFull(text)
        case (.media(let description), _):
            return .media(description: description)
        }
    }

    /// The first "line" of a transcript — everything up to the
    /// first `.`, `?`, `!`, or newline. Trailing whitespace
    /// trimmed. `Memory Detail · long-memory navigation.md`
    /// §Compact: "media-icon · time · first-line-of-transcript ·
    /// chevron."
    ///
    /// If the text starts with a break/punctuation, the returned
    /// preview may be empty — that's honest and matches the
    /// spec's rule that the lead line never *invents* content.
    private static func firstLinePreview(from text: String) -> String {
        let separators = CharacterSet(charactersIn: ".?!\n")
        let firstPart = text.components(separatedBy: separators).first ?? text
        return firstPart.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Evidence projection

/// The play/evidence control the atom renders for a given `(model,
/// register)`. `.none` when the model has no `evidence` (photo,
/// note) OR when the register is `.reflectiveCompact` (spec: "none
/// on the row — expanding delegates to the reflective body").
enum ClipEvidenceProjection: Equatable {
    case none
    case compactPlay(durationString: String?)
    case namedPlay(label: String, durationString: String?)

    static func project(model: ClipDisplayModel, register: ClipRegister) -> ClipEvidenceProjection {
        // Compact: never draw evidence on the collapsed row. The
        // container's expand path swaps the atom to `.reflective`,
        // which draws the named-play form.
        if register == .reflectiveCompact { return .none }
        guard let evidence = model.evidence else { return .none }
        switch (evidence, register) {
        case (.audio(let d), .operational):
            return .compactPlay(durationString: d.map(formatShortDuration))
        case (.audio(let d), .reflective):
            return .namedPlay(label: "Original recording", durationString: d.map(formatShortDuration))
        case (.video(let d), .operational):
            return .compactPlay(durationString: d.map(formatShortDuration))
        case (.video(let d), .reflective):
            return .namedPlay(label: "Video", durationString: d.map(formatShortDuration))
        default:
            return .none
        }
    }
}

// MARK: - Timing projection

/// The header the atom draws above content. Register-specific: the
/// three cases don't overlap (operational is offset+duration,
/// reflective is date+time+place, reflectiveCompact is time-only +
/// leading media glyph). Nil fields for cases that don't apply.
struct ClipTimingProjection: Equatable {

    /// Operational offset from session start (`+128s` or `0:00`).
    let offsetString: String?

    /// Operational duration (`0:03`) — used alongside `offsetString`
    /// as `+128s · 0:03` or `0:00 · 0:03`.
    let durationString: String?

    /// Reflective composed header (`Sun May 17 · 6:12 PM · Bishop
    /// St, Bluffton`). Format matches `CaptureTimestampLabel`
    /// (verified at `ChronologicalCaptureStream.swift:842-890`)
    /// exactly — the reflective register reuses the existing view
    /// component in Slice 3's atom render; the projected string is
    /// for tests and for surfaces that need the string directly.
    let dateTimePlace: String?

    /// Reflective Compact time-only header (`6:12 PM`).
    let timeOnly: String?

    /// Reflective Compact leading media glyph — a projection of
    /// `model.media`, no new field per invariant #2.
    let mediaGlyph: ClipDisplayModel.Media?

    static func project(model: ClipDisplayModel, register: ClipRegister, now: Date = Date()) -> ClipTimingProjection {
        switch register {
        case .operational:
            return ClipTimingProjection(
                offsetString: formatOffset(from: model.sessionStart, to: model.capturedAt),
                durationString: durationForOffset(model),
                dateTimePlace: nil,
                timeOnly: nil,
                mediaGlyph: nil
            )
        case .reflective:
            return ClipTimingProjection(
                offsetString: nil,
                durationString: nil,
                dateTimePlace: formatDateTimePlace(date: model.capturedAt, place: model.placeName, now: now),
                timeOnly: nil,
                mediaGlyph: nil
            )
        case .reflectiveCompact:
            return ClipTimingProjection(
                offsetString: nil,
                durationString: nil,
                dateTimePlace: nil,
                timeOnly: formatTimeOnly(model.capturedAt),
                mediaGlyph: model.media
            )
        }
    }

    private static func durationForOffset(_ model: ClipDisplayModel) -> String? {
        switch model.evidence {
        case .audio(let d), .video(let d):
            return d.map(formatShortDuration)
        case .none:
            return nil
        }
    }
}

// MARK: - Shared formatters (module-private)

private func formatShortDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds)
    let m = total / 60
    let s = total % 60
    return String(format: "%d:%02d", m, s)
}

/// One operational offset notation — always `+Ns` delta-seconds
/// (T1 in `Clip model · spec.md` convergence checklist). Mixing
/// `0:00` and `+129s` on the same session was the drift the
/// checklist calls out. First clip prints `+0s`; sessionless
/// operational clips also print `+0s` (no session anchor to
/// delta against). Only ever seconds.
private func formatOffset(from sessionStart: Date?, to capturedAt: Date) -> String {
    guard let sessionStart else { return "+0s" }
    let delta = capturedAt.timeIntervalSince(sessionStart)
    if delta < 1 { return "+0s" }
    return "+\(Int(delta))s"
}

/// Reproduces `CaptureTimestampLabel`'s composed string:
/// `Sun May 17 · 6:12 PM · Bishop St, Bluffton`, with the year
/// suffix appended for non-current-year clips and the place suffix
/// omitted when nil. Sourced from
/// `ChronologicalCaptureStream.swift:842-890` — verified in
/// Slice 3's planning pass so the atom's reflective header matches
/// the existing surface exactly (no drift).
private func formatDateTimePlace(date: Date, place: String?, now: Date) -> String {
    let cal = Calendar.current
    let currentYear = cal.component(.year, from: now)
    let dateYear = cal.component(.year, from: date)
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = (dateYear == currentYear) ? "EEE MMM d" : "EEE MMM d, yyyy"
    let timeFormatter = DateFormatter()
    timeFormatter.dateFormat = "h:mm a"
    let dateStr = dateFormatter.string(from: date)
    let timeStr = timeFormatter.string(from: date)
    if let place, !place.isEmpty {
        return "\(dateStr) · \(timeStr) · \(place)"
    }
    return "\(dateStr) · \(timeStr)"
}

private func formatTimeOnly(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "h:mm a"
    return f.string(from: date)
}
