import Foundation

/// **Which binary is on the wrist.**
///
/// The phone has had this since the walkthrough work and it earned its place
/// twice on 2026-08-21: three different iPhone binaries in one evening all
/// reported `v1.0 (28)`, because `MARKETING_VERSION` and
/// `CURRENT_PROJECT_VERSION` do not move between dev builds (ASC assigns the
/// build number; we never hand-edit it). **The executable's mtime was the only
/// thing distinguishing them**, and every device reading that night rested on it.
///
/// The watch had no equivalent, so a watch reading could not be checked against
/// a stale install at all — on the one surface that had never run on hardware.
/// Found 2026-08-21 while preparing the first watch device pass.
///
/// **This duplicates `BuildStamp` in the iOS target, and that is a real cost,
/// not a tidy reuse.** It is the `.measurement` shape CLAUDE.md names: an
/// invariant with an owner on one platform and a literal on the other. The
/// honest fix is one owner in `Shared/` — but `Shared/` uses **explicit**
/// `project.pbxproj` references while `Himem Watch Watch App/` is a
/// `PBXFileSystemSynchronizedRootGroup`, so moving it means editing the project
/// file, which is exactly what orphaned the `Shared/` references during F18.
/// Doing that surgery minutes before a device pass trades a known small cost for
/// an unknown large one. **Logged for consolidation, deliberately not taken now.**
enum WatchBuildStamp {
    static func log() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var built = "unknown"
        if let exe = Bundle.main.executableURL,
           let date = (try? FileManager.default.attributesOfItem(atPath: exe.path))?[.modificationDate] as? Date {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            built = f.string(from: date)
        }
        // Same prefix as the phone so one grep finds both, with `watch` naming
        // which surface answered — the two run in different processes and a
        // reading that cannot say which one it came from is worse than none.
        NSLog("[HiMem][Build] watch v\(version) (\(build)) · binary built \(built)")
    }
}
