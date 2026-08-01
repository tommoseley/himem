import Testing
import Foundation
import Speech
@testable import HiMem

/// F23 · the transcription round-trip's coverage is no longer allowed to be
/// silently zero.
///
/// Eight test legs across six files exercise the only end-to-end coverage of
/// **record → compress → transcribe**. Each used to `print` a note and
/// `return` when the on-device speech model was absent. That is honest in the
/// console and invisible in the result: a `print`-and-`return` reports as
/// **passed**, so on a machine without the asset the suite goes green having
/// exercised none of it.
///
/// It was not hypothetical. On 2026-07-31 every one of the eight skipped on the
/// development simulator, so each "1195 passed" gate that day contained zero
/// transcription coverage while reading as full coverage.
///
/// So the gap is now loud. Per the ruling (2026-07-31): make the absence a
/// failure, and make the failure **name the cause and the remedy** — this
/// machine lacks the speech asset; transcription is not broken. A local
/// opt-out was explicitly rejected: an opt-out is how the gap hid in the first
/// place.
///
/// Splitting each leg into a model-free half against a stubbed recognizer
/// (real coverage everywhere) is the better answer and is post-tag — it needs
/// a seam through the transcription path that does not exist yet.
enum SpeechAssetGate {

    /// `true` when the round trip can actually be exercised. When it cannot,
    /// records a failure naming what is missing, why, and what to do — then
    /// returns `false` so the caller can return without asserting on a leg
    /// that never ran.
    ///
    /// - Parameter leg: what this test would have covered, named in the
    ///   failure so a reader knows which coverage is missing rather than
    ///   which line failed.
    @available(iOS 26.0, *)
    static func canExerciseTranscription(
        _ leg: String,
        locale: Locale = .current,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async -> Bool {
        if await TranscriptionService.shared.modelIsInstalled(for: locale) { return true }

        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let status = await AssetInventory.status(forModules: [transcriber])
        Issue.record(
            """
            NO TRANSCRIPTION COVERAGE — "\(leg)" did not run.

            Transcription is NOT broken. This machine lacks the on-device \
            speech asset for \(locale.identifier) (AssetInventory status: \
            \(String(describing: status))), so the leg was skipped.

            \(Self.remedy(for: status, locale: locale))

            Why this is a failure rather than a quiet skip: these eight legs \
            are the only end-to-end coverage of record → compress → \
            transcribe. A `print`-and-`return` reports as PASSED, so a machine \
            without the asset produced a fully green suite with none of that \
            path exercised (F23 audit, Class 4 #5; observed 2026-07-31).
            """,
            sourceLocation: sourceLocation
        )
        return false
    }

    /// The remedy depends on which of two very different things is wrong.
    @available(iOS 26.0, *)
    private static func remedy(for status: AssetInventory.Status, locale: Locale) -> String {
        switch status {
        case .unsupported:
            return """
            REMEDY: this runtime reports the speech model as UNSUPPORTED for \
            \(locale.identifier) — it cannot be downloaded here, so \
            `ensureModelReady` will not help. Run this suite on a real device, \
            or on a simulator runtime that ships the speech assets. (Observed \
            on the iOS 26.4 simulator, 2026-07-31.)
            """
        default:
            return """
            REMEDY: the asset is supported but not cached on this machine. Run \
            once with a network connection so \
            `TranscriptionService.ensureModelReady(for:)` can install it — it \
            caches permanently per locale — then re-run.
            """
        }
    }
}
