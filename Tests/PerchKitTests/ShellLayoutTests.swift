import XCTest
@testable import PerchKit

/// The folding phone's four screens: the whole screen, and the room the app is given inside it.
///
/// On the cover screen iOS keeps a column about 86 points wide for its status strip, toolbar buttons
/// and tab bar (measured on the simulator: 380 of 466 upright, 594 of 678 on its side, where the
/// column also costs 34 points of height). Nobody has measured the inner screen yet, so every test
/// of it runs twice: with the whole screen, and with the same column taken off the width.
private enum Duo {
    typealias Screen = (width: Double, height: Double, sceneWidth: Double, sceneHeight: Double)

    static let column = 86.0
    static let coverPortrait: Screen = (380, 678, 466, 678)
    static let coverLandscape: Screen = (594, 432, 678, 466)
    static let innerPortrait: [Screen] = [(669, 951, 669, 951), (669 - column, 951, 669, 951)]
    static let innerLandscape: [Screen] = [(951, 669, 951, 669), (951 - column, 669, 951, 669), (951 - column, 583, 951, 669)]
}

final class ShellLayoutTests: XCTestCase {
    private func layout(_ screen: Duo.Screen, _ preference: SidebarPreference = .expanded, wide: Bool = true, scale: Double = 1) -> ShellLayout {
        ShellLayout(
            width: screen.width, height: screen.height, sceneWidth: screen.sceneWidth, sceneHeight: screen.sceneHeight,
            allowsWide: wide, preference: preference, scale: scale
        )
    }

    /// A screen with nothing kept back by the system.
    private func layout(_ size: (Double, Double), _ preference: SidebarPreference = .expanded, scale: Double = 1) -> ShellLayout {
        ShellLayout(width: size.0, height: size.1, preference: preference, scale: scale)
    }

    func testTheClosedPhoneUprightKeepsTabs() {
        let cover = layout(Duo.coverPortrait)
        XCTAssertEqual(cover.navigation, .tabs)
        XCTAssertEqual(cover.contentWidth, 380)
        for size in [(466.0, 678.0), (320.0, 568.0), (639.0, 900.0), (440.0, 956.0)] {
            let layout = layout(size)
            XCTAssertEqual(layout.navigation, .tabs)
            XCTAssertFalse(layout.isWide)
            XCTAssertFalse(layout.splitsContent)
            XCTAssertEqual(layout.offersBoard, size.0 >= 500, "the Board needs 500 points, tabs or not")
            XCTAssertTrue(layout.showsContentBars)
            XCTAssertEqual(layout.contentWidth, size.0)
        }
    }

    func testTheClosedPhoneOnItsSideKeepsTabs() {
        // 678 points wide, 594 for the app: under 640, and too short to be the big screen. iOS has
        // already put the tab bar in its own column there, so a rail would only be a second column
        // (523 points of content instead of 594). Tabs, with room for the Board.
        for preference in SidebarPreference.allCases {
            let layout = layout(Duo.coverLandscape, preference)
            XCTAssertEqual(layout.navigation, .tabs)
            XCTAssertEqual(layout.contentWidth, 594)
            XCTAssertTrue(layout.offersBoard)
            XCTAssertFalse(layout.splitsContent)
        }
        // The same, were the system to keep nothing: 678 points of room is wide whatever the height.
        XCTAssertEqual(layout((678.0, 466.0)).navigation, .rail)
    }

    func testTheOpenPhoneUprightGetsTheRailAndADrawerWithOrWithoutASystemColumn() {
        for screen in Duo.innerPortrait {
            for preference in SidebarPreference.allCases {
                let layout = layout(screen, preference)
                XCTAssertEqual(layout.navigation, .rail, "\(screen.width) of 669")
                XCTAssertFalse(layout.canPinSidebar, "the sidebar is a drawer")
                XCTAssertTrue(layout.showsContentBars, "the rail has no areas or folders, so the content keeps its bars")
                XCTAssertFalse(layout.splitsContent, "one pane")
                XCTAssertTrue(layout.offersBoard, "\(layout.contentWidth) points is room for the Board")
                XCTAssertEqual(layout.contentWidth, screen.width - 68 - 1)
            }
        }
        XCTAssertEqual(layout(Duo.innerPortrait[0]).contentWidth, 600)
        XCTAssertEqual(layout(Duo.innerPortrait[1]).contentWidth, 514)
    }

