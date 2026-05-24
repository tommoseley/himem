import SwiftUI

/// Settings → Your AI. The day-to-day home for the assist counter.
///
/// Hero varies by tier:
///   • **Free** — total balance (starter remaining + pack balance) with
///     breakdown copy
///   • **Plus / Founders** — monthly remaining/total + ring + reset date
///
/// Followed by:
///   • Pack balance group (Plus only, when packBalance > 0)
///   • Add more (always — links into AIPackPurchaseSheet)
///   • Plan (current tier, Upgrade or Manage)
struct YourAIView: View {
    @ObservedObject var entitlement: EntitlementService = .shared
    @State private var showPackPurchase = false
    @State private var showUpgradeHub = false
    @State private var thresholdDraft: Double = 0
    @State private var thresholdDraftSeeded: Bool = false

    var body: some View {
        ZStack {
            Crucible.Color.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroSection
                        .padding(.horizontal, 18)
                        .padding(.bottom, 22)

                    if entitlement.isPlus && entitlement.packBalance > 0 {
                        packBalanceGroup
                            .padding(.bottom, 20)
                    }

                    if entitlement.isPlus {
                        autoOrganizeGroup
                            .padding(.bottom, 20)
                    }

                    addMoreGroup
                        .padding(.bottom, 20)

                    planGroup

                    Text("AI is an organizational helper, not the product. HiMem works without it.")
                        .font(.system(size: 11))
                        .foregroundStyle(Crucible.Color.ink3)
                        .padding(.horizontal, 22)
                        .padding(.top, 20)
                        .lineSpacing(2)
                }
                .padding(.top, 6)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("Your AI")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPackPurchase) {
            AIPackPurchaseSheet()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showUpgradeHub) {
            NavigationStack {
                UpgradeHubView()
            }
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private var heroSection: some View {
        if entitlement.isPlus {
            plusHero
        } else {
            freeHero
        }
    }

    private var freeHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            PricingEyebrow(text: "Free · Starter + Packs")
                .padding(.bottom, 8)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(entitlement.totalAssistsRemaining)")
                    .font(PricingFonts.serif(48))
                    .foregroundStyle(Crucible.Color.ink)
                Text(entitlement.totalAssistsRemaining == 1 ? "assist remaining" : "assists remaining")
                    .font(.system(size: 14))
                    .foregroundStyle(Crucible.Color.ink2)
            }
            Text(freeBreakdown)
                .font(.system(size: 12.5))
                .foregroundStyle(Crucible.Color.ink3)
                .padding(.top, 6)
                .lineSpacing(2)
        }
    }

    private var freeBreakdown: String {
        let starterLeft = entitlement.starterRemaining
        let packs = entitlement.packBalance - max(0, starterLeft)
        // packBalance includes starter assists. Show the breakdown
        // honestly: starter left, then pack count.
        if !entitlement.starterGranted {
            return "Try AI on a memory to receive 3 starter assists."
        }
        if starterLeft > 0 {
            return "\(starterLeft) starter · \(max(0, packs)) from packs · packs never expire"
        }
        return "\(entitlement.packBalance) from packs · never expire"
    }

    private var plusHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            PricingEyebrow(text: "This month")
                .padding(.bottom, 8)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(entitlement.monthlyRemaining)")
                    .font(PricingFonts.serif(48))
                    .foregroundStyle(Crucible.Color.ink)
                Text("/ \(entitlement.monthlyAllowance)")
                    .font(PricingFonts.serif(18))
                    .foregroundStyle(Crucible.Color.ink3)
                Text("included")
                    .font(.system(size: 14))
                    .foregroundStyle(Crucible.Color.ink2)
                    .padding(.leading, 6)
            }
            // Progress bar
            ProgressView(value: usedFraction)
                .progressViewStyle(.linear)
                .tint(progressTint)
                .padding(.top, 14)
            HStack {
                Text("\(entitlement.monthlyUsed) used")
                Spacer()
                if let resetDate = entitlement.monthlyResetDate {
                    Text("Resets \(YourAIView.resetFormatter.string(from: resetDate))")
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Crucible.Color.ink3)
            .padding(.top, 8)
        }
    }

    private var usedFraction: Double {
        guard entitlement.monthlyAllowance > 0 else { return 0 }
        return Double(entitlement.monthlyUsed) / Double(entitlement.monthlyAllowance)
    }

    private var progressTint: Color {
        let f = usedFraction
        if f >= 1.0 { return Crucible.Color.danger }
        if f >= 0.75 { return Crucible.Color.warning }
        return Crucible.Color.accent
    }

    // MARK: - Groups

    /// Settings → Your AI → Auto-organize. Plus/Founders only — Free
    /// has no auto-org to gate. Slider 0 … monthlyAllowance lets the
    /// user reserve some of their assist budget for explicit manual
    /// taps. At 0 (default), auto-org runs while any assists remain.
    private var autoOrganizeGroup: some View {
        groupedList(
            header: "Auto-organize",
            footer: thresholdFooter
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Reserve for manual organize")
                        .font(.system(size: 15))
                        .foregroundStyle(Crucible.Color.ink)
                    Spacer()
                    Text("\(Int(thresholdDraft))")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(Crucible.Color.ink2)
                        .monospacedDigit()
                }
                Slider(
                    value: $thresholdDraft,
                    in: 0...Double(entitlement.monthlyAllowance),
                    step: 1
                ) { editing in
                    if !editing {
                        entitlement.setAutoOrganizeThreshold(Int(thresholdDraft))
                    }
                }
                .tint(Crucible.Color.accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .onAppear {
            if !thresholdDraftSeeded {
                thresholdDraft = Double(entitlement.autoOrganizeThreshold)
                thresholdDraftSeeded = true
            }
        }
        .onChange(of: entitlement.autoOrganizeThreshold) { _, newValue in
            thresholdDraft = Double(newValue)
        }
    }

    private var thresholdFooter: String {
        let threshold = Int(thresholdDraft)
        let remaining = entitlement.totalAssistsRemaining
        if threshold == 0 {
            return "Auto-organize uses everything. Currently \(remaining) left. Manual Organize always works."
        }
        if threshold >= remaining {
            return "Auto-organize is off (you've reserved more than you have left). Currently \(remaining) left. Manual Organize always works."
        }
        return "Auto-organize runs while remaining > \(threshold). Currently \(remaining) left. Manual Organize always works."
    }

    private var packBalanceGroup: some View {
        groupedList(header: "Pack balance") {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Crucible.Color.accent)
                    .frame(width: 26, height: 26)
                    .background(Crucible.Color.accentTint)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(entitlement.packBalance) pack assists")
                        .font(.system(size: 15))
                        .foregroundStyle(Crucible.Color.ink)
                    Text("Used after your monthly allowance. Never expire.")
                        .font(.system(size: 12))
                        .foregroundStyle(Crucible.Color.ink3)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private var addMoreGroup: some View {
        groupedList(header: "Add more") {
            VStack(spacing: 0) {
                Button { showPackPurchase = true } label: {
                    settingsRow(iconSystem: "plus", title: "20 assists", value: "$4.99")
                }
                .buttonStyle(.plain)
                Divider().background(Crucible.Color.divider).padding(.leading, 52)
                Button { showPackPurchase = true } label: {
                    settingsRow(iconSystem: "plus", title: "100 assists", value: "$19.99")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var planGroup: some View {
        groupedList(header: "Plan", footer: "Cancel anytime in Settings. AI features pause; your memories stay.") {
            Button {
                if !entitlement.isPlus {
                    showUpgradeHub = true
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: entitlement.isPlus ? "sparkles" : "books.vertical")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Crucible.Color.accent)
                        .frame(width: 26, height: 26)
                        .background(Crucible.Color.accentTint)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tierLabel)
                            .font(.system(size: 15))
                            .foregroundStyle(Crucible.Color.ink)
                        Text(planSubtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Crucible.Color.ink3)
                    }
                    Spacer()
                    if entitlement.isPlus {
                        Text("Manage")
                            .font(.system(size: 14))
                            .foregroundStyle(Crucible.Color.ink3)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Crucible.Color.ink4)
                    } else {
                        Text("Upgrade")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Crucible.Color.accent)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
    }

    private var tierLabel: String {
        switch entitlement.tier {
        case .free: return "Free"
        case .plusMonthly: return "Plus · Monthly"
        case .plusYearly: return "Plus · Yearly"
        case .founders: return "Founders Lifetime"
        }
    }

    private var planSubtitle: String {
        switch entitlement.tier {
        case .free: return "Save, organize, capture — yours forever."
        case .plusMonthly: return "$4.99/month · AI organization and unlimited projects."
        case .plusYearly: return "$39.99/year · two months free."
        case .founders: return "Plus features for life · TestFlight + bonus assists."
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func groupedList<Content: View>(
        header: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PricingEyebrow(text: header)
                .padding(.horizontal, 22)
            VStack(spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Crucible.Color.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Crucible.Color.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 14)
            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(Crucible.Color.ink3)
                    .padding(.horizontal, 22)
                    .padding(.top, 2)
                    .lineSpacing(2)
            }
        }
    }

    private func settingsRow(iconSystem: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconSystem)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Crucible.Color.accent)
                .frame(width: 26, height: 26)
                .background(Crucible.Color.accentTint)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(Crucible.Color.ink)
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(Crucible.Color.ink3)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private static let resetFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}

#Preview {
    NavigationStack {
        YourAIView()
    }
}
