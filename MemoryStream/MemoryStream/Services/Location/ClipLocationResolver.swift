import Foundation
import CoreData
import CoreLocation

/// Stamps `MediaReference` rows with their captured coordinates and
/// kicks off a background reverse-geocode that writes back `placeName`.
///
/// The clip-row header in Memory Detail (v3) reads `placeName`
/// directly — no render-time geocode hop. This resolver is what makes
/// that possible: it's called from each ingestion path (watch clip
/// → MediaReference, phone voice session → MediaReference, append-
/// clips-to-memory) right after `saveEntry` / `appendToEntry` has
/// linked the new refs in.
///
/// Network/geocoder failures are silent — the row falls back to
/// rendering date + time only. We don't retry; the user can edit the
/// memory later if they want the place name attached.
enum ClipLocationResolver {

    /// Stamps lat/lon on a freshly-created MediaReference, then
    /// fires a background reverse-geocode that writes `placeName`
    /// when it returns. Returns immediately — the geocode and the
    /// write-back are detached so the caller's save path isn't
    /// blocked on network.
    ///
    /// `viewContext` lives on MainActor; the geocode `Task` hops
    /// back to MainActor to write the resolved name. Pure no-op
    /// when both coords are nil (legacy clips and `.note`
    /// fragments) — saves the caller from filtering upstream.
    @MainActor
    static func stamp(
        clipId: UUID,
        latitude: Double?,
        longitude: Double?,
        in viewContext: NSManagedObjectContext,
        storage: StorageService = .shared
    ) {
        stamp(
            latitude: latitude,
            longitude: longitude,
            in: viewContext,
            storage: storage
        ) { fetchClip(id: clipId, in: viewContext) }
    }

    /// Variant for callers that have the `osIdentifier` (voice
    /// audio filename) but haven't fetched the ref yet. Used by the
    /// ingestion-path fixup loops that already look refs up by
    /// `osIdentifier` to set transcripts — saves the duplicate
    /// fetch.
    @MainActor
    static func stamp(
        osIdentifier: String,
        latitude: Double?,
        longitude: Double?,
        in viewContext: NSManagedObjectContext,
        storage: StorageService = .shared
    ) {
        stamp(
            latitude: latitude,
            longitude: longitude,
            in: viewContext,
            storage: storage
        ) { fetchClip(osIdentifier: osIdentifier, in: viewContext) }
    }

    /// Shared body — runs the lookup, stamps lat/lon, schedules the
    /// background geocode. The lookup is a closure so the ID-based
    /// and osIdentifier-based public entry points can share the
    /// rest of the flow.
    @MainActor
    private static func stamp(
        latitude: Double?,
        longitude: Double?,
        in viewContext: NSManagedObjectContext,
        storage: StorageService,
        lookup: () -> MediaReference?
    ) {
        guard let latitude, let longitude else {
            NSLog("[Himem][ClipLoc] stamp skipped — nil lat/lon on this clip")
            return
        }
        guard let ref = lookup() else {
            NSLog("[Himem][ClipLoc] stamp skipped — MediaReference not found in store for stamp lookup")
            return
        }
        let refId = ref.id
        ref.latitude = NSNumber(value: latitude)
        ref.longitude = NSNumber(value: longitude)
        try? storage.save(context: viewContext)
        NSLog("[Himem][ClipLoc] stamped lat=\(latitude) lon=\(longitude) on ref=\(refId.uuidString)")

        Task { @MainActor in
            let location = CLLocation(latitude: latitude, longitude: longitude)
            guard let name = await LocationService.shared.reverseGeocode(location) else {
                NSLog("[Himem][ClipLoc] reverseGeocode returned nil for ref=\(refId.uuidString)")
                return
            }
            guard let refreshed = fetchClip(id: refId, in: viewContext) else {
                NSLog("[Himem][ClipLoc] post-geocode fetch failed for ref=\(refId.uuidString)")
                return
            }
            refreshed.placeName = name
            try? storage.save(context: viewContext)
            NSLog("[Himem][ClipLoc] wrote placeName=\(name) for ref=\(refId.uuidString)")
        }
    }

    private static func fetchClip(id: UUID, in context: NSManagedObjectContext) -> MediaReference? {
        let request = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    private static func fetchClip(osIdentifier: String, in context: NSManagedObjectContext) -> MediaReference? {
        let request = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        request.predicate = NSPredicate(format: "osIdentifier == %@", osIdentifier)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
}
