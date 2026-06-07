import SwiftUI
import AVFoundation

/// Square tile — the thumbnail IS the type identifier.
/// Photos and videos show themselves (no fold, no label).
/// Audio and text get a quieted placeholder + small corner fold in the media color.
/// Tap to view, press-and-hold for context menu.
///
/// Renders captured-but-not-yet-committed media tiles.
struct MediaTile: View {
    let localIdentifier: String
    let mediaType: MediaReference.MediaType
    /// When provided, a small timestamp footer is rendered:
    ///   - voice: "h:mm a · m:ss" (timestamp + audio duration).
    ///   - image / video: "h:mm a" overlaid at the bottom of the thumbnail
    ///     (white-on-gradient so it reads against any photo).
    /// Lets the user tell multiple captures on a single memory apart.
    var createdAt: Date? = nil
    var onRemove: (() -> Void)? = nil
    var onTap: (() -> Void)? = nil
    @State private var thumbnail: UIImage? = nil
    @State private var audioDuration: TimeInterval? = nil
    @ObservedObject private var player = AudioPlayerService.shared

    /// Only audio and text get a fold — photos/videos carry their own visual
    private var needsFold: Bool {
        mediaType == .voice
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Tile content
            Group {
                if mediaType == .voice {
                    // Audio: quieted waveform on white, tap to play.
                    let isPlaying = player.isPlaying && player.currentFile == localIdentifier
                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
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
                        Spacer(minLength: 0)

                        if let footer = audioFooterLabel {
                            Text(footer)
                                .font(.system(size: 10, weight: .medium).monospacedDigit())
                                .foregroundStyle(Crucible.Color.ink3)
                                .padding(.bottom, 6)
                                .padding(.horizontal, 4)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .accessibilityLabel(audioFooterAccessibilityLabel ?? "")
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

            // Capture-time overlay for image/video tiles. Voice tiles render
            // their footer inline (above) since they have no thumbnail to
            // sit on top of.
            if (mediaType == .image || mediaType == .video), let createdAt {
                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .allowsHitTesting(false)

                Text(Self.timeFormatter.string(from: createdAt))
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .accessibilityLabel("Captured at \(Self.timeFormatter.string(from: createdAt))")
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
                .accessibilityLabel("Remove attachment")
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
        .task(id: localIdentifier) {
            guard mediaType != .voice else { return }
            if let cached = await ThumbnailService.shared.cacheThumbnail(for: localIdentifier) {
                thumbnail = ThumbnailService.shared.cachedThumbnail(filename: cached)
            }
        }
        .task(id: localIdentifier) {
            // Load audio duration for the footer label. AVURLAsset.load is
            // async; the tile renders without a duration until this resolves.
            // No `fileExists` pre-check — `try? asset.load(.duration)`
            // returns nil for missing/unreadable files without throwing,
            // and avoiding the synchronous disk hit keeps the per-tile
            // `.task` off the main thread.
            guard mediaType == .voice, createdAt != nil else { return }
            let url = SpeechService.audioURL(for: localIdentifier)
            let asset = AVURLAsset(url: url)
            if let cm = try? await asset.load(.duration), cm.seconds.isFinite {
                audioDuration = cm.seconds
            }
        }
    }

    private var audioFooterLabel: String? {
        guard let createdAt else { return nil }
        let timestamp = Self.timeFormatter.string(from: createdAt)
        guard let audioDuration else { return timestamp }
        return "\(timestamp) · \(formatDuration(audioDuration))"
    }

    private var audioFooterAccessibilityLabel: String? {
        guard let createdAt else { return nil }
        let timestamp = Self.timeFormatter.string(from: createdAt)
        guard let audioDuration else { return "Recorded at \(timestamp)" }
        return "Recorded at \(timestamp), \(formatDuration(audioDuration)) long"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
}

/// 12pt corner fold in the media color, top-right. Only used on audio & text tiles.
struct CornerFold: View {
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
