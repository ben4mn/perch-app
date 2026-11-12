import XCTest
@testable import PerchKit
@testable import PerchUI

/// The experimental tabs and split view, where it meets the app: the focused tab mirrors the app's one
/// place, a workspace survives a relaunch, and two panes showing one note can't disagree about it.
@MainActor
final class WorkspaceStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("perch-tabs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Personal"), withIntermediateDirectories: true)
        try "# Chess\n".write(to: root.appendingPathComponent("Personal/Chess.md"), atomically: true, encoding: .utf8)
        try "# Rules\n".write(to: root.appendingPathComponent("Personal/Rules.md"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        setTabs(nil)
        try? FileManager.default.removeItem(at: root)
    }

    private func bareModel() -> AppModel {
        AppModel(supportDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("perch-support-\(UUID().uuidString)"))
    }

    private func openModel() async -> AppModel {
        let model = bareModel()
        model.open(root: root, engine: nil)
        await model.reload(force: true)
        addTeardownBlock { await model.close() }
        return model
    }

    /// Turns the setting on or off for this process only, the way a launch argument would. Nothing is saved.
    private func setTabs(_ on: Bool?) {
        var volatile = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        volatile[WorkspaceStore.settingKey] = on
        UserDefaults.standard.setVolatileDomain(volatile, forName: UserDefaults.argumentDomain)
    }

    /// Lets work queued on the main queue run.
    private func settle() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }

    private let chess = WorkspaceItem.file("Personal/Chess.md")
    private let rules = WorkspaceItem.file("Personal/Rules.md")

    // MARK: The Mac: the route is the place

    func testRoutesAndItemsAgree() {
        let routes: [Route] = [.today, .upcoming, .ready, .list, .calendar, .board, .file("a.md"), .folder(""), .folder("Personal"), .search, .insights, .activity, .importer, .settings]
        for route in routes {
            XCTAssertEqual(WorkspaceItem(route)?.route, route, "\(route)")
        }
        XCTAssertEqual(WorkspaceItem(.week), .tasks(.calendar))
        // An area is a scope, not a place.
        XCTAssertNil(WorkspaceItem(.area("Personal")))
    }

    func testNothingHappensUntilAWorkspaceIsOnScreen() {
        let model = bareModel()
        let store = WorkspaceStore(model: model, defaults: nil)
        model.route = .folder("Personal")
        store.newTab()
        XCTAssertEqual(model.route, .folder("Personal"))
        XCTAssertEqual(store.workspace.panes[0].tabs.first?.item, .tasks(.today))
        XCTAssertFalse(store.isActive)
    }

    func testTheFocusedTabFollowsTheRoute() {
        let model = bareModel()
        let store = WorkspaceStore(model: model, defaults: nil)
        store.activate()
        model.route = .folder("Personal")
        model.route = .file("Personal/Chess.md")
        XCTAssertEqual(store.workspace.tabCount, 1)
        XCTAssertEqual(store.workspace.focusedItem, chess)
        XCTAssertEqual(store.workspace.focusedTab.back, [.tasks(.today), .folder("Personal")])
        // An area sets the scope and shows the List: the tab ends up there, with one step of history.
        model.route = .area("Personal")
        XCTAssertEqual(store.workspace.focusedItem, .tasks(.list))
        XCTAssertEqual(store.workspace.focusedTab.back.count, 3)
        XCTAssertEqual(store.workspace.invariantFailures, [])
    }

    func testBringingATabForwardMovesTheApp() {
        let model = bareModel()
        let store = WorkspaceStore(model: model, defaults: nil)
        store.activate()
        store.open(chess, in: .newTab)
        XCTAssertEqual(model.route, .file("Personal/Chess.md"))
        XCTAssertEqual(model.section, .notes)
        store.select(store.workspace.panes[0].tabs[0].id)
        XCTAssertEqual(model.route, .today)
        XCTAssertEqual(model.section, .tasks)
        store.selectAdjacent(1)
        XCTAssertEqual(model.route, .file("Personal/Chess.md"))
        store.goBack()
        XCTAssertEqual(model.route, .file("Personal/Chess.md"), "a new tab has nowhere to go back to")
        store.closeFocusedTab()
        XCTAssertEqual(model.route, .today)
        store.reopenClosedTab()
        XCTAssertEqual(model.route, .file("Personal/Chess.md"))
        // The app's moves never loop back as new history.
        XCTAssertEqual(store.workspace.focusedTab.back, [])
    }

    func testThePaneWithTheFocusIsTheAppsPlace() {
        let model = bareModel()
        let store = WorkspaceStore(model: model, defaults: nil)
        store.activate()
        model.route = .list
        store.open(chess, in: .otherPane)
        XCTAssertEqual(model.route, .file("Personal/Chess.md"))
        // Going somewhere now happens in the second pane, and the first is untouched.
        model.route = .file("Personal/Rules.md")
        XCTAssertEqual(store.workspace.panes.map(\.selected.item), [.tasks(.list), rules])
        store.focus(pane: 0)
        XCTAssertEqual(model.route, .list)
        model.route = .calendar
        XCTAssertEqual(store.workspace.panes.map(\.selected.item), [.tasks(.calendar), rules])
        store.closeSplit()
        XCTAssertEqual(model.route, .calendar)
        XCTAssertEqual(store.workspace.tabCount, 2)
    }

    func testTurningTabsOnPicksUpWhereTheAppIs() {
        let model = bareModel()
        let store = WorkspaceStore(model: model, defaults: nil)
        store.activate()
        store.open(chess, in: .newTab)
        store.deactivate()
        // With tabs off the app carries on by itself.
        model.route = .calendar
        XCTAssertEqual(store.workspace.focusedItem, chess)
        store.activate()
        XCTAssertEqual(store.workspace.focusedItem, .tasks(.calendar))
        XCTAssertEqual(store.workspace.focusedTab.back, [chess])
        XCTAssertEqual(store.workspace.tabCount, 2)
    }

    func testTheTabLimitSaysSo() {
        let model = bareModel()
        let store = WorkspaceStore(model: model, defaults: nil)
        store.activate()
        for _ in 1..<Workspace.maxTabs { store.newTab() }
        XCTAssertNil(model.banner)
        store.newTab()
        XCTAssertEqual(store.workspace.tabCount, Workspace.maxTabs)
        XCTAssertNotNil(model.banner)
    }

    // MARK: Saving

    func testAWorkspaceSurvivesARelaunchAndSavedLayoutsToo() throws {
        let suite = "perch-tabs-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = bareModel()
        let store = WorkspaceStore(model: model, defaults: defaults)
        store.activate()
        store.open(.tasks(.calendar), in: .otherPane)
        store.saveWorkspace(as: "Planning")
        store.closeSplit()
        store.open(chess, in: .newTab)

        let again = WorkspaceStore(model: bareModel(), defaults: defaults)
        XCTAssertEqual(again.workspace, store.workspace)
        XCTAssertEqual(again.saved.items.map(\.name), ["Planning"])
        again.activate()
        again.showWorkspace("Planning")
        XCTAssertEqual(again.workspace.panes.map(\.selected.item), [.tasks(.today), .tasks(.calendar)])
        XCTAssertEqual(again.model.route, .calendar)
        again.renameWorkspace("Planning", to: "Week")
        again.deleteWorkspace("Nothing")
        XCTAssertEqual(WorkspaceStore(model: bareModel(), defaults: defaults).saved.items.map(\.name), ["Week"])
        again.deleteWorkspace("week")
        XCTAssertEqual(WorkspaceStore(model: bareModel(), defaults: defaults).saved.items, [])
    }

    func testWithNowhereToSaveNothingIsSaved() {
        let before = UserDefaults.standard.data(forKey: WorkspaceStore.layoutKey)
        let store = WorkspaceStore(model: bareModel(), defaults: nil)
        store.activate()
        store.newTab()
        store.saveWorkspace(as: "Anything")
        XCTAssertEqual(UserDefaults.standard.data(forKey: WorkspaceStore.layoutKey), before)
    }

    // MARK: Files

    func testTabsFollowTheNotebook() async throws {
        let model = await openModel()
        let store = WorkspaceStore(model: model, defaults: nil)
        store.activate()
        store.open(chess, in: .newTab)
        store.open(rules, in: .otherPane)
        // Renamed here: both the tab and its pane keep it.
        model.rename("Personal/Rules.md", to: "Life Rules")
        XCTAssertEqual(store.workspace.focusedItem, .file("Personal/Life Rules.md"))
        XCTAssertEqual(model.route, .file("Personal/Life Rules.md"))
        // Deleted behind the app's back, as a sync would: the tab in the other pane says so.
        try FileManager.default.removeItem(at: root.appendingPathComponent("Personal/Chess.md"))
        await model.reload(force: true)
        XCTAssertEqual(store.workspace.panes[0].tabs.map(\.isMissing), [false, true])
        XCTAssertFalse(store.workspace.focusedTab.isMissing)
        // And it comes back.
        try "# Chess\n".write(to: root.appendingPathComponent("Personal/Chess.md"), atomically: true, encoding: .utf8)
        await model.reload(force: true)
        XCTAssertEqual(store.workspace.panes[0].tabs.map(\.isMissing), [false, false])
        XCTAssertEqual(store.workspace.invariantFailures, [])
    }

    func testAWorkspaceReadBackDropsWhatHasGone() async throws {
        let suite = "perch-tabs-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var workspace = Workspace(.file("Personal/Deleted last week.md"))
        workspace.newTab(chess)
        workspace.open(.file("Gone/Too.md"), in: .otherPane)
        defaults.set(workspace.encoded(), forKey: WorkspaceStore.layoutKey)

        let model = bareModel()
        let store = WorkspaceStore(model: model, defaults: defaults)
        XCTAssertEqual(store.workspace.tabCount, 3)
        model.open(root: root, engine: nil)
        await model.reload(force: true)
        addTeardownBlock { await model.close() }
        XCTAssertFalse(store.workspace.isSplit)
        XCTAssertEqual(store.workspace.panes[0].tabs.map(\.item), [chess])
        XCTAssertFalse(store.workspace.canReopen)
    }

    // MARK: The iPhone: the shell is the place

    func testOnThePhoneTheFocusedTabMirrorsTheShell() async {
        let model = bareModel()
        let shell = ShellState()
        let store = WorkspaceStore(model: model, defaults: nil)
        store.attach(shell: shell)
        model.route = nil
        store.activate()
        XCTAssertEqual(store.workspace.focusedItem, .tasks(.today))

        // The workspace moves the shell.
        store.open(chess, in: .otherPane)
        XCTAssertEqual(shell.destination, .notes)
        XCTAssertEqual(shell.openNote, "Personal/Chess.md")
        XCTAssertEqual(model.section, .notes)
        store.focus(pane: 0)
        XCTAssertEqual(shell.destination, .tasks)
        store.open(.folder("Personal"), in: .newTab)
        XCTAssertEqual(shell.destination, .notes)
        XCTAssertNil(shell.openNote)
        XCTAssertEqual(model.notesFolder, "Personal")
        store.open(.search, in: .newTab)
        XCTAssertEqual(shell.destination, .search)
        await settle()
        XCTAssertEqual(store.workspace.panes[0].tabs.map(\.item), [.tasks(.today), .folder("Personal"), .search])

        // The shell moves the focused tab: the sidebar picks a note, then the Calendar.
        shell.openNote("Personal/Rules.md", fromLink: false, model: model)
        await settle()
        XCTAssertEqual(store.workspace.focusedItem, rules)
        XCTAssertEqual(store.workspace.focusedTab.back, [.search])
        model.show(view: .calendar)
        shell.show(.tasks, model: model)
        await settle()
        XCTAssertEqual(store.workspace.focusedItem, .tasks(.calendar))
        // The other pane never moved.
        XCTAssertEqual(store.workspace.panes[1].tabs.map(\.item), [chess])
        XCTAssertEqual(store.workspace.invariantFailures, [])
    }

    func testOnThePhoneARequestOpensInTheFocusedTab() async {
        let model = bareModel()
        let shell = ShellState()
        let store = WorkspaceStore(model: model, defaults: nil)
        store.attach(shell: shell)
        model.route = nil
        store.activate()
        // A link inside a note asks through the route, as it does without tabs.
        model.route = .file("Personal/Chess.md")
        store.take(.file("Personal/Chess.md"))
        XCTAssertNil(model.route)
        XCTAssertEqual(store.workspace.focusedItem, chess)
        XCTAssertEqual(shell.openNote, "Personal/Chess.md")
        // Settings and Insights are sheets on the phone, not places.
        store.take(.settings)
        await settle()
        XCTAssertEqual(store.workspace.focusedItem, chess)
        XCTAssertEqual(store.workspace.tabCount, 1)
    }

    func testFoldingAndUnfoldingThePhone() async {
        let model = bareModel()
        let shell = ShellState()
        let store = WorkspaceStore(model: model, defaults: nil)
        store.attach(shell: shell)
        model.route = nil
        store.activate()
        store.open(.tasks(.list))
        store.open(.tasks(.calendar), in: .newTab)
        store.open(chess, in: .otherPane)
        await settle()
        let open = store.workspace

        // Folded: no workspace on screen, and the shell is already at the focused tab's place.
        store.deactivate()
        XCTAssertEqual(shell.destination, .notes)
        XCTAssertEqual(shell.openNote, "Personal/Chess.md")
        XCTAssertNil(shell.workspaceTaskPane)
        // Opened again untouched: exactly the workspace that was folded away.
        store.activate()
        XCTAssertEqual(store.workspace, open)

        // Folded, and this time the user goes to Tasks before opening it again.
        store.deactivate()
        shell.show(.tasks, model: model)
        await settle()
        XCTAssertEqual(store.workspace, open, "a folded phone doesn't move the tabs")
        store.activate()
        XCTAssertEqual(store.workspace.focus, 1)
        XCTAssertEqual(store.workspace.focusedItem, .tasks(.calendar))
        XCTAssertEqual(store.workspace.focusedTab.back, [chess])
        XCTAssertEqual(store.workspace.panes[0].tabs.map(\.item), [.tasks(.list), .tasks(.calendar)])
    }

    // MARK: One note in two panes

    func testTwoPanesOnOneNoteShareItsText() async throws {
        setTabs(true)
        let model = await openModel()
        let left = NoteSession.forView(path: "Personal/Chess.md", model: model)
        let right = NoteSession.forView(path: "Personal/Chess.md", model: model)
        XCTAssertTrue(left === right)
        // Typing in one pane is in the other at once, and the tab shows its dot.
        left.text += "Opening moves.\n"
        XCTAssertEqual(right.text, "# Chess\nOpening moves.\n")
        XCTAssertTrue(NoteDirt.shared.paths.contains("Personal/Chess.md"))
        right.text += "End game.\n"
        // Each pane saves as it goes away. Neither save can take the other for a change from elsewhere.
        left.saveNow()
        right.saveNow()
        let disk = try String(contentsOf: root.appendingPathComponent("Personal/Chess.md"), encoding: .utf8)
        XCTAssertEqual(disk, "# Chess\nOpening moves.\nEnd game.\n")
        XCTAssertFalse(ConflictBlocks.contains(disk))
        XCTAssertFalse(NoteDirt.shared.paths.contains("Personal/Chess.md"))
        // Another notebook's note of the same name is somebody else's.
        let other = bareModel()
        XCTAssertFalse(NoteSession.forView(path: "Personal/Chess.md", model: other) === left)
    }

    // MARK: Pages nobody is looking at

    func testAReaderPageOffScreenIsLetGoAfterHalfAMinute() {
        func unloads(_ seconds: TimeInterval, onScreen: Bool = false, spare: Bool = false, unloaded: Bool = false) -> Bool {
            ReaderIdle.unloads(offScreenFor: seconds, isOnScreen: onScreen, isSpare: spare, isUnloaded: unloaded)
        }
        XCTAssertFalse(unloads(0))
        XCTAssertFalse(unloads(29.9))
        XCTAssertTrue(unloads(30))
        XCTAssertTrue(unloads(3600))
        // Back on screen in time, it stays. So does the page kept ready for the next note, and a
        // page already let go is not let go twice.
        XCTAssertFalse(unloads(3600, onScreen: true))
        XCTAssertFalse(unloads(3600, spare: true))
        XCTAssertFalse(unloads(3600, unloaded: true))
    }

    func testAPageThatWasNeverShownUnloadsAndComesBackWhenAsked() async throws {
        // Where there are no built pages (this test bundle) the web view has nothing to load, which is
        // all this needs: the bookkeeping, not the drawing.
        let host = WebHost(page: "render") { nil }
        XCTAssertFalse(host.isUnloaded)
        host.call("render", arguments: ["text": "one"])
        host.debugUnload()
        XCTAssertTrue(host.isUnloaded)
        // Told to draw while let go: remembered, not sent.
        host.call("render", arguments: ["text": "two"])
        XCTAssertEqual(host.debugLastRender?["text"] as? String, "two")
        host.debugRestore()
        XCTAssertFalse(host.isUnloaded)
        XCTAssertEqual(host.debugPendingCount, 1, "the note is drawn again once the page is ready")
    }

    func testWithTabsOffEveryViewHasItsOwnSessionAsBefore() async {
        setTabs(false)
        let model = await openModel()
        let first = NoteSession.forView(path: "Personal/Chess.md", model: model)
        let second = NoteSession.forView(path: "Personal/Chess.md", model: model)
        XCTAssertFalse(first === second)
    }

    func testADiscardedSessionIsNotShared() async {
        setTabs(true)
        let model = await openModel()
        let first = NoteSession.forView(path: "Personal/Rules.md", model: model)
        first.discard()
        XCTAssertFalse(NoteSession.forView(path: "Personal/Rules.md", model: model) === first)
    }
}
