import SwiftUI

/// Animated horizontal placeholder — the skeleton for incoming
/// transcript content. Spec § SYNC / INCOMING uses three of these
/// stacked at decreasing widths (96% / 100% / 64%) inside the
/// transcribing `IncomingCard` body so the shape looks like real
/// text that hasn't arrived yet.
///
/// The 1.3 s linear shimmer matches the spec's `ccShimmer`
/// keyframes. The gradient travels left→right across a base sunk
/// fill, mimicking the cream-on-warm pulse of the Crucible palette.
struct ShimmerLine: View {
    /// Fraction of the parent width this line occupies. The spec
    /// uses 0.96 / 1.0 / 0.64 to fake the last-line indent of
    /// real text.
    let widthFraction: CGFloat

    @State private var offsetPhase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            let lineWidth = geo.size.width * widthFraction
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Crucible.Color.sunk)
                    .frame(width: lineWidth, height: 9)
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        LinearGradient(
                            colors: [
                                Crucible.Color.sunk,
                                Crucible.Color.ink.opacity(0.10),
                                Crucible.Color.sunk
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 110, height: 9)
                    .offset(x: offsetPhase * (lineWidth + 110))
                    .mask(
                        RoundedRectangle(cornerRadius: 5)
                            .frame(width: lineWidth, height: 9)
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 9)
        .onAppear {
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                offsetPhase = 1
            }
        }
    }
}
