import SwiftUI
import UIKit

/// Universal "add" surface from the Append spec (v1). Tap the FAB → scrim
/// fades over the host content, the FAB rotates 45° to "×", and the action
/// pills rise from behind it. Picking a pill collapses the stack and emits
/// the chosen modality so the host can present its capture surface.
///
/// Used in both contexts: capture-new (JournalView) and append-to-memory
/// (EntryExpandedView). The host owns the capture flow and is responsible
/// for the resulting save.
///
/// Geometry, motion, and color values are pinned to the spec.
/// A non-capture action rendered as an extra pill at the top of the
/// `AppendFAB` stack. Used by the in-project FAB (F7) to surface the
/// "Add existing memory" path above the capture modalities — the stack's
/// two jobs read as one list: make a new memory here, or add one you
/// already have. `nil` (the default) means a pure capture stack.
struct AppendFABLeadingAction {
    let label: String
    let systemImage: String
    let onTap: () -> Void
}

struct AppendFAB: View {
    /// Fired when the user picks a pill. The host presents the appropriate
    /// capture surface for `modality`.
    let onSelect: (CaptureModality) -> Void
    /// Optional accessibility label override for the closed FAB. Default: "Add."
    var accessibilityLabel: String = "Add"
    /// Optional non-capture pill above the modality stack (F7 in-project
    /// "Add existing memory"). `nil` → capture-only stack, unchanged.
    var leadingAction: AppendFABLeadingAction? = nil

    @State private var isOpen = false
    @AppStorage("fabHandednessLeft") private var fabHandednessLeft = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var alignment: Alignment {
        FABHandedness.containerAlignment(leftHanded: fabHandednessLeft)
    }
    private var horizontalEdge: HorizontalAlignment {
        FABHandedness.horizontalEdge(leftHanded: fabHandednessLeft)
    }
    private var anchorPaddingEdge: Edge.Set {
        FABHandedness.paddingEdge(leftHanded: fabHandednessLeft)
    }

