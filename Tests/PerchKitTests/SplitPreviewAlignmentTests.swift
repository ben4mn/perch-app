import XCTest
@testable import PerchUI

/// Editing with the preview beside: a line sits level on both sides, at the top of the note and after a sync.
final class SplitPreviewAlignmentTests: XCTestCase {
    func testTheEditorsTextStartsBelowItsFormatBarAndInset() {
        XCTAssertEqual(NotePanes.editorTextTop(barHeight: 34, insetTop: 26), 60)
        XCTAssertEqual(NotePanes.editorTextTop(barHeight: 0, insetTop: 26), 26, "with the format bar turned off")
    }

    func testBesideTheEditorThePreviewStartsItsTextAtTheEditorsHeight() {
        let base: [String: Any] = ["fontSize": 17, "style": ["--perch-paragraph-gap": "1.4em"], "variables": ["--perch-accent": "#123456"]]
        let payload = NotePanes.readerAppearance(base, previewTop: 60)
        let style = payload["style"] as? [String: String]
        XCTAssertEqual(style?["--perch-pad-top"], "60px")
        XCTAssertEqual(style?["--perch-paragraph-gap"], "1.4em", "the reading settings are kept")
        XCTAssertEqual(payload["fontSize"] as? Int, 17)
        XCTAssertEqual((payload["variables"] as? [String: String])?["--perch-accent"], "#123456")
        XCTAssertEqual((NotePanes.readerAppearance([:], previewTop: 37.4)["style"] as? [String: String])?["--perch-pad-top"], "37px")
    }

    func testScrollingThePreviewBringsTheEditorAlongWhenYouScrolledIt() {
        XCTAssertTrue(NotePanes.editorFollowsPreview(byUser: true, syncing: true))
        XCTAssertFalse(NotePanes.editorFollowsPreview(byUser: false, syncing: true), "the page moved because the editor moved it: no echo")
        XCTAssertFalse(NotePanes.editorFollowsPreview(byUser: true, syncing: false), "not side by side, or sync is turned off")
    }

    func testTheReaderOnItsOwnGoesBackToThePagesOwnSpacing() {
        let payload = NotePanes.readerAppearance(["style": ["--perch-paragraph-gap": "1.4em"]], previewTop: nil)
        let style = payload["style"] as? [String: String]
        // Left out, the page would keep the split's spacing; an empty value puts the page's own back.
        XCTAssertEqual(style?["--perch-pad-top"], "")
        XCTAssertEqual(style?["--perch-paragraph-gap"], "1.4em")
    }
}
