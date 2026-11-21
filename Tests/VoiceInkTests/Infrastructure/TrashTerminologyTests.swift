import XCTest
@testable import VoiceInk

/// The Trash is called the "Bin" in Australia, the UK and similar regions.
/// The sidebar must use the same region-aware wording as the Trash screen itself.
final class TrashTerminologyTests: XCTestCase {
    func testCommonwealthRegionsSayBin() {
        for region in ["AU", "GB", "NZ", "IE", "ZA", "IN", "SG", "HK", "MY", "PK"] {
            XCTAssertTrue(Localization.usesBinTerminology(regionCode: region), "\(region) should say Bin")
        }
    }

    func testOtherRegionsSayTrash() {
        for region in ["US", "CA", "FR", "JP", "DE", ""] {
            XCTAssertFalse(Localization.usesBinTerminology(regionCode: region), "\(region) should say Trash")
        }
        XCTAssertFalse(Localization.usesBinTerminology(regionCode: nil))
    }

    func testRegionCodesAreMatchedExactly() {
        XCTAssertFalse(Localization.usesBinTerminology(regionCode: "au"))
        XCTAssertFalse(Localization.usesBinTerminology(regionCode: "AUS"))
    }

    func testTitleFollowsTheTerminology() {
        XCTAssertEqual(Localization.Trash.title(usesBin: true), "Bin")
        XCTAssertEqual(Localization.Trash.title(usesBin: false), "Trash")
    }

    func testSidebarLabelsTheTrashWithTheRegionalWord() {
        let usesBin = Localization.usesBinTerminology(regionCode: Locale.current.region?.identifier)

        XCTAssertEqual(ViewType.trash.sidebarTitleKey, Localization.Trash.title(usesBin: usesBin))
        XCTAssertEqual(ViewType.trash.sidebarTitleKey, Localization.Trash.title)
    }

    func testOtherSidebarLabelsAreUnchanged() {
        XCTAssertEqual(ViewType.transcribeAudio.sidebarTitleKey, "Transcribe")

        for item in ViewType.allCases where item != .trash && item != .transcribeAudio {
            XCTAssertEqual(item.sidebarTitleKey, item.rawValue)
        }
    }

    func testTheNavigationIdentifierStaysTrash() {
        // Deep links and saved selections use the raw value, so it must not follow the region.
        XCTAssertEqual(ViewType.trash.rawValue, "Trash")
        XCTAssertEqual(ViewType(rawValue: "Trash"), .trash)
    }
}
