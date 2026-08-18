import Testing
import Foundation
@testable import HiMem

/// **The transcript eyebrow states the scale, and only in a unit the
/// transcript actually has.**
///
/// Ruled 2026-08-18 (Tom): `Transcript · 3,581 words`. The clip term is
/// **removed, not renamed** — a photo has no place in a transcript count under
/// any noun, so the fix is deleting the wrong number rather than relabelling
/// it. `Memory Detail · long-memory navigation.md:44` changed in the same edit.
///
/// **What went wrong:** `TranscriptWordCount.clipCount` counts voice + note and
/// excludes image and video, while the eyebrow heads the whole PARTS body. A
/// cluster commit carrying its photo (2 voice + 1 photo) therefore drew
/// **"TRANSCRIPT · 2 CLIPS"** over three visible parts — F37's locked rule,
/// *"a count must describe the thing it sits on,"* broken by one eyebrow
/// serving two scopes. The spec's own worked example was a 25-minute lecture,
/// all voice, where the two sets coincide, so the choice was never forced until
/// F43 made cluster commits carry their media.
///
/// **These pin the literal deliberately.** Per *Assert the Meaning, Not the
/// Phrasing*: when the wording IS the promise — a retired term — the test's
/// subject is the term itself, so a failure here reads as *"the retired count
/// came back"*, not *"someone reworded an eyebrow."*
struct TranscriptEyebrowTests {

    @Test
    func eyebrowStatesWordsAndCarriesNoClipCount() {
        let text = TranscriptHeaderControl.eyebrow(wordCount: 3_581)

        #expect(
            !text.lowercased().contains("clip"),
            "The transcript eyebrow must carry no clip count — it heads a body that can contain photos and video, which are not in the transcript under any noun"
        )
        #expect(text.contains("words"), "The scale signal the spec asks for must survive the removal")
        #expect(text.hasPrefix("Transcript · "))
    }

    /// The scale signal is the reason the count exists at all, so it must
    /// actually track the words rather than being a constant that happens to
    /// satisfy the assertion above.
    @Test
    func theWordCountIsTheNumberShown() {
        #expect(TranscriptHeaderControl.eyebrow(wordCount: 12).contains("12"))
        #expect(TranscriptHeaderControl.eyebrow(wordCount: 0).contains("0"))
    }
}
