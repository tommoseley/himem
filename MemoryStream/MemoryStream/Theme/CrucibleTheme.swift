import SwiftUI
import CoreData

/// User-facing appearance preference. Persisted via `@AppStorage`
/// under key `"appearance"`. Default is `.system` so iOS Settings
/// drives the choice — the user's deliberate override (Light or
/// Dark) wins when set.
///
/// Watch is dark-native and ignores this setting (per spec footer:
/// "The watch is always dark — capture happens in any light").
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    /// Maps to SwiftUI's `ColorScheme?` for use with
    /// `.preferredColorScheme(_:)`. `nil` means "follow system."
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var detail: String {
        switch self {
        case .system: return "Match iOS · light by day, dark by night"
        case .light:  return "Cream paper, warm ink"
        case .dark:   return "Warm near-black, cream type"
        }
    }

    /// SF Symbol name for the row glyph.
    var systemImage: String {
        switch self {
        case .system: return "circle.righthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon.fill"
        }
    }
}

/// Crucible design system tokens.
/// Apple-native base · warm editorial serif moments · Swiss precision in layout.
/// iOS is the source of truth. Values are opinionated and fixed.
enum Crucible {

    // MARK: - Color

    enum Color {
        // All spec-aligned tokens are sourced from the Crucible color
        // catalog (`Assets.xcassets/Crucible/*.colorset`). Each entry
        // has both Any-Appearance and Dark-Appearance values pulled
        // from `docs/design/crucible.css` byte-for-byte. Switching to
        // catalog-backed colors makes dark-mode wiring (Phase 4)
        // declarative — no per-call branching on color scheme.
        //
        // Tokens not in the spec (modality colors, status pairs, AI
        // namespace) stay as inline literals below. Topic palette
        // stays inline too for now — Phase 2 will fold it into the
        // catalog alongside the slug-hash alignment.

        // Surfaces
        static let paper    = SwiftUI.Color("paper")
        static let card     = SwiftUI.Color("card")
        static let sunk     = SwiftUI.Color("sunk")
        // Type & lines
        static let ink      = SwiftUI.Color("ink")
        static let ink2     = SwiftUI.Color("ink2")
        static let ink3     = SwiftUI.Color("ink3")
        static let ink4     = SwiftUI.Color("ink4")
        static let hairline = SwiftUI.Color("hairline")
        static let divider  = SwiftUI.Color("divider")

        // Accent — warm ember (brand action color)
        static let accent        = SwiftUI.Color("accent")
        static let accentPressed = SwiftUI.Color("accent-press")
        static let accentTint    = SwiftUI.Color("accent-tint")
        static let accentTint2   = SwiftUI.Color("accent-tint-2")
        /// Brightened ochre used for the countdown ring's bright stroke
        /// — needs higher saturation than the brand accent to read on
        /// the black countdown surface.
        static let accentBright  = SwiftUI.Color("accent-bright")
        /// Deeper ochre used as the countdown ring's "dim" overlay
        /// sweeping over the bright base.
        static let accentDim     = SwiftUI.Color("accent-dim")
        /// Foreground color for content sitting on top of solid
        /// `accent` (e.g. cream label on an ochre pill). Flips dark
        /// in dark mode so a solid `ink` button still reads.
        static let accentInk     = SwiftUI.Color("accent-ink")

        // Capture colors — semantic, used across FAB, cards, filters
        // Modality tokens — Append spec v1. Each value also dots the
        // entry-head in the detail timeline so the modality reads at a glance.
        static let captureAudio  = SwiftUI.Color(hex: 0xC64A1C) // voice ochre (= accent)
        static let captureText   = SwiftUI.Color(hex: 0x1F8FB3) // note teal
        static let capturePhoto  = SwiftUI.Color(hex: 0x2F9E6B) // photo green
        static let captureVideo  = SwiftUI.Color(hex: 0xB8328F) // video magenta
        static let captureAttach = SwiftUI.Color(hex: 0x5B6BF5) // attach indigo

        // Semantic — sourced from catalog (each has a dark variant).
        // `success`/`warning`/`info` map to the spec's
        // confirmed/warn/ai tokens; keep the legacy names so callers
        // don't churn, but they share storage with the spec tokens.
        static let confirmed     = SwiftUI.Color("confirmed")
        static let confirmedTint = SwiftUI.Color("confirmed-tint")
        static let confirmedInk  = SwiftUI.Color("confirmed-ink")
        static let warn          = SwiftUI.Color("warn")
        static let warnTint      = SwiftUI.Color("warn-tint")
        static let warnInk       = SwiftUI.Color("warn-ink")
        static let danger        = SwiftUI.Color("danger")
        // Legacy aliases — keep existing call sites compiling. New
        // code should prefer the spec names.
        static let success = confirmed
        static let warning = warn
        static let info    = SwiftUI.Color("ai")

