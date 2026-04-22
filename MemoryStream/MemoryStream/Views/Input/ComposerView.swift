import SwiftUI

struct ComposerView: View {
    @ObservedObject var composer: ComposerViewModel
    let topics: [String]
    let onCommit: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(Crucible.Color.divider)
                .frame(width: 32, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 6)

            // Header
            ComposerHeader(composer: composer)

            ScrollView {
                VStack(spacing: 12) {
                    // Audio row
                    ComposerAudioRow(composer: composer)

                    // Live transcript
                    if !composer.transcribedText.isEmpty || !composer.textContent.isEmpty {
                        ComposerTextArea(composer: composer)
                    }

                    // Existing media (append mode, dimmed)
                    if composer.isAppendMode && !composer.existingMedia.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ALREADY ATTACHED")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .tracking(0.5)
                                .foregroundStyle(Crucible.Color.ink3)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(composer.existingMedia) { item in
                                        MediaThumbnailView(item: item, size: 62) {}
                                            .opacity(0.5)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                    }

                    // New media filmstrip
                    if !composer.mediaCaptures.isEmpty {
                        ComposerFilmstrip(composer: composer)
                    }

                    // Add media buttons (when not recording and no filmstrip yet)
                    if composer.mediaCaptures.isEmpty && composer.existingMedia.isEmpty {
                        Button {
                            composer.showCamera = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "camera")
                                    .foregroundStyle(Crucible.Color.Media.photo)
                                Text("Add photo or video")
                                    .foregroundStyle(Crucible.Color.ink2)
                            }
                            .font(.subheadline)
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(Crucible.Color.card)
                            .clipShape(RoundedRectangle(cornerRadius: Crucible.Radius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: Crucible.Radius.md)
                                    .stroke(Crucible.Color.hairline, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                    }

                    // Topic picker
                    ComposerTopicPicker(
                        selectedTopic: $composer.selectedTopicName,
                        topics: topics
                    )
                    .padding(.horizontal, 14)
                }
                .padding(.top, 4)
                .padding(.bottom, 8)
            }

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
        .background(Crucible.Color.paper)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - Header

private struct ComposerHeader: View {
    @ObservedObject var composer: ComposerViewModel

    var body: some View {
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

            // Media add buttons
            HStack(spacing: 6) {
                HeaderButton(icon: "camera", color: Crucible.Color.Media.photo) {
                    composer.showCamera = true
                }
                HeaderButton(icon: "pencil", color: Crucible.Color.Media.text) {
                    // Focus on text — just ensure text area is visible
                    if composer.textContent.isEmpty {
                        composer.textContent = " " // triggers text area to show
                        composer.textContent = ""
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct HeaderButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(Crucible.Color.card)
                .clipShape(RoundedRectangle(cornerRadius: Crucible.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Crucible.Radius.sm)
                        .stroke(Crucible.Color.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Audio Row

private struct ComposerAudioRow: View {
    @ObservedObject var composer: ComposerViewModel

    var body: some View {
        HStack(spacing: 10) {
            // Mic button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                composer.toggleRecording()
            } label: {
                ZStack {
                    Circle()
                        .fill(Crucible.Color.Media.audio)
                        .frame(width: 28, height: 28)
                    if composer.isRecording {
                        // Stop square
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.white)
                            .frame(width: 10, height: 10)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                    }
                }
                .shadow(color: composer.isRecording ? Crucible.Color.Media.audio.opacity(0.3) : .clear, radius: 6)
            }
            .buttonStyle(.plain)

            if composer.isRecording {
                // Waveform placeholder (animated bars)
                HStack(spacing: 2) {
                    ForEach(0..<16, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Crucible.Color.Media.audio)
                            .frame(width: 2.5, height: CGFloat.random(in: 4...22))
                    }
                }
                .frame(height: 28)

                Spacer()

                // Timer
                Text(formatDuration(composer.recordingDuration))
                    .font(.caption)
                    .fontFamily(.monospaced)
                    .foregroundStyle(Crucible.Color.ink3)
            } else if composer.recordingDuration > 0 {
                Text("Voice recorded")
                    .font(.caption)
                    .foregroundStyle(Crucible.Color.ink2)
                Spacer()
                Text(formatDuration(composer.recordingDuration))
                    .font(.caption)
                    .fontFamily(.monospaced)
                    .foregroundStyle(Crucible.Color.ink3)
            } else {
                Text("Tap to record")
                    .font(.caption)
                    .foregroundStyle(Crucible.Color.ink3)
                Spacer()
            }
        }
        .padding(12)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: Crucible.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Crucible.Radius.md)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
        .padding(.horizontal, 14)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Text Area + Transcript

private struct ComposerTextArea: View {
    @ObservedObject var composer: ComposerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Live transcript (serif italic when recording)
            if !composer.transcribedText.isEmpty {
                Text(composer.transcribedText)
                    .font(.footnote)
                    .italic()
                    .foregroundStyle(Crucible.Color.ink)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Editable text
            if !composer.isRecording {
                TextEditor(text: $composer.textContent)
                    .font(.body)
                    .foregroundStyle(Crucible.Color.ink)
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
            }
        }
        .padding(12)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: Crucible.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Crucible.Radius.md)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
        .padding(.horizontal, 14)
    }
}

// MARK: - Media Filmstrip

private struct ComposerFilmstrip: View {
    @ObservedObject var composer: ComposerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if composer.isAppendMode {
                Text("NEW")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .tracking(0.5)
                    .foregroundStyle(Crucible.Color.ink3)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(composer.mediaCaptures.enumerated()), id: \.offset) { index, capture in
                        ComposerMediaThumb(
                            localIdentifier: capture.localIdentifier,
                            mediaType: capture.mediaType,
                            onRemove: { composer.removeMedia(at: index) }
                        )
                    }

                    // Add tile
                    Button {
                        composer.showCamera = true
                    } label: {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Crucible.Color.divider, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                            .frame(width: 62, height: 62)
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Crucible.Color.ink3)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
    }
}

private struct ComposerMediaThumb: View {
    let localIdentifier: String
    let mediaType: MediaReference.MediaType
    let onRemove: () -> Void

    @State private var thumbnail: UIImage? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Thumbnail
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Crucible.Color.sunk
                }
            }
            .frame(width: 62, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Media type dot
            Circle()
                .fill(mediaType == .video ? Crucible.Color.Media.video : Crucible.Color.Media.photo)
                .frame(width: 16, height: 16)
                .overlay(
                    Image(systemName: mediaType == .video ? "play.fill" : "camera.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.white)
                )
                .offset(x: 4, y: 4)

            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Crucible.Color.danger)
                    .clipShape(Circle())
            }
            .offset(x: 48, y: -4)
        }
        .frame(width: 62, height: 62)
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
                Spacer()
            }
        }
    }
}

// MARK: - Font extension for monospaced

private extension View {
    func fontFamily(_ design: Font.Design) -> some View {
        self.font(.system(.caption, design: design))
    }
}
