import XCTest
@testable import PerchKit
@testable import PerchUI

private func task(_ id: String, area: String, due: String? = nil, status: TaskStatus = .open) -> PerchTask {
    var task = PerchTask(id: id, path: "\(area)/Tasks/\(id).md", title: id)
    task.due = due
    task.status = status
    return task
}

private func file(_ path: String) -> VaultFile { VaultFile(path: path, kind: VaultFile.classify(path), modified: nil) }

final class TaskScopeTests: XCTestCase {
    private let tasks = [
        task("a", area: "✈️ Acme", due: "2026-11-01"),
        task("b", area: "✈️ Acme", due: "2026-11-20"),
        task("c", area: "Personal", due: "2026-11-09"),
        task("d", area: "Personal", due: "2026-10-01", status: .done),
    ]

    func testNilScopeIsEveryArea() {
        XCTAssertEqual(TaskScope.filter(tasks, area: nil).map(\.id), ["a", "b", "c", "d"])
        XCTAssertEqual(TaskScope.filter(tasks, area: "Personal").map(\.id), ["c", "d"])
        XCTAssertEqual(TaskScope.filter(tasks, area: "Consulting"), [])
        XCTAssertTrue(TaskScope.contains(tasks[0], area: nil))
        XCTAssertFalse(TaskScope.contains(tasks[0], area: "Personal"))
    }

    func testBoardCardsFollowTheirTopFolder() {
        XCTAssertTrue(TaskScope.contains(path: "Personal/Plans.kanban.md", area: "Personal"))
        XCTAssertFalse(TaskScope.contains(path: "Personal Stuff/Plans.kanban.md", area: "Personal"))
        XCTAssertTrue(TaskScope.contains(path: "Claude/Plans.kanban.md", area: nil))
    }

    func testCountsOpenAndOverduePerArea() {
        let counts = TaskScope.counts(tasks, today: "2026-11-09")
        XCTAssertEqual(counts.all, .init(open: 3, overdue: 1))
        XCTAssertEqual(counts.byArea["✈️ Acme"], .init(open: 2, overdue: 1))
        XCTAssertEqual(counts.byArea["Personal"], .init(open: 1, overdue: 0))
        XCTAssertNil(counts.byArea["Consulting"])
    }

    func testAScopeThatIsGoneFallsBackToAll() {
        XCTAssertEqual(TaskScope.resolved("Personal", in: ["✈️ Acme", "Personal"]), "Personal")
        XCTAssertNil(TaskScope.resolved("Consulting", in: ["✈️ Acme", "Personal"]))
        XCTAssertNil(TaskScope.resolved(nil, in: ["Personal"]))
    }

    func testTitlesSayWhereYouAre() {
        XCTAssertEqual(TaskScope.title(view: .today, area: nil), "Today")
        XCTAssertEqual(TaskScope.title(view: .upcoming, area: "Personal"), "Personal · Upcoming")
        XCTAssertEqual(TaskScope.title(view: .calendar, area: "✈️ Acme"), "Acme · Calendar")
        XCTAssertEqual(TaskScope.spoken(name: "Personal", count: .init(open: 12, overdue: 3)), "Personal, 12 open, 3 overdue")
        XCTAssertEqual(TaskScope.spoken(name: "Consulting", count: .init()), "Consulting, no open tasks")
    }
}

final class AreaListTests: XCTestCase {
    func testDiscoveredKeepsTheOldRule() {
        let standard = ["✈️ Acme", "Personal"]
        XCTAssertEqual(AreaList.discovered(topLevelFolders: ["✈️ Acme", "Personal", "Claude"], taskAreas: ["Personal", "Claude", "Claude"], standard: standard), ["✈️ Acme", "Personal", "Claude"])
        // Neither standard folder: whatever has tasks, and no empty standard area beside it.
        XCTAssertEqual(AreaList.discovered(topLevelFolders: ["Work"], taskAreas: ["Work"], standard: standard), ["Work"])
    }

    func testAddedAreasFollowAndDuplicatesAreIgnored() {
        let preferences = AreaPreferences(extra: ["Consulting", "acme"])
        XCTAssertEqual(AreaList.all(discovered: ["✈️ Acme", "Personal"], preferences: preferences), ["✈️ Acme", "Personal", "Consulting"])
        XCTAssertEqual(AreaList.all(discovered: ["Personal"], preferences: preferences, transient: ["Other", "consulting"]), ["Personal", "Consulting", "acme", "Other"])
    }

