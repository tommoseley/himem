import SwiftUI

struct EntryCardView: View {
    let entry: EntryDisplayModel
    var density: CardDensity = .standard
    var onFeedback: ((UUID, InferenceSummary.FeedbackState) -> Void)? = nil
    var onAdjust: ((UUID, String) -> Void)? = nil
    var onEntityTap: ((String) -> Void)? = nil
    var onAppend: ((EntryDisplayModel) -> Void)? = nil
    @State private var showInferenceDetail = false
    @State private var selectedMedia: MediaDisplayItem? = nil
    @State private var isContentExpanded = false

    /// Tags that add information beyond what's already in the content text.
    private func dotColor(for type: MediaReference.MediaType) -> Color {
        switch type {
        case .image: return Crucible.Color.Media.photo
        case .video: return Crucible.Color.Media.video
        case .voice: return Crucible.Color.Media.audio
        }
    }

    private var smartTags: [TagDisplayModel] {
        entry.tags.filter { tag in
            !entry.content.localizedCaseInsensitiveContains(tag.value)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 8 : 12) {
            // Title + metadata row
            EntryHeaderRow(entry: entry, density: density, onStatusTap: entry.feedbackState != nil ? {
                showInferenceDetail = true
            } : nil)

            // Media dot strip
            if entry.hasAudio || !entry.mediaItems.isEmpty {
                HStack(spacing: 6) {
                    if entry.audioFilePath != nil {
                        Circle().fill(Crucible.Color.Media.audio).frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                    }
                    ForEach(entry.mediaItems) { item in
                        Circle()
                            .fill(dotColor(for: item.mediaType))
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                    }
                    if let summary = entry.mediaSummary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(Crucible.Color.ink3)
                            .padding(.leading, 4)
                    }
                    Spacer()
                }
            }

            // Topic chips — palette-colored
            if !entry.topicNames.isEmpty {
                HStack(spacing: 6) {
                    ForEach(entry.topicNames, id: \.self) { topic in
                        let hue = Crucible.Color.topicHue(for: topic)
                        Text(topic)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(hue.bg)
                            .foregroundStyle(hue.fg)
                            .clipShape(Capsule())
                    }
                }
            }

            // Divider
            Rectangle()
                .fill(Crucible.Color.hairline)
                .frame(height: 0.5)

            // Content
            Text(entry.content)
                .font(density == .compact ? .subheadline : .body)
                .foregroundStyle(Crucible.Color.ink)
                .lineSpacing(density == .compact ? 2 : 3)
                .lineLimit(isContentExpanded && density != .compact ? nil : density.contentLineLimit)

            if density.contentLineLimit != nil && entry.content.count > 120 {
                Button(isContentExpanded ? "Show less" : "Show more") {
                    withAnimation(.easeInOut(duration: 0.2)) { isContentExpanded.toggle() }
                }
                .font(.caption)
                .foregroundStyle(.blue)
            }

            // Processing status card (when actively processing)
            if density != .compact,
               let processingStatus = entry.processingStatus, processingStatus != .completed {
                ProcessingStatusCard(status: processingStatus, progressDescription: entry.progressDescription)
            }

            // Entity tags — only visible in Rich mode (search-only in Standard/Compact)
            if density == .rich && !smartTags.isEmpty {
                EntityTagsRow(tags: smartTags, onEntityTap: onEntityTap)
            }

            // Inference summary card
            if density == .rich {
                // Rich: always show inference if available
                if let inference = entry.inferenceSummary {
                    InferenceCard(
                        summary: inference,
                        feedbackState: entry.feedbackState,
                        onFeedback: { state in onFeedback?(entry.id, state) },
                        onAdjust: { correction in onAdjust?(entry.id, correction) }
                    )
                }
            } else if density == .standard {
                // Standard: only show while pending
                if let inference = entry.inferenceSummary, entry.feedbackState == nil {
                    InferenceCard(
                        summary: inference,
                        feedbackState: entry.feedbackState,
                        onFeedback: { state in onFeedback?(entry.id, state) },
                        onAdjust: { correction in onAdjust?(entry.id, correction) }
                    )
                }
            }
            // Compact: no inference card

            // Voice playback and append moved to expanded view
        }
        .padding(density == .compact ? Crucible.Space.md : Crucible.Space.lg)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: Crucible.Radius.xl))
        .modifier(WarmShadow(level: 1))
        .sheet(isPresented: $showInferenceDetail) {
            if let inference = entry.inferenceSummary, let feedbackState = entry.feedbackState {
                InferenceDetailSheet(
                    summary: inference,
                    feedbackState: feedbackState,
                    userCorrection: entry.userCorrection,
                    audioFilePath: entry.audioFilePath
                )
            }
        }
        .fullScreenCover(item: $selectedMedia) { item in
            MediaViewerView(item: item)
        }
    }
}

