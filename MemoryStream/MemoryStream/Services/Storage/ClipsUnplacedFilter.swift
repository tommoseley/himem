import Foundation
import CoreData

/// Filters the day-grouped unplaced-refs stack on the Clips bench,
/// dropping the Core-Data-invalidated rows the 250ms fetch debounce
/// (`ClipsTabView.unplacedReload`) can leave behind mid-render.
///
/// **Why this exists.** `ClipsTabView.unplacedRefs` is `@State` — a
/// strong array of `MediaReference` objects fetched at most every
/// 250ms (throttling was added to end main-thread thrash during
/// CloudKit churn). Between the moment a ref is deleted (locally
/// via ClipDetail's *Delete clip*, or remotely via a CloudKit merge)
/// and the moment the debounced re-fetch runs, `unplacedRefs` still
/// holds the now-stale Swift reference. SwiftUI re-renders the
/// parent `newFilterContent` freely during that window, and
/// accessing `$0.id` inside the filter closure on an invalidated
/// Core Data fault traps with `EXC_BREAKPOINT`.
///
/// **What this does.** Skips any ref that Core Data has marked
/// `isDeleted` or detached (`managedObjectContext == nil`) *before*
/// touching `.id`. The absorbed-ids check still runs against the
/// live refs. Same shape as the pre-existing inline filter; adds
/// a defensive gate.
enum ClipsUnplacedFilter {

    /// Returns the refs the day-grouped stack should render.
    ///
    /// - Skips refs whose Core Data row has been deleted or invalidated
    ///   (guards `EXC_BREAKPOINT` on `.id` access).
    /// **The absorbed-set subtraction is gone (C2 step 3, 2026-08-18).** Refs
    /// now arrive from `BenchSiblingStackBus` already scoped to what the bench
    /// did not draw, so "appears once" is a property of the composition rather
    /// than a filter the caller must remember. The invalidation guard stays:
    /// published managed objects can still be deleted between the publish and
    /// the render, which is the `EXC_BREAKPOINT` this was written for.
    static func visible(refs: [MediaReference]) -> [MediaReference] {
        refs.filter { ref in
            !ref.isDeleted && ref.managedObjectContext != nil
        }
    }
}
