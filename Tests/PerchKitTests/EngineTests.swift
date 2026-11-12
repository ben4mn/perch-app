import XCTest
@testable import PerchKit

final class TodoistImportTests: XCTestCase {
    private func snapshot() throws -> TodoistSnapshot {
        let url = try XCTUnwrap(Bundle.module.resourceURL).appendingPathComponent("Fixtures/todoist-snapshot.json")
        return try JSONDecoder().decode(TodoistSnapshot.self, from: Data(contentsOf: url))
    }

    /// What the import screen passes: the notebook's areas and the person importing.
    private let options = TodoistImportOptions(
        areas: ["✈️ Acme", "Personal"], ownerLabels: ["alex", "claude", "pair"], ownerID: "alex",
        agentCommentPrefixes: ["helperbot": "helperbot"]
    )

    func testMapping() throws {
        let plan = TodoistMapper.plan(snapshot: try snapshot(), options: options)
        XCTAssertEqual(plan.summary.open, 6)
        XCTAssertEqual(plan.summary.completed, 1)
        XCTAssertEqual(plan.summary.subtasks, 1)
        XCTAssertEqual(plan.summary.comments, 4)
        XCTAssertEqual(plan.summary.repeating, 2)
        XCTAssertEqual(plan.summary.byArea, ["✈️ Acme": 3, "Personal": 4])
        XCTAssertFalse(plan.tasks.contains { $0.title == "Deleted thing" })

        let main = try XCTUnwrap(plan.tasks.first { $0.sourceID == "todoist:100" })
        XCTAssertEqual(main.area, "✈️ Acme", "a project named like an area goes to it")
        XCTAssertEqual(main.priority, 2, "Todoist API priority 3 is P2")
        XCTAssertEqual(main.owner, "alex")
        XCTAssertEqual(main.due, "2026-10-13")
        XCTAssertTrue(main.labels.contains("section/This quarter"))
        XCTAssertEqual(main.activity.map(\.author), ["helperbot", "triage-routine", "alex", "triage-routine"])
        XCTAssertTrue(main.activity[2].text.contains("a.pdf"))
        XCTAssertEqual(plan.tasks.first { $0.title == "Inbox thing" }?.owner, "alex")
        XCTAssertFalse(main.path.contains(":"))

        let sub = try XCTUnwrap(plan.tasks.first { $0.sourceID == "todoist:101" })
        XCTAssertEqual(sub.parent, main.id)
        XCTAssertEqual(sub.owner, "pair")
        XCTAssertEqual(sub.priority, 4)

        let water = try XCTUnwrap(plan.tasks.first { $0.title == "Water the tomatoes" })
        XCTAssertEqual(water.area, "Personal")
        XCTAssertEqual(water.priority, 1)
        XCTAssertEqual(water.time, "09:30")
        XCTAssertEqual(water.recurrence, "every day")
        XCTAssertTrue(water.labels.contains("garden"), "a project with no area of its own folds into Personal as a label")
        XCTAssertEqual(water.remind, ["2026-11-08T09:00", "-30m"])

        XCTAssertEqual(plan.tasks.first { $0.title == "Consulting thing" }?.labels, ["consulting"])
        XCTAssertTrue(plan.warnings.contains { $0.contains("every 3rd friday") })
        XCTAssertEqual(plan.tasks.first { $0.title == "Finished thing" }?.status, .done)
    }

    func testWithNoKnownAreasEveryProjectFoldsIntoTheFallback() throws {
        let plan = TodoistMapper.plan(snapshot: try snapshot())
        XCTAssertEqual(plan.summary.byArea, ["Personal": 7])
        let main = try XCTUnwrap(plan.tasks.first { $0.sourceID == "todoist:100" })
        XCTAssertTrue(main.labels.contains("acme"), "the project stays findable")
        XCTAssertEqual(main.activity.map(\.author), ["me", "triage-routine", "me", "triage-routine"], "no agent prefixes are assumed")
    }

    func testApplyWritesReadableFilesAndRerunIsSafe() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = Vault(root: root)
        let plan = TodoistMapper.plan(snapshot: try snapshot())
        XCTAssertEqual(try TodoistMapper.apply(plan, to: vault), 7)

        let store = TaskStore(vault: vault)
        let loaded = store.loadAll()
        XCTAssertEqual(loaded.count, 7)
        let original = try XCTUnwrap(plan.tasks.first { $0.sourceID == "todoist:100" })
        let read = try XCTUnwrap(loaded.first { $0.id == original.id })
        XCTAssertEqual(read.details, original.details)
        XCTAssertEqual(read.activity, original.activity)
        XCTAssertEqual(read.title, original.title)

