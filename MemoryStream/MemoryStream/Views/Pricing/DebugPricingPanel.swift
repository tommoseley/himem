#if DEBUG
import SwiftUI

/// Developer-only pricing/entitlement debug panel. Lets you scrub the
/// state machine without going through the App Store sandbox or
/// hand-crafting transactions.
///
/// Wrapped in `#if DEBUG` so it's stripped from Release builds — App
/// Store users never see this. Even at the file level: nothing in this
/// file is compiled in Release.
///
/// Linked from `SettingsView` (also DEBUG-guarded). To find it: open
/// Settings → scroll to "Debug · Pricing" at the bottom.
struct DebugPricingPanel: View {
    @ObservedObject var entitlement: EntitlementService = .shared
    @ObservedObject var founders: FoundersCounter = .shared
    @ObservedObject var tenure: TenureTracker = .shared
    @ObservedObject var promptCoord: UpgradePromptCoordinator = .shared

    @State private var monthlyUsedDraft: Double = 0
    @State private var packBalanceDraft: Double = 0
    @State private var starterUsedDraft: Double = 0
    @State private var foundersClaimedDraft: Double = 0
    @State private var thresholdDraft: Double = 0
    @State private var supporterOverlayDraft: Bool = false

    // Live sheet/screen previews
    @State private var showUpgradePrompt = false
    @State private var showPackPurchase = false
    @State private var showFoundersDetail = false
    @State private var showSupporterDetail = false
    @State private var showProjectCap = false
    @State private var showOnboardingStarter = false
    @State private var showAlert: AlertInfo?

    struct AlertInfo: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        Form {
            tierSection
            assistsSection
            autoOrganizeSection
            supporterOverlaySection
            grantFlagsSection
            foundersSection
            tenureSection
            upgradePromptSection
            previewSection
            resetSection
        }
        .navigationTitle("Debug · Pricing")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { syncDrafts() }
        .alert(item: $showAlert) { info in
            Alert(title: Text(info.title), message: Text(info.message), dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $showUpgradePrompt) {
            UpgradePromptSheet().presentationDetents([.large])
        }
        .sheet(isPresented: $showPackPurchase) {
            AIPackPurchaseSheet().presentationDetents([.large])
        }
        .sheet(isPresented: $showFoundersDetail) {
            NavigationStack { FoundersDetailView() }
        }
        .sheet(isPresented: $showSupporterDetail) {
            NavigationStack { SupporterDetailView() }
        }
        .sheet(isPresented: $showProjectCap) {
            ProjectCapSheet().presentationDetents([.medium])
        }
        .sheet(isPresented: $showOnboardingStarter) {
            OnboardingStarterCard().presentationDetents([.large])
        }
    }

    // MARK: - Tier

