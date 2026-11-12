import CryptoKit
import Foundation

/// Syncs a local folder with a GitHub branch through its REST API.
/// iOS has no `git` command, and this needs no native Git library.
public actor GitHubAPISync: SyncEngine {
    public struct Configuration: Codable, Equatable, Sendable {
        public var owner: String
        public var repository: String
        public var branch: String
        public init(owner: String, repository: String, branch: String = "main") {
            self.owner = owner
            self.repository = repository
            self.branch = branch
        }
    }

    /// The last synced commit and each file's Git blob ID.
    struct State: Codable, Equatable {
        var commit: String
        var blobs: [String: String]
    }

    private struct TreeEntry: Codable {
        var path: String
        var type: String
        var sha: String?
        var mode: String?
    }

    private let configuration: Configuration
    private let token: String
    private let vault: Vault
    private let stateURL: URL
    private let session: URLSession
    private let baseURL: URL
    private let authorName: String
    private let authorEmail: String
    private let progress: (@Sendable (String) -> Void)?

    public init(
        configuration: Configuration,
        token: String,
        root: URL,
        stateURL: URL,
        authorName: String = "Perch",
        authorEmail: String = "perch@users.noreply.github.com",
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.github.com")!,
        progress: (@Sendable (String) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.token = token
        vault = Vault(root: root)
        self.stateURL = stateURL
        self.session = session
        self.baseURL = baseURL
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.progress = progress
    }

    public func sync() async throws -> SyncResult {
        // A push can lose a race with another device. Retrying merges their commit too.
        var lastError: Error?
        for _ in 0..<3 {
            do {
                return try await syncOnce()
            } catch let SyncError.failed(message) where message.contains("not a fast forward") || message.contains("HTTP 422") {
                lastError = SyncError.failed(message)
            }
        }
        throw lastError ?? SyncError.failed("Sync kept losing a race with another device.")
    }

    private func syncOnce() async throws -> SyncResult {
        var result = SyncResult()
        let state = loadState()
        let head = try await headCommit()
        let remote = try await remoteTree(commit: head)
        let local = try localBlobs()

        let base = state?.blobs ?? [:]
        var uploads: [String: Data] = [:]
        var deletes: Set<String> = []
        var downloads: Set<String> = []
        var removals: Set<String> = []
        let today = DayMath.string(from: Date())

        for path in Set(base.keys).union(remote.keys).union(local.keys) {
            let baseBlob = base[path], remoteBlob = remote[path], localBlob = local[path]
            if remoteBlob == localBlob { continue }
            let localChanged = localBlob != baseBlob
            let remoteChanged = remoteBlob != baseBlob
            switch (localChanged, remoteChanged) {
            case (false, true):
                if remoteBlob == nil { removals.insert(path) } else { downloads.insert(path) }
            case (true, false):
                if localBlob == nil { deletes.insert(path) } else { uploads[path] = try vault.readData(path) }
            case (true, true):
                result.conflicts.append(path)
                try await mergeConflict(
                    path: path, remoteBlob: remoteBlob, localBlob: localBlob, today: today,
                    uploads: &uploads, downloads: &downloads
                )
            case (false, false):
                continue
            }
        }

        var finalBlobs = remote
        var downloaded = 0
        for path in downloads.sorted() {
            guard let blob = remote[path] else { continue }
            progress?("Downloading \(VaultFile(path: path).name)")
            // Conflict paths already wrote their merged copy, which `uploads` will send.
            if uploads[path] == nil { try vault.writeData(try await fetchBlob(blob), to: path) }
            downloaded += 1
        }
        for path in removals where vault.exists(path) {
            try vault.delete(path)
            finalBlobs[path] = nil
        }
        result.pulled = downloaded + removals.count

        if !uploads.isEmpty || !deletes.isEmpty {
            var entries: [TreeEntry] = []
            for (path, data) in uploads.sorted(by: { $0.key < $1.key }) {
                progress?("Uploading \(VaultFile(path: path).name)")
                let sha = try await createBlob(data)
                finalBlobs[path] = sha
                entries.append(TreeEntry(path: path, type: "blob", sha: sha, mode: "100644"))
            }
            for path in deletes where remote[path] != nil {
                finalBlobs[path] = nil
                entries.append(TreeEntry(path: path, type: "blob", sha: nil, mode: "100644"))
            }
            if !entries.isEmpty {
                let baseTree = try await commitTree(head)
                let tree = try await createTree(base: baseTree, entries: entries)
                let names = (Array(uploads.keys) + Array(deletes)).map { VaultFile(path: $0).name }
                let message = names.count == 1 ? "Update \(names[0])" : "Update \(names.count) files"
                let commit = try await createCommit(message: message, tree: tree, parent: head)
                try await updateHead(to: commit)
                result.pushed = uploads.count + deletes.count
                saveState(State(commit: commit, blobs: finalBlobs))
                return result
            }
        }
        for path in deletes { finalBlobs[path] = nil }
        saveState(State(commit: head, blobs: finalBlobs))
        return result
    }

    private func mergeConflict(
        path: String, remoteBlob: String?, localBlob: String?, today: String,
        uploads: inout [String: Data], downloads: inout Set<String>
    ) async throws {
        guard let remoteBlob else {
            // Deleted elsewhere but edited here: keep the edit.
            if localBlob != nil { uploads[path] = try vault.readData(path) }
            return
        }
        guard localBlob != nil else {
            // Deleted here but edited elsewhere: keep the edit.
            downloads.insert(path)
            return
        }
        let remoteData = try await fetchBlob(remoteBlob)
        let localData = try vault.readData(path)
        if !MergePolicy.usesCopy(path), let remoteText = String(data: remoteData, encoding: .utf8), let localText = String(data: localData, encoding: .utf8) {
            let merged = Data(ConflictBlocks.wrap(remote: remoteText, local: localText).utf8)
            try vault.writeData(merged, to: path)
            uploads[path] = merged
        } else {
            let copy = MergePolicy.conflictCopyPath(path, date: today)
            try vault.writeData(localData, to: copy)
            uploads[copy] = localData
            try vault.writeData(remoteData, to: path)
        }
    }

    private func localBlobs() throws -> [String: String] {
        var blobs: [String: String] = [:]
        for file in try vault.scan() { blobs[file.path] = Self.blobID(try vault.readData(file.path)) }
        return blobs
    }

    /// Git's blob ID: SHA-1 of `blob <size>\0<bytes>`.
    public static func blobID(_ data: Data) -> String {
        var hasher = Insecure.SHA1()
        hasher.update(data: Data("blob \(data.count)\0".utf8))
        hasher.update(data: data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: GitHub API

    private func headCommit() async throws -> String {
        let response: [String: JSONValue] = try await request("git/ref/heads/\(configuration.branch)")
        guard case let .object(object)? = response["object"], case let .string(sha)? = object["sha"] else {
            throw SyncError.failed("GitHub didn't return the branch head.")
        }
        return sha
    }

    private func commitTree(_ commit: String) async throws -> String {
        let response: [String: JSONValue] = try await request("git/commits/\(commit)")
        guard case let .object(tree)? = response["tree"], case let .string(sha)? = tree["sha"] else {
            throw SyncError.failed("GitHub didn't return the commit's tree.")
        }
        return sha
    }

    private func remoteTree(commit: String) async throws -> [String: String] {
        struct TreeResponse: Decodable {
            var tree: [TreeEntry]
            var truncated: Bool
        }
        let tree = try await commitTree(commit)
        let response: TreeResponse = try await request("git/trees/\(tree)?recursive=1")
        guard !response.truncated else {
            throw SyncError.failed("This notebook is too large for GitHub's file listing.")
        }
        var blobs: [String: String] = [:]
        for entry in response.tree where entry.type == "blob" {
            let name = (entry.path as NSString).lastPathComponent
            if name == ".DS_Store" || name == ".gitkeep" { continue }
            blobs[entry.path] = entry.sha
        }
        return blobs
    }

    private func fetchBlob(_ sha: String) async throws -> Data {
        struct Blob: Decodable { var content: String; var encoding: String }
        let blob: Blob = try await request("git/blobs/\(sha)")
        guard blob.encoding == "base64", let data = Data(base64Encoded: blob.content, options: .ignoreUnknownCharacters) else {
            throw SyncError.failed("GitHub returned a file Perch couldn't decode.")
        }
        return data
    }

    private func createBlob(_ data: Data) async throws -> String {
        struct Body: Encodable { var content: String; var encoding = "base64" }
        struct Reply: Decodable { var sha: String }
        let reply: Reply = try await request("git/blobs", method: "POST", body: Body(content: data.base64EncodedString()))
        return reply.sha
    }

    private func createTree(base: String, entries: [TreeEntry]) async throws -> String {
        struct Body: Encodable { var base_tree: String; var tree: [TreeBody] }
        struct TreeBody: Encodable {
            var path: String, mode: String, type: String, sha: String?
            enum CodingKeys: String, CodingKey { case path, mode, type, sha }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(path, forKey: .path)
                try container.encode(mode, forKey: .mode)
                try container.encode(type, forKey: .type)
                // GitHub deletes a path when `sha` is explicitly null.
                try container.encode(sha, forKey: .sha)
            }
        }
        struct Reply: Decodable { var sha: String }
        let body = Body(base_tree: base, tree: entries.map { TreeBody(path: $0.path, mode: "100644", type: "blob", sha: $0.sha) })
        let reply: Reply = try await request("git/trees", method: "POST", body: body)
        return reply.sha
    }

    private func createCommit(message: String, tree: String, parent: String) async throws -> String {
        struct Author: Encodable { var name: String; var email: String }
        struct Body: Encodable { var message: String; var tree: String; var parents: [String]; var author: Author }
        struct Reply: Decodable { var sha: String }
        let reply: Reply = try await request(
            "git/commits", method: "POST",
            body: Body(message: message, tree: tree, parents: [parent], author: Author(name: authorName, email: authorEmail))
        )
        return reply.sha
    }

    private func updateHead(to commit: String) async throws {
        struct Body: Encodable { var sha: String; var force = false }
        let _: [String: JSONValue] = try await request("git/refs/heads/\(configuration.branch)", method: "PATCH", body: Body(sha: commit))
    }

    private func request<T: Decodable>(_ path: String, method: String = "GET") async throws -> T {
        try await request(path, method: method, body: Optional<String>.none)
    }

    private func request<T: Decodable, B: Encodable>(_ path: String, method: String = "GET", body: B?) async throws -> T {
        var url = baseURL.absoluteString + "/repos/\(configuration.owner)/\(configuration.repository)/" + path
        url = url.replacingOccurrences(of: " ", with: "%20")
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw SyncError.authentication }
        guard (200..<300).contains(status) else {
            let detail = String(decoding: data.prefix(300), as: UTF8.self)
            throw SyncError.failed("GitHub returned HTTP \(status): \(detail)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func loadState() -> State? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(State.self, from: data)
    }

    private func saveState(_ state: State) {
        try? FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
    }
}

/// Decodes arbitrary JSON, for API replies where only a couple of fields matter.
public enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
