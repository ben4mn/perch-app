import Foundation
#if canImport(Security)
import Security
#endif

/// What asking for a secret found.
public enum SecretRead: Equatable, Sendable {
    case found(Data)
    case notFound
    /// The user chose Deny or closed the dialog, or the Keychain couldn't ask (locked, no window to ask in), or
    /// held something Perch can't make sense of. Not the same as nothing saved: nothing is deleted or written
    /// over because of it.
    case refused
}

/// One generic password in the Keychain, named by its service and, when it has one, its account.
public struct KeychainItem: Hashable, Sendable {
    public var service: String
    /// Nil matches the service's item whatever its account. The Relay token was saved without one.
    public var account: String?

    public init(service: String, account: String? = nil) {
        self.service = service
        self.account = account
    }
}

/// How a Keychain write went.
public enum KeychainWrite: Equatable, Sendable {
    case done
    case notFound
    case duplicate
    case refused
}

/// The few Keychain calls Perch makes, behind a protocol so tests can count them and refuse them.
public protocol KeychainItems: Sendable {
    func read(_ item: KeychainItem) -> SecretRead
    /// Changes the data of an item that is there. Its access list, the apps allowed to read it without
    /// asking, stays as it is.
    func update(_ item: KeychainItem, data: Data) -> KeychainWrite
    /// Makes an item. Its access list names only the build that is running.
    func add(_ item: KeychainItem, data: Data, label: String?) -> KeychainWrite
    func delete(_ item: KeychainItem) -> KeychainWrite
}

/// What Perch keeps about its secrets outside the Keychain: their names, never their values. With these it
/// can tell that nothing is saved without asking the Keychain.
public protocol SecretNotes: AnyObject, Sendable {
    /// The names of the secrets in the Keychain, or nil until this version of Perch has looked.
    var storedKeys: Set<String>? { get set }
    /// Secrets still in an item an earlier Perch made, because reading it was refused. They are moved on a
    /// later launch.
    var pendingMoves: Set<String> { get set }
}

/// `SecretNotes` in preferences.
public final class UserDefaultsSecretNotes: SecretNotes, @unchecked Sendable {
    static let storedKeysKey = "keychainSecretNames"
    static let pendingMovesKey = "keychainSecretsToMove"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var storedKeys: Set<String>? {
        get { defaults.stringArray(forKey: Self.storedKeysKey).map(Set.init) }
        set { defaults.set(newValue.map { $0.sorted() }, forKey: Self.storedKeysKey) }
    }

    public var pendingMoves: Set<String> {
        get { Set(defaults.stringArray(forKey: Self.pendingMovesKey) ?? []) }
        set { newValue.isEmpty ? defaults.removeObject(forKey: Self.pendingMovesKey) : defaults.set(newValue.sorted(), forKey: Self.pendingMovesKey) }
    }
}

/// Every secret Perch keeps on the Mac, in one Keychain item that is read at most once a launch.
///
/// macOS asks before an app reads an item whose access list doesn't name the build that is running, and a
/// local build is new to it every time. One item means one question covers the GitHub account and the Relay
/// token together, and only when something needs one of them:
/// - The first read fills a cache; later reads, from any thread, come from memory. Callers arriving while a
///   read is under way wait for it rather than start another.
/// - Saving updates the item in place, so its access list (every build the user has allowed) is kept.
/// - When the notes say nothing is saved, the Keychain isn't touched at all.
/// - A refused read is remembered for the launch. It is asked again only when the user does something that needs a
///   secret (signing in, Connect in Settings), and nothing is deleted or written over because of it.
/// - The items earlier versions kept, one per secret, are moved into this one the first time it is needed.
public final class KeychainSecrets: SecretStore, @unchecked Sendable {
    /// The name the Keychain shows, in Keychain Access and in its dialog.
    public static let label = "Perch"
    public static let relayTokenKey = "relay-token"
    /// The one item, named by the build's Keychain service (`PerchConfiguration.keychainService`).
    public let item: KeychainItem
    /// Where earlier versions kept each secret, one item each, under the same service with a suffix.
    public let oldGitHubItem: KeychainItem
    public let oldRelayItem: KeychainItem
    /// Where each secret lived before, in the order they are moved.
    private var oldItems: [(key: String, item: KeychainItem)] { [(GitHubSession.storeKey, oldGitHubItem), (Self.relayTokenKey, oldRelayItem)] }

