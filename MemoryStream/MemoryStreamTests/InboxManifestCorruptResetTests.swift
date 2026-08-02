import Testing
import Foundation
@testable import HiMem

/// F23 · T1.4 — **the corrupt-manifest reset destroyed every pending clip's
/// metadata.**
///
/// `load()`'s catch was `clips = []` under the comment "start fresh rather
/// than block the user" (`InboxManifest.swift:1024` pre-fix). The next
/// mutation calls `persist()`, which writes the whole in-memory array over
/// `manifest.json` — so an unreadable file became an empty one, and every
/// pending clip's transcript, capturedAt, lat/lon and rollGroup went with it.
///
/// The comment establishes that blocking the user is bad. It never establishes
/// that the rows are worthless. And they are not recoverable from anywhere
/// else: `backupManifestIfNeeded` is gated on *any* `manifest.backup.*`
/// existing, making it a one-shot lifetime snapshot rather than a recovery
/// point at the moment of corruption.
///
/// The rule (punch list, F23 ship item 4): **never persist over an unreadable
/// manifest.** The bytes move aside first, intact; only then do we start fresh.
@MainActor
@Suite(.serialized)
struct InboxManifestCorruptResetTests {

    private func makeSandbox() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("himem-manifest-quarantine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// A real manifest's worth of metadata — the thing the reset used to
    /// discard. Deliberately not valid `[InboxClip]` JSON: that is what makes
    /// `load()` take the catch.
    private let unreadableBytes = Data(
        #"[{"clipId":"not-a-uuid","transcript":"the dinner at the CIA","capturedAt":"#.utf8
    )

    /// THE MONEY TEST. After the reset path runs, the rows must still exist
    /// somewhere on disk — a later `persist()` writing `[]` to `manifest.json`
    /// must not be able to reach them.
    @Test func unreadableManifestSurvivesTheResetThatFollowsIt() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = root.appendingPathComponent("manifest.json")
        try unreadableBytes.write(to: manifest)

        // What `load()`'s catch now does before `clips = []`.
        let quarantined = InboxManifest.quarantineUnreadableManifest(at: manifest)

        // What the very next mutation does: persist the empty in-memory array.
        try Data("[]".utf8).write(to: manifest)

        let survivor = try #require(quarantined, "the bytes must be moved somewhere we can name")
        #expect(survivor != manifest, "quarantining in place is not quarantining")
        #expect(
            try Data(contentsOf: survivor) == unreadableBytes,
            "every pending clip's transcript, capturedAt, lat/lon and rollGroup, byte-for-byte"
        )
    }

    /// A move, not a copy: the same unreadable bytes must not be re-read — and
    /// re-quarantined — on every subsequent launch.
    @Test func theUnreadableFileIsMovedAsideNotCopied() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = root.appendingPathComponent("manifest.json")
        try unreadableBytes.write(to: manifest)

        InboxManifest.quarantineUnreadableManifest(at: manifest)

        #expect(!FileManager.default.fileExists(atPath: manifest.path),
                "left in place, the next launch quarantines it again, forever")
    }

    /// Two corruptions in the same second must not collide — the second must
    /// not overwrite the first survivor.
    @Test func aSecondQuarantineDoesNotOverwriteTheFirst() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = root.appendingPathComponent("manifest.json")
        let fixedNow = Date(timeIntervalSince1970: 1_785_000_000)

        try Data("first".utf8).write(to: manifest)
        let a = try #require(InboxManifest.quarantineUnreadableManifest(at: manifest, now: fixedNow))
        try Data("second".utf8).write(to: manifest)
        let b = try #require(InboxManifest.quarantineUnreadableManifest(at: manifest, now: fixedNow))

        #expect(a != b)
        #expect(try Data(contentsOf: a) == Data("first".utf8))
        #expect(try Data(contentsOf: b) == Data("second".utf8))
    }

    /// The non-empty companion. Nothing on disk → nothing to lose → the caller
    /// must be free to persist. Without this, a `quarantine` that always
    /// returned nil (block everything, forever) would pass the money test.
    @Test func noFileOnDiskIsNotAReasonToRefusePersisting() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("manifest.json")

        #expect(InboxManifest.quarantineUnreadableManifest(at: missing) != nil,
                "a fresh install decodes nothing; persisting is safe")
    }

    // MARK: - The caller uses it

    /// THE GATE. A correct quarantine that `load()` doesn't call rebuilds the
    /// defect exactly. The reset may not stand alone in its catch.
    @Test func theResetQuarantinesBeforeItStartsFresh() throws {
        let source = try Self.inboxManifestSource()
        #expect(
            Self.resetIsGuarded(in: source),
            """
            `clips = []` runs in a catch that never moves the unreadable file \
            aside. The next `persist()` writes the empty array over \
            `manifest.json` and every pending clip's transcript, capturedAt, \
            lat/lon and rollGroup is gone — the bytes were the only copy.
            """
        )
    }

    /// Guards the guard: the scanner must be able to see the shipped defect,
    /// or it passes by recognizing nothing.
    @Test func theScannerCanSeeTheUnguardedReset() {
        let shipped = """
            } catch {
                // Corrupt manifest — start fresh rather than block the user.
                clips = []
            }
            """
        #expect(!Self.resetIsGuarded(in: shipped), "the shipped defect, verbatim")

        let guarded = """
            } catch {
                manifestIsUnreadable = (Self.quarantineUnreadableManifest(at: url) == nil)
                clips = []
            }
            """
        #expect(Self.resetIsGuarded(in: guarded))
    }

    /// True when every `clips = []` that sits inside a `catch` is preceded,
    /// within that catch, by the quarantine call.
    static func resetIsGuarded(in source: String) -> Bool {
        let lines = source.components(separatedBy: "\n")
        var catchStart: Int? = nil
        var sawReset = false
        for (i, line) in lines.enumerated() {
            if line.contains("catch {") { catchStart = i }
            guard line.trimmingCharacters(in: .whitespaces) == "clips = []" else { continue }
            guard let start = catchStart else { continue }   // not in a catch
            sawReset = true
            let body = lines[start...i].joined(separator: "\n")
            if !body.contains("quarantineUnreadableManifest") { return false }
        }
        return sawReset
    }

    static func inboxManifestSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // MemoryStreamTests
            .deletingLastPathComponent()          // MemoryStream (project dir)
            .appendingPathComponent("MemoryStream/Services/Storage/InboxManifest.swift")
        guard let src = try? String(contentsOf: url, encoding: .utf8), !src.isEmpty else {
            throw Failure.sourceNotFound(url.path)
        }
        return src
    }

    enum Failure: Error { case sourceNotFound(String) }
}