        // AI attribution — Crucible reserves this blue for every
        // AI-generated/owned surface (Project Assist, AI Summary
        // eyebrow, "App is inferring" block, ✦ sparkle glyph,
        // confidence chips, suggested-memory rationale).
        static let aiBlue      = SwiftUI.Color("ai")
        static let aiBlueTint  = SwiftUI.Color("ai-tint")
        static let aiEdge      = SwiftUI.Color("ai-edge")

        // Focus, scrim, washes, highlight — also catalog-backed.
        static let focus       = SwiftUI.Color("focus")
        // Ink washes — faint surface tints over paper, lighter than
        // hairline. Use for chip backgrounds, segmented-control pills.
        static let wash1       = SwiftUI.Color("wash-1")
        static let wash2       = SwiftUI.Color("wash-2")
        /// Yellow wash for search hits, tuned to read on both modes.
        static let highlight   = SwiftUI.Color("highlight")

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
            // AI inference attribution — Crucible reserves blue for
            // AI moments. The amber/ochre forms `0xF3E4C3` / `0x8A5A0E`
            // were the source of the ochre AI bug; both moved to AI
            // blue 2026-05-19 as part of the Projects MVP sweep.
            static let inferringBg = SwiftUI.Color(hex: 0xE6EEF8)
            static let inferringFg = SwiftUI.Color(hex: 0x1E5C8E)
            static let capturedBg  = SwiftUI.Color(hex: 0xEFE6D4)
            static let capturedFg  = SwiftUI.Color(hex: 0x7A5A10)
        }

        // Media type dots — used on entry cards and inside the Composer
        // to honestly represent which kinds of media are attached.
        enum Media {
            static let audio  = captureAudio
            static let text   = captureText
            static let photo  = capturePhoto
            static let video  = captureVideo
            static let attach = captureAttach
        }

        // AI — everything the model does wears this blue. Crucible
        // reserves the blue family for AI moments; user intent /
        // action accent stays in the ochre family. The 2026-05 sweep
        // moved this from the ochre/amber family (`0x8A5A0E` etc.) to
        // blue after callout from the Projects MVP review.
        //
        // `base`/`tint` mirror the spec's `ai`/`ai-tint` tokens.
        // `strong` is iOS-specific (no spec equivalent) and stays
        // inline — used in narrow contexts that want a denser blue.
        enum AI {
            static let base   = SwiftUI.Color("ai")
            static let strong = SwiftUI.Color(hex: 0x154567)
            static let tint   = SwiftUI.Color("ai-tint")
        }

        // Topic palette — finite pool of hues users pick from when creating a Topic.
        // Topics are user data, NEVER hard-coded. We only define the pool.
        //
        // Chip backgrounds and borders are derived per-render from a single
        // `fg` color via SwiftUI's perceptual `Color.mix`, mirroring the CSS
        // contract `color-mix(in oklab, var(--topic-X) <pct>%, var(--paper))`.
        // Because `paper` and `fg` are both appearance-aware asset colors,
        // the derived values flip light/dark automatically — one token per
        // swatch carries the whole chip styling.
        struct TopicHue {
            let key: String
            let fg: SwiftUI.Color

            /// 14% topic mixed over paper. Use as the chip fill.
            var bg: SwiftUI.Color {
                SwiftUI.Color("paper").mix(with: fg, by: 0.14, in: .perceptual)
            }

            /// 26% topic mixed over paper. Use as the chip border or a
            /// stronger-tint variant when a chip needs definition.
            var border: SwiftUI.Color {
                SwiftUI.Color("paper").mix(with: fg, by: 0.26, in: .perceptual)
            }
        }

