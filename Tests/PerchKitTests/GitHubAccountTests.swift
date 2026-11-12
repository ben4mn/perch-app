import XCTest
@testable import PerchKit

/// A GitHub that answers the account calls: who you are, which repositories Perch can reach, and token refreshes.
final class AccountGitHub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let path = request.url!.path
        Self.requests.append(path)
        if request.value(forHTTPHeaderField: "Authorization") == "Bearer ghu_revoked" {
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(#"{"message":"Bad credentials"}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let reply: [String: Any]
        switch path {
        case "/login/oauth/access_token":
            reply = ["access_token": "ghu_new", "refresh_token": "ghr_new", "expires_in": 28800, "token_type": "bearer"]
        case "/user":
            reply = ["login": "alexdoe", "id": 42, "name": "Alex Doe"]
        case "/user/installations":
            reply = ["installations": [["id": 7, "app_slug": "perch-notes"]]]
        case "/user/installations/7/repositories":
            reply = ["repositories": [["full_name": "alexdoe/perch"], ["full_name": "alexdoe/Alex-Notes"]]]
        default:
            fatalError("Unexpected request \(path)")
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: reply))
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// A secret store that counts what it is asked, and can refuse a read as the Keychain does when the user chooses Deny.
final class CountingSecretStore: SecretStore, @unchecked Sendable {
    private let inner = MemorySecretStore()
    private let lock = NSLock()
    private var counts = (reads: 0, saves: 0, deletes: 0)
    private var refusing = false

    var reads: Int { lock.withLock { counts.reads } }
    var writes: Int { lock.withLock { counts.saves + counts.deletes } }
    func refuse(_ refuse: Bool) { lock.withLock { refusing = refuse } }
    func put(_ data: Data, for key: String) { inner.save(data, for: key) }

    func read(_ key: String) -> SecretRead {
        let refused = lock.withLock { counts.reads += 1; return refusing }
        return refused ? .refused : inner.read(key)
    }

    func load(_ key: String) -> Data? {
        if case let .found(data) = read(key) { return data }
        return nil
    }

    func save(_ data: Data, for key: String) {
        lock.withLock { counts.saves += 1 }
        inner.save(data, for: key)
    }

    func delete(_ key: String) {
        lock.withLock { counts.deletes += 1 }
        inner.delete(key)
    }
}

final class GitHubAccountTests: XCTestCase {
    private var store: MemorySecretStore!

    override func setUp() {
        AccountGitHub.requests = []
        store = MemorySecretStore()
    }

    private var signIn: GitHubDeviceSignIn {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountGitHub.self]
        return GitHubDeviceSignIn(clientID: "Iv-test", session: URLSession(configuration: configuration))
    }

    private func token(_ access: String, expiresIn seconds: TimeInterval?) -> GitHubDeviceSignIn.Token {
        GitHubDeviceSignIn.Token(accessToken: access, refreshToken: "ghr_old", expiresAt: seconds.map { Date().addingTimeInterval($0) })
    }

    func testCommitsUseTheAccountsNoReplyAddress() {
        let account = GitHubAccount(login: "alexdoe", id: 42, name: "Alex Doe", token: token("t", expiresIn: nil))
        XCTAssertEqual(account.commitName, "Alex Doe")
        XCTAssertEqual(account.commitEmail, "42+alexdoe@users.noreply.github.com")
        let unnamed = GitHubAccount(login: "alexdoe", id: 42, name: "", token: token("t", expiresIn: nil))
        XCTAssertEqual(unnamed.commitName, "alexdoe")
    }

    func testSigningInReadsWhoYouAreAndRemembersIt() async throws {
        let session = GitHubSession(signIn: signIn, store: store)
        let account = try await session.signedIn(with: token("ghu_a", expiresIn: 3600))
        XCTAssertEqual(account.login, "alexdoe")
        XCTAssertEqual(account.id, 42)
        XCTAssertEqual(account.token.accessToken, "ghu_a")
        // A new launch finds the same account without signing in again.
        let again = GitHubSession(signIn: signIn, store: store)
        let remembered = await again.account
        XCTAssertEqual(remembered, account)
    }

    func testAnExpiringTokenIsRefreshedOnceAndSaved() async throws {
        let session = GitHubSession(signIn: signIn, store: store)
        _ = try await session.signedIn(with: token("ghu_old", expiresIn: 60))
        AccountGitHub.requests = []
        let first = try await session.accessToken()
        let second = try await session.accessToken()
        XCTAssertEqual(first, "ghu_new")
        XCTAssertEqual(second, "ghu_new")
        XCTAssertEqual(AccountGitHub.requests, ["/login/oauth/access_token"], "one refresh, then the new token is used")
        let reloaded = await GitHubSession(signIn: signIn, store: store).account
        XCTAssertEqual(reloaded?.token.accessToken, "ghu_new")
        XCTAssertEqual(reloaded?.token.refreshToken, "ghr_new")
    }

    func testCallersArrivingDuringARenewalShareIt() async throws {
        let session = GitHubSession(signIn: signIn, store: store)
        _ = try await session.signedIn(with: token("ghu_old", expiresIn: 60))
        AccountGitHub.requests = []
        async let sync = session.accessToken()
        async let updates = session.accessToken()
        let (first, second) = try await (sync, updates)
        XCTAssertEqual(first, "ghu_new")
        XCTAssertEqual(second, "ghu_new")
        XCTAssertEqual(AccountGitHub.requests, ["/login/oauth/access_token"], "GitHub takes a refresh token once, so one renewal")
    }

    func testATokenWithTimeLeftOrNoExpiryIsUsedAsItIs() async throws {
        let session = GitHubSession(signIn: signIn, store: store)
        _ = try await session.signedIn(with: token("ghu_fresh", expiresIn: 7200))
        AccountGitHub.requests = []
        let fresh = try await session.accessToken()
        XCTAssertEqual(fresh, "ghu_fresh")
        _ = try await session.signedIn(with: token("ghu_forever", expiresIn: nil))
        AccountGitHub.requests = []
        let forever = try await session.accessToken()
        XCTAssertEqual(forever, "ghu_forever")
        XCTAssertEqual(AccountGitHub.requests, [])
    }

    func testSigningOutForgetsTheAccount() async throws {
        let session = GitHubSession(signIn: signIn, store: store)
        _ = try await session.signedIn(with: token("ghu_a", expiresIn: nil))
        await session.signOut()
        let account = await session.account
        XCTAssertNil(account)
        XCTAssertNil(store.load(GitHubSession.storeKey))
        do {
            _ = try await session.accessToken()
            XCTFail("signed out, so there is no token")
        } catch {
            XCTAssertEqual(error as? SyncError, .authentication)
        }
    }

    func testTheSessionReadsItsStoreOnlyWhenSomethingNeedsTheAccount() async throws {
        let counting = CountingSecretStore()
        let saved = GitHubAccount(login: "alexdoe", id: 42, name: nil, token: token("ghu_fresh", expiresIn: 7200))
        counting.put(try JSONEncoder().encode(saved), for: GitHubSession.storeKey)
        let session = GitHubSession(signIn: signIn, store: counting)
        XCTAssertEqual(counting.reads, 0, "making the session reads nothing")
        let first = try await session.accessToken()
        let second = try await session.accessToken()
        let account = await session.account
        XCTAssertEqual(first, "ghu_fresh")
        XCTAssertEqual(second, "ghu_fresh")
        XCTAssertEqual(account, saved)
        XCTAssertEqual(counting.reads, 1)
    }

    func testARefusedReadIsNotSignedOut() async throws {
        let counting = CountingSecretStore()
        let saved = GitHubAccount(login: "alexdoe", id: 42, name: nil, token: token("ghu_fresh", expiresIn: 7200))
        counting.put(try JSONEncoder().encode(saved), for: GitHubSession.storeKey)
        counting.refuse(true)
        let session = GitHubSession(signIn: signIn, store: counting)
        do {
            _ = try await session.accessToken()
            XCTFail("the Keychain said no")
        } catch {
            XCTAssertEqual(error as? SyncError, .keychainRefused, "not the same as GitHub turning the token down")
        }
        XCTAssertEqual(counting.writes, 0, "nothing is deleted or written over")
        // The session doesn't decide it is signed out: once the store hands the account over, it is there.
        counting.refuse(false)
        let token = try await session.accessToken()
        XCTAssertEqual(token, "ghu_fresh")
    }

    func testReachListsRepositoriesAndTheLinkToAddMore() async throws {
        let reach = try await signIn.reach(token: "ghu_a")
        XCTAssertEqual(reach.repositories, ["alexdoe/Alex-Notes", "alexdoe/perch"])
        XCTAssertEqual(reach.appSlug, "perch-notes")
        XCTAssertEqual(reach.installURL, URL(string: "https://github.com/apps/perch-notes/installations/new"))
    }

    func testARevokedTokenSaysSoRatherThanListingNothing() async throws {
        do {
            _ = try await signIn.reach(token: "ghu_revoked")
            XCTFail("GitHub turned the token down")
        } catch {
            XCTAssertEqual(error as? SyncError, .authentication)
        }
        do {
            _ = try await signIn.user(token: "ghu_revoked")
            XCTFail("GitHub turned the token down")
        } catch {
            XCTAssertEqual(error as? SyncError, .authentication)
        }
    }

    func testRepositoryNamesAreReadFromEveryKindOfGitHubAddress() {
        XCTAssertEqual(GitHubNotebook.fullName(fromRemote: "https://github.com/alexdoe/Alex-Notes.git"), "alexdoe/Alex-Notes")
        XCTAssertEqual(GitHubNotebook.fullName(fromRemote: "https://github.com/alexdoe/Alex-Notes"), "alexdoe/Alex-Notes")
        XCTAssertEqual(GitHubNotebook.fullName(fromRemote: "https://github.com/alexdoe/Alex-Notes/"), "alexdoe/Alex-Notes")
        XCTAssertEqual(GitHubNotebook.fullName(fromRemote: "https://x-access-token@github.com/alexdoe/Alex-Notes.git"), "alexdoe/Alex-Notes")
        XCTAssertEqual(GitHubNotebook.fullName(fromRemote: "git@github.com:alexdoe/Alex-Notes.git"), "alexdoe/Alex-Notes")
        XCTAssertEqual(GitHubNotebook.fullName(fromRemote: "ssh://git@github.com/alexdoe/Alex-Notes.git"), "alexdoe/Alex-Notes")
        XCTAssertNil(GitHubNotebook.fullName(fromRemote: "https://github.example-corp.com/someone/repo.git"))
        XCTAssertNil(GitHubNotebook.fullName(fromRemote: "/tmp/remote.git"))
        XCTAssertEqual(GitHubNotebook.remoteURL(for: "alexdoe/Alex-Notes"), "https://github.com/alexdoe/Alex-Notes.git")
    }
}