    func testTheOpenPhoneOnItsSideKeepsTheSidebarBesideTwoPanesWithOrWithoutASystemColumn() {
        for screen in Duo.innerLandscape {
            let expanded = layout(screen)
            XCTAssertEqual(expanded.navigation, .sidebar, "\(screen.width) of 951")
            XCTAssertTrue(expanded.canPinSidebar)
            XCTAssertFalse(expanded.showsContentBars)
            XCTAssertEqual(expanded.contentWidth, screen.width - 232 - 1)
            XCTAssertTrue(expanded.splitsContent)
            XCTAssertGreaterThanOrEqual(PaneLayout.trailingWidth(content: expanded.contentWidth), 310)
            XCTAssertGreaterThanOrEqual(expanded.contentWidth - PaneLayout.trailingWidth(content: expanded.contentWidth), 310)

            let rail = layout(screen, .rail)
            XCTAssertEqual(rail.navigation, .rail)
            XCTAssertTrue(rail.canPinSidebar)
            XCTAssertTrue(rail.showsContentBars)
            XCTAssertEqual(rail.contentWidth, screen.width - 68 - 1)
            XCTAssertTrue(rail.splitsContent)
        }
        XCTAssertEqual(layout(Duo.innerLandscape[0]).contentWidth, 718)
        XCTAssertEqual(layout(Duo.innerLandscape[1]).contentWidth, 632)
    }

    func testEveryUsableSizeOfTheFourScreens() {
        // Widths the app may be given, by heights it may be given, with the screen they belong to.
        // 583 and 669 wide are the open phone upright; 865 and 951 the open phone on its side.
        for height in [466.0, 583, 669, 951] {
            for (width, navigation) in [(865.0, ShellLayout.Navigation.sidebar), (951, .sidebar)] {
                let layout = ShellLayout(width: width, height: height, sceneWidth: 951, sceneHeight: 669)
                XCTAssertEqual(layout.navigation, navigation, "\(width)x\(height)")
                XCTAssertTrue(layout.splitsContent, "\(width)x\(height)")
            }
            for width in [583.0, 669] {
                // The room's own height may be anything (the keyboard takes half of it): the screen is 951 tall.
                let layout = ShellLayout(width: width, height: height, sceneWidth: 669, sceneHeight: 951)
                XCTAssertEqual(layout.navigation, .rail, "\(width)x\(height)")
                XCTAssertFalse(layout.splitsContent)
            }
        }
        // The same widths on a short screen: 669 is wide in its own right, 583 is a phone on its side.
        XCTAssertEqual(ShellLayout(width: 669, height: 466, sceneWidth: 669, sceneHeight: 466).navigation, .rail)
        XCTAssertEqual(ShellLayout(width: 583, height: 466, sceneWidth: 669, sceneHeight: 466).navigation, .tabs)
        XCTAssertEqual(ShellLayout(width: 583, height: 583, sceneWidth: 669, sceneHeight: 599).navigation, .tabs)
        XCTAssertEqual(ShellLayout(width: 583, height: 583, sceneWidth: 669, sceneHeight: 600).navigation, .rail)
    }

    func testTheKeyboardNeverChangesTheArrangement() {
        // The keyboard shrinks the room's height, not the screen's. Typing must not bring the tabs back.
        let before = ShellLayout(width: 583, height: 951, sceneWidth: 669, sceneHeight: 951)
        let typing = ShellLayout(width: 583, height: 520, sceneWidth: 669, sceneHeight: 951)
        XCTAssertEqual(before.navigation, .rail)
        XCTAssertEqual(typing.navigation, .rail)
        XCTAssertEqual(before.contentWidth, typing.contentWidth)
    }

