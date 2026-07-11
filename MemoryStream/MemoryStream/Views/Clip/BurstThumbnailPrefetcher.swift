import Foundation
import UIKit

/// Batch-loads thumbnails for a burst strip through a bounded-
/// concurrency queue, returning a `[UUID: UIImage]` map keyed by
/// the source model id.
///
/// Slice 6 of the Clip Model convergence
/// (`docs/architecture/2026-07-11-clip-model-convergence-plan.md`).
/// The load-bearing fix for R2's burst-thumbnail-storm flag: a
/// same-minute burst of ≤5 photos calling
/// `ThumbnailService.cacheThumbnail` per atom concurrently
/// saturates disk with parallel `UIImage(data:)` decodes on cold
/// launch. This prefetcher caps live loads (default 3) so the
/// strip fetches politely, then hands each atom its
/// `providedThumbnail` param (Slice 3's opt-in perf affordance).
///
/// Not the same as R2's Q4b (in-flight dedup on
/// `ThumbnailService`). This solves the **distinct-N-keys** case;
/// dedup solves the **same-key across surfaces** case. Both
/// warranted; both shipped in different slices — see the plan
/// doc's Q4 answer.
///
/// **Pure logic** — the actual disk hits go through
/// `ThumbnailService.cacheThumbnail`, which is unchanged. The
/// prefetcher owns the concurrency policy + result aggregation.
enum BurstThumbnailPrefetcher {

    /// Load thumbnails for `keys` with `maxConcurrent` live loads
    /// at a time. Returns a map keyed by model id; entries are
    /// nil-safe (a key that fails to resolve stays absent from
    /// the map). Order-agnostic — call sites look up by id.
    ///
    /// - Parameters:
    ///   - keys: `[(id: UUID, thumbnailKey: ClipDisplayModel.ThumbnailKey)]`
    ///     tuples. The `id` is what the atom will look up; the
    ///     `thumbnailKey` is what feeds `ThumbnailService`.
    ///   - maxConcurrent: cap on simultaneous loads. Default 3.
    ///     Higher = faster on burst but heavier disk contention;
    ///     lower = politer. 3 is the R2-recommended default.
    ///   - service: injected for tests. Default = shared.
    static func prefetch(
        keys: [PrefetchInput],
        maxConcurrent: Int = 3,
        service: ThumbnailFetching = ThumbnailService.shared
    ) async -> [UUID: UIImage] {
        guard !keys.isEmpty else { return [:] }

        // Dedupe by osIdentifier so two atoms in the strip pointing
        // at the same source share one disk hit. (Rare in a burst
        // by definition — a burst is one moment's worth of distinct
        // captures — but the dedup is free and closes the loop for
        // any edge cases.)
        var uniqueByOsId: [String: PrefetchInput] = [:]
        for input in keys {
            if uniqueByOsId[input.thumbnailKey.osIdentifier] == nil {
                uniqueByOsId[input.thumbnailKey.osIdentifier] = input
            }
        }
        let unique = Array(uniqueByOsId.values)

        // Bounded-concurrency task group. `withTaskGroup` spawns
        // all N tasks at once by default; we throttle by adding
        // tasks in chunks and awaiting completions before adding
        // the next. Simple + correct + no OperationQueue plumbing.
        var results: [UUID: UIImage] = [:]
        await withTaskGroup(of: (UUID, UIImage?).self) { group in
            var pending = unique
            var inflight = 0
            let cap = max(1, maxConcurrent)

            // Prime the pipeline with the first `cap` tasks.
            while inflight < cap, let next = pending.first {
                pending.removeFirst()
                group.addTask {
                    let image = await Self.loadOne(input: next, service: service)
                    return (next.id, image)
                }
                inflight += 1
            }

            // Drain: as each completes, add the next.
            while let (id, image) = await group.next() {
                inflight -= 1
                if let image { results[id] = image }
                if let next = pending.first {
                    pending.removeFirst()
                    group.addTask {
                        let image = await Self.loadOne(input: next, service: service)
                        return (next.id, image)
                    }
                    inflight += 1
                }
            }
        }

        // Fan the unique-by-osId results back out to any duplicate
        // ids the caller passed. (No-op in the normal case; keeps
        // the API honest under edge conditions.)
        var finalMap: [UUID: UIImage] = [:]
        for input in keys {
            if let image = results[input.id] {
                finalMap[input.id] = image
            } else {
                // A dupe with the same osIdentifier — look up by
                // the primary id and reuse the image.
                let primary = uniqueByOsId[input.thumbnailKey.osIdentifier]
                if let primaryId = primary?.id, let image = results[primaryId] {
                    finalMap[input.id] = image
                }
            }
        }
        return finalMap
    }

    private static func loadOne(input: PrefetchInput, service: ThumbnailFetching) async -> UIImage? {
        guard let filename = await service.cacheThumbnail(
            for: input.thumbnailKey.osIdentifier,
            mediaType: input.thumbnailKey.mediaType
        ) else { return nil }
        return service.cachedThumbnail(filename: filename)
    }

    /// One caller-supplied load target — model id + the thumbnail
    /// address.
    struct PrefetchInput: Equatable, Hashable {
        let id: UUID
        let thumbnailKey: ClipDisplayModel.ThumbnailKey
    }
}

/// The subset of `ThumbnailService` the prefetcher needs. Protocol
/// so tests can inject a counting mock without spinning up the real
/// disk-backed service.
protocol ThumbnailFetching: Sendable {
    func cacheThumbnail(for localIdentifier: String, mediaType: MediaReference.MediaType) async -> String?
    func cachedThumbnail(filename: String) -> UIImage?
}

extension ThumbnailService: ThumbnailFetching {}
