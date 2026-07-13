import SwiftUI

/// Which body a `ClipCollection` renders. Two modes only:
///
///   - **Collapsed** — composition summary only, no atom body.
///     Used by memory cards on the Memories list (title, summary,
///     and composition; body deferred until the user opens the
///     memory detail).
///   - **Expanded** — composition summary + full atom list. Used
///     by session cards (body is the clips triage view) and
///     Memory Detail Full stream (body is the chronological read).
///
/// If a consumer wants a third mode ("compact index"), that's a
/// container concern (Memory Detail's long-memory Compact view
/// owns single-open accordion state per `Memory Detail ·
/// long-memory navigation.md`) — not a body mode on `ClipCollection`.
/// Adding a `.compact` case here is a fork signal.
enum ClipCollectionBodyMode: Equatable, Hashable, CaseIterable {
    case collapsed
    case expanded

    static func fromExpanded(_ isExpanded: Bool) -> ClipCollectionBodyMode {
        isExpanded ? .expanded : .collapsed
    }
}

/// The shared collection skeleton: **composition summary + optional
/// atom body**, with slots for a derived-layer header and an actions
/// row. Session cards, memory cards, and Memory Detail Full all
/// render through this component per `Clip model · spec.md`
/// §Collection skeleton (July 11 lock).
///
/// Slice 5 of the Clip Model convergence
/// (`docs/architecture/2026-07-11-clip-model-convergence-plan.md`).
/// R1's SwiftUI-native slot design: `@ViewBuilder` closures for
/// `derived` and `actions`, no protocol soup, no associated types
/// fighting `some View` inference. Empty consumers pass
/// `EmptyView()` in the slot — the compiler drops the branch.
///
/// The composition is derived from `clips` via
/// `CompositionModel.from(clips:)` — same code path Slice 4 tested.
/// Consumers hand a `[ClipDisplayModel]` and this collection makes
/// the summary + body render match.
struct ClipCollection<Derived: View, Actions: View>: View {

    let clips: [ClipDisplayModel]
    let register: ClipRegister
    let bodyMode: ClipCollectionBodyMode

    /// Derived-layer slot. Session cards pass `EmptyView()` (no
    /// derived layer — a session is a collection *without* derived
    /// data). Memory cards + Memory Detail pass the AI title,
    /// summary, topic chips, and mentions.
    let derived: () -> Derived

    /// Actions slot at the bottom of the body. Session cards pass
    /// the "Start a Memory" pill + "Delete session" button. Memory
    /// Detail passes `EmptyView()` (Memory Detail's actions live on
    /// the containing view — bottom Delete + reorganize).
    let actions: () -> Actions

    /// Per-atom callback for tapping the content area (transcript,
    /// thumbnail, description). Slice 6-9 wire this up per surface;
    /// nil = the atom's content is inert.
    var onTapClip: ((ClipDisplayModel) -> Void)? = nil

    var body: some View {
        let composition = CompositionModel.from(clips: clips)
        VStack(alignment: .leading, spacing: derivedSpacing) {
            derived()
            ClipComposition(model: composition, register: register)
            if bodyMode == .expanded, !clips.isEmpty {
                VStack(spacing: bodySpacing) {
                    ForEach(clips) { clip in
                        ClipAtomView(
                            model: clip,
                            register: register,
                            onTapContent: onTapClip.map { fn in { fn(clip) } }
                        )
                        if clip.id != clips.last?.id {
                            ClipDivider()
                        }
                    }
                }
            }
            actions()
        }
    }

    private var derivedSpacing: CGFloat {
        switch register {
        case .operational:      return 10
        case .reflective:       return 14
        case .reflectiveCompact: return 6
        }
    }

    private var bodySpacing: CGFloat {
        switch register {
        case .operational:      return 12
        case .reflective:       return 18
        case .reflectiveCompact: return 4
        }
    }

    // MARK: - Testability

    /// Exposed so tests can lock the invariant that
    /// `ClipCollection`'s summary derives from
    /// `CompositionModel.from(clips:)` — no view-side arithmetic
    /// forks the composition contract.
    static func compositionSnapshot(clips: [ClipDisplayModel]) -> CompositionModel {
        CompositionModel.from(clips: clips)
    }
}

/// Hairline divider between atoms in the expanded body. Extracted
/// so consumers can reuse the exact stroke/color without redrawing
/// the primitive.
struct ClipDivider: View {
    var body: some View {
        Rectangle()
            .fill(Crucible.Color.hairline)
            .frame(height: 0.5)
    }
}
