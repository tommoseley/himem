import Testing
import Foundation
import CoreData
@testable import HiMem

/// F22 · the guard for the false empty state.
///
/// This fix only ever executes on a **fresh install** — the path with the least
/// device history and no repeatable dogfood. Tom cannot reinstall repeatedly to
/// test it, and Judi's next reinstall is a 45-day trip. So this suite is not the
/// durable half of the fix, it is the **only** half, and it must prove the state
/// machine end-to-end rather than merely that surfaces read a flag.
///
/// The lie being guarded: a list rendering "you have nothing" from a local store
/// that has not finished importing. Zero-because-none and
/// zero-because-not-looked-yet are different facts.
@MainActor
@Suite(.serialized)
struct FirstImportStateTests {

    private func freshDefaults() -> UserDefaults {
        let suite = "himem.tests.firstImport.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    // MARK: - The state machine

    /// THE MONEY ASSERTION. A fresh install starts in `importing`, and in that
    /// phase no surface may claim to be empty.
    @Test func freshInstall_startsImporting_andForbidsEmptyClaims() {
        let s = FirstImportState(defaults: freshDefaults())
        #expect(s.phase == .importing, "a fresh install has not finished looking yet")
        #expect(s.mayAssertEmpty == false,
                "asserting empty mid-import is the false-empty-state defect (F22)")
    }

    /// The first import success latches, and counts become sayable.
    @Test func firstSuccess_latchesComplete() {
        let s = FirstImportState(defaults: freshDefaults())
        s.markComplete()
        #expect(s.phase == .complete)
        #expect(s.mayAssertEmpty, "after the first import, an empty list is honest")
    }

    /// **The multi-batch reality.** `.import .succeeded` is not terminal —
    /// CloudKit delivers in batches and fires repeatedly. Completion is the
    /// FIRST success, latched; later batches may add content afterwards and
    /// that is fine. A list that grows is not a lie; a list that claims empty
    /// is. Deliberately does NOT attempt to detect "all batches done", which is
    /// unknowable and would strand users in a permanent "still fetching".
    @Test func laterBatches_doNotReopenTheAmbiguity() {
        let s = FirstImportState(defaults: freshDefaults())
        s.markComplete()
        s.markComplete()
        s.markComplete()
        #expect(s.phase == .complete, "the latch is one-way; repeated successes are no-ops")
    }