    func testAColumnThatLeavesTooLittleKeepsTabs() {
        // A big screen of which the app is given a sliver (a narrow split view, say): the rail must
        // leave at least a large phone's width, 440 points, or the tabs stay.
        XCTAssertEqual(ShellLayout(width: 509, height: 900, sceneWidth: 1000, sceneHeight: 900).navigation, .rail)
        XCTAssertEqual(ShellLayout(width: 508, height: 900, sceneWidth: 1000, sceneHeight: 900).navigation, .tabs)
        XCTAssertEqual(ShellLayout(width: 380, height: 678, sceneWidth: 669, sceneHeight: 951).navigation, .tabs)
    }

    func testThresholds() {
        XCTAssertEqual(layout((639.0, 800.0)).navigation, .tabs)
        XCTAssertEqual(layout((640.0, 800.0)).navigation, .rail)
        XCTAssertEqual(ShellLayout.splitWidth, 620)
        XCTAssertEqual(ShellLayout.pinnedSidebarWidth, 853)
        XCTAssertEqual(layout((852.0, 800.0)).navigation, .rail, "619 points beside the sidebar is one pane, so it stays a drawer")
        XCTAssertEqual(layout((853.0, 800.0)).navigation, .sidebar)
        XCTAssertTrue(layout((853.0, 800.0)).splitsContent, "the sidebar only stays open where two panes fit beside it")
        XCTAssertFalse(layout((688.0, 800.0)).splitsContent)
        XCTAssertTrue(layout((689.0, 800.0)).splitsContent, "620 points beside the rail")
    }

    func testWideLayoutsTurnedOffKeepsTabsEverywhere() {
        for screen in [Duo.coverLandscape] + Duo.innerPortrait + Duo.innerLandscape {
            let layout = layout(screen, wide: false)
            XCTAssertEqual(layout.navigation, .tabs)
            XCTAssertEqual(layout.contentWidth, screen.width, "the content still gets the real width")
            XCTAssertFalse(layout.splitsContent)
        }
    }

    func testALargerInterfaceGetsAWiderSidebarAndStillTwoPanes() {
        let large = layout(Duo.innerLandscape[0], scale: 1.25)
        XCTAssertEqual(large.sidebarWidth, 290)
        XCTAssertEqual(large.railWidth, 85)
        XCTAssertEqual(large.navigation, .sidebar)
        XCTAssertTrue(large.splitsContent, "660 points beside the wider sidebar")
        // With a system column there is no room for the wider sidebar and two panes: the sidebar
        // becomes a drawer, and the content keeps both panes.
        let squeezed = layout(Duo.innerLandscape[1], scale: 1.25)
        XCTAssertEqual(squeezed.navigation, .rail)
        XCTAssertFalse(squeezed.canPinSidebar)
        XCTAssertTrue(squeezed.splitsContent)
        XCTAssertEqual(layout(Duo.innerLandscape[0], scale: 5).sidebarWidth, layout(Duo.innerLandscape[0], scale: 1.3).sidebarWidth)
        // Upright, the largest interface still leaves the rail its content.
        XCTAssertEqual(layout(Duo.innerPortrait[1], scale: 1.3).navigation, .rail)
    }

    func testSwipeOpensAndClosesTheSidebar() {
        XCTAssertEqual(ShellLayout.swipe(translation: 60, predicted: 80, vertical: 4), .expanded)
        XCTAssertEqual(ShellLayout.swipe(translation: -60, predicted: -80, vertical: 4), .rail)
        XCTAssertNil(ShellLayout.swipe(translation: 10, predicted: 20, vertical: 0), "a nudge does nothing")
        XCTAssertEqual(ShellLayout.swipe(translation: 20, predicted: 120, vertical: 3), .expanded, "a short flick counts")
        XCTAssertNil(ShellLayout.swipe(translation: 50, predicted: 60, vertical: 90), "scrolling the sidebar is not a swipe")
        XCTAssertEqual(SidebarPreference.expanded.toggled, .rail)
        XCTAssertEqual(SidebarPreference.rail.toggled, .expanded)
    }