    private var tierSection: some View {
        Section {
            Picker("Tier", selection: tierBinding) {
                Text("Free").tag(EntitlementService.Tier.free)
                Text("Plus · Monthly").tag(EntitlementService.Tier.plusMonthly)
                Text("Plus · Yearly").tag(EntitlementService.Tier.plusYearly)
                Text("Founders Lifetime").tag(EntitlementService.Tier.founders)
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Toggle("Use developer override", isOn: Binding(
                get: { entitlement.developerOverrideTier != nil },
                set: { useOverride in
                    entitlement.developerOverrideTier = useOverride ? entitlement.tier : nil
                }
            ))
        } header: {
            Text("Tier")
        } footer: {
            Text("Developer override bypasses StoreKit and pins the tier to whatever you pick here. When off, the tier follows real subscription state.")
        }
    }

    private var tierBinding: Binding<EntitlementService.Tier> {
        Binding(
            get: { entitlement.tier },
            set: { newTier in
                if entitlement.developerOverrideTier != nil {
                    entitlement.developerOverrideTier = newTier
                } else {
                    entitlement.setTier(newTier)
                }
            }
        )
    }

    // MARK: - Assists

    private var assistsSection: some View {
        Section {
            VStack(alignment: .leading) {
                HStack {
                    Text("Monthly used")
                    Spacer()
                    Text("\(Int(monthlyUsedDraft)) / 50")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $monthlyUsedDraft, in: 0...50, step: 1) { editing in
                    if !editing {
                        entitlement.debugSetMonthlyUsed(Int(monthlyUsedDraft))
                    }
                }
            }

            VStack(alignment: .leading) {
                HStack {
                    Text("Pack balance")
                    Spacer()
                    Text("\(Int(packBalanceDraft))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $packBalanceDraft, in: 0...150, step: 1) { editing in
                    if !editing {
                        entitlement.debugSetPackBalance(Int(packBalanceDraft))
                    }
                }
                HStack(spacing: 8) {
                    presetButton("0") { setPackBalance(0) }
                    presetButton("20") { setPackBalance(20) }
                    presetButton("100") { setPackBalance(100) }
                    presetButton("120") { setPackBalance(120) }
                }
            }

            VStack(alignment: .leading) {
                HStack {
                    Text("Starter used")
                    Spacer()
                    Text("\(Int(starterUsedDraft)) / 3")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $starterUsedDraft, in: 0...3, step: 1) { editing in
                    if !editing {
                        entitlement.debugSetStarterUsed(Int(starterUsedDraft))
                    }
                }
            }
        } header: {
            Text("AI Assists")
        } footer: {
            Text("Monthly drains first (Plus/Founders), then pack balance. Starter is the Free one-time 3-pack — granted into packBalance when the user first encounters Organize.")
        }
    }

    private func setPackBalance(_ value: Int) {
        packBalanceDraft = Double(value)
        entitlement.debugSetPackBalance(value)
    }

    // MARK: - Auto-organize threshold

    private var autoOrganizeSection: some View {
        Section {
            VStack(alignment: .leading) {
                HStack {
                    Text("Threshold")
                    Spacer()
                    Text("\(Int(thresholdDraft)) / 50")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $thresholdDraft, in: 0...50, step: 1) { editing in
                    if !editing {
                        entitlement.debugSetAutoOrganizeThreshold(Int(thresholdDraft))
                    }
                }
            }
            HStack {
                Text("canAutoOrganize")
                Spacer()
                Text(entitlement.canAutoOrganize ? "true" : "false")
                    .foregroundStyle(entitlement.canAutoOrganize ? .green : .secondary)
                    .monospacedDigit()
            }
        } header: {
            Text("Auto-organize")
        } footer: {
            Text("Auto-org runs when totalAssistsRemaining > threshold. At 0, runs while any assists remain. At ≥ remaining, never runs. Manual taps ignore this.")
        }
    }

    // MARK: - Supporter overlay

    private var supporterOverlaySection: some View {
        Section {
            Toggle("Is Supporter (overlay)", isOn: Binding(
                get: { entitlement.isSupporter },
                set: { entitlement.isSupporter = $0 }
            ))
        } header: {
            Text("Supporter")
        } footer: {
            Text("Composes with any tier except Founders (Founders subsumes Supporter). Surfaces the overlay card on the Plan Hub + a heart TierMark for Free users. Production storage TBD when Supporter SKU ships.")
        }
    }

    // MARK: - Grant flags

    private var grantFlagsSection: some View {
        Section {
            Toggle("Starter granted", isOn: Binding(
                get: { entitlement.starterGranted },
                set: { entitlement.debugSetStarterGranted($0) }
            ))
            Toggle("Founders bonus granted", isOn: Binding(
                get: { entitlement.foundersBonusGranted },
                set: { entitlement.debugSetFoundersBonusGranted($0) }
            ))
        } header: {
            Text("Grant flags")
        } footer: {
            Text("Idempotency guards for one-time grants. Flip to false to replay the grant on the next code path that calls grantStarterIfNeeded / grantFoundersBonusIfNeeded.")
        }
    }

    // MARK: - Founders cap

    private var foundersSection: some View {
        Section {
            VStack(alignment: .leading) {
                HStack {
                    Text("Claimed")
                    Spacer()
                    Text("\(Int(foundersClaimedDraft)) / 250")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $foundersClaimedDraft, in: 0...250, step: 1) { editing in
                    if !editing {
                        founders.debugSetClaimed(Int(foundersClaimedDraft))
                    }
                }
                HStack(spacing: 8) {
                    presetButton("0") { setClaimed(0) }
                    presetButton("47") { setClaimed(47) }
                    presetButton("238") { setClaimed(238) }
                    presetButton("250") { setClaimed(250) }
                }
            }
            Button("Refresh from CloudKit") {
                Task { await founders.refresh() }
            }
        } header: {
            Text("Founders cap")
        } footer: {
            Text("Local override — doesn't write to the public CloudKit counter. 'Refresh from CloudKit' pulls the real value and clobbers the override.")
        }
    }

    private func setClaimed(_ value: Int) {
        foundersClaimedDraft = Double(value)
        founders.debugSetClaimed(value)
    }

    // MARK: - Tenure

    private var tenureSection: some View {
        Section {
            HStack {
                Text("Tenured")
                Spacer()
                Text(tenure.isTenured ? "Yes" : "No")
                    .foregroundStyle(.secondary)
            }
            Button("Set install date to 31 days ago") {
                tenure.debugSetInstallDaysAgo(31)
            }
            Button("Set install date to today") {
                tenure.debugSetInstallDaysAgo(0)
            }
        } header: {
            Text("Tenure")
        } footer: {
            Text("Supporter row surfaces when tier == Free AND 30+ days of install AND 10+ memories saved.")
        }
    }

    // MARK: - Upgrade prompt

    private var upgradePromptSection: some View {
        Section {
            Button("Clear 'has shown' flag (re-arm)") {
                promptCoord.debugClearShownFlag()
                promptCoord.evaluate()
            }
            Button("Force show prompt now") {
                promptCoord.debugForceShow()
            }
            Button("Evaluate trigger") {
                promptCoord.evaluate()
                if !promptCoord.shouldShow {
                    showAlert = AlertInfo(
                        title: "Trigger not met",
                        message: "Need: tier == Free, starterUsed >= 3, memories saved >= 5. Adjust above and re-evaluate."
                    )
                }
            }
        } header: {
            Text("Upgrade prompt (3 + 5 trigger)")
        }
    }

    // MARK: - Surface previews

    private var previewSection: some View {
        Section {
            Button("Onboarding starter card") { showOnboardingStarter = true }
            Button("Upgrade prompt sheet") { showUpgradePrompt = true }
            Button("AI pack purchase sheet") { showPackPurchase = true }
            Button("Founders detail") { showFoundersDetail = true }
            Button("Supporter detail") { showSupporterDetail = true }
            Button("Project cap modal") { showProjectCap = true }
        } header: {
            Text("Preview surfaces directly")
        }
    }

    // MARK: - Reset

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                entitlement.debugResetAll()
                promptCoord.debugClearShownFlag()
                syncDrafts()
            } label: {
                Text("Reset all entitlement state")
            }
        } footer: {
            Text("Wipes tier, monthly used, pack balance, starter, Founders bonus flag, and the upgrade-prompt shown pin. Doesn't touch CloudKit or StoreKit transaction history.")
        }
    }

    // MARK: - Helpers

    private func presetButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.system(.caption, design: .monospaced))
    }

    private func syncDrafts() {
        monthlyUsedDraft = Double(entitlement.monthlyUsed)
        packBalanceDraft = Double(entitlement.packBalance)
        starterUsedDraft = Double(entitlement.starterUsed)
        foundersClaimedDraft = Double(founders.claimed)
        thresholdDraft = Double(entitlement.autoOrganizeThreshold)
    }
}

#Preview {
    NavigationStack {
        DebugPricingPanel()
    }
}
#endif
