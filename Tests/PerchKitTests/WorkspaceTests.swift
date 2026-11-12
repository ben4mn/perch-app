import XCTest
@testable import PerchKit

/// The experimental tabs and split view: the workspace model, its rules for the room it is given,
/// and how a folding phone's two layouts share it.
final class WorkspaceTests: XCTestCase {
    private let today = WorkspaceItem.tasks(.today)
    private let list = WorkspaceItem.tasks(.list)
    private let calendar = WorkspaceItem.tasks(.calendar)
    private let chess = WorkspaceItem.file("Personal/Chess Project.md")
    private let recipes = WorkspaceItem.file("Personal/Recipes.md")
    private let personal = WorkspaceItem.folder("Personal")

    private func check(_ workspace: Workspace, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(workspace.invariantFailures, [], file: file, line: line)
    }

    private func items(_ workspace: Workspace, pane: Int = 0) -> [WorkspaceItem] {
        workspace.panes[pane].tabs.map(\.item)
    }

    // MARK: Items

    func testItemTokensRoundTrip() {
        let all: [WorkspaceItem] = TaskViewKind.allCases.map { .tasks($0) }
            + [.folder(""), personal, .folder("Personal/Daily: notes"), chess, .file("A/B: c.md"), .search]
            + WorkspacePage.allCases.map { .page($0) }
        for item in all {
            XCTAssertEqual(WorkspaceItem(token: item.token), item, item.token)
        }
    }

    func testItemTokensAsTyped() {
        XCTAssertEqual(WorkspaceItem(token: "today"), today)
        XCTAssertEqual(WorkspaceItem(token: "calendar"), calendar)
        XCTAssertEqual(WorkspaceItem(token: "tasks"), today)
        XCTAssertEqual(WorkspaceItem(token: "folder"), .folder(""))
        XCTAssertEqual(WorkspaceItem(token: "notes"), .folder(""))
        XCTAssertEqual(WorkspaceItem(token: "folder:Personal"), personal)
        XCTAssertEqual(WorkspaceItem(token: "file:Personal/Chess Project.md"), chess)
        XCTAssertEqual(WorkspaceItem(token: "insights"), .page(.insights))
        XCTAssertNil(WorkspaceItem(token: "file:"))
        XCTAssertNil(WorkspaceItem(token: "tasks:someday"))
        XCTAssertNil(WorkspaceItem(token: "nowhere"))
        XCTAssertNil(WorkspaceItem(token: ""))
    }

    func testTitlesAndIcons() {
        XCTAssertEqual(today.title, "Today")
        XCTAssertEqual(chess.title, "Chess Project")
        XCTAssertEqual(WorkspaceItem.file("Work/Plan.kanban.md").title, "Plan")
        XCTAssertEqual(WorkspaceItem.file("Work/Plan.kanban.md").symbol, "rectangle.split.3x1")
        XCTAssertEqual(WorkspaceItem.file("Personal/Tasks/call-mum.md").symbol, "checkmark.circle")
        XCTAssertEqual(personal.title, "Personal")
        XCTAssertEqual(WorkspaceItem.folder("Personal/Daily").title, "Daily")
        XCTAssertEqual(WorkspaceItem.folder("").title, "Notes")
        XCTAssertEqual(WorkspaceItem.home(for: .tasks), today)
        XCTAssertEqual(WorkspaceItem.home(for: .notes), .folder(""))
        XCTAssertEqual(chess.section, .notes)
        XCTAssertEqual(calendar.section, .tasks)
        XCTAssertNil(WorkspaceItem.search.section)
    }

    // MARK: Opening

    func testStartsWithOneTab() {
        let workspace = Workspace()
        XCTAssertEqual(workspace.tabCount, 1)
        XCTAssertFalse(workspace.isSplit)
        XCTAssertEqual(workspace.focusedItem, today)
        check(workspace)
    }

    func testOpeningInTheCurrentTabRemembersWhereItWas() {
        var workspace = Workspace()
        workspace.open(personal)
        workspace.open(chess)
        XCTAssertEqual(workspace.tabCount, 1)
        XCTAssertEqual(workspace.focusedItem, chess)
        XCTAssertTrue(workspace.goBack())
        XCTAssertEqual(workspace.focusedItem, personal)
        XCTAssertTrue(workspace.goForward())
        XCTAssertEqual(workspace.focusedItem, chess)
        XCTAssertTrue(workspace.goBack())
        XCTAssertTrue(workspace.goBack())
        XCTAssertEqual(workspace.focusedItem, today)
        XCTAssertFalse(workspace.goBack())
        // Going somewhere new forgets the way forward.
        workspace.open(list)
        XCTAssertFalse(workspace.goForward())
        check(workspace)
    }