    func testPaneWidths() {
        XCTAssertEqual(PaneLayout.trailingWidth(content: 619), 0, "no room for two panes")
        XCTAssertEqual(PaneLayout.trailingWidth(content: 632), 310, "the open phone on its side, beside a system column")
        XCTAssertEqual(PaneLayout.trailingWidth(content: 718), 316)
        XCTAssertEqual(PaneLayout.trailingWidth(content: 882), 388)
        XCTAssertEqual(PaneLayout.trailingWidth(content: 882, fraction: 0.9), 547, "the fraction is held to its range")
        XCTAssertEqual(PaneLayout.trailingWidth(content: 660, fraction: 0.62), 350, "the leading pane keeps 310 points")
        // Dragging the divider saves a fraction that gives the same width back.
        for width in [310.0, 400, 500] {
            let fraction = PaneLayout.fraction(trailingWidth: width, content: 882)
            XCTAssertEqual(PaneLayout.trailingWidth(content: 882, fraction: fraction), width, accuracy: 1)
        }
        XCTAssertEqual(PaneLayout.fraction(trailingWidth: 50, content: 882), 310.0 / 882, accuracy: 0.001)
        XCTAssertEqual(PaneLayout.listWidth(content: 632), 310)
        XCTAssertEqual(PaneLayout.listWidth(content: 718), 310)
        XCTAssertEqual(PaneLayout.listWidth(content: 882), 335)
        XCTAssertEqual(PaneLayout.listWidth(content: 1400), 380)
        XCTAssertEqual(PaneLayout.listWidth(content: 500), 500)
    }

    func testDestinationsMatchTheSections() {
        XCTAssertEqual(ShellDestination.allCases.map(\.title), ["Tasks", "Notes", "Agents", "Search"])
        XCTAssertEqual(ShellDestination.tasks.symbol, AppSection.tasks.symbol)
        XCTAssertEqual(ShellDestination.notes.symbol, AppSection.notes.symbol)
        XCTAssertEqual(ShellDestination(.notes), .notes)
        XCTAssertEqual(ShellDestination.tasks.section, .tasks)
        XCTAssertNil(ShellDestination.search.section)
    }
}

/// Folding and unfolding changes how a place is shown and never the place.
final class ShellPresentationTests: XCTestCase {
    private let compact = ShellLayout(width: 380, height: 678)
    private let rail = ShellLayout(width: 669, height: 951)
    private let open = ShellLayout(width: 951, height: 669)

    func testASelectedTaskIsASheetWhenNarrowAndAPaneWhenWide() {
        let place = ShellPlace(destination: .tasks, taskView: .list, selectedTask: "t1")
        XCTAssertEqual(ShellPresentation(place: place, layout: compact).taskDetail, .sheet)
        XCTAssertEqual(ShellPresentation(place: place, layout: rail).taskDetail, .sheet)
        let wide = ShellPresentation(place: place, layout: open)
        XCTAssertEqual(wide.taskDetail, .pane)
        XCTAssertEqual(wide.tasksTrailing, .detail)
    }

    func testATaskIsNeverLostWhateverTheLayout() {
        for destination in ShellDestination.allCases {
            for layout in [compact, rail, open] {
                let shown = ShellPresentation(place: ShellPlace(destination: destination, selectedTask: "t1"), layout: layout)
                XCTAssertNotEqual(shown.taskDetail, .none)
                let hidden = ShellPresentation(place: ShellPlace(destination: destination), layout: layout)
                XCTAssertEqual(hidden.taskDetail, .none)
            }
        }
    }

    func testATaskOpenedFromNotesOrAgentsIsASheetEvenWhenWide() {
        XCTAssertEqual(ShellPresentation(place: ShellPlace(destination: .notes, selectedTask: "t1"), layout: open).taskDetail, .sheet)
        XCTAssertEqual(ShellPresentation(place: ShellPlace(destination: .agents, selectedTask: "t1"), layout: open).taskDetail, .sheet)
        let search = ShellPresentation(place: ShellPlace(destination: .search, selectedTask: "t1"), layout: open)
        XCTAssertEqual(search.taskDetail, .pane)
        XCTAssertTrue(search.searchShowsTask)
        XCTAssertFalse(ShellPresentation(place: ShellPlace(destination: .search, selectedTask: "t1"), layout: compact).searchShowsTask)
    }

