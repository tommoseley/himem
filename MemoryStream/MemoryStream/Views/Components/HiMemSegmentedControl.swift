import SwiftUI

/// The ochre-track segmented pill. Generic over any identifiable option
/// with a display label. Selection language matches the Clips lock (Tom,
/// 2026-07-12): accent fill + accentInk bold text when selected; ink2
/// medium otherwise, on a `wash1` track.
///
/// **Extracted from `ClipsTabView` in I2** (2026-09-20). It was factored out
/// of the Clips header status lens in July 2026 precisely so Recently
/// Deleted's type selector could reuse the exact control rather than a
/// lookalike — and that second caller is why it outlives the lens it was
/// born for. The two-axis filter retires with the bench; the control does
/// not.
struct HiMemSegmentedControl<Option: Identifiable & Equatable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String
    /// Optional per-option count. When provided, a small count pill renders
    /// after the label for any option whose count is > 0. Omitted (nil) →
    /// label-only, byte-identical to the pre-count control.
    var count: ((Option) -> Int)? = nil

    private var showsCounts: Bool { count != nil }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { opt in
                segment(for: opt)
            }
        }
        .padding(3)
        .background(Crucible.Color.wash1, in: RoundedRectangle(cornerRadius: 10))
        .fixedSize(horizontal: true, vertical: false)
    }

    private func segment(for opt: Option) -> some View {
        let selected = selection == opt
        let n = count?(opt)
        return Button {
            selection = opt
        } label: {
            HStack(spacing: 5) {
                Text(label(opt))
                    .font(.system(size: 13.5, weight: selected ? .bold : .medium))
                    .tracking(-0.1)
                    .foregroundStyle(selected ? Crucible.Color.accentInk : Crucible.Color.ink2)
                if let n, n > 0 {
                    Text("\(n)")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(selected ? Crucible.Color.accentInk.opacity(0.9) : Crucible.Color.ink3)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            selected ? Color.white.opacity(0.28) : Crucible.Color.sunk,
                            in: Capsule()
                        )
                }
            }
            .padding(.horizontal, showsCounts ? 13 : 20)
            .frame(minHeight: 32)
            .background(
                selected ? Crucible.Color.accent : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(n.map { "\(label(opt)), \($0)" } ?? label(opt))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
