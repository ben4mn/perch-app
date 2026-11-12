#if os(macOS)
import XCTest
@testable import PerchUI

/// Cmd+W in the main window. A task's panel is the thing in front, so Cmd+W closes it first, as Esc and the
/// panel's X do; only with no panel open does it close the window.
final class MainWindowCloseTests: XCTestCase {
    func testCommandWClosesAnOpenPanelNotTheWindow() {
        XCTAssertEqual(MainWindowClose.commandW(panelOpen: true, inMainWindow: true), .closePanel)
    }

    func testWithNoPanelCommandWClosesTheWindowAsUsual() {
        XCTAssertEqual(MainWindowClose.commandW(panelOpen: false, inMainWindow: true), .closeWindow)
    }

    func testOtherWindowsAreLeftToMacOS() {
        // Settings, a sheet, or a document window: Cmd+W does what it always does there.
        XCTAssertEqual(MainWindowClose.commandW(panelOpen: true, inMainWindow: false), .notOurs)
        XCTAssertEqual(MainWindowClose.commandW(panelOpen: false, inMainWindow: false), .notOurs)
    }
}
#endif
