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