        let second = TodoistMapper.plan(snapshot: try snapshot(), existing: loaded)
        XCTAssertEqual(second.tasks.count, 0)
        XCTAssertEqual(second.summary.alreadyImported, 7)
        XCTAssertTrue(try VaultVerifier.verify(vault).passed)
    }
}

final class ConflictTests: XCTestCase {
    func testGitMarkersBecomeBlocks() {
        let text = "before\n<<<<<<< HEAD\nmine\n||||||| base\nold\n=======\ntheirs\n>>>>>>> origin/main\nafter\n"
        let converted = ConflictBlocks.fromGitMarkers(text)
        XCTAssertTrue(converted.contains(":::conflict{variant=a}\ntheirs\n:::"))
        XCTAssertTrue(converted.contains(":::conflict{variant=d}\nmine\n:::"))
        XCTAssertTrue(converted.hasPrefix("before\n"))
        XCTAssertTrue(converted.hasSuffix("after\n"))
        XCTAssertFalse(converted.contains("<<<<<<<"))
    }

    func testResolveKeepsChosenVariant() {
        let text = "top\n\n" + ConflictBlocks.wrap(remote: "theirs", local: "mine") + "\nmiddle\n\n" + ConflictBlocks.wrap(remote: "t2", local: "m2")
        let resolved = ConflictBlocks.resolve(text, blockIndex: 1, variant: "d")
        XCTAssertTrue(resolved.contains("top\n\nmine\n"))
        XCTAssertFalse(resolved.contains("theirs"))
        XCTAssertTrue(resolved.contains(":::conflict{variant=a}\nt2"))
        let final = ConflictBlocks.resolve(resolved, blockIndex: 0, variant: "a")
        XCTAssertFalse(ConflictBlocks.contains(final))
        XCTAssertTrue(final.contains("t2"))
        XCTAssertFalse(final.contains("m2"))
    }
}

#if os(macOS)
final class GitCLISyncTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try shell("git init -q --bare -b main remote.git")
        try shell("git clone -q remote.git a 2>/dev/null")
        try shell("git clone -q remote.git b 2>/dev/null")
        for clone in ["a", "b"] {
            try shell("git -C \(clone) config user.name Test && git -C \(clone) config user.email t@example.com && git -C \(clone) checkout -q -b main 2>/dev/null || true")
        }
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func shell(_ command: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = root
        try process.run()
        process.waitUntilExit()
    }

    private func vault(_ name: String) -> Vault { Vault(root: root.appendingPathComponent(name)) }
    private func engine(_ name: String) -> GitCLISync { GitCLISync(root: root.appendingPathComponent(name)) }

    func testTwoDevicesSyncAndConflictsKeepBothVersions() async throws {
        try vault("a").write("line one\n", to: "Note.md")
        _ = try await engine("a").sync()
        _ = try await engine("b").sync()
        XCTAssertEqual(try vault("b").read("Note.md"), "line one\n")

        // Separate files merge cleanly.
        try vault("a").write("a", to: "FromA.md")
        try vault("b").write("b", to: "FromB.md")
        _ = try await engine("a").sync()
        _ = try await engine("b").sync()
        _ = try await engine("a").sync()
        XCTAssertTrue(vault("a").exists("FromB.md"))
        XCTAssertTrue(vault("b").exists("FromA.md"))

        // The same line changed on both devices.
        try vault("a").write("from a\n", to: "Note.md")
        try vault("b").write("from b\n", to: "Note.md")
        _ = try await engine("a").sync()
        let result = try await engine("b").sync()
        XCTAssertEqual(result.conflicts, ["Note.md"])
        let merged = try vault("b").read("Note.md")
        XCTAssertTrue(merged.contains(":::conflict{variant=a}\nfrom a\n:::"))
        XCTAssertTrue(merged.contains(":::conflict{variant=d}\nfrom b\n:::"))
        _ = try await engine("a").sync()
        XCTAssertEqual(try vault("a").read("Note.md"), merged)
    }

    func testBoardConflictKeepsACopy() async throws {
        try vault("a").write("## L\n- One  ", to: "B.kanban.md")
        _ = try await engine("a").sync()
        _ = try await engine("b").sync()
        try vault("a").write("## L\n- From A  ", to: "B.kanban.md")
        try vault("b").write("## L\n- From B  ", to: "B.kanban.md")
        _ = try await engine("a").sync()
        let result = try await engine("b").sync()
        XCTAssertEqual(result.conflicts, ["B.kanban.md"])
        XCTAssertEqual(try vault("b").read("B.kanban.md"), "## L\n- From A  ")
        let copies = try vault("b").scan().filter { $0.name.contains("conflict") }
        XCTAssertEqual(copies.count, 1)
        XCTAssertEqual(copies[0].kind, .board)
        XCTAssertEqual(try vault("b").read(copies[0].path), "## L\n- From B  ")
    }
}
#endif

