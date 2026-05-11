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
    @AppStorage(NotificationService.Keys.notifyDailyNudge) private var notifyDailyNudge = false
    @AppStorage(NotificationService.Keys.nudgeTimeMinutes) private var nudgeTimeMinutes = 1200
    @State private var notificationAuthStatus: UNAuthorizationStatus = .notDetermined
    // autoSaveDelay removed — Composer uses explicit commit

    private let storage = StorageService.shared

    @State private var displayName: String = AuthService.shared.userName
    @ObservedObject private var inbox = InboxManifest.shared
    @State private var showInbox = false

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
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showInbox) {
                if let viewModel {
                    ClipInboxView(viewModel: viewModel)
                }
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
                    let hasEntry = StorageService.shared.hasEntryCreatedToday()
                    await NotificationService.shared.refreshDailyNudge(hadEntryToday: hasEntry)
                }
            }
            .onChange(of: nudgeTimeMinutes) { _, _ in
                Task {
                    let hasEntry = StorageService.shared.hasEntryCreatedToday()
                    await NotificationService.shared.refreshDailyNudge(hadEntryToday: hasEntry)
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
}

#Preview {
    SettingsView()
}
