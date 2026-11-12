import XCTest
@testable import PerchKit

/// When the pointer opens and closes the notch. Ticks come from pointer events and from a poll while it
/// matters, so leaving the panel closes it even when macOS sends no more events.
final class NotchHoverTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    func testResting_onTheNotchOpensItAfterAShortPause() {
        var hover = NotchHover()
        XCTAssertEqual(hover.closed(onNotch: true, pressed: false, at: at(0)), .stay)
        XCTAssertEqual(hover.closed(onNotch: true, pressed: false, at: at(0.05)), .stay)
        XCTAssertEqual(hover.closed(onNotch: true, pressed: false, at: at(NotchHover.openDelay + 0.01)), .open)
    }

    func testPassingOverTheNotchOnTheWayToTheMenuBarDoesntOpenIt() {
        var hover = NotchHover()
        _ = hover.closed(onNotch: true, pressed: false, at: at(0))
        XCTAssertEqual(hover.closed(onNotch: false, pressed: false, at: at(0.05)), .stay)
        XCTAssertEqual(hover.closed(onNotch: false, pressed: false, at: at(1)), .stay)
    }

    func testDraggingAcrossTheNotchNeverOpensIt() {
        var hover = NotchHover()
        _ = hover.closed(onNotch: true, pressed: true, at: at(0))
        XCTAssertEqual(hover.closed(onNotch: true, pressed: true, at: at(1)), .stay)
    }

    func testAfterClosingItWaitsForThePointerToLeaveBeforeOpeningAgain() {
        var hover = NotchHover()
        hover.didClose(pointerOnNotch: true)
        XCTAssertEqual(hover.closed(onNotch: true, pressed: false, at: at(0)), .stay)
        XCTAssertEqual(hover.closed(onNotch: true, pressed: false, at: at(2)), .stay, "Escape or a click closed it: don't bounce back open")
        XCTAssertEqual(hover.closed(onNotch: false, pressed: false, at: at(2.1)), .stay)
        XCTAssertEqual(hover.closed(onNotch: true, pressed: false, at: at(3)), .stay)
        XCTAssertEqual(hover.closed(onNotch: true, pressed: false, at: at(3 + NotchHover.openDelay + 0.01)), .open)
    }

    func testLeavingThePanelClosesItAfterAPauseWithoutAnyMoreEvents() {
        var hover = NotchHover()
        hover.didOpen()
        XCTAssertEqual(hover.open(insidePanel: true, keyboardInPanel: false, at: at(0)), .stay)
        XCTAssertEqual(hover.open(insidePanel: false, keyboardInPanel: false, at: at(1)), .stay)
        // Only the poll ticks from here: the pointer sits still outside.
        XCTAssertEqual(hover.open(insidePanel: false, keyboardInPanel: false, at: at(1 + NotchHover.closeDelay + 0.01)), .close)
    }

    func testComingBackBeforeThePauseKeepsItOpen() {
        var hover = NotchHover()
        hover.didOpen()
        _ = hover.open(insidePanel: false, keyboardInPanel: false, at: at(0))
        XCTAssertEqual(hover.open(insidePanel: true, keyboardInPanel: false, at: at(0.2)), .stay)
        XCTAssertEqual(hover.open(insidePanel: false, keyboardInPanel: false, at: at(0.3)), .stay)
        XCTAssertEqual(hover.open(insidePanel: false, keyboardInPanel: false, at: at(0.6)), .stay, "the pause starts again from the second exit")
        XCTAssertEqual(hover.open(insidePanel: false, keyboardInPanel: false, at: at(0.3 + NotchHover.closeDelay + 0.01)), .close)
    }

    func testTypingInThePanelKeepsItOpenWhereverThePointerGoes() {
        var hover = NotchHover()
        hover.didOpen()
        _ = hover.open(insidePanel: false, keyboardInPanel: true, at: at(0))
        XCTAssertEqual(hover.open(insidePanel: false, keyboardInPanel: true, at: at(5)), .stay)
    }

    func testOnlyTheVisiblePanelTakesClicks() {
        XCTAssertTrue(NotchHover.panelTakesClicks(open: true, pointerInPanel: true))
        XCTAssertFalse(NotchHover.panelTakesClicks(open: true, pointerInPanel: false), "the clear border around the panel lets clicks through")
        XCTAssertFalse(NotchHover.panelTakesClicks(open: false, pointerInPanel: true))
    }

    func testTheHoverAreaKeepsTheSameMarginWhetherOrNotMenusNeedTheRoom() {
        XCTAssertEqual(NotchHover.hoverMargin(hasRoom: true), NotchHover.hoverMargin(hasRoom: false))
        XCTAssertGreaterThan(NotchHover.hoverMargin(hasRoom: false), 0)
    }

    // MARK: Under a full-screen app

    func testWhileCoveredItStopsWaitingSoThePollStops() {
        var hover = NotchHover()
        _ = hover.closed(onNotch: true, pressed: false, at: at(0))
        XCTAssertTrue(hover.isWaitingToOpen)
        hover.covered(onNotch: true)
        XCTAssertFalse(hover.isWaitingToOpen, "a poll left running here would tick 30 times a second for as long as the app stays full screen")
    }

    func testUncoveredItWaitsTheShortPauseAgainRatherThanOpeningAtOnce() {
        var hover = NotchHover()
        _ = hover.closed(onNotch: true, pressed: false, at: at(0))
        hover.covered(onNotch: true)
        XCTAssertEqual(hover.closed(onNotch: true, pressed: false, at: at(5)), .stay, "the arrival from before the cover doesn't count")
        XCTAssertEqual(hover.closed(onNotch: true, pressed: false, at: at(5 + NotchHover.openDelay + 0.01)), .open)
    }

    func testThePointerLeavingWhileCoveredStillCountsAsLeaving() {
        var hover = NotchHover()
        hover.didClose(pointerOnNotch: true)
        hover.covered(onNotch: true)
        XCTAssertFalse(hover.armed)
        hover.covered(onNotch: false)
        XCTAssertTrue(hover.armed, "otherwise a close just before the cover outlives it")
        XCTAssertEqual(hover.closed(onNotch: true, pressed: false, at: at(0)), .stay)
        XCTAssertEqual(hover.closed(onNotch: true, pressed: false, at: at(NotchHover.openDelay + 0.01)), .open)
    }
}

