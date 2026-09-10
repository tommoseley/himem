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

    /// **REVERSES `sortsByCreatedAtAscending` (2026-09-10).** This assertion
    /// used to pin `[.voice, .video, .image]` — the input re-sorted by
    /// `createdAt`. That was an *implementation* choice, not a decided one:
    /// `Memory Detail · long-memory navigation.md` describes the Compact view
    /// as a table of contents and is **silent on ordering**.
    ///
    /// **What it collided with.** A memory's part order is owned by
    /// `MemoryClipEdge.orderInMemory` — `edgesArray` sorts by it,
    /// `mediaReferencesArray` inherits that, and `EntryMapper` carries it into
    /// `mediaItems`, with `EvidenceEdgeReadWriteTests` pinning that reads
    /// "respect each memory's per-edge `orderInMemory` — **not**
    /// `ref.createdAt`". The renderer then threw that away and re-sorted, so
    /// the documented append semantics (*"New clips append in
    /// `orderInMemory`/`capturedAt` order"*, unified editing model §"Adding
    /// clips to a memory") were **unobservable**: an old clip added to a
    /// memory today jumped to the top instead of appearing where it was put.
    ///
    /// **The failure this test now guards is a REORDER, not a sort.** Input
    /// arrives in edge order; the renderer's job is to draw it, not to have an
    /// opinion about it.
    @Test func preservesEdgeOrderWhenCaptureTimeDisagrees() {
        // Edge order [image, voice, video] with DESCENDING capture times —
        // the shape produced by adding older clips to an existing memory.
        let items: [MediaDisplayItem] = [
            makeItem(.image, secondsAfterEpoch: 30),
            makeItem(.voice, secondsAfterEpoch: 10),
            makeItem(.video, secondsAfterEpoch: 20)
        ]
        let result = ChronologicalCaptureStream.compactItems(from: items)
        #expect(result.map(\.mediaType) == [.image, .voice, .video], """
            The renderer re-ordered its input. `mediaItems` arrives in \
            `orderInMemory` order from EntryMapper; re-sorting by createdAt \
            discards the only per-memory sequence the model has, and makes \
            "append" mean nothing.
            """)
    }

    /// The twin site. `panels` (Full mode) had the identical `sorted` call, and
    /// fixing one renderer while leaving the other would leave Full and Compact
    /// describing the same memory in two different orders — the two-sets family
    /// at the view layer, which is the class this change exists to close.
    @Test func fullAndCompactAgreeOnOrder() {
        let items: [MediaDisplayItem] = [
            makeItem(.note,  secondsAfterEpoch: 99),
            makeItem(.voice, secondsAfterEpoch: 1)
        ]
        #expect(
            ChronologicalCaptureStream.orderedItems(from: items).map(\.id)
                == ChronologicalCaptureStream.compactItems(from: items).map(\.id)
        )
    }

    /// **Guards the CLASS, not the two instances.** `panels` is `private`, so
    /// no behavioural test can reach it — and it is exactly where the second
    /// copy of this defect lived for two months while `compactItems` had a test
    /// suite of its own. A third renderer added later would re-sort locally and
    /// nothing would notice, which is the shape CLAUDE.md § Guard the Caller
    /// names: a correct owner that a caller stops consulting.
    ///
    /// So: **no renderer in this file may sort `mediaItems`.** Order is
    /// `orderedItems(from:)`'s decision alone.
    @Test func noRendererReSortsTheMemorysParts() throws {
        let src = try Self.streamSource()
        let offenders = src.components(separatedBy: "\n").enumerated().filter { _, line in
            Self.isOffendingSort(line)
        }
        #expect(offenders.isEmpty, """
            A renderer sorts the memory's parts locally instead of asking \
            `orderedItems(from:)`. That is how Full and Compact diverged. \
            Sites: \(offenders.map { "\($0.offset + 1): \($0.element.trimmingCharacters(in: .whitespaces))" })
            """)
    }

    /// Self-tests, including a **malformed input** per CLAUDE.md § Guard the
    /// Caller — a scanner's input is every line of the file, not what a test
    /// constructs, and one that traps takes down the host rather than failing.
    @Test func theSortScannerSeesTheOffenderAndIgnoresTheRest() {
        #expect(Self.isOffendingSort("let sorted = entry.mediaItems.sorted { $0.createdAt < $1.createdAt }"))
        #expect(Self.isOffendingSort("        items.sorted { $0.createdAt < $1.createdAt }"))
        #expect(!Self.isOffendingSort("        orderedItems(from: items)"), "the owner is not an offender")
        #expect(!Self.isOffendingSort("/// used to be items.sorted { $0.createdAt < $1.createdAt }"),
                "prose is not code")
        #expect(!Self.isOffendingSort(""), "a degenerate line must not match or trap")
        #expect(!Self.isOffendingSort("   "), "whitespace only must not match or trap")
        #expect(!Self.isOffendingSort("sorted"), "a bare token is not a sort call")
    }

    static func isOffendingSort(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.hasPrefix("//"), !t.hasPrefix("///") else { return false }
        return t.contains(".sorted") && t.contains("createdAt")
    }

    /// Throws rather than returning empty, so the guard cannot pass by failing
    /// to find its subject.
    static func streamSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MemoryStream/Views/Journal/ChronologicalCaptureStream.swift")
        guard let s = try? String(contentsOf: url, encoding: .utf8) else {
            throw ScanFailure.unreadable(url.path)
        }
        return s
    }

    enum ScanFailure: Error { case unreadable(String) }

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