    var body: some View {
        ZStack(alignment: alignment) {
            // Scrim — tap to dismiss. Uses `.ultraThinMaterial` for the
            // dim-plus-blur effect: the host content sits clearly muted
            // behind a translucent layer while the FAB stack stays crisp
            // above. The scrim is the first ZStack child so the action
            // pills and FAB remain on top of the blur.
            if isOpen {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.75)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { close() }
                    .accessibilityHidden(true)
            }

            VStack(alignment: horizontalEdge, spacing: 0) {
                if isOpen {
                    actionStack
                        .padding(anchorPaddingEdge, 22)
                        .padding(.bottom, 8) // gap between stack and FAB
                }
                fab
                    .padding(anchorPaddingEdge, 22)
                    .padding(.bottom, 28)
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - FAB

    private var fab: some View {
        Button {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(isOpen ? Crucible.Color.accentPressed : Crucible.Color.accent)
                    .frame(width: 60, height: 60)
                    .shadow(color: Crucible.Color.accent.opacity(0.32), radius: 16, x: 0, y: 4)
                    .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(isOpen ? 45 : 0))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOpen ? "Cancel" : accessibilityLabel)
        .accessibilityAddTraits(isOpen ? [] : [])
        .accessibilityHint(isOpen ? "Closes the action stack." : "Opens the capture action stack.")
    }

    // MARK: - Action stack

    private var actionStack: some View {
        VStack(spacing: 8) {
            if let leadingAction {
                leadingActionPill(leadingAction)
            }
            ForEach(Array(CaptureModality.stackOrder.enumerated()), id: \.element.id) { index, modality in
                pill(for: modality, index: index)
            }
        }
        .frame(width: 188, alignment: .leading)
    }

    /// The non-capture "Add existing memory" pill (F7). Styled as a
    /// secondary pill (same height/weight as a non-primary modality) but
    /// with an ink glyph rather than a modality colour — it isn't a
    /// capture type. Sits at the top of the stack, furthest from the FAB.
    private func leadingActionPill(_ action: AppendFABLeadingAction) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            close()
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.08 : 0.14)) {
                action.onTap()
            }
        } label: {
            HStack(spacing: 0) {
                Text(action.label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink)
                    .padding(.leading, 18)
                Spacer(minLength: 8)
                ZStack {
                    Circle()
                        .fill(Crucible.Color.ink2.opacity(0.10))
                        .frame(width: 36, height: 36)
                    Image(systemName: action.systemImage)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Crucible.Color.ink2)
                }
                .padding(.trailing, 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Crucible.Color.card)
            .clipShape(Capsule())
            .shadow(
                color: Color(red: 40/255, green: 25/255, blue: 15/255).opacity(0.10),
                radius: 12, x: 0, y: 8
            )
            .shadow(color: .black.opacity(0.06), radius: 1, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.label)
        .accessibilityAddTraits(.isButton)
        .transition(
            reduceMotion
                ? .opacity
                : .asymmetric(
                    insertion: .modifier(
                        active: PillEnter(progress: 0),
                        identity: PillEnter(progress: 1)
                    ).animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.18)),
                    removal: .opacity.combined(with: .move(edge: .bottom))
                        .animation(.easeOut(duration: 0.12))
                )
        )
    }

    /// Pill enter timing (open): each pill animates 180ms with the spec's
    /// cubic-bezier easing, translating from +12pt Y + opacity 0 to settle.
    /// Voice (closest to FAB, last in array) leads at 0ms; others stagger 30ms.
    /// Reduced-motion path: pills fade in together over 100ms with no Y
    /// translate.
    private func pill(for modality: CaptureModality, index: Int) -> some View {
        let isPrimary = modality.isPrimary
        let height: CGFloat = isPrimary ? 64 : 52
        let labelFontSize: CGFloat = isPrimary ? 17 : 15
        let glyphChipSize: CGFloat = isPrimary ? 44 : 36
        // Voice (last) leads. Others stagger by distance from the FAB.
        let stackDepth = CaptureModality.stackOrder.count - 1 - index
        let staggerMs = reduceMotion ? 0 : Double(stackDepth) * 30

        return Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            close()
            // Brief delay so the user sees the collapse before the host
            // presents the capture surface.
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.08 : 0.14)) {
                onSelect(modality)
            }
        } label: {
            HStack(spacing: 0) {
                Text(modality.label)
                    .font(.system(size: labelFontSize, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink)
                    .padding(.leading, 18)
                Spacer(minLength: 8)
                ZStack {
                    Circle()
                        .fill(modality.color.opacity(0.10))
                        .frame(width: glyphChipSize, height: glyphChipSize)
                    Image(systemName: modality.sfSymbol)
                        .font(.system(size: isPrimary ? 22 : 18, weight: .regular))
                        .foregroundStyle(modality.color)
                }
                .padding(.trailing, isPrimary ? 8 : 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Crucible.Color.card)
            .overlay(
                Capsule()
                    .stroke(isPrimary ? Crucible.Color.accent.opacity(0.10) : .clear, lineWidth: 2)
            )
            .clipShape(Capsule())
            .shadow(
                color: Color(red: 40/255, green: 25/255, blue: 15/255).opacity(isPrimary ? 0.14 : 0.10),
                radius: isPrimary ? 16 : 12, x: 0, y: isPrimary ? 12 : 8
            )
            .shadow(color: .black.opacity(0.06), radius: 1, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(modality.label)
        .accessibilityAddTraits(.isButton)
        .transition(
            reduceMotion
                ? .opacity
                : .asymmetric(
                    insertion: .modifier(
                        active: PillEnter(progress: 0),
                        identity: PillEnter(progress: 1)
                    ).animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.18).delay(staggerMs / 1000)),
                    removal: .opacity.combined(with: .move(edge: .bottom))
                        .animation(.easeOut(duration: 0.12))
                )
        )
    }

    // MARK: - State transitions

    private func toggle() {
        if isOpen { close() } else { open() }
    }

    private func open() {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.10)) { isOpen = true }
        } else {
            // Scrim and FAB rotation on a fast spring; the staggered pill
            // entry rides the .transition modifier on each pill.
            withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) { isOpen = true }
        }
    }

    private func close() {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.08)) { isOpen = false }
        } else {
            withAnimation(.easeOut(duration: 0.14)) { isOpen = false }
        }
    }
}

/// Drives the pill enter motion: translates from +12pt Y + opacity 0 to
/// settled. Used by `.transition(.modifier(...))` so the staggered timing
/// can sit on each pill independently.
private struct PillEnter: ViewModifier, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .offset(y: (1 - progress) * 12)
    }
}
