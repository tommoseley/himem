import SwiftUI

/// Signal-based card for the project list. NOT an entry card.
/// Shows: name, purpose, memory count, topic dots, last updated.
struct ProjectCardView: View {
    let project: ProjectDisplayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Name + count
            HStack {
                Text(project.name)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(Crucible.Color.ink)
                Spacer()
                Text("\(project.memoryCount)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Crucible.Color.ink3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Crucible.Color.sunk)
                    .clipShape(Capsule())
            }

            // Purpose line
            if let purpose = project.purpose, !purpose.isEmpty {
                Text(purpose)
                    .font(.subheadline)
                    .foregroundStyle(Crucible.Color.ink2)
                    .lineLimit(2)
            }

            // Topic dots + updated
            HStack(spacing: 6) {
                ForEach(project.topicNames.prefix(4), id: \.self) { topic in
                    let hue = Crucible.Color.topicHue(for: topic)
                    HStack(spacing: 3) {
                        Circle().fill(hue.fg).frame(width: 6, height: 6)
                        Text(topic)
                            .font(.caption2)
                            .foregroundStyle(hue.fg)
                    }
                }
                if project.topicNames.count > 4 {
                    Text("+\(project.topicNames.count - 4)")
                        .font(.caption2)
                        .foregroundStyle(Crucible.Color.ink3)
                }
                Spacer()
                Text(project.updatedLabel)
                    .font(.caption2)
                    .foregroundStyle(Crucible.Color.ink4)
            }
        }
        .padding(14)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: Crucible.Radius.xl))
        .modifier(WarmShadow(level: 1))
    }
}
