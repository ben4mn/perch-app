import Foundation

/// Reads who's working in the notebook from the Perch Relay. It never writes.
public struct RelayClient: Sendable {
    public struct Agent: Decodable, Equatable, Sendable {
        public var name: String
        public var status: String
        public var isActive: Bool
        public var path: String?
        public var updated: String
        /// The session the agent is working in, as the Relay last heard it from the agent's bridge.
        public var link: String?

        /// The link, when it is one Perch opens.
        public var sessionLink: URL? { link.flatMap(SessionLink.url) }
    }

    /// Something an agent did recently: set a status, claimed or released a file, wrote, or left a message.
    public struct Event: Decodable, Equatable, Sendable {
        public var agent: String
        public var kind: String
        public var text: String
        public var path: String?
        public var at: String
    }

    struct Snapshot: Decodable {
        var agents: [Agent]
        var recent: [Event]?
    }

    public var baseURL: URL
    public var token: String
    public var session: URLSession

    /// Why the Relay didn't answer with the agents.
    public enum Failure: Error, Equatable {
        /// 401 or 403: the token is wrong, or was revoked.
        case refused
        /// Any other status that isn't 200.
        case status(Int)
    }

    public init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        // A pasted token often carries the line break at the end of its file, and the Relay refuses one with it.
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    public func agents() async throws -> [Agent] { try await presence().agents }

    /// Who is here, and what agents did recently (kept by the Relay until it restarts).
    public func presence() async throws -> (agents: [Agent], events: [Event]) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/presence"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw status == 401 || status == 403 ? Failure.refused : Failure.status(status) }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        return (snapshot.agents, snapshot.recent ?? [])
    }

    /// The notebook's Git history, as `git log` prints it with `FileHistory.logArguments`, for each file's
    /// created and last edited dates on a device without Git. Nil when it hasn't changed since `etag`.
    public func history(etag: String?) async throws -> (etag: String, log: String)? {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/history"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        // The answer is the same until the next commit; the ETag decides, not a cache.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        if status == 304 { return nil }
        guard status == 200 else { throw status == 401 || status == 403 ? Failure.refused : Failure.status(status) }
        let tag = http?.value(forHTTPHeaderField: "ETag") ?? ""
        return (tag, String(decoding: data, as: UTF8.self))
    }
}

/// Whether Perch is reading from the Relay, as Settings shows it.
public enum RelayStatus: Equatable, Sendable {
    /// No address or token yet.
    case off
    /// Waiting for the Relay's first answer.
    case connecting
    case connected(agentsHere: Int)
    case refused
    /// Nothing answered at the address.
    case unreachable
    case failed(String)

    public init(error: Error) {
        switch error {
        case RelayClient.Failure.refused: self = .refused
        case let RelayClient.Failure.status(code): self = .failed("HTTP \(code)")
        case let error as URLError where Self.unreachableCodes.contains(error.code): self = .unreachable
        case let error as URLError: self = .failed("network error \(error.code.rawValue)")
        default: self = .failed("unreadable reply")
        }
    }

    private static let unreachableCodes: Set<URLError.Code> = [
        .cannotConnectToHost, .cannotFindHost, .timedOut, .notConnectedToInternet, .networkConnectionLost, .dnsLookupFailed,
    ]

    public var isConnected: Bool { if case .connected = self { true } else { false } }

    public var title: String {
        switch self {
        case .off: "Not connected"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .refused: "Token refused"
        case .unreachable: "Can't reach the Relay"
        case .failed: "Relay error"
        }
    }

    public var detail: String {
        switch self {
        case .off: "Enter the Relay address and an app token, then click Connect."
        case .connecting: "Waiting for the Relay to answer."
        case let .connected(count) where count == 0: "No agents are working right now."
        case let .connected(count) where count == 1: "1 agent is working now."
        case let .connected(count): "\(count) agents are working now."
        case .refused: "The Relay didn't accept this token. Copy it again, paste it and click Connect."
        case .unreachable: "Nothing answered at this address. Check that the Relay is running."
        case let .failed(reason): "The Relay answered with an error (\(reason))."
        }
    }
}
