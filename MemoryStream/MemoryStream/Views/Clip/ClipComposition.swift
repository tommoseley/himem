import SwiftUI

/// The shared summary primitive every collection surface reads:
/// **timespan · media counts · word count**. Session cards use
/// timespan + counts; memory cards use the same; transcript-header
/// eyebrows add the word count.
///
/// Slice 4 of the Clip Model convergence
/// (`docs/architecture/2026-07-11-clip-model-convergence-plan.md`).
/// `CompositionModel.from(clips:)` is the pure computation — one
/// place to change how a collection summarises itself. `ClipComposition`
/// is the view that renders it.

// MARK: - Model

/// Value-typed snapshot of a collection's summary. Derived from
/// `[ClipDisplayModel]` via `CompositionModel.from(clips:)`; every
/// consumer reads the same fields off the same computation.
struct CompositionModel: Equatable {

    /// The `earliestCapturedAt ... latestCapturedAt` span of the
    /// collection. Nil when the collection is empty.
    let timespan: Timespan?

    /// Per-media-kind tallies. Zero-filled for kinds not present;
    /// use `nonZeroKinds` for iterating the view.
    let mediaCounts: MediaCounts

    /// Sum of transcript words across voice + note clips. Zero for
    /// media-only collections. Consumed only by the transcript-
    /// header context (`Transcript · N clips · M words`); other
    /// consumers ignore it.
    let words: Int

    struct Timespan: Equatable, Hashable {
        let start: Date
        let end: Date
    }

    /// Compute the summary from a list of clips. Deterministic —
    /// same input, same output. No `now`, no side channels.
    static func from(clips: [ClipDisplayModel]) -> CompositionModel {
        guard !clips.isEmpty else {
            return CompositionModel(timespan: nil, mediaCounts: MediaCounts.zero, words: 0)
        }
        let times = clips.map(\.capturedAt)
        let timespan = Timespan(
            start: times.min() ?? .distantPast,
            end: times.max() ?? .distantFuture
        )
        var voice = 0, photo = 0, video = 0, note = 0
        var wordSum = 0
        for clip in clips {
            switch clip.media {
            case .voice: voice += 1
            case .photo: photo += 1
            case .video: video += 1
            case .note:  note += 1
            }
            if case .transcript(let text) = clip.content {
                wordSum += countWords(in: text)
            }
        }
        return CompositionModel(
            timespan: timespan,
            mediaCounts: MediaCounts(voice: voice, photo: photo, video: video, note: note),
            words: wordSum
        )
    }

    /// Whitespace-separated token count; empty and whitespace-only
    /// strings return 0. Matches the shipped word-count semantics
    /// of `EntryMapper`'s summary path so `Transcript · N clips ·
    /// M words` stays honest.
    private static func countWords(in text: String) -> Int {
        text
            .split(whereSeparator: \.isWhitespace)
            .filter { !$0.isEmpty }
            .count
    }
}

// MARK: - MediaCounts

/// Per-media-kind tally. `total` is the sum across all four. Used
/// by `MediaRow` — the shared media-count component — and by every
/// consumer that needs "N clips" without caring which kinds.
struct MediaCounts: Equatable, Hashable {
    let voice: Int
    let photo: Int
    let video: Int
    let note: Int

    static let zero = MediaCounts(voice: 0, photo: 0, video: 0, note: 0)

    var total: Int { voice + photo + video + note }

    /// Kinds present in the collection with a count > 0, in the
    /// spec's rendering order (voice → photo → video → note).
    /// Deterministic — the view iterates this to render only kinds
    /// that actually appear, without hard-coding all four.
    var nonZeroKinds: [(kind: ClipDisplayModel.Media, count: Int)] {
        var out: [(kind: ClipDisplayModel.Media, count: Int)] = []
        if voice > 0 { out.append((.voice, voice)) }
        if photo > 0 { out.append((.photo, photo)) }
        if video > 0 { out.append((.video, video)) }
        if note > 0  { out.append((.note, note)) }
        return out
    }
}