    func testOrderAndHiding() {
        var preferences = AreaPreferences(extra: ["Consulting"])
        let discovered = ["✈️ Acme", "Personal"]
        AreaList.move("Consulting", by: -2, in: AreaList.all(discovered: discovered, preferences: preferences), preferences: &preferences)
        XCTAssertEqual(AreaList.all(discovered: discovered, preferences: preferences), ["Consulting", "✈️ Acme", "Personal"])
        // Stops at the ends, and an area found later joins the end.
        AreaList.move("Consulting", by: -1, in: AreaList.all(discovered: discovered, preferences: preferences), preferences: &preferences)
        XCTAssertEqual(AreaList.all(discovered: discovered + ["Claude"], preferences: preferences), ["Consulting", "✈️ Acme", "Personal", "Claude"])

        AreaList.setHidden(true, area: "Personal", in: &preferences)
        let all = AreaList.all(discovered: discovered, preferences: preferences)
        XCTAssertEqual(all, ["Consulting", "✈️ Acme", "Personal"], "hidden areas stay known, for quick add")
        XCTAssertEqual(AreaList.visible(all, preferences: preferences), ["Consulting", "✈️ Acme"])
        AreaList.setHidden(false, area: "Personal", in: &preferences)
        XCTAssertEqual(AreaList.visible(all, preferences: preferences), all)
    }

    func testAddingByName() {
        var preferences = AreaPreferences(hidden: ["Personal"])
        XCTAssertEqual(AreaList.add("  Consulting ", to: &preferences, existing: ["✈️ Acme", "Personal"]), "Consulting")
        XCTAssertEqual(preferences.extra, ["Consulting"])
        // A name that is already an area resolves to it, and shows it again if it was hidden.
        XCTAssertEqual(AreaList.add("acme", to: &preferences, existing: ["✈️ Acme", "Personal", "Consulting"]), "✈️ Acme")
        XCTAssertEqual(AreaList.add("personal", to: &preferences, existing: ["✈️ Acme", "Personal", "Consulting"]), "Personal")
        XCTAssertEqual(preferences, AreaPreferences(extra: ["Consulting"]))
        for bad in ["", "   ", "a/b", ".hidden", "🙂", "C:"] {
            XCTAssertNil(AreaList.add(bad, to: &preferences, existing: []), bad)
        }
        AreaList.remove("Consulting", from: &preferences)
        XCTAssertEqual(preferences, AreaPreferences())
    }

    func testSuggestionsLeaveOutWhatIsAlreadyAnArea() {
        XCTAssertEqual(
            AreaList.suggestions(topLevelFolders: ["✈️ Acme", "Claude", "work-y"], existing: ["✈️ Acme", "Personal"], extras: ["Consulting"]),
            ["Consulting", "Claude", "work-y"]
        )
        XCTAssertEqual(AreaList.suggestions(topLevelFolders: ["Claude"], existing: ["Consulting", "Claude"], extras: ["Consulting"]), [])
    }

    func testPreferencesRoundTrip() throws {
        let name = "perch-areas-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(AreaPreferences.load(from: defaults), AreaPreferences())
        let saved = AreaPreferences(extra: ["Consulting"], order: ["Consulting", "Personal"], hidden: ["Personal"])
        saved.save(to: defaults)
        XCTAssertEqual(AreaPreferences.load(from: defaults), saved)
    }
}

final class NotesSubsectionsTests: XCTestCase {
    private let files = [
        "Inbox.md", "Personal/Plan.md", "Personal/Cooking/Bread.md", "Personal/Cooking/Baking/Scones.md",
        "Personal/AI Learning/Intro.md", "Personal/AI Learning/Apps/One.md", "Personal/Tasks/Do it t1.md",
        "Work/Roadmap.kanban.md", "Work/Sketch.excalidraw",
    ].map(file)

    func testTopLevel() {
        let sections = NotesSubsections(files: files, path: "")
        XCTAssertEqual(sections.total, 8, "task files are not notes")
        XCTAssertEqual(sections.top.map(\.name), ["Personal", "Work"])
        XCTAssertEqual(sections.top.map(\.count), [5, 2])
        XCTAssertNil(sections.selectedTop)
        XCTAssertEqual(sections.row, [])
        XCTAssertNil(sections.up)
    }

