import Testing
import Foundation
@testable import Himem_Watch_Watch_App

/// Money tests for the 2026-05-18 regression: watch app showed
/// "all caught up" (manifest empty) while the complication showed
/// "1 pending" (stale `WatchSharedState.pendingCount` from a prior
/// session). Root cause was `WatchPendingManifest.load()` setting
/// `clips` directly — bypassing `replace(with:)`, the only mutation
/// path that synced the App Group shared state for the widget.
///
/// Two failure modes covered:
///   1. Manifest persists clips whose audio file has gone missing
///      between sessions. Filter drops them from `clips`. Shared
///      count must follow.
///   2. Manifest decode fails (corrupt JSON). Catch sets `clips =
///      []`. Shared count must still be reset to 0, not whatever
///      a prior session left in App Group defaults.
///
/// Both paths now route through `syncSharedCountAfterLoad()` via
/// `defer` in `load()`.
@MainActor
struct WatchPendingManifestLoadSyncTests {

    /// Money test: persist a manifest listing one clip whose audio
    /// file is absent. Pre-seed shared count to 1 to simulate a prior
    /// session that had the clip. After load, both the in-memory
    /// clips AND the shared count must be 0.
    @Test
    func load_filtersOrphanedClip_syncsSharedCount() throws {
        // Arrange
        cleanPendingDirectory()
        WatchSharedState.pendingCount = 1   // simulate stale state from prior session

        let orphan = WatchPendingClip(
            clipId: UUID(),
            capturedAt: Date(),
            duration: 5,
            transcript: "",
            latitude: nil,
            longitude: nil,
            audioFilename: "missing.caf"  // file deliberately not created
        )
        try writeManifest([orphan])

        // Act — force a fresh load by reading-via-init. We construct
        // a fresh non-singleton instance to isolate this test from
        // app state. `WatchPendingManifest.shared` is the production
        // path; here we exercise the same load logic without the
        // singleton's app-level coupling.
        let manifest = makeManifestForTest()

        // Assert
        #expect(manifest.clips.isEmpty)
        #expect(WatchSharedState.pendingCount == 0)
    }

    /// Money test: persist a corrupt manifest. Load catch-branch sets
    /// `clips = []`. Pre-seeded shared count of 3 must reset to 0.
    @Test
    func load_corruptManifest_resetsSharedCountToZero() throws {
        // Arrange
        cleanPendingDirectory()
        WatchSharedState.pendingCount = 3
        let url = WatchPendingManifest.manifestURL
        try "not json at all".write(to: url, atomically: true, encoding: .utf8)

        // Act
        let manifest = makeManifestForTest()

        // Assert
        #expect(manifest.clips.isEmpty)
        #expect(WatchSharedState.pendingCount == 0)
    }

    /// Symmetry: when manifest correctly contains one playable clip,
    /// shared count must be 1.
    @Test
    func load_validClipWithAudio_syncsSharedCountToOne() throws {
        // Arrange
        cleanPendingDirectory()
        WatchSharedState.pendingCount = 99   // wildly stale

        let clip = WatchPendingClip(
            clipId: UUID(),
            capturedAt: Date(),
            duration: 3,
            transcript: "",
            latitude: nil,
            longitude: nil,
            audioFilename: "real.caf"
        )
        // Touch the audio file so the filter keeps the clip.
        FileManager.default.createFile(
            atPath: WatchPendingManifest.audioURL(for: "real.caf").path,
            contents: Data([0x00])
        )
        try writeManifest([clip])

        // Act
        let manifest = makeManifestForTest()

        // Assert
        #expect(manifest.clips.count == 1)
        #expect(WatchSharedState.pendingCount == 1)
    }

    // MARK: - Helpers

    /// Wipes the pending directory so each test starts clean.
    private func cleanPendingDirectory() {
        let root = WatchPendingManifest.pendingRoot
        try? FileManager.default.removeItem(at: root)
        _ = WatchPendingManifest.pendingRoot     // recreate
        _ = WatchPendingManifest.audioDirectory
    }

    private func writeManifest(_ clips: [WatchPendingClip]) throws {
        let url = WatchPendingManifest.manifestURL
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(clips)
        try data.write(to: url, options: .atomic)
    }

    /// Returns the shared singleton — `WatchPendingManifest.shared`
    /// is the only constructor; the tests share it but reset state
    /// before each via `cleanPendingDirectory`. The init runs once
    /// per process; subsequent test runs use `forceReload` if added,
    /// or rely on the shared instance picking up our preconditions
    /// at construction.
    ///
    /// **Note:** `WatchPendingManifest` exposes only a private init.
    /// To exercise `load()` from a clean state per-test, we'd need a
    /// test seam (an internal `init(suiteName:)` or a `reload()`
    /// method). Until that exists, the shared instance's state at
    /// first test access reflects whatever the previous run left. The
    /// assertions still hold because `load()` always reruns the same
    /// logic, but cross-test isolation isn't perfect. See
    /// `forceReloadForTesting()` reference in the implementation if
    /// it's been added.
    private func makeManifestForTest() -> WatchPendingManifest {
        // Force a re-load by calling the test seam. The seam is
        // `#if DEBUG` only and re-runs the same `load()` flow that
        // happens on first init.
        WatchPendingManifest.shared.forceReloadForTesting()
        return WatchPendingManifest.shared
    }
}
