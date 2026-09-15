import Testing
import Foundation
@testable import HiMem

/// **The tee's guard: a device reading must not depend on the collection path.**
///
/// On 2026-09-15, five consecutive attempts to collect a device log failed.
/// `log collect --device-udid` returned `Device not configured` against a
/// locked phone, an unlocked phone and a wired one, and nothing on record shows
/// it ever working on this machine. A sysdiagnose succeeded, and its 2.3 GB
/// archive carried **no third-party subsystem lines at all** for the window we
/// needed while holding 138,522 Apple-subsystem lines from those same twenty
/// minutes. The app was emitting throughout — the identical line appeared live
/// over a `devicectl --console` bridge.
///
/// The reading was lost in the **collection path**, not the instrument.
/// `DeviceLogFile` writes every `DeviceLog` line into the app container, so a
/// reading is pulled with `devicectl device copy from`: no sudo, no password,
/// no retention window, no dependency on third-party log persistence.
///
/// **Why `.serialized`, and what it does NOT buy.** `directoryOverride` is
/// process-global, so this attribute orders *this suite's own* tests against
/// each other and nothing more. It emphatically does **not** isolate the file:
/// while the override is set, every other suite's `DeviceLog` calls land in the
/// same temp file, because the sink is reachable from the whole process. Any
/// assertion here must therefore be scoped to this suite's own markers rather
/// than to the file's totals — the first draft counted total lines, passed in
/// isolation, and failed at 1542 cases. That is the retired rule in CLAUDE.md
/// § Test Concurrency reappearing: serializing a suite is not a remedy for
/// process-global state, and the lock at the owner is what makes the write
/// safe. `concurrentAppendsDoNotTearLines` is what exercises that lock.
@Suite(.serialized)
struct DeviceLogFileTests {

    enum GateFailure: Error { case sourceNotFound(String), anchorNotFound(String) }

    private func withTempDirectory(_ body: (URL) throws -> Void) rethrows {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("devicelogfile-\(UUID().uuidString)", isDirectory: true)
        DeviceLogFile.directoryOverride = dir
        defer {
            DeviceLogFile.directoryOverride = nil
            try? FileManager.default.removeItem(at: dir)
        }
        try body(dir)
    }

    // MARK: - The caller guard

