#if os(macOS)
import Foundation

/// Syncs a normal Git clone with the system `git`, so it works with your existing setup and credentials.
/// A notebook cloned from GitHub through Perch's sign-in passes a token instead: see `invocation`.
public actor GitCLISync: SyncEngine {
    private let root: URL
    private let vault: Vault
    private let gitPath: String
    private let remote = "origin"
    private let tokenProvider: (@Sendable () async throws -> String)?
    /// The token for the sync under way, fetched once at its start.
    private var token: String?

    public init(root: URL, gitPath: String = "/usr/bin/git", token: (@Sendable () async throws -> String)? = nil) {
        self.root = root
        vault = Vault(root: root)
        self.gitPath = gitPath
        tokenProvider = token
    }

    public func isRepository() -> Bool {
        (try? git(["rev-parse", "--is-inside-work-tree"])) == "true"
    }

    public func sync() async throws -> SyncResult {
        token = try await tokenProvider?()
        defer { token = nil }
        do {
            return try await syncNow()
        } catch let SyncError.failed(message) where tokenProvider != nil && Self.isAuthenticationFailure(message) {
            throw SyncError.authentication
        }
    }

    private func syncNow() async throws -> SyncResult {
        var result = SyncResult()
        guard isRepository() else { throw SyncError.notConfigured }
        guard (try? git(["symbolic-ref", "--short", "HEAD"])) != nil else {
            throw SyncError.failed("The notebook isn't on a branch.")
        }
        let branch = try git(["symbolic-ref", "--short", "HEAD"])
        // A previous interrupted merge must be finished before anything else runs.
        if vault.exists(".git/MERGE_HEAD") { result.conflicts = try resolveMerge(date: today()) }

        let pending = try changedFiles()
        if !pending.isEmpty {
            _ = try git(["add", "-A"])
            _ = try git(["commit", "-m", commitMessage(for: pending)])
            result.pushed = pending.count
        }

        let hasRemote = (try? git(["remote", "get-url", remote])) != nil
        guard hasRemote else { return result }
        _ = try git(["fetch", remote])
        guard (try? git(["rev-parse", "--verify", "\(remote)/\(branch)"])) != nil else {
            _ = try git(["push", "-u", remote, branch])
            return result
        }

        // A brand-new clone has no commits of its own yet, so it just takes the remote's.
        guard (try? git(["rev-parse", "--verify", "HEAD"])) != nil else {
            _ = try git(["checkout", "-B", branch, "\(remote)/\(branch)"])
            result.pulled = Int(try git(["rev-list", "--count", "HEAD"])) ?? 0
            return result
        }

        let behind = Int(try git(["rev-list", "--count", "HEAD..\(remote)/\(branch)"])) ?? 0
        if behind > 0 {
            result.pulled = behind
            do {
                _ = try git(["merge", "--no-edit", "\(remote)/\(branch)"])
            } catch {
                result.conflicts += try resolveMerge(date: today())
            }
        }

        let ahead = Int(try git(["rev-list", "--count", "\(remote)/\(branch)..HEAD"])) ?? 0
        if ahead > 0 { _ = try git(["push", remote, branch]) }
        return result
    }

    /// Each file's created and last edited dates, and the files with changes not committed yet.
    /// Reading the whole history takes a moment, so it is skipped when HEAD is still `knownHead`
    /// (then `dates` is nil and the caller keeps what it has).
    public func fileHistory(knownHead: String?) -> (head: String, dates: [String: FileDates]?, uncommitted: Set<String>)? {
        guard let head = try? git(["rev-parse", "HEAD"]), !head.isEmpty else { return nil }
        var dates: [String: FileDates]?
        if head != knownHead {
            guard let log = try? git(FileHistory.logArguments, trim: false) else { return nil }
            dates = FileHistory.parse(log)
        }
        var uncommitted: Set<String> = []
        if let status = try? git(["-c", "core.quotepath=off", "status", "--porcelain", "-z", "--untracked-files=no"], trim: false) {
            // Entries are "XY path", NUL-separated; a rename's old path follows as its own entry.
            var entries = status.split(separator: "\0", omittingEmptySubsequences: true).makeIterator()
            while let entry = entries.next() {
                guard entry.count > 3 else { continue }
                uncommitted.insert(String(entry.dropFirst(3)))
                if entry.first == "R" || entry.first == "C" { _ = entries.next() }
            }
        }
        return (head, dates, uncommitted)
    }

    /// Git's history for one file, or all files, for the activity view.
    public func log(path: String? = nil, limit: Int = 100) -> [GitLogEntry] {
        var arguments = ["log", "-n", String(limit), "--date=iso-strict", "--format=%H%x1f%an%x1f%ae%x1f%ad%x1f%s"]
        if let path { arguments += ["--", path] }
        guard let output = try? git(arguments), !output.isEmpty else { return [] }
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 5 else { return nil }
            return GitLogEntry(hash: parts[0], author: parts[1], email: parts[2], date: parts[3], subject: parts[4])
        }
    }

    private func resolveMerge(date: String) throws -> [String] {
        let output = try git(["diff", "--name-only", "--diff-filter=U", "-z"], trim: false)
        let paths = output.split(separator: "\0").map(String.init)
        for path in paths {
            if MergePolicy.usesCopy(path) || !vault.exists(path) {
                // Keep the incoming version in place and save this device's version beside it.
                let copy = MergePolicy.conflictCopyPath(path, date: date)
                if let mine = try? git(["show", ":2:\(path)"], trim: false) { try vault.write(mine, to: copy) }
                if (try? git(["checkout", "--theirs", "--", path])) == nil, vault.exists(path) { try vault.delete(path) }
            } else {
                let merged = ConflictBlocks.fromGitMarkers(try vault.read(path))
                try vault.write(merged, to: path)
            }
        }
        _ = try git(["add", "-A"])
        _ = try git(["commit", "--no-edit", "-m", "Merge from \(remote), keeping both versions of \(paths.count) file(s)"])
        return paths
    }

    private func changedFiles() throws -> [String] {
        let output = try git(["-c", "core.quotepath=off", "status", "--porcelain=v1", "-z", "--untracked-files=all"], trim: false)
        return output.split(separator: "\0").compactMap { entry in
            guard entry.count > 3 else { return nil }
            return String(entry.dropFirst(3))
        }.filter { !$0.hasSuffix(".DS_Store") }
    }

    private func commitMessage(for files: [String]) -> String {
        if files.count == 1 { return "Update \(VaultFile(path: files[0]).name)" }
        return "Update \(files.count) files"
    }

    private func today() -> String { DayMath.string(from: Date()) }

    @discardableResult
    private func git(_ arguments: [String], trim: Bool = true) throws -> String {
        try Self.run(gitPath: gitPath, Self.invocation(root: root, arguments: arguments, token: token), trim: trim)
    }

    /// The arguments and environment for one `git` call. With a token, git gets it for github.com from a
    /// credential helper that reads it from the environment, after clearing any helper set up elsewhere
    /// (the Mac's keychain may hold a different GitHub login). The token is never in the arguments, so it
    /// can't be seen in a process list, and nothing about it is written to the repository's config.
    static func invocation(root: URL?, arguments: [String], token: String?) -> (arguments: [String], environment: [String: String]) {
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_MERGE_AUTOEDIT"] = "no"
        environment["PERCH_GIT_TOKEN"] = nil
        var prefix = root.map { ["-C", $0.path] } ?? []
        if let token {
            environment["PERCH_GIT_TOKEN"] = token
            let helper = #"!f() { test "$1" = get || exit 0; echo username=x-access-token; echo "password=$PERCH_GIT_TOKEN"; }; f"#
            prefix += ["-c", "credential.https://github.com.helper=", "-c", "credential.https://github.com.helper=\(helper)"]
        }
        return (prefix + arguments, environment)
    }

    static func isAuthenticationFailure(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return ["authentication failed", "returned error: 401", "returned error: 403", "invalid username or token", "permission to"]
            .contains { lowered.contains($0) }
    }

    @discardableResult
    private static func run(gitPath: String, _ call: (arguments: [String], environment: [String: String]), trim: Bool = true) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = call.arguments
        process.environment = call.environment
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        // Read before waiting, so a large output can't fill the pipe and block.
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: outData, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errData, as: UTF8.self)
            throw SyncError.failed(message.isEmpty ? text : message)
        }
        return trim ? text.trimmingCharacters(in: .whitespacesAndNewlines) : text
    }

    /// The address a folder's `origin` remote points at, if it is a Git repository with one.
    public static func origin(of folder: URL, gitPath: String = "/usr/bin/git") -> String? {
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path) else { return nil }
        return try? run(gitPath: gitPath, invocation(root: folder, arguments: ["remote", "get-url", "origin"], token: nil))
    }

    /// Clones a repository into a folder that doesn't exist yet. With an author, the clone's own config names
    /// them for every commit Perch makes there. A clone that fails leaves no folder behind.
    public static func clone(_ remote: String, to destination: URL, token: String?, author: (name: String, email: String)?,
                             gitPath: String = "/usr/bin/git") async throws {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: destination.path) else { throw SyncError.failed("\(destination.path) already exists.") }
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await Task.detached {
            do {
                try run(gitPath: gitPath, invocation(root: nil, arguments: ["clone", "--quiet", remote, destination.path], token: token))
                if let author {
                    try run(gitPath: gitPath, invocation(root: destination, arguments: ["config", "user.name", author.name], token: nil))
                    try run(gitPath: gitPath, invocation(root: destination, arguments: ["config", "user.email", author.email], token: nil))
                }
            } catch let SyncError.failed(message) where token != nil && isAuthenticationFailure(message) {
                try? FileManager.default.removeItem(at: destination)
                throw SyncError.authentication
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        }.value
    }
}

public struct GitLogEntry: Identifiable, Equatable, Sendable {
    public var hash: String
    public var author: String
    public var email: String
    public var date: String
    public var subject: String
    public var id: String { hash }
}
#endif