    func testOpeningTheSamePlaceAgainAddsNoHistory() {
        var workspace = Workspace()
        workspace.open(today)
        XCTAssertFalse(workspace.focusedTab.canGoBack)
    }

    func testHistoryIsBounded() {
        var workspace = Workspace()
        for index in 0..<100 { workspace.open(.file("Notes/\(index).md")) }
        XCTAssertEqual(workspace.focusedTab.back.count, WorkspaceTab.historyLimit)
        check(workspace)
    }

    func testNewTabGoesAfterTheOneInFrontAndComesForward() {
        var workspace = Workspace()
        workspace.newTab(list)
        workspace.newTab(calendar)
        workspace.select(workspace.panes[0].tabs[0].id)
        XCTAssertTrue(workspace.open(chess, in: .newTab))
        XCTAssertEqual(items(workspace), [today, chess, list, calendar])
        XCTAssertEqual(workspace.focusedItem, chess)
        check(workspace)
    }

    func testOpeningInANewTabReusesATabAlreadyShowingIt() {
        var workspace = Workspace()
        workspace.newTab(chess)
        workspace.newTab(list)
        XCTAssertTrue(workspace.open(chess, in: .newTab))
        XCTAssertEqual(workspace.tabCount, 3)
        XCTAssertEqual(workspace.focusedItem, chess)
        // The + button always makes a tab, even of somewhere already open.
        workspace.newTab(today)
        XCTAssertEqual(workspace.tabCount, 4)
    }

    func testTheTabLimit() {
        var workspace = Workspace()
        for index in 1..<Workspace.maxTabs { XCTAssertTrue(workspace.newTab(.file("Notes/\(index).md"))) }
        XCTAssertTrue(workspace.isFull)
        XCTAssertFalse(workspace.newTab(list))
        XCTAssertFalse(workspace.open(list, in: .newTab))
        XCTAssertFalse(workspace.open(list, in: .otherPane))
        XCTAssertFalse(workspace.split(.horizontal))
        XCTAssertFalse(workspace.duplicate(workspace.focusedTab.id))
        XCTAssertEqual(workspace.tabCount, Workspace.maxTabs)
        // Somewhere already open is still reachable, and the current tab can still go anywhere.
        XCTAssertTrue(workspace.open(.file("Notes/3.md"), in: .newTab))
        XCTAssertTrue(workspace.open(list))
        check(workspace)
    }

    func testDuplicate() {
        var workspace = Workspace(chess)
        XCTAssertTrue(workspace.duplicate(workspace.focusedTab.id))
        XCTAssertEqual(items(workspace), [chess, chess])
        XCTAssertEqual(workspace.panes[0].selectedIndex, 1)
        check(workspace)
    }

    // MARK: Selecting

    func testNextAndPreviousGoRound() {
        var workspace = Workspace()
        workspace.newTab(list)
        workspace.newTab(calendar)
        workspace.selectAdjacent(1)
        XCTAssertEqual(workspace.focusedItem, today)
        workspace.selectAdjacent(-1)
        XCTAssertEqual(workspace.focusedItem, calendar)
        workspace.selectAdjacent(-1)
        XCTAssertEqual(workspace.focusedItem, list)
    }

    func testSelectingATabFocusesItsPane() {
        var workspace = Workspace()
        workspace.open(chess, in: .otherPane)
        XCTAssertEqual(workspace.focus, 1)
        workspace.select(workspace.panes[0].tabs[0].id)
        XCTAssertEqual(workspace.focus, 0)
        XCTAssertEqual(workspace.focusedItem, today)
        workspace.focus(pane: 7)
        XCTAssertEqual(workspace.focus, 1)
        workspace.focus(pane: -2)
        XCTAssertEqual(workspace.focus, 0)
    }

    // MARK: Closing

    func testClosingSelectsTheNeighbor() {
        var workspace = Workspace()
        workspace.newTab(list)
        workspace.newTab(calendar)
        // The middle tab: the one to its right comes forward.
        workspace.select(workspace.panes[0].tabs[1].id)
        workspace.close(workspace.focusedTab.id)
        XCTAssertEqual(workspace.focusedItem, calendar)
        // The last tab: the one to its left.
        workspace.close(workspace.focusedTab.id)
        XCTAssertEqual(workspace.focusedItem, today)
        check(workspace)
    }

    func testClosingATabBehindLeavesTheFrontAlone() {
        var workspace = Workspace()
        workspace.newTab(list)
        workspace.newTab(calendar)
        workspace.close(workspace.panes[0].tabs[0].id)
        XCTAssertEqual(workspace.focusedItem, calendar)
        XCTAssertEqual(items(workspace), [list, calendar])
    }

