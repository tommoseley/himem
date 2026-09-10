import Foundation
import CoreData

/// **The CloudKit import arc, logged for as long as CloudKit keeps talking.**
///
/// **Why this is a separate object from `FirstImportState`.** That type already
/// observes the same notification, and the obvious move is to log from there.
/// It was, and reading #2 was void three times because of it. The two uses are
/// **two jobs with opposite deadlines, sharing one observer lifetime:**
///
/// | | Job | Correct deadline |
/// |---|---|---|
/// | `FirstImportState` | decide when a surface may claim to be empty | **as early as honestly possible** |
/// | this type | make the ~17–21s setup floor visible | **after the quantity elapses** |
///
/// `FirstImportState.markComplete` calls `removeObserver`, and for *its* job
/// that is right — the question is answered forever, so it stops listening. But
/// its 3s fallback fires long before CloudKit's per-zone setup completes: on
/// 2026-08-25 it fired at **+3149ms**, tore the observer down, and the archive
/// carried **zero** `ck event` lines. Silence-because-we-stopped-listening is
/// byte-identical to silence-because-no-import-started, which is the exact
/// fault `FirstImportState.begin`'s own guard-return comment warns about.
///
/// **The conflict is structural, not a tuning problem.** Lengthening that
/// timeout to serve the instrument would damage the guarantee the timeout
/// exists to provide — an account with nothing to import must not sit in an
/// eternal "getting your memories" (`FirstImportState`: *"The fallback is not
/// optional"*). One lifetime cannot satisfy both deadlines, so there are two.
///
/// **What this type therefore does NOT do, by construction:**
/// - **never removes its observer** — there is no teardown path at all, which
///   is what makes the arc's length a property of CloudKit rather than of us;
/// - **never latches** — no `markComplete`, no `phase`, no UserDefaults write;
/// - **never reads `FirstImportState`** — in particular it does **not** inherit
///   that type's `guard phase == .importing`, so it speaks on a relaunch where
///   `himem.firstImportComplete` is already true. That branch going silent was
///   reading #2's second void, and it is the branch a populated account
///   actually takes.
///
/// Because it only writes to a sink, it cannot alter the thing it measures —
/// which matters more than usual here: `FirstImportState`'s docstring records
/// that its code path *"only ever runs on a fresh install"*, the path with no
/// repeatable dogfood. An instrument able to perturb that path is the wrong
/// instrument.
///
/// **No settle flag, deliberately.** The arc ends when the events stop, and a
/// reader can see that. An invented `settled` line would be a claim we cannot
/// substantiate — the same reason `FirstImportState` refuses to detect "all
/// batches done".
@MainActor
final class CloudKitArcLog {

    static let shared = CloudKitArcLog()

    /// Where lines go. Injectable **because `NSPersistentCloudKitContainer.Event`
    /// has no public initialiser** — no test in this project has ever
    /// constructed one, so the notification payload cannot be synthesised. The
    /// sink plus `record(...)` are the seam that makes every decision this type
    /// takes reachable from a test; only the three-line notification adapter
    /// sits outside it, and `theLaunchPathArmsTheArc` guards that it is called.
    private let sink: (String) -> Void

    /// Deliberately no `stop()`, and this is never written back to nil.
    private var observer: NSObjectProtocol?

    /// The origin for every elapsed figure. Set once, at `begin`.
    private var armedAt: Date?

    init(sink: @escaping (String) -> Void = { DeviceLog.launch($0) }) {
        self.sink = sink
    }

    /// True once `begin` has armed. Never returns to false — see the class doc.
    var isArmed: Bool { observer != nil }

    /// Arms the arc. Idempotent: a second call is a no-op rather than a second
    /// observer, so a re-entrant launch path cannot double-log.
    ///
    /// **There is no `guard phase == .importing` here and there must not be.**
    func begin(container: NSPersistentContainer, now: Date = Date()) {
        guard observer == nil else { return }
        armedAt = now
        sink("[HiMem][CKArc] armed — every CloudKit event, for the life of the process")
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
            MainActor.assumeIsolated {
                self?.record(
                    type: event.type.rawValue,
                    succeeded: event.succeeded,
                    ended: event.endDate != nil,
                    error: event.error
                )
            }
        }
    }

    /// The seam. Everything the notification handler decides happens here, so
    /// it is reachable without an `Event`.
    func record(
        type: Int,
        succeeded: Bool,
        ended: Bool,
        error: Error? = nil,
        now: Date = Date()
    ) {
        let ms = Int(now.timeIntervalSince(armedAt ?? now) * 1000)
        sink(Self.line(type: type, succeeded: succeeded, ended: ended, elapsedMs: ms, error: error))
    }

    /// `NSPersistentCloudKitContainer.EventType`: 0 setup · 1 import · 2 export.
    ///
    /// **Named rather than left as a raw value, because `setup` is where the
    /// floor goes** and a reader should not have to hold the mapping. Unknown
    /// values render rather than trap — Apple may add a case, and an instrument
    /// that crashes on an unfamiliar input is worse than one that says
    /// "type9".
    static func typeName(_ raw: Int) -> String {
        switch raw {
        case 0: return "setup"
        case 1: return "import"
        case 2: return "export"
        default: return "type\(raw)"
        }
    }

    /// Pure, so the format is testable without a container or a notification.
    ///
    /// `started` vs `ended` is `endDate != nil`; an event fires twice, and the
    /// **interval between the two is the quantity this whole type exists to
    /// expose.** `succeeded` is only meaningful once ended, so it is reported
    /// only there — a "succeeded=false" on a start line would read as a failure
    /// that has not happened.
    static func line(
        type: Int,
        succeeded: Bool,
        ended: Bool,
        elapsedMs: Int,
        error: Error?
    ) -> String {
        var s = "[HiMem][CKArc] \(typeName(type)) "
        if ended {
            s += succeeded ? "ended ok" : "ended FAILED"
        } else {
            s += "started"
        }
        s += " +\(elapsedMs)ms"
        if let error {
            s += " err=\(error.localizedDescription)"
        }
        return s
    }
}
