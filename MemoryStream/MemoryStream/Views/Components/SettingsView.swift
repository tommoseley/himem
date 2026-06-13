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
    @AppStorage("tagMemoriesWithLocation") private var tagMemoriesWithLocation = true
    @AppStorage("fabHandednessLeft") private var fabHandednessLeft = false
    @AppStorage(CameraService.alsoSaveToPhotosLibraryKey) private var alsoSaveToPhotosLibrary = true
    @AppStorage("appearance") private var appearanceRaw: String = Appearance.system.rawValue
    private var appearance: Appearance {
        Appearance(rawValue: appearanceRaw) ?? .system
    }
    @AppStorage(NotificationService.Keys.notifyDailyNudge) private var notifyDailyNudge = false
    @AppStorage(NotificationService.Keys.nudgeTimeMinutes) private var nudgeTimeMinutes = 1200
    @State private var notificationAuthStatus: UNAuthorizationStatus = .notDetermined
    // autoSaveDelay removed — Composer uses explicit commit

    private let storage = StorageService.shared

    @State private var displayName: String = AuthService.shared.userName
    @ObservedObject private var inbox = InboxManifest.shared
    @ObservedObject private var entitlement = Entitlement.shared
    @State private var showInbox = false
    @State private var showPricing = false
    /// Live project count for the C3 "AI & Organizing" row. Backed
    /// by a Core Data fetch so the displayed "N of 3" stays honest
    /// when the user creates or deletes a project from elsewhere
    /// while Settings is open.
    @FetchRequest(
        entity: Project.entity(),
        sortDescriptors: []
    ) private var allProjects: FetchedResults<Project>
    #if DEBUG
    @State private var showResetOnboardingAlert = false
    @State private var showResetTutorialAlert = false
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
                            Text("Tutorials")
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
                if let viewModel {
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
                                let count = viewModel.loadRecycledEntries().count
                                if count > 0 {
                                    Text("\(count)")
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
                }

                // MARK: - AI & Organizing
                // Reads as ambient state for Plus users; for Free users
                // the rows are tappable upgrade-routes — both fields are
                // tier-gated so reaching for either is a "yes, this is
                // how to change it" signal.
                Section {
                    aiOrganizingRow(
                        icon: "sparkles",
                        title: "Organizing",
                        value: entitlement.isPlus ? "Automatic" : "Manual"
                    )
                    aiOrganizingRow(
                        icon: "folder",
                        title: "Projects",
                        value: projectsRowValue
                    )
                } header: {
                    Text("AI & Organizing")
                }

                // MARK: - Captured Clips (Inbox)
                Section {
                    Button {
                        showInbox = true
                    } label: {
                        HStack {
                            Image(systemName: "applewatch")
                                .foregroundStyle(Crucible.Color.accent)
                            Text("Captured Clips")
                                .foregroundStyle(Crucible.Color.ink)
                            Spacer()
                            Text("\(inbox.count) pending")
                                .font(.subheadline)
                                .foregroundStyle(inbox.isEmpty ? Crucible.Color.ink4 : Crucible.Color.ink2)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Crucible.Color.ink4)
                        }
                    }
                    .buttonStyle(.plain)
                } footer: {
                    Text("Voice clips from Apple Watch land here. Review them, then create a new memory or add them to an existing one.")
                }

                // MARK: - Voice
                Section {
                    Toggle("Save voice recordings", isOn: $saveVoiceEntries)
                        .tint(Crucible.Color.accent)
                    Picker("Voice search pace", selection: $voiceSilenceModeRaw) {
                        ForEach(VoiceSilenceMode.allCases) { mode in
                            Text("\(mode.label) · \(mode.subtitle)").tag(mode.rawValue)
                        }
                    }
                } header: {
                    Text("Voice")
                } footer: {
                    Text(saveVoiceEntries
                        ? "Voice recordings are saved on device. You can play them back from entry cards. Tap Done to finish a voice search; the pace setting only controls how long HiMem waits if you stop talking."
                        : "Voice recordings are discarded after transcription. Only the text is kept. Tap Done to finish a voice search; the pace setting only controls how long HiMem waits if you stop talking.")
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
                Section {
                    notificationPermissionRow
                    Toggle("Daily nudge", isOn: $notifyDailyNudge)
                        .tint(Crucible.Color.accent)
                    if notifyDailyNudge {
                        DatePicker(
                            "Nudge time",
                            selection: nudgeTimeBinding,
                            displayedComponents: .hourAndMinute
                        )
                    }
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

                // MARK: - Captures (Photos library opt-in)
                // Default off per the data-custody lock: media lives
                // in HiMem's iCloud Files container, not the Photos
                // library. When the user opts in, captures land in a
                // single "HiMem" album in Photos. The previous
                // per-topic album scheme was retired June 10 2026.
                Section {
                    Toggle("Also save captures to my Photos library",
                           isOn: $alsoSaveToPhotosLibrary)
                        .tint(Crucible.Color.accent)
                } header: {
                    Text("Captures")
                } footer: {
                    Text("Off by default — your photos and videos live in HiMem's iCloud Drive folder. Turn this on to drop a copy into a **HiMem** album in your Photos library too, so you can share or print from Photos.")
                }

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
            .navigationDestination(isPresented: $showInbox) {
                if let viewModel {
                    SessionListView(viewModel: viewModel)
                }
            }
            .sheet(isPresented: $showPricing) {
                PricingView()
            }
            .onAppear {
                loadTopics()
                Task {
                    notificationAuthStatus = await NotificationService.shared.authorizationStatus()
                }
            }
            .onChange(of: notifyDailyNudge) { _, isOn in
                Task {
                    if isOn { await ensurePermissionAndRefresh() }
                    let lastCapture = StorageService.shared.mostRecentEntryAt()
                    await NotificationService.shared.refreshDailyNudge(lastCaptureAt: lastCapture)
                }
            }
            .onChange(of: nudgeTimeMinutes) { _, _ in
                Task {
                    let lastCapture = StorageService.shared.mostRecentEntryAt()
                    await NotificationService.shared.refreshDailyNudge(lastCaptureAt: lastCapture)
                }
            }
            .sheet(isPresented: $showRecycleBin) {
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

    /// Bridges the Int "minutes since midnight" stored in UserDefaults to
    /// the `Date` type the SwiftUI DatePicker expects. Only the time portion
    /// of the Date matters; the calendar day is whatever today is at read.
    private var nudgeTimeBinding: Binding<Date> {
        Binding(
            get: {
                let h = nudgeTimeMinutes / 60
                let m = nudgeTimeMinutes % 60
                return Calendar.current.date(
                    bySettingHour: h, minute: m, second: 0, of: Date()
                ) ?? Date()
            },
            set: { newDate in
                let cal = Calendar.current
                nudgeTimeMinutes = cal.component(.hour, from: newDate) * 60
                                 + cal.component(.minute, from: newDate)
            }
        )
    }

    // MARK: - C3 Plus card

    /// The C3 hero card per `docs/design/pricing-screens-upgrade.jsx`.
    /// Sits inside a Section row but renders its own card chrome
    /// (cream paper, accent stroke, 16pt corner) so it reads as a
    /// hero element above the AI & Organizing list rows.
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

    /// Trailing label on the Plus card header. For Plus users this
    /// shows their state instead of a price.
    private var plusCardPriceLine: String {
        entitlement.isPlus ? "Subscribed" : "from \(monthlyPriceFallback)/mo"
    }

    private var monthlyPriceFallback: String {
        StoreKitService.shared
            .product(for: StoreKitService.ProductID.plusMonthly)?
            .displayPrice ?? "$6.99"
    }

    /// One AI & Organizing list row. Free users see a tappable row
    /// (chevron + label "See plans" → opens PricingView) so the
    /// natural reach for "change this" lands on the upgrade flow.
    /// Plus users see a read-only ambient state row.
    @ViewBuilder
    private func aiOrganizingRow(icon: String, title: String, value: String) -> some View {
        if entitlement.isPlus {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(Crucible.Color.accent)
                    .frame(width: 22)
                Text(title)
                    .foregroundStyle(Crucible.Color.ink)
                Spacer()
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(Crucible.Color.ink2)
            }
        } else {
            Button {
                showPricing = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .foregroundStyle(Crucible.Color.accent)
                        .frame(width: 22)
                    Text(title)
                        .foregroundStyle(Crucible.Color.ink)
                    Spacer()
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(Crucible.Color.ink2)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Crucible.Color.ink4)
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// "N of 3" for Free, "N" for Plus (unlimited).
    private var projectsRowValue: String {
        let count = allProjects.count
        if entitlement.isPlus { return "\(count)" }
        return "\(count) of \(ProjectCapPolicy.freeProjectCap)"
    }

    private var notificationsFooter: String {
        switch notificationAuthStatus {
        case .denied:
            return "Notifications are turned off for HiMem at the system level. Tap above or open iOS Settings → Notifications → HiMem to enable."
        case .authorized, .provisional, .ephemeral:
            return "Watch clips ping when they land on the iPhone. The daily nudge is an optional reminder if you haven't captured anything by your chosen time."
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
                Task { await ensurePermissionAndRefresh() }
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
            HStack {
                Text("Notifications")
                Spacer()
                Text("On")
                    .foregroundStyle(Crucible.Color.ink3)
            }
        @unknown default:
            EmptyView()
        }
    }

    private func ensurePermissionAndRefresh() async {
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
