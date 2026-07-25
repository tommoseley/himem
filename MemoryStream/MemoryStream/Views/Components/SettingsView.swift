import SwiftUI
import CoreData
import UserNotifications

struct SettingsView: View {
    var viewModel: JournalViewModel? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var topics: [Topic] = []
    @State private var showRecycleBin = false
    @State private var newTopicName: String = ""
    @State private var newTopicColorKey: String = Crucible.Color.topicPalette[0].key
    @State private var showNewTopicSheet = false
    @State private var editingTopic: Topic? = nil
    @State private var refreshID = UUID()
    @AppStorage("saveVoiceEntries") private var saveVoiceEntries = true
    @AppStorage("voiceSilenceMode") private var voiceSilenceModeRaw = VoiceSilenceMode.standard.rawValue
    /// Hands-free (Siri) recording cap in minutes; `0` = No limit. Default 10.
    @AppStorage("handsFreeRecordingLimitMinutes") private var handsFreeLimitMinutes = 10
    @AppStorage("tagMemoriesWithLocation") private var tagMemoriesWithLocation = true
    @AppStorage("fabHandednessLeft") private var fabHandednessLeft = false
    @AppStorage("appearance") private var appearanceRaw: String = Appearance.system.rawValue
    private var appearance: Appearance {
        Appearance(rawValue: appearanceRaw) ?? .system
    }
    // Channel B (daily nudge) storage retired 2026-07-07.
    @State private var notificationAuthStatus: UNAuthorizationStatus = .notDetermined
    /// RH-1: the one persisted Captured-Clips arrivals control (was cosmetic).
    @State private var arrivalsEnabled: Bool = NotificationPreference.arrivalsEnabled
    // autoSaveDelay removed — Composer uses explicit commit

    private let storage = StorageService.shared

    @State private var displayName: String = AuthService.shared.userName
    @ObservedObject private var inbox = InboxManifest.shared
    @ObservedObject private var entitlement = Entitlement.shared
    @State private var showPricing = false
    @State private var isRestoring = false
    @State private var restoreNotice: String?
    @State private var showManageSubscriptions = false
    /// All-types recycled tally for the "Recently Deleted" row badge. Refreshed
    /// on appear and when the bin sheet closes (deletes/restores there change
    /// it), so we don't re-fetch every render.
    @State private var recycledCount = 0
    #if DEBUG
    @State private var showResetOnboardingAlert = false
    @State private var showResetTutorialAlert = false
    @State private var showAggregateScanAlert = false
    @State private var aggregateScanResult = ""
    // RH-8 orphaned-blob sweep (destructive; deliberate trigger only).
    @State private var showSweepAlert = false
    @State private var sweepPlan: [URL] = []
    @State private var showSeedClusterAlert = false
    @State private var seedClusterMessage = ""
    @AppStorage("himem.debug.useLeanOrganizerPrompt") private var useLeanOrganizerPrompt = false
    #endif

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Profile
                Section {
                    HStack {
                        Text("Name")
                        Spacer()
                        TextField("Your name", text: $displayName)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(Crucible.Color.ink2)
                            .onSubmit { commitDisplayName() }
                    }
                } header: {
                    Text("Profile")
                }

