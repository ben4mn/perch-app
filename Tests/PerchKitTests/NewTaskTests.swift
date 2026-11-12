import XCTest
@testable import PerchKit
@testable import PerchUI

/// "New task" in the New menu, wherever that menu is: it goes to Tasks, in the area of the folder it was
/// asked from, with the keyboard in quick add.
@MainActor
final class NewTaskTests: XCTestCase {
    private var root: URL!
    private var suite = ""
    private var defaults: UserDefaults!
    private var vault: Vault { Vault(root: root) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("perch-newtask-" + UUID().uuidString)
        suite = "perch-newtask-" + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        try vault.write("---\nid: tper0001\ntitle: Water plants\nstatus: open\ncreated: 2026-11-01\n---\n", to: "Personal/Tasks/Water plants tper0001.md")
        try vault.write("---\nid: texp0001\ntitle: Book flights\nstatus: open\ncreated: 2026-11-01\n---\n", to: "✈️ Acme/Tasks/Book flights texp0001.md")
        try vault.write("# Bread\n", to: "Personal/Cooking/Bread.md")
        try vault.write("# Readme\n", to: "Claude/Readme.md")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suite)
    }

    private func openModel() async -> AppModel {
        let model = AppModel(supportDirectory: root.appendingPathComponent(".support"), navigationDefaults: defaults, savesNavigation: false, configuration: .ownersAreas)
        model.open(root: root, engine: nil)
        await model.reload(force: true)
        return model
    }

    func testAFoldersAreaIsItsTopFolderWhenThatIsAnArea() {
        let areas = ["✈️ Acme", "Personal"]
        XCTAssertEqual(AppModel.area(forFolder: "Personal/Cooking", areas: areas), "Personal")
        XCTAssertEqual(AppModel.area(forFolder: "✈️ Acme", areas: areas), "✈️ Acme")
        XCTAssertNil(AppModel.area(forFolder: "Claude", areas: areas))
        XCTAssertNil(AppModel.area(forFolder: "", areas: areas))
    }

    func testNewTaskFromAFolderOpensQuickAddInThatFoldersArea() async throws {
        let model = await openModel()
        model.route = .folder("Personal/Cooking")
        XCTAssertEqual(model.section, .notes)
        let before = model.newTaskRequests
        model.newTask(fromFolder: "Personal/Cooking")
        XCTAssertEqual(model.section, .tasks)
        XCTAssertEqual(model.taskScope, "Personal")
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(model.newTaskRequests, before + 1, "the quick add field is asked to take the keyboard")
        model.close()
    }

    func testNewTaskFromAFolderOutsideEveryAreaKeepsTheAreaYouWereIn() async {
        let model = await openModel()
        model.setScope("✈️ Acme")
        model.route = .folder("Claude")
        model.newTask(fromFolder: "Claude")
        XCTAssertEqual(model.section, .tasks)
        XCTAssertEqual(model.taskScope, "✈️ Acme")
        model.close()
    }
}
