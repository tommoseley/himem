import SwiftUI

/// Horizontally-scrolling topic filter bar shown at the top of the
/// Memories list. After the June 8 affordance lock + H1/H2 answers,
/// renders through the canonical `TopicChip` with two locked rules:
///
/// - **Compact size** — memory cards' density rhythm benefits from
///   28pt body + ≥10pt row gap rather than the strict 44pt body.
/// - **`All` pill is dotless** (H2) — `All` is a scope selector, not
///   a palette topic; a leading dot would falsely imply it's a
///   colored topic like the rest.
///
/// Selected = `.set` (wash1 fill, palette-colored dot). Unselected =
/// `.off` (hairline outline, palette-colored dot). The dot stays
/// visible in both states so the user can identify the topic at a
/// glance regardless of selection.
struct TopicTabBar: View {
    let topics: [String]
    @Binding var selected: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                TopicChip(
                    label: "All",
                    state: selected == nil ? .set : .off,
                    size: .compact,
                    showsLeadingDot: false,
                    onTap: { selected = nil }
                )

                ForEach(topics, id: \.self) { topic in
                    let hue = Crucible.Color.topicHue(for: topic)
                    TopicChip(
                        label: topic,
                        state: selected == topic ? .set : .off,
                        size: .compact,
                        dotColor: hue.fg,
                        onTap: { selected = topic }
                    )
                }
            }
            .padding(.horizontal)
        }
    }
}
