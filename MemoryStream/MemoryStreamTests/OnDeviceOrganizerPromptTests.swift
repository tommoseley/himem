import Testing
import Foundation
@testable import HiMem

/// Money tests for `OnDeviceOrganizer.formatPrompt(content:existingTopics:)`
/// and `promptInstructions`. Per AI Organize spec §2c "Palette
/// discipline", the on-device prompt must bias the model toward the
/// user's existing topic palette — "Until it lands, the on-device path
/// is the source of topic sprawl."
///
/// Before 2026-06-07, `formatPrompt` took only `content:` and the
/// `existingTopics` parameter to `organize(...)` was silently dropped.
/// The model coined fresh topic names every pass: *Garden / Gardening
/// / Plants / Yard / Vegetables* — fragmenting the palette until
/// topics were useless as filters. This test enforces the plumbing
/// fix.
@Suite
struct OnDeviceOrganizerPromptTests {

    @available(iOS 26.0, *)
    @Test func formatPrompt_emptyExistingTopics_omitsSection() {
        let prompt = OnDeviceOrganizer.formatPrompt(content: "Hello", existingTopics: [])
        // No "Existing topics:" header on first-pass memories — the
        // palette is empty so the bias instruction would be noise.
        #expect(prompt.lowercased().contains("existing topics") == false)
    }

    @available(iOS 26.0, *)
    @Test func formatPrompt_withExistingTopics_includesEachTopicInPrompt() {
        let prompt = OnDeviceOrganizer.formatPrompt(content: "Hello", existingTopics: ["Garden", "Work"])
        // The list must reach the model verbatim — that's the whole
        // point of the bias.
        #expect(prompt.contains("Garden"))
        #expect(prompt.contains("Work"))
    }

    @available(iOS 26.0, *)
    @Test func formatPrompt_alwaysIncludesContent() {
        let prompt = OnDeviceOrganizer.formatPrompt(content: "specific marker content", existingTopics: [])
        #expect(prompt.contains("specific marker content"))
    }

    @available(iOS 26.0, *)
    @Test func formatPrompt_emptyTopicsAreFilteredFromSection() {
        // Defensive: a stray empty string in the palette (shouldn't
        // happen, but if it does) doesn't render as a phantom bullet
        // in the prompt.
        let prompt = OnDeviceOrganizer.formatPrompt(content: "Hello", existingTopics: ["", "Garden"])
        #expect(prompt.contains("Garden"))
        // Count bullet-style markers — should be one, not two.
        let bullets = prompt.components(separatedBy: "\n- ").count - 1
        #expect(bullets == 1)
    }

    /// The model rule from spec §2c lives in the static instructions
    /// passed to `LanguageModelSession(instructions:)`. The exact
    /// wording isn't load-bearing for the test, but the directive
    /// MUST be present — otherwise the per-call topic list is just
    /// context with no guidance for the model.
    @available(iOS 26.0, *)
    @Test func promptInstructions_includesPreferExistingDirective() {
        let instructions = OnDeviceOrganizer.promptInstructions.lowercased()
        // Either phrasing is fine; the rule is "bias toward the
        // palette" and the test enforces that the prompt actually
        // mentions the palette.
        let mentionsPaletteRule =
            instructions.contains("existing topic") ||
            instructions.contains("existing palette") ||
            instructions.contains("user's palette") ||
            instructions.contains("supplied palette")
        #expect(mentionsPaletteRule, "Prompt instructions must direct the model to prefer existing palette topics per AI Organize spec §2c")
    }
}
