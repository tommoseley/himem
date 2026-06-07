import SwiftUI

/// Shared template for "edit the words attached to a media item." The
/// voice clip's transcript editor and the photo / video description
/// editor do the same job and share this chrome: sheet presentation,
/// grabber, Cancel · title · Done top bar, metadata line, ochre-ring
/// field, one-line footer slot. The hero block and the footer line
/// are the only content-driven differences — voice gets a player,
/// photo gets a thumbnail; voice's footer is *Retry transcription*,
/// photo's is *Part of this memory · searchable*. Per
/// `docs/design/HiMem · Edit Sheet.html` (June 2026).
struct EditTextSheet<Hero: View, Footer: View>: View {
    let title: String
    let metadata: String
    let fieldLabel: String
    @Binding var text: String
    let onCancel: () -> Void
    let onDone: () -> Void
    @ViewBuilder var hero: Hero
    @ViewBuilder var footer: Footer

    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            grabber
            topBar
            content
        }
        .background(Crucible.Color.paper.ignoresSafeArea())
        .onAppear {
            // Tiny delay so the sheet's present animation finishes
            // before the keyboard rises — without it the keyboard
            // races the sheet and pops up under a mid-animation
            // surface, which lands jittery.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                fieldFocused = true
            }
        }
    }

    // MARK: - Top chrome

    private var grabber: some View {
        Capsule()
            .fill(Crucible.Color.ink4.opacity(0.5))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity)
    }

    private var topBar: some View {
        HStack {
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 15))
                    .foregroundStyle(Crucible.Color.ink2)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 56, alignment: .leading)
            Spacer()
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink)
                .lineLimit(1)
            Spacer()
            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Crucible.Color.accent)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 56, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    // MARK: - Body

    /// Content area: hero, metadata line, field eyebrow, editor (flex),
    /// footer (fixed). The editor's `maxHeight: .infinity` is critical
    /// — it constrains the TextEditor to whatever vertical space the
    /// sheet's content area has after the keyboard takes its bite, so
    /// the editor scrolls internally instead of extending under the
    /// keyboard.
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            Text(metadata)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Crucible.Color.ink3)
                .monospacedDigit()
                .padding(.top, 14)
                .padding(.bottom, 12)
            Text(fieldLabel.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Crucible.Color.ink3)
                .padding(.bottom, 8)
            TextEditor(text: $text)
                .focused($fieldFocused)
                .font(.system(size: 15))
                .foregroundStyle(Crucible.Color.ink)
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
                .background(Crucible.Color.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Crucible.Color.accent, lineWidth: 2)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
                .padding(.top, 12)
                .padding(.bottom, 14)
        }
        .padding(.horizontal, 18)
    }
}
