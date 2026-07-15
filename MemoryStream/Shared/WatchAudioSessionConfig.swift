import Foundation
import AVFoundation

/// Watch capture audio-session configuration (capture-gain P0, 2026-07-15).
///
/// **The watch records in `.default` mode, never `.measurement`.**
///
/// `.measurement` minimizes system input processing — which includes input
/// GAIN — so the watch mic landed at ~-40 dBFS: the loud-clip dogfood had
/// `in_peak` pinned ~0.01 regardless of how loud the user spoke, and nothing
/// transcribed (silent clips). `.measurement` was *also* selecting the raw
/// 3-channel hardware input. `.default` applies normal input gain AND resolves
/// to processed mono — it fixes the level bug and dissolves the 3-channel
/// downmix problem at the source (dogfood: `in_peak` 0.1, clips transcribe).
///
/// The mode invariant is the standing regression guard
/// (`WatchAudioSessionConfigTests`): a refactor that silently reverts to
/// `.measurement` re-breaks capture. The `[Amp]` transcode log is the
/// device-side check; this constant is the deterministic one.
enum WatchAudioSessionConfig {
    /// Record + warm session mode. MUST apply input gain — `.default`, not
    /// `.measurement`. See the type doc for why. `nonisolated` so the
    /// `nonisolated` warm/record paths in `WatchRecordingService` can read it
    /// (the project defaults to MainActor isolation).
    nonisolated static let recordMode: AVAudioSession.Mode = .default
}