// MARK: - Entry Header

struct EntryHeaderRow: View {
    let entry: EntryDisplayModel
    var density: CardDensity = .standard
    var onStatusTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.displayTitle)
                .font(.headline)
                .foregroundStyle(Crucible.Color.ink)

            HStack(spacing: 6) {
                Text(entry.timeString)
                    .font(.caption)
                    .foregroundStyle(Crucible.Color.ink2)

                Spacer()

                if let status = entry.displayStatus {
                    if let onStatusTap {
                        Button(action: onStatusTap) {
                            StatusBadge(text: status.text, style: status.style)
                        }
                        .buttonStyle(.plain)
                    } else {
                        StatusBadge(text: status.text, style: status.style)
                    }
                }
            }

            // Variant B (Himem · Location.html): own row, mappin glyph, place
            // name. Max density only. Apply the design's truncation ladder —
            // drop trailing comma-separated segments (locality, then admin)
            // until the result fits the row, never mid-token "…".
            if density == .rich,
               let locationName = entry.locationName,
               !locationName.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin")
                        .font(.caption2)
                        .foregroundStyle(Crucible.Color.ink3)
                        .accessibilityHidden(true)
                    Text(EntryHeaderRow.fitting(locationName))
                        .font(.caption)
                        .foregroundStyle(Crucible.Color.ink2)
                        .lineLimit(1)
                }
            }
        }
    }

    /// Drops trailing comma-separated segments from a placemark string until
    /// it fits the target character budget. Lossy but predictable — never
    /// produces a string that ends in a comma + ellipsis.
    static func fitting(_ name: String, maxChars: Int = 28) -> String {
        if name.count <= maxChars { return name }
        var segments = name.components(separatedBy: ", ")
        while segments.count > 1 {
            segments.removeLast()
            let candidate = segments.joined(separator: ", ")
            if candidate.count <= maxChars { return candidate }
        }
        // Single segment, still too long. Let SwiftUI truncate as a last
        // resort — a long single token can't be split without becoming wrong.
        return segments.first ?? name
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

// MARK: - Processing Status Card

struct ProcessingStatusCard: View {
    let status: ProcessingTask.Status
    let progressDescription: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("PROCESSING")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .tracking(0.5)
                    .foregroundStyle(.secondary)

                if status == .processing {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }

            if let progressDescription {
                Text(progressDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Crucible.Color.sunk)
        .clipShape(RoundedRectangle(cornerRadius: Crucible.Radius.sm))
    }
}

// MARK: - Entity Tags Row

struct EntityTagsRow: View {
    let tags: [TagDisplayModel]
    var onEntityTap: ((String) -> Void)? = nil
    @State private var showAll = false

    private var visibleTags: [TagDisplayModel] {
        showAll ? tags : Array(tags.prefix(3))
    }

    private var hiddenCount: Int {
        max(0, tags.count - 3)
    }

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(visibleTags) { tag in
                Button {
                    onEntityTap?(tag.value)
                } label: {
                    Text(tag.value)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Crucible.Color.sunk)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if !showAll && hiddenCount > 0 {
                Button {
                    withAnimation { showAll = true }
                } label: {
                    Text("+\(hiddenCount)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Crucible.Color.sunk)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
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
    @StateObject private var player = AudioPlayerService.shared
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
                        .foregroundStyle(.blue)
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
                    .foregroundStyle(.blue)
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
    var audioFilePath: String? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                // Voice playback — shown first since it's what drove the inference
                if let audioFile = audioFilePath {
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
