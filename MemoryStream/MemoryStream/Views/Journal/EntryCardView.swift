import SwiftUI

// MARK: - Place name helper

/// Drops trailing comma-separated segments from a placemark string until
/// it fits the target character budget. Lossy but predictable — never
/// produces a string ending in "comma, ellipsis".
enum PlaceName {
    static func fitting(_ name: String, maxChars: Int = 28) -> String {
        if name.count <= maxChars { return name }
        var segments = name.components(separatedBy: ", ")
        while segments.count > 1 {
            segments.removeLast()
            let candidate = segments.joined(separator: ", ")
            if candidate.count <= maxChars { return candidate }
        }
        return segments.first ?? name
    }
}

// MARK: - Memory card
//
// Spec: `docs/design/Memories list · spec.md` (June 4 2026).
// One card, no density toggle. Recognition, not reading — the whole card
// taps to Memory Detail; expansion is a destination, never inline.
// Anatomy (spec §3): title (serif) → meta (time · place) → media glyph
// row + topic chips → gist with fallback chain (spec §4).

struct EntryCardView: View {
    let entry: EntryDisplayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            titleAndMeta
            mediaAndTopics
            GistView(kind: Self.gistKind(for: entry))
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Crucible.Color.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var titleAndMeta: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.displayTitle)
                .font(.system(size: 17.5, weight: .medium, design: .serif))
                .tracking(-0.2)
                .foregroundStyle(Crucible.Color.ink)
                .lineLimit(2)

            Text(metaLine)
                .font(.system(size: 13))
                .tracking(-0.05)
                .foregroundStyle(Crucible.Color.ink3)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var mediaAndTopics: some View {
        let hasMedia = !entry.mediaItems.isEmpty
        let hasTopics = !entry.topicNames.isEmpty
        if hasMedia || hasTopics {
            HStack(alignment: .center, spacing: 12) {
                if hasMedia { MediaGlyphRow(mediaItems: entry.mediaItems) }
                Spacer(minLength: 0)
                if hasTopics { TopicChipsRow(topicNames: entry.topicNames) }
            }
        }
    }

    private var metaLine: String {
        let time = entry.timeString
        if let place = entry.locationName, !place.isEmpty {
            return "\(time) · \(PlaceName.fitting(place))"
        }
        return time
    }

    // Spec §4 — the gist always says something true. Resolve in order:
    // AI summary → raw excerpt (italic serif) → media description.
    static func gistKind(for entry: EntryDisplayModel) -> GistKind {
        if let summary = entry.renderedSummary,
           !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .summary(summary)
        }
        let excerpt = entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !excerpt.isEmpty {
            return .excerpt(excerpt)
        }
        return .media(Self.mediaDescription(for: entry))
    }

    private static func mediaDescription(for entry: EntryDisplayModel) -> String {
        let audio = entry.mediaItems.filter { $0.mediaType == .voice }.count
        let photo = entry.mediaItems.filter { $0.mediaType == .image }.count
        let video = entry.mediaItems.filter { $0.mediaType == .video }.count
        var parts: [String] = []
        if photo > 0 { parts.append("\(photo) photo\(photo == 1 ? "" : "s")") }
        if video > 0 { parts.append("\(video) video\(video == 1 ? "" : "s")") }
        if audio > 0 { parts.append("\(audio) audio clip\(audio == 1 ? "" : "s")") }
        let head = parts.joined(separator: ", ")
        if head.isEmpty { return "" }
        if let place = entry.locationName, !place.isEmpty {
            return "\(head) captured near \(PlaceName.fitting(place))."
        }
        return "\(head)."
    }
}

// MARK: - Gist kinds & view (spec §4)

enum GistKind {
    case summary(String)
    case excerpt(String)
    case media(String)
}

struct GistView: View {
    let kind: GistKind

