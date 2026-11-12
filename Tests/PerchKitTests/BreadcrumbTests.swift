import XCTest
@testable import PerchKit

/// The path above a folder's title shows only what the folder chips don't already say.
final class BreadcrumbTests: XCTestCase {
    func testATopFolderBesideItsChipNeedsNoPath() {
        XCTAssertFalse(FolderListing.showsBreadcrumb(for: "✈️ Acme", besideFolderChips: true), "the chip, and the title, already say where you are")
        XCTAssertFalse(FolderListing.showsBreadcrumb(for: "", besideFolderChips: true))
    }

    func testDeeperFoldersKeepThePath() {
        XCTAssertTrue(FolderListing.showsBreadcrumb(for: "✈️ Acme/People", besideFolderChips: true))
    }

    func testWithoutTheChipsThePathIsTheWayBack() {
        XCTAssertTrue(FolderListing.showsBreadcrumb(for: "✈️ Acme", besideFolderChips: false))
        XCTAssertFalse(FolderListing.showsBreadcrumb(for: "", besideFolderChips: false), "the top of the notebook has no path")
    }
}
