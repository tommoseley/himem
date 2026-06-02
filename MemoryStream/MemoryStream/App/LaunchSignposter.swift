import Foundation
import os.signpost

/// Cold-start instrumentation. Wraps `OSSignposter` so launch-path
/// intervals show up under Instruments → Points of Interest →
/// `com.himem.app: launch`, and `os_signpost` debug logs from
/// `log stream --predicate 'subsystem == "com.himem.app"'`.
///
/// Added 2026-06-01 after a >9s cold-launch report. Used in the
/// suspected hot spots (StorageService.loadPersistentStores, the
/// DEBUG CloudKit schema init, LaunchScreenView's choreography
/// phases, and the service-startup block in MemoryStreamApp.init)
/// so the next cold-launch produces a measurable timeline rather
/// than estimates. Free to leave in — the runtime cost of a
/// non-emitted signpost is a tag check.
enum LaunchSignposter {
    static let signposter = OSSignposter(
        subsystem: "com.himem.app",
        category: "launch"
    )

    /// Wraps a synchronous block in begin/end signposts. Use sparingly
    /// for the launch hot spots — the call sites already know what
    /// name they're measuring.
    static func interval<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id)
        defer { signposter.endInterval(name, state) }
        return try body()
    }
}
