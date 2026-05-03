import Testing
import Foundation
@testable import MemoryStream

struct PlacemarkFormatterTests {

    /// Synthetic placemark — CLPlacemark itself is awkward to construct
    /// because its initializer doesn't expose thoroughfare/subThoroughfare
    /// independently. The protocol exists exactly to let us bypass that.
    private struct StubPlacemark: PlacemarkFields {
        var areasOfInterest: [String]? = nil
        var thoroughfare: String? = nil
        var subThoroughfare: String? = nil
        var subLocality: String? = nil
        var locality: String? = nil
        var administrativeArea: String? = nil
        var country: String? = nil
    }

    // MARK: - Each documented output shape gets one money test

    @Test func displayName_POIPlusLocality() {
        let pm = StubPlacemark(
            areasOfInterest: ["Columbus Circle"],
            thoroughfare: "Broadway",
            subThoroughfare: "1888",
            locality: "New York",
            administrativeArea: "NY",
            country: "United States"
        )
        #expect(PlacemarkFormatter.displayName(from: pm) == "Columbus Circle, New York")
    }

    @Test func displayName_StreetWithNumberPlusLocality() {
        let pm = StubPlacemark(
            thoroughfare: "Columbus Cir",
            subThoroughfare: "18",
            locality: "Bluffton",
            administrativeArea: "SC",
            country: "United States"
        )
        #expect(PlacemarkFormatter.displayName(from: pm) == "18 Columbus Cir, Bluffton")
    }

    @Test func displayName_StreetWithoutNumberPlusLocality() {
        let pm = StubPlacemark(
            thoroughfare: "Main St",
            locality: "Springfield",
            administrativeArea: "IL",
            country: "United States"
        )
        #expect(PlacemarkFormatter.displayName(from: pm) == "Main St, Springfield")
    }

    @Test func displayName_NeighborhoodPlusLocality() {
        let pm = StubPlacemark(
            subLocality: "Hell's Kitchen",
            locality: "New York",
            administrativeArea: "NY",
            country: "United States"
        )
        #expect(PlacemarkFormatter.displayName(from: pm) == "Hell's Kitchen, New York")
    }

    @Test func displayName_LocalityPlusAdmin() {
        let pm = StubPlacemark(
            locality: "New York",
            administrativeArea: "NY",
            country: "United States"
        )
        #expect(PlacemarkFormatter.displayName(from: pm) == "New York, NY")
    }

    @Test func displayName_AdminAlone() {
        let pm = StubPlacemark(
            administrativeArea: "NY",
            country: "United States"
        )
        // Admin alone — no broader scope to append (we don't append country).
        #expect(PlacemarkFormatter.displayName(from: pm) == "NY")
    }

    @Test func displayName_CountryAlone() {
        let pm = StubPlacemark(country: "United States")
        #expect(PlacemarkFormatter.displayName(from: pm) == "United States")
    }

    // MARK: - Edge cases worth locking down

    @Test func displayName_emptyPlacemark_returnsNil() {
        let pm = StubPlacemark()
        #expect(PlacemarkFormatter.displayName(from: pm) == nil)
    }

    @Test func displayName_emptyAreasOfInterest_fallsThroughToStreet() {
        let pm = StubPlacemark(
            areasOfInterest: ["", "  "],
            thoroughfare: "Broadway",
            locality: "New York"
        )
        // Empty/whitespace POI strings are skipped; falls through to street.
        #expect(PlacemarkFormatter.displayName(from: pm) == "Broadway, New York")
    }

    @Test func displayName_streetButNoLocality_returnsStreetAlone() {
        let pm = StubPlacemark(
            thoroughfare: "Columbus Cir",
            subThoroughfare: "18"
        )
        #expect(PlacemarkFormatter.displayName(from: pm) == "18 Columbus Cir")
    }

    @Test func displayName_localityEqualsAdmin_returnsLocalityAlone() {
        // Some places have locality == admin (city-states or single-name regions).
        // Avoid producing "Singapore, Singapore" duplicates.
        let pm = StubPlacemark(locality: "Singapore", administrativeArea: "Singapore")
        #expect(PlacemarkFormatter.displayName(from: pm) == "Singapore")
    }

    @Test func displayName_subLocalityEqualsLocality_collapsesToOne() {
        let pm = StubPlacemark(
            subLocality: "Manhattan",
            locality: "Manhattan",
            administrativeArea: "NY"
        )
        // Don't render "Manhattan, Manhattan". Should collapse.
        let result = PlacemarkFormatter.displayName(from: pm)
        #expect(result?.contains("Manhattan, Manhattan") != true)
    }
}
