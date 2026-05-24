import SwiftUI

/// Dismissible toast at the top of Today that surfaces once per
/// monthly period when usage crosses 75%. Doesn't block anything — a
/// heads-up that lets Plus / Founders users plan ahead.
///
/// Suppression logic:
///   • Tracks the monthly reset date the user dismissed against. When
///     a new period starts (resetDate changes), the dismissal lifts.
///   • Free users never see this — they have no monthly allowance.
struct Soft75Banner: View {
    @ObservedObject var entitlement: EntitlementService = .shared
    @AppStorage("soft75.dismissedForResetDate") private var dismissedForResetEpoch: Double = 0

    var body: some View {
        if shouldShow {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(Crucible.Color.warning)
                    .frame(width: 6, height: 6)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(entitlement.monthlyUsed) of \(entitlement.monthlyAllowance) assists used this month")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(softWarnFg)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(softWarnFg.opacity(0.85))
                        .lineSpacing(2)
                }
                Spacer(minLength: 4)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(softWarnFg.opacity(0.5))
                        .padding(.top, 2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color(red: 0.96, green: 0.91, blue: 0.82))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var shouldShow: Bool {
        guard entitlement.isPlus else { return false }
        guard entitlement.monthlyAllowance > 0 else { return false }
        let frac = Double(entitlement.monthlyUsed) / Double(entitlement.monthlyAllowance)
        guard frac >= 0.75 && frac < 1.0 else { return false }
        // Suppress if user already dismissed this period
        if let resetDate = entitlement.monthlyResetDate,
           dismissedForResetEpoch == resetDate.timeIntervalSince1970 {
            return false
        }
        return true
    }

    private var subtitle: String {
        guard let resetDate = entitlement.monthlyResetDate else { return "Add more any time." }
        return "Resets \(Soft75Banner.resetFormatter.string(from: resetDate)). Add more any time."
    }

    private func dismiss() {
        if let resetDate = entitlement.monthlyResetDate {
            dismissedForResetEpoch = resetDate.timeIntervalSince1970
        }
    }

    private var softWarnFg: Color { Color(red: 0.48, green: 0.29, blue: 0.06) }

    private static let resetFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}
