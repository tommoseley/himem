import Foundation
import CoreLocation

/// Subset of CLPlacemark fields Hi Mem uses for formatting. Modeled as a
/// protocol so tests can pass synthetic placemarks (CLPlacemark itself is
/// awkward to construct — the public initializer needs `region`/`name`/etc.
/// and won't let you set thoroughfare/subThoroughfare independently).
protocol PlacemarkFields {
    var areasOfInterest: [String]? { get }
    var thoroughfare: String? { get }
    var subThoroughfare: String? { get }
    var subLocality: String? { get }
    var locality: String? { get }
    var administrativeArea: String? { get }
    var country: String? { get }
}

extension CLPlacemark: PlacemarkFields {}

/// Pure formatter that reduces a placemark to a comma-separated
/// "primary, context" string. Output shapes (most → least specific):
///
///   "Columbus Circle, New York"     POI + locality
///   "18 Columbus Cir, Bluffton"     street + locality
///   "Hell's Kitchen, New York"      neighborhood + locality
///   "New York, NY"                  locality + admin
///   "NY"                            admin alone
///   "United States"                 country alone
///
/// Never produces a leading street number with no street, never a
/// trailing comma+ellipsis. Card display is responsible for dropping
/// trailing comma segments to fit a width budget; this formatter just
/// supplies the most-specific full string.
private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { isEmpty ? nil : self }
}

enum PlacemarkFormatter {

    static func displayName<P: PlacemarkFields>(from pm: P) -> String? {
        let primary = primaryToken(from: pm)
        let context = contextToken(from: pm, given: primary)
        if let primary, let context, primary != context {
            return "\(primary), \(context)"
        }
        if let primary { return primary }
        if let context { return context }
        return pm.country
    }

    /// The most-specific identifier for the location. POI > street (with
    /// number when present) > neighborhood > city > state > country.
    /// Whitespace-only fields are treated as missing.
    static func primaryToken<P: PlacemarkFields>(from pm: P) -> String? {
        if let poi = pm.areasOfInterest?.first(where: { !$0.trimmed.isEmpty }) {
            return poi.trimmed
        }
        if let thoroughfare = pm.thoroughfare?.trimmed, !thoroughfare.isEmpty {
            if let number = pm.subThoroughfare?.trimmed, !number.isEmpty {
                return "\(number) \(thoroughfare)"
            }
            return thoroughfare
        }
        if let sub = pm.subLocality?.trimmed, !sub.isEmpty { return sub }
        if let locality = pm.locality?.trimmed, !locality.isEmpty { return locality }
        if let admin = pm.administrativeArea?.trimmed, !admin.isEmpty { return admin }
        return pm.country?.trimmed.nonEmpty
    }

    /// The next-broader scope to append after the primary. We don't repeat
    /// what's already in `primary` and we never go more granular.
    static func contextToken<P: PlacemarkFields>(from pm: P, given primary: String?) -> String? {
        guard let primary else { return nil }
        if pm.areasOfInterest?.contains(where: { $0 == primary }) == true,
           let locality = pm.locality, !locality.isEmpty {
            return locality
        }
        if let thoroughfare = pm.thoroughfare,
           primary.hasSuffix(thoroughfare),
           let locality = pm.locality, !locality.isEmpty {
            return locality
        }
        if let sub = pm.subLocality, sub == primary,
           let locality = pm.locality, !locality.isEmpty, locality != primary {
            return locality
        }
        if let locality = pm.locality, locality == primary,
           let admin = pm.administrativeArea, !admin.isEmpty, admin != primary {
            return admin
        }
        return nil
    }
}