/// A tiny in-memory GitHub for the REST sync engine.
final class FakeGitHub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var blobs: [String: Data] = [:]
    nonisolated(unsafe) static var trees: [String: [String: String]] = [:]
    nonisolated(unsafe) static var commits: [String: (tree: String, parents: [String])] = [:]
    nonisolated(unsafe) static var head = ""
    nonisolated(unsafe) static var counter = 0

    static func reset(files: [String: String]) {
        blobs = [:]; trees = [:]; commits = [:]; counter = 0
        var tree: [String: String] = [:]
        for (path, text) in files {
            let data = Data(text.utf8)
            let sha = GitHubAPISync.blobID(data)
            blobs[sha] = data
            tree[path] = sha
        }
        trees["tree0"] = tree
        commits["commit0"] = ("tree0", [])
        head = "commit0"
    }

    static func commit(files: [String: String?]) {
        var tree = trees[commits[head]!.tree]!
        for (path, text) in files {
            if let text {
                let data = Data(text.utf8)
                let sha = GitHubAPISync.blobID(data)
                blobs[sha] = data
                tree[path] = sha
            } else {
                tree[path] = nil
            }
        }
        counter += 1
        trees["t\(counter)"] = tree
        commits["c\(counter)"] = ("t\(counter)", [head])
        head = "c\(counter)"
    }

    static var headFiles: [String: String] {
        trees[commits[head]!.tree]!.mapValues { String(decoding: blobs[$0]!, as: UTF8.self) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let path = request.url!.path.replacingOccurrences(of: "/repos/o/r/git/", with: "")
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
            body = data
        }
        let json = body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        var reply: Any = [:]
        switch (request.httpMethod ?? "GET", path) {
        case ("GET", "ref/heads/main"):
            reply = ["object": ["sha": Self.head]]
        case let ("GET", p) where p.hasPrefix("commits/"):
            reply = ["tree": ["sha": Self.commits[String(p.dropFirst(8))]!.tree]]
        case let ("GET", p) where p.hasPrefix("trees/"):
            let tree = Self.trees[String(p.dropFirst(6))]!
            reply = ["truncated": false, "tree": tree.map { ["path": $0.key, "type": "blob", "sha": $0.value] }]
        case let ("GET", p) where p.hasPrefix("blobs/"):
            reply = ["encoding": "base64", "content": Self.blobs[String(p.dropFirst(6))]!.base64EncodedString()]
        case ("POST", "blobs"):
            let data = Data(base64Encoded: json!["content"] as! String)!
            let sha = GitHubAPISync.blobID(data)
            Self.blobs[sha] = data
            reply = ["sha": sha]
        case ("POST", "trees"):
            var tree = Self.trees[json!["base_tree"] as! String]!
            for entry in json!["tree"] as! [[String: Any]] {
                tree[entry["path"] as! String] = entry["sha"] as? String
            }
            Self.counter += 1
            Self.trees["t\(Self.counter)"] = tree
            reply = ["sha": "t\(Self.counter)"]
        case ("POST", "commits"):
            Self.counter += 1
            Self.commits["c\(Self.counter)"] = (json!["tree"] as! String, json!["parents"] as! [String])
            reply = ["sha": "c\(Self.counter)"]
        case ("PATCH", "refs/heads/main"):
            Self.head = json!["sha"] as! String
        default:
            fatalError("Unexpected request \(path)")
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: reply))
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class GitHubAPISyncTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func engine() -> GitHubAPISync {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeGitHub.self]
        return GitHubAPISync(
            configuration: .init(owner: "o", repository: "r"),
            token: "x",
            root: root.appendingPathComponent("vault"),
            stateURL: root.appendingPathComponent("state.json"),
            session: URLSession(configuration: configuration)
        )
    }

    private var vault: Vault { Vault(root: root.appendingPathComponent("vault")) }

    func testBlobIDMatchesGit() {
        XCTAssertEqual(GitHubAPISync.blobID(Data("hello\n".utf8)), "ce013625030ba8dba906f756967f9e9ca394464a")
    }

    func testPullPushDeleteAndConflict() async throws {
        FakeGitHub.reset(files: ["A.md": "a", "Folder/B.md": "b", "Gone.md": "x", "Board.kanban.md": "## L"])
        var result = try await engine().sync()
        XCTAssertEqual(result.pulled, 4)
        XCTAssertEqual(try vault.read("Folder/B.md"), "b")

        // Nothing changed, so nothing moves.
        let quietHead = FakeGitHub.head
        result = try await engine().sync()
        XCTAssertEqual(result, SyncResult())
        XCTAssertEqual(FakeGitHub.head, quietHead)

        // Local changes go up.
        try vault.write("edited", to: "A.md")
        try vault.write("new", to: "New.md")
        try vault.delete("Gone.md")
        result = try await engine().sync()
        XCTAssertEqual(result.pushed, 3)
        XCTAssertEqual(FakeGitHub.headFiles["A.md"], "edited")
        XCTAssertEqual(FakeGitHub.headFiles["New.md"], "new")
        XCTAssertNil(FakeGitHub.headFiles["Gone.md"])

        // Remote changes come down.
        FakeGitHub.commit(files: ["Remote.md": "r", "New.md": nil])
        result = try await engine().sync()
        XCTAssertEqual(result.pulled, 2)
        XCTAssertEqual(try vault.read("Remote.md"), "r")
        XCTAssertFalse(vault.exists("New.md"))

        // Both sides edit a note: conflict blocks, on both sides.
        FakeGitHub.commit(files: ["A.md": "theirs"])
        try vault.write("mine", to: "A.md")
        result = try await engine().sync()
        XCTAssertEqual(result.conflicts, ["A.md"])
        let merged = try vault.read("A.md")
        XCTAssertTrue(merged.contains(":::conflict{variant=a}\ntheirs\n:::"))
        XCTAssertTrue(merged.contains(":::conflict{variant=d}\nmine\n:::"))
        XCTAssertEqual(FakeGitHub.headFiles["A.md"], merged)

        // Both sides edit a board: the incoming one stays, this device's becomes a copy.
        FakeGitHub.commit(files: ["Board.kanban.md": "## Theirs"])
        try vault.write("## Mine", to: "Board.kanban.md")
        result = try await engine().sync()
        XCTAssertEqual(try vault.read("Board.kanban.md"), "## Theirs")
        XCTAssertEqual(FakeGitHub.headFiles["Board.kanban.md"], "## Theirs")
        let copy = try XCTUnwrap(FakeGitHub.headFiles.keys.first { $0.contains("(conflict") })
        XCTAssertTrue(copy.hasSuffix(".kanban.md"))
        XCTAssertEqual(FakeGitHub.headFiles[copy], "## Mine")

        // Settled state stays settled.
        let settled = FakeGitHub.head
        result = try await engine().sync()
        XCTAssertEqual(result, SyncResult())
        XCTAssertEqual(FakeGitHub.head, settled)
    }
}

/// A GitHub that drops the first two polls, like iOS does while the app is in the background.
final class FlakyGitHub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var polls = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let path = request.url!.path
        var reply: [String: Any] = [:]
        if path == "/login/device/code" {
            reply = ["device_code": "dc", "user_code": "ABCD-1234", "verification_uri": "https://github.com/login/device", "interval": 1, "expires_in": 60]
        } else if path == "/login/oauth/access_token" {
            Self.polls += 1
            if Self.polls <= 2 {
                client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
                return
            }
            reply = Self.polls == 3 ? ["error": "authorization_pending"] : ["access_token": "ghu_test", "token_type": "bearer"]
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: reply))
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class DeviceSignInTests: XCTestCase {
    func testSurvivesDroppedConnectionsWhileApproving() async throws {
        FlakyGitHub.polls = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FlakyGitHub.self]
        let signIn = GitHubDeviceSignIn(clientID: "Iv-test", session: URLSession(configuration: configuration))
        let code = try await signIn.start()
        XCTAssertEqual(code.userCode, "ABCD-1234")
        let token = try await signIn.waitForApproval(code)
        XCTAssertEqual(token.accessToken, "ghu_test")
        XCTAssertEqual(FlakyGitHub.polls, 4)
    }
}