    private enum State {
        case unread
        case read(itemExists: Bool)
        case refused
    }

    private let keychain: KeychainItems
    private let notes: SecretNotes
    /// Held through every Keychain call, so there is only ever one at a time.
    private let lock = NSLock()
    private var state = State.unread
    private var values: [String: Data] = [:]
    /// Secrets in old items that were refused this launch. They stay where they are.
    private var unreadable: Set<String> = []
    /// Set by `allowAskingAgain` when there are old items to ask for again.
    private var retryUnreadable = false

    public init(keychain: KeychainItems, notes: SecretNotes, service: String) {
        self.keychain = keychain
        self.notes = notes
        item = KeychainItem(service: service, account: "secrets")
        oldGitHubItem = KeychainItem(service: service + ".github", account: GitHubSession.storeKey)
        oldRelayItem = KeychainItem(service: service + ".relay")
    }

    public func read(_ key: String) -> SecretRead {
        lock.withLock {
            loadIfNeeded()
            if retryUnreadable {
                retryUnreadable = false
                moveOldItems(oldItems.filter { unreadable.contains($0.key) })
            }
            if let value = values[key] { return .found(value) }
            if unreadable.contains(key) { return .refused }
            if case .refused = state { return notes.storedKeys?.contains(key) == false ? .notFound : .refused }
            return .notFound
        }
    }

    public func load(_ key: String) -> Data? {
        if case let .found(data) = read(key) { return data }
        return nil
    }

    /// Saves come from the user signing in or connecting, or from a token renewed after a read that worked. After a
    /// refusal, a save asks once more rather than write over secrets it couldn't read; refused again, the
    /// value is kept for this launch only.
    public func save(_ data: Data, for key: String) {
        lock.withLock {
            loadIfNeeded()
            if case .refused = state { state = .unread; loadIfNeeded() }
            let unchanged = values[key] == data
            values[key] = data
            unreadable.remove(key)
            guard case .read = state, !unchanged else { return }
            if writeItem() { noteWhatIsStored() }
        }
    }

    public func delete(_ key: String) {
        lock.withLock {
            // Known not to be saved: nothing to do, and the Keychain isn't touched.
            if let stored = notes.storedKeys, !stored.contains(key), values[key] == nil { return }
            loadIfNeeded()
            if case .refused = state { state = .unread; loadIfNeeded() }
            let had = values.removeValue(forKey: key) != nil
            // An old item left behind holds only this secret, so signing out can remove it without reading it.
            if notes.pendingMoves.contains(key), let old = oldItems.first(where: { $0.key == key }) {
                _ = keychain.delete(old.item)
                notes.pendingMoves.remove(key)
                unreadable.remove(key)
            }
            guard case .read = state else { return }
            if had {
                if values.isEmpty {
                    let result = keychain.delete(item)
                    guard result == .done || result == .notFound else { return }
                    state = .read(itemExists: false)
                } else {
                    guard writeItem() else { return }
                }
            }
            noteWhatIsStored()
        }
    }

    /// Whether a secret is saved, from the notes alone: nil until this version of Perch has looked. Never
    /// touches the Keychain and never waits for it, so a window can draw from it.
    public func isSaved(_ key: String) -> Bool? {
        notes.storedKeys.map { $0.contains(key) }
    }

    /// For something the user does that needs a secret, such as Connect in Settings: a refusal earlier in this
    /// launch may be asked again.
    public func allowAskingAgain() {
        lock.withLock {
            switch state {
            case .refused: state = .unread
            case .read: retryUnreadable = !unreadable.isEmpty
            case .unread: break
            }
        }
    }

    // MARK: Under the lock

    private func loadIfNeeded() {
        guard case .unread = state else { return }
        // Nothing saved, as far as this Perch knows: the Keychain isn't asked.
        if let stored = notes.storedKeys, stored.isEmpty {
            state = .read(itemExists: false)
            return
        }
        switch keychain.read(item) {
        case let .found(data):
            guard let decoded = Self.decode(data) else {
                // Not something Perch wrote, or written by a newer Perch: leave it alone.
                state = .refused
                return
            }
            // A value saved earlier this launch, while the item couldn't be read, is the newer one.
            values = decoded.merging(values) { _, saved in saved }
            state = .read(itemExists: true)
        case .notFound:
            state = .read(itemExists: false)
        case .refused:
            state = .refused
            return
        }
        // The first look by this version moves every old item; later launches move only those left behind.
        if notes.storedKeys == nil {
            moveOldItems(oldItems)
        } else {
            let pending = notes.pendingMoves
            if !pending.isEmpty { moveOldItems(oldItems.filter { pending.contains($0.key) }) }
        }
    }