    func testAnOpenNoteIsPushedWhenNarrowAndBesideTheBrowserWhenWide() {
        let place = ShellPlace(destination: .notes, notesFiles: ["Personal/Welcome.md"])
        XCTAssertEqual(ShellPresentation(place: place, layout: compact).note, .pushed)
        XCTAssertEqual(ShellPresentation(place: place, layout: rail).note, .pushed)
        XCTAssertEqual(ShellPresentation(place: place, layout: open).note, .pane)
        XCTAssertEqual(ShellPresentation(place: ShellPlace(destination: .notes), layout: open).note, .none)
    }

    func testSearchResultsFollowTheSameRule() {
        let place = ShellPlace(destination: .search, searchFiles: ["a.md"])
        XCTAssertEqual(ShellPresentation(place: place, layout: compact).searchResult, .pushed)
        XCTAssertEqual(ShellPresentation(place: place, layout: open).searchResult, .pane)
    }

    func testTheTrailingPaneOfTasksFollowsTheView() {
        func trailing(_ view: TaskViewKind, task: String? = nil, _ layout: ShellLayout) -> ShellPresentation.TasksTrailing {
            ShellPresentation(place: ShellPlace(taskView: view, selectedTask: task), layout: layout).tasksTrailing
        }
        XCTAssertEqual(trailing(.today, open), .dashboard)
        XCTAssertEqual(trailing(.upcoming, open), .placeholder)
        XCTAssertEqual(trailing(.list, open), .placeholder)
        XCTAssertEqual(trailing(.ready, open), .placeholder)
        XCTAssertEqual(trailing(.calendar, open), .none)
        XCTAssertEqual(trailing(.board, open), .none)
        for view in TaskViewKind.allCases {
            XCTAssertEqual(trailing(view, task: "t1", open), .detail)
            XCTAssertEqual(trailing(view, compact), .none)
            XCTAssertEqual(trailing(view, task: "t1", rail), .none)
        }
    }

    func testTheBoardBecomesUpcomingWhenThereIsNoRoomAndComesBack() {
        let place = ShellPlace(taskView: .board)
        XCTAssertEqual(ShellPresentation(place: place, layout: compact).taskView, .upcoming)
        XCTAssertEqual(ShellPresentation(place: place, layout: rail).taskView, .board)
        XCTAssertEqual(ShellPresentation(place: place, layout: open).taskView, .board)
        XCTAssertEqual(place.taskView, .board, "the saved view is untouched")
        XCTAssertEqual(TaskViewKind.offered(wide: false, ready: false), [.today, .upcoming, .list, .calendar])
        XCTAssertEqual(TaskViewKind.offered(wide: true, ready: false), [.today, .upcoming, .list, .calendar, .board])
        XCTAssertEqual(TaskViewKind.offered(wide: true, ready: true), [.today, .upcoming, .list, .calendar, .board, .ready])
        XCTAssertEqual(TaskViewKind.offered(wide: false, ready: true).last, .ready)
        for view in TaskViewKind.allCases where view != .board {
            XCTAssertEqual(view.effective(wide: false), view)
        }
    }

    func testFoldingAndUnfoldingRoundTrips() {
        // The same place through closed, open, rotated and closed again: nothing about it changes,
        // and each arrangement shows every part of it somewhere.
        let place = ShellPlace(destination: .notes, taskView: .board, selectedTask: "t9", notesFiles: ["a.md", "b.md"], searchFiles: ["c.md"])
        var previous = place
        for layout in [compact, open, rail, compact, open] {
            let shown = ShellPresentation(place: previous, layout: layout)
            XCTAssertNotEqual(shown.note, .none)
            XCTAssertNotEqual(shown.taskDetail, .none)
            XCTAssertNotEqual(shown.searchResult, .none)
            previous = place
        }
        XCTAssertEqual(previous, place)
    }