    func testATopFolderShowsItsSubfolders() {
        let sections = NotesSubsections(files: files, path: "Personal")
        XCTAssertEqual(sections.selectedTop, "Personal")
        XCTAssertEqual(sections.row.map(\.path), ["Personal/AI Learning", "Personal/Cooking"])
        XCTAssertEqual(sections.rowParent, "Personal")
        XCTAssertNil(sections.selectedInRow)
        XCTAssertNil(sections.up)
        // A folder with no sub-folders has no second row.
        XCTAssertEqual(NotesSubsections(files: files, path: "Work").row, [])
    }

    func testDeeperDownTheRowIsTheSiblings() {
        let sections = NotesSubsections(files: files, path: "Personal/Cooking")
        XCTAssertEqual(sections.selectedTop, "Personal")
        XCTAssertEqual(sections.row.map(\.name), ["AI Learning", "Cooking"])
        XCTAssertEqual(sections.selectedInRow, "Personal/Cooking")
        XCTAssertNil(sections.up, "the top-level chip already leads back up")

        let deep = NotesSubsections(files: files, path: "Personal/Cooking/Baking")
        XCTAssertEqual(deep.row.map(\.path), ["Personal/Cooking/Baking"])
        XCTAssertEqual(deep.selectedInRow, "Personal/Cooking/Baking")
        XCTAssertEqual(deep.up?.path, "Personal/Cooking")
        XCTAssertEqual(deep.up?.name, "Cooking")
    }

    func testTheKindFilterNarrowsFoldersAndCounts() {
        let boards = NotesSubsections(files: files, path: "", kinds: NotesKind.boards.kinds)
        XCTAssertEqual(boards.total, 1)
        XCTAssertEqual(boards.top.map(\.name), ["Work"])
        XCTAssertEqual(NotesSubsections(files: files, path: "", kinds: NotesKind.whiteboards.kinds).total, 1)
        XCTAssertEqual(NotesSubsections(files: files, path: "", kinds: NotesKind.notes.kinds).total, 6)
        XCTAssertEqual(NotesKind.all.kinds, FolderListing.browsableKinds)
    }

    func testASavedFolderThatIsGoneFallsBackToOneThatExists() {
        XCTAssertEqual(NotesSubsections.existing("Personal/Cooking", files: files), "Personal/Cooking")
        XCTAssertEqual(NotesSubsections.existing("Personal/Gone/Deeper", files: files), "Personal")
        XCTAssertEqual(NotesSubsections.existing("Nowhere", files: files), "")
        XCTAssertEqual(NotesSubsections.existing("", files: files), "")
    }

    func testRailNeedsRealWidth() {
        XCTAssertFalse(AdaptiveLayout.subsectionRail(width: 380))
        XCTAssertFalse(AdaptiveLayout.subsectionRail(width: 669))
        XCTAssertTrue(AdaptiveLayout.subsectionRail(width: 860))
    }
}

final class NavigationStateTests: XCTestCase {
    func testEachSectionRemembersItsPlace() {
        var state = NavigationState()
        XCTAssertEqual(state.place(in: .tasks), .tasks(.today))
        XCTAssertEqual(state.place(in: .notes), .folder(""))
        state.visit(.tasks(.calendar))
        state.visit(.folder("Personal/Cooking"))
        XCTAssertEqual(state.section, .notes)
        XCTAssertEqual(state.place(in: .tasks), .tasks(.calendar))
        state.visit(.file("Personal/Cooking/Bread.md"))
        XCTAssertEqual(state.place(in: .notes), .file("Personal/Cooking/Bread.md"))
        XCTAssertEqual(state.notesFolder, "Personal/Cooking", "the folder being browsed is kept under the open file")
        state.visit(.tasks(.upcoming))
        XCTAssertEqual(state.section, .tasks)
        XCTAssertEqual(state.place(in: .notes), .file("Personal/Cooking/Bread.md"))
        state.visit(.folder(""))
        XCTAssertEqual(state.place(in: .notes), .folder(""))
    }

    func testAnAreaIsAScopeInTheList() {
        var state = NavigationState()
        state.visit(.folder("Personal"))
        state.visit(.area("Personal"))
        XCTAssertEqual(state.section, .tasks)
        XCTAssertEqual(state.taskScope, "Personal")
        XCTAssertEqual(state.taskView, .list)
        state.visit(.tasks(.today))
        XCTAssertEqual(state.taskScope, "Personal", "changing the view keeps the scope")
    }

