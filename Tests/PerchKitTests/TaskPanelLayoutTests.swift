import XCTest
@testable import PerchUI

/// The Mac's task panel is Perch's own column beside the list or note, not SwiftUI's inspector, which
/// reported itself closed late and closed a panel that had just opened. How wide it is, and how dragging
/// its edge changes that.
final class TaskPanelLayoutTests: XCTestCase {
    func testTheSavedWidthIsKeptWhenThereIsRoom() {
        XCTAssertEqual(TaskPanelLayout.width(saved: 420, available: 1100), 420)
        XCTAssertEqual(TaskPanelLayout.width(saved: 500, available: 1100), 500)
    }

    func testTheWidthStaysBetweenItsLimits() {
        XCTAssertEqual(TaskPanelLayout.width(saved: 100, available: 1400), TaskPanelLayout.minWidth)
        XCTAssertEqual(TaskPanelLayout.width(saved: 2000, available: 1400), TaskPanelLayout.maxWidth)
    }

    func testTheListOrNoteKeepsItsRoom() {
        // 700 wide: the panel gives way so the content keeps its share.
        XCTAssertEqual(TaskPanelLayout.width(saved: 500, available: 700), 700 - TaskPanelLayout.contentRoom)
        // Narrower than both can have: the panel keeps a usable width and the content takes the rest.
        XCTAssertEqual(TaskPanelLayout.width(saved: 500, available: 560), TaskPanelLayout.narrowestWidth)
    }

    func testDraggingTheEdgeLeftWidensThePanel() {
        // The edge is on the panel's left: dragging left (a negative distance) makes it wider.
        XCTAssertEqual(TaskPanelLayout.dragged(from: 420, by: -60, available: 1400), 480)
        XCTAssertEqual(TaskPanelLayout.dragged(from: 420, by: 60, available: 1400), 360)
        XCTAssertEqual(TaskPanelLayout.dragged(from: 420, by: 400, available: 1400), TaskPanelLayout.minWidth)
    }
}
