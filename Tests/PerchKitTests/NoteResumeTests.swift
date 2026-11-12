import XCTest
@testable import PerchUI

/// A note redrawn a moment after it left (the layout changed under it) carries on where it was.
final class NoteResumeTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testAFirstVisitStartsFresh() {
        var resume = NoteResume()
        XCTAssertNil(resume.appear("a.md", now: start))
    }

    func testANoteRedrawnStraightAwayIsStillBeingEdited() {
        var resume = NoteResume()
        _ = resume.appear("a.md", now: start)
        resume.update("a.md", editing: true)
        resume.update("a.md", line: 42)
        resume.disappear("a.md", now: start.addingTimeInterval(10))
        XCTAssertEqual(resume.appear("a.md", now: start.addingTimeInterval(10.5)), NoteResume.Place(editing: true, line: 42))
    }

    func testTheNewViewCanArriveBeforeTheOldOneLeaves() {
        var resume = NoteResume()
        _ = resume.appear("a.md", now: start)
        resume.update("a.md", editing: true)
        // The pane is built while the pushed screen is still there.
        XCTAssertEqual(resume.appear("a.md", now: start.addingTimeInterval(60))?.editing, true)
        resume.disappear("a.md", now: start.addingTimeInterval(60.1))
        // The one still showing keeps the visit alive however long it lasts.
        XCTAssertEqual(resume.appear("a.md", now: start.addingTimeInterval(600))?.editing, true)
    }

    func testComingBackLaterStartsFresh() {
        var resume = NoteResume()
        _ = resume.appear("a.md", now: start)
        resume.update("a.md", editing: true, line: 12)
        resume.disappear("a.md", now: start.addingTimeInterval(5))
        XCTAssertNil(resume.appear("a.md", now: start.addingTimeInterval(5 + NoteResume.window + 0.1)))
        // And the stale place is gone, not waiting for the next quick redraw.
        resume.disappear("a.md", now: start.addingTimeInterval(20))
        XCTAssertEqual(resume.appear("a.md", now: start.addingTimeInterval(20.5)), NoteResume.Place())
    }

    func testNotesAreKeptApartAndFinishingEditingIsRemembered() {
        var resume = NoteResume()
        _ = resume.appear("a.md", now: start)
        _ = resume.appear("b.md", now: start)
        resume.update("a.md", editing: true)
        resume.update("a.md", editing: false)
        resume.update("b.md", editing: true)
        resume.update("c.md", editing: true)
        resume.disappear("a.md", now: start)
        resume.disappear("b.md", now: start)
        XCTAssertEqual(resume.appear("a.md", now: start.addingTimeInterval(1))?.editing, false)
        XCTAssertEqual(resume.appear("b.md", now: start.addingTimeInterval(1))?.editing, true)
        XCTAssertNil(resume.appear("c.md", now: start.addingTimeInterval(1)), "a note that was never shown has nothing to resume")
    }
}

/// The layout changing under a note builds a second view of it before the first has gone. Whatever
/// was typed in the first and not yet written must reach the second, and must not come back later
/// looking like somebody else's change.
@MainActor
final class NoteHandoffTests: XCTestCase {
    private var root: URL!
    private var model: AppModel!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("perch-handoff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "one".write(to: root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        model = AppModel(supportDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("perch-handoff-support-\(UUID().uuidString)"))
        model.open(root: root, engine: nil)
        await model.reload(force: true)
    }

    override func tearDown() async throws {
        await model.close()
        try? FileManager.default.removeItem(at: root)
    }

    private var onDisk: String { (try? String(contentsOf: root.appendingPathComponent("a.md"), encoding: .utf8)) ?? "" }

    func testTypingNotYetSavedCarriesOverToTheNewView() {
        let old = NoteSession(path: "a.md", model: model)
        old.text = "one two"
        XCTAssertEqual(onDisk, "one", "the save is still half a second away")
        // The new arrangement's view is built while the old one is still there.
        let new = NoteSession(path: "a.md", model: model)
        XCTAssertEqual(new.text, "one two")
        // The old view goes, saving as it leaves; typing carries on in the new one.
        old.saveNow()
        XCTAssertEqual(onDisk, "one two")
        new.text = "one two three"
        new.saveNow()
        XCTAssertEqual(onDisk, "one two three", "the old view's save is not a conflict")
        XCTAssertEqual(new.text, "one two three")
    }

    func testTheNewViewSavesWhatItInheritedEvenIfTheOldOneNeverDid() {
        var old: NoteSession? = NoteSession(path: "a.md", model: model)
        old?.text = "one two"
        let new = NoteSession(path: "a.md", model: model)
        old?.discard()
        old = nil
        new.saveNow()
        XCTAssertEqual(onDisk, "one two")
    }

    func testWithNothingUnsavedTheFileIsWhatOpens() {
        let old = NoteSession(path: "a.md", model: model)
        old.text = "one two"
        old.saveNow()
        let new = NoteSession(path: "a.md", model: model)
        XCTAssertEqual(new.text, "one two")
        new.saveNow()
        XCTAssertEqual(onDisk, "one two")
    }

    func testAChangeFromElsewhereIsStillKeptBesideYours() throws {
        let old = NoteSession(path: "a.md", model: model)
        old.text = "one two"
        let new = NoteSession(path: "a.md", model: model)
        old.saveNow()
        // Something else writes the file after the handoff: that is a real conflict, and both are kept.
        try "theirs".write(to: root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        new.text = "one two three"
        new.saveNow()
        XCTAssertTrue(onDisk.contains("theirs"))
        XCTAssertTrue(onDisk.contains("one two three"))
    }
}

/// Files that are open on iPhone when they are renamed or deleted.
@MainActor
final class ShellStateFileTests: XCTestCase {
    func testARenamedNoteStaysOpenWhereverItWasOpen() {
        let shell = ShellState(destination: .notes)
        shell.notesPath = [.file("a.md"), .file("b.md")]
        shell.searchPath = [.file("b.md")]
        shell.agentsPath = [.folder("b.md"), .file("c.md")]
        shell.renamed("b.md", to: "d.md")
        XCTAssertEqual(shell.notesPath, [.file("a.md"), .file("d.md")])
        XCTAssertEqual(shell.searchPath, [.file("d.md")])
        XCTAssertEqual(shell.agentsPath, [.folder("b.md"), .file("c.md")], "only files of that name move")
        XCTAssertEqual(shell.openNote, "d.md")
    }
}
