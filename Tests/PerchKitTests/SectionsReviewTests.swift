import XCTest
@testable import PerchKit
@testable import PerchUI

/// Names typed into "Edit areas" become folder names, so they are cleaned before anything keeps them.
final class AreaNameTests: XCTestCase {
    func testNamesAreNormalized() {
        XCTAssertEqual(AreaList.cleaned("  Consulting  "), "Consulting")
        XCTAssertEqual(AreaList.cleaned("Side   Projects\t"), "Side Projects")
        XCTAssertEqual(AreaList.cleaned("Consulting. . "), "Consulting")
        XCTAssertEqual(AreaList.cleaned("Pasted\nname"), "Pasted name")
        XCTAssertEqual(AreaList.cleaned("💼 Consulting"), "💼 Consulting")
        XCTAssertEqual(AreaList.cleaned("R&D"), "R&D")
        // A decomposed é is stored composed, the way the name comes back from a synced folder.
        XCTAssertEqual(AreaList.cleaned("Cafe\u{301}"), "Caf\u{e9}")
    }

    func testNamesThatCannotBeFoldersAreRefused() {
        let bad = [
            "", "   ", ".", "..", ".hidden", "a/b", "/", "a\\b", "C:", "what?", "a*b", "\"q\"", "<x>", "a|b", "#tag",
            "nul\u{0}l", "bell\u{7}", "🙂", "✈️ ", "Tasks", "tasks", " TASKS. ", "✅ Tasks",
            String(repeating: "x", count: AreaList.nameLimit + 1),
        ]
        for name in bad {
            XCTAssertNil(AreaList.cleaned(name), name)
            var preferences = AreaPreferences()
            XCTAssertNil(AreaList.add(name, to: &preferences, existing: []), name)
            XCTAssertEqual(preferences, AreaPreferences(), name)
        }
        XCTAssertNotNil(AreaList.cleaned(String(repeating: "x", count: AreaList.nameLimit)))
        XCTAssertEqual(AreaList.cleaned("Tasks and plans"), "Tasks and plans")
    }

    func testAProblemIsSaidOnlyForANameThatCannotBeUsed() {
        XCTAssertNil(AreaList.problem(with: ""))
        XCTAssertNil(AreaList.problem(with: "  "))
        XCTAssertNil(AreaList.problem(with: "Consulting"))
        for name in [".hidden", "a/b", "Tasks", "🙂", String(repeating: "x", count: 80)] {
            XCTAssertNotNil(AreaList.problem(with: name), name)
        }
    }

    func testANameTakesTheSpellingOfTheFolderThatIsThere() {
        var preferences = AreaPreferences()
        // Two folders that differ only by case can't both exist on a Mac or an iPhone.
        XCTAssertEqual(AreaList.add("work", to: &preferences, existing: ["Personal"], topLevelFolders: ["Work", "Claude"]), "Work")
        XCTAssertEqual(AreaList.add("consulting", to: &preferences, existing: ["Personal", "Work"], topLevelFolders: ["💼 Consulting"]), "💼 Consulting")
        XCTAssertEqual(AreaList.add("Fresh", to: &preferences, existing: ["Personal"], topLevelFolders: ["Work"]), "Fresh")
        XCTAssertEqual(preferences.extra, ["Work", "💼 Consulting", "Fresh"])
        // Adding the same name again, in any case, adds nothing.
        XCTAssertEqual(AreaList.add("FRESH", to: &preferences, existing: ["Personal", "Work", "💼 Consulting", "Fresh"]), "Fresh")
        XCTAssertEqual(preferences.extra.count, 3)
    }

    func testSavedNamesFollowAFolderRenamedOnAnotherDevice() {
        // Saved while the folder was "Acme"; another device has since renamed it "✈️ Acme".
        let preferences = AreaPreferences(order: ["Personal", "Acme"], hidden: ["Acme"])
        let all = AreaList.all(discovered: ["✈️ Acme", "Personal"], preferences: preferences)
        XCTAssertEqual(all, ["Personal", "✈️ Acme"], "the order is kept")
        XCTAssertEqual(AreaList.visible(all, preferences: preferences), ["Personal"], "and it stays hidden")
        XCTAssertTrue(AreaList.isHidden("✈️ Acme", in: all, preferences: preferences))
        XCTAssertEqual(TaskScope.resolved("Acme", in: ["✈️ Acme", "Personal"]), "✈️ Acme")
        XCTAssertEqual(TaskScope.resolved("acme", in: ["✈️ Acme", "Personal"]), "✈️ Acme")
        // The exact name wins when both spellings are real areas.
        XCTAssertEqual(TaskScope.resolved("Acme", in: ["✈️ Acme", "Acme"]), "Acme")
        XCTAssertNil(TaskScope.resolved("Consulting", in: ["✈️ Acme", "Personal"]))

        var changed = preferences
        AreaList.setHidden(false, area: "✈️ Acme", in: &changed)
        XCTAssertEqual(changed.hidden, [], "showing it again clears the old spelling")
    }
}

