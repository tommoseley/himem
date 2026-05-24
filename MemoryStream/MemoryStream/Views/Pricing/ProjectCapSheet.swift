import SwiftUI

/// Quiet bottom sheet shown when a Free user tries to create a second
/// project. Doesn't gate the rest of HiMem — just this one action.
/// Offers Upgrade as the path forward, plus the gentler reminder that
/// tagging works inside the existing project for free.
struct ProjectCapSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showUpgradeHub = false

    var body: some View {
        ZStack {
            Crucible.Color.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Crucible.Color.accentTint)
                        .frame(width: 32, height: 32)
                    Image(systemName: "folder")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Crucible.Color.accent)
                }
                .padding(.bottom, 14)

                Text("Free includes one project.")
                    .font(PricingFonts.serif(22))
                    .foregroundStyle(Crucible.Color.ink)
                    .lineSpacing(2)
                    .padding(.bottom, 10)

                Text("Plus opens up as many as you want — keep work, family, and the garden in their own spaces.")
                    .font(.system(size: 14))
                    .foregroundStyle(Crucible.Color.ink2)
                    .lineSpacing(2)
                    .padding(.bottom, 6)

                Text("You can also tag memories inside your existing project — that's free.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Crucible.Color.ink3)
                    .lineSpacing(2)

                Spacer()

                VStack(spacing: 8) {
                    PricingPrimaryButton(title: "Upgrade to Plus · $4.99/mo") {
                        showUpgradeHub = true
                    }
                    PricingGhostButton(title: "Maybe later") {
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 26)
        }
        .sheet(isPresented: $showUpgradeHub) {
            NavigationStack {
                UpgradeHubView()
            }
        }
    }
}

#Preview {
    ProjectCapSheet()
}
