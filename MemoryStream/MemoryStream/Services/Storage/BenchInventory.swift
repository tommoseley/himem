import Foundation

/// A bench-backing row reduced to what composition needs. Value-typed so the
/// rules below are testable without Core Data — the view copies four fields
/// off a `MediaReference` at the boundary and nothing downstream asks which
/// backing a thing has.
struct BenchRefDescriptor: Equatable {
    let id: UUID
    let kind: BenchClipItem.Kind
    let createdAt: Date?
    let rollGroupId: UUID?
}

/// **The two-store boundary, as a pure function** (C2 rebuild step 2).
///
/// The bench is backed by two stores: the device-local manifest (`InboxClip`,
/// voice only) and CloudKit-synced `MediaReference`s of every kind. Review
/// state lives in two places to match — `InboxClip.reviewed` on the manifest
/// row, and the per-device `BenchClipReviewStore` for refs.
///
/// **This is the wiring shape that has been the defect every time.** It is
/// isolated here, and tested behaviourally rather than by inspection, because
/// if the resolution is wrong the New lens is wrong and the failure is
/// silent — nothing crashes, a clip is simply in the wrong lens.
///
/// The rules are inherited verbatim from `ArrivedClipMaterializer`, which
/// this replaces at the bench:
///  - **Refs win on collision.** `composeBenchClips` writes manifest rows
///    first and lets refs overwrite by id — the ref is the source of truth
///    once a clip has been materialized. Review state follows the same
///    precedence, or a clip could be counted seen by one store and unseen by
///    the other.
///  - **A nil `createdAt` sinks to the epoch**, matching `syntheticClip`.
///    Preserved deliberately rather than silently improved: it is existing
///    behaviour, it is visible (such an item groups alone in 1970), and
///    changing it belongs to its own cycle with its own evidence.
enum BenchInventory {

    struct Result: Equatable {
        /// Every bench item of every kind — the union that had no
        /// representation in the code before this.
        let items: [BenchClipItem]
        /// Ids the user has opened, resolved across both stores.
        let reviewedIds: Set<UUID>
    }

    /// - Parameters:
    ///   - manifestClips: `InboxManifest.clips`. Voice only by construction —
    ///     `PhoneCaptureBenchDispatcher` routes voice to the manifest and
    ///     every other kind straight to a ref.
    ///   - refs: zero-edge, non-recycled `MediaReference`s of ALL kinds,
    ///     reduced to descriptors.
    ///   - refIsReviewed: injected so the per-device store is not a hidden
    ///     dependency of a pure function.
    static func compose(
        manifestClips: [InboxClip],
        refs: [BenchRefDescriptor],
        refIsReviewed: (UUID) -> Bool
    ) -> Result {
        var byId: [UUID: BenchClipItem] = [:]
        var reviewed: Set<UUID> = []

        for clip in manifestClips {
            byId[clip.clipId] = BenchClipItem(
                id: clip.clipId,
                kind: .voice,
                capturedAt: clip.capturedAt,
                rollGroupId: clip.rollGroupId
            )
            if clip.reviewed { reviewed.insert(clip.clipId) } else { reviewed.remove(clip.clipId) }
        }

        // Refs overwrite — the ref is the source of truth once materialized,
        // and review state must follow the same precedence or the two stores
        // can disagree about one clip.
        for ref in refs {
            byId[ref.id] = BenchClipItem(
                id: ref.id,
                kind: ref.kind,
                capturedAt: ref.createdAt ?? Date(timeIntervalSince1970: 0),
                rollGroupId: ref.rollGroupId
            )
            if refIsReviewed(ref.id) { reviewed.insert(ref.id) } else { reviewed.remove(ref.id) }
        }

        return Result(
            items: byId.values.sorted { $0.capturedAt > $1.capturedAt },
            reviewedIds: reviewed
        )
    }
}
