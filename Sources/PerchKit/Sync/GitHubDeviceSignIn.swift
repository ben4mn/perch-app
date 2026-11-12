import Foundation

/// Signs in to GitHub with a short code, the way TVs and command-line tools do:
/// the app shows a code, you enter it at github.com/login/device, and the app gets a token.
/// Uses Perch's own GitHub App, so the token reaches only the repositories the app is installed on.
public struct GitHubDeviceSignIn: Sendable {
    public struct Code: Equatable, Sendable {
        public var userCode: String
        public var verificationURL: URL
        public var deviceCode: String
        public var interval: Int
        public var expiresAt: Date

        public init(userCode: String, verificationURL: URL, deviceCode: String, interval: Int, expiresAt: Date) {
            self.userCode = userCode
            self.verificationURL = verificationURL
            self.deviceCode = deviceCode
            self.interval = interval
            self.expiresAt = expiresAt
        }
    }

    public struct Token: Codable, Equatable, Sendable {
        public var accessToken: String
        public var refreshToken: String?
        public var expiresAt: Date?
    }

    public enum SignInError: Error, LocalizedError, Equatable {
        case expired, denied, notConfigured
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .expired: return "The code expired. Start again for a new one."
            case .denied: return "Access was declined on GitHub."
            case .notConfigured: return "This build doesn't have Perch's GitHub App set up."
            case let .failed(message): return message
            }
        }
    }

    public var clientID: String
    public var session: URLSession

    public init(clientID: String, session: URLSession = .shared) {
        self.clientID = clientID
        self.session = session
    }

    public func start() async throws -> Code {
        guard !clientID.isEmpty else { throw SignInError.notConfigured }
        let reply = try await retrying { try await post("https://github.com/login/device/code", ["client_id": clientID]) }
        guard let device = reply["device_code"] as? String, let user = reply["user_code"] as? String,
              let uri = (reply["verification_uri"] as? String).flatMap(URL.init(string:)) else {
            throw SignInError.failed((reply["error_description"] as? String) ?? "GitHub didn't return a code.")
        }
        return Code(
            userCode: user, verificationURL: uri, deviceCode: device,
            interval: reply["interval"] as? Int ?? 5,
            expiresAt: Date().addingTimeInterval(TimeInterval(reply["expires_in"] as? Int ?? 900))
        )
    }

    /// Waits until you approve the code on GitHub. Cancel the surrounding task to stop.
    public func waitForApproval(_ code: Code) async throws -> Token {
        var interval = max(code.interval, 1)
        while Date() < code.expiresAt {
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            let reply: [String: Any]
            do {
                reply = try await post("https://github.com/login/oauth/access_token", [
                    "client_id": clientID,
                    "device_code": code.deviceCode,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                ])
            } catch let error as URLError where Self.isTransient(error) {
                // iOS drops connections while you're in Safari approving the code; just ask again.
                continue
            }
            if let token = Self.token(from: reply) { return token }
            switch reply["error"] as? String {
            case "authorization_pending": continue
            case "slow_down": interval = (reply["interval"] as? Int) ?? interval + 5
            case "expired_token": throw SignInError.expired
            case "access_denied": throw SignInError.denied
            default: throw SignInError.failed((reply["error_description"] as? String) ?? "GitHub sign-in failed.")
            }
        }
        throw SignInError.expired
    }

    /// Exchanges a refresh token for a new access token, when GitHub issued one.
    public func refresh(_ token: Token) async throws -> Token {
        guard let refreshToken = token.refreshToken else { return token }
        let reply = try await post("https://github.com/login/oauth/access_token", [
            "client_id": clientID, "grant_type": "refresh_token", "refresh_token": refreshToken,
        ])
        guard let fresh = Self.token(from: reply) else {
            throw SignInError.failed((reply["error_description"] as? String) ?? "Sign in to GitHub again.")
        }
        return fresh
    }

    static func isTransient(_ error: URLError) -> Bool {
        [.networkConnectionLost, .notConnectedToInternet, .timedOut, .cannotConnectToHost,
         .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed, .secureConnectionFailed].contains(error.code)
    }

    /// Runs a request, retrying a few times through dropped connections.
    private func retrying<T>(_ work: () async throws -> T) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await work()
            } catch let error as URLError where Self.isTransient(error) && attempt < 4 {
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
            }
        }
    }

    static func token(from reply: [String: Any]) -> Token? {
        guard let access = reply["access_token"] as? String else { return nil }
        let expires = (reply["expires_in"] as? Int).map { Date().addingTimeInterval(TimeInterval($0)) }
        return Token(accessToken: access, refreshToken: reply["refresh_token"] as? String, expiresAt: expires)
    }

    /// Repositories this sign-in can reach, as "owner/name".
    public func repositories(token: String) async throws -> [String] {
        try await reach(token: token).repositories
    }

    /// Who signed in.
    public struct User: Equatable, Sendable {
        public var login: String
        public var id: Int
        public var name: String?
    }

    public func user(token: String) async throws -> User {
        let reply = try await get("https://api.github.com/user", token: token)
        guard let login = reply["login"] as? String, let id = reply["id"] as? Int else {
            throw SignInError.failed((reply["message"] as? String) ?? "GitHub didn't say who signed in.")
        }
        return User(login: login, id: id, name: reply["name"] as? String)
    }

    /// What Perch's GitHub App can reach for this sign-in, and where to add more.
    public struct Reach: Equatable, Sendable {
        /// "owner/name", sorted without regard to case.
        public var repositories: [String]
        /// The app's name on GitHub, read from an installation. Nil until it is installed somewhere.
        public var appSlug: String?

        public init(repositories: [String], appSlug: String?) {
            self.repositories = repositories
            self.appSlug = appSlug
        }

        /// GitHub's page for installing the app on more repositories.
        public var installURL: URL? { appSlug.flatMap { URL(string: "https://github.com/apps/\($0)/installations/new") } }
    }

    public func reach(token: String) async throws -> Reach {
        let installations = try await get("https://api.github.com/user/installations", token: token)["installations"] as? [[String: Any]] ?? []
        var names: [String] = []
        for installation in installations {
            guard let id = installation["id"] as? Int else { continue }
            let repos = try await get("https://api.github.com/user/installations/\(id)/repositories?per_page=100", token: token)["repositories"] as? [[String: Any]] ?? []
            names += repos.compactMap { $0["full_name"] as? String }
        }
        let slug = installations.lazy.compactMap { $0["app_slug"] as? String }.first
        return Reach(repositories: names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }, appSlug: slug)
    }

    private func get(_ url: String, token: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await retrying { try await session.data(for: request) }
        let reply = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        // A revoked or expired token must say so, not read as an account that can reach nothing.
        switch (response as? HTTPURLResponse)?.statusCode ?? 200 {
        case 401: throw SyncError.authentication
        case 400...: throw SignInError.failed((reply["message"] as? String) ?? "GitHub couldn't answer just now.")
        default: return reply
        }
    }

    private func post(_ url: String, _ form: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+:/")
        request.httpBody = Data(form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }.joined(separator: "&").utf8)
        let (data, _) = try await session.data(for: request)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
