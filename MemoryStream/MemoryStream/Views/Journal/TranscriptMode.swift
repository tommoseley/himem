import Foundation

/// View-state for the Memory Detail transcript section. The Full ⇄ Compact
/// toggle lets long memories open as a scannable index (Compact) rather
/// than as a continuous wall of clip cards (Full). Short memories never
/// see the toggle and always render Full.
///
/// Design source of truth:
/// `docs/design/screens-memory-detail.jsx` §"Long memory · Full ⇄ Compact"
/// (Tom 2026-06-09). Thresholds locked there:
///
///   - More than 6 voice+note clips, OR
///   - More than 1,500 words across those clips' transcripts/text.
///
/// Either condition earns the toggle AND flips the default opening mode
/// from `.full` to `.compact`. Word count excludes photo descriptions —
/// the Compact index is a transcript-of-spoken-or-typed-content scan.
enum TranscriptMode: String, Hashable, CaseIterable, Sendable {
    case full
    case compact
}

/// Two questions the spec answers separately (Tom 2026-06-09, locked
/// in `docs/design/Memory Detail · long-memory navigation.md`):
///
/// 1. **Does the header + Full/Compact toggle appear?** A memory with
///    more than one clip earns the header — an index is meaningful
///    exactly when there's more than one thing to index. There is no
///    word-count gate on visibility; the prior `> 1,500 words` rule
///    was deleted as needless magic.
/// 2. **Which mode opens by default?** Size-driven: long memories open
///    in Compact (scannable index), short multi-clip memories open in
///    Full (continuous read). `> 6 clips` **or** `> 1,500 words` flips
///    the default to Compact.
enum TranscriptModeThreshold {
    /// Default flips to Compact once `clipCount > minClips` — i.e. ≥7.
    static let minClips = 6

    /// Default flips to Compact once `wordCount > minWords` — i.e. ≥1,501.
    static let minWords = 1_500

    /// True when the header + toggle should be rendered. The eyebrow
    /// + Compact mode are only meaningful with something to scan, so
    /// single-clip memories don't see the control at all.
    static func headerShown(clipCount: Int) -> Bool {
        clipCount > 1
    }

    /// True when a long memory should open in Compact by default.
    /// Independent of `headerShown` (a 2-clip 2,000-word memory shows
    /// the toggle AND opens in Compact; a 3-clip 200-word memory shows
    /// the toggle but opens in Full).
    static func opensCompact(clipCount: Int, wordCount: Int) -> Bool {
        clipCount > minClips || wordCount > minWords
    }

    static func defaultMode(clipCount: Int, wordCount: Int) -> TranscriptMode {
        opensCompact(clipCount: clipCount, wordCount: wordCount) ? .compact : .full
    }
}

/// Session-only memory of the user's transcript-mode choice per entry.
/// Lives in process memory only — a cold launch resets every entry back
/// to its threshold-driven default. Deliberate launch-scope cut: the
/// proper home is a per-entity UX metadata blob on the Memory model,
/// planned post-launch (see memory note `project_ux_metadata_blob`).
///
/// What "session" buys us: the common "tap into Full to read, scroll
/// down to Mentions, tap Back, navigate away and back" pattern keeps
/// the user's Full choice during their reading session. What it
/// doesn't: cross-launch persistence and cross-device sync — both
/// require a real DB/CloudKit attribute and CloudKit-schema ceremony
/// we're deferring past v1.
@MainActor
final class TranscriptModeSessionStore {
    static let shared = TranscriptModeSessionStore()
    private var storage: [UUID: TranscriptMode] = [:]

    private init() {}

    func mode(for entryId: UUID) -> TranscriptMode? {
        storage[entryId]
    }

    func set(_ mode: TranscriptMode, for entryId: UUID) {
        storage[entryId] = mode
    }

    /// Forgets every entry's mode. Intended for tests; production has no
    /// reason to call this — the store dies with the process anyway.
    func clearAll() {
        storage.removeAll()
    }
}

/// Word-count helper for the transcript section header. Counts words
/// across each voice clip's `transcript` and each note's `text`. Photo
/// and video `mediaDescription` are intentionally excluded — the
/// Compact index is a *transcript* scan, and surfacing photo-description
/// words there would inflate the count for memories that are mostly
/// images (per design decision A, Tom 2026-06-09).
///
/// Tokenization is whitespace-and-newline split; punctuation stays
/// glued to the preceding word. That matches a casual reader's count
/// of "how many words is this presentation" and is locale-agnostic.
enum TranscriptWordCount {
    static func count(transcriptsAndNotes items: [MediaDisplayItem]) -> Int {
        var total = 0
        for item in items {
            let source: String?
            switch item.mediaType {
            case .voice: source = item.transcript
            case .note:  source = item.text
            case .image, .video: source = nil
            }
            guard let text = source, !text.isEmpty else { continue }
            total += text.split { $0.isWhitespace || $0.isNewline }.count
        }
        return total
    }

    /// Number of clips eligible for the Compact index — voice + note
    /// MediaReferences only. Photos and videos don't appear in the
    /// Compact index, so they don't count toward "N clips" either.
    static func clipCount(transcriptsAndNotes items: [MediaDisplayItem]) -> Int {
        items.filter { $0.mediaType == .voice || $0.mediaType == .note }.count
    }
}
