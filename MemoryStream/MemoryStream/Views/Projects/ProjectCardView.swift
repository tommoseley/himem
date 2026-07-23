import SwiftUI

/// Signal-based card for the projects list. Per the v1 spec and
/// `screens-projects-cards.jsx::ProjectCard`: title left, count
/// badge + last-activity date stacked on the right, topic dot+label
/// row beneath. The **goal line** sits beneath the title (2026-07-17,
/// Tom — reverses the earlier "detail only" call): a project is
/// *intent*, and the goal is the intent, so it earns a place on the
/// card. Reuses the goal's app-wide identity — 13pt italic serif, ink2
/// (matching `ProjectTitleBlock`) — via `.system(design: .serif)`
/// (New York), never a bundled font.
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
            // Card subtitle — the short thread summary once Find-the-thread
            // has run (the AI's one-line read of what the project became),
            // falling back to the goal (the user's intent) when there's no
            // thread yet: 0 memories or never run. Same italic-serif card
            // identity for both; two-line cap. The goal itself still lives —
            // and stays editable — in the detail header.
            if let subtitle = project.cardSubtitle {
                Text(subtitle)
                    .font(.system(size: 13, design: .serif))
                    .italic()
                    .foregroundStyle(Crucible.Color.ink2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
