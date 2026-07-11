import Testing
import Foundation
import SwiftUI
@testable import HiMem

/// Money tests for `ClipCollection` — the shared composition +
/// optional-body wrapper for session cards, memory cards, and
/// Memory Detail's expanded body.
///
/// Slice 5 of the Clip Model convergence
/// (`docs/architecture/2026-07-11-clip-model-convergence-plan.md`).
/// Most of the value is a compile-time contract (the three-slot
/// generic View + the two body modes); the runtime value is
/// composition-derives-from-clips and the mode-driven atom
/// rendering. Both are lockable at value-level.
@Suite(.serialized)
struct ClipCollectionTests {

    private func voice(capturedAt: Date, transcript: String = "hi") -> ClipDisplayModel {
        ClipDisplayModel(
            id: UUID(),
            media: .voice,
            capturedAt: capturedAt,
            sessionStart: nil,
            placeName: nil,
            content: .transcript(transcript),
            evidence: .audio(duration: 3),
            thumbnailKey: nil,
            failed: false
        )
    }

    /// `ClipCollection.compositionSnapshot(clips:)` — the exposed
    /// helper the view uses to compute composition. Ensures the
    /// collection's summary derives from the same
    /// `CompositionModel.from(clips:)` computation Slice 4 tested.
    /// No drift between what the collection displays and what a
    /// bare composition would show for the same clips.
    @Test func composition_snapshot_matches_bare_composition_from() {
        let start = Date(timeIntervalSince1970: 1_720_000_000)
        let clips = [
            voice(capturedAt: start, transcript: "one two"),
            voice(capturedAt: start.addingTimeInterval(60), transcript: "three four"),
        ]
        let a = ClipCollection<EmptyView, EmptyView>.compositionSnapshot(clips: clips)
        let b = CompositionModel.from(clips: clips)
        #expect(a == b)
    }

    /// The two body modes are the only two the spec defines
    /// (`Clip model · spec.md` §Collection skeleton). Compile-time
    /// exhaustive switch guards against a `.compact` third mode
    /// creeping in as a fork.
    @Test func body_mode_enum_has_only_collapsed_and_expanded() {
        for mode in [ClipCollectionBodyMode.collapsed, .expanded] {
            switch mode {
            case .collapsed, .expanded: break
                // Exhaustive switch — new cases would break this test.
            }
        }
    }

    /// Consumers derive the mode from a memory's collapsed/expanded
    /// state or a session's default. The mapping is trivial; this
    /// test locks the intent.
    @Test func body_mode_from_isExpanded_bool() {
        #expect(ClipCollectionBodyMode.fromExpanded(true) == .expanded)
        #expect(ClipCollectionBodyMode.fromExpanded(false) == .collapsed)
    }
}
