import Testing
import Foundation
import CoreData
@testable import HiMem

/// **The instrument must outlive the latch.**
///
/// Reading #2 — cold-launch-to-first-record-visible against CloudKit's
/// ~17–21s per-zone setup floor — was void three times, and two of the three
/// reasons were `FirstImportState` owning the only observer:
///
/// 1. the arc was measured at `storageReady`, the wrong quantity (fixed 08-23);
/// 2. `begin`'s `guard phase == .importing` meant a relaunch logged nothing at
///    all, and the archive's silence was indistinguishable from "no import";
/// 3. the 3s fallback fired at **+3149ms** and `markComplete` removed the
///    observer, ~15s before CloudKit's setup would have had anything to say.
///
/// `CloudKitArcLog` exists so (2) and (3) cannot recur: it arms regardless of
/// phase and has no teardown path. These tests pin exactly that.
///
/// **Test-kind, stated honestly (ADR-050).** The format and behaviour cases are
/// **contract tests** — written alongside a new type, green on first run, so
/// they are mutation-verified rather than claimed as a red-first cycle. The one
/// genuine red is `theLaunchPathArmsTheArc`, which fails against real shipped
/// source until the wiring lands.
@MainActor
@Suite("CloudKitArcLog — the instrument must outlive the latch")
struct CloudKitArcLogTests {

    enum Failure: Error { case rootNotFound(String), walkFoundNoSource(String), unreadable(String) }

    /// Collects lines instead of writing to the device log.
    final class Spy {
        private(set) var lines: [String] = []
        func take(_ s: String) { lines.append(s) }
    }

    private func makeContainer() -> NSPersistentContainer {
        StorageService(inMemory: true).container
    }

    // MARK: - The load-bearing property: it outlives the latch

