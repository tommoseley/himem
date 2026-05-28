import SwiftUI

/// Reusable view showing the 16 palette hues as tappable circles.
/// Selection is a ring (not a check) — ring = selected, check = completed.
struct TopicColorPicker: View {
    @Binding var selectedKey: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(Crucible.Color.topicPalette, id: \.key) { hue in
                Button {
                    selectedKey = hue.key
                } label: {
                    ZStack {
                        Circle()
                            .fill(hue.bg)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .stroke(hue.fg.opacity(0.13), lineWidth: 1)
                            )
                        if selectedKey == hue.key {
                            Circle()
                                .stroke(hue.fg, lineWidth: 2)
                                .frame(width: 50, height: 50)
                        }
                    }
                    .frame(width: 50, height: 50)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