        /// 16-swatch topic palette. Slug keys are the cross-platform
        /// contract (see `topicSlug(for:)`). `fg` is sourced from the
        /// asset catalog and adapts to light/dark via the two variants
        /// in each `topic-X.colorset`. `bg` is derived per-render from
        /// `fg` and `paper`, so the chip's surface color tracks both
        /// the picker swatch and the current appearance with no second
        /// source to maintain.
        static let topicPalette: [TopicHue] = [
            // Row 1 · warms
            TopicHue(key: "ember",      fg: SwiftUI.Color("topic-ember")),
            TopicHue(key: "terracotta", fg: SwiftUI.Color("topic-terracotta")),
            TopicHue(key: "clay",       fg: SwiftUI.Color("topic-clay")),
            TopicHue(key: "amber",      fg: SwiftUI.Color("topic-amber")),
            // Row 2 · yellows & greens
            TopicHue(key: "wheat",      fg: SwiftUI.Color("topic-wheat")),
            TopicHue(key: "sage",       fg: SwiftUI.Color("topic-sage")),
            TopicHue(key: "moss",       fg: SwiftUI.Color("topic-moss")),
            TopicHue(key: "pine",       fg: SwiftUI.Color("topic-pine")),
            // Row 3 · blues
            TopicHue(key: "sea",        fg: SwiftUI.Color("topic-sea")),
            TopicHue(key: "tide",       fg: SwiftUI.Color("topic-tide")),
            TopicHue(key: "indigo",     fg: SwiftUI.Color("topic-indigo")),
            TopicHue(key: "violet",     fg: SwiftUI.Color("topic-violet")),
            // Row 4 · purples, roses, neutrals
            TopicHue(key: "plum",       fg: SwiftUI.Color("topic-plum")),
            TopicHue(key: "rose",       fg: SwiftUI.Color("topic-rose")),
            TopicHue(key: "sand",       fg: SwiftUI.Color("topic-sand")),
            TopicHue(key: "slate",      fg: SwiftUI.Color("topic-slate")),
        ]

        /// Returns the hue for a topic. Uses the stored paletteKey if
        /// one exists, otherwise auto-assigns via the spec hash
        /// (`topicSlug(for:)`). Stored overrides win — once a topic
        /// has a paletteKey, the hash is never consulted again for
        /// that topic.
        static func topicHue(for name: String) -> TopicHue {
            if let key = TopicPaletteStore.shared.key(for: name),
               let hue = topicPalette.first(where: { $0.key == key }) {
                return hue
            }
            return topicHue(forKey: topicSlug(for: name))
        }

        /// Look up a hue by its palette key directly.
        static func topicHue(forKey key: String) -> TopicHue {
            topicPalette.first { $0.key == key } ?? topicPalette[0]
        }

        /// Deterministic topic-name → palette-slug hash per the
        /// cross-platform contract in
        /// `docs/design/Crucible · topic palette spec.md`. Same
        /// inputs always produce the same slug; the JavaScript
        /// reference implementation in the spec must produce
        /// byte-identical output for every input. Validate against
        /// the spec's golden vectors when changing anything here.
        ///
        /// Algorithm: djb2 over UTF-16 code units, mod 16. The
        /// `&*` / `&+` are explicit overflow operators to make the
        /// unsigned-32-bit wrap explicit (matches `>>> 0` in JS).
        ///
        /// Topic slugs are load-bearing data — they ship in
        /// `Topic.paletteKey`, round-trip through CloudKit, and
        /// drive the asset-catalog lookup. Don't rename palette
        /// entries without a data migration.
        static func topicSlug(for name: String) -> String {
            let normalized = name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            var h: UInt32 = 5381
            for c in normalized.utf16 {
                h = h &* 33 &+ UInt32(c)
            }
            let index = Int(h % UInt32(topicPalette.count))
            return topicPalette[index].key
        }

        // Scrim — sits behind sheets / modals to dim the page beneath.
        static let scrim = SwiftUI.Color("scrim")
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
        let context = StorageService.shared.viewContext
        let request = NSFetchRequest<Topic>(entityName: "Topic")
        guard let topics = try? context.fetch(request) else { return }
        // Backfill: every topic must have a paletteKey under the
        // v1 design-system contract. Topics created pre-contract or
        // arriving from CloudKit without a slug get one auto-assigned
        // via the spec hash. Idempotent — runs once per topic, never
        // re-runs because paletteKey is non-nil after.
        var dirty = false
        for topic in topics {
            if let pk = topic.paletteKey, !pk.isEmpty {
                map[topic.name] = pk
            } else {
                let slug = Crucible.Color.topicSlug(for: topic.name)
                topic.paletteKey = slug
                map[topic.name] = slug
                dirty = true
            }
        }
        if dirty {
            do {
                try StorageService.shared.save(context: context)
            } catch {
                NSLog("[HiMem][Theme] topic palette backfill save failed: \(error.localizedDescription)")
            }
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