/// Whether a full-screen app covers the notch's screen. The answer hides the notch and stops hover, so it
/// must never wait for another app to come forward or the space to change before it is looked at again.
final class NotchHoverFullScreenTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    func testAFullScreenAnswerIsCheckedAgainWhenThePointerReachesTheNotch() {
        // Taken while the slide out of a full-screen space was still running, and nothing has happened
        // since that macOS announces: no app came forward and the space didn't change again.
        var check = NotchFullScreenCheck()
        check.record(true, at: at(0))
        XCTAssertTrue(check.isFullScreen)
        XCTAssertTrue(check.shouldCheck(pointerOnNotch: true, at: at(30)))
    }

    func testThePointerAnywhereElseNeverCausesALook() {
        var check = NotchFullScreenCheck()
        check.record(true, at: at(0))
        XCTAssertFalse(check.shouldCheck(pointerOnNotch: false, at: at(30)))
    }

    func testWithNoFullScreenAppPointerEventsNeverCauseALook() {
        var check = NotchFullScreenCheck()
        XCTAssertFalse(check.shouldCheck(pointerOnNotch: true, at: at(0)), "nothing blocks hover, so there is nothing to heal")
        check.record(false, at: at(0))
        XCTAssertFalse(check.shouldCheck(pointerOnNotch: true, at: at(30)))
    }

    func testLooksFromThePointerAreSpacedOut() {
        // Listing every window costs about half a millisecond, and the pointer sends dozens of events a second.
        var check = NotchFullScreenCheck()
        check.record(true, at: at(0))
        XCTAssertFalse(check.shouldCheck(pointerOnNotch: true, at: at(0.1)))
        XCTAssertTrue(check.shouldCheck(pointerOnNotch: true, at: at(NotchFullScreenCheck.pointerInterval + 0.01)))
        check.record(true, at: at(NotchFullScreenCheck.pointerInterval + 0.01))
        XCTAssertFalse(check.shouldCheck(pointerOnNotch: true, at: at(NotchFullScreenCheck.pointerInterval + 0.2)))
    }

    func testTheAnswerFollowsTheLatestLook() {
        var check = NotchFullScreenCheck()
        check.record(true, at: at(0))
        check.record(false, at: at(1))
        XCTAssertFalse(check.isFullScreen)
    }

    func testAfterASpaceChangeItLooksAgainOnceTheSlideIsOver() {
        let delays = NotchFullScreenCheck.settleDelays
        XCTAssertFalse(delays.isEmpty)
        XCTAssertEqual(delays, delays.sorted())
        XCTAssertGreaterThan(delays.first ?? 0, 0)
        XCTAssertGreaterThanOrEqual(delays.last ?? 0, 1, "the slide between spaces takes about half a second, longer on a slow swipe")
        XCTAssertLessThanOrEqual(delays.count, 3, "each look lists every window on screen")
    }
}
