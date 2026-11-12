import Foundation
@testable import PerchKit
import XCTest

/// The values a build of Perch is set up with (Config/Perch.xcconfig, and Config/Private.xcconfig when it is
/// there) and the decisions that follow from them. A build without the private file has no GitHub sign-in and
/// no update checks, and must still open a notebook.
final class BuildConfigurationTests: XCTestCase {
    /// An Info.plist as the owner's build fills it, with invented values.
    private let ownerInfo: [String: Any] = [
        "CFBundleIdentifier": "org.example.perch",
        PerchConfiguration.Key.gitHubClientID: "Iv1.example",
        PerchConfiguration.Key.updateRepository: "someone/perch",
        PerchConfiguration.Key.keychainService: "org.example.perch",
        PerchConfiguration.Key.standardAreas: "✈️ Acme, Personal",
        PerchConfiguration.Key.preferredNotebook: "Notes",
        PerchConfiguration.Key.ownerID: "alex",
        PerchConfiguration.Key.otherOwners: "pair, claude, robin",
        PerchConfiguration.Key.agentMarks: "claude=claude, robin=house",
        PerchConfiguration.Key.defaultRepositoryOwner: "alex-notes",
    ]

    func testNothingSetIsThePublicBuild() {
        let configuration = PerchConfiguration(info: [:])
        XCTAssertEqual(configuration.gitHubClientID, "")
        XCTAssertEqual(configuration.updateRepository, "")
        XCTAssertEqual(configuration.standardAreas, ["Personal"])
        XCTAssertEqual(configuration.preferredNotebook, "")
        XCTAssertEqual(configuration.ownerID, "me")
        XCTAssertEqual(configuration.otherOwners, ["pair", "claude"])
        XCTAssertEqual(configuration.agentMarks, ["claude": .claude])
        XCTAssertEqual(configuration.defaultRepositoryOwner, "")
        XCTAssertFalse(configuration.signsInWithGitHub)
        XCTAssertFalse(configuration.checksForUpdates)
        XCTAssertEqual(PerchConfiguration.neutral, configuration)
    }

    func testTheOwnersBuildReadsEveryValue() {
        let configuration = PerchConfiguration(info: ownerInfo)
        XCTAssertEqual(configuration.gitHubClientID, "Iv1.example")
        XCTAssertEqual(configuration.updateRepository, "someone/perch")
        XCTAssertEqual(configuration.keychainService, "org.example.perch")
        XCTAssertEqual(configuration.standardAreas, ["✈️ Acme", "Personal"], "the emoji survives, spaces around commas go")
        XCTAssertEqual(configuration.preferredNotebook, "Notes")
        XCTAssertEqual(configuration.ownerID, "alex")
        XCTAssertEqual(configuration.otherOwners, ["pair", "claude", "robin"])
        XCTAssertEqual(configuration.agentMarks, ["claude": .claude, "robin": .house])
        XCTAssertEqual(configuration.defaultRepositoryOwner, "alex-notes")
        XCTAssertTrue(configuration.signsInWithGitHub)
        XCTAssertTrue(configuration.checksForUpdates)
    }

    func testEmptyUnexpandedAndMalformedValuesAreOff() {
        let configuration = PerchConfiguration(info: [
            PerchConfiguration.Key.gitHubClientID: "$(PERCH_GITHUB_CLIENT_ID)",
            PerchConfiguration.Key.updateRepository: "not a repository",
            PerchConfiguration.Key.standardAreas: " , ",
            PerchConfiguration.Key.ownerID: "  ",
            PerchConfiguration.Key.otherOwners: "",
            PerchConfiguration.Key.agentMarks: "claude=sparkle, =house, robin, pip=dot",
            PerchConfiguration.Key.defaultRepositoryOwner: "$(PERCH_DEFAULT_REPOSITORY_OWNER)",
        ])
        XCTAssertEqual(configuration.gitHubClientID, "", "a build setting the build didn't set")
        XCTAssertEqual(configuration.updateRepository, "", "only owner/name")
        XCTAssertEqual(configuration.standardAreas, ["Personal"])
        XCTAssertEqual(configuration.ownerID, "me")
        XCTAssertEqual(configuration.otherOwners, [])
        XCTAssertEqual(configuration.agentMarks, ["pip": .dot], "an unknown mark, no name or no mark is left out")
        XCTAssertEqual(configuration.defaultRepositoryOwner, "")
        XCTAssertEqual(PerchConfiguration(info: [PerchConfiguration.Key.agentMarks: ""]).agentMarks, [:], "empty: no agent has a mark")
        XCTAssertFalse(PerchConfiguration(info: [PerchConfiguration.Key.updateRepository: "a/b/c"]).checksForUpdates)
    }

