import SwiftUI

/// Drag-to-reveal delete action for rows that live inside a
/// `LazyVStack` / `ScrollView` (where SwiftUI's native
/// `.swipeActions` modifier — which requires a `List` — isn't
/// available). The wrapped content stays interactive; the swipe
/// threshold is wide enough that it doesn't fight vertical scroll
/// or tap gestures on the row body.
///
/// Drag left → red delete button slides in from the right. Tap
/// delete → invokes `onDelete`. Tap anywhere else, or release
/// the drag below the reveal threshold → snaps back.
///
/// One swipe at a time across the rendered list — `id` lets the
/// container ensure only one row's reveal is open via the
/// optional `@Binding openedRowId` parameter.
struct SwipeToDelete<Content: View>: View {
    let id: AnyHashable
    @Binding var openedRowId: AnyHashable?
    /// Text shown under the icon on the revealed affordance.
    /// Defaults to `"Delete"` for the original clip-deletion use; the
    /// project memory-list path passes `"Remove"` since the memory
    /// itself isn't destroyed, just unlinked from the project.
    var label: String = "Delete"
    /// SF Symbol for the affordance icon. Defaults to `"trash"`.
    var systemImage: String = "trash"
    let onDelete: () -> Void
    let content: () -> Content

    @State private var dragOffset: CGFloat = 0

    /// Width of the revealed delete area. Visible only after the
    /// drag passes the snap threshold.
    private let revealWidth: CGFloat = 80
    /// Minimum drag before the reveal starts following the finger.
    /// Larger than SwiftUI's default tap-vs-drag threshold so the
    /// existing row tap behavior isn't captured by accident.
    private let dragMinDistance: CGFloat = 18
    /// Drag distance past which the reveal snaps open on release.
    private let snapOpenThreshold: CGFloat = 40

    private var isOpen: Bool { openedRowId == id }
    /// Resting offset for the row content: 0 closed, -revealWidth open.
    private var settledOffset: CGFloat { isOpen ? -revealWidth : 0 }
    /// Total visible offset including in-flight drag.
    private var visibleOffset: CGFloat {
        // Clamp left-only — dragging right past 0 doesn't reveal anything.
        let combined = settledOffset + dragOffset
        return min(0, max(combined, -revealWidth - 20))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete button revealed behind the row.
            deleteAffordance
            // Row content — slides over the delete affordance.
            content()
                .offset(x: visibleOffset)
                .gesture(swipeGesture)
                .simultaneousGesture(closeOnTapWhenOpen)
        }
        .clipped()
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: visibleOffset)
    }

    private var deleteAffordance: some View {
        Button(action: {
            onDelete()
            openedRowId = nil
        }) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(width: revealWidth)
            .frame(maxHeight: .infinity)
            .background(Crucible.Color.danger)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .opacity(visibleOffset < -4 ? 1.0 : 0)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: dragMinDistance)
            .onChanged { value in
                // Track horizontal drag only — vertical motion stays
                // free for the parent ScrollView.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if !isOpen {
                    // Closing → opening: left-only drag.
                    dragOffset = min(0, value.translation.width)
                } else {
                    // Already open: right drag closes; left drag is a no-op.
                    dragOffset = max(0, value.translation.width)
                }
            }
            .onEnded { value in
                let projected = settledOffset + dragOffset
                dragOffset = 0
                if !isOpen, projected <= -snapOpenThreshold {
                    openedRowId = id
                } else if isOpen, projected >= -revealWidth + snapOpenThreshold {
                    openedRowId = nil
                }
                // Else: snap back to current settled state.
            }
    }

    /// When the row is open, a tap anywhere on the row body closes
    /// the reveal (instead of firing the row's own tap action).
    /// Implemented as a simultaneousGesture so we don't swallow taps
    /// when the row is closed.
    private var closeOnTapWhenOpen: some Gesture {
        TapGesture().onEnded {
            if isOpen { openedRowId = nil }
        }
    }
}

extension View {
    /// Adds a left-swipe-to-delete affordance suitable for rows in a
    /// `LazyVStack` / `ScrollView`. `openedRowId` ensures at most one
    /// row's reveal is open at a time across the list — pass a
    /// shared `@State AnyHashable?` from the container.
    func swipeToDelete(
        id: some Hashable,
        openedRowId: Binding<AnyHashable?>,
        label: String = "Delete",
        systemImage: String = "trash",
        onDelete: @escaping () -> Void
    ) -> some View {
        SwipeToDelete(
            id: AnyHashable(id),
            openedRowId: openedRowId,
            label: label,
            systemImage: systemImage,
            onDelete: onDelete,
            content: { self }
        )
    }
}
