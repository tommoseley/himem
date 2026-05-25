import SwiftUI

/// Two-tap session-discard modifier — drag-to-reveal a red button
/// whose label changes on first tap. Per the Captured Clips v2.1
/// spec: "Tap once expands the action to 'Discard N clips?'; second
/// tap commits." No confirmation dialog. No undo toast.
///
/// Distinct from `SwipeToDelete` (one-tap with separate confirm)
/// because the spec wants the confirm inline, in the revealed
/// affordance, not in a dialog. Same drag-and-snap mechanics; the
/// difference is the button's state machine.
///
/// Reveal closes automatically after the commit fires, or when the
/// user taps outside / drags the row back. Confirm state times out
/// after 5 seconds if the user pauses — keeps a hot destructive
/// button from waiting indefinitely.
struct SwipeToDiscard<Content: View>: View {
    let id: AnyHashable
    @Binding var openedRowId: AnyHashable?
    let clipCount: Int
    let onCommit: () -> Void
    let content: () -> Content

    @State private var dragOffset: CGFloat = 0
    @State private var confirming: Bool = false
    @State private var confirmTimeoutTask: Task<Void, Never>? = nil

    /// Width of the revealed button in default state ("Discard").
    /// Grows to `revealWidthConfirm` once the user taps once.
    private let revealWidthDefault: CGFloat = 92
    private let revealWidthConfirm: CGFloat = 158
    private let dragMinDistance: CGFloat = 18
    private let snapOpenThreshold: CGFloat = 40

    private var isOpen: Bool { openedRowId == id }

    private var revealWidth: CGFloat {
        confirming ? revealWidthConfirm : revealWidthDefault
    }

    private var settledOffset: CGFloat {
        isOpen ? -revealWidth : 0
    }

    private var visibleOffset: CGFloat {
        let combined = settledOffset + dragOffset
        return min(0, max(combined, -revealWidth - 20))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            discardAffordance
            content()
                .offset(x: visibleOffset)
                .gesture(swipeGesture)
                .simultaneousGesture(closeOnTapWhenOpen)
        }
        .clipped()
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: visibleOffset)
        .animation(.easeOut(duration: 0.18), value: confirming)
        .onChange(of: isOpen) { _, nowOpen in
            // Closing the reveal also clears the confirm state and
            // cancels any pending timeout. Re-opening always starts
            // fresh in the default ("Discard") state.
            if !nowOpen {
                confirming = false
                confirmTimeoutTask?.cancel()
                confirmTimeoutTask = nil
            }
        }
    }

    private var discardAffordance: some View {
        Button {
            if confirming {
                onCommit()
                openedRowId = nil
            } else {
                confirming = true
                scheduleConfirmTimeout()
            }
        } label: {
            Text(confirming ? "Discard \(clipCount) clip\(clipCount == 1 ? "" : "s")?" : "Discard")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: revealWidth)
                .frame(maxHeight: .infinity)
                .background(Crucible.Color.danger)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(confirming ? "Confirm discard \(clipCount) clips" : "Discard session")
        .opacity(visibleOffset < -4 ? 1.0 : 0)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: dragMinDistance)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if !isOpen {
                    dragOffset = min(0, value.translation.width)
                } else {
                    dragOffset = max(0, value.translation.width)
                }
            }
            .onEnded { _ in
                let projected = settledOffset + dragOffset
                dragOffset = 0
                if !isOpen, projected <= -snapOpenThreshold {
                    openedRowId = id
                } else if isOpen, projected >= -revealWidth + snapOpenThreshold {
                    openedRowId = nil
                }
            }
    }

    /// When the row is open, a tap on the row body closes it.
    /// Implemented as `simultaneousGesture` so taps don't get
    /// swallowed when the row is closed.
    private var closeOnTapWhenOpen: some Gesture {
        TapGesture().onEnded {
            if isOpen { openedRowId = nil }
        }
    }

    /// Hot confirm-state timeout — after 5 seconds with no second
    /// tap, the button reverts to "Discard" so a forgotten reveal
    /// doesn't sit hot indefinitely.
    private func scheduleConfirmTimeout() {
        confirmTimeoutTask?.cancel()
        confirmTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            // Re-check that the task wasn't cancelled and that we're
            // still in the confirm state — otherwise this is a stale
            // timeout from a previous reveal.
            if !Task.isCancelled, confirming {
                confirming = false
            }
        }
    }
}

extension View {
    /// Adds a left-swipe-to-discard with a two-tap inline commit.
    /// Spec: Captured Clips · session-first · v2.1 (Discarding
    /// sessions). Used on session cards in `SessionListView`.
    /// `clipCount` drives the confirm-state label "Discard N clips?".
    func swipeToDiscard(
        id: some Hashable,
        openedRowId: Binding<AnyHashable?>,
        clipCount: Int,
        onCommit: @escaping () -> Void
    ) -> some View {
        SwipeToDiscard(
            id: AnyHashable(id),
            openedRowId: openedRowId,
            clipCount: clipCount,
            onCommit: onCommit,
            content: { self }
        )
    }
}