    func testRoundTrip() throws {
        let name = "perch-nav-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(NavigationState.load(from: defaults), NavigationState())
        var state = NavigationState()
        state.visit(.tasks(.calendar))
        state.taskScope = "✈️ Acme"
        state.visit(.folder("Personal"))
        state.visit(.file("Personal/Plan.md"))
        state.notesKind = .boards
        state.save(to: defaults)
        XCTAssertEqual(NavigationState.load(from: defaults), state)
        // Clearing the scope and the file is saved too.
        state.taskScope = nil
        state.visit(.folder(""))
        state.save(to: defaults)
        XCTAssertEqual(NavigationState.load(from: defaults), state)
    }
}

/// The model's side of sections: routes still work, a scope filters every view, and places are remembered.
@MainActor
final class SectionModelTests: XCTestCase {
    private var root: URL!
    private var suite = ""
    private var defaults: UserDefaults!
    private var vault: Vault { Vault(root: root) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("perch-sections-" + UUID().uuidString)
        suite = "perch-sections-" + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        try vault.write("---\nid: tper0001\ntitle: Water plants\nstatus: open\ndue: 2026-11-09\ncreated: 2026-11-01\n---\n", to: "Personal/Tasks/Water plants tper0001.md")
        try vault.write("---\nid: texp0001\ntitle: Book flights\nstatus: open\ncreated: 2026-11-01\n---\n", to: "✈️ Acme/Tasks/Book flights texp0001.md")
        try vault.write("# Plan\n", to: "Personal/Plan.md")
        try vault.write("# Bread\n", to: "Personal/Cooking/Bread.md")
        try vault.write("# Readme\n", to: "Claude/Readme.md")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suite)
    }

    private func openModel(saves: Bool = true) async -> AppModel {
        let model = AppModel(supportDirectory: root.appendingPathComponent(".support"), navigationDefaults: defaults, savesNavigation: saves, configuration: .ownersAreas)
        model.open(root: root, engine: nil)
        await model.reload(force: true)
        return model
    }

    func testAScopeFiltersTheTasksEveryViewReads() async {
        let model = await openModel()
        XCTAssertEqual(model.areas, ["✈️ Acme", "Personal"])
        XCTAssertEqual(model.scopedTasks.count, 2)
        model.setScope("Personal")
        XCTAssertEqual(model.scopedTasks.map(\.id), ["tper0001"])
        XCTAssertEqual(model.route, .today, "the view stays where it was")
        model.route = .calendar
        XCTAssertEqual(model.taskScope, "Personal", "the scope carries to the next view")
        model.setScope(nil)
        XCTAssertEqual(model.scopedTasks.count, 2)
        model.close()
    }

    func testOldRoutesStillLand() async {
        let model = await openModel()
        model.route = .area("Personal")
        XCTAssertEqual(model.route, .list, "an area is its List now")
        XCTAssertEqual(model.taskScope, "Personal")
        XCTAssertEqual(model.section, .tasks)
        model.route = .week
        XCTAssertEqual(model.taskView, .calendar)
        model.route = .file("Personal/Plan.md")
        XCTAssertEqual(model.section, .notes)
        model.route = .settings
        XCTAssertEqual(model.section, .notes, "settings belongs to neither section")
        model.route = .today
        XCTAssertEqual(model.section, .tasks)
        XCTAssertEqual(model.taskScope, "Personal")
        model.close()
    }

    func testSwitchingSectionsReturnsToWhereEachWasLeft() async {
        let model = await openModel()
        model.route = .upcoming
        model.route = .folder("Personal/Cooking")
        model.show(.tasks)
        XCTAssertEqual(model.route, .upcoming)
        model.show(.notes)
        XCTAssertEqual(model.route, .folder("Personal/Cooking"))
        model.route = .file("Personal/Plan.md")
        model.show(.tasks)
        model.show(.notes)
        XCTAssertEqual(model.route, .file("Personal/Plan.md"))
        model.close()
    }

    func testAnAddedAreaWritesNothingUntilItsFirstTask() async throws {
        let model = await openModel()
        XCTAssertEqual(model.addArea("Consulting"), "Consulting")
        XCTAssertEqual(model.visibleAreas, ["✈️ Acme", "Personal", "Consulting"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Consulting").path))
        XCTAssertTrue(model.canRemoveArea("Consulting"))
        XCTAssertFalse(model.canRemoveArea("Personal"))

        // Quick add inside the scope files the task there, which is what creates the folder.
        model.setScope("Consulting")
        XCTAssertTrue(model.scopedTasks.isEmpty)
        let added = try XCTUnwrap(model.quickAdd("Send the proposal", defaultArea: model.taskScope))
        XCTAssertEqual(added.area, "Consulting")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Consulting/Tasks").path))
        XCTAssertFalse(model.canRemoveArea("Consulting"))
        // `#Area` in quick add knows the added area too.
        model.setScope(nil)
        XCTAssertEqual(model.quickAdd("Invoice #consulting")?.area, "Consulting")
        model.close()
    }

    func testHidingTheAreaInScopeFallsBackToAll() async {
        let model = await openModel()
        model.setScope("Personal")
        var preferences = model.areaPreferences
        AreaList.setHidden(true, area: "Personal", in: &preferences)
        model.areaPreferences = preferences
        XCTAssertNil(model.taskScope)
        XCTAssertEqual(model.visibleAreas, ["✈️ Acme"])
        XCTAssertEqual(model.areas, ["✈️ Acme", "Personal"], "still known to quick add")
        model.close()
    }

    func testCrossLinksBetweenAnAreaAndItsFolder() async {
        let model = await openModel()
        XCTAssertEqual(model.notesFolder(forArea: "Personal"), "Personal")
        XCTAssertNil(model.notesFolder(forArea: "✈️ Acme"), "only tasks live there, nothing to browse")
        XCTAssertNil(model.notesFolder(forArea: nil))
        XCTAssertEqual(model.area(forFolder: "Personal/Cooking"), "Personal")
        XCTAssertNil(model.area(forFolder: "Claude"))
        model.route = .calendar
        model.route = .folder("Personal/Cooking")
        model.showTasks(area: "Personal")
        XCTAssertEqual(model.route, .calendar, "back in the view Tasks was left in")
        XCTAssertEqual(model.taskScope, "Personal")
        model.close()
    }

    func testPlacesArePersistedAndRestored() async {
        let first = await openModel()
        first.addArea("Consulting")
        first.setScope("Personal")
        first.route = .calendar
        first.route = .folder("Personal/Cooking")
        first.setNotesKind(.boards)
        first.close()

        let second = await openModel()
        XCTAssertEqual(second.section, .notes)
        XCTAssertEqual(second.route, .folder("Personal/Cooking"))
        XCTAssertEqual(second.notesKind, .boards)
        XCTAssertEqual(second.taskScope, "Personal")
        XCTAssertEqual(second.visibleAreas, ["✈️ Acme", "Personal", "Consulting"])
        second.show(.tasks)
        XCTAssertEqual(second.route, .calendar)
        second.close()
    }

    func testARememberedPlaceThatIsGoneIsReplaced() async throws {
        var state = NavigationState()
        state.taskScope = "Vanished"
        state.visit(.folder("Personal/Gone"))
        state.visit(.file("Personal/Gone/Old.md"))
        state.save(to: defaults)
        let model = await openModel()
        XCTAssertNil(model.taskScope)
        XCTAssertEqual(model.notesFolder, "Personal")
        XCTAssertEqual(model.route, .folder("Personal"))
        model.close()
    }

    func testALaunchWithOverridesSavesNothing() async {
        let model = await openModel(saves: false)
        model.route = .folder("Personal")
        model.addArea("Consulting")
        model.transientAreas = ["Other"]
        model.setScope(named: "other")
        XCTAssertEqual(model.taskScope, "Other")
        model.close()
        XCTAssertEqual(NavigationState.load(from: defaults), NavigationState())
        XCTAssertEqual(AreaPreferences.load(from: defaults), AreaPreferences())
    }

    func testWithoutDefaultsNothingIsSavedAnywhere() async {
        let model = AppModel(supportDirectory: root.appendingPathComponent(".support"), configuration: .ownersAreas)
        model.open(root: root, engine: nil)
        await model.reload(force: true)
        model.route = .folder("Personal")
        model.setScope(named: "acme")
        XCTAssertEqual(model.taskScope, "✈️ Acme")
        model.close()
        XCTAssertNil(defaults.string(forKey: NavigationState.Key.section))
    }

    func testDetailPaneKeepsOneIdentityPerSection() {
        XCTAssertEqual(DetailRouter.pane(.today), DetailRouter.pane(.calendar))
        XCTAssertEqual(DetailRouter.pane(.folder("")), DetailRouter.pane(.folder("Personal")))
        XCTAssertNotEqual(DetailRouter.pane(.today), DetailRouter.pane(.folder("")))
        XCTAssertNotEqual(DetailRouter.pane(.file("a.md")), DetailRouter.pane(.file("b.md")))
        XCTAssertNotEqual(DetailRouter.pane(.search), DetailRouter.pane(.settings))
    }
}
