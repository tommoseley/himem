import Testing
import Foundation

/// **The Watch's *Next* button must keep its controller.**
///
/// `On a roll · spec.md` is CURRENT and **Watch-only** — the phone sections
/// were removed from it on 2026-09-17, not annotated. So when §5.4 retires the
/// phone's voice capture, the roll machinery must survive on the wrist.
///
/// The hazard is specific and was nearly acted on: `NextClipController` and
/// `MinClipDebouncer` live in **`Shared/`**, compiled into both targets. The
/// §5.4 brief described "On-a-roll's phone half" as part of the deletion, and
/// read literally that would have taken the Watch's Next button with it. The
/// phone half is `VoiceClipSplitter`, `VoiceCaptureOrchestrator` and the call
/// sites inside `VoiceCaptureScreen`; **nothing in `Shared/`**.
///
/// This test lives in the **Watch** target on purpose. A guard for "the Watch
/// still has its controller" that runs only in the phone suite would keep
/// passing on a build where the Watch no longer compiles it.
@Suite struct WatchNextPathSurvivesTests {

    enum GateFailure: Error { case sourceNotFound(String) }

    /// `…/MemoryStream/` — this file is at `Himem Watch Watch AppTests/…`.
    private static let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func source(_ rel: String) throws -> String {
        let url = projectRoot.appendingPathComponent(rel)
        guard let s = try? String(contentsOf: url, encoding: .utf8), !s.isEmpty else {
            throw GateFailure.sourceNotFound(url.path)
        }
        return s
    }

    /// **THE LOAD-BEARING ASSERTION.** The controller exists, in `Shared/`.
    @Test("the roll controller still exists and is shared")
    func theControllerSurvives() throws {
        let src = try Self.source("Shared/NextClipController.swift")
        #expect(src.contains("class NextClipController"), """
            `NextClipController` is gone or moved out of `Shared/`. The Watch's \
            Next button — commit this recording, start another, never pause the \
            waveform — depends on it, and `On a roll · spec.md` is CURRENT.
            """)
        let debounce = try Self.source("Shared/MinClipDebouncer.swift")
        #expect(debounce.contains("MinClipDebouncer"), """
            `MinClipDebouncer` is gone. It is the rolling-thumb protection: a \
            tap under 2s is silently ignored, because surfacing "too short!" \
            would punish behaviour she did not intend.
            """)
    }

    /// The Watch's recording screen must still *wire* it. A controller nothing
    /// constructs is the shape this project keeps finding — guard the caller,
    /// not just the owner.
    @Test("the Watch recording screen still wires the controller")
    func theWatchStillWiresIt() throws {
        let view = try Self.source("Himem Watch Watch App/WatchRecordingView.swift")
        #expect(view.contains("NextClipController(handoff:"), """
            `WatchRecordingView` no longer constructs `NextClipController`. The \
            type can survive while the button stops working, which is exactly \
            the failure this guard exists for.
            """)
        #expect(view.contains("@StateObject private var nextController"),
                "the controller must be owned by the view, not recreated per render")
    }

    /// The roll key is what makes a roll one memory on arrival. If the Watch
    /// stops stamping it, `ArrivedClipMaterializer` has nothing to group on and
    /// a five-tap roll silently becomes five memories again.
    @Test("the Watch still stamps a roll group id")
    func theRollKeyIsStillStamped() throws {
        let service = try Self.source("Himem Watch Watch App/WatchRecordingService.swift")
        #expect(service.contains("rollGroupId"), """
            The Watch stopped carrying `rollGroupId`. On arrival it is the \
            deterministic override that makes a roll one memory; without it the \
            §1 defect returns by a different route.
            """)
    }
}
