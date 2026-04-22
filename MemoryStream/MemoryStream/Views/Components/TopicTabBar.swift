import SwiftUI

struct TopicTabBar: View {
    let topics: [String]
    @Binding var selected: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                TopicTab(label: "All", isSelected: selected == nil, hue: nil) {
                    selected = nil
                }

                ForEach(topics, id: \.self) { topic in
                    TopicTab(
                        label: topic,
                        isSelected: selected == topic,
                        hue: Crucible.Color.topicHue(for: topic)
                    ) {
                        selected = topic
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct TopicTab: View {
    let label: String
    let isSelected: Bool
    let hue: Crucible.Color.TopicHue?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(chipBackground)
                .foregroundStyle(chipForeground)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : Crucible.Color.divider, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private var chipBackground: Color {
        guard isSelected else { return .clear }
        if let hue { return hue.bg }
        return Crucible.Color.accentTint // "All" uses accent
    }

    private var chipForeground: Color {
        guard isSelected else { return Crucible.Color.ink }
        if let hue { return hue.fg }
        return Crucible.Color.accentPressed
    }
}
