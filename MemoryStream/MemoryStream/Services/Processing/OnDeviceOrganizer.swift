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

    /// The locked iter-5 prompt from the spike. See
    /// `docs/architecture/foundation-models-spike-findings.md` §3.
    static let promptInstructions = """
    You are HiMem's AI Organize feature. Your job is to give a memory a name its author will recognize six months later.

    - Honest Label: describe what the clips contain. Never what they mean or what the user feels. Do not add details the clips don't have.
    - Every sentence about the owner must begin with "You" or "You're." Never "the user", "the author", "the clip", or "the memory" as a subject. Use names for everyone else.
    - Do not add reasons, purposes, or causes the clips don't state. No "to ___," no "because ___."
    - Photo and video clips are not visible. Do not describe their visual content. Reference them by count only.

    Generate: title, summary, topics, mentions.
    """

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
        let promptInput = Self.formatPrompt(content: content)
        let response = try await session.respond(
            to: promptInput,
            generating: OrganizeOutput.self,
            options: GenerationOptions()
        )

        return Self.mapToAnalysisResult(response.content)
    }

    /// Renders the memory text into the input string the model sees.
    /// Keeps the format minimal — the spike's elaborate `TestMemory`
    /// scaffolding (multi-clip rows, time/place context) is deferred
    /// until the main app feeds those signals. PR 8a only routes the
    /// content string through.
    private static func formatPrompt(content: String) -> String {
        """
        MEMORY

        Text clip 1:
        "\(content)"

        Organize this memory.
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