    func testClosingTheLastTabLeavesHome() {
        var workspace = Workspace(chess)
        let old = workspace.focusedTab.id
        workspace.close(old, home: .folder(""))
        XCTAssertEqual(workspace.tabCount, 1)
        XCTAssertEqual(workspace.focusedItem, .folder(""))
        XCTAssertNotEqual(workspace.focusedTab.id, old)
        // And the note can be brought back.
        XCTAssertTrue(workspace.reopenClosed())
        XCTAssertEqual(workspace.focusedItem, chess)
        // Closing home itself is not worth remembering.
        var home = Workspace()
        home.close(home.focusedTab.id)
        XCTAssertFalse(home.canReopen)
        check(workspace)
        check(home)
    }

    func testClosingAPanesLastTabClosesTheSplit() {
        var workspace = Workspace()
        workspace.open(chess, in: .otherPane)
        XCTAssertTrue(workspace.isSplit)
        workspace.close(workspace.focusedTab.id)
        XCTAssertFalse(workspace.isSplit)
        XCTAssertEqual(workspace.focus, 0)
        XCTAssertEqual(workspace.focusedItem, today)
        // The first pane's last tab: the second pane becomes the only one.
        workspace.open(chess, in: .otherPane)
        workspace.close(workspace.panes[0].tabs[0].id)
        XCTAssertFalse(workspace.isSplit)
        XCTAssertEqual(workspace.focusedItem, chess)
        check(workspace)
    }

    func testCloseOthers() {
        var workspace = Workspace()
        workspace.newTab(list)
        workspace.newTab(calendar)
        workspace.open(chess, in: .otherPane)
        let keep = workspace.panes[0].tabs[1].id
        workspace.closeOthers(keeping: keep)
        XCTAssertEqual(items(workspace), [list])
        XCTAssertEqual(workspace.focus, 0)
        // The other pane is not touched.
        XCTAssertEqual(items(workspace, pane: 1), [chess])
        XCTAssertEqual(workspace.closed.map(\.item), [today, calendar])
        check(workspace)
    }

    func testReopenPutsTheTabBackWhereItWas() {
        var workspace = Workspace()
        workspace.newTab(list)
        workspace.newTab(calendar)
        workspace.close(workspace.panes[0].tabs[1].id)
        XCTAssertTrue(workspace.reopenClosed())
        XCTAssertEqual(items(workspace), [today, list, calendar])
        XCTAssertEqual(workspace.focusedItem, list)
        XCTAssertFalse(workspace.reopenClosed())
    }

    func testClosedTabsAreBounded() {
        var workspace = Workspace()
        for index in 0..<40 {
            workspace.newTab(.file("Notes/\(index).md"))
            workspace.close(workspace.focusedTab.id)
        }
        XCTAssertEqual(workspace.closed.count, Workspace.closedLimit)
        XCTAssertEqual(workspace.closed.last?.item, .file("Notes/39.md"))
        check(workspace)
    }

    func testReopenIntoAPaneThatHasGone() {
        var workspace = Workspace()
        workspace.open(chess, in: .otherPane)
        workspace.newTab(recipes)
        workspace.close(workspace.focusedTab.id)
        workspace.closeSplit()
        XCTAssertTrue(workspace.reopenClosed())
        XCTAssertEqual(workspace.focusedItem, recipes)
        check(workspace)
    }

    // MARK: Splitting and moving

    func testSplitShowsTheSamePlaceAgainOrSomethingElse() {
        var same = Workspace(chess)
        XCTAssertTrue(same.split(.horizontal))
        XCTAssertEqual(items(same, pane: 1), [chess])
        XCTAssertEqual(same.focus, 1)
        var other = Workspace(list)
        XCTAssertTrue(other.split(.vertical, showing: calendar))
        XCTAssertEqual(other.axis, .vertical)
        XCTAssertEqual(other.focusedItem, calendar)
        // Splitting again only turns the split.
        XCTAssertTrue(other.split(.horizontal))
        XCTAssertEqual(other.panes.count, 2)
        XCTAssertEqual(other.axis, .horizontal)
        check(same)
        check(other)
    }

    func testOpenToTheSide() {
        var workspace = Workspace(list)
        XCTAssertTrue(workspace.open(chess, in: .otherPane))
        XCTAssertEqual(workspace.focus, 1)
        // From the second pane, the side is the first.
        XCTAssertTrue(workspace.open(calendar, in: .otherPane))
        XCTAssertEqual(workspace.focus, 0)
        XCTAssertEqual(items(workspace), [list, calendar])
        // Already open there: that tab comes forward, and no new one is made.
        workspace.focus(pane: 1)
        XCTAssertTrue(workspace.open(list, in: .otherPane))
        XCTAssertEqual(items(workspace), [list, calendar])
        XCTAssertEqual(workspace.focusedItem, list)
        check(workspace)
    }