    func testOpeningAndClosingNotes() {
        var place = ShellPlace(destination: .notes)
        place.openNote("a.md", fromLink: false)
        place.openNote("b.md", fromLink: true)
        XCTAssertEqual(place.notesFiles, ["a.md", "b.md"])
        place.openNote("b.md", fromLink: true)
        XCTAssertEqual(place.notesFiles, ["a.md", "b.md"], "the note already showing isn't opened twice")
        XCTAssertEqual(place.closeNote(), "a.md")
        place.openNote("c.md", fromLink: false)
        XCTAssertEqual(place.notesFiles, ["c.md"], "picking from the browser replaces what was open")
        XCTAssertNil(place.closeNote())
        XCTAssertNil(place.closeNote())
        place.notesFiles = ["a.md", "gone.md"]
        place.searchFiles = ["gone.md"]
        place.prune { $0 != "gone.md" }
        XCTAssertEqual(place.notesFiles, ["a.md"])
        XCTAssertEqual(place.searchFiles, [])
        // A renamed file stays open under its new name, wherever it was open.
        place = ShellPlace(notesFiles: ["a.md", "b.md"], searchFiles: ["b.md"])
        place.rename("b.md", to: "c.md")
        XCTAssertEqual(place.notesFiles, ["a.md", "c.md"])
        XCTAssertEqual(place.searchFiles, ["c.md"])
        place.prune { $0 != "b.md" }
        XCTAssertEqual(place.notesFiles, ["a.md", "c.md"], "nothing is left pointing at the old name")
    }

    func testWeekColumnsOnAnOpenPhone() {
        // An unfolded phone is a compact size class to iOS, but with the sidebar collapsed the week has room.
        XCTAssertEqual(AdaptiveLayout.week(width: 882, compactWidthClass: true), .columns)
        XCTAssertEqual(AdaptiveLayout.week(width: 718, compactWidthClass: true), .tiled)
        XCTAssertEqual(AdaptiveLayout.week(width: 796, compactWidthClass: true), .tiled, "beside a system column the rail leaves 796: tiles")
        XCTAssertEqual(AdaptiveLayout.week(width: 600, compactWidthClass: true), .stacked)
        XCTAssertEqual(AdaptiveLayout.month(width: 698, height: 600, compactWidthClass: true), .split)
    }
}

