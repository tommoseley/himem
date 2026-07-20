import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for the RecycleBin thumbnail fix (July 20 2026). The bin
/// rows showed no photo/video thumbnail because `RecycledClipDisplay`
/// carried no thumbnail source at all (cause #1 — not a recycledAt
/// over-filter). These lock that the display model captures the same
/// `(osIdentifier, mediaType)` the live row resolves through
/// `ThumbnailService`, and only for the media types that have a thumbnail.
@MainActor
@Suite(.serialized)
struct RecycledClipDisplayThumbnailTests {

    private func makeRef(_ storage: StorageService, type: MediaReference.MediaType, osId: String) -> MediaReference {
        let r = MediaReference(context: storage.viewContext)
        r.id = UUID()
        r.mediaType = type.rawValue
        r.osIdentifier = osId
        return r
    }

    @Test func photoAndVideo_carryThumbnailSource() {
        let s = StorageService(inMemory: true)
        let photo = RecycledClipDisplay(ref: makeRef(s, type: .image, osId: "p.heic"))
        #expect(photo.thumbnailOSIdentifier == "p.heic")
        #expect(photo.thumbnailMediaType == .image)

        let video = RecycledClipDisplay(ref: makeRef(s, type: .video, osId: "v.mov"))
        #expect(video.thumbnailOSIdentifier == "v.mov")
        #expect(video.thumbnailMediaType == .video)
    }

    @Test func voiceNoteAndInbox_haveNoThumbnailSource() {
        let s = StorageService(inMemory: true)
        #expect(RecycledClipDisplay(ref: makeRef(s, type: .voice, osId: "a.caf")).thumbnailOSIdentifier == nil)
        #expect(RecycledClipDisplay(ref: makeRef(s, type: .note, osId: "note-marker")).thumbnailOSIdentifier == nil)

        let inbox = InboxClip(
            clipId: UUID(), capturedAt: Date(), duration: 1, transcript: "hi",
            latitude: nil, longitude: nil, source: "watch", audioFilename: "a.m4a"
        )
        #expect(RecycledClipDisplay(inboxClip: inbox).thumbnailOSIdentifier == nil)
    }
}
