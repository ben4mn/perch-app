import XCTest
@testable import PerchKit
@testable import PerchUI

final class TaskTextTests: XCTestCase {
    func testPlainDropsMarkdownMarks() {
        XCTAssertEqual(TaskText.plain("**Ask:** accept from the `email`"), "Ask: accept from the email")
        XCTAssertEqual(TaskText.plain("Wrote a summary in [[Perch agent demo]]."), "Wrote a summary in Perch agent demo.")
        XCTAssertEqual(TaskText.plain("See [[Personal/Notes/Plan|the plan]] and [the doc](https://example.com/a_b)"), "See the plan and the doc")
        XCTAssertEqual(TaskText.plain("## Heading"), "Heading")
        XCTAssertEqual(TaskText.plain("- [ ] buy milk"), "buy milk")
        XCTAssertEqual(TaskText.plain("> quoted *softly*"), "quoted softly")
    }

    func testPlainLeavesOrdinaryTextAlone() {
        XCTAssertEqual(TaskText.plain("2 * 3 = 6, file_name_here.md"), "2 * 3 = 6, file_name_here.md")
        XCTAssertEqual(TaskText.plain("An unclosed [[link"), "An unclosed [[link")
        XCTAssertEqual(TaskText.plain(""), "")
    }

    func testFirstLineSkipsBlankAndRuleLines() {
        XCTAssertEqual(TaskText.firstLine("\n\n---\n**From:** Sam\nMore"), "From: Sam")
        XCTAssertNil(TaskText.firstLine("  \n\n"))
    }

    func testSimplifyingLinksKeepsOtherMarkdown() {
        XCTAssertEqual(TaskText.simplifyingLinks("**Done** in [[A/B#Part|b]] and [[C]]"), "**Done** in b and C")
    }
}

final class AdaptiveLayoutTests: XCTestCase {
    func testMonthLayoutFollowsTheRoomAvailable() {
        // A small phone, and the folding phone's outer screen upright.
        XCTAssertEqual(AdaptiveLayout.month(width: 320, height: 568, compactWidthClass: true), .stacked)
        XCTAssertEqual(AdaptiveLayout.month(width: 466, height: 678, compactWidthClass: true), .stacked)
        // The outer screen sideways, and the inner screen upright: the day's list sits beside the grid.
        XCTAssertEqual(AdaptiveLayout.month(width: 678, height: 466, compactWidthClass: true), .split)
        XCTAssertEqual(AdaptiveLayout.month(width: 669, height: 951, compactWidthClass: false), .split)
        XCTAssertEqual(AdaptiveLayout.month(width: 951, height: 669, compactWidthClass: true), .split)
        // Room for pills.
        XCTAssertEqual(AdaptiveLayout.month(width: 951, height: 669, compactWidthClass: false), .grid)
        XCTAssertEqual(AdaptiveLayout.month(width: 990, height: 800, compactWidthClass: false), .grid)
        XCTAssertEqual(AdaptiveLayout.month(width: 990, height: 400, compactWidthClass: false), .split)
    }

    func testWeekLayout() {
        XCTAssertEqual(AdaptiveLayout.week(width: 466, compactWidthClass: true), .stacked)
        XCTAssertEqual(AdaptiveLayout.week(width: 678, compactWidthClass: true), .tiled)
        XCTAssertEqual(AdaptiveLayout.week(width: 669, compactWidthClass: false), .tiled)
        XCTAssertEqual(AdaptiveLayout.week(width: 951, compactWidthClass: false), .columns)
    }

    func testFolderGrid() {
        XCTAssertTrue(AdaptiveLayout.folderGrid(width: 400, prefersList: false))
        XCTAssertFalse(AdaptiveLayout.folderGrid(width: 466, prefersList: true))
        XCTAssertTrue(AdaptiveLayout.folderGrid(width: 669, prefersList: true))
    }
}

