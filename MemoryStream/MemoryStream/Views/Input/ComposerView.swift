import SwiftUI

struct ComposerView: View {
    @ObservedObject var composer: ComposerViewModel
    let topics: [String]
    let onCommit: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showTextEditor = false

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(Crucible.Color.divider)
                .frame(width: 32, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 6)

            // Header — title + close only
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if composer.isAppendMode {
                        Text("ADDING TO")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .tracking(0.5)
                            .foregroundStyle(Crucible.Color.ink3)
                    }
                    Text(composer.headerTitle)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(Crucible.Color.ink)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Crucible.Color.ink2)
                        .frame(width: 28, height: 28)
                        .background(Crucible.Color.sunk)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            // Media toolbar — four first-class entry points
            ComposerToolbar(
                activeType: activeToolbarType,
                onAudioTap: { composer.toggleRecording() },
                onTextTap: { showTextEditor = true },
                onPhotoTap: { composer.showCamera = true },
                onVideoTap: { composer.showCamera = true }
            )
            .padding(.horizontal, 14)

            // Work area — list of attachments
            ScrollView {
                VStack(spacing: 8) {
                    // Existing media (append mode)
                    if composer.isAppendMode && !composer.existingMedia.isEmpty {
                        Text("ALREADY ATTACHED")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .tracking(0.5)
                            .foregroundStyle(Crucible.Color.ink3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)

                        ForEach(composer.existingMedia) { item in
                            AttachmentRow(
                                color: item.mediaType == .video ? Crucible.Color.Media.video : Crucible.Color.Media.photo,
                                icon: item.mediaType == .video ? "video" : "camera",
                                label: item.mediaType == .video ? "Video" : "Photo",
                                emphasized: false
                            ) {
                                MediaThumbnailView(item: item, size: 48) {}
                            }
                            .opacity(0.7)
                        }

                        if !composer.mediaCaptures.isEmpty || composer.isRecording || !composer.transcribedText.isEmpty {
                            Text("NEW")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .tracking(0.5)
                                .foregroundStyle(Crucible.Color.ink3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                        }
                    }

                    // Active recording row
                    if composer.isRecording {
                        AttachmentRow(
                            color: Crucible.Color.Media.audio,
                            icon: "mic",
                            label: "Recording",
                            meta: formatDuration(composer.recordingDuration),
                            emphasized: true
                        ) {
                            HStack(spacing: 10) {
                                // Waveform bars
                                HStack(spacing: 2) {
                                    ForEach(0..<16, id: \.self) { i in
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(Crucible.Color.Media.audio)
                                            .frame(width: 2.5, height: CGFloat.random(in: 4...20))
                                    }
                                }
                                .frame(height: 22)

                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Crucible.Color.Media.audio)
                                        .frame(width: 6, height: 6)
                                    Text("LIVE")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(Crucible.Color.Media.audio)
                                }
                            }
                        } actions: {
                            // Stop button
                            Button {
                                composer.stopRecording()
                            } label: {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(.white)
                                    .frame(width: 8, height: 8)
                                    .frame(width: 24, height: 24)
                                    .background(Crucible.Color.Media.audio)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    } else if composer.recordingDuration > 0 {
                        // Completed recording
                        AttachmentRow(
                            color: Crucible.Color.Media.audio,
                            icon: "mic",
                            label: "Audio",
                            meta: formatDuration(composer.recordingDuration)
                        ) {
                            HStack(spacing: 2) {
                                ForEach(0..<16, id: \.self) { i in
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(Crucible.Color.Media.audio.opacity(0.6))
                                        .frame(width: 2.5, height: CGFloat(4 + (i % 5) * 3))
                                }
                            }
                            .frame(height: 18)
                        }
                    }

                    // Transcript row (auto-generated from voice)
                    if !composer.transcribedText.isEmpty {
                        AttachmentRow(
                            color: Crucible.Color.Media.text,
                            icon: "pencil",
                            label: "Transcript"
                        ) {
                            Text(composer.transcribedText)
                                .font(.footnote)
                                .italic()
                                .foregroundStyle(Crucible.Color.ink)
                                .lineSpacing(3)
                        }
                    }

                    // Text note row
                    if showTextEditor || !composer.textContent.isEmpty {
                        AttachmentRow(
                            color: Crucible.Color.Media.text,
                            icon: "pencil",
                            label: "Note"
                        ) {
                            TextEditor(text: $composer.textContent)
                                .font(.footnote)
                                .foregroundStyle(Crucible.Color.ink)
                                .frame(minHeight: 44)
                                .scrollContentBackground(.hidden)
                        }
                    }

                    // Media rows
                    ForEach(Array(composer.mediaCaptures.enumerated()), id: \.offset) { index, capture in
                        let isVideo = capture.mediaType == .video
                        AttachmentRow(
                            color: isVideo ? Crucible.Color.Media.video : Crucible.Color.Media.photo,
                            icon: isVideo ? "video" : "camera",
                            label: isVideo ? "Video" : "Photo"
                        ) {
                            ComposerThumb(localIdentifier: capture.localIdentifier, isVideo: isVideo)
                        } actions: {
                            Button {
                                composer.removeMedia(at: index)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Crucible.Color.ink3)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }

            // Footer — topic picker + item count + commit
            VStack(spacing: 10) {
                HStack {
                    // Topic picker
                    ComposerTopicPicker(selectedTopic: $composer.selectedTopicName, topics: topics)
                    Spacer()
                    Text("\(itemCount) item\(itemCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(Crucible.Color.ink3)
                }
                .padding(.horizontal, 14)

                // Commit button
                Button(action: {
                    onCommit()
                    dismiss()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: composer.commitButtonIcon)
                            .font(.system(size: 14, weight: .bold))
                        Text(composer.commitButtonTitle)
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(composer.canCommit ? Crucible.Color.accent : Crucible.Color.sunk)
                    .foregroundStyle(composer.canCommit ? .white : Crucible.Color.ink3)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!composer.canCommit)
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
            }
        }
        .background(Crucible.Color.paper)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private var activeToolbarType: String? {
        if composer.isRecording { return "audio" }
        if showTextEditor || !composer.textContent.isEmpty { return "text" }
        return nil
    }

    private var itemCount: Int {
        var count = composer.mediaCaptures.count
        if composer.recordingDuration > 0 || composer.isRecording { count += 1 }
        if !composer.transcribedText.isEmpty { count += 1 }
        if !composer.textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        return count
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Media Toolbar

private struct ComposerToolbar: View {
    let activeType: String?
    let onAudioTap: () -> Void
    let onTextTap: () -> Void
    let onPhotoTap: () -> Void
    let onVideoTap: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ToolbarButton(kind: "audio", icon: "mic", label: "Audio", isActive: activeType == "audio", action: onAudioTap)
            ToolbarButton(kind: "text", icon: "pencil", label: "Text", isActive: activeType == "text", action: onTextTap)
            ToolbarButton(kind: "photo", icon: "camera", label: "Photo", isActive: activeType == "photo", action: onPhotoTap)
            ToolbarButton(kind: "video", icon: "video", label: "Video", isActive: activeType == "video", action: onVideoTap)
        }
        .padding(4)
        .background(Crucible.Color.sunk)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
    }
}

private struct ToolbarButton: View {
    let kind: String
    let icon: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    private var color: Color {
        switch kind {
        case "audio": return Crucible.Color.Media.audio
        case "text": return Crucible.Color.Media.text
        case "photo": return Crucible.Color.Media.photo
        case "video": return Crucible.Color.Media.video
        default: return Crucible.Color.ink2
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon == "video" ? "video" : (icon == "camera" ? "camera" : (icon == "pencil" ? "pencil" : "mic")))
                    .font(.system(size: 14, weight: isActive ? .bold : .medium))
                    .foregroundStyle(isActive ? .white : color)
                    .frame(width: 28, height: 28)
                    .background(isActive ? color : Crucible.Color.card)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isActive ? Color.clear : Crucible.Color.hairline, lineWidth: 1)
                    )
                    .shadow(color: isActive ? color.opacity(0.2) : .clear, radius: 4)

                Text(label)
                    .font(.caption2)
                    .fontWeight(isActive ? .bold : .medium)
                    .foregroundStyle(isActive ? color : Crucible.Color.ink2)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .background(isActive ? color.opacity(0.12) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Attachment Row

private struct AttachmentRow<Content: View, Actions: View>: View {
    let color: Color
    let icon: String
    let label: String
    var meta: String? = nil
    var emphasized: Bool = false
    @ViewBuilder let content: Content
    @ViewBuilder var actions: Actions

    init(
        color: Color, icon: String, label: String, meta: String? = nil, emphasized: Bool = false,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }
    ) {
        self.color = color
        self.icon = icon
        self.label = label
        self.meta = meta
        self.emphasized = emphasized
        self.content = content()
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Color tag
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(label)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(color)

                    if let meta {
                        Text(meta)
                            .font(.caption)
                            .foregroundStyle(Crucible.Color.ink3)
                            .monospacedDigit()
                    }
                }

                content
            }

            Spacer(minLength: 0)

            // Actions
            actions
        }
        .padding(12)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(emphasized ? color.opacity(0.33) : Crucible.Color.hairline, lineWidth: 1)
        )
        .shadow(color: emphasized ? color.opacity(0.1) : .clear, radius: 6)
    }
}