    func testCloseSplitKeepsEveryTab() {
        var workspace = Workspace()
        workspace.newTab(list)
        workspace.open(chess, in: .otherPane)
        workspace.newTab(recipes)
        workspace.select(workspace.panes[1].tabs[0].id)
        workspace.closeSplit()
        XCTAssertEqual(items(workspace), [today, list, chess, recipes])
        XCTAssertEqual(workspace.focusedItem, chess)
        check(workspace)
    }

    func testReorderingWithinAPane() {
        var workspace = Workspace()
        workspace.newTab(list)
        workspace.newTab(calendar)
        let first = workspace.panes[0].tabs[0].id
        // Dropped before the tab at index 2: it lands between List and Calendar.
        workspace.move(first, toPane: 0, at: 2)
        XCTAssertEqual(items(workspace), [list, today, calendar])
        workspace.move(first, toPane: 0)
        XCTAssertEqual(items(workspace), [list, calendar, today])
        workspace.move(first, toPane: 0, at: 0)
        XCTAssertEqual(items(workspace), [today, list, calendar])
        XCTAssertEqual(workspace.focusedItem, today)
        check(workspace)
    }

    func testMovingATabToTheOtherPane() {
        var workspace = Workspace()
        workspace.newTab(list)
        workspace.newTab(calendar)
        let moved = workspace.panes[0].tabs[1].id
        // Dragged to the edge of an unsplit workspace: that makes the split.
        workspace.move(moved, toPane: 1, axis: .vertical)
        XCTAssertTrue(workspace.isSplit)
        XCTAssertEqual(workspace.axis, .vertical)
        XCTAssertEqual(items(workspace), [today, calendar])
        XCTAssertEqual(items(workspace, pane: 1), [list])
        XCTAssertEqual(workspace.focus, 1)
        // And back, between the two that stayed.
        workspace.move(moved, toPane: 0, at: 1)
        XCTAssertFalse(workspace.isSplit)
        XCTAssertEqual(items(workspace), [today, list, calendar])
        XCTAssertEqual(workspace.focusedItem, list)
        check(workspace)
    }

    func testALoneTabCannotLeaveForANewPane() {
        var workspace = Workspace()
        workspace.move(workspace.focusedTab.id, toPane: 1)
        XCTAssertFalse(workspace.isSplit)
        workspace.move("nothing", toPane: 0)
        workspace.move(workspace.focusedTab.id, toPane: 5)
        check(workspace)
    }

    func testMovingTheTabInFrontBringsItsNeighborForward() {
        var workspace = Workspace()
        workspace.newTab(list)
        workspace.open(chess, in: .otherPane)
        let front = workspace.panes[0].selectedID
        workspace.move(front, toPane: 1)
        XCTAssertEqual(workspace.panes[0].selected.item, today)
        XCTAssertEqual(items(workspace, pane: 1), [chess, list])
        check(workspace)
    }

    func testSwappingPanesKeepsTheFocusWithItsPane() {
        var workspace = Workspace(list)
        workspace.open(chess, in: .otherPane)
        workspace.setFraction(0.3)
        workspace.swapPanes()
        XCTAssertEqual(items(workspace), [chess])
        XCTAssertEqual(items(workspace, pane: 1), [list])
        XCTAssertEqual(workspace.focusedItem, chess)
        XCTAssertEqual(workspace.fraction, 0.7, accuracy: 0.0001)
        var single = Workspace()
        single.swapPanes()
        XCTAssertEqual(single, Workspace())
        check(workspace)
    }

    func testFractionIsKeptInRange() {
        var workspace = Workspace()
        workspace.setFraction(0.9)
        XCTAssertEqual(workspace.fraction, 0.75)
        workspace.setFraction(-3)
        XCTAssertEqual(workspace.fraction, 0.25)
        workspace.setFraction(.nan)
        XCTAssertEqual(workspace.fraction, 0.5)
    }

    // MARK: Files that change