/// Ticking a task waits a moment for its animation. The wait must never lose or misapply the completion.
@MainActor
final class CompletionQueueTests: XCTestCase {
    private var root: URL!
    private var vault: Vault { Vault(root: root) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("perch-completing-" + UUID().uuidString)
        try vault.write("---\nid: tone0001\ntitle: One\nstatus: open\ndue: 2026-11-09\ncreated: 2026-11-01\n---\nNotes.\n", to: "Personal/Tasks/One tone0001.md")
        try vault.write("---\nid: ttwo0001\ntitle: Two\nstatus: open\ncreated: 2026-11-01\n---\n", to: "Personal/Tasks/Two ttwo0001.md")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func openModel() async -> AppModel {
        let model = AppModel(supportDirectory: root.appendingPathComponent(".support"))
        model.open(root: root, engine: nil)
        await model.reload(force: true)
        return model
    }

    private func status(_ path: String) throws -> String {
        let text = try vault.read(path)
        return text.components(separatedBy: "\n").first { $0.hasPrefix("status:") } ?? ""
    }

    func testFlushCompletesStraightAway() async throws {
        let model = await openModel()
        let task = try XCTUnwrap(model.task(id: "tone0001"))
        model.beginCompleting(task, after: 30)
        XCTAssertTrue(model.completing.contains("tone0001"))
        XCTAssertEqual(try status("Personal/Tasks/One tone0001.md"), "status: open")
        model.flushCompletions()
        XCTAssertTrue(model.completing.isEmpty)
        XCTAssertEqual(try status("Personal/Tasks/One tone0001.md"), "status: done")
        XCTAssertEqual(model.task(id: "tone0001")?.isOpen, false)
        model.close()
    }

    func testCancelLeavesTheTaskOpen() async throws {
        let model = await openModel()
        let task = try XCTUnwrap(model.task(id: "tone0001"))
        model.beginCompleting(task, after: 0.05)
        model.cancelCompleting("tone0001")
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(model.completing.isEmpty)
        XCTAssertEqual(try status("Personal/Tasks/One tone0001.md"), "status: open")
        model.close()
    }

    func testCompletesAfterTheDelayUsingTheLatestCopy() async throws {
        let model = await openModel()
        let stale = try XCTUnwrap(model.task(id: "ttwo0001"))
        model.beginCompleting(stale, after: 0.05)
        // An edit lands while the tick is still animating. It must survive the completion.
        var edited = stale
        edited.title = "Two, renamed"
        model.update(edited)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertTrue(model.completing.isEmpty)
        let text = try vault.read("Personal/Tasks/Two ttwo0001.md")
        XCTAssertTrue(text.contains("status: done"))
        XCTAssertTrue(text.contains("Two, renamed"))
        model.close()
    }

    // MARK: Completing exactly once

    private let weeklyPath = "Personal/Tasks/Water twkly001.md"
    private let oddPath = "Personal/Tasks/Odd toddd001.md"

    /// A repeating task far in the future, so "the next one" is always exactly a week on.
    private func addWeekly() throws {
        try vault.write("---\nid: twkly001\ntitle: Water\nstatus: open\ndue: 2099-01-05\nrepeat: every week\ncreated: 2026-11-01\n---\n", to: weeklyPath)
    }

    private func completions(_ path: String) throws -> Int {
        try vault.read(path).components(separatedBy: "Completed; next due").count - 1
    }

    func testRepeatingTaskAdvancesOnceWhenFlushedTwice() async throws {
        try addWeekly()
        let model = await openModel()
        model.beginCompleting(try XCTUnwrap(model.task(id: "twkly001")), after: 30)
        model.flushCompletions()
        model.flushCompletions()
        XCTAssertEqual(model.task(id: "twkly001")?.due, "2099-01-12")
        XCTAssertEqual(try completions(weeklyPath), 1)
        model.close()
        XCTAssertEqual(try completions(weeklyPath), 1)
    }

    /// Ticked in the list, then completed from the task's own view before the tick is written.
    func testRepeatingTaskAdvancesOnceWhenAlsoCompletedDirectly() async throws {
        try addWeekly()
        let model = await openModel()
        let task = try XCTUnwrap(model.task(id: "twkly001"))
        model.beginCompleting(task, after: 0.05)
        model.complete(task)
        XCTAssertTrue(model.completing.isEmpty)
        try await Task.sleep(nanoseconds: 300_000_000)
        model.flushCompletions()
        XCTAssertEqual(model.task(id: "twkly001")?.due, "2099-01-12")
        XCTAssertEqual(try completions(weeklyPath), 1)
        model.close()
    }

    func testTickingTwiceQuicklyQueuesOneCompletion() async throws {
        try addWeekly()
        let model = await openModel()
        let task = try XCTUnwrap(model.task(id: "twkly001"))
        model.beginCompleting(task, after: 0.05)
        model.beginCompleting(task, after: 0.05)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(model.task(id: "twkly001")?.due, "2099-01-12")
        XCTAssertEqual(try completions(weeklyPath), 1)
        // The row still holds the copy from before; ticking with it completes the task as it now is, once more.
        model.beginCompleting(task, after: 30)
        model.flushCompletions()
        XCTAssertEqual(model.task(id: "twkly001")?.due, "2099-01-19")
        XCTAssertEqual(try completions(weeklyPath), 2)
        model.close()
    }

    func testTickUntickTickCompletesOnce() async throws {
        try addWeekly()
        let model = await openModel()
        let task = try XCTUnwrap(model.task(id: "twkly001"))
        model.beginCompleting(task, after: 0.05)
        model.cancelCompleting(task.id)
        model.beginCompleting(task, after: 0.05)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(try completions(weeklyPath), 1)
        XCTAssertEqual(model.task(id: "twkly001")?.due, "2099-01-12")
        model.close()
    }

    func testAnUntickedTaskIsNotCompletedByAFlushOrByClosing() async throws {
        let model = await openModel()
        model.beginCompleting(try XCTUnwrap(model.task(id: "tone0001")), after: 30)
        model.cancelCompleting("tone0001")
        model.flushCompletions()
        model.close()
        XCTAssertEqual(try status("Personal/Tasks/One tone0001.md"), "status: open")
    }

    /// Moved to another day while the tick waits: the completion counts from the new day, once.
    func testReschedulingWhileTickedIsKept() async throws {
        try addWeekly()
        let model = await openModel()
        model.beginCompleting(try XCTUnwrap(model.task(id: "twkly001")), after: 30)
        model.move(taskIDs: ["twkly001"], to: "2099-01-07")
        model.flushCompletions()
        XCTAssertEqual(model.task(id: "twkly001")?.due, "2099-01-14")
        XCTAssertEqual(try completions(weeklyPath), 1)
        model.close()
    }

    /// Another device or an agent completed the repeating task while the tick was waiting here.
    func testRepeatingTaskCompletedElsewhereIsNotAdvancedAgain() async throws {
        try addWeekly()
        let model = await openModel()
        model.beginCompleting(try XCTUnwrap(model.task(id: "twkly001")), after: 30)
        var elsewhere = try XCTUnwrap(model.task(id: "twkly001"))
        elsewhere = try TaskStore(vault: vault).complete(elsewhere, by: "claude")
        XCTAssertEqual(elsewhere.due, "2099-01-12")
        await model.reload(force: true)
        XCTAssertEqual(model.task(id: "twkly001")?.due, "2099-01-12")
        model.flushCompletions()
        XCTAssertEqual(model.task(id: "twkly001")?.due, "2099-01-12")
        XCTAssertEqual(try completions(weeklyPath), 1)
        model.close()
    }

    func testReopeningOrDeletingDropsAWaitingTick() async throws {
        let model = await openModel()
        let one = try XCTUnwrap(model.task(id: "tone0001"))
        model.beginCompleting(one, after: 30)
        model.reopen(one)
        XCTAssertTrue(model.completing.isEmpty)
        model.flushCompletions()
        XCTAssertEqual(try status("Personal/Tasks/One tone0001.md"), "status: open")

        let two = try XCTUnwrap(model.task(id: "ttwo0001"))
        model.beginCompleting(two, after: 30)
        model.delete(two)
        model.flushCompletions()
        XCTAssertFalse(vault.exists("Personal/Tasks/Two ttwo0001.md"))
        model.close()
    }

    /// A repeat rule Perch can't work out asks for the next date instead of queueing anything.
    func testTaskNeedingANextDateAsksAndIsNotQueued() async throws {
        try vault.write("---\nid: toddd001\ntitle: Odd\nstatus: open\ndue: 2099-01-05\nrepeat: when the moon is full\ncreated: 2026-11-01\n---\n", to: oddPath)
        let model = await openModel()
        let task = try XCTUnwrap(model.task(id: "toddd001"))
        model.beginCompleting(task, after: 0.01)
        XCTAssertTrue(model.completing.isEmpty)
        XCTAssertEqual(model.needsNextDate?.id, "toddd001")
        model.flushCompletions()
        XCTAssertEqual(try completions(oddPath), 0)
        // The sheet's answer completes it once, with the date given.
        model.needsNextDate = nil
        model.complete(task, manualNextDue: "2099-02-01")
        XCTAssertEqual(model.task(id: "toddd001")?.due, "2099-02-01")
        XCTAssertEqual(try completions(oddPath), 1)
        model.close()
    }

    func testADoneTaskIsNotQueued() async throws {
        let model = await openModel()
        let task = try XCTUnwrap(model.task(id: "tone0001"))
        model.complete(task)
        // The row may still hold the open copy.
        model.beginCompleting(task, after: 30)
        XCTAssertTrue(model.completing.isEmpty)
        model.close()
    }

    /// Switching notebooks writes a waiting tick into the notebook it was made in, and nothing into the new one.
    func testSwitchingNotebooksWritesTheTickToTheOldOne() async throws {
        let other = FileManager.default.temporaryDirectory.appendingPathComponent("perch-completing-other-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: other) }
        try Vault(root: other).write("---\nid: tthr0001\ntitle: Three\nstatus: open\ncreated: 2026-11-01\n---\n", to: "Personal/Tasks/Three tthr0001.md")
        let model = await openModel()
        model.beginCompleting(try XCTUnwrap(model.task(id: "tone0001")), after: 0.05)
        model.selectedTaskID = "tone0001"
        model.open(root: other, engine: nil)
        XCTAssertEqual(try status("Personal/Tasks/One tone0001.md"), "status: done")
        XCTAssertTrue(model.completing.isEmpty)
        XCTAssertTrue(model.tasks.isEmpty, "the old notebook's tasks must not be editable against the new one")
        XCTAssertNil(model.selectedTaskID)
        await model.reload(force: true)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(model.tasks.map(\.id), ["tthr0001"])
        XCTAssertFalse(Vault(root: other).exists("Personal/Tasks/One tone0001.md"))
        model.close()
    }

    /// The three-second reload swaps in fresh copies of every task. A waiting tick must survive that.
    func testAReloadWhileTickedKeepsTheTick() async throws {
        let model = await openModel()
        model.beginCompleting(try XCTUnwrap(model.task(id: "tone0001")), after: 30)
        try vault.write("---\nid: tone0001\ntitle: One, edited elsewhere\nstatus: open\ndue: 2026-11-09\ncreated: 2026-11-01\n---\nNotes.\n", to: "Personal/Tasks/One tone0001.md")
        await model.reload(force: true)
        XCTAssertTrue(model.completing.contains("tone0001"))
        model.flushCompletions()
        let text = try vault.read("Personal/Tasks/One tone0001.md")
        XCTAssertTrue(text.contains("status: done"))
        XCTAssertTrue(text.contains("One, edited elsewhere"))
        model.close()
    }

    func testClosingTheNotebookFlushes() async throws {
        let model = await openModel()
        model.beginCompleting(try XCTUnwrap(model.task(id: "tone0001")), after: 30)
        model.close()
        XCTAssertEqual(try status("Personal/Tasks/One tone0001.md"), "status: done")
    }
}

/// The Mac sidebar draws its own rows, so the rules a system list gave for free are written out and tested here.
final class SidebarOutlineTests: XCTestCase {
    private func file(_ path: String) -> VaultFile { VaultFile(path: path, kind: VaultFile.classify(path), modified: nil) }

    private var tree: FolderNode {
        FolderNode.tree(from: [
            "Inbox.md", "Personal/Plan.md", "Personal/Cooking/Bread.md", "Personal/Cooking/Soup.md",
            "Personal/Cooking/Baking/Scones.md", "Work/Roadmap.kanban.md",
        ].map(file))
    }

    func testOnlyOpenFoldersShowTheirContents() {
        XCTAssertEqual(tree.visibleEntries(expanded: []).map(\.route), [.folder("Personal"), .folder("Work"), .file("Inbox.md")])
        let open = tree.visibleEntries(expanded: ["Personal", "Personal/Cooking"])
        XCTAssertEqual(open.map(\.route), [
            .folder("Personal"), .folder("Personal/Cooking"), .folder("Personal/Cooking/Baking"),
            .file("Personal/Cooking/Bread.md"), .file("Personal/Cooking/Soup.md"), .file("Personal/Plan.md"),
            .folder("Work"), .file("Inbox.md"),
        ])
        XCTAssertEqual(open.map(\.depth), [0, 1, 2, 2, 2, 1, 0, 0])
        XCTAssertEqual(open[0].kind, .folder(isExpanded: true))
        XCTAssertEqual(open[2].kind, .folder(isExpanded: false))
        // A folder open inside a closed one stays hidden.
        XCTAssertEqual(tree.visibleEntries(expanded: ["Personal/Cooking"]).count, 3)
    }

    func testRowsHaveUniqueIDs() {
        let entries = tree.visibleEntries(expanded: ["Personal", "Personal/Cooking", "Personal/Cooking/Baking", "Work"])
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
        XCTAssertEqual(entries.count, 10)
    }

    func testAncestorsAreTheFoldersToOpen() {
        XCTAssertEqual(SidebarKeys.ancestors(of: .file("Personal/Cooking/Baking/Scones.md")), ["Personal", "Personal/Cooking", "Personal/Cooking/Baking"])
        XCTAssertEqual(SidebarKeys.ancestors(of: .folder("Personal/Cooking")), ["Personal"])
        XCTAssertEqual(SidebarKeys.ancestors(of: .file("Inbox.md")), [])
        XCTAssertEqual(SidebarKeys.ancestors(of: .folder("")), [])
        XCTAssertEqual(SidebarKeys.ancestors(of: .today), [])
        XCTAssertEqual(SidebarKeys.parent(of: .file("Personal/Cooking/Bread.md")), .folder("Personal/Cooking"))
        XCTAssertNil(SidebarKeys.parent(of: .folder("Personal")))
    }

    /// A file deep in the tree shows once the folders above it are open.
    func testOpeningAncestorsRevealsADeepFile() {
        let route = Route.file("Personal/Cooking/Baking/Scones.md")
        XCTAssertFalse(tree.visibleEntries(expanded: []).contains { $0.route == route })
        XCTAssertTrue(tree.visibleEntries(expanded: Set(SidebarKeys.ancestors(of: route))).contains { $0.route == route })
    }

    func testArrowKeysStepAndStopAtTheEnds() {
        let rows: [Route] = [.today, .upcoming, .area("Personal"), .folder(""), .file("Inbox.md")]
        XCTAssertEqual(SidebarKeys.step(from: .today, by: 1, in: rows), .upcoming)
        XCTAssertEqual(SidebarKeys.step(from: .area("Personal"), by: -1, in: rows), .upcoming)
        XCTAssertEqual(SidebarKeys.step(from: .today, by: -1, in: rows), .today)
        XCTAssertEqual(SidebarKeys.step(from: .file("Inbox.md"), by: 1, in: rows), .file("Inbox.md"))
        // Nothing in the sidebar is selected, as on Settings: Down starts at the top, Up at the bottom.
        XCTAssertEqual(SidebarKeys.step(from: .settings, by: 1, in: rows), .today)
        XCTAssertEqual(SidebarKeys.step(from: nil, by: -1, in: rows), .file("Inbox.md"))
        XCTAssertNil(SidebarKeys.step(from: .today, by: 1, in: []))
    }

    func testTypingANameJumpsToIt() {
        let rows: [(route: Route, title: String)] = [
            (.today, "Today"), (.upcoming, "Upcoming"), (.area("✈️ Acme"), "✈️ Acme"), (.area("Personal"), "Personal"),
            (.folder("Personal"), "Personal"), (.file("Plan.md"), "Plan"),
        ]
        XCTAssertEqual(SidebarKeys.match("u", in: rows, after: .today), .upcoming)
        XCTAssertEqual(SidebarKeys.match("a", in: rows, after: .today), .area("✈️ Acme"), "a leading emoji is skipped")
        // The same letter again moves to the next match, and wraps.
        XCTAssertEqual(SidebarKeys.match("p", in: rows, after: .today), .area("Personal"))
        XCTAssertEqual(SidebarKeys.match("p", in: rows, after: .area("Personal")), .folder("Personal"))
        XCTAssertEqual(SidebarKeys.match("p", in: rows, after: .file("Plan.md")), .area("Personal"))
        // More letters narrow it, and the selected row may keep matching.
        XCTAssertEqual(SidebarKeys.match("pl", in: rows, after: .area("Personal")), .file("Plan.md"))
        XCTAssertEqual(SidebarKeys.match("pe", in: rows, after: .area("Personal")), .area("Personal"))
        XCTAssertNil(SidebarKeys.match("zz", in: rows, after: .today))
        XCTAssertNil(SidebarKeys.match("", in: rows, after: .today))
    }

    /// A notebook with a thousand notes builds only the rows that show.
    func testALargeNotebookStaysSmallUntilOpened() {
        var files: [VaultFile] = []
        for folder in 0..<20 { for note in 0..<50 { files.append(file("Area \(folder)/Notes/Note \(note).md")) } }
        let tree = FolderNode.tree(from: files)
        XCTAssertEqual(tree.visibleEntries(expanded: []).count, 20)
        XCTAssertEqual(tree.visibleEntries(expanded: ["Area 3", "Area 3/Notes"]).count, 20 + 1 + 50)
    }
}