    /// Reads each old item once, writes what it found into the one item, and only then deletes the old ones.
    /// A refused item is left where it is, to be asked for on a later launch.
    private func moveOldItems(_ candidates: [(key: String, item: KeychainItem)]) {
        var found: [(key: String, item: KeychainItem)] = []
        var refused: Set<String> = []
        var changed = false
        for old in candidates {
            switch keychain.read(old.item) {
            case let .found(data):
                found.append(old)
                // A value already in the one item is newer than the old item's.
                if values[old.key] == nil {
                    values[old.key] = data
                    changed = true
                }
            case .notFound:
                break
            case .refused:
                refused.insert(old.key)
            }
        }
        unreadable.formUnion(refused)
        var pending = notes.pendingMoves.subtracting(candidates.map(\.key)).union(refused)
        if changed, !writeItem() {
            // Couldn't write the one item: every old item stays, to be moved on a later launch.
            pending.formUnion(found.map(\.key))
        } else {
            for old in found {
                let result = keychain.delete(old.item)
                if result != .done, result != .notFound { pending.insert(old.key) }
            }
        }
        notes.pendingMoves = pending
        noteWhatIsStored()
    }

    /// Writes `values` to the one item: an update when it is there, so its access list is kept, and an add
    /// only when it isn't. An item that appears between the read and the write is not written over.
    private func writeItem() -> Bool {
        let data = Self.encode(values)
        let exists: Bool
        if case let .read(itemExists) = state { exists = itemExists } else { return false }
        var result = exists ? keychain.update(item, data: data) : keychain.add(item, data: data, label: Self.label)
        if exists, result == .notFound { result = keychain.add(item, data: data, label: Self.label) }
        guard result == .done else { return false }
        state = .read(itemExists: true)
        return true
    }

    private func noteWhatIsStored() {
        notes.storedKeys = Set(values.keys).union(notes.pendingMoves)
    }

    // MARK: The item's contents

    private struct Contents: Codable {
        var version: Int
        var secrets: [String: Data]
    }

    /// The secrets as one small JSON object (the values in base64), only ever written to the Keychain item.
    static func encode(_ secrets: [String: Data]) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(Contents(version: 1, secrets: secrets))) ?? Data()
    }

    static func decode(_ data: Data) -> [String: Data]? {
        guard let contents = try? JSONDecoder().decode(Contents.self, from: data), contents.version == 1 else { return nil }
        return contents.secrets
    }
}

#if canImport(Security)
/// The login Keychain, through Security's `SecItem` calls.
public struct SystemKeychain: KeychainItems {
    public init() {}

    private func query(_ item: KeychainItem) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: item.service]
        if let account = item.account { query[kSecAttrAccount as String] = account }
        return query
    }

    public func read(_ item: KeychainItem) -> SecretRead {
        var request = query(item)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        switch SecItemCopyMatching(request as CFDictionary, &result) {
        case errSecSuccess: return .found(result as? Data ?? Data())
        case errSecItemNotFound: return .notFound
        // errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed and anything else: not "nothing saved".
        default: return .refused
        }
    }

    public func update(_ item: KeychainItem, data: Data) -> KeychainWrite {
        Self.write(SecItemUpdate(query(item) as CFDictionary, [kSecValueData as String: data] as CFDictionary))
    }

    public func add(_ item: KeychainItem, data: Data, label: String?) -> KeychainWrite {
        var add = query(item)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if let label { add[kSecAttrLabel as String] = label }
        return Self.write(SecItemAdd(add as CFDictionary, nil))
    }

    public func delete(_ item: KeychainItem) -> KeychainWrite {
        Self.write(SecItemDelete(query(item) as CFDictionary))
    }

    private static func write(_ status: OSStatus) -> KeychainWrite {
        switch status {
        case errSecSuccess: return .done
        case errSecItemNotFound: return .notFound
        case errSecDuplicateItem: return .duplicate
        default: return .refused
        }
    }
}
#endif