    func testARenamedNoteKeepsItsTabs() {
        var workspace = Workspace(personal)
        workspace.open(chess)
        workspace.open(chess, in: .otherPane)
        workspace.newTab(recipes)
        workspace.close(workspace.focusedTab.id)
        workspace.renamed(from: "Personal/Chess Project.md", to: "Personal/Chess Club.md")
        let club = WorkspaceItem.file("Personal/Chess Club.md")
        XCTAssertEqual(items(workspace), [club])
        XCTAssertEqual(items(workspace, pane: 1), [club])
        XCTAssertEqual(workspace.focusedTab.title, "Chess Club")
        // A folder moved: everything inside follows, in tabs, their history and the closed tabs.
        workspace.renamed(from: "Personal", to: "Home")
        XCTAssertEqual(items(workspace), [.file("Home/Chess Club.md")])
        XCTAssertEqual(workspace.panes[0].tabs[0].back, [.folder("Home")])
        XCTAssertEqual(workspace.closed.map(\.item), [.file("Home/Recipes.md")])
        // A name that only starts the same is someone else.
        workspace.renamed(from: "Hom", to: "X")
        XCTAssertEqual(items(workspace), [.file("Home/Chess Club.md")])
        check(workspace)
    }

    func testADeletedNoteIsMarkedMissingAndComesBack() {
        var workspace = Workspace(today)
        workspace.newTab(chess)
        workspace.open(recipes)
        workspace.newTab(.folder("Personal/Daily"))
        var gone: Set<String> = ["Personal/Chess Project.md", "Personal/Recipes.md"]
        func validate() {
            workspace.validate(fileExists: { !gone.contains($0) }, folder: { $0 == "Personal/Daily" ? "Personal" : $0 })
        }
        validate()
        XCTAssertTrue(workspace.panes[0].tabs[1].isMissing)
        XCTAssertEqual(workspace.panes[0].tabs[1].symbol, "questionmark.folder")
        // Its history no longer leads to the other file that went.
        XCTAssertEqual(workspace.panes[0].tabs[1].back, [])
        // The folder that went became the nearest one that exists.
        XCTAssertEqual(workspace.panes[0].tabs[2].item, personal)
        XCTAssertFalse(workspace.panes[0].tabs[0].isMissing)
        // Synced back from another device: the tab works again.
        gone = []
        validate()
        XCTAssertFalse(workspace.panes[0].tabs[1].isMissing)
        check(workspace)
    }

    func testMissingTabsAreDroppedOnRestoreAndNotRemembered() {
        var workspace = Workspace(chess)
        workspace.open(recipes, in: .otherPane)
        workspace.validate(fileExists: { _ in false }, folder: { $0 })
        workspace.dropMissing(home: .folder(""))
        XCTAssertFalse(workspace.isSplit)
        XCTAssertEqual(items(workspace), [.folder("")])
        XCTAssertFalse(workspace.canReopen)
        check(workspace)
    }

    func testGoingSomewhereElseClearsMissing() {
        var workspace = Workspace(chess)
        workspace.validate(fileExists: { _ in false }, folder: { $0 })
        XCTAssertTrue(workspace.focusedTab.isMissing)
        workspace.open(personal)
        XCTAssertFalse(workspace.focusedTab.isMissing)
    }

    // MARK: Saving

    func testRoundTripsThroughData() {
        var workspace = Workspace()
        workspace.newTab(list)
        workspace.open(chess)
        workspace.open(calendar, in: .otherPane)
        workspace.newTab(.search)
        workspace.close(workspace.focusedTab.id)
        workspace.setFraction(0.4)
        workspace.split(.vertical)
        let restored = Workspace.decoded(workspace.encoded())
        XCTAssertEqual(restored, workspace)
        check(restored ?? Workspace())
    }

    func testRubbishIsNotAWorkspace() {
        XCTAssertNil(Workspace.decoded(nil))
        XCTAssertNil(Workspace.decoded(Data("{}".utf8)))
        XCTAssertNil(Workspace.decoded(Data("not json".utf8)))
    }

    func testAPlaceThatNoLongerExistsAsAKindIsNotAWorkspace() throws {
        let data = try XCTUnwrap(Workspace().encoded())
        let text = try XCTUnwrap(String(data: data, encoding: .utf8)).replacingOccurrences(of: "tasks:today", with: "tasks:someday")
        XCTAssertNil(Workspace.decoded(Data(text.utf8)))
    }

    func testDamagedBookkeepingIsPutRight() {
        var workspace = Workspace()
        workspace.newTab(list)
        workspace.open(chess, in: .otherPane)
        // Two tabs with one id, a selection that isn't a tab, an empty pane, focus on nothing.
        workspace.panes[0].tabs[1] = WorkspaceTab(id: workspace.panes[0].tabs[0].id, item: list)
        workspace.panes[0].selectedID = "gone"
        workspace.panes.append(WorkspacePane(tabs: [], selectedID: ""))
        workspace.panes.append(WorkspacePane(tabs: [WorkspaceTab(id: "t99", item: recipes)], selectedID: "t99"))
        workspace.focus = 9
        workspace.fraction = 4
        workspace.nextID = 0
        var fixed = workspace.sanitized()
        check(fixed)
        XCTAssertEqual(fixed.panes.count, 2)
        XCTAssertEqual(items(fixed), [today, list])
        XCTAssertEqual(items(fixed, pane: 1), [chess, recipes])
        XCTAssertEqual(fixed.focus, 1)
        // A new tab can't take an id that is in use.
        fixed.newTab(calendar)
        check(fixed)
    }

