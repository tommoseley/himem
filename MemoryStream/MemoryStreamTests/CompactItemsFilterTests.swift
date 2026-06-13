import Testing
import Foundation
@testable import HiMem

/// Money tests for `ChronologicalCaptureStream.compactItems(from:)`.
/// Pre-fix the filter dropped `.image` and `.video` items entirely,
/// which meant a long memory with photos/videos showed them only in
/// Full mode. The user could not reach their own captures from the
/// Compact index they had chosen.
///
/// Spec: `docs/design/Memory Detail · long-memory navigation.md` —
/// "one row per clip" extends to every capture in the memory; the
/// Compact view is the memory's table of contents.
struct CompactItemsFilterTests {

    @Test func includesVoiceAndNote() {
        let items: [MediaDisplayItem] = [
            makeItem(.voice, secondsAfterEpoch: 0),
            makeItem(.note,  secondsAfterEpoch: 1)
        ]
        let result = ChronologicalCaptureStream.compactItems(from: items)
        #expect(result.count == 2)
        #expect(result.map(\.mediaType) == [.voice, .note])
    }

    /// **Money test for the photo/video Compact-mode bug.** Before the
    /// fix, this returned 2 (voice + note only). The Compact index
    /// hid photos and videos so the user could not reach them
    /// without leaving the Compact mode they had chosen. After the
    /// fix, all four media types appear, sorted chronologically.
    @Test func includesPhotoAndVideo() {
        let items: [MediaDisplayItem] = [
            makeItem(.voice, secondsAfterEpoch: 0),
            makeItem(.image, secondsAfterEpoch: 1),
            makeItem(.note,  secondsAfterEpoch: 2),
            makeItem(.video, secondsAfterEpoch: 3)
        ]
        let result = ChronologicalCaptureStream.compactItems(from: items)
        #expect(result.count == 4)
        #expect(result.map(\.mediaType) == [.voice, .image, .note, .video])
    }

    @Test func sortsByCreatedAtAscending() {
        let items: [MediaDisplayItem] = [
            makeItem(.image, secondsAfterEpoch: 30),
            makeItem(.voice, secondsAfterEpoch: 10),
            makeItem(.video, secondsAfterEpoch: 20)
        ]
        let result = ChronologicalCaptureStream.compactItems(from: items)
        #expect(result.map(\.mediaType) == [.voice, .video, .image])
    }

    @Test func emptyInputReturnsEmpty() {
        let result = ChronologicalCaptureStream.compactItems(from: [])
        #expect(result.isEmpty)
    }

    // MARK: - Helpers

    private func makeItem(
        _ type: MediaReference.MediaType,
        secondsAfterEpoch: TimeInterval
    ) -> MediaDisplayItem {
        MediaDisplayItem(
            id: UUID(),
            localIdentifier: UUID().uuidString,
            mediaType: type,
            thumbnailCacheFilename: nil,
            isAccessible: true,
            createdAt: Date(timeIntervalSince1970: secondsAfterEpoch)
        )
    }
}
