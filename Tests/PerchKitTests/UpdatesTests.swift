import XCTest
@testable import PerchKit

/// A GitHub that answers "latest release" for someone/perch.
final class ReleasesGitHub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var reply: [String: Any] = [:]
    nonisolated(unsafe) static var lastAuthorization: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.lastAuthorization = request.value(forHTTPHeaderField: "Authorization")
        XCTAssertEqual(request.url?.path, "/repos/someone/perch/releases/latest")
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: Self.reply))
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class UpdatesTests: XCTestCase {
    private var checker: UpdateChecker {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleasesGitHub.self]
        return UpdateChecker(repository: "someone/perch", session: URLSession(configuration: configuration))
    }

    private func release(_ tag: String, assets: [String]) -> [String: Any] {
        ["tag_name": tag, "name": "Perch \(tag)", "body": "- Agent history in the notch\n- Steadier hover",
         "published_at": "2026-11-10T18:00:00Z", "html_url": "https://github.com/someone/perch/releases/tag/\(tag)",
         "assets": assets.enumerated().map { ["name": $1, "url": "https://api.github.com/repos/someone/perch/releases/assets/\($0 + 1)", "size": 1234] }]
    }

    func testVersionsCompareAsNumbersNotText() {
        XCTAssertTrue(Version("0.10.0")! > Version("0.9.9")!)
        XCTAssertEqual(Version("v0.2.0"), Version("0.2.0"))
        XCTAssertTrue(Version("0.2")! < Version("0.2.1")!)
        XCTAssertEqual(Version("0.2"), Version("0.2.0"))
        XCTAssertNil(Version("nightly"))
    }

    func testANewerReleaseIsOfferedWithItsNotesAndMacBuild() async throws {
        ReleasesGitHub.status = 200
        ReleasesGitHub.reply = release("v0.3.0", assets: ["Perch-0.3.0.zip", "checksums.txt"])
        let result = try await checker.check(current: "0.2.0", token: "ghu_a")
        guard case let .available(update) = result else { return XCTFail("expected an update, got \(result)") }
        XCTAssertEqual(update.version, Version("0.3.0"))
        XCTAssertEqual(update.notes, "- Agent history in the notch\n- Steadier hover")
        XCTAssertEqual(update.download, URL(string: "https://api.github.com/repos/someone/perch/releases/assets/1"))
        XCTAssertEqual(ReleasesGitHub.lastAuthorization, "Bearer ghu_a", "a private repository needs the account's token")
    }

    func testTheSameOrAnOlderReleaseIsNothingToDo() async throws {
        ReleasesGitHub.status = 200
        ReleasesGitHub.reply = release("v0.2.0", assets: ["Perch-0.2.0.zip"])
        let same = try await checker.check(current: "0.2.0", token: "ghu_a")
        XCTAssertEqual(same, .upToDate)
        let older = try await checker.check(current: "0.4.1", token: "ghu_a")
        XCTAssertEqual(older, .upToDate)
    }

    func testAReleaseWithoutAMacBuildIsNotOffered() async throws {
        ReleasesGitHub.status = 200
        ReleasesGitHub.reply = release("v0.3.0", assets: ["notes.txt"])
        let result = try await checker.check(current: "0.2.0", token: "ghu_a")
        XCTAssertEqual(result, .upToDate)
    }

    func testWhenGitHubWontShowTheRepositoryItSaysHowToFixIt() async throws {
        ReleasesGitHub.status = 404
        ReleasesGitHub.reply = ["message": "Not Found"]
        let result = try await checker.check(current: "0.2.0", token: "ghu_a")
        XCTAssertEqual(result, .noAccess)
    }

    func testTheChangelogReadsAsReleasesNewestFirst() {
        let markdown = """
        # Changelog

        Everything that changed, newest first.

        ## 0.2.0 (2026-11-10)

        - Agent history in the notch
        - Steadier hover

        ## 0.1.0 (2026-11-09)

        - First build
        """
        let releases = Changelog.parse(markdown)
        XCTAssertEqual(releases.map(\.version), ["0.2.0", "0.1.0"])
        XCTAssertEqual(releases.map(\.date), ["2026-11-10", "2026-11-09"])
        XCTAssertEqual(releases[0].items, ["Agent history in the notch", "Steadier hover"])
        XCTAssertEqual(Changelog.notes(for: "0.2.0", in: markdown), "- Agent history in the notch\n- Steadier hover")
        XCTAssertNil(Changelog.notes(for: "9.9.9", in: markdown))
    }

    #if os(macOS)
    private func makeApp(at url: URL, version: String, bundleID: String = "org.example.perch") throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleShortVersionString": version, "CFBundleExecutable": "Perch"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        try Data("version \(version)".utf8).write(to: contents.appendingPathComponent("MacOS/Perch"))
    }

    private func zip(_ app: URL, to file: URL) throws {
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", app.path, file.path]
        try ditto.run()
        ditto.waitUntilExit()
    }

    func testTheInstallerSwapsTheAppForTheDownloadedOne() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let installed = root.appendingPathComponent("Applications/Perch.app")
        try makeApp(at: installed, version: "0.2.0")
        let built = root.appendingPathComponent("build/Perch.app")
        try makeApp(at: built, version: "0.3.0")
        let download = root.appendingPathComponent("Perch-0.3.0.zip")
        try zip(built, to: download)

        try UpdateInstaller.install(zip: download, replacing: installed, bundleID: "org.example.perch", version: Version("0.3.0")!)
        XCTAssertEqual(try String(contentsOf: installed.appendingPathComponent("Contents/MacOS/Perch"), encoding: .utf8), "version 0.3.0")
    }

    func testTheInstallerRefusesAnythingThatIsntThisVersionOfPerch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let installed = root.appendingPathComponent("Applications/Perch.app")
        try makeApp(at: installed, version: "0.2.0")
        let other = root.appendingPathComponent("build/Perch.app")
        try makeApp(at: other, version: "0.3.0", bundleID: "com.example.notperch")
        let download = root.appendingPathComponent("Other.zip")
        try zip(other, to: download)

        XCTAssertThrowsError(try UpdateInstaller.install(zip: download, replacing: installed, bundleID: "org.example.perch", version: Version("0.3.0")!))
        XCTAssertEqual(try String(contentsOf: installed.appendingPathComponent("Contents/MacOS/Perch"), encoding: .utf8), "version 0.2.0", "left as it was")
    }
    #endif
}
