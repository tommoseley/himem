import Testing
import Foundation
@testable import HiMem

/// Money tests for the shared `BreathCaption` rotation per the May
/// 27 2026 spec revision. Both the phone voice composer and the
/// watch recording surface read from this one source so the same
/// user moving from phone to watch sees the rotation continue, not
/// reset.
///
/// Spec contract (`docs/design/Watch · spec.md`, `docs/design/Himem
/// · Voice Composer.html`): "Caption rotates across recordings —
/// index persisted in UserDefaults. Advance the index on commit,
/// not on cancel."
@MainActor
struct VoiceComposerBreathRotationTests {

    @Test func captionList_matchesSpec() {
        // Locked order from the May 27 2026 spec. Reorder = behavior
        // change (existing installs' persisted index lands on a
        // different caption). U+2019 apostrophe per the comment on
        // the array. "Preparing." / "Almost ready." / "One moment."
        // were dropped — they imply the app is the one doing
        // something, which contradicts the "you're free to speak"
        // rhythm we want here.
        #expect(BreathCaption.captions == [
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
        ])
    }

    @Test func rotation_advancesByOne() {
        #expect(BreathCaption.nextIndex(after: 0) == 1)
        #expect(BreathCaption.nextIndex(after: 1) == 2)
        #expect(BreathCaption.nextIndex(after: 11) == 12)
    }

    @Test func rotation_wrapsAtEnd() {
        // Last caption ("Speak freely.") rolls back to index 0
        // ("Ready when you are.") — closes the loop.
        let lastIndex = BreathCaption.captions.count - 1
        #expect(BreathCaption.nextIndex(after: lastIndex) == 0)
    }

    @Test func rotation_clampsStaleOversizedValue() {
        // A persisted index from a future build with more captions
        // shouldn't poison the rotation when downgrading. With the
        // 13-item list, 99 % 13 = 8 → +1 = 9.
        let count = BreathCaption.captions.count
        let result = BreathCaption.nextIndex(after: 99)
        #expect(result >= 0)
        #expect(result < count)
        #expect(result == 9)
    }

    @Test func rotation_clampsNegativeValue() {
        // Negative stored values (corruption / signed-int hiccup)
        // also normalize cleanly rather than crashing or producing
        // negative indices that would index-out-of-bounds.
        let count = BreathCaption.captions.count
        let result = BreathCaption.nextIndex(after: -3)
        #expect(result >= 0)
        #expect(result < count)
    }

    @Test func caption_forIndex_handlesOversizedAndNegative() {
        // The display helper normalizes too — so callers can pass a
        // raw stored value without manual mod arithmetic.
        let count = BreathCaption.captions.count
        let oversized = BreathCaption.caption(forIndex: 99)
        let negative = BreathCaption.caption(forIndex: -3)
        // 99 % 13 = 8
        #expect(oversized == BreathCaption.captions[8])
        // -3 → normalize: ((-3 % 13) + 13) % 13 = 10
        #expect(negative == BreathCaption.captions[10])
        // And in-band values are returned verbatim.
        #expect(BreathCaption.caption(forIndex: 0) == BreathCaption.captions[0])
        #expect(BreathCaption.caption(forIndex: count - 1) == BreathCaption.captions[count - 1])
    }

    @Test func defaultsKey_isStable() {
        // The persistence key is part of the user's per-device
        // state — renaming it would silently reset the rotation
        // and dump every user back to "Ready when you are." Cheap
        // canary against accidental rename.
        #expect(BreathCaption.defaultsKey == "voice_composer.breath_caption_index")
    }
}
