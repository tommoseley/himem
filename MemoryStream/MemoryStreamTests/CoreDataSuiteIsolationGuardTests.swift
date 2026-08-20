import Testing
import Foundation

/// **B24 — every suite that builds a Core Data stack must run on the main
/// actor.**
///
/// `StorageService(inMemory:).viewContext` is an `NSMainQueueConcurrencyType`
/// context. Swift Testing runs `@Test` bodies on the cooperative pool, so a
/// suite without `@MainActor` calls `save()` from a non-main thread. Core Data
/// raises an ObjC exception, `_XCTTerminateHandler` turns it into `abort()`,
/// and **the test host dies** — taking every test scheduled after it down as
/// collateral.
///
/// That is B24, which presented three times as 67, then 87, then 59 "failures"
/// across suites with no relationship to the change under test. The crash
/// report from the third occurrence
/// (`HiMem-2026-08-19-205033.ips`) named the owner outright:
///
/// ```
///   com.apple.root.user-initiated-qos.cooperative   ← not main
///     NSManagedObjectContext save:
///     BenchMediaKeyCollapseTests.makeRef(in:at:)
///     _XCTTerminateHandler → abort → SIGABRT
/// ```
///
/// **The convention was already near-universal and therefore invisible when it
/// lapsed**: 52 of 57 such suites declared `@MainActor`; the five that did not
/// included the crashing owner. B24's original entry suspected exactly those
/// suites for the wrong reason — "more parallel Core Data stacks" — when the
/// discriminator was simply the missing annotation.
///
/// **Why a source scan rather than a behavioural test.** The failure is a host
/// abort, not a wrong answer: it cannot be asserted from inside the process it
/// kills, and it is intermittent (it depends on which pool thread runs the
/// body). CLAUDE.md sanctions a mechanical source-level assertion for exactly
/// this shape, on three conditions, all met below: anchored on real files, a
/// self-test proving the matcher recognises the defect, and a throw if the walk
/// reaches no source — **a guard that passes by matching nothing is the failure
/// mode this class of test has already shipped once.**
struct CoreDataSuiteIsolationGuardTests {

    /// Walks the test sources. Throws rather than returning empty, so the guard
    /// cannot pass by finding nothing.
    private func testSourceFiles() throws -> [(name: String, text: String)] {
        // Anchored on this file's own location, so a move cannot silently empty
        // the walk.
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let urls = try FileManager.default.contentsOfDirectory(
            at: here, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }

        guard urls.count > 20 else {
            throw GuardError.walkFoundNothing(
                "expected the MemoryStreamTests sources at \(here.path); found \(urls.count) .swift files"
            )
        }
        return try urls.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    enum GuardError: Error, CustomStringConvertible {
        case walkFoundNothing(String)
        var description: String {
            switch self { case let .walkFoundNothing(m): return "guard reached no source — \(m)" }
        }
    }

    /// Does this source build a Core Data stack, and does it declare
    /// `@MainActor` at file scope?
    private func buildsCoreDataStack(_ text: String) -> Bool {
        text.contains("StorageService(inMemory: true)")
    }

    private func declaresMainActor(_ text: String) -> Bool {
        text.split(separator: "\n").contains { $0.hasPrefix("@MainActor") }
    }

    /// **The guard.**
    @Test
    func everySuiteBuildingACoreDataStackRunsOnTheMainActor() throws {
        let sources = try testSourceFiles()

        // **This file excludes ITSELF, and nothing else.** Its self-test below
        // embeds the literal `StorageService(inMemory: true)` as a fixture, so
        // the matcher matches this source — which correctly carries no
        // `@MainActor`, because it builds no Core Data stack. Derived from
        // `#filePath` rather than typed, so a rename cannot turn the exclusion
        // into a silent hole.
        //
        // The count is asserted so this can never grow into a general opt-out
        // list — an opt-out is how the gap hides (CLAUDE.md § Guard the
        // Caller). One file, this one, forever.
        let selfName = URL(fileURLWithPath: #filePath).lastPathComponent
        let scanned = sources.filter { $0.name != selfName }
        #expect(sources.count - scanned.count == 1, "exactly one file is excluded — this one")

        let coreData = scanned.filter { buildsCoreDataStack($0.text) }

        #expect(coreData.count > 40, "the matcher must actually be finding these suites — got \(coreData.count)")

        let offenders = coreData.filter { !declaresMainActor($0.text) }.map(\.name).sorted()
        #expect(
            offenders.isEmpty,
            "these suites build an NSMainQueueConcurrencyType viewContext without @MainActor, so save() runs on the cooperative pool and aborts the HOST — every test after it fails as collateral (B24): \(offenders.joined(separator: ", "))"
        )
    }

    /// **The self-test: the matcher must recognise the known offender.**
    ///
    /// Without this, a matcher that silently stopped detecting either half
    /// would report an empty offender list and read as green. This reconstructs
    /// `BenchMediaKeyCollapseTests` as it actually was when it crashed the host.
    @Test
    func theMatcherRecognisesTheShapeThatCrashedTheHost() {
        let offending = """
        import Testing
        @testable import HiMem

        struct BenchMediaKeyCollapseTests {
            func makeRef() { let ctx = StorageService(inMemory: true).viewContext }
        }
        """
        #expect(buildsCoreDataStack(offending), "must see the Core Data stack")
        #expect(!declaresMainActor(offending), "must see the missing annotation")

        let fixed = offending.replacingOccurrences(
            of: "struct BenchMediaKeyCollapseTests",
            with: "@MainActor\nstruct BenchMediaKeyCollapseTests"
        )
        #expect(declaresMainActor(fixed), "and must see the fix, or it would flag every suite forever")
    }

    /// A suite that touches no Core Data is not the guard's business — so the
    /// rule cannot be satisfied by flagging everything.
    @Test
    func aSuiteWithNoCoreDataStackIsNotFlagged() {
        let unrelated = """
        import Testing
        struct LinkifyTests { func urls() {} }
        """
        #expect(!buildsCoreDataStack(unrelated))
    }
}