    func testTheKeychainServiceFallsBackToTheBundleIdentifier() {
        XCTAssertEqual(PerchConfiguration(info: ["CFBundleIdentifier": "com.example.perch"]).keychainService, "com.example.perch")
        XCTAssertEqual(PerchConfiguration(info: [:]).keychainService, "perch")
    }

    func testUpdatesNeedTheSignInToo() {
        // Releases are read with the GitHub sign-in, so a repository alone checks nothing.
        var info = ownerInfo
        info[PerchConfiguration.Key.gitHubClientID] = ""
        XCTAssertFalse(PerchConfiguration(info: info).checksForUpdates)
        info = ownerInfo
        info[PerchConfiguration.Key.updateRepository] = ""
        XCTAssertFalse(PerchConfiguration(info: info).checksForUpdates)
    }

    // MARK: Keychain names

    func testKeychainItemsAreNamedFromTheService() {
        let secrets = KeychainSecrets(keychain: FakeKeychain(), notes: MemorySecretNotes(), service: "org.example.perch")
        XCTAssertEqual(secrets.item, KeychainItem(service: "org.example.perch", account: "secrets"))
        XCTAssertEqual(secrets.oldGitHubItem, KeychainItem(service: "org.example.perch.github", account: GitHubSession.storeKey))
        XCTAssertEqual(secrets.oldRelayItem, KeychainItem(service: "org.example.perch.relay"))
    }

    // MARK: First run

    private let owner = PerchConfiguration(info: [PerchConfiguration.Key.gitHubClientID: "Iv1.example", PerchConfiguration.Key.updateRepository: "someone/perch"])
    private let stranger = PerchConfiguration.neutral

    func testOnlyABuildWithSignInAsksForAnAccount() {
        XCTAssertTrue(FirstRun.needsAccount(owner, isSignedIn: false, isTestRun: false))
        XCTAssertFalse(FirstRun.needsAccount(owner, isSignedIn: true, isTestRun: false))
        XCTAssertFalse(FirstRun.needsAccount(owner, isSignedIn: false, isTestRun: true), "test runs never ask")
        XCTAssertFalse(FirstRun.needsAccount(stranger, isSignedIn: false, isTestRun: false), "nobody can sign in, so nobody is asked")
    }

    func testWhatTheChooserOffers() {
        XCTAssertEqual(FirstRun.sources(owner), [.gitHub, .gitFolder])
        XCTAssertEqual(FirstRun.sources(stranger), [.anyFolder])
    }

    func testWhichFoldersOpen() {
        XCTAssertEqual(FirstRun.opening(owner, isGitRepository: true), .withSync)
        XCTAssertEqual(FirstRun.opening(owner, isGitRepository: false), .refused, "the owner's build is as it was")
        XCTAssertEqual(FirstRun.opening(stranger, isGitRepository: true), .withSync)
        XCTAssertEqual(FirstRun.opening(stranger, isGitRepository: false), .withoutSync, "a plain folder works, without sync")
    }

    func testUpdateChecksAtLaunch() {
        XCTAssertTrue(FirstRun.checksForUpdatesAtLaunch(owner, hasAccount: true))
        XCTAssertFalse(FirstRun.checksForUpdatesAtLaunch(owner, hasAccount: false))
        XCTAssertFalse(FirstRun.checksForUpdatesAtLaunch(stranger, hasAccount: false))
        XCTAssertFalse(FirstRun.checksForUpdatesAtLaunch(stranger, hasAccount: true))
    }

