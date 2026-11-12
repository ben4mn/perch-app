import Foundation
import PerchKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    fail("""
    Usage:
      perch verify <vault-folder>     Check that Perch can read every file. Changes nothing.
      perch todoist-import <vault-folder> [--apply] [--snapshot file.json] [--save-snapshot file.json]
          Dry run by default. The token comes from the PERCH_TODOIST_TOKEN environment variable.
          It only reads from Todoist. --apply writes task files into the vault.
      perch github-sync <folder> <owner> <repo> <branch>
          Syncs a folder with a GitHub branch, the way the iPhone app does. Reads GITHUB_TOKEN.
      perch dates <vault-folder>      Each file's created and last edited dates from Git. Changes nothing.
    """)
}

switch command {
case "verify":
    guard arguments.count == 2 else { fail("Usage: perch verify <vault-folder>") }
    let vault = Vault(root: URL(fileURLWithPath: arguments[1]))
    let report = try VaultVerifier.verify(vault)
    // Guard against a partial scan: compare with what Git says is in the vault.
    let scanned = try vault.scan().count
    let git = Process()
    git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    git.arguments = ["-C", arguments[1], "-c", "core.quotepath=off", "ls-files", "-z"]
    let pipe = Pipe()
    git.standardOutput = pipe
    git.standardError = Pipe()
    var scanMismatch = false
    if (try? git.run()) != nil {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        git.waitUntilExit()
        if git.terminationStatus == 0 {
            let names = String(decoding: data, as: UTF8.self).split(separator: "\0").map(String.init)
            let expected = names.filter { !$0.hasSuffix(".DS_Store") && !$0.hasSuffix(".gitkeep") }.count
            print("Files scanned: \(scanned), tracked by Git: \(expected)")
            scanMismatch = scanned != expected
            if scanMismatch { print("Scan doesn't match Git.") }
        }
    }
    print("Files:")
    for (kind, count) in report.counts.sorted(by: { $0.value > $1.value }) { print("  \(kind.rawValue): \(count)") }
    print("Bytes: \(report.totalBytes)")
    print("Wiki links: \(report.wikiLinks), unresolved: \(report.unresolvedLinks.count)")
    for link in report.unresolvedLinks.prefix(20) { print("  \(link.source) -> [[\(link.target)]]") }
    print("Files with conflict blocks: \(report.conflictFiles.count)")
    for path in report.conflictFiles { print("  \(path)") }
    print("Boards NotesHub would reformat on save: \(report.boardsNotCanonical.count)")
    for path in report.boardsNotCanonical { print("  \(path)") }
    print("Boards with lines NotesHub would drop: \(report.boardsWithDroppableLines.count)")
    for board in report.boardsWithDroppableLines { print("  \(board.path): \(board.count) lines") }
    print("Non-UTF-8 Markdown: \(report.binaryMarkdown.count)")
    print("Existing Tasks folders holding plain notes: \(report.existingTaskFolders.count)")
    for folder in report.existingTaskFolders { print("  \(folder)") }
    print("Failures: \(report.failures.count)")
    for issue in report.failures { print("  \(issue.path): \(issue.problem)") }
    let passed = report.passed && !scanMismatch
    print(passed ? "PASS" : "FAIL")
    exit(passed ? 0 : 1)
case "todoist-import":
    guard arguments.count >= 2 else { fail("Usage: perch todoist-import <vault-folder> [--apply]") }
    let vault = Vault(root: URL(fileURLWithPath: arguments[1]))
    func option(_ name: String) -> String? {
        arguments.firstIndex(of: name).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    }
    var warnings: [String] = []
    let snapshot: TodoistSnapshot
    if let path = option("--snapshot") {
        snapshot = try JSONDecoder().decode(TodoistSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    } else {
        guard let token = ProcessInfo.processInfo.environment["PERCH_TODOIST_TOKEN"], !token.isEmpty else {
            fail("Set PERCH_TODOIST_TOKEN, or pass --snapshot.")
        }
        snapshot = try await TodoistClient(token: token).fetchSnapshot(warnings: &warnings)
    }
    if let path = option("--save-snapshot") {
        try JSONEncoder().encode(snapshot).write(to: URL(fileURLWithPath: path), options: .atomic)
        print("Saved snapshot to \(path). It holds your tasks in plain text, so delete it when you're done.")
    }
    let plan = TodoistMapper.plan(snapshot: snapshot, existing: TaskStore(vault: vault).loadAll())
    let summary = plan.summary
    print("Projects: \(snapshot.projects.map(\.name).joined(separator: ", "))")
    print("New tasks: \(plan.tasks.count) (open \(summary.open), completed \(summary.completed)), already imported: \(summary.alreadyImported)")
    print("Subtasks: \(summary.subtasks), with details: \(summary.withDetails), comments: \(summary.comments), reminders: \(summary.reminders), repeating: \(summary.repeating)")
    print("By area: \(summary.byArea.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))")
    print("By owner: \(summary.byOwner.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))")
    print("By priority: \(summary.byPriority.sorted { $0.key < $1.key }.map { "P\($0.key) \($0.value)" }.joined(separator: ", "))")
    for warning in warnings + plan.warnings { print("Warning: \(warning)") }
    if arguments.contains("--apply") {
        print("Wrote \(try TodoistMapper.apply(plan, to: vault)) task files.")
    } else {
        print("Dry run: nothing was written. Add --apply to write these files.")
    }
case "task-encode":
    // Prints what the app would write for a task file, to check other writers match.
    guard arguments.count == 2 else { fail("Usage: perch task-encode <task-file>") }
    let url = URL(fileURLWithPath: arguments[1])
    let task = try TaskCodec.decode(path: "Area/Tasks/" + url.lastPathComponent, text: String(contentsOf: url, encoding: .utf8))
    FileHandle.standardOutput.write(Data(TaskCodec.encode(task).utf8))
case "github-sync":
    guard arguments.count == 5, let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] else {
        fail("Usage: GITHUB_TOKEN=... perch github-sync <folder> <owner> <repo> <branch>")
    }
    let root = URL(fileURLWithPath: arguments[1])
    let engine = GitHubAPISync(
        configuration: .init(owner: arguments[2], repository: arguments[3], branch: arguments[4]),
        token: token, root: root, stateURL: root.appendingPathExtension("sync-state.json")
    )
    let result = try await engine.sync()
    print("pulled \(result.pulled), pushed \(result.pushed), conflicts \(result.conflicts)")
case "dates":
    guard arguments.count == 2 else { fail("Usage: perch dates <vault-folder>") }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", arguments[1]] + FileHistory.logArguments
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    let log = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    let day = DateFormatter()
    day.dateFormat = "yyyy-MM-dd"
    for (path, dates) in FileHistory.parse(log).sorted(by: { $0.key < $1.key }) {
        print("\(day.string(from: dates.created))\t\(day.string(from: dates.edited))\t\(path)")
    }
default:
    fail("Unknown command: \(command)")
}
