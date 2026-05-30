import Foundation
import AVFoundation
import CryptoKit

/// Splits a phone master audio file into N per-clip audio files at
/// the offsets recorded by `NextClipController.nextTapOffsets`.
///
/// Phone uses one continuous `AVAudioFile` per recording session (the
/// engine writes to it via the input tap without interruption — see
/// `docs/design/on-a-roll-spec.md` § Implementation notes, "Phone
/// master-file-then-split"). At Save time we slice that file into the
/// per-clip outputs the rest of the app expects.
///
/// Watch on-a-roll multi-clip recordings also feed this splitter: the
/// watch ships one master file plus `nextTapOffsets`, and
/// `WatchSessionDelegate.acceptArrivedClip` runs `split` to produce N
/// children. Each child's `clipId` is derived deterministically from
/// `(masterClipId, offsetIndex)` via `deterministicChildClipId` so a
/// redelivered master always produces the same children —
/// `InboxManifest.acceptClip`'s dedup then handles redelivery without
/// per-clipId race gating.
enum VoiceClipSplitter {

    /// One slice of the master file, ready for downstream
    /// transcription + storage.
    struct ClipFragment: Equatable {
        let audioFilename: String
        let duration: TimeInterval
        let rollGroupId: UUID
    }

    enum SplitError: Error {
        case masterFileMissing(URL)
        case readFailed(String)
        case writeFailed(String)
    }

    // MARK: - Pure offset math (testable)

    /// 200ms of audio each side of every split. Each clip pair
    /// overlaps by `2 × splitOverlap` total so the transcriber sees
    /// the full word the user happened to tap Next through. Cuts
    /// stay honest in the audio file (each clip really does contain
    /// the surrounding context); only the transcripts get the
    /// benefit.
    static let splitOverlap: TimeInterval = 0.2

    /// Pure: turns the master duration + Next-tap offsets into the
    /// per-clip time ranges. Result count is always
    /// `nextTapOffsets.count + 1`. With the default overlap, clip N
    /// extends `splitOverlap` past its split into clip N+1, and clip
    /// N+1 starts `splitOverlap` before its preceding split — so a
    /// word the user tapped Next through is fully present in *both*
    /// clips' audio. The transcript on each clip ends up with the
    /// full word at the seam instead of `Receiv...` / `...ing`.
    ///
    /// First clip's start is clamped to 0; last clip's end is
    /// clamped to `masterDuration`. The 2s `MinClipDebouncer` floor
    /// guarantees consecutive offsets are well past 400ms apart, so
    /// overlap never swallows an entire interior clip.
    ///
    /// Filters offsets to `0 < offset < masterDuration` and to
    /// strictly-monotonic — defensive against clock skew or rapid
    /// taps the UI didn't debounce.
    static func segmentRanges(
        masterDuration: TimeInterval,
        nextTapOffsets: [TimeInterval],
        overlap: TimeInterval = splitOverlap
    ) -> [Range<TimeInterval>] {
        let cleaned = sanitize(offsets: nextTapOffsets, masterDuration: masterDuration)
        var ranges: [Range<TimeInterval>] = []
        var cursor: TimeInterval = 0
        for offset in cleaned {
            // This clip extends `overlap` past the split; the next
            // clip will start `overlap` before the split. Both clamp
            // to file bounds.
            let endWithOverlap = min(offset + overlap, masterDuration)
            ranges.append(cursor..<endWithOverlap)
            cursor = max(0, offset - overlap)
        }
        if cursor < masterDuration {
            ranges.append(cursor..<masterDuration)
        }
        return ranges
    }

    /// Drops zero, negative, beyond-duration, and out-of-order
    /// offsets. Returns a strictly-increasing list within
    /// `(0, masterDuration)`.
    static func sanitize(
        offsets: [TimeInterval],
        masterDuration: TimeInterval
    ) -> [TimeInterval] {
        var last: TimeInterval = 0
        var out: [TimeInterval] = []
        for o in offsets {
            guard o > last, o < masterDuration else { continue }
            out.append(o)
            last = o
        }
        return out
    }

    // MARK: - Deterministic child clipId