    var body: some View {
        switch kind {
        case .summary(let text):
            HStack(alignment: .top, spacing: 7) {
                // The ONLY AI-blue on the card — provenance for an
                // organized summary, "the only marker of AI authorship."
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Crucible.Color.aiBlue)
                    .accessibilityHidden(true)
                    .padding(.top, 2)
                Text(text)
                    .font(.system(size: 15))
                    .tracking(-0.05)
                    .foregroundStyle(Crucible.Color.ink2)
                    .lineSpacing(4)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        case .excerpt(let text):
            // Italic serif with curly quotes — these are the user's own
            // words, verbatim.
            Text("\u{201C}\(text)\u{201D}")
                .font(.system(size: 15.5, design: .serif).italic())
                .foregroundStyle(Crucible.Color.ink2)
                .lineSpacing(4)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        case .media(let text):
            Text(text)
                .font(.system(size: 15))
                .tracking(-0.05)
                .foregroundStyle(Crucible.Color.ink3)
                .lineSpacing(4)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
    }
}

// MARK: - Media glyph row (spec §5)

/// Shape-differentiated glyphs (not color). Audio gets the one legitimate
/// tint: ochre. Photo/video/note are warm ink. Past 3 distinct types,
/// collapses to "N items" — never a dot-soup row.
struct MediaGlyphRow: View {
    let mediaItems: [MediaDisplayItem]

    var body: some View {
        let counts = MediaTypeCounts(items: mediaItems)
        if counts.distinctCount > 3 {
            HStack(spacing: 5) {
                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Crucible.Color.Media.audio)
                    .accessibilityHidden(true)
                Text("\(counts.total) items")
                    .font(.system(size: 12))
                    .foregroundStyle(Crucible.Color.ink3)
                    .monospacedDigit()
            }
        } else {
            HStack(spacing: 13) {
                if counts.audio > 0 {
                    glyphCell(symbol: "waveform", count: counts.audio, tint: Crucible.Color.Media.audio)
                }
                if counts.photo > 0 {
                    glyphCell(symbol: "camera", count: counts.photo, tint: Crucible.Color.ink3)
                }
                if counts.video > 0 {
                    glyphCell(symbol: "video", count: counts.video, tint: Crucible.Color.ink3)
                }
                if counts.note > 0 {
                    glyphCell(symbol: "text.alignleft", count: counts.note, tint: Crucible.Color.ink3)
                }
            }
        }
    }

    private func glyphCell(symbol: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text("\(count)")
                .font(.system(size: 12))
                .foregroundStyle(Crucible.Color.ink2)
                .monospacedDigit()
        }
    }
}

private struct MediaTypeCounts {
    let audio: Int
    let photo: Int
    let video: Int
    let note:  Int

    init(items: [MediaDisplayItem]) {
        var a = 0, p = 0, v = 0, n = 0
        for item in items {
            switch item.mediaType {
            case .voice: a += 1
            case .image: p += 1
            case .video: v += 1
            case .note:  n += 1
            }
        }
        self.audio = a; self.photo = p; self.video = v; self.note = n
    }

    var total: Int { audio + photo + video + note }
    var distinctCount: Int { [audio, photo, video, note].filter { $0 > 0 }.count }
}

// MARK: - Topic chips row (spec §3 row 4)

/// Max 2 chips, +N overflow pill. Neutral wash background; the only
/// color is a small topic-palette dot per chip.
struct TopicChipsRow: View {
    let topicNames: [String]

    var body: some View {
        let shown = Array(topicNames.prefix(2))
        let extra = topicNames.count - shown.count
        HStack(spacing: 6) {
            ForEach(shown, id: \.self) { name in
                TopicChip(name: name)
            }
            if extra > 0 {
                Text("+\(extra)")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink3)
                    .monospacedDigit()
            }
        }
    }
}

private struct TopicChip: View {
    let name: String

