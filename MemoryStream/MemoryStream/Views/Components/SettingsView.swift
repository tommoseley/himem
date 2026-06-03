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
    @ObservedObject private var entitlement = EntitlementService.shared
    @ObservedObject private var tenure = TenureTracker.shared
    @State private var showInbox = false
    @State private var showYourAI = false
    @State private var showUpgradeHub = false
    @State private var showSupporter = false
    #if DEBUG
    @State private var showDebugPricing = false
    @State private var scaleSeedProgress: (current: Int, total: Int)? = nil
    @State private var scaleStatusMessage: String? = nil
    @State private var scaleWorking: Bool = false
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
                            .onSubmit {
                                let name = displayName.trimmingCharacters(in: .whitespaces)
                                guard !name.isEmpty else { return }
                                let _ = KeychainService.shared.save(key: "userName", value: name)
                                AuthService.shared.userName = name
                            }
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

                // MARK: - HiMem Plus (Pricing)
                Section {
                    Button {
                        showYourAI = true
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Crucible.Color.accent)
                            Text("Your AI")
                                .foregroundStyle(Crucible.Color.ink)
                            Spacer()
                            Text(aiSummary)
                                .font(.subheadline)
                                .foregroundStyle(Crucible.Color.ink2)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Crucible.Color.ink4)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        showUpgradeHub = true
                    } label: {
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundStyle(Crucible.Color.accent)
                            Text("HiMem Plus")
                                .foregroundStyle(Crucible.Color.ink)
                            Spacer()
                            Text(planSummary)
                                .font(.subheadline)
                                .foregroundStyle(Crucible.Color.ink2)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Crucible.Color.ink4)
                        }
                    }
                    .buttonStyle(.plain)
                } footer: {
                    Text("HiMem AI is the helper, not the product. Free works forever; Plus adds AI organization and unlimited projects.")
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

                // MARK: - Supporter (post-trust only)
                if tenure.isTenured {
                    Section {
                        Button {
                            showSupporter = true
                        } label: {
                            HStack {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(Crucible.Color.accent)
                                Text("Support HiMem")
                                    .foregroundStyle(Crucible.Color.ink)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Crucible.Color.ink4)
                            }
                        }
                        .buttonStyle(.plain)
                    } header: {
                        Text("Behind HiMem")
                    } footer: {
                        Text("Voluntary. No feature unlocks. We surface this only after you've stuck around.")
                    }
                }

                // MARK: - Voice
                Section {
                    Toggle("Save voice recordings", isOn: $saveVoiceEntries)
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
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Location stays on your device. We never send it to the server. Turn this off and new memories will be saved without location.")
                }

                // MARK: - Notifications
                Section {
                    notificationPermissionRow
                    Toggle("Daily nudge", isOn: $notifyDailyNudge)
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
                } header: {
                    Text("Handedness")
                } footer: {
                    Text("Anchors the Add button to the bottom-left of the screen instead of the bottom-right. The action stack flips with it.")
                }

                #if DEBUG
                // MARK: - Debug (stripped from Release builds)
                Section {
                    Button {
                        showDebugPricing = true
                    } label: {
                        HStack {
                            Image(systemName: "ladybug.fill")
                                .foregroundStyle(.purple)
                            Text("Pricing & entitlements")
                                .foregroundStyle(Crucible.Color.ink)
                            Spacer()
                            Text(devTierLabel)
                                .font(.caption)
                                .foregroundStyle(Crucible.Color.ink3)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Crucible.Color.ink4)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Debug")
                } footer: {
                    Text("Developer-only. Compiled out of Release builds — App Store users never see this section.")
                }

                // MARK: - Scaling test
                Section {
                    Button("Seed 100 test entries") {
                        Task { await seedScalingTestData(count: 100) }
                    }
                    .disabled(scaleWorking)
                    Button("Seed 1,000 test entries") {
                        Task { await seedScalingTestData(count: 1000) }
                    }
                    .disabled(scaleWorking)
                    Button("Seed 10,000 test entries") {
                        Task { await seedScalingTestData(count: 10000) }
                    }
                    .disabled(scaleWorking)
                    Button(role: .destructive) {
                        Task { await deleteScalingTestData() }
                    } label: {
                        Text("Delete test entries")
                    }
                    .disabled(scaleWorking)
                    if let progress = scaleSeedProgress {
                        HStack(spacing: 8) {
                            ProgressView(value: Double(progress.current), total: Double(progress.total))
                            Text("\(progress.current) / \(progress.total)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    } else if let message = scaleStatusMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Scaling test")
                } footer: {
                    Text("Seeds JournalEntry records identified by title prefix 'Scale-test #'. After seeding, allow time for CloudKit to mirror to iCloud before cold-launch measurement. Delete is filtered to the same prefix and won't touch real memories.")
                }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showInbox) {
                if let viewModel {
                    SessionListView(viewModel: viewModel)
                }
            }
            .navigationDestination(isPresented: $showYourAI) {
                YourAIView()
            }
            .navigationDestination(isPresented: $showUpgradeHub) {
                UpgradeHubView()
            }
            .navigationDestination(isPresented: $showSupporter) {
                SupporterDetailView()
            }
            #if DEBUG
            .navigationDestination(isPresented: $showDebugPricing) {
                DebugPricingPanel()
            }
            #endif
            .onAppear {
                loadTopics()
                tenure.refresh()
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
            AlbumSyncService.shared.migrateTopicName(from: oldName, to: name)
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

    // MARK: - Pricing summaries

    private var aiSummary: String {
        if entitlement.isPlus {
            return "\(entitlement.monthlyRemaining)/\(entitlement.monthlyAllowance) this month"
        }
        return "\(entitlement.totalAssistsRemaining) assists"
    }

    private var planSummary: String {
        switch entitlement.tier {
        case .free: return "Upgrade"
        case .plusMonthly: return "Plus · Monthly"
        case .plusYearly: return "Plus · Yearly"
        case .founders: return "Founders"
        }
    }

    #if DEBUG
    /// Compact tier label for the debug-section row, with an "(override)"
    /// suffix when the developer override is in play so it's obvious at
    /// a glance which path is driving the tier.
    private var devTierLabel: String {
        let base = planSummary
        if entitlement.developerOverrideTier != nil {
            return "\(base) · override"
        }
        return base
    }

    // MARK: - Scaling test (DEBUG only)

    /// Seeds N JournalEntry records onto a background context so the cold-
    /// launch CloudKit-import question — is the post-load gap O(1) or
    /// O(n) — can be answered empirically. Each entry is minimal (just
    /// the required fields) so we measure CloudKit sync overhead per
    /// record, not per-relationship fan-out.
    @MainActor
    private func seedScalingTestData(count: Int) async {
        scaleWorking = true
        scaleSeedProgress = (0, count)
        scaleStatusMessage = nil
        await Self.seed(count: count) { current in
            Task { @MainActor in
                scaleSeedProgress = (current, count)
            }
        }
        scaleSeedProgress = nil
        scaleStatusMessage = "Seeded \(count). Wait for CloudKit sync (could be minutes for 10k) then cold-launch."
        scaleWorking = false
    }

    /// Deletes every JournalEntry whose title starts with "Scale-test #".
    /// Real memories cannot match this predicate unless the user
    /// deliberately titled one that way, in which case they earned it.
    @MainActor
    private func deleteScalingTestData() async {
        scaleWorking = true
        scaleStatusMessage = "Deleting test entries…"
        let deleted = await Self.deleteTestEntries()
        scaleStatusMessage = "Deleted \(deleted) test entries."
        scaleWorking = false
    }

    private static func seed(count: Int, onProgress: @escaping (Int) -> Void) async {
        let bg = StorageService.shared.backgroundContext()
        await bg.perform {
            let chunkSize = 200
            var created = 0
            for chunkStart in stride(from: 0, to: count, by: chunkSize) {
                let chunkEnd = min(chunkStart + chunkSize, count)
                for i in chunkStart..<chunkEnd {
                    let entry = JournalEntry(context: bg)
                    entry.id = UUID()
                    entry.title = "Scale-test #\(i + 1)"
                    entry.content = "Auto-generated test data entry \(i + 1)."
                    entry.inputType = "typed"
                    entry.createdAt = Date().addingTimeInterval(-TimeInterval(i * 60))
                    entry.isRecycled = false
                    entry.titleSourcedFromAI = false
                    created += 1
                }
                do {
                    try bg.save()
                } catch {
                    NSLog("[ScalingTest] Save failed at \(created): \(error.localizedDescription)")
                    return
                }
                bg.reset() // drop materialized objects between batches so we don't balloon memory on 10k runs
                onProgress(created)
            }
        }
    }

    private static func deleteTestEntries() async -> Int {
        let bg = StorageService.shared.backgroundContext()
        return await bg.perform {
            let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            req.predicate = NSPredicate(format: "title BEGINSWITH %@", "Scale-test #")
            do {
                let entries = try bg.fetch(req)
                let count = entries.count
                for entry in entries {
                    bg.delete(entry)
                }
                try bg.save()
                return count
            } catch {
                NSLog("[ScalingTest] Delete failed: \(error.localizedDescription)")
                return 0
            }
        }
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
