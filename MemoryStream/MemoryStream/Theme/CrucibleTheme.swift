import SwiftUI

/// Crucible design system tokens.
/// Apple-native base · warm editorial serif moments · Swiss precision in layout.
/// iOS is the source of truth. Values are opinionated and fixed.
enum Crucible {

    // MARK: - Color

    enum Color {
        // Neutrals (light)
        static let paper    = SwiftUI.Color(hex: 0xF7F5F0)   // canvas — warm, not blue-white
        static let card     = SwiftUI.Color.white             // raised surface
        static let sunk     = SwiftUI.Color(hex: 0xEFECE5)   // inset / inactive
        static let hairline = SwiftUI.Color(red: 25/255, green: 20/255, blue: 15/255).opacity(0.08)
        static let divider  = SwiftUI.Color(red: 25/255, green: 20/255, blue: 15/255).opacity(0.12)
        static let ink      = SwiftUI.Color(hex: 0x1A1612)    // primary text (warm near-black)
        static let ink2     = SwiftUI.Color(hex: 0x1A1612).opacity(0.64) // secondary
        static let ink3     = SwiftUI.Color(hex: 0x1A1612).opacity(0.42) // tertiary
        static let ink4     = SwiftUI.Color(hex: 0x1A1612).opacity(0.22) // disabled

        // Accent — warm ember
        static let accent       = SwiftUI.Color(hex: 0xC64A1C)
        static let accentPressed = SwiftUI.Color(hex: 0xA53A13)
        static let accentTint   = SwiftUI.Color(hex: 0xFBEAE0)

        // Capture colors — semantic, used across FAB, cards, filters
        static let captureAudio = SwiftUI.Color(hex: 0xE8893A) // ochre
        static let captureText  = SwiftUI.Color(hex: 0x3FA877) // field green
        static let capturePhoto = SwiftUI.Color(hex: 0x2E7BD6) // signal blue
        static let captureVideo = SwiftUI.Color(hex: 0xA935B8) // memory magenta

        // Semantic
        static let success = SwiftUI.Color(hex: 0x2F7D4F)
        static let warning = SwiftUI.Color(hex: 0xB87322)
        static let danger  = SwiftUI.Color(hex: 0xB8311E)
        static let info    = SwiftUI.Color(hex: 0x1E5C8E)

        // Status — entry lifecycle chips (specific bg/fg pairs)
        enum Status {
            static let editedBg    = SwiftUI.Color(hex: 0xE6EEF8)
            static let editedFg    = SwiftUI.Color(hex: 0x1E5C8E)
            static let processedBg = SwiftUI.Color(hex: 0xDDEBE3)
            static let processedFg = SwiftUI.Color(hex: 0x2F7D4F)
            static let confirmedBg = SwiftUI.Color(hex: 0xDDEBE3)
            static let confirmedFg = SwiftUI.Color(hex: 0x2F7D4F)
            static let draftBg     = SwiftUI.Color(hex: 0xEEE9E0)
            static let draftFg     = SwiftUI.Color(hex: 0x1A1612).opacity(0.64)
            static let failedBg    = SwiftUI.Color(hex: 0xF6E1DD)
            static let failedFg    = SwiftUI.Color(hex: 0xB8311E)
            static let inferringBg = SwiftUI.Color(hex: 0xE6EEF8)
            static let inferringFg = SwiftUI.Color(hex: 0x1E5C8E)
        }

        // AI — everything the model does wears this blue.
        // Distinct from ember (user intent) and status.info (passive).
        enum AI {
            static let base   = SwiftUI.Color(hex: 0x1E5C8E)
            static let strong = SwiftUI.Color(hex: 0x144674)
            static let tint   = SwiftUI.Color(hex: 0xE6EEF8)
        }

        // Topic palette — finite pool of hues users pick from when creating a Topic.
        // Topics are user data, NEVER hard-coded. We only define the pool.
        struct TopicHue {
            let key: String
            let bg: SwiftUI.Color
            let fg: SwiftUI.Color
        }

        static let topicPalette: [TopicHue] = [
            // Row 1 · warms
            TopicHue(key: "ember",      bg: SwiftUI.Color(hex: 0xFBEAE0), fg: SwiftUI.Color(hex: 0xA53A13)),
            TopicHue(key: "terracotta", bg: SwiftUI.Color(hex: 0xF4DED0), fg: SwiftUI.Color(hex: 0x8A4724)),
            TopicHue(key: "clay",       bg: SwiftUI.Color(hex: 0xEFDDD0), fg: SwiftUI.Color(hex: 0x7A3A1C)),
            TopicHue(key: "amber",      bg: SwiftUI.Color(hex: 0xF3E4C3), fg: SwiftUI.Color(hex: 0x8A5A0E)),
            // Row 2 · yellows & greens
            TopicHue(key: "wheat",      bg: SwiftUI.Color(hex: 0xEFE6CF), fg: SwiftUI.Color(hex: 0x7A5A10)),
            TopicHue(key: "sage",       bg: SwiftUI.Color(hex: 0xDFE7D9), fg: SwiftUI.Color(hex: 0x4A6A3A)),
            TopicHue(key: "moss",       bg: SwiftUI.Color(hex: 0xE0EADB), fg: SwiftUI.Color(hex: 0x3E6A2A)),
            TopicHue(key: "pine",       bg: SwiftUI.Color(hex: 0xD6E0D3), fg: SwiftUI.Color(hex: 0x284A1F)),
            // Row 3 · blues
            TopicHue(key: "sea",        bg: SwiftUI.Color(hex: 0xD6E5E3), fg: SwiftUI.Color(hex: 0x1F5C56)),
            TopicHue(key: "tide",       bg: SwiftUI.Color(hex: 0xDCE7EE), fg: SwiftUI.Color(hex: 0x255A7A)),
            TopicHue(key: "indigo",     bg: SwiftUI.Color(hex: 0xDCDFEE), fg: SwiftUI.Color(hex: 0x2E3E7C)),
            TopicHue(key: "violet",     bg: SwiftUI.Color(hex: 0xE0DAEC), fg: SwiftUI.Color(hex: 0x4A3577)),
            // Row 4 · purples, roses, neutrals
            TopicHue(key: "plum",       bg: SwiftUI.Color(hex: 0xEADDE8), fg: SwiftUI.Color(hex: 0x6B3567)),
            TopicHue(key: "rose",       bg: SwiftUI.Color(hex: 0xF1DDDD), fg: SwiftUI.Color(hex: 0x8A3A3A)),
            TopicHue(key: "sand",       bg: SwiftUI.Color(hex: 0xE6E0D6), fg: SwiftUI.Color(hex: 0x5A4A30)),
            TopicHue(key: "slate",      bg: SwiftUI.Color(hex: 0xDFE1E6), fg: SwiftUI.Color(hex: 0x3B4452)),
        ]