    var body: some View {
        let hue = Crucible.Color.topicHue(for: name)
        HStack(spacing: 5) {
            Circle()
                .fill(hue.fg)
                .frame(width: 6, height: 6)
            Text(name)
                .font(.system(size: 11.5, weight: .medium))
                .tracking(-0.1)
                .foregroundStyle(Crucible.Color.ink2)
        }
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Crucible.Color.wash1)
        .clipShape(Capsule())
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let text: String
    let style: BadgeStyle

    enum BadgeStyle {
        case processing
        case confirmed
        case failed
        case edited
        case ignored
        case captured

        var foreground: Color {
            switch self {
            case .processing: return Crucible.Color.Status.inferringFg
            case .confirmed: return Crucible.Color.Status.confirmedFg
            case .failed: return Crucible.Color.Status.failedFg
            case .edited: return Crucible.Color.Status.editedFg
            case .ignored: return Crucible.Color.Status.draftFg
            case .captured: return Crucible.Color.Status.capturedFg
            }
        }

        var background: Color {
            switch self {
            case .processing: return Crucible.Color.Status.inferringBg
            case .confirmed: return Crucible.Color.Status.confirmedBg
            case .failed: return Crucible.Color.Status.failedBg
            case .edited: return Crucible.Color.Status.editedBg
            case .ignored: return Crucible.Color.Status.draftBg
            case .captured: return Crucible.Color.Status.capturedBg
            }
        }
    }

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(style.background)
            .foregroundStyle(style.foreground)
            .clipShape(Capsule())
    }
}

// MARK: - Inference Card

struct InferenceCard: View {
    let summary: String
    let feedbackState: InferenceSummary.FeedbackState?
    let onFeedback: (InferenceSummary.FeedbackState) -> Void
    var onAdjust: ((String) -> Void)? = nil

    @State private var showAdjustSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(Crucible.Color.AI.base)
                    .accessibilityHidden(true)
                Text("APP IS INFERRING")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .tracking(0.5)
                    .foregroundStyle(Crucible.Color.AI.base)
            }

            Text(summary)
                .font(.caption)
                .foregroundStyle(Crucible.Color.ink2)
                .lineSpacing(2)

            if let state = feedbackState {
                // Resolved — show status pill
                HStack(spacing: 6) {
                    Image(systemName: state.iconName)
                        .font(.system(size: 10)) // design-token size
                        .foregroundStyle(state.color)
                        .accessibilityHidden(true)
                    Text(state.pillLabel)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(state.color)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(state.color.opacity(0.1))
                .clipShape(Capsule())
            } else {
                // Pending — show feedback buttons
                HStack(spacing: 8) {
                    Button(action: { onFeedback(.confirmed) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10)) // design-token size
                                .accessibilityHidden(true)
                            Text("Confirm")
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Crucible.Color.AI.base)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }

                    Button(action: { showAdjustSheet = true }) {
                        Text("Adjust")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Crucible.Color.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Crucible.Color.sunk)
                            .clipShape(Capsule())
                    }

                    Button(action: { onFeedback(.ignored) }) {
                        Text("Not this time")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Crucible.Color.ink2)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Crucible.Color.sunk)
                            .clipShape(Capsule())
                    }

                    Spacer()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Crucible.Color.AI.tint)
        .clipShape(RoundedRectangle(cornerRadius: Crucible.Radius.md))
        .sheet(isPresented: $showAdjustSheet) {
            AdjustInferenceSheet(summary: summary) { correction in
                onAdjust?(correction)
            }
        }
    }
}

// MARK: - Adjust Inference Sheet

struct AdjustInferenceSheet: View {
    let summary: String
    let onSave: (String) -> Void

    @State private var editedSummary: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("ADJUST INFERENCE")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .tracking(0.5)
                    .foregroundStyle(.secondary)

                Text("Edit what the app inferred. Your correction helps improve future results.")
                    .font(.caption)
                    .foregroundStyle(Crucible.Color.ink2)

