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
            TopicHue(key: "ember", bg: SwiftUI.Color(hex: 0xFBEAE0), fg: SwiftUI.Color(hex: 0xA53A13)),
            TopicHue(key: "moss",  bg: SwiftUI.Color(hex: 0xE0EADB), fg: SwiftUI.Color(hex: 0x3E6A2A)),
            TopicHue(key: "tide",  bg: SwiftUI.Color(hex: 0xDCE7EE), fg: SwiftUI.Color(hex: 0x255A7A)),
            TopicHue(key: "plum",  bg: SwiftUI.Color(hex: 0xEADDE8), fg: SwiftUI.Color(hex: 0x6B3567)),
            TopicHue(key: "wheat", bg: SwiftUI.Color(hex: 0xEFE6CF), fg: SwiftUI.Color(hex: 0x7A5A10)),
            TopicHue(key: "clay",  bg: SwiftUI.Color(hex: 0xEFDDD0), fg: SwiftUI.Color(hex: 0x8A4724)),
            TopicHue(key: "slate", bg: SwiftUI.Color(hex: 0xDFE1E6), fg: SwiftUI.Color(hex: 0x3B4452)),
            TopicHue(key: "rose",  bg: SwiftUI.Color(hex: 0xF1DDDD), fg: SwiftUI.Color(hex: 0x8A3A3A)),
        ]

        /// Deterministic hue for a topic name — hashes the name into the palette.
        static func topicHue(for name: String) -> TopicHue {
            let index = abs(name.hashValue) % topicPalette.count
            return topicPalette[index]
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
