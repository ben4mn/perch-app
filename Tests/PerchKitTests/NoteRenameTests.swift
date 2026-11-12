import XCTest
@testable import PerchKit
@testable import PerchUI

/// Renaming a note from the sidebar or its title, possibly while it is open and being typed in.
@MainActor
final class NoteRenameTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("perch-rename-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Personal"), withIntermediateDirectories: true)
        try "# Rules\n".write(to: root.appendingPathComponent("Personal/Rules.md"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func openModel() async -> AppModel {
        let model = AppModel(supportDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("perch-support-\(UUID().uuidString)"))
        model.open(root: root, engine: nil)
        await model.reload(force: true)
        addTeardownBlock { await model.close() }
        return model
    }

    private func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
    }

    func testRenamingAnOpenNoteKeepsWhatWasJustTyped() async throws {
        let model = await openModel()
        let session = NoteSession(path: "Personal/Rules.md", model: model)
        session.text = "# Rules\nTyped a moment ago\n"
        // From the sidebar, while the note's own view hasn't saved yet.
        model.rename("Personal/Rules.md", to: "Life Rules")
        let renamed = try String(contentsOf: root.appendingPathComponent("Personal/Life Rules.md"), encoding: .utf8)
        XCTAssertEqual(renamed, "# Rules\nTyped a moment ago\n")
        XCTAssertFalse(exists("Personal/Rules.md"))
        // A late save from the old view must not bring the old file back.
        session.text += "more"
        session.saveNow()
        XCTAssertFalse(exists("Personal/Rules.md"))
    }

    func testANoteBeingEditedIsStillBeingEditedUnderItsNewName() {
        var resume = NoteResume()
        let now = Date(timeIntervalSince1970: 1_000_000)
        _ = resume.appear("a.md", now: now)
        resume.update("a.md", editing: true, line: 7)
        resume.renamed(from: "a.md", to: "b.md")
        resume.disappear("a.md", now: now)
        XCTAssertEqual(resume.appear("b.md", now: now.addingTimeInterval(0.5)), NoteResume.Place(editing: true, line: 7))
        XCTAssertNil(resume.appear("a.md", now: now.addingTimeInterval(0.5)))
    }
}
