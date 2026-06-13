import Testing
import Foundation
import AVFoundation
import UIKit
@testable import HiMem

/// Money test for the "videos in ubiquity have no thumbnail" regression
/// (Tom 2026-06-09). Before the fix, `ThumbnailService.cacheThumbnail`
/// hardcoded `mediaType: .image` and tried to load video bytes with
/// `UIImage(data:)`, which silently fails. Result: every video in the
/// chronological capture stream rendered as a generic "video" glyph
/// placeholder.
///
/// `extractThumbnailImage(from:mediaType:size:)` is the pure helper that
/// owns the per-media-type decoding (UIImage for images,
/// AVAssetImageGenerator for videos). Bug-first: this assertion failed
/// to compile against the pre-fix codebase because the helper didn't
/// exist, then went green once added.
@MainActor
struct ThumbnailServiceVideoTests {

    @Test func extractThumbnailImage_videoFile_returnsImage() async throws {
        let url = try await Self.writeTinyMP4()
        defer { try? FileManager.default.removeItem(at: url) }

        let image = await ThumbnailService.extractThumbnailImage(
            from: url,
            mediaType: .video,
            size: CGSize(width: 200, height: 200)
        )
        #expect(image != nil, "Video URL must produce a still frame via AVAssetImageGenerator")
    }

    @Test func extractThumbnailImage_missingFile_returnsNil() async {
        // Defensive: a video URL pointing at nothing should fail
        // quietly (returns nil), not crash. Mirrors the
        // `UbiquityStore.downloadStatus == notDownloaded` case where
        // the file simply isn't on disk yet.
        let bogus = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).mp4")
        let image = await ThumbnailService.extractThumbnailImage(
            from: bogus,
            mediaType: .video,
            size: CGSize(width: 200, height: 200)
        )
        #expect(image == nil)
    }

    // MARK: - Fixture: write a 1-second blank MP4 to a temp URL

    /// Writes a programmatic 1-second 16×16 black video to a temp URL.
    /// Used in lieu of bundling a real .mp4 in the test bundle — keeps
    /// the test self-contained.
    private static func writeTinyMP4() async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumb-test-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 16,
            AVVideoHeightKey: 16,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 16,
                kCVPixelBufferHeightKey as String: 16,
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // One black 16×16 frame.
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            16, 16,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        guard let buffer = pixelBuffer else {
            throw NSError(domain: "ThumbnailServiceVideoTests", code: 1)
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = CVPixelBufferGetBaseAddress(buffer)
        let bytes = CVPixelBufferGetBytesPerRow(buffer) * 16
        memset(base, 0, bytes)
        CVPixelBufferUnlockBaseAddress(buffer, [])

        // Loop a few frames so the asset has a valid duration the
        // generator can sample. Using 1s duration at 30fps = 30 frames.
        for i in 0..<30 {
            while !input.isReadyForMoreMediaData { await Task.yield() }
            adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(i), timescale: 30))
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw NSError(domain: "ThumbnailServiceVideoTests", code: Int(writer.status.rawValue))
        }
        return url
    }
}
