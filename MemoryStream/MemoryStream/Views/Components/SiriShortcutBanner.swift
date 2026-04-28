import SwiftUI

struct SiriShortcutBanner: View {
    @AppStorage("siriBannerDismissed") private var isDismissed = false

    var body: some View {
        if !isDismissed {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label {
                        Text("SIRI SHORTCUT")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .tracking(0.5)
                    } icon: {
                        Image(systemName: "waveform.circle.fill")
                            .foregroundStyle(.purple)
                    }
                    .foregroundStyle(.secondary)

                    Spacer()

                    Text("Hands-free")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.purple.opacity(0.1))
                        .foregroundStyle(.purple)
                        .clipShape(Capsule())

                    Button {
                        withAnimation { isDismissed = true }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }

                Text("\"Tell Memory Stream that...\"")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("Say this to Siri followed by what you want to remember. It'll be saved and inferred automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
            .padding()
            .background(Crucible.Color.card)
            .clipShape(RoundedRectangle(cornerRadius: Crucible.Radius.xl))
            .modifier(WarmShadow(level: 1))
        }
    }
}