    /// **The load-bearing test.** Proving `DeviceLogFile.append` works proves
    /// nothing about whether anyone calls it — the Guard-the-Caller class. This
    /// drives the four real `DeviceLog` entry points and asserts each one lands
    /// in the file, so adding a fifth `DeviceLog` function without teeing it, or
    /// dropping a tee in a refactor, fails here rather than as a silent absence
    /// in a device reading three weeks later.
    @Test("every DeviceLog category reaches the file — the tee is on the caller, not just the sink")
    func everyDeviceLogCategoryReachesTheFile() throws {
        try withTempDirectory { _ in
            DeviceLog.wc("wc-marker")
            DeviceLog.inbox("inbox-marker")
            DeviceLog.build("build-marker")
            DeviceLog.launch("launch-marker")

            let text = try String(contentsOf: DeviceLogFile.fileURL, encoding: .utf8)
            for (category, marker) in [("WC", "wc-marker"), ("Inbox", "inbox-marker"),
                                       ("Build", "build-marker"), ("Launch", "launch-marker")] {
                #expect(text.contains("[\(category)] \(marker)"), """
                DeviceLog.\(category) logged to Logger but not to the file.
                A category that is not teed is invisible to every device reading
                taken from the container — which is the entire failure this type
                exists to remove.
                """)
            }
        }
    }

    // MARK: - Bounded growth

    @Test("rotation caps the file — a diagnostic sink must not grow without bound on someone's phone")
    func rotationCapsTheFile() throws {
        try withTempDirectory { _ in
            let chunk = String(repeating: "x", count: 4096)
            var written = 0
            while written < DeviceLogFile.maxBytes + 8192 {
                DeviceLog.inbox(chunk)
                written += chunk.utf8.count
            }
            let fm = FileManager.default
            #expect(fm.fileExists(atPath: DeviceLogFile.rotatedURL.path),
                    "past the cap, the previous file must be kept as the single rollover")
            let attrs = try fm.attributesOfItem(atPath: DeviceLogFile.fileURL.path)
            let size = attrs[.size] as? Int ?? Int.max
            #expect(size < DeviceLogFile.maxBytes, """
            The live file is \(size) bytes against a \(DeviceLogFile.maxBytes)-byte cap.
            Worst case on disk must stay bounded at 2 * maxBytes.
            """)
        }
    }

    // MARK: - The lock at the owner

    @Test("concurrent appends do not tear — the compound operation is atomic at the owner")
    func concurrentAppendsDoNotTearLines() throws {
        try withTempDirectory { _ in
            let count = 200
            DispatchQueue.concurrentPerform(iterations: count) { i in
                DeviceLog.wc("line-\(i)-END")
            }
            let text = try String(contentsOf: DeviceLogFile.fileURL, encoding: .utf8)
            let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }

            // Scoped to this test's own markers, NOT to the file's total, and
            // that distinction is load-bearing. `directoryOverride` is
            // process-global, so while it is set every other suite's
            // `DeviceLog` calls land in this same file — a total-line count
            // measures the rest of the run, not this test. (Found by the full
            // gate on 2026-09-15: this assertion passed in isolation and failed
            // at 1542 cases. Serializing this suite orders its own tests and
            // does nothing about a sink every suite can reach — exactly the
            // distinction CLAUDE.md § Test Concurrency draws.)
            let mine = lines.filter { $0.contains("[WC] line-") }
            #expect(mine.count == count, """
            Expected \(count) of this test's own lines, got \(mine.count) — an append was lost.
            """)
            #expect(mine.allSatisfy { $0.hasSuffix("-END") }, """
            A line does not end where it should, so two appends interleaved.
            Each write is individually fine; it is the size-check → rotate →
            append sequence that must be atomic, which is why the lock is at the
            owner rather than on the callers.
            """)
        }
    }

    // MARK: - Unconditional by construction

    /// The behavioural tests above can only ever run in a debug build, so they
    /// cannot speak to what a TestFlight build writes. This is the mechanical
    /// assertion that the tee is not compiled out — the one property that
    /// matters for a reading taken from a shipping build.
    @Test("the tee is not build-gated — a TestFlight reading must carry the lines a debug one does")
    func theTeeIsNotBuildGated() throws {
        let source = try Self.appSource()
        guard let body = Self.deviceLogBody(in: source) else {
            throw GateFailure.anchorNotFound("enum DeviceLog {")
        }
        #expect(!body.contains("#if DEBUG"), """
        `DeviceLog` is build-gated. A device reading that exists only in a debug
        build cannot answer a question about the build that ships.
        """)
        #expect(body.contains("DeviceLogFile.append(category:"), """
        No tee call remains inside `enum DeviceLog`. Every category must write
        to the container file as well as to Logger.
        """)
    }

    @Test("the body matcher recognises the offender, the clean case, and degenerate input")
    func theBodyMatcherSelfTest() {
        let offender = "enum DeviceLog {\n    #if DEBUG\n    #endif\n}\n"
        #expect(Self.deviceLogBody(in: offender)?.contains("#if DEBUG") == true)

        let clean = "enum DeviceLog {\n    static func wc() {}\n}\n"
        #expect(Self.deviceLogBody(in: clean)?.contains("#if DEBUG") == false)

        // Degenerate shapes, and they are the reason this self-test exists.
        // A scanner's input is not what any test constructs — it is whatever
        // anyone writes next. A scanner that MIS-READS under-reports and a test
        // catches it; a scanner that TRAPS kills the test host and nothing
        // catches that (CLAUDE.md, 2026-08-25: 199 failures across 110 suites
        // from one inverted Range). This matcher builds no Range at all.
        #expect(Self.deviceLogBody(in: "") == nil)
        #expect(Self.deviceLogBody(in: "enum DeviceLog {") == nil)          // never closed
        #expect(Self.deviceLogBody(in: "\n}\n") == nil)                     // close, no open
        #expect(Self.deviceLogBody(in: "enum DeviceLogFile { }") == nil)    // near-miss name
    }

    // MARK: - Scanner

    /// Splits on markers rather than slicing by offset, so no `Range` is ever
    /// constructed and the inverted-range trap cannot be reproduced here.
    private static func deviceLogBody(in source: String) -> String? {
        let marker = "enum DeviceLog {"
        guard source.contains(marker),
              let afterOpen = source.components(separatedBy: marker).last else { return nil }
        let parts = afterOpen.components(separatedBy: "\n}")
        guard parts.count > 1 else { return nil }
        return parts.first
    }

    private static func appSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MemoryStream/App/MemoryStreamApp.swift")
        guard let src = try? String(contentsOf: url, encoding: .utf8), !src.isEmpty else {
            throw GateFailure.sourceNotFound(url.path)
        }
        return src
    }
}
