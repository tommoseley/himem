import SwiftUI

/// **The waiting card** — `HiMem · Transient capture.html` (CURRENT).
///
/// Something arrived from the Watch and she has not decided what it is yet.
/// It appears at the top of Memories, **where she already is** — there is no
/// tab, no destination, nothing to visit.
///
/// > When nothing waits there is **no trace of the mechanism** — no empty
/// > section, no "nothing new."
///
/// That is enforced at the call site (the card is simply not built), and
/// `TransientCaptureSurfaceTests` guards it, because "the inbox does not
/// exist when it is empty" is the whole difference between this and the
/// bench we deleted.
struct TransientCaptureCard: View {
    let capture: TransientCapture
    /// "2 more after this" — scope for the errand she is starting. `nil` when
    /// this is the only one; see `TransientCaptureStack.moreAfterThis`.
    let moreAfterThis: String?
    let onAddToMemory: () -> Void
    let onStartNewMemory: () -> Void
    let onDiscard: () -> Void

    private var exits: [TransientCaptureStack.Exit] {
        TransientCaptureStack.exits(for: capture)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            body_
            actions
        }
        .padding(16)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "applewatch")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Crucible.Color.ink3)
            Text(capture.capturedAt, format: .dateTime.weekday(.wide).hour().minute())
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Crucible.Color.ink3)
            Spacer(minLength: 8)
            // The count rides on the thing she is already looking at. Never a
            // badge: a number that follows her is an obligation to zero out.
            if let moreAfterThis {
                Text(moreAfterThis)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Crucible.Color.ink3)
            }
        }
    }

    // MARK: - Body

    @ViewBuilder
    private var body_: some View {
        if capture.heardNothing {
            // Says so rather than showing an empty row. "From your Watch" is
            // reassurance: what she said reached the phone.
            Text(TransientCaptureStack.heardNothingText)
                .font(.system(size: 16, design: .serif))
                .italic()
                .foregroundStyle(Crucible.Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(capture.transcript)
                .font(.system(size: 17, design: .serif))
                .foregroundStyle(Crucible.Color.ink)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - The exits

    private var actions: some View {
        HStack(spacing: 10) {
            if exits.contains(.addToMemory) {
                Button(action: onAddToMemory) {
                    Text("Add to a memory")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Crucible.Color.accentInk)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(Crucible.Color.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Button(action: onStartNewMemory) {
                Text("Start a new memory")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Crucible.Color.accent)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .overlay(Capsule().stroke(Crucible.Color.accent, lineWidth: 1))
                    // The pill's interior is transparent, so without this it
                    // responds only where the glyphs are drawn. No background:
                    // that would change the rank the design system assigns.
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            // Quiet tertiary — never a peer of the two keeps.
            Button(action: onDiscard) {
                Text("Discard")
                    .font(.system(size: 14))
                    .foregroundStyle(Crucible.Color.ink3)
                    .frame(height: 40)
            }
            .buttonStyle(.plain)
        }
    }
}
