import Foundation

/// The visual register a `ClipAtomView` renders in. One prop, three
/// values — the single skin-switch defined by `Clip model · spec.md`
/// §1 (locked July 11 2026).
///
/// `.reflectiveCompact` is a **density** of the reflective register,
/// not a new axis: same `ClipDisplayModel`, different chrome (time-
/// only header + leading media glyph + first-line preview). If a
/// consumer wants a fourth value or a second axis (a `density`
/// prop separate from register), stop and flag it — that's the fork
/// signal the guardrail promises to catch (see spec §1 guardrail
/// paragraph).
enum ClipRegister: Equatable, Hashable, CaseIterable {
    /// Clips tab, session bench — SF Pro denser, ochre inclusion
    /// ring, offset timing, compact evidence, Retry link when
    /// failed.
    case operational
    /// Memory Detail Full stream — roomier chrome, full date · time
    /// · location header, named evidence
    /// (`Original recording · 0:42`).
    case reflective
    /// Memory Detail long-memory Compact index — SF Pro single-row
    /// density, time-only header + leading media glyph, first-line
    /// transcript preview, no evidence on the row (expanding
    /// swaps the container's row to `.reflective`).
    case reflectiveCompact
}
