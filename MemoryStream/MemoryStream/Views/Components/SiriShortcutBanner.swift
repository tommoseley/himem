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

                Text("\"Capture in Hi Mem\"")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("Say this to Siri from your headphones or lock screen. Siri will ask what you want to remember, then save it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
            .padding()
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        }
    }
}