    /// Derives a stable child `clipId` for the split fragment at
    /// `offsetIndex` of `master`. Same inputs → same UUID, every time.
    /// Redelivery of the same master produces children with the same
    /// clipIds the manifest already has — `InboxManifest.acceptClip`'s
    /// dedup then drops the duplicates by construction, with no
    /// per-clipId critical section needed.
    ///
    /// Seed format: `"clip-fragment|<master.uuidString>|<offsetIndex>"`.
    /// Hashed with SHA-256; first 16 bytes form the UUID. Matches the
    /// `FragmentMigration.deterministicUUID` idiom already shipping in
    /// this project, so contributors meet the same pattern twice.
    ///
    /// Seed format is locked: changing it would invalidate every
    /// persisted split clipId for in-flight roll sessions on Tom's
    /// dev devices. Treat as a stable contract.
    static func deterministicChildClipId(master: UUID, offsetIndex: Int) -> UUID {
        let seed = "clip-fragment|\(master.uuidString)|\(offsetIndex)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    // MARK: - File I/O

    /// Reads `masterURL` and writes N per-clip files into
    /// `outputDir`, named `<rollGroupId>-<index>.caf`. Returns the
    /// resulting `ClipFragment` list (filenames only — caller is
    /// responsible for transcription + storage attachment).
    ///
    /// Master file is left in place; caller deletes after use
    /// (along with the offsets sidecar if any).
    static func split(
        masterURL: URL,
        nextTapOffsets: [TimeInterval],
        outputDir: URL,
        rollGroupId: UUID
    ) async throws -> [ClipFragment] {
        guard FileManager.default.fileExists(atPath: masterURL.path) else {
            throw SplitError.masterFileMissing(masterURL)
        }
        let reader: AVAudioFile
        do {
            reader = try AVAudioFile(forReading: masterURL)
        } catch {
            throw SplitError.readFailed(error.localizedDescription)
        }
        let sampleRate = reader.processingFormat.sampleRate
        let totalFrames = AVAudioFrameCount(reader.length)
        let masterDuration = TimeInterval(totalFrames) / sampleRate
        let ranges = segmentRanges(
            masterDuration: masterDuration,
            nextTapOffsets: nextTapOffsets
        )

        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        var fragments: [ClipFragment] = []
        let processingFormat = reader.processingFormat
        let chunkFrames: AVAudioFrameCount = 4096

        for (index, range) in ranges.enumerated() {
            let startFrame = AVAudioFramePosition(range.lowerBound * sampleRate)
            let endFrame = AVAudioFramePosition(range.upperBound * sampleRate)
            let framesToCopy = AVAudioFrameCount(max(0, endFrame - startFrame))
            guard framesToCopy > 0 else { continue }

            let filename = "\(rollGroupId.uuidString)-\(index + 1).caf"
            let outputURL = outputDir.appendingPathComponent(filename)
            // If a prior split left a stale file, replace it.
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }

            let writer: AVAudioFile
            do {
                writer = try AVAudioFile(
                    forWriting: outputURL,
                    settings: processingFormat.settings,
                    commonFormat: processingFormat.commonFormat,
                    interleaved: processingFormat.isInterleaved
                )
            } catch {
                throw SplitError.writeFailed(error.localizedDescription)
            }

            reader.framePosition = startFrame
            var remaining = framesToCopy
            while remaining > 0 {
                let toRead = min(chunkFrames, remaining)
                guard let buffer = AVAudioPCMBuffer(
                    pcmFormat: processingFormat,
                    frameCapacity: toRead
                ) else {
                    throw SplitError.readFailed("buffer alloc failed")
                }
                do {
                    try reader.read(into: buffer, frameCount: toRead)
                } catch {
                    throw SplitError.readFailed(error.localizedDescription)
                }
                if buffer.frameLength == 0 { break }
                do {
                    try writer.write(from: buffer)
                } catch {
                    throw SplitError.writeFailed(error.localizedDescription)
                }
                remaining = remaining > AVAudioFrameCount(buffer.frameLength)
                    ? remaining - AVAudioFrameCount(buffer.frameLength)
                    : 0
            }
            fragments.append(ClipFragment(
                audioFilename: filename,
                duration: TimeInterval(framesToCopy) / sampleRate,
                rollGroupId: rollGroupId
            ))
        }
        return fragments
    }
}
