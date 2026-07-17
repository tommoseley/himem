import Foundation
import FoundationModels

/// Apple Foundation Models (iOS 26) implementation of `Organizer`.
///
/// Ported verbatim from the FM spike's locked iter-5 prompt
/// (`HiMemFMSpike/OrganizeService.swift`) — see
/// `docs/architecture/foundation-models-spike-findings.md` for the
/// validation history. The prompt is the source of truth; if it
/// drifts from the spike, the spike's QA panel is no longer a valid
/// reference for output quality.
///
/// **Not authoritative.** Per `AI Organize · spec.md` §2b/§9 and the
/// spike findings, on-device output is presented as an *editable
/// first draft*. The Memory Detail chip reads "Draft organized"
/// until the user reviews. Three documented failure classes (purposive
/// drift, visible-photo claims, occasional voice slip) are
/// hand-editable and the UI does not promise authority.
///
/// **No `nextSteps`.** Per `AI Organize · spec.md` §6, `nextSteps` is
/// a Plus-only field. The on-device schema omits it entirely — the
/// 3B model fabricates forward actions when given the field, even
/// when the clips don't state them.
///
/// **Mention typing.** The on-device prompt returns mentions as
/// untyped strings (the model lacks reliable typing at the 3B scale).
/// All mentions are stored as `.idea` — the Memory Detail UI surfaces
/// them under a unified "Mentions" section regardless of subtype,
/// matching the spec's untyped framing. This matches
/// `ExtractedEntity.entityTypeEnum`'s fallback (`?? .idea`).
final class OnDeviceOrganizer: Organizer {

    /// Structured output schema for FoundationModels. Mirrors the
    /// spike's `OrganizeOutput` — title, summary, topics, mentions.
    /// No `nextSteps` (Plus-only).
    @Generable
    struct OrganizeOutput: Equatable {
        @Guide(description: "A concrete noun phrase, 3–8 words.")
        var title: String

        @Guide(description: "A 1–4 sentence summary.")
        var summary: String

        @Guide(description: "1–3 short topic labels.")
        var topics: [String]

        @Guide(description: "0–5 named entities (people, places, projects, ideas).")
        var mentions: [String]
    }

    /// Iter-5 prompt from the spike (`docs/architecture/foundation-
    /// models-spike-findings.md` §3) plus the palette-discipline rule
    /// locked by AI Organize spec §2c (June 2026). The palette
    /// directive closed the "on-device path is the source of topic
    /// sprawl" gap the spec named — Garden/Gardening/Plants/Yard all
    /// coined fresh by the previous on-device pass, fragmenting the
    /// user's filter palette into uselessness. The per-call prompt
    /// (`formatPrompt`) injects the actual palette list; this static
    /// directive tells the model what to do with it.
    static let strictPromptInstructions = """
    You are HiMem's AI Organize feature. Your job is to give a memory a name its author will recognize six months later.

    - Honest Label: describe what the clips contain. Never what they mean or what the user feels. Do not add details the clips don't have.
    - Every sentence about the owner must begin with "You" or "You're." Never "the user", "the author", "the clip", or "the memory" as a subject. Use names for everyone else.
    - Do not add reasons, purposes, or causes the clips don't state. No "to ___," no "because ___."
    - Photo and video clips are not visible. Do not describe their visual content. Reference them by count only.
    - Topic selection: when the input lists the user's existing topics, prefer one of those exact labels if any fits this memory. Coin a new topic only when none of the existing topics reasonably fit.
    - Mention selection: when the input lists people, places, and projects the user has mentioned before, prefer one of those exact names if the memory refers to the same one. Coin a new mention only when none of the existing ones match.

    Generate: title, summary, topics, mentions.
    """

    /// Debug-only minimal prompt — strips every stylistic
    /// constraint so we can test whether the strict prompt's
    /// cumulative cognitive load (Honest-Label voice + mandatory
    /// "You" framing + no-causes + media-blindness + palette
    /// discipline) was a factor when the strict prompt fails. Per
    /// Tom 2026-06-08 ("maybe the complexity (relatively) of the
    /// prompt took it over a hump"). Toggle via Settings → Debug
    /// → "Use lean organize prompt." Flag clears on next ship-day
    /// build, not load-bearing in production.
    static let leanPromptInstructions = """
    Summarize this memory. Generate: title, summary, topics, mentions.
    """

    /// Picks between the strict iter-5 prompt and the lean debug
    /// prompt based on the `himem.debug.useLeanOrganizerPrompt`
    /// UserDefaults flag. Production always reads strict; the lean
    /// path is for diagnostic A/B against safety-rejected content.
    static var promptInstructions: String {
        if UserDefaults.standard.bool(forKey: "himem.debug.useLeanOrganizerPrompt") {
            NSLog("[HiMem][OnDeviceOrganizer] using LEAN prompt (debug flag set)")
            return leanPromptInstructions
        }
        return strictPromptInstructions
    }