    /// **The 08-25 defect, as an assertion.** `FirstImportState` latching and
    /// tearing down its own observer must not silence the arc — that is the
    /// whole reason this is a second object.
    @Test func recordsAfterFirstImportStateHasCompleted() {
        let spy = Spy()
        let arc = CloudKitArcLog(sink: spy.take)
        arc.begin(container: makeContainer())

        // The latch closes and disarms itself, exactly as it does at +3s.
        let latch = FirstImportState(defaults: freshDefaults())
        latch.markComplete(cause: "3s fallback — no import event arrived")
        #expect(latch.phase == .complete)

        // CloudKit finally speaks, ~17s later. The arc must still be listening.
        arc.record(type: 0, succeeded: true, ended: true)
        #expect(arc.isArmed, "the arc must never disarm — that is its only guarantee")
        #expect(spy.lines.contains { $0.contains("setup") && $0.contains("ended ok") }, """
            The arc went silent after the latch completed. This is the 2026-08-25 \
            defect: markComplete removed the only observer at +3149ms, ~15s before \
            CloudKit's setup event, and the archive carried zero ck lines. \
            Lines seen: \(spy.lines)
            """)
    }

    /// **Reading #2's SECOND void.** `FirstImportState.begin` returns early when
    /// `himem.firstImportComplete` is already true, so its instrumentation is
    /// silent on relaunch — and a populated account, which is the only kind that
    /// has a floor, takes that branch. The arc must not inherit that guard.
    @Test func armsEvenWhenTheLatchIsAlreadyComplete() {
        let d = freshDefaults()
        d.set(true, forKey: "himem.firstImportComplete")
        let latch = FirstImportState(defaults: d)
        #expect(latch.phase == .complete, "precondition: the relaunch branch")

        let spy = Spy()
        let arc = CloudKitArcLog(sink: spy.take)
        arc.begin(container: makeContainer())

        #expect(arc.isArmed, """
            The arc refused to arm on a relaunch. That is the branch a populated \
            account actually takes, and it is where the ~17–21s floor lives.
            """)
        #expect(spy.lines.contains { $0.contains("armed") })
    }

    /// Never disarms — there is deliberately no `stop()`, so this is a property
    /// of the type's shape rather than of anyone remembering not to call one.
    @Test func staysArmedAcrossManyEvents() {
        let arc = CloudKitArcLog(sink: { _ in })
        arc.begin(container: makeContainer())
        for t in 0..<3 { arc.record(type: t, succeeded: true, ended: true) }
        #expect(arc.isArmed)
    }

    /// A re-entrant launch path must not produce a second observer, which would
    /// double every line and make the arc's own count a lie.
    @Test func beginIsIdempotent() {
        let spy = Spy()
        let arc = CloudKitArcLog(sink: spy.take)
        let c = makeContainer()
        arc.begin(container: c)
        arc.begin(container: c)
        #expect(spy.lines.filter { $0.contains("armed") }.count == 1)
    }

    /// Elapsed is measured from the arm, because the floor is
    /// cold-launch-relative. A zero here would silently make every reading
    /// describe an interval nobody asked about.
    @Test func elapsedIsMeasuredFromTheArm() {
        let spy = Spy()
        let arc = CloudKitArcLog(sink: spy.take)
        let t0 = Date()
        arc.begin(container: makeContainer(), now: t0)
        arc.record(type: 0, succeeded: true, ended: true, now: t0.addingTimeInterval(17.432))
        #expect(spy.lines.contains { $0.contains("+17432ms") }, "lines: \(spy.lines)")
    }

    // MARK: - The format

    @Test func lineNamesEachEventTypeRatherThanItsRawValue() {
        #expect(CloudKitArcLog.typeName(0) == "setup")
        #expect(CloudKitArcLog.typeName(1) == "import")
        #expect(CloudKitArcLog.typeName(2) == "export")
    }

    /// **Malformed input, per CLAUDE.md § Guard the Caller.** Apple may add a
    /// case; an instrument that traps on an unfamiliar value is worse than one
    /// that renders it.
    @Test func typeNameDoesNotTrapOnAnUnknownRawValue() {
        #expect(CloudKitArcLog.typeName(9) == "type9")
        #expect(CloudKitArcLog.typeName(-1) == "type-1")
    }

    /// `started` and `ended` are the two halves whose INTERVAL is the quantity
    /// this type exists to expose. Collapsing them loses the measurement.
    @Test func lineDistinguishesStartedFromEnded() {
        let started = CloudKitArcLog.line(type: 0, succeeded: false, ended: false, elapsedMs: 12, error: nil)
        let ended = CloudKitArcLog.line(type: 0, succeeded: true, ended: true, elapsedMs: 17432, error: nil)
        #expect(started.contains("started"))
        #expect(!started.contains("FAILED"), """
            A start line must not report success or failure — neither has \
            happened yet, and "succeeded=false" on a start reads as a failure.
            """)
        #expect(ended.contains("ended ok"))
        #expect(started.contains("+12ms") && ended.contains("+17432ms"))
    }

    @Test func aFailedEventSaysSoAndCarriesItsError() {
        struct Boom: LocalizedError { var errorDescription: String? { "quota exceeded" } }
        let s = CloudKitArcLog.line(type: 1, succeeded: false, ended: true, elapsedMs: 5, error: Boom())
        #expect(s.contains("ended FAILED"))
        #expect(s.contains("quota exceeded"))
    }

    // MARK: - The wiring (the genuine red)

    /// **Verified red before the wiring landed.** An arc nothing arms logs
    /// nothing, and would look identical in the archive to an arc that armed and
    /// heard silence — the exact ambiguity this type exists to remove.
    @Test func theLaunchPathArmsTheArc() throws {
        let sites = try Self.armCallSites()
        #expect(!sites.isEmpty, """
            Nothing calls `CloudKitArcLog.shared.begin(container:)`. The type is \
            inert, and its silence in a device archive is indistinguishable from \
            CloudKit having said nothing — which is precisely the reading #2 \
            failure it was built to prevent.
            """)
    }

    /// Guards the guard: the matcher must be able to see a real call and must
    /// not be fooled by prose. A scanner that matches nothing reports a clean
    /// codebase forever.
    @Test func theWiringScannerCanSeeItsTarget() {
        #expect(Self.isArmCall("CloudKitArcLog.shared.begin(container: StorageService.shared.container)"))
        #expect(!Self.isArmCall("/// call `CloudKitArcLog.shared.begin(` at launch"), "prose is not a call")
        #expect(!Self.isArmCall(""), "a degenerate line must not match")
    }

    // MARK: - No teardown, no coupling

    /// The two properties that make this a *decoupled* observer rather than a
    /// second copy of the latch. Both are absences, so only a source read can
    /// see them — a behavioural test cannot prove that a teardown path is
    /// missing, only that it was not taken.
    @Test func theArcHasNoTeardownPathAndNoCouplingToTheLatch() throws {
        let src = try Self.arcSource()
        let code = src.components(separatedBy: "\n")
            .filter { l in
                let t = l.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("//") && !t.hasPrefix("///")
            }
            .joined(separator: "\n")

        #expect(!code.contains("removeObserver"), """
            CloudKitArcLog removes its observer somewhere. That is the 08-25 \
            defect reintroduced in the object built to prevent it: the arc's \
            length must be a property of CloudKit, not of us.
            """)
        #expect(!code.contains("markComplete"), "the arc must never latch")
        #expect(!code.contains("FirstImportState"), """
            The arc references FirstImportState. Any read couples the \
            instrument's lifetime or behaviour to the latch's deadline, which \
            is the thing that made reading #2 void.
            """)
    }

    /// **Guards the guard, and this one is not hypothetical.** The check above
    /// passes *only* because it strips comment lines: `CloudKitArcLog`'s own
    /// class doc explains the defect by naming `removeObserver`,
    /// `markComplete` and `FirstImportState` in prose. So the comment filter is
    /// load-bearing **today**, not against some future edit — and a scanner
    /// "simplified" to a raw `contains` would fail on correct code, while one
    /// that stopped stripping properly would pass on broken code.
    ///
    /// Pinning both directions means the filter cannot be removed silently.
    @Test func theCouplingScannerDependsOnStrippingComments() throws {
        let raw = try Self.arcSource()
        for token in ["removeObserver", "markComplete", "FirstImportState"] {
            #expect(raw.contains(token), """
                The class doc no longer mentions \(token). That is fine in \
                itself, but this self-test exists to prove the comment filter \
                is what makes the guard pass — re-point it at whatever prose \
                now carries the explanation, don't delete it.
                """)
        }
        let code = raw.components(separatedBy: "\n")
            .filter { l in
                let t = l.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("//") && !t.hasPrefix("///")
            }
            .joined(separator: "\n")
        #expect(!code.contains("FirstImportState"), "the filter must remove prose, not code")
    }

    // MARK: - Scanners

    static func isArmCall(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.hasPrefix("//"), !t.hasPrefix("///") else { return false }
        return t.contains("CloudKitArcLog.shared.begin(")
    }

    /// Walks production source. **Throws if it reaches no source** rather than
    /// returning an empty result, so the guard cannot pass by matching nothing.
    static func armCallSites() throws -> [String] {
        var sites: [String] = []
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MemoryStream")
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { throw Failure.rootNotFound(root.path) }
        var sawAnySwift = false
        for case let url as URL in walker where url.pathExtension == "swift" {
            sawAnySwift = true
            guard url.lastPathComponent != "CloudKitArcLog.swift" else { continue }  // the declaration
            guard let src = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (i, line) in src.components(separatedBy: "\n").enumerated()
            where isArmCall(line) {
                sites.append("\(url.lastPathComponent):\(i + 1)")
            }
        }
        guard sawAnySwift else { throw Failure.walkFoundNoSource(root.path) }
        return sites
    }

    static func arcSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MemoryStream/Services/Storage/CloudKitArcLog.swift")
        guard let s = try? String(contentsOf: url, encoding: .utf8) else {
            throw Failure.unreadable(url.path)
        }
        return s
    }
}

/// Isolated defaults so a test never reads or writes the real install's state.
@MainActor
private func freshDefaults() -> UserDefaults {
    let d = UserDefaults(suiteName: "CloudKitArcLogTests-\(UUID().uuidString)")!
    d.removePersistentDomain(forName: d.description)
    return d
}