        /// Returns the hue for a topic. Uses the stored paletteKey if one exists,
        /// otherwise falls back to a deterministic hash of the name.
        static func topicHue(for name: String) -> TopicHue {
            if let key = TopicPaletteStore.shared.key(for: name),
               let hue = topicPalette.first(where: { $0.key == key }) {
                return hue
            }
            let index = abs(name.hashValue) % topicPalette.count
            return topicPalette[index]
        }

        /// Look up a hue by its palette key directly.
        static func topicHue(forKey key: String) -> TopicHue {
            topicPalette.first { $0.key == key } ?? topicPalette[0]
        }

        // Scrim
        static let scrim = SwiftUI.Color(red: 20/255, green: 18/255, blue: 15/255).opacity(0.36)
    }

    // MARK: - Radius

    enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 22    // default card radius on iOS
        static let pill: CGFloat = 9999
    }

    // MARK: - Elevation (warm orange-tinted shadows)

    static func shadow1() -> some ViewModifier { WarmShadow(level: 1) }
    static func shadow2() -> some ViewModifier { WarmShadow(level: 2) }

    // MARK: - Space (4pt grid)

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }
}

// MARK: - Warm Shadow Modifier

struct WarmShadow: ViewModifier {
    let level: Int
    private let shadowColor = SwiftUI.Color(red: 40/255, green: 25/255, blue: 15/255)

    func body(content: Content) -> some View {
        switch level {
        case 1:
            content
                .shadow(color: shadowColor.opacity(0.06), radius: 1.5, y: 1)
                .shadow(color: shadowColor.opacity(0.04), radius: 3, y: 1)
        case 2:
            content
                .shadow(color: shadowColor.opacity(0.08), radius: 6, y: 2)
                .shadow(color: shadowColor.opacity(0.06), radius: 18, y: 6)
        default:
            content
        }
    }
}

// MARK: - Topic Palette Store

/// In-memory cache of topic name → paletteKey, loaded from Core Data on app start.
/// Views read this via Crucible.Color.topicHue(for:) without any plumbing.
final class TopicPaletteStore {
    static let shared = TopicPaletteStore()
    private var map: [String: String] = [:]

    func key(for topicName: String) -> String? { map[topicName] }

    func set(key: String, for topicName: String) {
        map[topicName] = key
    }

    func remove(for topicName: String) {
        map.removeValue(forKey: topicName)
    }

    func loadFromCoreData() {
        let request = NSFetchRequest<Topic>(entityName: "Topic")
        guard let topics = try? StorageService.shared.viewContext.fetch(request) else { return }
        for topic in topics {
            if let pk = topic.paletteKey {
                map[topic.name] = pk
            }
        }
    }
}

// MARK: - Topic Color Picker

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

// MARK: - Topic Editor Sheet

/// Edit an existing topic: rename, change color, or delete.
struct TopicEditorSheet: View {
    let topic: Topic
    let onSave: (String, String) -> Void   // newName, newPaletteKey
    let onDelete: () -> Void

    @State private var name: String = ""
    @State private var colorKey: String = ""
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                TextField("Topic name", text: $name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                    let hue = Crucible.Color.topicHue(forKey: colorKey)
                    Text(name.trimmingCharacters(in: .whitespaces))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(hue.bg)
                        .foregroundStyle(hue.fg)
                        .clipShape(Capsule())
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("COLOR")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .tracking(0.5)
                        .foregroundStyle(Crucible.Color.ink3)

                    TopicColorPicker(selectedKey: $colorKey)
                }

                Spacer()

                VStack(spacing: 4) {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Text("Delete Topic")
                            .font(.footnote)
                            .fontWeight(.semibold)
                    }
                    Text("\(topic.entryCount) entries will keep their text but lose this topic.")
                        .font(.caption)
                        .foregroundStyle(Crucible.Color.ink3)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 8)
            }
            .padding(24)
            .navigationTitle("Edit Topic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed, colorKey)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasChanges || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Delete Topic?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(topic.entryCount) entries will keep their text but lose the \"\(topic.name)\" topic assignment.")
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            name = topic.name
            colorKey = topic.paletteKey ?? Crucible.Color.topicHue(for: topic.name).key
        }
    }

    private var hasChanges: Bool {
        let currentKey = topic.paletteKey ?? Crucible.Color.topicHue(for: topic.name).key
        return name.trimmingCharacters(in: .whitespaces) != topic.name || colorKey != currentKey
    }
}

import CoreData

// MARK: - Color hex initializer

extension SwiftUI.Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