    /// **The fallback is not optional.** No iCloud account, no network, or
    /// simply nothing to import means no event ever arrives. Without this the
    /// user waits forever on a screen that will never resolve.
    @Test func noEventEverArrives_fallbackStillLatches() async throws {
        let s = FirstImportState(defaults: freshDefaults())
        // A bare container is enough: the fallback path is what's under test,
        // and it must fire precisely BECAUSE no CloudKit event ever arrives.
        let container = NSPersistentContainer(name: "MemoryStream")
        s.begin(container: container, timeout: 0.05)
        #expect(s.phase == .importing, "still importing immediately after begin")
        try await Task.sleep(nanoseconds: 250_000_000)
        #expect(s.phase == .complete,
                "with no CloudKit event, the timeout must resolve the state — never an eternal spinner")
    }

    /// Persistence is per install: once complete, always complete. A relaunch
    /// on day 40 shows the truth instantly rather than re-entering ambiguity.
    @Test func completionPersistsAcrossLaunches() {
        let d = freshDefaults()
        FirstImportState(defaults: d).markComplete()
        let relaunched = FirstImportState(defaults: d)
        #expect(relaunched.phase == .complete,
                "a later launch must not re-show the importing state")
        #expect(relaunched.mayAssertEmpty)
    }

    /// A fresh install on a DIFFERENT device is still a fresh install — the
    /// flag is per-install, not synced. Guards against someone "helpfully"
    /// moving it to CloudKit, which would make a new device skip the very
    /// state it needs.
    @Test func aDifferentInstallStartsImportingAgain() {
        FirstImportState(defaults: freshDefaults()).markComplete()
        let otherDevice = FirstImportState(defaults: freshDefaults())
        #expect(otherDevice.phase == .importing,
                "per-install by design: a new device has its own first import to wait for")
    }

    // MARK: - Surface guard

    /// THE F22 SURFACE GUARD. No surface may render an empty state without
    /// consulting the owner. Source-scanned because the invariant is a property
    /// of how views are written, and nothing else in the suite can observe it.
    ///
    /// Per the F17 lesson this guard self-tests below: a scanner that matches
    /// nothing would report a clean codebase forever.
    @Test func noSurfaceAssertsEmptyWithoutConsultingTheOwner() throws {
        let offenders = try Self.emptyStateSurfaces().filter { !$0.consultsOwner }
        #expect(
            offenders.isEmpty,
            """
            Surface(s) render an empty state without consulting `FirstImportState`:
            \(offenders.map { "  • \($0.file):\($0.line)" }.joined(separator: "\n"))

            On a fresh install these claim "you have nothing" while CloudKit is \
            still importing. Gate the empty branch on `mayAssertEmpty`.

            Exempt only where the store is genuinely device-local (the Clips \
            manifest half) — and that exemption must be STATED in the code, not \
            left for a future reader to re-derive.
            """
        )
    }

    /// **The scanner must see BOTH shapes.** Its first version inspected only a
    /// window around a `var empty…State` declaration, which had two blind spots
    /// baked in (F23 audit, Class 4 #3):
    ///
    /// 1. A named empty-state view whose window contains no `isEmpty` — the
    ///    branch lives in the *caller* — scored compliant forever
    ///    (`AddExistingClipsSheet:109`).
    /// 2. Inline empty-state renders had no declaration to anchor on and were
    ///    invisible entirely (`ManageTopicsSheet`, `ManageMentionsSheet`,
    ///    `AddMemoryToProjectSheet`, `RecycleBinView`, …).
    ///
    /// It saw five surfaces and judged four, under a doc claiming seven. Both
    /// shapes are covered below, and both are self-tested here.
    @Test func scannerFlagsAnUngatedEmptyState() {
        // Shape 1 — a named empty-state view. The DECLARATION is the claim, so
        // it must consult or be exempt whether or not `isEmpty` is in view.
        #expect(Self.isUngated(kind: .namedEmptyStateView, block: """
        private var emptyMemoriesState: some View {
            if viewModel.filteredEntries.isEmpty {
                Text("No memories yet")
            }
        }
        """), "an ungated empty state must be flagged — otherwise this guard guards nothing")

        #expect(Self.isUngated(kind: .namedEmptyStateView, block: """
        private var emptyState: some View {
            VStack { Text("No unconnected clips") }
        }
        """), "blind spot 1: no `isEmpty` in the window is not evidence of a gate")

        #expect(!Self.isUngated(kind: .namedEmptyStateView, block: """
        private var emptyMemoriesState: some View {
            if firstImport.mayAssertEmpty, viewModel.filteredEntries.isEmpty {
                Text("No memories yet")
            }
        }
        """), "consulting the owner is the fix and must not be flagged")

        // Shape 2 — an inline branch that renders. Invisible to the old rule.
        #expect(Self.isUngated(kind: .inlineEmptyBranch, block: """
        if available.isEmpty {
            Text("Your library is empty. Add a topic above to get started.")
        }
        """), "blind spot 2: inline empty-state renders are surfaces too")

        #expect(!Self.isUngated(kind: .inlineEmptyBranch, block: """
        // F22 EXEMPT: the manifest is sandbox-local and genuinely empty on a
        // new device — nothing to import, so no ambiguity to resolve.
        if clips.isEmpty { Text("Nothing new") }
        """), "a stated exemption is honoured; an unstated one is not")
    }

    /// The **non-empty companion** the sibling scanners have and this one
    /// lacked. A walk that matches nothing reports a clean codebase forever —
    /// which is exactly how "4 of 7" hid a wrong denominator.
    @Test func theScannerActuallySeesTheKnownSurfaces() throws {
        let surfaces = try Self.emptyStateSurfaces()
        #expect(surfaces.count >= 25,
                "the union rule finds ~34 sites; a sudden collapse means the walk broke, not that the app got simpler")
        let files = Set(surfaces.map(\.file))
        // One representative per shape and per area — named, inline, and the
        // two that were invisible before.
        for expected in ["JournalView.swift", "AddExistingClipsSheet.swift",
                         "ManageTopicsSheet.swift", "RecycleBinView.swift",
                         "ProjectListView.swift"] {
            #expect(files.contains(expected), "\(expected) must be in view of the scanner")
        }
        #expect(surfaces.contains { $0.kind == .namedEmptyStateView })
        #expect(surfaces.contains { $0.kind == .inlineEmptyBranch })
    }

    // MARK: - The owner is actually wired

    /// The F23 audit's first Tier-1 finding against this very file: the doc
    /// asserted "the one fact every surface reads before it claims to be empty"
    /// while there were **zero production readers**. A reader would have
    /// believed F22 was fixed when the fresh-install path was unchanged.
    ///
    /// Two halves, because either one alone is a dead contract: something must
    /// *end* the importing phase, and something must *ask*.
    @Test func theOwnerIsReachableFromProduction() throws {
        let (begins, readers) = try Self.productionUses()
        #expect(!begins.isEmpty, """
            Nothing calls `FirstImportState.begin(container:)`. Without it the \
            phase never ends: no CloudKit observer, no fallback, and every \
            gated surface stays silent forever.
            """)
        #expect(readers.count >= 8, """
            Only \(readers.count) production site(s) read `mayAssertEmpty`. The \
            F22 survey put ~14 surfaces behind this owner; a collapse means \
            surfaces were un-gated, not that the app got smaller. Sites: \
            \(readers.sorted().joined(separator: ", "))
            """)
    }

    /// Guards the guard: the matcher must be able to see each use.
    @Test func theReachabilityScannerCanSeeItsTargets() {
        #expect(Self.isBeginCall("FirstImportState.shared.begin(container: StorageService.shared.container)"))
        #expect(!Self.isBeginCall("/// call `begin(container:)` at launch"), "prose is not a call")
        #expect(Self.isOwnerRead("if items.isEmpty, firstImport.mayAssertEmpty {"))
        #expect(!Self.isOwnerRead("// gated on firstImport.mayAssertEmpty"), "a comment is not a read")
    }

    static func isBeginCall(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.hasPrefix("//"), !t.hasPrefix("///") else { return false }
        return t.contains("FirstImportState.shared.begin(")
    }

    static func isOwnerRead(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.hasPrefix("//"), !t.hasPrefix("///") else { return false }
        return t.contains("mayAssertEmpty")
    }

    /// - Returns: `(begin call sites, files reading `mayAssertEmpty`)`.
    static func productionUses() throws -> ([String], Set<String>) {
        var begins: [String] = []
        var readers: Set<String> = []
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MemoryStream")
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { throw Failure.rootNotFound(root.path) }
        var sawAnySwift = false
        for case let url as URL in walker where url.pathExtension == "swift" {
            sawAnySwift = true
            guard url.lastPathComponent != "FirstImportState.swift" else { continue }  // the declaration
            guard let src = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (i, line) in src.components(separatedBy: "\n").enumerated() {
                if isBeginCall(line) { begins.append("\(url.lastPathComponent):\(i + 1)") }
                if isOwnerRead(line) { readers.insert(url.lastPathComponent) }
            }
        }
        guard sawAnySwift else { throw Failure.walkFoundNoSource(root.path) }
        return (begins, readers)
    }

    // MARK: - Scanner

    enum SurfaceKind: Equatable { case namedEmptyStateView, inlineEmptyBranch }
    struct Surface { let file: String; let line: Int; let kind: SurfaceKind; let consultsOwner: Bool }

    /// A surface is ungated when it neither consults the owner nor carries an
    /// explicit `F22 EXEMPT` note stating why the collection cannot come from
    /// an unimported store.
    ///
    /// The two shapes differ in one respect only: for an **inline branch** the
    /// `isEmpty` test is the claim, so a block with no `isEmpty` is not a
    /// surface at all; for a **named empty-state view** the declaration itself
    /// is the claim, and requiring `isEmpty` in the window is precisely the
    /// blind spot that scored `AddExistingClipsSheet:109` compliant forever.
    static func isUngated(kind: SurfaceKind, block: String) -> Bool {
        if kind == .inlineEmptyBranch, !block.contains("isEmpty") { return false }
        if block.contains("mayAssertEmpty") || block.contains("FirstImportState")
            || block.contains("firstImport") { return false }
        if block.contains("F22 EXEMPT") { return false }
        return true
    }

    /// True when the line is an `if` / `else if` whose condition tests
    /// emptiness **positively** — `!xs.isEmpty` is a non-empty branch and says
    /// nothing about an unimported store. The negation test walks back over the
    /// expression rather than pattern-matching a fixed shape, so
    /// `!s.trimmingCharacters(in: .whitespaces).isEmpty` is recognised too.
    static func isPositiveEmptinessBranch(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.hasPrefix("//"), !t.hasPrefix("///") else { return false }
        guard let condRange = t.range(of: #"^(\}\s*)?(else\s+)?if\s+"#, options: .regularExpression)
        else { return false }
        let cond = String(t[condRange.upperBound...])
        guard cond.contains("isEmpty") else { return false }
        let chars = Array(cond)
        let expr = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._()[]:, \"?$")
        var idx = cond.startIndex
        while let found = cond.range(of: "isEmpty", range: idx..<cond.endIndex) {
            var j = cond.distance(from: cond.startIndex, to: found.lowerBound) - 1
            while j >= 0, expr.contains(chars[j]) { j -= 1 }
            if j < 0 || chars[j] != "!" { return true }   // a positive test
            idx = found.upperBound
        }
        return false
    }

    /// A block "renders" when it puts something on screen. This is what keeps
    /// pure logic (`if head.isEmpty { return "" }`) out of the count without
    /// relaxing the discriminator on anything that actually speaks to the user.
    static func rendersSomething(_ block: String) -> Bool {
        ["Text(", "Label(", "Image(", "ContentUnavailableView", "emptyState", "EmptyState"]
            .contains { block.contains($0) }
    }

    static func emptyStateSurfaces() throws -> [Surface] {
        var out: [Surface] = []
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MemoryStream").appendingPathComponent("Views")
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { throw Failure.rootNotFound(root.path) }
        var sawAnySwift = false
        for case let url as URL in walker where url.pathExtension == "swift" {
            sawAnySwift = true
            guard let src = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = src.components(separatedBy: "\n")
            for (i, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let kind: SurfaceKind
                if trimmed.hasPrefix("//") {
                    continue
                } else if line.range(of: #"var empty[A-Za-z]*State"#, options: .regularExpression) != nil {
                    kind = .namedEmptyStateView
                } else if isPositiveEmptinessBranch(line),
                          rendersSomething(lines[i..<min(i + 14, lines.count)].joined(separator: "\n")) {
                    kind = .inlineEmptyBranch
                } else {
                    continue
                }
                // Look back far enough to catch a preceding `F22 EXEMPT` note
                // or the `if` that gates a named view from just above it.
                let start = max(0, i - 6)
                let block = lines[start..<min(i + 20, lines.count)].joined(separator: "\n")
                out.append(Surface(file: url.lastPathComponent,
                                   line: i + 1,
                                   kind: kind,
                                   consultsOwner: !isUngated(kind: kind, block: block)))
            }
        }
        // Proves the walk reached source — the `fcb378b` pattern. Without it
        // this guard can pass by matching nothing, which is the failure mode it
        // exists to prevent.
        guard sawAnySwift else { throw Failure.walkFoundNoSource(root.path) }
        return out
    }

    enum Failure: Error { case rootNotFound(String), walkFoundNoSource(String) }
}
