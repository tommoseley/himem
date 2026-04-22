import SwiftUI

struct MediaThumbnailView: View {
    let item: MediaDisplayItem
    var size: CGFloat = 72
    var onTap: () -> Void

    @State private var thumbnail: UIImage? = nil

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else if !item.isAccessible {
                        Image(systemName: "photo.slash")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
                .frame(width: size, height: size)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if item.mediaType == .video {
                    Image(systemName: "play.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        if let filename = item.thumbnailCacheFilename,
           let cached = ThumbnailService.shared.cachedThumbnail(filename: filename) {
            thumbnail = cached
            return
        }
        thumbnail = await ThumbnailService.shared.fullImage(for: item.localIdentifier)
    }
}
