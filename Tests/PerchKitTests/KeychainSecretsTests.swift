import XCTest
@testable import PerchKit

/// A Keychain in memory that logs every call and can refuse an item, as the real one does when the user
/// chooses Deny or closes the dialog.
final class FakeKeychain: KeychainItems, @unchecked Sendable {
    enum Call: Equatable {
        case read(KeychainItem), update(KeychainItem), add(KeychainItem), delete(KeychainItem)
    }

    private let lock = NSLock()
    private var items: [KeychainItem: Data] = [:]
    private var refusing: Set<KeychainItem> = []
    private var log: [Call] = []
    /// How long a read takes, so callers can arrive while one is under way.
    var readDelay: TimeInterval = 0

    var calls: [Call] { lock.withLock { log } }
    func clearLog() { lock.withLock { log = [] } }
    func put(_ data: Data, at item: KeychainItem) { lock.withLock { items[item] = data } }
    func data(at item: KeychainItem) -> Data? { lock.withLock { items[item] } }
    func refuse(_ item: KeychainItem) { _ = lock.withLock { refusing.insert(item) } }
    func allow(_ item: KeychainItem) { _ = lock.withLock { refusing.remove(item) } }

    func read(_ item: KeychainItem) -> SecretRead {
        lock.withLock { log.append(.read(item)) }
        if readDelay > 0 { Thread.sleep(forTimeInterval: readDelay) }
        return lock.withLock {
            if refusing.contains(item) { return .refused }
            return items[item].map(SecretRead.found) ?? .notFound
        }
    }

    func update(_ item: KeychainItem, data: Data) -> KeychainWrite {
        lock.withLock {
            log.append(.update(item))
            if refusing.contains(item) { return .refused }
            guard items[item] != nil else { return .notFound }
            items[item] = data
            return .done
        }
    }

    func add(_ item: KeychainItem, data: Data, label: String?) -> KeychainWrite {
        lock.withLock {
            log.append(.add(item))
            guard items[item] == nil else { return .duplicate }
            items[item] = data
            return .done
        }
    }

    func delete(_ item: KeychainItem) -> KeychainWrite {
        lock.withLock {
            log.append(.delete(item))
            if refusing.contains(item) { return .refused }
            return items.removeValue(forKey: item) == nil ? .notFound : .done
        }
    }
}

final class KeychainSecretsTests: XCTestCase {
    private var keychain: FakeKeychain!
    private var defaults: UserDefaults!
    private var suite: String!

    private let github = GitHubSession.storeKey
    private let relay = KeychainSecrets.relayTokenKey
    /// The build's Keychain service; the items are named from it (see BuildConfigurationTests).
    private let service = "org.example.perch"
    private var item: KeychainItem { KeychainItem(service: service, account: "secrets") }
    private var oldGitHub: KeychainItem { KeychainItem(service: service + ".github", account: GitHubSession.storeKey) }
    private var oldRelay: KeychainItem { KeychainItem(service: service + ".relay") }
    private let account = Data("the account".utf8)
    private let relayToken = Data("the relay token".utf8)

