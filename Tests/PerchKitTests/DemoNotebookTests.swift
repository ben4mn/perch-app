import XCTest
@testable import PerchKit

/// The demo notebook (`Demo/notebook`) is what someone opens first in a build made from the public source,
/// with nothing configured, and what the website's clips are drawn from in the maintainer's build. These
/// hold it, and the dated copy `scripts/demo-notebook.sh` makes, to the build's settings.
final class DemoNotebookTests: XCTestCase {
    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let notebook = repo.appendingPathComponent("Demo/notebook")
    private let neutral = PerchConfiguration.neutral
    /// The one person in the notebook besides its owner: Tomas, who runs the studio with her.
    private let people = ["tomas"]

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("perch-demo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: scratch) }

    private func tasks(in root: URL) -> [PerchTask] { TaskStore(vault: Vault(root: root)).loadAll() }

    private func areas(in root: URL, standard: [String]) throws -> [String] {
        let files = try Vault(root: root).scan()
        let top = Set(files.compactMap { file -> String? in
            let parts = file.path.split(separator: "/")
            return parts.count > 1 ? String(parts[0]) : nil
        })
        return AreaList.discovered(topLevelFolders: top, taskAreas: tasks(in: root).map(\.area), standard: standard)
    }

    /// The agents the clips show as working in the notebook (`Demo/agents.json`).
    private func standInAgents() throws -> Set<String> {
        struct File: Decodable {
            struct Here: Decodable { var name: String }
            struct Deed: Decodable { var agent: String }
            var here: [Here]
            var history: [Deed]
        }
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: Self.repo.appendingPathComponent("Demo/agents.json")))
        return Set(file.here.map(\.name) + file.history.map(\.agent))
    }

    /// Runs `scripts/demo-notebook.sh` into a new folder and returns it.
    private func datedCopy(_ arguments: [String]) throws -> URL {
        let target = scratch.appendingPathComponent("copy-\(UUID().uuidString)")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [Self.repo.appendingPathComponent("scripts/demo-notebook.sh").path, target.path] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, text)
        return target
    }

    func testPassesTheVerifier() throws {
        let report = try VaultVerifier.verify(Vault(root: Self.notebook))
        XCTAssertTrue(report.passed, report.failures.map { "\($0.path): \($0.problem)" }.joined(separator: "\n"))
        XCTAssertTrue(report.unresolvedLinks.isEmpty, "\(report.unresolvedLinks)")
        XCTAssertTrue(report.conflictFiles.isEmpty)
    }

    /// Its areas are its own three folders, in the public build and in one with other standard areas, and
    /// no empty fallback area is added beside them.
    func testAreasAreItsOwnFoldersAndNothingElse() throws {
        for standard in [neutral.standardAreas, ["✈️ Work", "Personal"]] {
            let areas = try areas(in: Self.notebook, standard: standard)
            XCTAssertEqual(Set(areas), ["Studio", "Home", "Learning"], "standard areas \(standard)")
            XCTAssertEqual(areas.count, 3)
        }
    }

    /// Every task has an owner, as tasks the app writes do. The notebook owner's own tasks and comments
    /// are the public build's owner, so they show as the user's own; the rest are Tomas's or an agent's.
    func testTheOwnersTasksBelongToThePublicDefaultOwner() throws {
        let tasks = tasks(in: Self.notebook)
        XCTAssertEqual(tasks.count, 49)
        XCTAssertEqual(tasks.filter { $0.owner == nil }.map(\.path), [])
        let mine = tasks.filter { $0.owner == neutral.ownerID }
        XCTAssertGreaterThan(mine.count, 40)
        let agents = try standInAgents()
        let known = Set([neutral.ownerID] + people).union(agents)
        XCTAssertEqual(Set(tasks.compactMap(\.owner)).subtracting(known), [])
        let authors = Set(tasks.flatMap { $0.activity.map(\.author) })
        XCTAssertTrue(authors.contains(neutral.ownerID))
        XCTAssertEqual(authors.subtracting(known), [])
    }

    /// The agents in it are agents: whoever proposes a task as done, or owns one and isn't a person, is one
    /// of the agents the clips show, the build offers as an owner, and the notch draws with its own mark.
    func testItsAgentsAreAgents() throws {
        let tasks = tasks(in: Self.notebook)
        let agents = try standInAgents()
        XCTAssertTrue(agents.isDisjoint(with: [neutral.ownerID] + people))
        let proposers = Set(tasks.compactMap(\.proposedDoneBy))
        XCTAssertFalse(proposers.isEmpty)
        let owningAgents = Set(tasks.compactMap(\.owner)).subtracting([neutral.ownerID] + people)
        for agent in proposers.union(owningAgents) {
            XCTAssertTrue(agents.contains(agent), agent)
            XCTAssertTrue(neutral.otherOwners.contains(agent), agent)
            XCTAssertEqual(AgentHistory.mark(for: agent), .claude, agent)
        }
    }

    /// A copy for a build whose owner isn't the public default carries that owner instead, on the tasks
    /// and in the comments, so the maintainer's build (and its clips) shows them as the user's own too.
    func testADatedCopyTakesTheBuildsOwner() throws {
        let source = tasks(in: Self.notebook)
        let copy = try datedCopy(["--date", "2026-11-19", "--owner", "robin"])
        let copied = tasks(in: copy)
        XCTAssertEqual(copied.count, source.count)
        XCTAssertFalse(copied.contains { $0.owner == neutral.ownerID })
        XCTAssertEqual(copied.filter { $0.owner == "robin" }.count, source.filter { $0.owner == neutral.ownerID }.count)
        let authors = Set(copied.flatMap { $0.activity.map(\.author) })
        XCTAssertTrue(authors.contains("robin"))
        XCTAssertFalse(authors.contains(neutral.ownerID))
        // Everyone else keeps their own name, and every date moves by the same days.
        for owner in people + ["claude"] {
            XCTAssertEqual(copied.filter { $0.owner == owner }.count, source.filter { $0.owner == owner }.count, owner)
        }
        let before = Dictionary(uniqueKeysWithValues: source.map { ($0.id, $0.due) })
        for task in copied where task.due != nil {
            XCTAssertEqual(task.due, before[task.id].flatMap { $0 }.flatMap { DayMath.adding(days: 7, to: $0) }, task.title)
        }
        let report = try VaultVerifier.verify(Vault(root: copy))
        XCTAssertTrue(report.passed)
        XCTAssertTrue(report.unresolvedLinks.isEmpty, "\(report.unresolvedLinks)")
        XCTAssertEqual(Set(try areas(in: copy, standard: neutral.standardAreas)), ["Studio", "Home", "Learning"])
    }

    func testACopyRefusesAnOwnerThatIsntOneWord() throws {
        let target = scratch.appendingPathComponent("bad")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [Self.repo.appendingPathComponent("scripts/demo-notebook.sh").path, target.path, "--owner", "two words"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertNotEqual(process.terminationStatus, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("Studio").path))
    }
}
