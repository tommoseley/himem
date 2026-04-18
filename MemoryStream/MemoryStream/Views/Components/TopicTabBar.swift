import SwiftUI

struct TopicTabBar: View {
    let topics: [String]
    @Binding var selected: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                TopicTab(label: "All", isSelected: selected == nil) {
                    selected = nil
                }

                ForEach(topics, id: \.self) { topic in
                    TopicTab(label: topic, isSelected: selected == topic) {
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.blue.opacity(0.12) : Color.clear)
                .foregroundStyle(isSelected ? .blue : .primary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : Color(.separator), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    TopicTabBar(topics: ["Garden", "Combine", "Astro"], selected: .constant(nil))
        .padding()
}