    enum OrganizerError: Error, LocalizedError {
        case modelUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .modelUnavailable(let reason):
                return "On-device organize unavailable: \(reason)"
            }
        }
    }

    /// Pre-flight check. Returns nil if the system model is ready,
    /// or an error describing why it isn't (device ineligibility,
    /// Apple Intelligence not enabled, model not yet downloaded).
    /// Callers route around an unavailable model rather than throw.
    static func availabilityError() -> OrganizerError? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            return .modelUnavailable(String(describing: reason))
        }
    }

    func organize(
        content: String,
        existingTopics: [String],
        existingMentions: [String]
    ) async throws -> ClaudeAPIService.AnalysisResult {
        if let unavailable = Self.availabilityError() {
            throw unavailable
        }

        let session = LanguageModelSession(instructions: Self.promptInstructions)
        let promptInput = Self.formatPrompt(
            content: content,
            existingTopics: existingTopics,
            existingMentions: existingMentions
        )
        do {
            let response = try await session.respond(
                to: promptInput,
                generating: OrganizeOutput.self,
                options: GenerationOptions()
            )
            return Self.mapToAnalysisResult(response.content)
        } catch {
            // Detailed diagnostic dump. Apple's `GenerationError` is
            // opaque ("Detected content likely to be unsafe") and
            // doesn't surface which content tripped it, but the
            // reflection dump captures the enum case + any
            // associated values, which is the closest we can get to
            // "what specifically failed." Logged here (closest to
            // the source) so the failure type is available for
            // anyone reading device logs. The ProcessingEngine
            // catcher logs the surface-level error too.
            let typeStr = String(describing: type(of: error))
            let reflected = String(reflecting: error)
            let contentChars = content.count
            let firstChars = String(content.prefix(120)).replacingOccurrences(of: "\n", with: " ")
            NSLog("[HiMem][OnDeviceOrganizer] respond() threw: type=\(typeStr) contentChars=\(contentChars)")
            NSLog("[HiMem][OnDeviceOrganizer]   localized=\(error.localizedDescription)")
            NSLog("[HiMem][OnDeviceOrganizer]   reflected=\(reflected)")
            NSLog("[HiMem][OnDeviceOrganizer]   contentPreview=\(firstChars)")
            // Classify into a coarse category by string-matching the
            // localized description — Apple doesn't expose a stable
            // typed reason, but the strings are predictable enough
            // to log a category that maps to remediation ("retry
            // via cloud" vs "memory too long, chunk it").
            let lower = error.localizedDescription.lowercased()
            let category: String
            if lower.contains("unsafe") || lower.contains("guardrail") || lower.contains("safety") {
                category = "guardrail-violation"
            } else if lower.contains("context") || lower.contains("token") || lower.contains("length") {
                category = "context-overflow"
            } else if lower.contains("unavailable") || lower.contains("not ready") {
                category = "model-unavailable"
            } else {
                category = "other"
            }
            NSLog("[HiMem][OnDeviceOrganizer]   category=\(category)")
            throw error
        }
    }

    /// Renders the memory text plus (when non-empty) the user's
    /// existing topic palette into the per-call prompt input. The
    /// palette section is the data side of spec §2c — without it the
    /// model has nothing to prefer, even though the static
    /// instructions tell it to. When the palette is empty (first-pass
    /// memory or wiped library), the section is omitted entirely to
    /// keep the prompt clean.
    ///
    /// Internal (not `private`) so the prompt-shape money tests in
    /// `OnDeviceOrganizerPromptTests` can exercise every cell of the
    /// palette / no-palette / whitespace-padding matrix.
    static func formatPrompt(
        content: String,
        existingTopics: [String],
        existingMentions: [String] = []
    ) -> String {
        let topicsSection = paletteSection(
            entries: existingTopics,
            header: "Existing topics in this user's library (prefer one of these if any fits):"
        )
        // Mentions get their own palette section, mirroring topics
        // (AI Organize spec §2c "Mentions follow the same palette
        // discipline"). Without it the on-device model coins a fresh
        // name every pass — Darlene / Darlene G. / Darlene Graham —
        // fragmenting recurring people. The static directive tells the
        // model what to do with the list; this renders the list.
        let mentionsSection = paletteSection(
            entries: existingMentions,
            header: "People, places, and projects this user has mentioned before (prefer one of these if any fits):"
        )
        return """
        MEMORY

        Text clip 1:
        "\(content)"
        \(topicsSection)\(mentionsSection)

        Organize this memory.
        """
    }

    /// Renders a bulleted "prefer one of these" palette block, or an
    /// empty string when the palette is empty (first-pass memory or a
    /// wiped library) so the prompt stays clean. Shared by the topics
    /// and mentions sections — one shape, two vocabularies.
    private static func paletteSection(entries: [String], header: String) -> String {
        let trimmed = entries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { return "" }
        let bulleted = trimmed.map { "- \($0)" }.joined(separator: "\n")
        return """


        \(header)
        \(bulleted)
        """
    }

    /// Maps the on-device structured output into the cloud-shaped
    /// `AnalysisResult` that `ProcessingEngine`'s storage helpers
    /// consume. Per spec:
    ///
    /// - Mentions → entities with type `idea` (untyped mentions, full
    ///   confidence). The Memory Detail UI groups them under a single
    ///   "Mentions" section.
    /// - `nextSteps` is nil (Plus-only field, not produced on-device).
    static func mapToAnalysisResult(_ output: OrganizeOutput) -> ClaudeAPIService.AnalysisResult {
        let entities = output.mentions.map { mention in
            ClaudeAPIService.EntityResult(
                type: ExtractedEntity.EntityType.idea.rawValue,
                value: mention,
                confidence: 1.0
            )
        }
        return ClaudeAPIService.AnalysisResult(
            entities: entities,
            topics: output.topics,
            summary: output.summary,
            title: output.title,
            nextSteps: nil
        )
    }
}
