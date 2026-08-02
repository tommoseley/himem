import Testing
import Foundation
@testable import HiMem

/// **No production file installs a runtime orientation clamp around the
/// camera picker (locked 2026-08-02).**
///
/// F18 removed the clamp on **iPad** after it produced a black preview
/// there, and kept it on iPhone behind `if userInterfaceIdiom != .pad`.
/// The device pass settled which half was right:
///
///   iPad — the platform that **lost** the clamp — **works**.
///   iPhone — the platform that **kept** it — **fails**.
///
/// F18 was right about the symptom and too narrow about the cause. Its
/// ruling was "iPad-only" because iPad was where the failure was
/// *observed*, not because iPhone was known good. That is the general
/// trap this test exists to hold shut: **a fix scoped to the platform it
/// was reproduced on leaves every other platform holding the broken
/// mechanism**, and the suite stays green because nothing asserts the
/// mechanism is gone.
///
/// The mechanism is gone on this OS regardless of idiom. The device log
/// shows `-[UIApplication statusBarOrientation]`, `isStatusBarHidden`
/// and `setStatusBarHidden:` all reporting *"deprecated and is a no-op
/// on 27.0 and later"*, immediately followed by `Attempted to change to
/// mode Portrait with an unsupported device (BackTriple)` and
/// `CMVideoFormatDescriptionGetDimensions … err=-12710 (Invalid desc)`
/// — the capture device failing to configure, which is what a black
/// preview is.
///
/// **What is NOT retired:** `PortraitImagePickerController` keeps
/// declaring its own preferred orientation. That is the supported way to
/// express the preference. What is retired is the app-wide *runtime*
/// clamp wrapped around the picker.
@Suite struct CameraPickerOrientationTests {

    /// THE GUARD.
    @Test func theCameraPickerInstallsNoRuntimeOrientationClamp() throws {
        let src = try Self.source("MemoryStream/Views/Input/CameraPickerView.swift")
        let code = Self.executableLines(of: src)

        #expect(code.contains(where: { $0.contains("OrientationLock") }) == false,
                """
                `CameraPickerView` sets the app-wide orientation lock again. \
                That clamp is what produced a black preview on iPad (F18) and \
                on iPhone (2026-08-02); the machinery it relies on is a no-op \
                on iOS 27.
                """)
        #expect(code.contains(where: { $0.contains("requestGeometryUpdate") }) == false,
                "`CameraPickerView` force-rotates the scene again — same defect, other half.")
    }

    /// The removal must be **unconditional**. An idiom-gated clamp is the
    /// exact shape that shipped: correct on the platform it was tested
    /// on, broken on the other.
    @Test func theRemovalIsNotIdiomGated() throws {
        let src = try Self.source("MemoryStream/Views/Input/CameraPickerView.swift")
        let code = Self.executableLines(of: src)
        #expect(code.contains(where: { $0.contains("userInterfaceIdiom") }) == false,
                """
                `CameraPickerView` branches on device idiom again. If a clamp \
                (or any capture configuration) is wrong on one platform it is \
                suspect on all of them — scoping the fix to where it was \
                reproduced is what left iPhone broken for two days.
                """)
    }

    /// The supported mechanism stays. This guard must not be satisfiable
    /// by deleting the preference entirely.
    @Test func thePickerStillDeclaresItsPreferredOrientation() throws {
        let src = try Self.source("MemoryStream/Views/Input/CameraPickerView.swift")
        #expect(src.contains("PortraitImagePickerController"),
                "The picker subclass that declares its own preferred orientation is gone — the fix was made by removing the preference, not the clamp.")
        #expect(src.contains("supportedInterfaceOrientations") || src.contains("preferredInterfaceOrientation"),
                "`PortraitImagePickerController` no longer declares an orientation preference.")
    }

    /// Self-test: the matcher must be able to see a clamp, or it passes
    /// forever by matching nothing.
    @Test func guardCanSeeAClamp() {
        let offending = """
                if UIDevice.current.userInterfaceIdiom != .pad {
                    OrientationLock.shared.portraitOnly = true
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
                }
        """
        let code = Self.executableLines(of: offending)
        #expect(code.contains(where: { $0.contains("OrientationLock") }))
        #expect(code.contains(where: { $0.contains("requestGeometryUpdate") }))
        #expect(code.contains(where: { $0.contains("userInterfaceIdiom") }))
    }

    /// …and must ignore the comments that explain the removal, or the
    /// guard fails on its own documentation.
    @Test func guardIgnoresComments() {
        let documented = """
                // the app-wide runtime clamp (`OrientationLock` +
                // `requestGeometryUpdate`) wrapped around the picker.
                /// F18 gated this on `userInterfaceIdiom`.
        """
        #expect(Self.executableLines(of: documented).isEmpty)
    }

    // MARK: - Helpers

    /// Lines that are actual code — comments explaining the removal must
    /// not trip a guard about the removal.
    static func executableLines(of source: String) -> [String] {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("//") && !$0.hasPrefix("///") && !$0.hasPrefix("*") }
    }

    static func source(_ relative: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        guard let src = try? String(contentsOf: url, encoding: .utf8), !src.isEmpty else {
            throw Failure.sourceNotFound(url.path)
        }
        return src
    }

    enum Failure: Error { case sourceNotFound(String) }
}
