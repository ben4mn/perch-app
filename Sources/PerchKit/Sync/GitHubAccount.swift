import Foundation

/// The GitHub account Perch is signed in to, with its token.
public struct GitHubAccount: Codable, Equatable, Sendable {
    public var login: String
    public var id: Int
    public var name: String?
    public var token: GitHubDeviceSignIn.Token

    public init(login: String, id: Int, name: String?, token: GitHubDeviceSignIn.Token) {
        self.login = login
        self.id = id
        self.name = name
        self.token = token
    }

    /// The name and address commits carry: see `GitHubProfile`.
    public var commitName: String { GitHubProfile(self).commitName }
    public var commitEmail: String { GitHubProfile(self).commitEmail }

    /// A token is renewed a few minutes before it runs out, so a sync never starts with one about to expire.
    func tokenNeedsRefresh(at now: Date) -> Bool {
        guard let expiresAt = token.expiresAt, token.refreshToken != nil else { return false }
        return expiresAt.timeIntervalSince(now) < 5 * 60
    }
}

/// The parts of the account that aren't secret, kept in preferences so drawing the window never needs the
/// Keychain: who is signed in, and the name and address their commits carry.
public struct GitHubProfile: Codable, Equatable, Sendable {
    public var login: String
    public var id: Int
    public var name: String?

    public init(_ account: GitHubAccount) {
        login = account.login
        id = account.id
        name = account.name
    }

    /// Commits in a notebook cloned from GitHub carry the account's name and its private GitHub address,
    /// so no other email (a work one, say) ends up in the repository's history.
    public var commitName: String { (name?.isEmpty == false ? name : nil) ?? login }
    public var commitEmail: String { "\(id)+\(login)@users.noreply.github.com" }
}

/// Somewhere to keep secrets. The Mac keeps them in the Keychain (`KeychainSecrets`); tests and the debug
/// test runs keep them in memory.
public protocol SecretStore: Sendable {
    func load(_ key: String) -> Data?
    func save(_ data: Data, for key: String)
    func delete(_ key: String)
    /// Like `load`, but tells nothing saved apart from a read the Keychain refused.
    func read(_ key: String) -> SecretRead
}

extension SecretStore {
    public func read(_ key: String) -> SecretRead { load(key).map(SecretRead.found) ?? .notFound }
}

public final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private var items: [String: Data] = [:]
    private let lock = NSLock()

    public init() {}
    public func load(_ key: String) -> Data? { lock.withLock { items[key] } }
    public func save(_ data: Data, for key: String) { lock.withLock { items[key] = data } }
    public func delete(_ key: String) { _ = lock.withLock { items.removeValue(forKey: key) } }
}

