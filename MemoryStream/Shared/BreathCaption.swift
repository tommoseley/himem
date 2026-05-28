import Foundation

/// Source of truth for the voice-composer "breath" caption rotation,
/// per the May 27 2026 spec revision in `docs/design/Watch · spec.md`
/// and `docs/design/Himem · Voice Composer.html`. Shared between the
/// phone and watch targets so both surfaces show identical text in
/// identical order — the same user moving from phone to watch should
/// see the rotation continue, not reset.
///
/// Both targets persist the rotation index in `UserDefaults`
/// (per-device for now). The spec notes "App Group share where
/// practical" as a future enhancement; when an App Group lands, swap
/// `UserDefaults.standard` for the shared suite in callers — no
/// changes here.
enum BreathCaption {
    /// Italic serif captions shown inside the breath ring, in spec
    /// order. Curly U+2019 apostrophes so serif rendering matches
    /// the rest of the editorial type in the app.
    static let captions: [String] = [
        "Ready when you are.",
        "Start anywhere.",
        "Whenever it comes.",
        "Take your time.",
        "Go ahead.",
        "Say it naturally.",
        "When you\u{2019}re ready.",
        "Hold the thought.",
        "Here when you need it.",
        "Catch the thought.",
        "Don\u{2019}t lose it.",
        "We\u{2019}re ready.",
        "Speak freely.",
    ]

    /// UserDefaults key for the persisted caption index. Same key
    /// across both targets.
    static let defaultsKey = "voice_composer.breath_caption_index"

    /// Pure rotation: advance by one with modular wrap. Negative /
    /// oversized stored values normalize into the band so a
    /// downgrade from a future build with more captions can't
    /// poison the rotation.
    static func nextIndex(after current: Int) -> Int {
        let count = captions.count
        guard count > 0 else { return 0 }
        let normalized = ((current % count) + count) % count
        return (normalized + 1) % count
    }

    /// Returns the caption for a normalized index — callers can pass
    /// a raw stored value without bounds checking.
    static func caption(forIndex index: Int) -> String {
        let count = captions.count
        guard count > 0 else { return "" }
        let normalized = ((index % count) + count) % count
        return captions[normalized]
    }
}
