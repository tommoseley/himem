import Testing
import Foundation
@testable import HiMem

/// F23 · **the orphan sweep must not be reachable.**
///
/// `MediaBlobOrphanSweep` judges files in the **shared ubiquity container**
/// against a keep-set that is partly **device-local**:
/// `referencedFilenames` unions `MediaReference.osIdentifier` (CloudKit-synced)
/// with `InboxManifest.referencedAudioFilenames` — and the manifest lives in the
/// app sandbox at `Documents/ClipInbox`, documented in its own source as
/// "per-device sync state, not user content".
///
/// Unpromoted watch clips exist only as manifest rows. So on a second device —
/// or on the same device after a manifest reset — every staged clip in
/// `Inbox/` is unreferenced by construction, ages past the 1-hour guard, and is
/// coordinated-deleted. Once the watch has been acked and purged its own copy,
/// that staged file is **the only copy of the recording**.
///
/// It was Debug-only, so no shipped user could fire it — but the dogfood
/// devices are exactly the ones carrying real recordings, and there are two of
/// them.
///
/// The pure `orphans(...)` predicate and its tests are deliberately KEPT: the
/// arithmetic is fine, the keep-set is not. Rebuilding this correctly belongs
/// with the clip-storage seam work (post-tag), where the device-local /
/// device-shared split is actually resolved rather than worked around.
@Suite
struct OrphanSweepReachabilityTests {

    /// THE GUARD. No production code may invoke the sweep's destructive or
    /// planning entry points while its keep-set can't see another device's
    /// staged clips.
    @Test func sweepIsNotReachableFromProduction() throws {
        let callers = try Self.callSites()
        #expect(
            callers.isEmpty,
            """
            `MediaBlobOrphanSweep` is invoked from production:
            \(callers.map { "  • \($0)" }.joined(separator: "\n"))

            Its keep-set unions a CloudKit-synced source with a SANDBOX-LOCAL \
            manifest, while the files it judges are in the shared ubiquity \
            container. On a second device, staged watch clips are unreferenced \
            by construction and get deleted — and that staged file is the only \
            copy once the watch has purged its own.

            Do not re-enable until the keep-set covers every device's staged \
            clips (clip-storage seam rebuild, post-tag).
            """
        )
    }

    /// Guards the guard: the scanner must be able to see a call site at all.
    /// Without this it would report "not reachable" forever, including after
    /// someone re-adds one.
    @Test func scannerCanSeeACallSite() {
        #expect(Self.isCallSite("sweepPlan = MediaBlobOrphanSweep.plan(context: storage.viewContext)"))
        #expect(Self.isCallSite("MediaBlobOrphanSweep.execute(plan: sweepPlan)"))
        #expect(!Self.isCallSite("enum MediaBlobOrphanSweep {"), "the declaration is not a call")
        #expect(!Self.isCallSite("/// `MediaBlobOrphanSweep` is disabled — see the type doc."),
                "prose naming it is not a call")
    }

    static func isCallSite(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.hasPrefix("//"), !t.hasPrefix("///") else { return false }
        guard t.contains("MediaBlobOrphanSweep.") else { return false }
        // The declaration and the type's own internal helper calls are not
        // production invocations.
        return t.contains(".plan(") || t.contains(".execute(")
    }

    static func callSites() throws -> [String] {
        var out: [String] = []
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { throw Failure.rootNotFound(root.path) }
        var sawAnySwift = false
        for case let url as URL in walker where url.pathExtension == "swift" {
            sawAnySwift = true
            guard !url.path.contains("Tests") else { continue }
            guard let src = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (i, line) in src.components(separatedBy: "\n").enumerated() where isCallSite(line) {
                out.append("\(url.lastPathComponent):\(i + 1)")
            }
        }
        // Proves the walk reached source — the failure mode the sibling
        // scanners were hardened against on 2026-07-31.
        guard sawAnySwift else { throw Failure.walkFoundNoSource(root.path) }
        return out
    }

    enum Failure: Error { case rootNotFound(String), walkFoundNoSource(String) }
}