/// The signed-in account, kept in a secret store, with a token that is renewed when it is about to run out.
/// The store is read the first time something needs the account (usually the first sync), not before.
public actor GitHubSession {
    public static let storeKey = "github-account"

    private let signIn: GitHubDeviceSignIn
    private let store: SecretStore
    private var stored: GitHubAccount?
    /// Whether the store has answered. A refused read leaves this false, so the next need asks the store
    /// again; the store itself decides whether that reaches the Keychain.
    private var loaded = false

    public init(signIn: GitHubDeviceSignIn, store: SecretStore) {
        self.signIn = signIn
        self.store = store
    }

    /// The signed-in account, or nil when there is none or the store wouldn't hand it over.
    public var account: GitHubAccount? { (try? currentAccount()) ?? nil }

    /// The remembered account, read without waiting for the session. Throws `SyncError.keychainRefused`
    /// when the store refused, which is not the same as signed out.
    public nonisolated static func storedAccount(in store: SecretStore) throws -> GitHubAccount? {
        switch store.read(storeKey) {
        case let .found(data): return try? JSONDecoder().decode(GitHubAccount.self, from: data)
        case .notFound: return nil
        case .refused: throw SyncError.keychainRefused
        }
    }

    private func currentAccount() throws -> GitHubAccount? {
        if loaded { return stored }
        stored = try Self.storedAccount(in: store)
        loaded = true
        return stored
    }

    /// Finishes a sign-in: asks GitHub who this is and remembers the account.
    @discardableResult
    public func signedIn(with token: GitHubDeviceSignIn.Token) async throws -> GitHubAccount {
        let user = try await signIn.user(token: token.accessToken)
        let account = GitHubAccount(login: user.login, id: user.id, name: user.name, token: token)
        remember(account)
        return account
    }

    /// A token that is good for the next few minutes. Throws `SyncError.keychainRefused` when the account
    /// couldn't be read, and `SyncError.authentication` when nobody is signed in.
    public func accessToken(now: Date = Date()) async throws -> String {
        guard var account = try currentAccount() else { throw SyncError.authentication }
        if account.tokenNeedsRefresh(at: now) {
            // Callers arriving during a renewal wait for it: GitHub takes each refresh token only once, and
            // each renewal is a Keychain write.
            if let refreshing { return try await refreshing.value.token.accessToken }
            let signIn = signIn
            let renewal = Task { [account] in
                var renewed = account
                renewed.token = try await signIn.refresh(account.token)
                return renewed
            }
            refreshing = renewal
            defer { refreshing = nil }
            account = try await renewal.value
            remember(account)
        }
        return account.token.accessToken
    }

    private var refreshing: Task<GitHubAccount, Error>?

    /// The repositories Perch can reach for this account.
    public func reach() async throws -> GitHubDeviceSignIn.Reach {
        try await signIn.reach(token: accessToken())
    }

    public func signOut() {
        stored = nil
        loaded = true
        store.delete(Self.storeKey)
    }

    private func remember(_ account: GitHubAccount) {
        stored = account
        loaded = true
        if let data = try? JSONEncoder().encode(account) { store.save(data, for: Self.storeKey) }
    }
}

/// Notebooks that come from a GitHub repository.
public enum GitHubNotebook {
    /// "owner/name" from a remote address, if it is on github.com.
    public static func fullName(fromRemote remote: String) -> String? {
        var path: Substring
        if let url = URL(string: remote), let host = url.host?.lowercased(), ["https", "http", "ssh"].contains(url.scheme?.lowercased() ?? "") {
            guard host == "github.com" else { return nil }
            path = Substring(url.path)
        } else if let colon = remote.firstIndex(of: ":"), remote[..<colon].lowercased().hasSuffix("@github.com") || remote[..<colon].lowercased() == "github.com" {
            path = remote[remote.index(after: colon)...]
        } else {
            return nil
        }
        while path.hasPrefix("/") { path = path.dropFirst() }
        while path.hasSuffix("/") { path = path.dropLast() }
        if path.lowercased().hasSuffix(".git") { path = path.dropLast(4) }
        let parts = path.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return parts.joined(separator: "/")
    }

    /// The address Perch clones from.
    public static func remoteURL(for fullName: String) -> String { "https://github.com/\(fullName).git" }

    /// The repository to offer first: the one named `name` (the build's `preferredNotebook`, ignoring case),
    /// or failing that the first one.
    public static func preferred(in repositories: [String], name: String) -> String? {
        let wanted = name.lowercased()
        let named = wanted.isEmpty ? nil : repositories.first { $0.lowercased().hasSuffix("/" + wanted) }
        return named ?? repositories.first
    }

    /// Where a new GitHub notebook goes unless you pick somewhere else: ~/Documents/Perch.
    public static var defaultParent: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Perch", isDirectory: true)
    }

    public enum Placement: Equatable, Sendable {
        /// A clone of this repository is already there.
        case open(URL)
        /// Clone into this folder, which doesn't exist yet.
        case clone(URL)
    }

    #if os(macOS)
    /// Where a repository's notebook goes inside a folder: an existing clone of it is reused, and any other
    /// folder of that name is left alone and the clone goes beside it.
    public static func placement(for fullName: String, in parent: URL) -> Placement {
        let name = fullName.split(separator: "/").last.map(String.init) ?? fullName
        var number = 1
        while true {
            let candidate = parent.appendingPathComponent(number == 1 ? name : "\(name) \(number)")
            guard FileManager.default.fileExists(atPath: candidate.path) else { return .clone(candidate) }
            if let origin = GitCLISync.origin(of: candidate), let existing = Self.fullName(fromRemote: origin),
               existing.caseInsensitiveCompare(fullName) == .orderedSame {
                return .open(candidate)
            }
            number += 1
        }
    }
    #endif
}
