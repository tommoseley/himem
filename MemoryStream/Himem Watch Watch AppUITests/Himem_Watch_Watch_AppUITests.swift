import XCTest

/// **This target is deliberately empty of tests, and deliberately still in the
/// gate (ruled 2026-08-19).**
///
/// It carried three Xcode template stubs — `testExample()` (launched the app and
/// asserted nothing), `testLaunchPerformance()` (measured), and `testLaunch()`
/// (attached a screenshot). All three passed unconditionally, so they inflated
/// the watch gate from 34 to 37 with three cases that could not fail. That is
/// the `#expect(true)` shape: a number someone reads as coverage, backed by
/// nothing. They were deleted.
///
/// **Why this file survives them.** A UI test target with no compiled source
/// builds an `.xctest` bundle with **no executable**, and the runner then fails
/// with *"Failed to load the test bundle … its executable couldn't be located"*
/// — a System Failure that reddens the gate without naming a defect. One
/// compiled class is the minimum that keeps the bundle loadable, so this class
/// exists to hold the target open, not to test anything.
///
/// **The July `-skip-testing:` ruling (F6c clause 2) is retired.** It excluded
/// this target because its runner failed to install on every invocation
/// (`Unknown application display identifier`). Under Xcode 27 / watchOS 26.5 it
/// installs and runs, so the exclusion is stale — the target is back in the
/// gate, contributing zero cases rather than three false ones.
///
/// A real watch UI test belongs here when one is written. Until then the
/// honest state is an empty target that runs, not a full one that lies.
final class Himem_Watch_Watch_AppUITests: XCTestCase {}
