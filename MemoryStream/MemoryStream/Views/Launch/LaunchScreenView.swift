import SwiftUI
import CoreData

struct LaunchScreenView: View {
    let onStorageReady: () -> Void
    let onComplete: () -> Void

    @State private var storageLoaded = false
    @State private var syncProgress: CGFloat = 0
    @State private var syncDone = false
    @State private var epigraph = ""
    @State private var epigraphSource = ""

    // Choreography — all start false, fade in on schedule
    @State private var showGreeting = false
    @State private var showMoment = false
    @State private var showProgress = false
    @State private var showFooter = false
    @State private var wordmarkExpanded = false

    // Design tokens — aliased from the Crucible catalog so launch
    // animations adapt to dark mode automatically when Phase 4
    // exposes it.
    private let ochre = Crucible.Color.accent
    private let ink = Crucible.Color.ink
    private let bg = Crucible.Color.paper

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let time: String
        switch hour {
        case 0..<12: time = "Good morning"
        case 12..<17: time = "Good afternoon"
        default: time = "Good evening"
        }
        let name = AuthService.shared.userName
        if !name.isEmpty && name != "there" {
            return "\(time), \(name)"
        }
        return time
    }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Greeting — 0ms start
                HStack(spacing: 8) {
                    Circle()
                        .fill(ochre)
                        .frame(width: 5, height: 5)
                    Text(greeting)
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(ink.opacity(0.55))
                }
                .opacity(showGreeting ? 1 : 0)
                .padding(.top, 14)

                // Wordmark — collapsed reads "HiMem"; expanded reads
                // "HiMemories!" on sync complete. The two-Text
                // construction preserves the brand's bold/italic + color
                // split across the transition. The TierMark sits to the
                // right of the wordmark for paying users (Founder /
                // Plus / Supporter) so they feel seen without ceremony.
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("Hi")
                            .font(.custom("Georgia-Bold", size: 56))
                            .foregroundStyle(ink)
                        Text(wordmarkExpanded ? "Memories!" : "Mem")
                            .font(.custom("Georgia-Italic", size: 56))
                            .foregroundStyle(ochre)
                    }
                    .animation(.easeInOut(duration: 0.6), value: wordmarkExpanded)

                    // TierMark and Founder line are gated on storageLoaded
                    // so EntitlementService.shared isn't accessed during
                    // the splash's initial body evaluation — that access
                    // would force loadPersistentStores synchronously on
                    // the main thread (loadOrCreate fetches AssistBalance
                    // from viewContext). After storage loads (and the
                    // bootstrap inside onStorageLoaded runs), the tier
                    // mark fades in on the splash's last re-render before
                    // dismissal. For Free/anonymous users this changes
                    // nothing visible.
                    if storageLoaded {
                        TierMark(
                            tier: EntitlementService.shared.tier,
                            supporter: EntitlementService.shared.isSupporter,
                            size: 18
                        )
                        .offset(y: -10) // align baseline with wordmark cap
                    }
                }
                .padding(.top, 18)

                // Founder line — unbounded acknowledgment under the
                // wordmark. Plus / Supporter / Free see nothing here;
                // the TierMark above is their identity. Same
                // storageLoaded gating as the TierMark above.
                if storageLoaded && EntitlementService.shared.tier == .founders {
                    Text("Thanks for being a founder.")
                        .font(.custom("Georgia-Italic", size: 13))
                        .foregroundStyle(ink.opacity(0.6))
                        .padding(.top, 6)
                }

                // Moment (epigraph) — 220ms start
                VStack(alignment: .leading, spacing: 10) {
                    if !epigraph.isEmpty {
                        Text("\u{201C}\(epigraph)\u{201D}")
                            .font(.custom("Georgia-Italic", size: 19))
                            .foregroundStyle(ink.opacity(0.72))
                            .lineSpacing(19 * 0.45)
                            .frame(maxWidth: 280, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !epigraphSource.isEmpty {
                        Text(epigraphSource.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(ink.opacity(0.42))
                    }
                }
                .opacity(showMoment ? 1 : 0)
                .padding(.top, 12)

                Spacer()

                // Footer: cloud status + progress hairline — 520ms start
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "cloud")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(ink.opacity(0.42))
                            .frame(width: 22, height: 22)

                        Text(syncDone
                             ? "Ready"
                             : "Opening your memory box \u{00B7} iCloud")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ink.opacity(0.55))
                    }

                    // Progress hairline — 360ms start
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(ink.opacity(0.08))
                            .frame(height: 2)
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(
                                        LinearGradient(
                                            colors: [ochre.opacity(0.25), ochre],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * syncProgress, height: 2)
                            }
                    }
                    .frame(height: 2)
                    .opacity(showProgress ? 1 : 0)
                }
                .opacity(showFooter ? 1 : 0)
            }
            .padding(.top, 70)
            .padding(.horizontal, 28)
            .padding(.bottom, 36)
        }
        .onAppear { runChoreography() }
    }

    // MARK: - Choreography: ~1500ms sequence

    private func runChoreography() {
        // Load epigraph from cache immediately (no storage needed)
        let selected = EpigraphService.shared.todaysEpigraphWithSource(entryCount: 0)
        epigraph = selected.text
        epigraphSource = selected.source

        // Greeting — 0ms
        withAnimation(.easeIn(duration: 0.2)) { showGreeting = true }

        // Wordmark is always visible (matches storyboard)

        // Moment — 220ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.easeIn(duration: 0.25)) { showMoment = true }
        }

        // Progress hairline — 360ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            withAnimation(.easeIn(duration: 0.2)) { showProgress = true }
        }

        // Footer (cloud status) — 520ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
            withAnimation(.easeIn(duration: 0.2)) { showFooter = true }
        }

        // Start loading storage on background thread at 100ms
        // This is the real work the hairline tracks
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            DispatchQueue.global(qos: .userInitiated).async {
                LaunchSignposter.interval("launchScreen.awaitStorageShared") {
                    _ = StorageService.shared
                }
                // FragmentMigration is intentionally NOT called here —
                // running it before CloudKit's initial import has settled
                // races against the importer and raises an ObjC NSException
                // from `_PFManagedObject_coerceValueForKeyWithDescription`
                // that Swift can't catch. See
                // docs/issues/2026-05-09-fragment-migration-cloudkit-race.md.
                // Migration is now gated on `eventChangedNotification`
                // import-success or the 3s safety net below.
                DispatchQueue.main.async { onStorageLoaded() }
            }
        }
    }

    // MARK: - Storage Ready

    private func onStorageLoaded() {
        LaunchSignposter.interval("launchScreen.topicPaletteLoad") {
            TopicPaletteStore.shared.loadFromCoreData()
        }
        // Bootstrap entitlement + StoreKit AFTER storage is ready.
        // Previously these ran inside MemoryStreamApp.init's
        // DispatchQueue.main.async block, which pre-empted the
        // off-main storage warm (EntitlementService.init fetches
        // AssistBalance from viewContext, forcing a sync
        // loadPersistentStores on the main thread). Running them
        // here means viewContext is already live, so the fetch is
        // cheap and doesn't block first paint. See
        // feedback_cold_launch_target memory.
        LaunchSignposter.interval("launchScreen.entitlementBootstrap") {
            _ = EntitlementService.shared
            StoreKitService.shared.start()
            Task { await FoundersCounter.shared.refresh() }
            TenureTracker.shared.start()
            WatchInboxNotificationCoordinator.shared.registerCategories()
        }
        storageLoaded = true
        onStorageReady()

        // Update epigraph with real entry count
        let count = EpigraphService.shared.entryCount()
        let accurate = EpigraphService.shared.todaysEpigraphWithSource(entryCount: count)
        if accurate.text != epigraph {
            epigraph = accurate.text
            epigraphSource = accurate.source
        }
        EpigraphService.shared.refreshFromAPI()

        // Animate progress to 70%
        withAnimation(.easeInOut(duration: 0.8)) { syncProgress = 0.7 }

        // Watch for CloudKit import completion — this drives the handoff
        // AND is the gate for FragmentMigration. The two-NSManagedObjectModel
        // race that crashes the migration only exists while CloudKit's
        // import is in flight; once `.import .succeeded` fires, only our
        // model is live and writes are safe. We run migration on EVERY
        // import-success event (not just the first) because CloudKit can
        // deliver entries across multiple batches — entries that arrive
        // in the second batch were missed by the first migration call,
        // and the next-launch flag won't help if the first call set it
        // prematurely (see 2026-05-09 issue doc).
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: StorageService.shared.container,
            queue: .main
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
            // type 1 = import
            if event.type.rawValue == 1 && event.succeeded {
                runMigration()
                completeSync()
            }
        }

        // If entries already exist (sync happened during store load), complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if !syncDone && EpigraphService.shared.entryCount() > 0 {
                runMigration()
                completeSync()
            }
        }

        // Safety net — if CloudKit never reports (no iCloud account, no
        // network, or empty store with nothing to import), still run
        // migration once and hand off so the user isn't stuck on the
        // splash. The migration's own UserDefaults flag is set only when
        // we confirm the steady state, so 0-entry runs from this path
        // get retried on next launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            runMigration()
            if !syncDone { completeSync() }
        }
    }

    /// Schedules `FragmentMigration.runIfNeeded` on a background context
    /// and runs `InboxManifest`'s deferred startup migrations. Safe to
    /// call multiple times — both migrations are internally idempotent.
    ///
    /// Per 2026-05-09 issue doc, only call after CloudKit's initial
    /// import has settled (or the 3s safety timeout) — running
    /// concurrently with import raises an ObjC NSException that can't
    /// be caught. The same window is what crashed the InboxManifest
    /// backup + legacy `InboxProcessedClipIds.json` migration on Tom's
    /// 2026-05-30 device run; deferring both to this hook eliminates
    /// the race for both.
    private func runMigration() {
        InboxManifest.shared.runStartupMigrationsIfNeeded()
        if FragmentMigration.hasCompleted { return }
        let context = StorageService.shared.backgroundContext()
        context.perform {
            FragmentMigration.runIfNeeded(in: context)
        }
    }

    // MARK: - Handoff

    private func completeSync() {
        guard !syncDone else { return }
        syncDone = true
        withAnimation(.easeInOut(duration: 0.3)) { syncProgress = 1.0 }

        // Cold-launch fix 2026-06-02: dismiss splash immediately rather
        // than holding for the 1.4s sequential brand moment (0.3s "Ready"
        // hold + 0.6s wordmark expand + 0.5s "HiMemories!" read pause).
        // That hold was pure UX delay tacked onto the front of every cold
        // launch — exactly what poisons the 400ms-to-interactive target.
        // The wordmark expand still fires so the brand moment plays out
        // during the fade-out animation; users see "HiMemories!" flash as
        // the splash dissolves into the feed. See
        // feedback_cold_launch_target memory.
        withAnimation(.easeInOut(duration: 0.6)) {
            wordmarkExpanded = true
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            onComplete()
        }
    }
}