#if os(macOS)
final class GitHubNotebookTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // A remote with one commit on main, as a GitHub repository has.
        try shell("git init -q --bare -b main remote.git && git clone -q remote.git seed 2>/dev/null && git -C seed -c user.name=T -c user.email=t@example.com commit -q --allow-empty -m init && git -C seed push -q origin HEAD:main")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    private func shell(_ command: String, environment: [String: String]? = nil, input: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = root
        if let environment { process.environment = environment }
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        let inputPipe = Pipe()
        process.standardInput = inputPipe
        try process.run()
        if let input { inputPipe.fileHandleForWriting.write(Data(input.utf8)) }
        try inputPipe.fileHandleForWriting.close()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testANewRepositoryIsClonedBesideOtherFoldersNeverIntoThem() throws {
        let parent = root.appendingPathComponent("Perch")
        XCTAssertEqual(GitHubNotebook.placement(for: "alexdoe/Alex-Notes", in: parent), .clone(parent.appendingPathComponent("Alex-Notes")))
        // A folder of the same name that isn't this repository is left alone.
        try FileManager.default.createDirectory(at: parent.appendingPathComponent("Alex-Notes"), withIntermediateDirectories: true)
        XCTAssertEqual(GitHubNotebook.placement(for: "alexdoe/Alex-Notes", in: parent), .clone(parent.appendingPathComponent("Alex-Notes 2")))
    }

    func testAnExistingCloneOfTheSameRepositoryIsOpenedAsItIs() throws {
        let parent = root.appendingPathComponent("Perch")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try shell("git clone -q remote.git Perch/Alex-Notes 2>/dev/null && git -C Perch/Alex-Notes remote set-url origin https://github.com/ALEXDOE/alex-notes.git")
        XCTAssertEqual(GitHubNotebook.placement(for: "alexdoe/Alex-Notes", in: parent), .open(parent.appendingPathComponent("Alex-Notes")))
    }

    func testTheTokenReachesGitOnlyThroughTheEnvironment() throws {
        // Some other GitHub login is already saved for git, as the Mac's keychain helper would have.
        let globalConfig = root.appendingPathComponent("gitconfig")
        try "[credential]\n\thelper = \"!f() { echo username=someone-else; echo password=wrong; }; f\"\n".write(to: globalConfig, atomically: true, encoding: .utf8)
        let ask = "protocol=https\nhost=github.com\npath=alexdoe/Alex-Notes.git\n\n"
        func fill(token: String?) throws -> (arguments: [String], output: String) {
            let call = GitCLISync.invocation(root: root, arguments: ["credential", "fill"], token: token)
            var environment = call.environment
            environment["GIT_CONFIG_GLOBAL"] = globalConfig.path
            environment["GIT_CONFIG_NOSYSTEM"] = "1"
            let command = (["/usr/bin/git"] + call.arguments).map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
            return (call.arguments, try shell(command, environment: environment, input: ask))
        }

        let signedIn = try fill(token: "ghu_secret")
        XCTAssertFalse(signedIn.arguments.joined(separator: " ").contains("ghu_secret"), "never in the command line")
        XCTAssertTrue(signedIn.output.contains("password=ghu_secret"), signedIn.output)
        XCTAssertTrue(signedIn.output.contains("username=x-access-token"), signedIn.output)
        XCTAssertFalse(signedIn.output.contains("wrong"), "the other login is not asked")

        let signedOut = try fill(token: nil)
        XCTAssertTrue(signedOut.output.contains("password=wrong"), "without a token, git's own login is used as before")
        XCTAssertNil(GitCLISync.invocation(root: root, arguments: ["status"], token: nil).environment["PERCH_GIT_TOKEN"])
    }

    func testACloneCommitsAsTheAccountAndKeepsTheTokenOutOfTheRepository() async throws {
        let destination = root.appendingPathComponent("Perch/Alex-Notes")
        try await GitCLISync.clone(root.appendingPathComponent("remote.git").path, to: destination, token: "ghu_secret",
                                   author: (name: "Alex Doe", email: "42+alexdoe@users.noreply.github.com"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent(".git").path))
        let config = try String(contentsOf: destination.appendingPathComponent(".git/config"), encoding: .utf8)
        XCTAssertFalse(config.contains("ghu_secret"))
        XCTAssertEqual(try shell("git -C Perch/Alex-Notes config user.email"), "42+alexdoe@users.noreply.github.com")

        try Vault(root: destination).write("hello\n", to: "Note.md")
        _ = try await GitCLISync(root: destination, token: { "ghu_secret" }).sync()
        XCTAssertEqual(try shell("git -C remote.git log -1 --format='%an <%ae>' main"), "Alex Doe <42+alexdoe@users.noreply.github.com>")
    }

    func testAFailedCloneLeavesNothingBehind() async throws {
        let destination = root.appendingPathComponent("Perch/Missing")
        do {
            try await GitCLISync.clone(root.appendingPathComponent("no-such-remote.git").path, to: destination, token: nil, author: nil)
            XCTFail("the remote doesn't exist")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
}
#endif
