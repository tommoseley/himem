import Foundation
import AVFoundation

/// **The one owner of capture audio-session mode, for every surface.**
///
/// **We record in `.default` mode, never `.measurement`** — watch and phone
/// alike.
///
/// `.measurement` minimizes system input processing — which includes input
/// GAIN — so the watch mic landed at ~-40 dBFS: the loud-clip dogfood had
/// `in_peak` pinned ~0.01 regardless of how loud the user spoke, and nothing
/// transcribed (silent clips, capture-gain P0, 2026-07-15). `.measurement` was
/// *also* selecting the raw 3-channel hardware input. `.default` applies normal
/// input gain AND resolves to processed mono — it fixes the level bug and
/// dissolves the 3-channel downmix problem at the source (dogfood: `in_peak`
/// 0.1, clips transcribe).
///
/// **Why this is no longer watch-specific (F18, 2026-07-31).** The original fix
/// landed only on the watch, behind a comment asserting *"the phone tolerates
/// `.measurement` because its mic is hotter."* The phone kept a hardcoded
/// `.measurement` literal in `SpeechService`. That assumption was wrong twice
/// over: on **iPad** the input is so far un-gained that the composer's waveform
/// never moves and voice capture is dead; and on **iPhone** "tolerates" only
/// ever meant "the defect is small enough not to be noticed" — every phone
/// recording was quieter than it should be, which is the last thing you want in
/// a noisy car.
///
/// One surface got an owner and a test, the other kept a literal, so the fix
/// could not travel. **Naming the owner after one surface is what made that
/// feel correct.** It is named for the *concern* now.
///
/// The mode invariant is the standing regression guard
/// (`CaptureAudioSessionConfigTests`), which asserts both that this constant
/// applies gain **and** that no production file hardcodes the mode instead of
/// reading it. The `[Amp]` transcode log is the device-side check; these are the
/// deterministic ones.
enum CaptureAudioSessionConfig {
    /// Record + warm session mode, every surface. MUST apply input gain —
    /// `.default`, not `.measurement`. See the type doc for why. `nonisolated`
    /// so the `nonisolated` warm/record paths in `WatchRecordingService` can
    /// read it (the project defaults to MainActor isolation).
    nonisolated static let recordMode: AVAudioSession.Mode = .default
}