// MARK: - View

/// The composition summary line — reads a `CompositionModel` and
/// renders it in the given `ClipRegister`. Consumers:
///   - Session cards (operational): `10:32 AM · 3 clips · 0:06`
///   - Memory cards (reflective): same shape, roomier chrome
///   - Transcript-header eyebrow: adds `· 3,581 words`
///
/// Register-aware font and spacing only; the model shape is
/// identical across registers.
struct ClipComposition: View {

    let model: CompositionModel
    let register: ClipRegister
    /// When true, render the word count (`· M words`). Set by
    /// transcript-header callsites; session/memory cards leave it
    /// false.
    var showsWordCount: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if let ts = model.timespan {
                Text(TimespanFormatter.format(ts))
                    .monospacedDigit()
                separator
            }
            Text(clipCountString)
            if showsWordCount, model.words > 0 {
                separator
                Text("\(model.words) words")
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .font(font)
        .foregroundStyle(Crucible.Color.ink3)
    }

    @ViewBuilder
    private var separator: some View {
        Text("·")
            .foregroundStyle(Crucible.Color.ink4)
    }

    private var clipCountString: String {
        let n = model.mediaCounts.total
        return n == 1 ? "1 clip" : "\(n) clips"
    }

    private var font: Font {
        switch register {
        case .operational:      return .system(size: 12, weight: .medium)
        case .reflective:       return .system(size: 13, weight: .medium)
        case .reflectiveCompact: return .system(size: 11, weight: .medium)
        }
    }
}

// MARK: - Timespan formatter (pure)

enum TimespanFormatter {
    static func format(_ ts: CompositionModel.Timespan) -> String {
        let cal = Calendar.current
        let sameDay = cal.isDate(ts.start, inSameDayAs: ts.end)
        if ts.start == ts.end {
            return timeFormatter.string(from: ts.start)
        }
        if sameDay {
            return "\(timeFormatter.string(from: ts.start))–\(timeFormatter.string(from: ts.end))"
        }
        // Cross-day — include short date on both sides.
        let startDay = dateFormatter.string(from: ts.start)
        let endDay = dateFormatter.string(from: ts.end)
        return "\(startDay) · \(timeFormatter.string(from: ts.start)) – \(endDay) · \(timeFormatter.string(from: ts.end))"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}

// MARK: - MediaRow (shared media-count component)

/// The `🎙3 📷1 🎦1` inline row. `ClipComposition` reads
/// `mediaCounts` and hands them off; other surfaces (memory card
/// summary line) reuse this component directly.
///
/// SF Symbols only, no emoji (Crucible rule §Voice — no emoji in
/// specimens; the JSX side uses emoji as a mock convention only).
struct MediaRow: View {
    let counts: MediaCounts
    var iconSize: CGFloat = 12
    var textSize: CGFloat = 12

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(counts.nonZeroKinds.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 3) {
                    Image(systemName: sfSymbol(for: entry.kind))
                        .font(.system(size: iconSize))
                    Text("\(entry.count)")
                        .font(.system(size: textSize, weight: .medium))
                        .monospacedDigit()
                }
                .foregroundStyle(Crucible.Color.ink3)
            }
        }
    }

    /// Canonical media glyphs — matches
    /// `EntryCardView.MediaGlyphRow` on the memory-card side.
    /// Voice reads as a waveform (evidence-of-a-recording), not
    /// a microphone (`mic.*` = the input-mode affordance
    /// elsewhere in the app: search's voice button, the
    /// PermissionWizard's mic-permission cell). Same discipline
    /// for photo/video/note — unfilled, matching the memory
    /// side. Sync 2026-07-11 per Tom's ask "these are all
    /// supposed to be identical."
    private func sfSymbol(for kind: ClipDisplayModel.Media) -> String {
        switch kind {
        case .voice: return "waveform"
        case .photo: return "camera"
        case .video: return "video"
        case .note:  return "text.alignleft"
        }
    }
}