                // MARK: - Appearance
                // Per docs/design/pricing-screens-settings.jsx
                // ScrSettingsAppearance — row shows current mode as
                // the value; tap navigates to the sub-screen.
                Section {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: appearance.systemImage)
                                .frame(width: 22)
                                .foregroundStyle(Crucible.Color.accent)
                                .accessibilityHidden(true)
                            Text("Appearance")
                                .foregroundStyle(Crucible.Color.ink)
                            Spacer()
                            Text(appearance.label)
                                .font(.body)
                                .foregroundStyle(Crucible.Color.ink2)
                        }
                    }
                    NavigationLink {
                        TutorialsHubView()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "questionmark.circle")
                                .frame(width: 22)
                                .foregroundStyle(Crucible.Color.accent)
                                .accessibilityHidden(true)
                            Text("Learn")
                                .foregroundStyle(Crucible.Color.ink)
                        }
                    }
                } header: {
                    Text("Display")
                }

                // MARK: - Topics
                Section {
                    ForEach(topics) { topic in
                        Button {
                            editingTopic = topic
                        } label: {
                            HStack(spacing: 10) {
                                let hue = Crucible.Color.topicHue(for: topic.name)
                                Circle()
                                    .fill(hue.fg)
                                    .frame(width: 10, height: 10)
                                    .accessibilityHidden(true)
                                Text(topic.name)
                                    .foregroundStyle(Crucible.Color.ink)
                                Spacer()
                                Text("\(topic.entryCount) \(topic.entryCount == 1 ? "entry" : "entries")")
                                    .font(.caption)
                                    .foregroundStyle(Crucible.Color.ink3)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(Crucible.Color.ink4)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .onDelete(perform: deleteTopic)
                    .id(refreshID)

                    Button {
                        newTopicName = ""
                        newTopicColorKey = Crucible.Color.topicPalette[0].key
                        showNewTopicSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Crucible.Color.accent)
                                .accessibilityHidden(true)
                            Text("New Topic")
                                .foregroundStyle(Crucible.Color.accent)
                        }
                    }
                } header: {
                    Text("Topics")
                } footer: {
                    Text("Topics are the top-level categories shown in the tab bar. When the AI suggests a new topic, you'll be asked to approve it first.")
                }

                // MARK: - Data Management
                // Gated on having a viewModel (the bin needs one); the row's
                // badge reads `recycledCount` and the sheet uses the outer
                // property, so the binding itself isn't needed here.
                if viewModel != nil {
                    Section {
                        Button {
                            showRecycleBin = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                    .foregroundStyle(Crucible.Color.ink2)
                                    .accessibilityHidden(true)
                                Text("Recently Deleted")
                                    .foregroundStyle(Crucible.Color.ink)
                                Spacer()
                                // All-types union (memories + clips + projects),
                                // not memories-only — the badge previously read
                                // `1` against a bin of 3 clips + 1 memory.
                                if recycledCount > 0 {
                                    Text("\(recycledCount)")
                                        .font(.caption)
                                        .foregroundStyle(Crucible.Color.ink3)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Crucible.Color.sunk)
                                        .clipShape(Capsule())
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(Crucible.Color.ink4)
                                    .accessibilityHidden(true)
                            }
                        }
                    } header: {
                        Text("Data Management")
                    } footer: {
                        Text("Deleted memories are kept for 30 days before permanent removal.")
                    }
                }

                // MARK: - HiMem Plus (C3 card)
                Section {
                    plusCard
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
                        .listRowSeparator(.hidden)
                    subscriptionLinksRow
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 6, trailing: 14))
                        .listRowSeparator(.hidden)
                }

                // AI & Organizing section removed entirely 2026-07-24. It held
                // "Organizing (Manual/Automatic)" and "Projects" — both vestigial
                // display/upsell rows that gated nothing. Organize behavior is
                // tier-inherent, never a setting: Free = the per-memory Organize
                // button (on-device, no cost); Plus = the same button PLUS
                // automatic background organization. There is no Manual/Automatic
                // preference and no paywall wired to one ("people never manage AI").

                // MARK: - Voice
                // Note (2026-07-09): the "Captured Clips" Settings row was
                // retired per `Captured Clips · session-first · spec.md`
                // v4 — "there is no 'Settings → Captured Clips' entry —
                // the page is a tab." The Clips tab is the surface now.
                Section {
                    Toggle("Save voice recordings", isOn: $saveVoiceEntries)
                        .tint(Crucible.Color.accent)
                    Picker("Recording limit", selection: $handsFreeLimitMinutes) {
                        Text("5 minutes").tag(5)
                        Text("10 minutes").tag(10)
                        Text("30 minutes").tag(30)
                        Text("60 minutes").tag(60)
                        Text("No limit").tag(0)
                    }
                    Picker("Voice search pace", selection: $voiceSilenceModeRaw) {
                        ForEach(VoiceSilenceMode.allCases) { mode in
                            Text("\(mode.label) · \(mode.subtitle)").tag(mode.rawValue)
                        }
                    }
                } header: {
                    Text("Voice & recording")
                } footer: {
                    Text(saveVoiceEntries
                        ? "Voice recordings are saved on device — play them back from entry cards. The recording limit stops and saves a hands-free or Siri recording when it reaches the limit, so one you walk away from is never lost; a recording you're holding on screen isn't limited. Voice search pace only controls how long HiMem waits if you stop talking."
                        : "Voice recordings are discarded after transcription — only the text is kept. The recording limit stops and saves a hands-free or Siri recording when it reaches the limit, so one you walk away from is never lost; a recording you're holding on screen isn't limited. Voice search pace only controls how long HiMem waits if you stop talking.")
                }

                // MARK: - Privacy
                Section {
                    Toggle("Tag memories with location", isOn: $tagMemoriesWithLocation)
                        .tint(Crucible.Color.accent)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Location stays on your device. We never send it to the server. Turn this off and new memories will be saved without location.")
                }

                // MARK: - Notifications
                // Channel B (daily nudge / inactivity) retired 2026-07-07
                // per `CLAUDE.md` §Notifications — Kingfisher constitution
                // forbids the app raising the skipped thing. Only the
                // passive Captured Clips arrival channel remains, and it
                // has no user-visible toggle (arrivals ping so long as
                // the OS permission is granted).
                Section {
                    notificationPermissionRow
                } header: {
                    Text("Notifications")
                } footer: {
                    Text(notificationsFooter)
                }

                // MARK: - Handedness
                Section {
                    Toggle("Left-handed FAB", isOn: $fabHandednessLeft)
                        .tint(Crucible.Color.accent)
                } header: {
                    Text("Handedness")
                } footer: {
                    Text("Anchors the Add button to the bottom-left of the screen instead of the bottom-right. The action stack flips with it.")
                }

                // "Also save captures to my Photos library" retired
                // 2026-07-10 per `screens-settings.jsx` lines 5-9,
                // 231-234: the toggle contradicted the locked data-
                // custody decision (media lives in HiMem's iCloud
                // Files container, never the Photos library). The
                // "Where your memories live" section below now carries
                // the whole storage story on its own.

                // MARK: - About: where memories live
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Where your memories live")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Crucible.Color.ink)
                        Text("Your transcripts, titles, summaries, topics, and projects sync via iCloud. Original audio, photos, and videos live in your iCloud Drive under a folder called **HiMem** — visible in the Files app, exportable anywhere, and durable across reinstalls.\n\nWe don't store your memories on our servers.")
                            .font(.footnote)
                            .foregroundStyle(Crucible.Color.ink2)
                            .lineSpacing(2)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Storage")
                }

                #if DEBUG
                // MARK: - Debug (stripped from Release builds)
                Section {
                    // One-tap rehearsal — wipes state AND drops the
                    // app back into the splash → wizard sequence
                    // immediately, no force-quit needed. Dismisses
                    // this Settings sheet first so the wizard has
                    // the screen.
                    Button {
                        AuthService.shared.requestOnboardingTestRun()
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "play.circle.fill")
                                .foregroundStyle(Crucible.Color.accent)
                            Text("Run onboarding test")
                                .foregroundStyle(Crucible.Color.ink)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        AuthService.shared.debugResetOnboardingState()
                        showResetOnboardingAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .foregroundStyle(Crucible.Color.ink2)
                            Text("Reset onboarding (next launch)")
                                .foregroundStyle(Crucible.Color.ink)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        TutorialOrchestrator.shared.debugResetAll()
                        showResetTutorialAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "mic.circle")
                                .foregroundStyle(Crucible.Color.ink2)
                            Text("Reset all tutorial seen flags")
                                .foregroundStyle(Crucible.Color.ink)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)

                    Toggle(isOn: $useLeanOrganizerPrompt) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use lean organize prompt")
                                .foregroundStyle(Crucible.Color.ink)
                            Text("Strips Honest-Label rules so on-device organize uses a minimal prompt — diagnostic for safety-rejected memories.")
                                .font(.caption2)
                                .foregroundStyle(Crucible.Color.ink3)
                        }
                    }
                    .tint(Crucible.Color.accent)

                    // Finding 1 evidence step (2026-07-16): read-only scan for
                    // already-stored aggregate `.note` artifacts. Mutates
                    // nothing — proves the cleanup predicate matches a real
                    // on-device note before the destructive pass is authorized.
                    Button {
                        let hits = EntryLifecycleService().scanForAggregateNotes()
                        if hits.isEmpty {
                            aggregateScanResult = "No aggregate-note artifacts found. The predicate matched nothing already at rest."
                        } else {
                            let lines = hits.prefix(5).map {
                                "• \"\($0.memoryTitle)\" — note \($0.noteId.uuidString.prefix(8)), \($0.siblingCount) sibling clips, \($0.noteLength) chars"
                            }.joined(separator: "\n")
                            aggregateScanResult = "\(hits.count) aggregate-note artifact(s) found:\n\n\(lines)\n\nFull detail (with memory ids) is in the device console under [HiMem][TranscriptWipe] AGGREGATE-FOUND."
                        }
                        showAggregateScanAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "magnifyingglass.circle.fill")
                                .foregroundStyle(Crucible.Color.ink2)
                            Text("Scan for aggregate notes (read-only)")
                                .foregroundStyle(Crucible.Color.ink)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)

                    // RH-8: sweep the backlog of orphaned media blobs left in
                    // iCloud Files by the old purge paths. Runs the dry-run
                    // plan first and shows the count; deletion happens only on
                    // the destructive confirm. Keep-set = live + recycled
                    // clips; age-guarded so in-flight arrivals aren't swept.
                    Button {
                        sweepPlan = MediaBlobOrphanSweep.plan(context: storage.viewContext)
                        showSweepAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash.slash.fill")
                                .foregroundStyle(Crucible.Color.danger)
                            Text("Sweep orphaned media blobs")
                                .foregroundStyle(Crucible.Color.ink)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)

                    // Seeds a real multi-clip Sort cluster through the actual
                    // grouping path so the cluster editor (and the aggregate
                    // arbiter check that needs a multi-clip context) is
                    // reproducible on demand — no waiting on organic dogfood.
                    Button {
                        InboxManifest.shared.debugSeedTestCluster()
                        seedClusterMessage = "Seeded a 3-clip \u{201C}Kingfisher Wharf\u{201D} cluster onto the bench. Open Clips → the Sort proposal appears → tap Adjust to expand → tap a clip row to open the modal from a multi-clip context. Tap \u{201C}Clear test cluster\u{201D} when done."
                        showSeedClusterAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "square.stack.3d.up.fill")
                                .foregroundStyle(Crucible.Color.accent)
                            Text("Seed test cluster (Sort repro)")
                                .foregroundStyle(Crucible.Color.ink)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        InboxManifest.shared.debugClearTestCluster()
                        seedClusterMessage = "Cleared the seeded test-cluster clips. Your real bench clips are untouched."
                        showSeedClusterAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "square.stack.3d.up.slash.fill")
                                .foregroundStyle(Crucible.Color.ink2)
                            Text("Clear test cluster")
                                .foregroundStyle(Crucible.Color.ink)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Debug")
                } footer: {
                    Text("Developer-only. Compiled out of Release builds — App Store users never see this section. **Run onboarding test** replays the splash + wizard immediately. **Reset onboarding** clears state for the next cold launch (requires force-quit).")
                }
                .alert("Onboarding reset", isPresented: $showResetOnboardingAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("Cleared Keychain (userID, userName) and the iCloud KV sidecar, and set the force-full-wizard flag so every screen shows on next launch (even ones whose iOS permission is already granted). Force-quit HiMem from the app switcher and re-launch to see it. iOS permission grants themselves are NOT reset — those live in Settings → HiMem and can only be cleared from there.")
                }
                .alert("Tutorials reset", isPresented: $showResetTutorialAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("Cleared every auto-fire tutorial's seen flag plus the session/day caps. Each tutorial will auto-fire on its next natural trigger (Capture on voice-composer open, Organizing on first Draft, Find-the-thread on Plus + ≥3-memory project, Watch story on non-empty Captured Clips, Watch discovery on next Today appearance with WCSession.isPaired && !installed).")
                }
                .alert("Aggregate-note scan", isPresented: $showAggregateScanAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(aggregateScanResult)
                }
                .alert("Orphaned media sweep", isPresented: $showSweepAlert) {
                    if sweepPlan.isEmpty {
                        Button("OK", role: .cancel) { }
                    } else {
                        Button("Delete \(sweepPlan.count) forever", role: .destructive) {
                            MediaBlobOrphanSweep.execute(plan: sweepPlan)
                            sweepPlan = []
                        }
                        Button("Cancel", role: .cancel) { }
                    }
                } message: {
                    Text(sweepPlan.isEmpty
                         ? "No orphaned media blobs found — the container matches the live + recycled clips."
                         : "\(sweepPlan.count) orphaned blob(s) in iCloud Files aren't referenced by any live or recycled clip (older than the 1-hour age guard). Delete permanently? This can't be undone.")
                }
                .alert("Test cluster", isPresented: $showSeedClusterAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(seedClusterMessage)
                }

                // MARK: - Plus override (DEBUG)
                Section {
                    Picker("Plus tier", selection: plusOverrideBinding) {
                        ForEach(PlusOverrideOption.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text("Effective")
                            .foregroundStyle(Crucible.Color.ink2)
                        Spacer()
                        Text(entitlement.isPlus ? "Plus" : "Free")
                            .font(.subheadline.monospaced())
                            .foregroundStyle(entitlement.isPlus ? Crucible.Color.accent : Crucible.Color.ink3)
                    }
                } header: {
                    Text("Plus override")
                } footer: {
                    Text("Forces the isPlus signal so you can exercise the Plus path without an active subscription. Persists across launches. Setting back to Real reads StoreKit's current entitlement state.")
                }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    // Done is the canonical commit moment in a nav/sheet
                    // top bar — per the Crucible colour code, top-bar
                    // confirm actions are explicit ochre. (System tint
                    // is usually accent already, but make it explicit
                    // so future tint changes can't drift this label.)
                    Button("Done") {
                        commitDisplayName()
                        dismiss()
                    }
                    .foregroundStyle(Crucible.Color.accent)
                    .fontWeight(.semibold)
                }
            }
            .onDisappear {
                // Catches swipe-to-dismiss and any other dismissal path
                // that bypasses the Done button.
                commitDisplayName()
            }
            .sheet(isPresented: $showPricing) {
                PricingView()
            }
            .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
            .alert("Restore Purchases", isPresented: restoreNoticeBinding) {
                Button("OK", role: .cancel) { restoreNotice = nil }
            } message: {
                Text(restoreNotice ?? "")
            }
            .onAppear {
                loadTopics()
                refreshRecycledCount()
                Task {
                    notificationAuthStatus = await NotificationService.shared.authorizationStatus()
                }
            }
            // Channel B onChange handlers retired 2026-07-07.
            .sheet(isPresented: $showRecycleBin, onDismiss: refreshRecycledCount) {
                if let viewModel {
                    RecycleBinView(viewModel: viewModel)
                }
            }
            .sheet(isPresented: $showNewTopicSheet) {
                NewTopicSheet(
                    name: $newTopicName,
                    colorKey: $newTopicColorKey,
                    onAdd: { name, colorKey in
                        addTopic(name: name, colorKey: colorKey)
                    }
                )
            }
            .sheet(item: $editingTopic) { topic in
                TopicEditorSheet(
                    topic: topic,
                    onSave: { newName, newColorKey in
                        updateTopic(topic, name: newName, paletteKey: newColorKey)
                    },
                    onDelete: {
                        storage.viewContext.delete(topic)
                        try? storage.save(context: storage.viewContext)
                        loadTopics()
                    }
                )
            }
        }
    }

    // MARK: - Profile

    /// Commits the profile name edit through the canonical AuthService
    /// API so it lands in Keychain + iCloud KV + @Published in one
    /// call. Idempotent: empty input is a no-op (handled by
    /// setUserName); re-saving the existing value is harmless. Wired
    /// to .onSubmit (Return key), Done toolbar button, and
    /// .onDisappear so name changes save regardless of how the user
    /// leaves Settings.
    private func commitDisplayName() {
        AuthService.shared.setUserName(displayName)
    }

    // MARK: - Topics

    private func loadTopics() {
        let request = Topic.fetchAll()
        do {
            topics = try storage.viewContext.fetch(request)
        } catch {
            ErrorState.shared.report(.topicError(error.localizedDescription))
        }
    }

    /// Recompute the "Recently Deleted" badge — the ALL-TYPES union, from the
    /// same four sources the bin lists (memories + bench clips + inbox clips +
    /// projects), via the shared `RecycleBinCounts`. Fixes the badge that read
    /// memories-only.
    private func refreshRecycledCount() {
        guard let viewModel else { recycledCount = 0; return }
        let lifecycle = EntryLifecycleService(storage: .shared, processingEngine: .shared)
        recycledCount = RecycleBinCounts(
            memories: viewModel.loadRecycledEntries().count,
            benchClips: lifecycle.loadRecycledClips().count,
            inboxClips: InboxManifest.shared.loadRecycledClips().count,
            projects: ProjectViewModel().loadRecycledProjects().count
        ).all
    }

    private func updateTopic(_ topic: Topic, name: String, paletteKey: String) {
        let oldName = topic.name
        topic.name = name
        topic.slug = TopicSlugHelper.slugify(name)
        topic.paletteKey = paletteKey

        // Migrate string-keyed caches if name changed
        TopicPaletteStore.shared.set(key: paletteKey, for: name)
        if oldName != name {
            TopicPaletteStore.shared.remove(for: oldName)
        }

        do {
            try storage.save(context: storage.viewContext)
            loadTopics()
            refreshID = UUID()
        } catch {
            ErrorState.shared.report(.topicError(error.localizedDescription))
        }
    }

    private func addTopic(name: String, colorKey: String) {
        do {
            let _ = try storage.findOrCreateTopic(name: name, paletteKey: colorKey)
            TopicPaletteStore.shared.set(key: colorKey, for: name)
            loadTopics()
        } catch {
            ErrorState.shared.report(.topicError(error.localizedDescription))
        }
    }

    private func deleteTopic(at offsets: IndexSet) {
        for index in offsets {
            let topic = topics[index]
            storage.viewContext.delete(topic)
        }
        do {
            try storage.save(context: storage.viewContext)
            loadTopics()
        } catch {
            ErrorState.shared.report(.topicError(error.localizedDescription))
        }
    }

    // MARK: - Notifications helpers

    // MARK: - C3 Plus card

    /// The C3 hero card per `docs/design/pricing-screens-upgrade.jsx`.
    /// Sits inside a Section row but renders its own card chrome
    /// (cream paper, accent stroke, 16pt corner) so it reads as a
    /// hero element at the top of the settings list.
    @ViewBuilder
    private var plusCard: some View {
        Button {
            showPricing = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("HiMem Plus")
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .foregroundStyle(Crucible.Color.accent)
                    Spacer()
                    Text(plusCardPriceLine)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Crucible.Color.ink3)
                }
                .padding(.bottom, 4)

                Text(entitlement.isPlus
                    ? "Manage your subscription in iOS Settings → Apple ID → Subscriptions."
                    : "Automatic organizing, memories that connect themselves, and unlimited projects.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Crucible.Color.ink2)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, entitlement.isPlus ? 4 : 12)

                if !entitlement.isPlus {
                    Text("See plans")
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Crucible.Color.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity)
            .background(Crucible.Color.card)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Crucible.Color.accent, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    /// Restore + (for Plus) Manage-subscription — the App Review-required
    /// affordances, always reachable from Settings regardless of tier.
    /// Restore matters most for a fresh install / new device where no
    /// transaction has arrived yet.
    @ViewBuilder
    private var subscriptionLinksRow: some View {
        HStack(spacing: 8) {
            Button(action: handleRestore) {
                if isRestoring {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("Restore Purchases")
                }
            }
            .disabled(isRestoring)
            if entitlement.isPlus {
                Text("·").foregroundStyle(Crucible.Color.ink4)
                Button("Manage subscription") { showManageSubscriptions = true }
            }
            Spacer()
        }
        .font(.system(size: 12.5))
        .foregroundStyle(Crucible.Color.aiBlue)
    }

    private var restoreNoticeBinding: Binding<Bool> {
        Binding(get: { restoreNotice != nil }, set: { if !$0 { restoreNotice = nil } })
    }

    private func handleRestore() {
        Task {
            isRestoring = true
            defer { isRestoring = false }
            switch await StoreKitService.shared.restorePurchases() {
            case .restored:
                restoreNotice = "Your HiMem Plus subscription has been restored."
            case .nothingToRestore:
                restoreNotice = "No active HiMem Plus subscription was found on this Apple Account."
            case .failed(let msg):
                restoreNotice = msg
            }
        }
    }

    /// Trailing label on the Plus card header. For Plus users this
    /// shows their state instead of a price.
    private var plusCardPriceLine: String {
        entitlement.isPlus ? "Subscribed" : "from \(monthlyPriceFallback)/mo"
    }

    /// Live monthly price, or an em-dash while StoreKit loads — never a
    /// hardcoded number that could flash a wrong price.
    private var monthlyPriceFallback: String {
        StoreKitService.shared
            .product(for: StoreKitService.ProductID.plusMonthly)?
            .displayPrice ?? "—"
    }

    private var notificationsFooter: String {
        switch notificationAuthStatus {
        case .denied:
            return "Notifications are turned off for HiMem at the system level. Tap above or open iOS Settings → Notifications → HiMem to enable."
        case .authorized, .provisional, .ephemeral:
            return "Watch clips ping when they land on the iPhone. No streaks, no nudges — HiMem doesn't raise the skipped thing."
        case .notDetermined:
            return "Notifications haven't been requested yet. Tap above to enable banner pings for watch-clip arrivals."
        @unknown default:
            return ""
        }
    }

    /// Permission row in the Notifications section. State-aware:
    ///   - `.notDetermined` → tap fires the iOS system permission prompt
    ///   - `.denied` → tap opens iOS Settings (system prompt is one-shot;
    ///      after a denial only Settings can re-enable)
    ///   - `.authorized` / `.provisional` / `.ephemeral` → static "On"
    ///      label (no action; iOS Settings is the disable path)
    @ViewBuilder
    private var notificationPermissionRow: some View {
        switch notificationAuthStatus {
        case .notDetermined:
            Button {
                Task { await ensurePermission() }
            } label: {
                HStack {
                    Text("Allow Notifications")
                        .foregroundStyle(Crucible.Color.accent)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        case .denied:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Text("Notifications Off — Open Settings")
                        .foregroundStyle(Crucible.Color.accent)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(Crucible.Color.ink3)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
        case .authorized, .provisional, .ephemeral:
            // RH-1: a real toggle (the persisted app preference the
            // coordinator consults), not just a permission-state row. Ochre
            // on-state per Crucible (never iOS green — green is semantic-only).
            Toggle(isOn: Binding(
                get: { arrivalsEnabled },
                set: { arrivalsEnabled = $0; NotificationPreference.arrivalsEnabled = $0 }
            )) {
                Text("Clip arrivals")
            }
            .tint(Crucible.Color.accent)
        @unknown default:
            EmptyView()
        }
    }

    private func ensurePermission() async {
        _ = await NotificationService.shared.requestPermissionIfNeeded()
        notificationAuthStatus = await NotificationService.shared.authorizationStatus()
    }


    // MARK: - Plus override binding (DEBUG)

    #if DEBUG
    enum PlusOverrideOption: Hashable, CaseIterable {
        case real
        case forcePlus
        case forceFree

        var label: String {
            switch self {
            case .real:      return "Real"
            case .forcePlus: return "Plus"
            case .forceFree: return "Free"
            }
        }

        var booleanValue: Bool? {
            switch self {
            case .real:      return nil
            case .forcePlus: return true
            case .forceFree: return false
            }
        }

        static func from(_ value: Bool?) -> PlusOverrideOption {
            switch value {
            case nil:          return .real
            case .some(true):  return .forcePlus
            case .some(false): return .forceFree
            }
        }
    }

    private var plusOverrideBinding: Binding<PlusOverrideOption> {
        Binding(
            get: { PlusOverrideOption.from(entitlement.developerOverridePlus) },
            set: { entitlement.developerOverridePlus = $0.booleanValue }
        )
    }
    #endif
}

#Preview {
    SettingsView()
}

// MARK: - Appearance sub-screen

/// Settings → Appearance per `docs/design/pricing-screens-settings.jsx
/// ScrSettingsAppearance`. Three radio rows — System (default),
/// Light, Dark — backed by `@AppStorage("appearance")`. Tapping a
/// row mutates the storage; the root `MemoryStreamApp` re-applies
/// `.preferredColorScheme(...)` and the whole app re-renders in the
/// chosen mode immediately.
///
/// Footer reminder: the watch is dark-native and ignores this
/// setting (watch's recording surface needs pure-black OLED at all
/// times, regardless of the user's phone preference).
struct AppearanceSettingsView: View {
    @AppStorage("appearance") private var appearanceRaw: String = Appearance.system.rawValue

    private var current: Appearance {
        Appearance(rawValue: appearanceRaw) ?? .system
    }

    var body: some View {
        Form {
            Section {
                ForEach(Appearance.allCases) { option in
                    Button {
                        appearanceRaw = option.rawValue
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: option.systemImage)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Crucible.Color.ink2)
                                .frame(width: 28, height: 28)
                                .background(Crucible.Color.wash2)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label)
                                    .foregroundStyle(Crucible.Color.ink)
                                Text(option.detail)
                                    .font(.caption)
                                    .foregroundStyle(Crucible.Color.ink3)
                            }
                            Spacer()
                            if current == option {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Crucible.Color.accent)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(option.label). \(option.detail)")
                    .accessibilityAddTraits(current == option ? [.isSelected] : [])
                }
            } header: {
                Text("Theme")
            } footer: {
                Text("The watch is always dark — capture happens in any light.")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}
