import SwiftUI

struct EntryCardView: View {
    let entry: EntryDisplayModel
    var density: CardDensity = .standard
    var onFeedback: ((UUID, InferenceSummary.FeedbackState) -> Void)? = nil
    var onEntityTap: ((String) -> Void)? = nil
    var onAppend: ((EntryDisplayModel) -> Void)? = nil
    @State private var showInferenceDetail = false
    @State private var selectedMedia: MediaDisplayItem? = nil
    @State private var isContentExpanded = false

    /// Tags that add information beyond what's already in the content text.
    private var smartTags: [TagDisplayModel] {
        entry.tags.filter { tag in
            !entry.content.localizedCaseInsensitiveContains(tag.value)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 8 : 12) {
            // Title + metadata row
            EntryHeaderRow(entry: entry, onStatusTap: entry.feedbackState != nil ? {
                showInferenceDetail = true
            } : nil)

            // Media strip
            if !entry.mediaItems.isEmpty {
                if density == .compact {
                    // Compact: just an attachment indicator
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip")
                            .font(.caption)
                        Text("\(entry.mediaItems.count) media")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(entry.mediaItems) { item in
                                MediaThumbnailView(item: item) {
                                    selectedMedia = item
                                }
                            }
                        }
                    }
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
                        onFeedback: { state in onFeedback?(entry.id, state) }
                    )
                }
            } else if density == .standard {
                // Standard: only show while pending
                if let inference = entry.inferenceSummary, entry.feedbackState == nil {
                    InferenceCard(
                        summary: inference,
                        feedbackState: entry.feedbackState,
                        onFeedback: { state in onFeedback?(entry.id, state) }
                    )
                }
            }
            // Compact: no inference card

            // Voice playback
            if density == .rich {
                // Rich: always show voice playback if available
                if let audioFile = entry.audioFilePath {
                    VoicePlaybackRow(filename: audioFile)
                }
            } else if density == .standard && entry.feedbackState == nil {
                // Standard: only while inference is pending
                if let audioFile = entry.audioFilePath {
                    VoicePlaybackRow(filename: audioFile)
                } else if entry.inputType == .siri || entry.inputType == .voiceInApp {
                    Text("Voice entry — audio was not saved.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            }
            // Compact: no voice playback

            // Append button
            if let onAppend, density != .compact {
                HStack {
                    Spacer()
                    Button {
                        onAppend(entry)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Crucible.Color.ink3)
                            .frame(width: 28, height: 28)
                            .background(Crucible.Color.sunk)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
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

                Circle()
                    .fill(Color(.separator))
                    .frame(width: 3, height: 3)

                Text(entry.inputType.displayLabel)
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
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(Crucible.Color.AI.base)
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

            if feedbackState == nil {
                // Pending — show feedback buttons
                HStack(spacing: 8) {
                    Button(action: { onFeedback(.confirmed) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
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

                    Button(action: { onFeedback(.edited) }) {
                        Text("Edit")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .overlay(Capsule().stroke(Crucible.Color.hairline, lineWidth: 0.5))
                    }

                    Button(action: { onFeedback(.ignored) }) {
                        Text("Not this time")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .overlay(Capsule().stroke(Crucible.Color.hairline, lineWidth: 0.5))
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
        case .edited:    return "You edited this inference."
        case .ignored:   return "You dismissed this inference."
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
