import XCTest
@testable import PerchKit

final class FileHistoryTests: XCTestCase {
    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: Double(n) * 86_400) }

    /// One commit of `git log` output in `FileHistory.logArguments` form.
    private func commit(_ n: Int, _ changes: String...) -> String {
        "\u{1e}\(n * 86_400)\n\n" + changes.joined(separator: "\n") + "\n"
    }

    func testAddThenEdits() {
        let log = commit(9, "M\tNotes/Plan.md") + commit(5, "M\tNotes/Plan.md") + commit(1, "A\tNotes/Plan.md")
        XCTAssertEqual(FileHistory.parse(log)["Notes/Plan.md"], FileDates(created: day(1), edited: day(9)))
    }

    func testAMoveKeepsDatesAndAnEditedRenameCounts() {
        let log = commit(8, "R100\tOld/Moved.md\tNew/Moved.md", "R087\tOld/Draft.md\tNew/Final.md")
            + commit(3, "M\tOld/Moved.md")
            + commit(2, "A\tOld/Moved.md", "A\tOld/Draft.md")
        let dates = FileHistory.parse(log)
        XCTAssertEqual(dates["New/Moved.md"], FileDates(created: day(2), edited: day(3)), "a pure move is not an edit")
        XCTAssertEqual(dates["New/Final.md"], FileDates(created: day(2), edited: day(8)), "a rename with changes is")
        XCTAssertNil(dates["Old/Moved.md"])
    }

    func testRenameChainsFollowBackToTheFirstAdd() {
        let log = commit(9, "R100\tB.md\tC.md") + commit(6, "R100\tA.md\tB.md") + commit(4, "M\tA.md") + commit(1, "A\tA.md")
        XCTAssertEqual(FileHistory.parse(log)["C.md"], FileDates(created: day(1), edited: day(4)))
    }

    func testDeletedAndAddedAgainStartsOver() {
        let log = commit(9, "A\tTodo.md") + commit(7, "D\tTodo.md") + commit(2, "M\tTodo.md") + commit(1, "A\tTodo.md")
        XCTAssertEqual(FileHistory.parse(log)["Todo.md"], FileDates(created: day(9), edited: day(9)))
    }

    func testQuotedAndUnicodePaths() {
        let quoted = #""Say \"hi\".md""#
        let log = commit(2, "M\t" + quoted) + commit(1, "A\t" + quoted, "A\t✈️ Acme/Trip.md", "A\t" + #""caf\303\251.md""#)
        let dates = FileHistory.parse(log)
        XCTAssertEqual(dates[#"Say "hi".md"#], FileDates(created: day(1), edited: day(2)))
        XCTAssertEqual(dates["✈️ Acme/Trip.md"]?.created, day(1))
        XCTAssertEqual(dates["café.md"]?.created, day(1))
    }

    func testApplyPrefersHistoryButKeepsUncommittedSaves() {
        let files = [
            VaultFile(path: "A.md", modified: day(30), created: day(30)),
            VaultFile(path: "B.md", modified: day(30), created: day(30)),
            VaultFile(path: "New.md", modified: day(31), created: day(31)),
        ]
        let history = ["A.md": FileDates(created: day(1), edited: day(5)), "B.md": FileDates(created: day(2), edited: day(6))]
        let dated = FileHistory.apply(history, uncommitted: ["B.md"], to: files)
        XCTAssertEqual(dated[0].created, day(1))
        XCTAssertEqual(dated[0].lastEdited, day(5), "a fresh copy's disk time isn't an edit")
        XCTAssertEqual(dated[1].lastEdited, day(30), "an unsynced save is newer than the history")
        XCTAssertEqual(dated[2].created, day(31))
        XCTAssertEqual(dated[2].lastEdited, day(31), "a file Git doesn't know keeps its disk dates")
    }
}
