import SwiftUI

/// C1 · After-a-glance upgrade nudge per
/// `docs/design/pricing-screens-upgrade.jsx` `ScrUpgradeC1`. Fires
/// once-ever — right after the user keeps their first draft. They've
/// felt the value; offer to deepen it. Framed as capability ("reach"),
/// never as "you're missing out", and never implying Plus is less
/// private.
///
/// The trigger is "first draft reviewed" — handled by the user
/// committing "Looks good" or otherwise dismissing the
/// `DraftReviewSheet`. Persistence lives in `UpgradeNudgeFlags`
/// (UserDefaults), so the "Shown once. Never again inline." promise
/// holds across launches.
///
/// "See Plus" opens `PricingView`; "Not now" sets the persistent flag
/// so the nudge never reappears here.
struct AfterAGlanceNudge: View {
    var onSeePlus: () -> Void
    var onNotNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Crucible.Color.aiBlue)
                        .frame(width: 24, height: 24)
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text("Want this to just happen?")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink)
            }
            .padding(.bottom, 7)

            Text("Plus organizes every memory the moment you capture it — and reaches across your library to connect what belongs together.")
                .font(.system(size: 12.5))
                .foregroundStyle(Crucible.Color.ink2)
                .lineSpacing(2)
                .padding(.bottom, 12)

            HStack(spacing: 9) {
                Button(action: onSeePlus) {
                    Text("See Plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Crucible.Color.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Button(action: onNotNow) {
                    Text("Not now")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Crucible.Color.ink2)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Crucible.Color.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Crucible.Color.hairline, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .background(Crucible.Color.aiBlueTint)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Crucible.Color.aiBlue, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// UserDefaults-backed persistence for the upgrade-nudge once-ever
/// flags. Single bool today (C1); kept as a typed wrapper so future
/// triggers (C2-rejected, post-launch C4) can compose without
/// scattering key strings.
enum UpgradeNudgeFlags {
    private static let c1ShownKey = "himem.upgrade.c1Shown"

    static var c1HasShown: Bool {
        UserDefaults.standard.bool(forKey: c1ShownKey)
    }

    static func markC1Shown() {
        UserDefaults.standard.set(true, forKey: c1ShownKey)
    }
}