// MARK: - Composer Thumbnail

private struct ComposerThumb: View {
    let localIdentifier: String
    let isVideo: Bool
    @State private var thumbnail: UIImage? = nil

    var body: some View {
        ZStack {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Crucible.Color.sunk
            }
        }
        .frame(width: 52, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
        .overlay {
            if isVideo {
                Image(systemName: "play.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.black.opacity(0.4))
                    .clipShape(Circle())
            }
        }
        .task {
            if let cached = await ThumbnailService.shared.cacheThumbnail(for: localIdentifier) {
                thumbnail = ThumbnailService.shared.cachedThumbnail(filename: cached)
            }
        }
    }
}

// MARK: - Topic Picker

private struct ComposerTopicPicker: View {
    @Binding var selectedTopic: String?
    let topics: [String]

    var body: some View {
        Menu {
            Button("None") { selectedTopic = nil }
            Divider()
            ForEach(topics, id: \.self) { topic in
                Button {
                    selectedTopic = topic
                } label: {
                    HStack {
                        Text(topic)
                        if selectedTopic == topic {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let topic = selectedTopic {
                    let hue = Crucible.Color.topicHue(for: topic)
                    Circle()
                        .fill(hue.fg)
                        .frame(width: 10, height: 10)
                    Text(topic)
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(Crucible.Color.ink)
                } else {
                    Circle()
                        .fill(Crucible.Color.ink4)
                        .frame(width: 10, height: 10)
                    Text("Add topic")
                        .font(.footnote)
                        .foregroundStyle(Crucible.Color.ink3)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(Crucible.Color.ink3)
            }
        }
    }
}
