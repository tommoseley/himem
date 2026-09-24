import Testing
import Foundation

/// **Guard the Caller — the drain must not ride on the bench.**
///
/// `ArrivedClipMaterializer.materializeAll` is the one-shot upgrade migration
/// AND the catch-up for any clip that finished transcribing while nothing was
/// looking. Its only production caller has been `SessionListView.onAppear`
/// (`:263`) — i.e. it runs *because the bench renders*, and it has no trigger
/// of its own.
///
/// That is `CLAUDE.md` § *Quieting a Busy Path Reveals What Was Riding On It*
/// in its load-bearing form: the vocabulary retirement deletes the bench, and
/// the drain would stop running with it. The consequence is not cosmetic —
/// an undrained `.transcribed` manifest row never becomes a `MediaReference`,
/// so it is invisible to the paperclip (`AddExistingClipsSheet`, which fetches
/// `edges.@count == 0`) *and* to Search (which reads `MediaReference`). The
/// user's own words become unreachable, which is the only irreversible failure
/// in the retirement (Tom, 2026-09-16).
///
/// The rule's remedy is **fix the trigger, not the silence**, so this asserts
/// the property that makes the deletion safe: *the drain has at least one
/// production owner outside the bench directory.* It deliberately does not pin
/// **which** owner, so the trigger can move without this becoming a chore —
/// but the failure message names the current one so a red is actionable.
///
/// Scanner discipline (`CLAUDE.md` § Guard the Caller):
/// - The walk **throws** if it reaches no source, so it cannot pass by
///   matching nothing.
/// - Matching splits on markers; **no `Range` is ever constructed**, so the
///   2026-08-25 inverted-range trap (199 failures across 110 suites) cannot be
///   reproduced here.
/// - Self-tests cover offender · clean · near-miss · **degenerate input**.
@Suite struct MaterializerDrainOwnerTests {

    enum GateFailure: Error { case sourceNotFound(String), noSourceWalked(String) }

    /// The call this guard is about, written once.
    private static let drainCall = "ArrivedClipMaterializer.materializeAll("

    /// The bench directory the vocabulary retirement deletes. A caller here
    /// does not count as an owner.
    private static let benchDirectory = "Views/Inbox/"

    // MARK: - The guard

    // `theDrainIsNotOwnedOnlyByTheBench` RETIRED BY SUPERSESSION, and the
    // rule it enforced was INVERTED rather than dropped (2026-09-24).
    //
    // F1 asserted the drain must keep at least one production owner outside
    // the bench, because an undrained `.transcribed` row never became a
    // `MediaReference` and was therefore invisible to the paperclip and to
    // Search — *"the user's own words become unreachable, which is the only
    // irreversible failure in the retirement"*.
    //
    // Transient capture removes the premise. A waiting capture is no longer
    // invisible: it is the card at the top of Memories and it is the
    // paperclip's inventory. So it does not need draining to be reachable,
    // and draining it automatically is the thing the descoping forbids —
    // *"forcing the second moves a decision from the user to the software"*.
    //
    // The replacement is `TransientCaptureSurfaceTests.noLaunchPathDrains`,
    // which asserts the opposite property: **no launch path may drain**, and
    // exactly one site materializes — her choosing "Start a new memory".
    // The concern F1 named is still guarded; what changed is which direction
    // keeps her words reachable.

    // MARK: - Self-tests — the guard must be able to fail, and must survive junk

    @Test("the matcher flags a bench-only caller set")
    func matcherFlagsTheOffender() {
        let offender = [
            "MemoryStream/Views/Inbox/SessionListView.swift":
                "        ArrivedClipMaterializer.materializeAll(in: context)\n"
        ]
        let callers = Self.callers(of: Self.drainCall, in: offender)
        #expect(callers.count == 1)
        #expect(callers.filter { !$0.contains(Self.benchDirectory) }.isEmpty)
    }

    @Test("the matcher accepts a bench-independent owner")
    func matcherAcceptsTheCleanShape() {
        let clean = [
            "MemoryStream/Views/Inbox/SessionListView.swift":
                "        ArrivedClipMaterializer.materializeAll(in: context)\n",
            "MemoryStream/Views/Launch/LaunchScreenView.swift":
                "        ArrivedClipMaterializer.materializeAll(in: ctx)\n"
        ]
        let callers = Self.callers(of: Self.drainCall, in: clean)
        #expect(callers.count == 2)
        #expect(callers.filter { !$0.contains(Self.benchDirectory) }.count == 1)
    }

    @Test("the matcher ignores near-misses and mentions in prose")
    func matcherIgnoresNearMisses() {
        let nearMiss = [
            // A doc comment naming the function is not a call.
            "MemoryStream/Services/Storage/InboxManifest.swift":
                "/// once `materializeAll` has drained the row into a ref\n",
            // A different member on the same type.
            "MemoryStream/Views/Journal/Foo.swift":
                "ArrivedClipMaterializer.materialize(clip, in: ctx)\n"
        ]
        #expect(Self.callers(of: Self.drainCall, in: nearMiss).isEmpty)
    }

    @Test("the matcher survives degenerate input")
    func matcherSurvivesDegenerateInput() {
        #expect(Self.callers(of: Self.drainCall, in: [:]).isEmpty)
        #expect(Self.callers(of: Self.drainCall, in: ["a.swift": ""]).isEmpty)
        // Truncated mid-token — the shape a partial write leaves behind.
        #expect(Self.callers(of: Self.drainCall, in: ["a.swift": "ArrivedClipMaterializer.materializeAl"]).isEmpty)
        // The marker with nothing after it.
        #expect(Self.callers(of: Self.drainCall, in: ["a.swift": Self.drainCall]).count == 1)
    }

    // MARK: - Scanner

    /// Pure matcher over a path→source map. Membership only — no offsets, no
    /// `Range`, so there is no slice to invert.
    private static func callers(of call: String, in sources: [String: String]) -> [String] {
        sources.compactMap { path, text in text.contains(call) ? path : nil }
    }

    /// Walks the app target and returns repo-relative paths of files
    /// containing `call`. Throws if the walk reaches no source at all —
    /// a scanner that silently inspects nothing reports a clean sweep forever.
    private static func productionCallers(of call: String) throws -> [String] {
        let appRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // MemoryStreamTests/
            .deletingLastPathComponent()      // MemoryStream/  (project dir)
            .appendingPathComponent("MemoryStream")

        guard let walker = FileManager.default.enumerator(
            at: appRoot, includingPropertiesForKeys: nil
        ) else {
            throw GateFailure.sourceNotFound(appRoot.path)
        }

        var sources: [String: String] = [:]
        // Consume the URL the enumerator hands us — never retype a path
        // (CLAUDE.md § A First Reading of an Unfamiliar Log, NEVER RETYPE A PATH).
        for case let url as URL in walker where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let relative = url.path.components(separatedBy: "/MemoryStream/MemoryStream/").last ?? url.path
            sources[relative] = text
        }

        guard !sources.isEmpty else {
            throw GateFailure.noSourceWalked(appRoot.path)
        }
        return callers(of: call, in: sources)
    }
}