                TextEditor(text: $editedSummary)
                    .font(.body)
                    .lineSpacing(4)
                    .padding(12)
                    .frame(minHeight: 120)
                    .background(Crucible.Color.sunk)
                    .clipShape(RoundedRectangle(cornerRadius: Crucible.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: Crucible.Radius.md)
                            .stroke(Crucible.Color.hairline, lineWidth: 1)
                    )

                Spacer()
            }
            .padding(24)
            .navigationTitle("Review & Adjust")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(editedSummary)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(editedSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear { editedSummary = summary }
        .presentationDetents([.medium])
    }
}

// MARK: - Voice Playback

struct VoicePlaybackRow: View {
    let filename: String
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var showShare = false

    private var isThisPlaying: Bool {
        player.isPlaying && player.currentFile == filename
    }

    private var audioURL: URL {
        SpeechService.audioURL(for: filename)
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: {
                if isThisPlaying {
                    player.stop()
                } else {
                    player.play(filename: filename)
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isThisPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Crucible.Color.accent)
                        .accessibilityHidden(true)

                    Text(isThisPlaying ? "Stop playback" : "Play voice entry")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: { showShare = true }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.caption)
                    .foregroundStyle(Crucible.Color.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share voice recording")
            .sheet(isPresented: $showShare) {
                ShareSheet(items: [audioURL])
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Inference Detail Sheet

struct InferenceDetailSheet: View {
    let summary: String
    let feedbackState: InferenceSummary.FeedbackState
    var userCorrection: String? = nil
    var voiceFilename: String? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                // Voice playback — shown first since it's what drove the inference
                if let audioFile = voiceFilename {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("VOICE ENTRY")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .tracking(0.5)
                            .foregroundStyle(.secondary)

                        VoicePlaybackRow(filename: audioFile)
                            .padding(10)
                            .background(Crucible.Color.sunk)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Divider()
                }

                // What the AI inferred
                VStack(alignment: .leading, spacing: 8) {
                    Text("WHAT THE APP INFERRED")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .tracking(0.5)
                        .foregroundStyle(.secondary)

                    Text(summary)
                        .font(.body)
                        .lineSpacing(4)
                        .strikethrough(feedbackState == .edited, color: .secondary.opacity(0.5))
                        .foregroundStyle(feedbackState == .edited ? .secondary : .primary)
                }

                // User's adjusted version
                if let correction = userCorrection, feedbackState == .edited {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YOUR ADJUSTMENT")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .tracking(0.5)
                            .foregroundStyle(Crucible.Color.Status.editedFg)

                        Text(correction)
                            .font(.body)
                            .lineSpacing(4)
                    }
                }

                Divider()

                // User's response
                VStack(alignment: .leading, spacing: 8) {
                    Text("YOUR RESPONSE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .tracking(0.5)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Image(systemName: feedbackState.iconName)
                            .foregroundStyle(feedbackState.color)
                            .accessibilityHidden(true)
                        Text(feedbackState.responseLabel)
                            .font(.subheadline)
                            .foregroundStyle(feedbackState.color)
                    }
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("AI Inference")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

extension InferenceSummary.FeedbackState {
    var responseLabel: String {
        switch self {
        case .confirmed: return "You confirmed this inference was accurate."
        case .edited:    return "You adjusted this inference."
        case .ignored:   return "You dismissed this inference."
        }
    }

    var pillLabel: String {
        switch self {
        case .confirmed: return "Confirmed"
        case .edited:    return "Adjusted"
        case .ignored:   return "Dismissed"
        }
    }

    var iconName: String {
        switch self {
        case .confirmed: return "checkmark.circle.fill"
        case .edited:    return "pencil.circle.fill"
        case .ignored:   return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .confirmed: return Crucible.Color.Status.confirmedFg
        case .edited:    return Crucible.Color.Status.editedFg
        case .ignored:   return Crucible.Color.Status.draftFg
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}
