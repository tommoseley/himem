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
/// **Not authoritative — and the model quality is Apple's to move, not ours
/// (2026-07-23).** Per `AI Organize · spec.md` §2b/§9, on-device output is an
/// *editable first draft* ("Draft organized" until the user reviews). The
/// on-device model is a **platform-controlled moving target**: it regressed
/// under **iOS 27** ("much colder," and it began fabricating proper names).
/// So HiMem's Honest-Label guarantee is **NOT staked on this model's prompt
/// behavior** — prompt tuning against a model Apple changes every OS release
/// is permanently unstable. Honesty is enforced in **deterministic code**
/// (`TruthReconciler`, applied on BOTH tiers via
/// `ProcessingEngine.reconcileResult` — on-device gets `.strict` grounding):
/// a proper name in the summary that the clips don't contain is rejected →
/// retry once → constrained extractive fallback ("say less before saying
/// false"). Models are advisory; code is authoritative. Documented 3B QUALITY ceilings
/// that remain (hand-editable, frontier/Plus clears them, not open bugs):
/// purposive drift · visible-photo claims · occasional voice slip ·
/// subject-out POV slip · invent-a-speaker · structural-metadata leak
/// (narrating "text clip 1" / "two video clips") — the last two are now caught
/// by the gate before they ship, even though the model can still produce them.
/// The structural leak was also fixed at the source (2026-07-24): `formatPrompt`
/// no longer wraps content in a `Text clip 1:` scaffold and the prompt no
/// longer tells the model to "reference [media] by count only" — prompt is
/// primary defense, the `TruthReconciler` structural-leak check is the belt.
///
/// Cross-memory contamination was a real bug, fixed at the source: the
/// library topics/mentions palette is no longer fed to the model (it
/// fabricated other memories' people into unrelated ones), and name reuse is
/// reconciled in code (`MentionReconciler`, now TruthReconciler's first
/// module, via `ProcessingEngine.canonicalizeMentions`). The reconciler is the
/// durable architecture; the prompt is not load-bearing for honesty.
///
/// **No `nextSteps`.** Cut from v1 entirely (RH-6, July 20 2026) — it's
/// no longer on `AnalysisResult` and no UI consumes it. The on-device
/// schema never had it: the 3B model fabricates forward actions when given
/// the field, even when the clips don't state them.
///
/// **The Cadence rule has NO positive example — do not add one (2026-07-23).**
/// The rule is prose only ("write as ONE connected thought … never clipped
/// declaratives, never a comma-list of fragments"). Every concrete Cadence
/// EXAMPLE we tried bled into the output, because a 3B model treats a
/// few-shot example as content to emit regardless of how abstract it is:
///   1. Concrete nouns ("peppers, tomatoes, and eggplants … South Carolina
///      garden … retirement") bled verbatim into an unrelated Lincoln-quote
///      memory — an Honest-Label data-integrity failure (asserting clips the
///      memory doesn't contain).
///   2. Abstracting the nouns to placeholders but keeping verbs ("You're
///      noting A…") → the model parroted "noting" into 4 of 6 calibration
///      summaries; the "You're" pushed a subject-out memory to second person.
///   3. Verb-free, POV-neutral shapes ("A, while B, and C") → the model
///      latched onto the comma-list and produced "You, X, and Y" fragments.
/// The example itself is the payload. So the positive example is GONE; the
/// prose rule (plus a NEGATIVE characterization of the anti-patterns, using
/// obvious X/Y placeholders) carries the pedagogy. A future edit must NOT
/// "helpfully" add a warm/cold example sentence back — re-run the FM-spike
/// QA panel after ANY prompt edit, since the prompt is the validated artifact.
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
    /// No `nextSteps` (cut from v1, RH-6).
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
    - If the memory has NO first-person voice — only a photo or a bare observation, nobody speaking as "I" — leave the owner out entirely. Do NOT write "You're capturing…" or "You…". Name only what is there. Example: for a sunset photo, "A deep-orange sunset over the ridge," not "You captured a sunset."
    - Do not add reasons, purposes, or causes the clips don't state. No "to ___," no "because ___."
    - Cadence: write the summary as ONE connected thought, the way a thoughtful friend would recap — flowing, subordinated sentences that string the facts together, connected with subordinating words (while, and, since, as). Never a run of short, clipped "You're X. You're Y. The Z is …" declaratives; that reads as a cold status log about the person. And never a comma list of fragments ("You, X, and Y, three things"). Keep the memory's own specific nouns; change only how they connect.
    - Describe only what was said or shown — never the container it arrived in. NEVER mention clips, a number of clips, "clip 1" / "clip N", or media types (photo, video, voice, note, audio, text). Photos and videos are not visible to you: do not invent their visual content, and do not count or label them. If a photo or video came with a description, treat that description as plain content, not as "a photo."
    - Topic selection: when the input lists the user's existing topics, prefer one of those exact labels if any fits this memory. Coin a new topic only when none of the existing topics reasonably fit.
    - Mention selection: when the input lists people, places, and projects the user has mentioned before, prefer one of those exact names if the memory refers to the same one. Coin a new mention only when none of the existing ones match.
    - Only ever name a topic or mention that THIS memory's clips actually refer to. The existing-topics and existing-mentions lists are for spelling and avoiding near-duplicates — they are NOT things to add. Never insert a name or topic from those lists that this memory does not mention. If the clips name no people, places, or projects, return no mentions. If nothing fits, return none.

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

    // MARK: - Project short summary (compress the long summary)

    /// Static instructions for the short-summary compression. The whole point
    /// (locked 2026-07-23): the short is **derived from the contents of the
    /// long summary alone** — it is a compression, never a re-reading of the
    /// project's memories — so it cannot introduce anything the long summary
    /// doesn't already state.
    static let shortSummaryInstructions = """
    You compress an already-written project summary into a single short line.

    You are given ONE piece of text: a longer project summary. Your only job is \
    to derive a one-line version FROM THAT TEXT ALONE. You are shortening it, \
    not adding to it.

    Rules:
    - Use only what the long summary already states. Introduce no name, place, \
    organization, date, number, or idea that is not present in the text you are \
    given. If it is not in the long summary, it must not be in the short one.
    - One sentence, roughly 8–16 words.
    - Keep the second-person voice ("You're …") when the long summary uses it.
    - Do not restate the project's name, do not wrap it in quotes, and never \
    open with "This project…" or "The summary…". Just the essence of what it is \
    about, exactly as the long text frames it.
    """

    /// Derives the one-line **short** project summary by compressing the
    /// **long** summary's own text on-device (Apple Intelligence). The input is
    /// the long summary and nothing else — see `shortSummaryInstructions`. This
    /// is a good fit for on-device precisely because it is compression of
    /// already-coherent prose, not synthesis from raw fragments; honesty is
    /// still enforced by the caller gating the result against the long text via
    /// `TruthReconciler` (strip → retry → extractive fallback), so a slip can
    /// only come out plainer, never false. Throws `modelUnavailable` on a
    /// device without Foundation Models — the caller then falls back to a
    /// deterministic extractive one-liner drawn from the long summary.
    func compressToShort(longSummary: String) async throws -> String {
        if let unavailable = Self.availabilityError() {
            throw unavailable
        }
        let session = LanguageModelSession(instructions: Self.shortSummaryInstructions)
        let prompt = """
        Long summary:
        \(longSummary)

        Write the one-line short version, derived only from the long summary above.
        """
        let response = try await session.respond(to: prompt, options: GenerationOptions())
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
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
        // The content is presented plainly — NO "Text clip N:" scaffold, no
        // media labels, no counts (2026-07-24). The 3B model parroted the
        // "Text clip 1:" wrapper and the "reference by count only" rule into
        // summaries ("text clip 1", "two video clips") — structural metadata
        // narrated as content. The payload is the clips' transcript/
        // description text only; the model must describe that, never the
        // container. (Same failure family as the cadence-example bleed.)
        return """
        MEMORY

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
    /// - `nextSteps` no longer exists on `AnalysisResult` (cut from v1, RH-6).
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
            title: output.title
        )
    }
}
