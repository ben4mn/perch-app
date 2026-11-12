import XCTest
@testable import PerchKit
@testable import PerchUI

/// Moving a task to another day must change its `due:` line and nothing else in the file.
/// These go through `AppModel.move`, the one path every drag, drop and "Move to" menu uses.
@MainActor
final class TaskRescheduleTests: XCTestCase {
    private var root: URL!
    private var vault: Vault { Vault(root: root) }

    /// A task as the Todoist import and the triage routine write them: quoted values, a time, a repeat
    /// rule, reminders, a deadline, a key Perch doesn't know, a body and an activity log.
    private let full = """
    ---
    notehub_pinned: true
    id: tfull001
    title: "Re-accept Robin's plan prep (Thu 29 Oct, 12:00-12:30 CT)"
    status: open
    owner: alex
    due: 2026-11-12
    time: "10:30"
    deadline: 2026-11-20
    repeat: every week
    remind: ["2026-11-12T09:00", 30m]
    priority: 2
    labels: [work, garden]
    created: 2026-10-22
    source: "todoist:0000example0000"
    ---
    **Ask:** accept from the email.

    - [Event](https://example.com/?a=1&b=2)

    ## Activity

    - 2026-10-30 @triage-routine: This task can be ticked.

    """

    private func file(id: String, title: String, status: String = "open", due: String? = "2026-11-12") -> String {
        "---\nid: \(id)\ntitle: \(title)\nstatus: \(status)\n" + (due.map { "due: \($0)\n" } ?? "") + "created: 2026-11-01\n---\nNotes.\n"
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("perch-reschedule-" + UUID().uuidString)
        try vault.write(full, to: "Personal/Tasks/Full tfull001.md")
        try vault.write(file(id: "tplain01", title: "Plain"), to: "Personal/Tasks/Plain tplain01.md")
        try vault.write(file(id: "tdone001", title: "Done", status: "done"), to: "Personal/Tasks/Done tdone001.md")
        try vault.write(file(id: "tnodate1", title: "Undated", due: nil), to: "Personal/Tasks/Undated tnodate1.md")
        try vault.write(file(id: "tbad0001", title: "Mistyped", due: "next tuesday"), to: "Personal/Tasks/Mistyped tbad0001.md")
        try vault.write("# Just a note\n", to: "Personal/Note.md")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func openModel() async -> AppModel {
        let model = AppModel(supportDirectory: root.appendingPathComponent(".support"))
        model.open(root: root, engine: nil)
        await model.reload(force: true)
        addTeardownBlock { await model.close() }
        return model
    }

    /// The lines that differ between two versions of a file, as (removed, added).
    private func changes(from old: String, to new: String) -> (removed: [String], added: [String]) {
        let before = old.components(separatedBy: "\n"), after = new.components(separatedBy: "\n")
        let difference = after.difference(from: before)
        var removed: [String] = [], added: [String] = []
        for change in difference {
            switch change {
            case let .remove(_, line, _): removed.append(line)
            case let .insert(_, line, _): added.append(line)
            }
        }
        return (removed, added)
    }

    private func modified(_ path: String) throws -> Date {
        try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: vault.url(for: path).path)[.modificationDate] as? Date)
    }

    private func taskFileCount() throws -> Int {
        try vault.scan().filter { $0.kind == .task }.count
    }

    // MARK: Through AppModel

    func testMovingATaskChangesOnlyItsDueLine() async throws {
        let model = await openModel()
        XCTAssertEqual(model.tasks.count, 5)
        let path = "Personal/Tasks/Full tfull001.md"

        XCTAssertEqual(model.move(taskIDs: ["tfull001"], to: "2026-11-19"), ["tfull001"])
        let moved = try vault.read(path)
        let diff = changes(from: full, to: moved)
        XCTAssertEqual(diff.removed, ["due: 2026-11-12"])
        XCTAssertEqual(diff.added, ["due: 2026-11-19"])
        XCTAssertEqual(model.task(id: "tfull001")?.due, "2026-11-19", "the list updates straight away")

        // And the file still reads back as the same task.
        let reread = try TaskCodec.decode(path: path, text: moved)
        XCTAssertEqual(reread.time, "10:30")
        XCTAssertEqual(reread.recurrence, "every week")
        XCTAssertEqual(reread.remind, ["2026-11-12T09:00", "30m"])
        XCTAssertEqual(reread.deadline, "2026-11-20")
        XCTAssertEqual(reread.extraFields["notehub_pinned"], "true")
        XCTAssertEqual(TaskCodec.encode(reread), moved, "round-trips through TaskCodec")
    }

    func testNoDateRemovesOnlyTheDueLineAndMovingBackRestoresTheFile() async throws {
        let model = await openModel()
        let path = "Personal/Tasks/Full tfull001.md"

        XCTAssertEqual(model.move(taskIDs: ["tfull001"], to: nil), ["tfull001"])
        let cleared = try vault.read(path)
        let diff = changes(from: full, to: cleared)
        XCTAssertEqual(diff.removed, ["due: 2026-11-12"])
        XCTAssertEqual(diff.added, [])
        let task = try XCTUnwrap(model.task(id: "tfull001"))
        XCTAssertNil(task.due)
        XCTAssertEqual(task.time, "10:30", "the time is kept for when the task gets a date again")
        XCTAssertEqual(task.recurrence, "every week")
        XCTAssertEqual(task.remind.count, 2)
        XCTAssertEqual(task.deadline, "2026-11-20")

        XCTAssertEqual(model.move(taskIDs: ["tfull001"], to: nil), [], "already undated")
        model.move(taskIDs: ["tfull001"], to: "2026-11-12")
        XCTAssertEqual(try vault.read(path), full, "back on its day, the file is byte for byte what it was")
    }

    func testDropsThatChangeNothingDoNotTouchTheFile() async throws {
        let model = await openModel()
        let paths = ["Personal/Tasks/Plain tplain01.md", "Personal/Tasks/Done tdone001.md", "Personal/Note.md"]
        let before = try paths.map { (try vault.read($0), try modified($0)) }
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(model.move(taskIDs: ["tplain01"], to: "2026-11-12"), [], "already on that day")
        XCTAssertEqual(model.move(taskIDs: ["tdone001"], to: "2026-11-20"), [], "a finished task doesn't move")
        XCTAssertEqual(model.move(taskIDs: ["Personal/Note.md", "", "nope", "B0A1F6C2-0000-4000-8000-000000000000"], to: "2026-11-20"), [], "text that isn't a task id")
        XCTAssertEqual(model.move(taskIDs: ["tplain01"], to: "the 20th"), [], "a day that isn't a date")
        model.reschedule(model.tasks.filter { $0.id == "tplain01" || $0.id == "tdone001" }, to: "2026-11-12")

        for (path, old) in zip(paths, before) {
            XCTAssertEqual(try vault.read(path), old.0, path)
            XCTAssertEqual(try modified(path), old.1, "\(path) was rewritten")
        }
        XCTAssertEqual(model.task(id: "tdone001")?.due, "2026-11-12")
    }

    func testAMultiTaskDropMovesEachOpenTaskOnce() async throws {
        let model = await openModel()
        let moved = model.move(taskIDs: ["tplain01", "tdone001", "tnodate1", "junk", "tfull001", "tbad0001"], to: "2026-11-12")
        XCTAssertEqual(moved, ["tnodate1", "tbad0001"], "the two already on the 12th and the finished one are skipped")
        XCTAssertEqual(model.task(id: "tnodate1")?.due, "2026-11-12")
        XCTAssertEqual(model.task(id: "tbad0001")?.due, "2026-11-12", "moving a task with a mistyped date gives it a real one")
        let undated = try vault.read("Personal/Tasks/Undated tnodate1.md")
        let diff = changes(from: file(id: "tnodate1", title: "Undated", due: nil), to: undated)
        XCTAssertEqual(diff.removed, [])
        XCTAssertEqual(diff.added, ["due: 2026-11-12"])
        XCTAssertEqual(try taskFileCount(), 5)
        XCTAssertEqual(try vault.read("Personal/Tasks/Full tfull001.md"), full)
    }

    func testQuickAddOnADayWritesOneFileWithThatDay() async throws {
        let model = await openModel()
        let task = try XCTUnwrap(model.quickAdd("Water the plants", defaultDue: "2026-12-03"))
        XCTAssertEqual(task.due, "2026-12-03")
        XCTAssertEqual(try taskFileCount(), 6)
        let written = try TaskCodec.decode(path: task.path, text: try vault.read(task.path))
        XCTAssertEqual(written.due, "2026-12-03")
        XCTAssertEqual(written.title, "Water the plants")
        XCTAssertEqual(model.tasks.filter { $0.id == task.id }.count, 1)

        // A date in the text wins over the day it was typed on.
        let dated = try XCTUnwrap(model.quickAdd("Call the vet 2026-12-24", defaultDue: "2026-12-03"))
        XCTAssertEqual(dated.due, "2026-12-24")
        XCTAssertEqual(try taskFileCount(), 7)

        await model.reload(force: true)
        XCTAssertEqual(model.tasks.filter { $0.id == task.id }.count, 1, "the reload doesn't duplicate it")
        XCTAssertEqual(model.tasks.count, 7)
    }

    /// A background scan that was already running when a task moved must not put the old date back.
    func testAScanInFlightDoesNotUndoAMove() async throws {
        // Enough files that the scan is still running when the move lands.
        for index in 0..<400 {
            try vault.write(file(id: "tbulk\(index)", title: "Bulk \(index)"), to: "Area/Tasks/Bulk \(index) tbulk\(index).md")
        }
        let model = await openModel()
        XCTAssertEqual(model.tasks.count, 405)

        for round in 0..<12 {
            let day = String(format: "2026-12-%02d", round + 1)
            let scan = Task { await model.reload(force: true) }
            await Task.yield()
            model.move(taskIDs: ["tplain01"], to: day)
            XCTAssertEqual(model.task(id: "tplain01")?.due, day)
            await scan.value
            XCTAssertEqual(model.task(id: "tplain01")?.due, day, "round \(round): a stale scan overwrote the move")
        }
        // Forced reloads still land: a file changed behind the app's back shows up.
        try vault.write(file(id: "tplain01", title: "Plain", due: "2027-01-05"), to: "Personal/Tasks/Plain tplain01.md")
        await model.reload(force: true)
        XCTAssertEqual(model.task(id: "tplain01")?.due, "2027-01-05")
        XCTAssertEqual(model.tasks.count, 405)
    }

    // MARK: The rule itself

    func testRescheduledOnlyEverChangesDue() throws {
        let task = try TaskCodec.decode(path: "Personal/Tasks/Full tfull001.md", text: full)
        var expected = task
        expected.due = "2027-01-04"
        XCTAssertEqual(TaskCalendar.rescheduled(task, to: "2027-01-04"), expected)
        expected.due = nil
        XCTAssertEqual(TaskCalendar.rescheduled(task, to: nil), expected)
        XCTAssertNil(TaskCalendar.rescheduled(task, to: "2026-11-12"))
        XCTAssertNil(TaskCalendar.rescheduled(task, to: "2026-02-30"), "not a real day")

        var done = task
        done.status = .done
        XCTAssertNil(TaskCalendar.rescheduled(done, to: "2027-01-04"))
        XCTAssertNil(TaskCalendar.rescheduled(done, to: nil))

        var timed = task
        timed.due = "2026-11-12T10:30"
        XCTAssertNil(TaskCalendar.rescheduled(timed, to: "2026-11-12"), "same day, whatever follows the date")
        XCTAssertEqual(TaskCalendar.rescheduled(timed, to: "2026-11-13")?.due, "2026-11-13")
    }
}