    func testSettingsShowOnlyWhatCanWork() {
        XCTAssertTrue(FirstRun.showsAccountSettings(owner))
        XCTAssertFalse(FirstRun.showsAccountSettings(stranger))
        XCTAssertTrue(FirstRun.showsUpdateChecks(owner))
        XCTAssertFalse(FirstRun.showsUpdateChecks(stranger))
    }

    // MARK: Choosing a repository

    func testThePreferredNotebookIsPicked() {
        let repositories = ["someone/perch", "someone/Notes", "someone/other"]
        XCTAssertEqual(GitHubNotebook.preferred(in: repositories, name: "notes"), "someone/Notes", "by name, ignoring case")
        XCTAssertEqual(GitHubNotebook.preferred(in: repositories, name: ""), "someone/perch", "no preference: the first")
        XCTAssertEqual(GitHubNotebook.preferred(in: repositories, name: "missing"), "someone/perch")
        XCTAssertNil(GitHubNotebook.preferred(in: [], name: "notes"))
    }

    // MARK: Areas

    func testStandardAreasComeFromTheBuild() {
        let owners = ["✈️ Acme", "Personal"]
        XCTAssertEqual(AreaList.discovered(topLevelFolders: ["✈️ Acme", "Personal", "Claude"], taskAreas: ["Personal", "Claude"], standard: owners),
                       ["✈️ Acme", "Personal", "Claude"], "the owner's areas first, in the owner's order")
        XCTAssertEqual(AreaList.discovered(topLevelFolders: ["✈️ Acme", "Personal", "Claude"], taskAreas: ["Personal", "Claude"], standard: ["Personal"]),
                       ["Personal", "Claude"], "a folder without tasks isn't an area unless the build names it")
        XCTAssertEqual(AreaList.discovered(topLevelFolders: ["Work"], taskAreas: ["Work"], standard: ["Personal"]), ["Work"],
                       "a notebook with its own areas shows exactly those, with no empty Personal beside them")
        XCTAssertEqual(AreaList.discovered(topLevelFolders: ["Studio", "Home", "Learning"], taskAreas: ["Studio", "Home", "Learning", "Home"], standard: ["Personal"]),
                       ["Studio", "Home", "Learning"])
        XCTAssertEqual(AreaList.discovered(topLevelFolders: ["Notes"], taskAreas: [], standard: ["Personal"]), ["Personal"],
                       "a notebook with no areas at all gets the first standard one, so a task has somewhere to go")
        XCTAssertEqual(AreaList.discovered(topLevelFolders: [], taskAreas: [], standard: ["✈️ Acme", "Personal"]), ["✈️ Acme"])
    }

    func testFixedTintsFollowTheStandardAreas() {
        let owners = ["✈️ Acme", "Personal"]
        XCTAssertEqual(AreaTint.fixed(for: "✈️ Acme", standard: owners), .first)
        XCTAssertEqual(AreaTint.fixed(for: "Acme Old", standard: owners), .first, "as before, the name only has to contain it")
        XCTAssertEqual(AreaTint.fixed(for: "Personal", standard: owners), .personal)
        XCTAssertEqual(AreaTint.fixed(for: "🏠 personal stuff", standard: owners), .personal)
        XCTAssertNil(AreaTint.fixed(for: "Claude", standard: owners))
        XCTAssertNil(AreaTint.fixed(for: "✈️ Acme", standard: ["Personal"]), "an area the build doesn't name gets a hashed tint")
        XCTAssertEqual(AreaTint.fixed(for: "Personal", standard: ["Personal"]), .personal)
    }
}

extension PerchConfiguration {
    /// A build whose notebook starts with a work area and Personal, as the maintainer's does, with an
    /// invented name. The area tests use it so they keep testing that order.
    static let ownersAreas = PerchConfiguration(standardAreas: ["✈️ Acme", "Personal"])
}

/// Secret notes kept in memory, for tests that never save.
private final class MemorySecretNotes: SecretNotes, @unchecked Sendable {
    var storedKeys: Set<String>?
    var pendingMoves: Set<String> = []
}