/// What a scope must and must not touch, checked through the model against real files.
@MainActor
final class ScopeBehaviorTests: XCTestCase {
    private var root: URL!
    private var suite = ""
    private var defaults: UserDefaults!
    private var vault: Vault { Vault(root: root) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("perch-scope-" + UUID().uuidString)
        suite = "perch-scope-" + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        try write("tper0001", "Water plants", area: "Personal", due: "2026-01-05")
        try write("tper0002", "Call the vet", area: "Personal", due: "2026-01-06")
        try write("texp0001", "Book flights", area: "✈️ Acme", due: "2026-01-05")
        try write("texp0002", "File expenses", area: "✈️ Acme", due: "2026-01-07")
        try vault.write("# Plan\n", to: "Personal/Plan.md")
        try vault.write("# Notes\n", to: "Work/Notes.md")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suite)
    }

    private func write(_ id: String, _ title: String, area: String, due: String? = nil, extra: String = "") throws {
        let dueLine = due.map { "due: \($0)\n" } ?? ""
        try vault.write("---\nid: \(id)\ntitle: \(title)\nstatus: open\n\(dueLine)\(extra)created: 2026-01-01\n---\n", to: "\(area)/Tasks/\(title) \(id).md")
    }

    private func openModel() async -> AppModel {
        let model = AppModel(supportDirectory: root.appendingPathComponent(".support"), navigationDefaults: defaults, configuration: .ownersAreas)
        model.open(root: root, engine: nil)
        await model.reload(force: true)
        return model
    }

    private func due(_ id: String) throws -> String? {
        let name = try XCTUnwrap(try FileManager.default.subpathsOfDirectory(atPath: root.path).first { $0.contains(id) })
        return try TaskCodec.decode(path: name, text: vault.read(name)).due
    }

    /// The Today view's "Reschedule" hands over the overdue tasks in scope. Nothing else may move.
    func testReschedulingOverdueInScopeLeavesOtherAreasAlone() async throws {
        let model = await openModel()
        model.setScope("Personal")
        let today = model.today
        let overdue = model.scopedTasks.filter { $0.isOverdue(today: today) }
        XCTAssertEqual(Set(overdue.map(\.id)), ["tper0001", "tper0002"])
        model.reschedule(overdue, to: "2031-03-03")
        XCTAssertEqual(try due("tper0001"), "2031-03-03")
        XCTAssertEqual(try due("tper0002"), "2031-03-03")
        XCTAssertEqual(try due("texp0001"), "2026-01-05", "another area's overdue task keeps its date")
        XCTAssertEqual(try due("texp0002"), "2026-01-07")
        XCTAssertEqual(model.tasks.filter { $0.isOverdue(today: today) }.map(\.area), ["✈️ Acme", "✈️ Acme"])
        model.close()
    }

    func testQuickAddFollowsTheScopeUnlessTheTextNamesAnArea() async throws {
        let model = await openModel()
        model.setScope("Personal")
        XCTAssertEqual(model.quickAdd("Buy stamps", defaultArea: model.taskScope)?.area, "Personal")
        XCTAssertEqual(model.quickAdd("Approve timesheet #acme", defaultArea: model.taskScope)?.area, "✈️ Acme")
        // A calendar day's "+" gives the day and the scope.
        let dated = try XCTUnwrap(model.quickAdd("Post the letter", defaultArea: model.taskScope, defaultDue: "2031-03-04"))
        XCTAssertEqual(dated.area, "Personal")
        XCTAssertEqual(dated.due, "2031-03-04")
        // A subtask goes where its parent is, whatever the scope.
        model.setScope("✈️ Acme")
        let parent = try XCTUnwrap(model.task(id: "tper0001"))
        XCTAssertEqual(model.quickAdd("Fill the can", defaultArea: model.taskScope, parent: parent)?.area, "Personal")
        model.close()
    }

    func testATaskMovedOutOfTheScopeLeavesItAndTheScopeStays() async throws {
        let model = await openModel()
        model.setScope("Personal")
        model.move(try XCTUnwrap(model.task(id: "tper0001")), toArea: "✈️ Acme")
        await model.reload(force: true)
        XCTAssertEqual(model.scopedTasks.map(\.id), ["tper0002"])
        XCTAssertEqual(model.taskScope, "Personal")
        XCTAssertEqual(model.task(id: "tper0001")?.area, "✈️ Acme", "it is still open for the detail sheet")
        model.close()
    }

    func testAScopeCannotNameAnAreaThatIsNotOnOffer() async {
        let model = await openModel()
        model.setScope("Nowhere")
        XCTAssertNil(model.taskScope)
        model.route = .area("Nowhere")
        XCTAssertNil(model.taskScope)
        XCTAssertEqual(model.route, .list)
        model.showTasks(area: "Work")
        XCTAssertNil(model.taskScope, "a folder with no tasks is not an area until it is added")
        // The simplified name finds the real one.
        model.setScope("Acme")
        XCTAssertEqual(model.taskScope, "✈️ Acme")
        model.close()
    }

    func testASavedScopeFollowsARenamedFolderAndAGoneOneFallsBack() async throws {
        defaults.set("Acme", forKey: NavigationState.Key.taskScope)
        var model = await openModel()
        XCTAssertEqual(model.taskScope, "✈️ Acme")
        XCTAssertEqual(defaults.string(forKey: NavigationState.Key.taskScope), "✈️ Acme", "and the new spelling is saved")
        model.close()

        defaults.set("Consulting", forKey: NavigationState.Key.taskScope)
        model = await openModel()
        XCTAssertNil(model.taskScope)
        XCTAssertEqual(model.scopedTasks.count, 4)
        model.close()
    }

    func testAnAreaWhoseLastTaskLeavesFallsBackToAll() async throws {
        try write("twrk0001", "Ship it", area: "Work")
        let model = await openModel()
        XCTAssertEqual(model.visibleAreas, ["✈️ Acme", "Personal", "Work"])
        model.setScope("Work")
        model.move(try XCTUnwrap(model.task(id: "twrk0001")), toArea: "Personal")
        await model.reload(force: true)
        XCTAssertNil(model.taskScope)
        XCTAssertEqual(model.visibleAreas, ["✈️ Acme", "Personal"])
        model.close()
    }

    func testAHiddenAreaStillCountsUnderAll() async {
        let model = await openModel()
        var preferences = model.areaPreferences
        AreaList.setHidden(true, area: "✈️ Acme", in: &preferences)
        model.areaPreferences = preferences
        XCTAssertEqual(model.visibleAreas, ["Personal"])
        XCTAssertEqual(model.scopedTasks.count, 4)
        XCTAssertEqual(TaskScope.counts(model.tasks, today: model.today).all.open, 4)
        XCTAssertEqual(model.quickAdd("Still reachable #acme")?.area, "✈️ Acme", "quick add can still name it")
        model.close()
    }

    func testAnAddedAreaIsFiledInTheFolderThatExists() async throws {
        let model = await openModel()
        // "Work" is a folder of notes with no tasks. Typing it in another case must not make a second folder.
        XCTAssertEqual(model.addArea("work"), "Work")
        model.setScope("Work")
        let task = try XCTUnwrap(model.quickAdd("Write the brief", defaultArea: model.taskScope))
        XCTAssertTrue(task.path.hasPrefix("Work/Tasks/"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.lowercased() == "work" }, ["Work"])
        // Odd names never reach the notebook.
        for bad in ["a/b", "../up", ".git", "Tasks", ""] { XCTAssertNil(model.addArea(bad), bad) }
        XCTAssertEqual(model.addArea("  Side   Projects. "), "Side Projects")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Side Projects").path))
        model.close()
    }

    func testTheReadyViewIsOfferedOnlyForTheScope() async throws {
        try write("texp0003", "Agent did this", area: "✈️ Acme", extra: "proposed_done_by: claude\n")
        let model = await openModel()
        try XCTSkipIf(model.readyToTick.isEmpty, "the task format marks proposals another way")
        XCTAssertTrue(model.offersReadyView)
        model.setScope("Personal")
        XCTAssertFalse(model.offersReadyView, "another area's proposal isn't hinted at here")
        model.show(view: .ready)
        XCTAssertTrue(model.offersReadyView, "the view showing always keeps its place in the switcher")
        model.close()
    }

    func testASubtaskWhoseParentIsElsewhereStillShows() async throws {
        try write("tper0003", "Pack bags", area: "Personal", extra: "parent: texp0001\n")
        try write("tper0004", "Buy soil", area: "Personal", extra: "parent: tper0001\n")
        let model = await openModel()
        model.setScope("Personal")
        let roots = model.roots(model.scopedTasks).map(\.id).sorted()
        XCTAssertEqual(roots, ["tper0001", "tper0002", "tper0003"], "the subtask of another area's task stands on its own; the other nests")
        model.close()
    }

    func testDeletingATaskPageReturnsToTheViewThatWasShowing() async throws {
        let model = await openModel()
        model.setScope("Personal")
        model.show(view: .upcoming)
        let task = try XCTUnwrap(model.task(id: "tper0001"))
        model.route = .file(task.path)
        XCTAssertEqual(model.section, .tasks, "a task's page is not a place in Notes")
        model.delete(task)
        XCTAssertEqual(model.route, .upcoming)
        XCTAssertEqual(model.taskScope, "Personal")
        model.close()
    }

    func testDeletingTheOpenNoteShowsItsFolderOnce() async throws {
        let model = await openModel()
        model.route = .file("Personal/Plan.md")
        model.deleteFile("Personal/Plan.md")
        XCTAssertEqual(model.route, .folder("Personal"))
        XCTAssertEqual(model.section, .notes)
        model.show(.tasks)
        model.show(.notes)
        XCTAssertEqual(model.route, .folder("Personal"), "the deleted note is not remembered")
        // The last note in a folder: the folder is gone with it, so the nearest one above shows.
        model.route = .file("Work/Notes.md")
        model.deleteFile("Work/Notes.md")
        XCTAssertEqual(model.route, .folder(""))
        model.close()
    }
}
