import SwiftUI

/// Signal-based card for the projects list. Per the v1 spec and
/// `screens-projects-cards.jsx::ProjectCard`: title left, count
/// badge + last-activity date stacked on the right, topic dot+label
/// row beneath. **No purpose / goal line.** Goal lives on detail
/// only (italic serif, below the title); putting it on the card
/// crowded the row and mixed editorial type into a list surface.
struct ProjectCardView: View {
    let project: ProjectDisplayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text(project.name)
                    .font(.system(size: 18, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(Crucible.Color.ink)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(project.memoryCount)")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Crucible.Color.ink2)
                        .padding(.horizontal, 7)
                        .frame(minWidth: 24, minHeight: 22)
                        .background(Crucible.Color.sunk)
                        .clipShape(Capsule())
                    Text(project.updatedLabel)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(Crucible.Color.ink3)
                }
            }
            // Topic row — pip + label inline, no chip background.
            // Matches `ProjectCard` topics map exactly: 6×6 dot in
            // the topic's pip color + 12pt ink2 label, gap 6.
            if !project.topicNames.isEmpty {
                HStack(spacing: 6) {
                    ForEach(project.topicNames.prefix(4), id: \.self) { topic in
                        let hue = Crucible.Color.topicHue(for: topic)
                        HStack(spacing: 5) {
                            Circle().fill(hue.fg).frame(width: 6, height: 6)
                                .accessibilityHidden(true)
                            Text(topic)
                                .font(.system(size: 12))
                                .foregroundStyle(Crucible.Color.ink2)
                        }
                    }
                    if project.topicNames.count > 4 {
                        Text("+\(project.topicNames.count - 4)")
                            .font(.system(size: 12))
                            .foregroundStyle(Crucible.Color.ink3)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Crucible.Color.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