    override func setUpWithError() throws {
        suite = "KeychainSecretsTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        keychain = FakeKeychain()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    /// One launch of Perch: a fresh store over the same Keychain and preferences.
    private func launch() -> KeychainSecrets {
        KeychainSecrets(keychain: keychain, notes: UserDefaultsSecretNotes(defaults: defaults), service: service)
    }

    /// Both secrets in the one item, as a launch after the move finds them, with the log cleared.
    private func saveBoth() {
        let secrets = launch()
        secrets.save(account, for: github)
        secrets.save(relayToken, for: relay)
        keychain.clearLog()
    }

    // MARK: One read a launch

    func testTwoLoadsMakeOneRead() {
        saveBoth()
        let secrets = launch()
        XCTAssertEqual(secrets.load(github), account)
        XCTAssertEqual(secrets.load(relay), relayToken)
        XCTAssertEqual(secrets.load(github), account)
        XCTAssertEqual(keychain.calls, [.read(item)], "one item holds both, read once")
    }

    func testCallersArrivingTogetherShareOneRead() {
        saveBoth()
        keychain.readDelay = 0.2
        let secrets = launch()
        let results = NSLock()
        var found: [Data?] = []
        DispatchQueue.concurrentPerform(iterations: 8) { index in
            let value = secrets.load(index.isMultiple(of: 2) ? github : relay)
            results.withLock { found.append(value) }
        }
        XCTAssertEqual(keychain.calls, [.read(item)], "the others wait for the read under way")
        XCTAssertEqual(found.filter { $0 == account }.count, 4)
        XCTAssertEqual(found.filter { $0 == relayToken }.count, 4)
    }

    func testALaunchReadsTheKeychainOnceForSyncAndTheRelay() async throws {
        let signedIn = GitHubAccount(login: "alexdoe", id: 42, name: "Alex Doe",
                                     token: .init(accessToken: "ghu_forever", refreshToken: nil, expiresAt: nil))
        let first = launch()
        first.save(try JSONEncoder().encode(signedIn), for: github)
        first.save(relayToken, for: relay)
        keychain.clearLog()
        keychain.readDelay = 0.1

        let secrets = launch()
        let session = GitHubSession(signIn: GitHubDeviceSignIn(clientID: "Iv-test"), store: secrets)
        XCTAssertEqual(keychain.calls, [], "making the session reads nothing")
        async let token = session.accessToken()
        async let relayRead = Task.detached { secrets.load(KeychainSecrets.relayTokenKey) }.value
        let (accessToken, relayValue) = try await (token, relayRead)
        XCTAssertEqual(accessToken, "ghu_forever")
        XCTAssertEqual(relayValue, relayToken)
        _ = try await session.accessToken()
        XCTAssertEqual(keychain.calls, [.read(item)])
    }

    // MARK: Moving the old items

    func testBothOldItemsMoveIntoOneAndAreThenDeleted() {
        keychain.put(account, at: oldGitHub)
        keychain.put(relayToken, at: oldRelay)
        let secrets = launch()
        XCTAssertEqual(secrets.load(github), account)
        XCTAssertEqual(secrets.load(relay), relayToken)
        XCTAssertEqual(keychain.calls, [.read(item), .read(oldGitHub), .read(oldRelay), .add(item), .delete(oldGitHub), .delete(oldRelay)])
        XCTAssertNil(keychain.data(at: oldGitHub))
        XCTAssertNil(keychain.data(at: oldRelay))
        XCTAssertEqual(secrets.isSaved(github), true)
        XCTAssertEqual(secrets.isSaved(relay), true)

        keychain.clearLog()
        let next = launch()
        XCTAssertEqual(next.load(relay), relayToken)
        XCTAssertEqual(next.load(github), account)
        XCTAssertEqual(keychain.calls, [.read(item)], "the next launch reads the one item and nothing else")
    }

    func testOneOldItemMovesAndTheOtherIsNotSaved() {
        keychain.put(account, at: oldGitHub)
        let secrets = launch()
        XCTAssertEqual(secrets.load(github), account)
        XCTAssertEqual(secrets.read(relay), .notFound)
        XCTAssertEqual(keychain.calls, [.read(item), .read(oldGitHub), .read(oldRelay), .add(item), .delete(oldGitHub)])
        XCTAssertEqual(secrets.isSaved(github), true)
        XCTAssertEqual(secrets.isSaved(relay), false)
    }

    func testWithNoOldItemsNothingIsWrittenAndLaterLaunchesNeverTouchTheKeychain() {
        let secrets = launch()
        XCTAssertNil(secrets.isSaved(github), "not known before the first look")
        XCTAssertNil(secrets.load(github))
        XCTAssertNil(secrets.load(relay))
        XCTAssertEqual(keychain.calls, [.read(item), .read(oldGitHub), .read(oldRelay)], "reads that find nothing ask nothing, and nothing is added")

        keychain.clearLog()
        let next = launch()
        XCTAssertEqual(next.isSaved(github), false)
        XCTAssertNil(next.load(github))
        XCTAssertEqual(next.read(relay), .notFound)
        next.delete(github)
        XCTAssertEqual(keychain.calls, [], "nothing is saved, so the Keychain isn't touched at all")
    }

    func testARefusedOldItemStaysWhereItIsAndIsAskedForOnALaterLaunch() {
        keychain.put(account, at: oldGitHub)
        keychain.put(relayToken, at: oldRelay)
        keychain.refuse(oldRelay)
        let secrets = launch()
        XCTAssertEqual(secrets.load(github), account)
        XCTAssertEqual(secrets.read(relay), .refused, "a refusal is not the same as nothing saved")
        XCTAssertEqual(secrets.read(relay), .refused)
        XCTAssertEqual(keychain.calls, [.read(item), .read(oldGitHub), .read(oldRelay), .add(item), .delete(oldGitHub)],
                       "the refused item is asked for once this launch, and left in place")
        XCTAssertEqual(keychain.data(at: oldRelay), relayToken, "nothing is lost")
        XCTAssertEqual(secrets.isSaved(relay), true)

        // A later launch asks for it again, and moves it this time.
        keychain.allow(oldRelay)
        keychain.clearLog()
        let next = launch()
        XCTAssertEqual(next.load(relay), relayToken)
        XCTAssertEqual(next.load(github), account)
        XCTAssertEqual(keychain.calls, [.read(item), .read(oldRelay), .update(item), .delete(oldRelay)])

        keychain.clearLog()
        let third = launch()
        XCTAssertEqual(third.load(relay), relayToken)
        XCTAssertEqual(keychain.calls, [.read(item)])
    }

    func testAValueAlreadyInTheNewItemWinsOverAnOldItemLeftBehind() {
        keychain.put(account, at: oldGitHub)
        keychain.put(relayToken, at: oldRelay)
        keychain.refuse(oldGitHub)
        let secrets = launch()
        XCTAssertEqual(secrets.read(github), .refused)
        // The user signs in again: the new account is the one to keep.
        let newer = Data("signed in again".utf8)
        secrets.save(newer, for: github)

        keychain.allow(oldGitHub)
        keychain.clearLog()
        let next = launch()
        XCTAssertEqual(next.load(github), newer)
        XCTAssertEqual(keychain.calls, [.read(item), .read(oldGitHub), .delete(oldGitHub)], "the old item goes, and the newer value stays")
    }

    // MARK: Saving

    func testASaveUpdatesTheItemInPlaceAndNeverDeletesItFirst() {
        saveBoth()
        let secrets = launch()
        secrets.save(Data("renewed".utf8), for: github)
        secrets.save(Data("renewed again".utf8), for: github)
        secrets.save(Data("renewed again".utf8), for: github)
        XCTAssertEqual(keychain.calls, [.read(item), .update(item), .update(item)],
                       "read first so the other secret is kept; then update, which keeps the item's access list; an unchanged value isn't written")
        let next = launch()
        XCTAssertEqual(next.load(github), Data("renewed again".utf8))
        XCTAssertEqual(next.load(relay), relayToken)
    }

    func testTheItemIsAddedOnlyWhenItIsNotThere() {
        XCTAssertNil(launch().load(github))
        keychain.clearLog()
        let secrets = launch()
        secrets.save(account, for: github)
        XCTAssertEqual(keychain.calls, [.add(item)], "known to be empty, so there is nothing to read first")
        secrets.save(relayToken, for: relay)
        XCTAssertEqual(keychain.calls, [.add(item), .update(item)])
        XCTAssertEqual(secrets.isSaved(relay), true)
    }

    func testDeletingOneSecretKeepsTheOtherAndDeletingTheLastRemovesTheItem() {
        saveBoth()
        let secrets = launch()
        secrets.delete(github)
        XCTAssertEqual(keychain.calls, [.read(item), .update(item)])
        XCTAssertEqual(secrets.isSaved(github), false)
        XCTAssertEqual(secrets.load(relay), relayToken)
        secrets.delete(relay)
        XCTAssertEqual(keychain.calls, [.read(item), .update(item), .delete(item)])
        XCTAssertNil(keychain.data(at: item))

        keychain.clearLog()
        XCTAssertNil(launch().load(github))
        XCTAssertEqual(keychain.calls, [])
    }

    // MARK: Refusals

    func testARefusalIsRememberedForTheLaunch() {
        saveBoth()
        keychain.refuse(item)
        let secrets = launch()
        XCTAssertEqual(secrets.read(github), .refused)
        XCTAssertNil(secrets.load(github))
        XCTAssertEqual(secrets.read(relay), .refused)
        XCTAssertEqual(keychain.calls, [.read(item)], "asked once, and not again this launch")
        XCTAssertNotNil(keychain.data(at: item), "a refusal never deletes")
        XCTAssertEqual(secrets.isSaved(github), true, "still saved, as far as Perch knows")

        // The user chooses Connect in Settings, which needs the secret: asking again is allowed.
        keychain.allow(item)
        secrets.allowAskingAgain()
        XCTAssertEqual(secrets.load(relay), relayToken)
        XCTAssertEqual(secrets.load(github), account)
        XCTAssertEqual(keychain.calls, [.read(item), .read(item)])
    }

    func testAfterARefusalASaveAsksOnceMoreAndNeverWritesOverWhatItCouldNotRead() {
        saveBoth()
        keychain.refuse(item)
        let secrets = launch()
        XCTAssertEqual(secrets.read(github), .refused)
        // The user signs in again while the Keychain still says no.
        let newer = Data("signed in again".utf8)
        secrets.save(newer, for: github)
        secrets.delete(relay)
        XCTAssertEqual(keychain.calls, [.read(item), .read(item), .read(item)], "each thing the user does asks once more, and writes nothing")
        XCTAssertEqual(secrets.load(github), newer, "kept for this launch")

        keychain.allow(item)
        let next = launch()
        XCTAssertEqual(next.load(github), account)
        XCTAssertEqual(next.load(relay), relayToken, "nothing was lost")
    }

    func testAnItemPerchCannotMakeSenseOfIsNeverWrittenOver() {
        keychain.put(Data("written by something else".utf8), at: item)
        let secrets = launch()
        XCTAssertEqual(secrets.read(github), .refused)
        secrets.save(account, for: github)
        XCTAssertFalse(keychain.calls.contains { if case .update = $0 { true } else if case .add = $0 { true } else { false } })
        XCTAssertEqual(keychain.data(at: item), Data("written by something else".utf8))
    }

    func testPreferencesNameTheSecretsAndNeverHoldThem() throws {
        saveBoth()
        let stored = try XCTUnwrap(keychain.data(at: item))
        let preferences = try XCTUnwrap(defaults.persistentDomain(forName: suite))
        let written = try PropertyListSerialization.data(fromPropertyList: preferences, format: .xml, options: 0)
        XCTAssertFalse(String(decoding: written, as: UTF8.self).contains("the relay token"), "preferences name the secrets, never hold them")
        XCTAssertFalse(String(decoding: written, as: UTF8.self).contains("the account"))
        XCTAssertNotNil(KeychainSecrets.decode(stored))
    }
}