final class TaskBoardTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func task(_ id: String, due: String?, time: String? = nil, parent: String? = nil, status: TaskStatus = .open) -> PerchTask {
        var task = PerchTask(id: id, path: "Personal/Tasks/\(id).md", title: id)
        task.due = due
        task.time = time
        task.parent = parent
        task.status = status
        return task
    }

    /// Monday 9 November 2026: the week runs to Sunday the 15th.
    private let monday = "2026-11-09"

    func testColumnsOnAMonday() {
        let tasks = [
            task("late", due: "2026-11-02"), task("now", due: monday), task("next", due: "2026-11-10"),
            task("thu", due: "2026-11-12"), task("wed", due: "2026-11-11"), task("far", due: "2026-12-01"),
            task("someday", due: nil), task("child", due: nil, parent: "now"), task("done", due: monday, status: .done),
        ]
        let columns = TaskBoard.columns(tasks, today: monday, calendar: calendar)
        XCTAssertEqual(columns.map(\.title), ["Overdue", "Today", "Tomorrow", "This week", "Later", "No date"])
        XCTAssertEqual(columns.map { $0.tasks.map(\.id) }, [["late"], ["now"], ["next"], ["wed", "thu"], ["far"], ["someday"]])
        XCTAssertEqual(columns.map(\.dropDay), [nil, monday, "2026-11-10", "2026-11-11", "2026-11-16", nil])
        XCTAssertEqual(columns.map(\.acceptsDrops), [false, true, true, true, true, true])
        XCTAssertEqual(Set(columns.map(\.id)).count, columns.count)
    }

    func testOverdueOnlyShowsWhenSomethingIsOverdueAndTheRestAlwaysDo() {
        let columns = TaskBoard.columns([], today: monday, calendar: calendar)
        XCTAssertEqual(columns.map(\.title), ["Today", "Tomorrow", "This week", "Later", "No date"])
        XCTAssertTrue(columns.allSatisfy { $0.tasks.isEmpty })
    }

    func testThisWeekGoesWhenTheWeekIsNearlyOver() {
        // Saturday: tomorrow is the week's last day, so nothing is left for "This week".
        let saturday = "2026-11-14"
        let columns = TaskBoard.columns([task("mon", due: "2026-11-16")], today: saturday, calendar: calendar)
        XCTAssertEqual(columns.map(\.title), ["Today", "Tomorrow", "Later", "No date"])
        XCTAssertEqual(columns[2].tasks.map(\.id), ["mon"])
        XCTAssertEqual(columns[2].dropDay, "2026-11-16", "Later starts the day after tomorrow")
        // Friday: Sunday is still this week.
        let friday = TaskBoard.columns([], today: "2026-11-13", calendar: calendar)
        XCTAssertEqual(friday.map(\.title), ["Today", "Tomorrow", "This week", "Later", "No date"])
        XCTAssertEqual(friday[2].dropDay, "2026-11-15")
        XCTAssertEqual(friday[3].dropDay, "2026-11-16")
    }

    func testTimedTasksComeFirstWithinADay() {
        let columns = TaskBoard.columns([task("b", due: monday), task("a", due: monday, time: "09:00")], today: monday, calendar: calendar)
        XCTAssertEqual(columns[0].tasks.map(\.id), ["a", "b"])
    }

    func testADropOnlyMovesWhatNeedsMoving() {
        let columns = TaskBoard.columns([task("late", due: "2026-11-02")], today: monday, calendar: calendar)
        func column(_ title: String) -> TaskBoard.Column { columns.first { $0.title == title }! }
        let thursday = task("thu", due: "2026-11-12")
        // Already in the column: stays on its own day.
        XCTAssertEqual(TaskBoard.move(thursday, to: column("This week"), today: monday, calendar: calendar), .stay)
        XCTAssertEqual(TaskBoard.move(thursday, to: column("Today"), today: monday, calendar: calendar), .day(monday))
        XCTAssertEqual(TaskBoard.move(thursday, to: column("Tomorrow"), today: monday, calendar: calendar), .day("2026-11-10"))
        XCTAssertEqual(TaskBoard.move(thursday, to: column("Later"), today: monday, calendar: calendar), .day("2026-11-16"))
        XCTAssertEqual(TaskBoard.move(thursday, to: column("No date"), today: monday, calendar: calendar), .clearDate)
        XCTAssertEqual(TaskBoard.move(thursday, to: column("Overdue"), today: monday, calendar: calendar), .stay, "nothing can be made overdue")
        XCTAssertEqual(TaskBoard.move(task("x", due: nil), to: column("No date"), today: monday, calendar: calendar), .stay)
        // A date that can't be read shows under No date; dropped there again it is left as written.
        XCTAssertEqual(TaskBoard.move(task("odd", due: "sometime"), to: column("No date"), today: monday, calendar: calendar), .stay)
        XCTAssertEqual(TaskBoard.move(task("odd", due: "sometime"), to: column("Tomorrow"), today: monday, calendar: calendar), .day("2026-11-10"))
        // Today onto Today, and a subtask with no date onto No date: nothing to do.
        XCTAssertEqual(TaskBoard.move(task("now", due: monday), to: column("Today"), today: monday, calendar: calendar), .stay)
        XCTAssertEqual(TaskBoard.move(task("child", due: nil, parent: "now"), to: column("No date"), today: monday, calendar: calendar), .stay)
        XCTAssertEqual(TaskBoard.move(task("x", due: monday, status: .done), to: column("Tomorrow"), today: monday, calendar: calendar), .stay)
        XCTAssertEqual(TaskBoard.move(task("late", due: "2026-11-02"), to: column("Today"), today: monday, calendar: calendar), .day(monday))
    }

    func testAMoveOnlyChangesTheDate() {
        var original = task("t", due: "2026-11-12", time: "10:30")
        original.recurrence = "every week"
        let columns = TaskBoard.columns([original], today: monday, calendar: calendar)
        guard case let .day(day) = TaskBoard.move(original, to: columns[0], today: monday, calendar: calendar),
              let moved = TaskCalendar.rescheduled(original, to: day) else { return XCTFail("expected a move") }
        var expected = original
        expected.due = monday
        XCTAssertEqual(moved, expected)
    }
}