    func testTooManyTabsAreTrimmedFromTheEnd() {
        var workspace = Workspace()
        workspace.open(chess, in: .otherPane)
        for index in 0..<40 {
            workspace.panes[1].tabs.append(WorkspaceTab(id: "x\(index)", item: .file("Notes/\(index).md")))
        }
        workspace.panes[1].selectedID = "x39"
        let fixed = workspace.sanitized()
        check(fixed)
        XCTAssertEqual(fixed.tabCount, Workspace.maxTabs)
        XCTAssertEqual(fixed.panes[0].tabs.count, 1)
        XCTAssertEqual(fixed.panes[1].selectedIndex, 0)
        XCTAssertEqual(Workspace(panesForTest: []).sanitized().tabCount, 1)
    }

    // MARK: Any sequence of operations

    private struct Random: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    func testInvariantsHoldUnderRandomOperations() {
        let places: [WorkspaceItem] = [today, list, calendar, chess, recipes, personal, .folder(""), .search, .page(.insights), .file("Work/Plan.kanban.md")]
        for seed in 1...60 {
            var random = Random(state: UInt64(seed))
            var workspace = Workspace()
            var log: [String] = []
            for _ in 0..<400 {
                let place = places.randomElement(using: &random)!
                let ids = workspace.panes.flatMap { $0.tabs.map(\.id) }
                let id = Int.random(in: 0..<12, using: &random) == 0 ? "missing" : ids.randomElement(using: &random)!
                let step = Int.random(in: 0..<23, using: &random)
                switch step {
                case 0: workspace.open(place)
                case 1: workspace.open(place, in: .newTab)
                case 2: workspace.open(place, in: .otherPane)
                case 3: workspace.newTab(place)
                case 4: workspace.close(id, home: place)
                case 5: workspace.closeOthers(keeping: id)
                case 6: workspace.reopenClosed()
                case 7: workspace.duplicate(id)
                case 8: workspace.select(id)
                case 9: workspace.selectAdjacent(Int.random(in: -3...3, using: &random))
                case 10: workspace.focus(pane: Int.random(in: -1...3, using: &random))
                case 11: workspace.split(Bool.random(using: &random) ? .horizontal : .vertical, showing: Bool.random(using: &random) ? place : nil)
                case 12: workspace.closeSplit()
                case 13: workspace.move(id, toPane: Int.random(in: -1...2, using: &random), at: Bool.random(using: &random) ? Int.random(in: -2...30, using: &random) : nil)
                case 14: workspace.goBack()
                case 15: workspace.goForward()
                case 16: workspace.setFraction(Double.random(in: -1...2, using: &random))
                case 17: workspace.renamed(from: "Personal", to: "Home")
                case 18: workspace.renamed(from: "Home", to: "Personal")
                case 19:
                    let coin = Bool.random(using: &random)
                    workspace.validate(fileExists: { _ in coin }, folder: { coin ? $0 : "" })
                case 20: workspace.dropMissing(home: place)
                case 21: workspace.swapPanes()
                default: workspace.adopt(place)
                }
                log.append("\(step)")
                let failures = workspace.invariantFailures
                if !failures.isEmpty {
                    XCTFail("seed \(seed) after \(log.suffix(12).joined(separator: ",")): \(failures)")
                    return
                }
                // Whatever state it reaches is one it can be saved in and read back from, unchanged.
                if step % 5 == 0 {
                    XCTAssertEqual(Workspace.decoded(workspace.encoded()), workspace, "seed \(seed)")
                    XCTAssertEqual(workspace.sanitized(), workspace, "seed \(seed)")
                }
            }
        }
    }

    // MARK: One place, two arrangements

    func testEveryPhonePlaceSurvivesFoldingAndUnfolding() {
        // Unfolded, the focused tab shows a place; folded, the tab bar shows `shellPlace`; unfolded
        // again, the item read back from the shell is the one that was there.
        let places: [WorkspaceItem] = TaskViewKind.allCases.map { .tasks($0) } + [.folder(""), personal, chess, .search, .page(.agents)]
        for item in places {
            let place = item.shellPlace
            let back = WorkspaceItem(
                destination: place.destination, taskView: place.taskView ?? .today,
                notesFolder: place.notesFolder ?? "Elsewhere", openNote: place.notesFile
            )
            XCTAssertEqual(back, item, item.token)
        }
    }

