import SwiftUI

struct ComposerView: View {
    @ObservedObject var composer: ComposerViewModel
    @ObservedObject var speechService: SpeechService
    let topics: [String]
    let onCommit: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showTextEditor = false
    @State private var selectedMedia: MediaDisplayItem? = nil
    @AppStorage("saveVoiceEntries") private var saveVoiceEntries = true

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
                Text(composer.headerTitle)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(Crucible.Color.ink)
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

            // Work area
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Active recording indicator
                    if composer.isRecording {
                        HStack(spacing: 10) {
                            Button {
                                composer.stopRecording()
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Crucible.Color.Media.audio)
                                        .frame(width: 28, height: 28)
                                        .shadow(color: Crucible.Color.Media.audio.opacity(0.3), radius: 6)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(.white)
                                        .frame(width: 10, height: 10)
                                }
                            }
                            .buttonStyle(.plain)

                            HStack(spacing: 2) {
                                ForEach(0..<16, id: \.self) { i in
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(Crucible.Color.Media.audio)
                                        .frame(width: 2.5, height: CGFloat.random(in: 4...20))
                                }
                            }
                            .frame(height: 22)

                            HStack(spacing: 4) {
                                Circle().fill(Crucible.Color.Media.audio).frame(width: 6, height: 6)
                                Text("LIVE")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Crucible.Color.Media.audio)
                            }

                            Spacer()

                            Text(formatDuration(composer.recordingDuration))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(Crucible.Color.ink3)
                        }
                        .padding(12)
                        .background(Crucible.Color.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Crucible.Color.Media.audio.opacity(0.33), lineWidth: 1)
                        )
                    }

                    // Live transcript
                    if composer.isRecording && !composer.transcribedText.isEmpty {
                        Text(composer.transcribedText)
                            .font(.footnote)
                            .italic()
                            .foregroundStyle(Crucible.Color.ink)
                            .lineSpacing(3)
                            .padding(.horizontal, 4)
                    }

                    // Staged transcripts (body text, not tiles)
                    ForEach(Array(composer.pendingTranscripts.enumerated()), id: \.offset) { index, transcript in
                        HStack(alignment: .top) {
                            Text(transcript)
                                .font(.footnote)
                                .italic()
                                .foregroundStyle(Crucible.Color.ink)
                                .lineSpacing(3)
                            Spacer()
                            Button {
                                composer.pendingTranscripts.remove(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(Crucible.Color.ink4)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 4)
                    }

                    // Text note
                    if showTextEditor || !composer.textContent.isEmpty {
                        TextEditor(text: $composer.textContent)
                            .font(.footnote)
                            .foregroundStyle(Crucible.Color.ink)
                            .frame(minHeight: 44)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Crucible.Color.card)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Crucible.Color.hairline, lineWidth: 1)
                            )
                    }

                    // Media tile grid
                    if !composer.mediaCaptures.isEmpty {
                        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(Array(composer.mediaCaptures.enumerated()), id: \.offset) { index, capture in
                                MediaTile(
                                    localIdentifier: capture.localIdentifier,
                                    mediaType: capture.mediaType,
                                    onRemove: { composer.removeMedia(at: index) },
                                    onTap: {
                                        guard capture.mediaType != .voice else { return }
                                        selectedMedia = MediaDisplayItem(
                                            id: UUID(),
                                            localIdentifier: capture.localIdentifier,
                                            mediaType: capture.mediaType,
                                            thumbnailCacheFilename: nil,
                                            isAccessible: true
                                        )
                                    }
                                )
                            }

                            // Add tile
                            Button {
                                composer.showCamera = true
                            } label: {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Crucible.Color.divider, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                                    .aspectRatio(1, contentMode: .fit)
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
        .sheet(isPresented: $composer.showCamera) {
            CameraPickerView(
                captureMode: .both,
                onCapture: { result in
                    composer.showCamera = false
                    Task { @MainActor in
                        guard let camera = composer.cameraService else { return }
                        do {
                            switch result {
                            case .photo(let image):
                                let id = try await camera.savePhoto(image)
                                composer.addMedia(localIdentifier: id, mediaType: .image)
                            case .video(let url):
                                let id = try await camera.saveVideo(at: url)
                                composer.addMedia(localIdentifier: id, mediaType: .video)
                            }
                        } catch {
                            print("Camera capture failed: \(error)")
                        }
                    }
                },
                onDismiss: { composer.showCamera = false }
            )
        }
        .fullScreenCover(item: $selectedMedia) { item in
            MediaViewerView(item: item)
        }
        .onChange(of: speechService.isRecording) { wasRecording, isRecording in
            guard wasRecording, !isRecording else { return }
            guard composer.pendingAudioAppend else { return }
            composer.pendingAudioAppend = false

            let transcript = speechService.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let path = speechService.lastRecordingPath {
                if saveVoiceEntries {
                    composer.mediaCaptures.append((localIdentifier: path, mediaType: .voice))
                    if !transcript.isEmpty { composer.pendingTranscripts.append(transcript) }
                } else {
                    // Primary audio discarded by user preference; derived transcript still retained.
                    AudioPlayerService.deleteAudio(filename: path)
                    if !transcript.isEmpty { composer.pendingTranscripts.append(transcript) }
                }
            } else if !transcript.isEmpty {
                composer.pendingTranscripts.append(transcript)
            }
            speechService.transcribedText = ""
            speechService.lastRecordingPath = nil
        }
    }

    private var activeToolbarType: String? {
        if composer.isRecording { return "audio" }
        if showTextEditor || !composer.textContent.isEmpty { return "text" }
        return nil
    }

    private var itemCount: Int {
        var count = composer.mediaCaptures.count
        count += composer.pendingTranscripts.count
        if composer.isRecording { count += 1 }
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

struct AttachmentRow<Content: View, Actions: View>: View {
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

// MARK: - Media Tile

/// Square tile — the thumbnail IS the type identifier.
/// Photos and videos show themselves (no fold, no label).
/// Audio and text get a quieted placeholder + small corner fold in the media color.
/// Tap to view, press-and-hold for context menu.
struct MediaTile: View {
    let localIdentifier: String
    let mediaType: MediaReference.MediaType
    var onRemove: (() -> Void)? = nil
    var onTap: (() -> Void)? = nil
    @State private var thumbnail: UIImage? = nil
    @StateObject private var player = AudioPlayerService.shared

    /// Only audio and text get a fold — photos/videos carry their own visual
    private var needsFold: Bool {
        mediaType == .voice
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Tile content
            Group {
                if mediaType == .voice {
                    // Audio: quieted waveform on white, tap to play
                    let isPlaying = player.isPlaying && player.currentFile == localIdentifier
                    VStack(spacing: 5) {
                        HStack(spacing: 2) {
                            ForEach(0..<10, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(isPlaying ? Crucible.Color.Media.audio : Crucible.Color.Media.audio.opacity(0.55))
                                    .frame(width: 2.5, height: CGFloat(6 + (i % 5) * 4))
                            }
                        }
                        .frame(height: 20)

                        if isPlaying {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Crucible.Color.Media.audio)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Crucible.Color.card)
                } else if let thumbnail {
                    // Photo/video: the image IS the tile
                    GeometryReader { geo in
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.width)
                    }
                } else {
                    Crucible.Color.sunk
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Crucible.Color.hairline, lineWidth: 1)
            )

            // Corner fold — only for audio and text (no native visual)
            if needsFold {
                CornerFold(color: Crucible.Color.Media.audio)
            }

            // Video play chevron (centered, small)
            if mediaType == .video {
                Circle()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: 24, height: 24)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Crucible.Color.ink)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Remove button (top-left × badge)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(4)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onTapGesture {
            if mediaType == .voice {
                // Audio: toggle playback inline
                if player.isPlaying && player.currentFile == localIdentifier {
                    player.stop()
                } else {
                    player.play(filename: localIdentifier)
                }
            } else {
                onTap?()
            }
        }
        .contextMenu {
            if let onRemove {
                Button(role: .destructive) { onRemove() } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .task {
            guard mediaType != .voice else { return }
            if let cached = await ThumbnailService.shared.cacheThumbnail(for: localIdentifier) {
                thumbnail = ThumbnailService.shared.cachedThumbnail(filename: cached)
            }
        }
    }
}

/// 12pt corner fold in the media color, top-right. Only used on audio & text tiles.
private struct CornerFold: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let path = Path { p in
                p.move(to: CGPoint(x: size.width, y: 0))
                p.addLine(to: CGPoint(x: size.width, y: size.height))
                p.addLine(to: CGPoint(x: 0, y: 0))
                p.closeSubpath()
            }
            context.fill(path, with: .color(color.opacity(0.8)))
        }
        .frame(width: 12, height: 12)
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
