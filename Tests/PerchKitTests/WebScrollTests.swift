import XCTest
@testable import PerchUI

/// A task's details are drawn by a small web view inside the panel's scroll view. On the Mac a web view keeps
/// scroll-wheel events even when it has nothing to scroll, so with the pointer over the details the panel
/// couldn't be scrolled down to its subtasks and activity. An embedded web view hands vertical scrolling to
/// the scroll view around it and keeps sideways scrolling, for a wide table or code block inside it.
final class WebScrollTests: XCTestCase {
    func testAnEmbeddedViewPassesUpAndDownToThePanel() {
        XCTAssertTrue(WebScroll.goesToParent(deltaX: 0, deltaY: -12, embedded: true))
        XCTAssertTrue(WebScroll.goesToParent(deltaX: 2, deltaY: 9, embedded: true), "a trackpad's slightly diagonal swipe is still up or down")
    }

    func testSidewaysScrollingStaysInTheView() {
        XCTAssertFalse(WebScroll.goesToParent(deltaX: -14, deltaY: 3, embedded: true))
    }

    func testAViewThatFillsItsPaneScrollsItself() {
        // The note reader and a board scroll inside their own page.
        XCTAssertFalse(WebScroll.goesToParent(deltaX: 0, deltaY: -12, embedded: false))
    }

    func testTheEndOfAGestureGoesWhereItStarted() {
        // No movement (momentum ending, a phase change): passed up from an embedded view too, so the panel
        // sees its gesture end.
        XCTAssertTrue(WebScroll.goesToParent(deltaX: 0, deltaY: 0, embedded: true))
    }

    #if os(macOS)
    /// The Mac's web view has two jobs: where scroll-wheel events go (above), and telling its host when it
    /// comes on screen and leaves, so a reader page nobody is looking at can be let go. Losing either one
    /// to the other is easy when both are written as their own web view class.
    @MainActor
    func testTheMacWebViewDoesBothJobs() throws {
        let host = WebHost(page: "render") { nil }
        let view = try XCTUnwrap(host.webView as? PerchWebView, "the Mac web view decides where scrolling goes")
        var heard: [Bool] = []
        let listener = view.onWindowChange
        XCTAssertNotNil(listener, "the host listens for the view coming and going")
        view.onWindowChange = { onScreen in heard.append(onScreen); listener?(onScreen) }
        let window = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView?.addSubview(view)
        view.removeFromSuperview()
        XCTAssertEqual(heard, [true, false])
    }
    #endif
}
