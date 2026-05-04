import SwiftUI

/// Square tile — the thumbnail IS the type identifier.
/// Photos and videos show themselves (no fold, no label).
/// Audio and text get a quieted placeholder + small corner fold in the media color.
/// Tap to view, press-and-hold for context menu.
///
/// Used by both the (legacy) ComposerView and the new ContributeActionBox to
/// render captured-but-not-yet-committed media. Same visual primitive in both
/// surfaces so the user sees the same affordance regardless of where they
/// captured from.
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
    }
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
