import SwiftUI

struct EntryCardView: View {
    let entry: EntryDisplayModel
    var onFeedback: ((UUID, InferenceSummary.FeedbackState) -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title + metadata row
            EntryHeaderRow(entry: entry)

            // Topic chips
            if !entry.topicNames.isEmpty {
                HStack(spacing: 6) {
                    ForEach(entry.topicNames, id: \.self) { topic in
                        Text(topic)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }
            }

            // Divider
            Rectangle()
                .fill(Color(.separator).opacity(0.3))
                .frame(height: 0.5)

            // Content
            Text(entry.content)
                .font(.body)
                .lineSpacing(3)

            // Processing status card (when actively processing)
            if let processingStatus = entry.processingStatus, processingStatus != .completed {
                ProcessingStatusCard(status: processingStatus, progressDescription: entry.progressDescription)
            }

            // Entity tags
            if !entry.tags.isEmpty {
                EntityTagsRow(tags: entry.tags)
            }

            // Inference summary card
            if let inference = entry.inferenceSummary {
                InferenceCard(
                    summary: inference,
                    feedbackState: entry.feedbackState,
                    onFeedback: { state in
                        onFeedback?(entry.id, state)
                    }
                )
            }

            // Voice playback
            if let audioFile = entry.audioFilePath {
                VoicePlaybackRow(filename: audioFile)
            } else if entry.inputType == .siri || entry.inputType == .voiceInApp {
                Text("Voice entry — audio was not saved.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }
}

// MARK: - Entry Header

struct EntryHeaderRow: View {
    let entry: EntryDisplayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.displayTitle)
                .font(.headline)

            HStack(spacing: 6) {
                Text(entry.timeString)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Circle()
                    .fill(Color(.separator))
                    .frame(width: 3, height: 3)

                Text(entry.inputType.displayLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Status badge
                if let status = entry.displayStatus {
                    StatusBadge(text: status.text, style: status.style)
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

        var foreground: Color {
            switch self {
            case .processing: return .orange
            case .confirmed: return .green
            case .failed: return .red
            }
        }

        var background: Color {
            foreground.opacity(0.12)
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
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Entity Tags Row

struct EntityTagsRow: View {
    let tags: [TagDisplayModel]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags) { tag in
                Text(tag.value)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(Capsule())
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
            Text("APP IS INFERRING")
                .font(.caption2)
                .fontWeight(.bold)
                .tracking(0.5)
                .foregroundStyle(.secondary)

            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(2)

            if feedbackState == nil {
                // Pending — show feedback buttons
                HStack(spacing: 8) {
                    Button(action: { onFeedback(.confirmed) }) {
                        Text("Looks right")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.label))
                            .foregroundColor(Color(.systemBackground))
                            .clipShape(Capsule())
                    }

                    Button(action: { onFeedback(.edited) }) {
                        Text("Edit")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .overlay(Capsule().stroke(Color(.separator), lineWidth: 0.5))
                    }

                    Button(action: { onFeedback(.ignored) }) {
                        Text("Ignore")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .overlay(Capsule().stroke(Color(.separator), lineWidth: 0.5))
                    }

                    Spacer()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
