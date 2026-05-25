import Testing
@testable import HiMem

@Suite struct PhotoGridLayoutTests {

    @Test func iPhonePortrait_returns3Columns() {
        #expect(PhotoGridLayout.columnCount(isPad: false, isLandscape: false) == 3)
    }

    @Test func iPhoneLandscape_returns5Columns() {
        #expect(PhotoGridLayout.columnCount(isPad: false, isLandscape: true) == 5)
    }

    @Test func iPadPortrait_returns4Columns() {
        #expect(PhotoGridLayout.columnCount(isPad: true, isLandscape: false) == 4)
    }

    @Test func iPadLandscape_returns6Columns() {
        #expect(PhotoGridLayout.columnCount(isPad: true, isLandscape: true) == 6)
    }
}