    func testAFoldedPhoneShowsTheFocusedTab() {
        var workspace = Workspace(list)
        workspace.open(chess, in: .otherPane)
        XCTAssertEqual(workspace.focusedItem.shellPlace, WorkspaceShellPlace(destination: .notes, notesFile: "Personal/Chess Project.md"))
        workspace.focus(pane: 0)
        XCTAssertEqual(workspace.focusedItem.shellPlace, WorkspaceShellPlace(destination: .tasks, taskView: .list))
        XCTAssertEqual(WorkspaceItem.folder("Personal").shellPlace, WorkspaceShellPlace(destination: .notes, notesFolder: "Personal"))
        // The Mac's own pages have nowhere on the phone.
        XCTAssertEqual(WorkspaceItem.page(.settings).shellPlace.destination, .tasks)
    }

    func testUnfoldingKeepsTheWorkspaceAndFollowsWhereTheFoldedPhoneWent() {
        var workspace = Workspace(list)
        workspace.newTab(calendar)
        workspace.open(chess, in: .otherPane)
        let before = workspace
        // Nothing was touched while folded: the workspace is exactly as it was.
        workspace.adopt(WorkspaceItem(destination: .notes, taskView: .calendar, notesFolder: "", openNote: "Personal/Chess Project.md"))
        XCTAssertEqual(workspace, before)
        // Folded, the user went to Recipes: the focused tab follows, and Back returns to the chess note.
        workspace.adopt(recipes)
        XCTAssertEqual(workspace.focusedItem, recipes)
        XCTAssertEqual(workspace.focus, 1)
        XCTAssertEqual(items(workspace), [list, calendar])
        XCTAssertEqual(workspace.focusedTab.back, [chess])
        check(workspace)
    }

    // MARK: Room for two panes

    func testTheFoldingPhonesScreens() {
        typealias Layout = WorkspaceLayout
        // Open, on its side: 718 points beside the sidebar, 632 if the system keeps a column, 882 beside the rail.
        for width in [718.0, 632, 882] {
            XCTAssertEqual(Layout.arrangement(width: width, height: 620, isSplit: true), .sideBySide, "\(width)")
        }
        // Open, upright: 600 beside the rail (514 with a column) is too narrow for two, so they stack.
        for width in [600.0, 514] {
            XCTAssertEqual(Layout.arrangement(width: width, height: 870, isSplit: true), .stacked, "\(width)")
        }
        // The cover screen never gets there (it has tabs, not a workspace), and would show one pane anyway.
        XCTAssertEqual(Layout.arrangement(width: 380, height: 600, isSplit: true), .single)
        XCTAssertEqual(Layout.arrangement(width: 594, height: 380, isSplit: true), .single)
        // An ordinary phone on its side with the sidebar folded: wide enough, far too short to stack.
        XCTAssertEqual(Layout.arrangement(width: 760, height: 380, isSplit: true), .sideBySide)
        // One pane is one pane, whatever the room.
        XCTAssertEqual(Layout.arrangement(width: 2000, height: 2000, isSplit: false), .single)
    }

    func testTheMacHonorsTheWayItWasSplitWhereItFits() {
        typealias Layout = WorkspaceLayout
        func arrangement(_ width: Double, _ height: Double, _ axis: SplitAxis) -> Layout.Arrangement {
            Layout.arrangement(width: width, height: height, isSplit: true, preferred: axis, minimumWidth: 280, minimumHeight: 220)
        }
        XCTAssertEqual(arrangement(900, 700, .horizontal), .sideBySide)
        XCTAssertEqual(arrangement(900, 700, .vertical), .stacked)
        // Split down in a short window: beside each other instead.
        XCTAssertEqual(arrangement(900, 400, .vertical), .sideBySide)
        // Split right in a narrow window: stacked instead.
        XCTAssertEqual(arrangement(500, 700, .horizontal), .stacked)
        XCTAssertEqual(arrangement(500, 400, .horizontal), .single)
        // Exactly enough: two panes and the line between them.
        XCTAssertEqual(arrangement(561, 300, .horizontal), .sideBySide)
        XCTAssertEqual(arrangement(560, 300, .horizontal), .single)
    }

