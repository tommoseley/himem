import SwiftUI

/// Phase-state pill for the sync surface (spec § SYNC / INCOMING in
/// `screens-captured-clips-sessions.jsx`). Renders the same role on
/// an `IncomingCard` that "Make a Memory" plays on a ready
/// `SessionCard` — the at-a-glance signal for what the card is doing.
///
/// Status is never color alone (Crucible accessibility rule): each
/// case carries its own glyph + label. Pulsing cases are the ones
/// actively progressing — receiving and transcribing — so the user
/// can distinguish in-flight work from waiting or paused.
///
/// Phase 2 (this commit) covers only `.transcribing`; the other
/// cases are stubbed out behind a switch that future commits flesh
/// out without changing this file's public API.
struct PhasePill: View {
    let phase: InboxArrivalTracker.Phase

    var body: some View {
        HStack(spacing: 5) {
            icon
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.3)
        }
        .textCase(.uppercase)
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .clipShape(Capsule())
        .modifier(PulseModifier(active: pulsing))
    }

    private var label: String {
        switch phase {
        case .transcribing: return "Transcribing"
        }
    }

    private var foregroundColor: Color {
        switch phase {
        case .transcribing: return Crucible.Color.ink2
        }
    }

    private var backgroundColor: Color {
        switch phase {
        case .transcribing: return Crucible.Color.sunk
        }
    }

    private var pulsing: Bool {
        switch phase {
        case .transcribing: return true
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch phase {
        case .transcribing:
            // Three horizontal text lines — "reading the audio."
            // Spec mock used a custom SVG; SF Symbol equivalent.
            Image(systemName: "text.alignleft")
        }
    }
}

/// Repeating ease-in-out opacity pulse for in-progress phase pills.
/// Matches the spec's 1.6 s `ccPulse` keyframes. Off (active=false)
/// renders the pill at full opacity with no animation cost.
private struct PulseModifier: ViewModifier {
    let active: Bool
    @State private var dim: Bool = false

    func body(content: Content) -> some View {
        content
            .opacity(active && dim ? 0.3 : 1.0)
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    dim = true
                }
            }
    }
}
