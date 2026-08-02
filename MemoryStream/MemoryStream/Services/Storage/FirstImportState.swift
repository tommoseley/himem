import Foundation
import CoreData
import Combine

/// F22 · **The one fact every surface reads before it claims to be empty.**
///
/// **The defect.** On a fresh install (uninstall/reinstall on iPad, 2026-07-31)
/// the app reported "0 memories" while CloudKit's first import was still
/// running. The memories arrived about a minute later. Nothing was lost — but
/// the app asserted emptiness as fact when the truth was "we haven't finished
/// looking." Zero-because-you-have-none and zero-because-we-haven't-looked-yet
/// are different facts, and every list picked the first reading, because a
/// count was the only input it had. Same Honest-Label class as the confident
/// `0:00` duration (F6i): a claim stated with certainty that happens to be
/// false. On a fresh install it reads as *your memories are gone*.
///
/// **Why one owner, not a flag per surface.** The scanner that enforces this
/// sees **34 empty-state sites** across `Views/`; **14** render from a store
/// that may not have imported (Memories, Recently Deleted, Projects, the two
/// add-sheets, the Clips bench and its filters, the manage sheets, the memory
/// picker, project detail), and the rest carry a stated `F22 EXEMPT` reason.
/// ("Seven" was this doc's original figure, written before the scanner could
/// see inline empty-state renders — an undercount by more than half, corrected
/// 2026-07-31 with the blind-spot fix.) Making each observe the container,
/// latch first-completion, and handle the no-iCloud fallback independently is
/// fourteen copies of a three-state machine —
/// the exact pattern that left `.measurement` hardcoded on the phone while the
/// watch had an owner and a test (F18), and that let a `?? 0` at one boundary
/// defeat three correct models (F19b/F6a). Surfaces should state facts, not
/// derive them.
///
/// **The latch, and what it deliberately does not attempt.** CloudKit delivers
/// in batches, and `.import .succeeded` is not terminal — it can fire many
/// times. So "first import complete" is the FIRST success, latched, and a later
/// batch may add content afterwards. That is honest: **a list that grows is not
/// a lie; a list that claims empty is.** Detecting "all batches done" is
/// unknowable and would strand users in a permanent "still fetching" state
/// (Tom, 2026-07-31).
///
/// **The fallback is not optional.** With no iCloud account, no network, or
/// simply nothing to import, no event ever arrives. The timeout latches anyway,
/// so those users see an honest empty state promptly rather than an eternal
/// spinner. This mirrors the 3-second net already proven in `LaunchScreenView`
/// for gating `FragmentMigration`.
///
/// **Persistence is per install.** Once the first import has completed on this
/// device, it is complete forever: a relaunch on day 40 shows the truth
/// instantly and never re-enters the ambiguous state. That also means this code
/// only ever runs on a fresh install — the path with the least device history
/// and no repeatable dogfood (Tom cannot reinstall repeatedly; Judi's next
/// reinstall is the trip). `FirstImportStateTests` is therefore not the durable
/// half of this fix, it is the only half.
@MainActor
final class FirstImportState: ObservableObject {

    enum Phase: Equatable {
        /// CloudKit's first import has not reported yet. **No surface may
        /// claim to be empty in this phase.**
        case importing
        /// The first import reported success, or the fallback fired. Counts
        /// are now the truth as far as we can know it.
        case complete
    }

    static let shared = FirstImportState()

    @Published private(set) var phase: Phase

    /// True while surfaces must withhold an empty-state claim. The single
    /// question every empty state asks.
    var mayAssertEmpty: Bool { phase == .complete }

    private let defaultsKey = "himem.firstImportComplete"
    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?
    private var fallback: DispatchWorkItem?

    /// - Parameter defaults: injectable so the tests can exercise a genuine
    ///   fresh install without touching the real install's state.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // A previous launch already saw the first import through: never show
        // the importing phase again on this install.
        self.phase = defaults.bool(forKey: defaultsKey) ? .complete : .importing
    }

    /// Begins observing CloudKit import events and arms the fallback. No-op if
    /// already complete, so a relaunch costs nothing.
    ///
    /// - Parameters:
    ///   - container: the CloudKit-backed container to watch.
    ///   - timeout: the no-event fallback. Matches `LaunchScreenView`'s proven
    ///     3-second net.
    func begin(container: NSPersistentContainer, timeout: TimeInterval = 3.0) {
        guard phase == .importing else { return }

        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
            // type 1 == .import. Matching the existing observer's form.
            guard event.type.rawValue == 1, event.succeeded else { return }
            MainActor.assumeIsolated { self?.markComplete() }
        }

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.markComplete() }
        }
        fallback = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    /// Latches. Idempotent — later batches are welcome to add content, they
    /// just don't change this fact.
    func markComplete() {
        guard phase == .importing else { return }
        phase = .complete
        defaults.set(true, forKey: defaultsKey)
        fallback?.cancel()
        fallback = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    /// **The three surfaces that speak while importing** (Tom, 2026-07-31).
    ///
    /// Every *other* gated surface renders nothing at all in this phase — no
    /// empty state, no message, no spinner. That keeps the copy surface at
    /// three while all fourteen gated surfaces sit behind one owner: a sheet
    /// that briefly shows nothing is honest, and inventing eleven more
    /// "getting your…" lines would be eleven more things to keep true.
    ///
    /// Parallel construction, and "from iCloud" is deliberate — it names where
    /// her things actually are, which is the custody story. A bare "Getting
    /// your memories" invites *from where?*
    enum Copy {
        /// Memories. The second line does the real work: the alarm came from
        /// certainty, not from delay.
        static let memoriesTitle = "Getting your memories from iCloud"
        static let memoriesDetail = "This can take a minute on a new device."
        /// Projects — no second line.
        static let projectsTitle = "Getting your projects from iCloud"
        /// Recently Deleted. "Still checking" was rejected: "still" implies
        /// struggling, on the one surface whose subject is content she already
        /// feared losing. Promising appearance beats describing absence.
        static let recycleBinTitle = "Getting things from iCloud"
        static let recycleBinDetail = "Anything you've deleted recently will appear here."
    }

    #if DEBUG
    /// Test-only reset to a genuine fresh-install state.
    func debugResetForTesting() {
        defaults.removeObject(forKey: defaultsKey)
        phase = .importing
        fallback?.cancel()
        fallback = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }
    #endif
}