    func testPaneLengths() {
        typealias Layout = WorkspaceLayout
        XCTAssertEqual(Layout.firstLength(total: 801, fraction: 0.5, minimum: 310), 400)
        // The saved share never squeezes either pane under the minimum.
        XCTAssertEqual(Layout.firstLength(total: 718, fraction: 0.25, minimum: 310), 310)
        XCTAssertEqual(Layout.firstLength(total: 718, fraction: 0.75, minimum: 310), 718 - 1 - 310)
        // No room for the minimum on both sides: halves.
        XCTAssertEqual(Layout.firstLength(total: 401, fraction: 0.7, minimum: 310), 200)
        // Dragging: the share saved is the one that gives that length back.
        let fraction = Layout.fraction(firstLength: 500, total: 1001, minimum: 310)
        XCTAssertEqual(Layout.firstLength(total: 1001, fraction: fraction, minimum: 310), 500)
        XCTAssertEqual(Layout.fraction(firstLength: 5000, total: 1001, minimum: 310), 0.69, accuracy: 0.001)
        XCTAssertEqual(Layout.fraction(firstLength: -40, total: 1001, minimum: 310), 0.31, accuracy: 0.001)
        XCTAssertEqual(Layout.fraction(firstLength: 10, total: 0, minimum: 310), 0.5)
    }

    func testWorkspaceThresholdsAgainstTheShellLayout() {
        // The numbers above come from the shell's own arithmetic for the open folding phone.
        let landscape = ShellLayout(width: 951, height: 669)
        XCTAssertEqual(landscape.contentWidth, 718)
        XCTAssertEqual(WorkspaceLayout.arrangement(width: landscape.contentWidth, height: landscape.height, isSplit: true), .sideBySide)
        let portrait = ShellLayout(width: 669, height: 951)
        XCTAssertEqual(portrait.navigation, .rail)
        XCTAssertEqual(WorkspaceLayout.arrangement(width: portrait.contentWidth, height: portrait.height, isSplit: true), .stacked)
        // The cover screen is not wide: no workspace is drawn there at all.
        XCTAssertFalse(ShellLayout(width: 380, height: 678, sceneWidth: 466, sceneHeight: 678).isWide)
        XCTAssertFalse(ShellLayout(width: 594, height: 432, sceneWidth: 678, sceneHeight: 466).isWide)
    }

    // MARK: Saved workspaces

    func testSavingNamedLayouts() {
        var planning = Workspace(today)
        planning.open(chess)
        planning.open(calendar, in: .otherPane)
        planning.newTab(list)
        planning.close(planning.focusedTab.id)
        var saved = SavedWorkspaces()
        XCTAssertTrue(saved.save(planning, as: "  Planning \n"))
        XCTAssertEqual(saved.items.map(\.name), ["Planning"])
        // The layout is kept; history and closed tabs are not.
        let layout = saved.layout(named: "planning")
        XCTAssertEqual(layout?.panes.map { $0.tabs.map(\.item) }, [[chess], [calendar]])
        XCTAssertEqual(layout?.closed, [])
        XCTAssertEqual(layout?.panes[0].tabs[0].back, [])
        // The same name again replaces it.
        XCTAssertTrue(saved.save(Workspace(list), as: "PLANNING"))
        XCTAssertEqual(saved.items.count, 1)
        XCTAssertEqual(saved.layout(named: "Planning")?.focusedItem, list)
        XCTAssertFalse(saved.save(planning, as: "   "))
        XCTAssertFalse(saved.save(planning, as: String(repeating: "x", count: 41)))
    }

    func testRenamingAndDeletingLayouts() {
        var saved = SavedWorkspaces()
        saved.save(Workspace(today), as: "Planning")
        saved.save(Workspace(chess), as: "Writing")
        XCTAssertFalse(saved.rename("Planning", to: "writing"))
        XCTAssertFalse(saved.rename("Planning", to: ""))
        XCTAssertFalse(saved.rename("Nothing", to: "Something"))
        XCTAssertTrue(saved.rename("Planning", to: "Week"))
        XCTAssertTrue(saved.rename("Week", to: "week"))
        XCTAssertEqual(saved.items.map(\.name), ["week", "Writing"])
        saved.delete("WRITING")
        XCTAssertEqual(saved.items.map(\.name), ["week"])
        XCTAssertNil(saved.layout(named: "Writing"))
    }

    func testAtMostEightLayouts() {
        var saved = SavedWorkspaces()
        for index in 0..<SavedWorkspaces.limit { XCTAssertTrue(saved.save(Workspace(), as: "Layout \(index)")) }
        XCTAssertTrue(saved.isFull)
        XCTAssertFalse(saved.save(Workspace(), as: "One more"))
        // Replacing one is still allowed.
        XCTAssertTrue(saved.save(Workspace(list), as: "Layout 3"))
        let restored = SavedWorkspaces.decoded(saved.encoded())
        XCTAssertEqual(restored, saved)
        XCTAssertEqual(SavedWorkspaces.decoded(Data("nope".utf8)), SavedWorkspaces())
    }
}

private extension Workspace {
    /// A workspace in a state the app can't reach, for testing `sanitized`.
    init(panesForTest panes: [WorkspacePane]) {
        self.init()
        self.panes = panes
    }
}
