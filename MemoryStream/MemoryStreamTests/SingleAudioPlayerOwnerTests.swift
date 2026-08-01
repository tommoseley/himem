import Testing
import Foundation
@testable import HiMem

/// F23 · T2.3 — **one owner for phone playback.**
///
/// `SessionListView` carried a hand-rolled `AVAudioPlayer` (`:1379-1411`
/// pre-fix) that duplicated `AudioPlayerService` and omitted its
/// `AVAudioPlayerDelegate`. A bench clip played to its natural end therefore
/// never routed through `stop()`: the `.playback` session stayed active and the
/// row stayed lit.
///
/// That is verbatim the bug `AudioPlayerService.swift:44-53` documents as
/// already fixed — *"on a plugged-in iPhone made the device feel like it was
/// refusing to sleep"* — and it contravenes `CLAUDE.md` §Wake Lock, where
/// playback is explicitly NOT capture and must not hold the session open.
///
/// **The owner existed and simply wasn't used.** So the guard is not "is
/// `AudioPlayerService` correct" (it was, twice over) but the F18 lesson: *the
/// invariant is one owner, not merely that the owner is correct.* A second
/// player is the defect, whatever it does.
///
/// Scope is the phone app target. The watch app has its own player
/// (`WatchPlaybackPeekView`) in a separate target with its own audio session
/// lifecycle; it is not in this owner's remit.
@Suite
struct SingleAudioPlayerOwnerTests {

    /// THE GUARD. Exactly one production `AVAudioPlayer` instantiation in the
    /// phone target, and it is the service's.
    @Test func phoneTargetInstantiatesExactlyOneAudioPlayer() throws {
        let sites = try Self.playerInstantiations()
        #expect(
            sites.map(\.file) == ["AudioPlayerService.swift"],
            """
            More than one `AVAudioPlayer` is created in the phone target:
            \(sites.map { "  • \($0.file):\($0.line)" }.joined(separator: "\n"))

            A second player is a second audio-session lifecycle. The one that \
            shipped had no `AVAudioPlayerDelegate`, so playing to the natural \
            end never deactivated the `.playback` session — the wake-lock \
            contract broken exactly the way `AudioPlayerService` documents \
            having already fixed.

            Route playback through `AudioPlayerService` (`play(url:)` covers \
            the inbox store as well as the memory store).
            """
        )
    }

    /// Guards the guard: the matcher must be able to see an instantiation, or
    /// this passes by recognising nothing.
    @Test func theScannerCanSeeAnInstantiation() {
        #expect(Self.isInstantiation("let p = try AVAudioPlayer(contentsOf: url)"))
        #expect(Self.isInstantiation("player = try AVAudioPlayer(contentsOf: url)"))
        #expect(!Self.isInstantiation("private var player: AVAudioPlayer?"), "a declaration is not an instantiation")
        #expect(!Self.isInstantiation("/// Mirrors AudioPlayerService's AVAudioPlayer(…) pattern"), "prose is not code")
        #expect(!Self.isInstantiation("var currentAVPlayer: AVAudioPlayer? { player }"), "an accessor is not an instantiation")
    }

    struct Site { let file: String; let line: Int }

    static func isInstantiation(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.hasPrefix("//"), !t.hasPrefix("///") else { return false }
        return t.contains("AVAudioPlayer(")
    }

    static func playerInstantiations() throws -> [Site] {
        var out: [Site] = []
        // The phone app target only — `MemoryStream/MemoryStream/`.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MemoryStream")
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { throw Failure.rootNotFound(root.path) }
        var sawAnySwift = false
        for case let url as URL in walker where url.pathExtension == "swift" {
            sawAnySwift = true
            guard let src = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (i, line) in src.components(separatedBy: "\n").enumerated() where isInstantiation(line) {
                out.append(Site(file: url.lastPathComponent, line: i + 1))
            }
        }
        // Proves the walk reached source (the `fcb378b` pattern) — without it
        // this guard passes on an empty read.
        guard sawAnySwift else { throw Failure.walkFoundNoSource(root.path) }
        return out.sorted { $0.file < $1.file }
    }

    enum Failure: Error { case rootNotFound(String), walkFoundNoSource(String) }
}
