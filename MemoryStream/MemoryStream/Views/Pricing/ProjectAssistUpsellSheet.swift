import SwiftUI

/// Upsell sheet fired on the second tap of "Find the thread" by a
/// Free user — the first tap consumed the starter Project Assist
/// silently, this tap routes here. Distinct from `ProjectCapSheet`
/// (which gates *creating* projects) and `UpgradePromptSheet` (the
/// 3-starter + 5-memories memory-assist conversion). Same Crucible
/// vocabulary as those siblings — quiet ochre, two paths, no math.
struct ProjectAssistUpsellSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showUpgradeHub = false

    var body: some View {
        ZStack {
            Crucible.Color.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Crucible.Color.aiBlueTint)
                        .frame(width: 32, height: 32)
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Crucible.Color.aiBlue)
                }
                .padding(.bottom, 14)

                Text("You've used your starter project assist.")
                    .font(PricingFonts.serif(22))
                    .foregroundStyle(Crucible.Color.ink)
                    .lineSpacing(2)
                    .padding(.bottom, 10)

                Text("Plus opens up unlimited assists across every project, plus a 50-per-month allowance for memory organizing.")
                    .font(.system(size: 14))
                    .foregroundStyle(Crucible.Color.ink2)
                    .lineSpacing(2)
                    .padding(.bottom, 14)

                Button {
                    showUpgradeHub = true
                } label: {
                    Text("Upgrade to Plus · $4.99/mo")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Crucible.Color.aiBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 8)

                Button {
                    dismiss()
                } label: {
                    Text("Not now")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Crucible.Color.ink3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
        }
        .sheet(isPresented: $showUpgradeHub) {
            UpgradeHubView()
                .presentationDetents([.large])
        }
    }
}
