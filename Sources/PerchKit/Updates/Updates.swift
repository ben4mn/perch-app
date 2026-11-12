import Foundation

/// A release number such as 0.2.0, compared part by part as numbers, so 0.10 comes after 0.9.
public struct Version: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    /// Accepts "0.2.0", "v0.2.0" and "0.2" (the same as 0.2.0). Anything else is nil.
    public init?(_ text: String) {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(pieces.count) else { return nil }
        var parts: [Int] = []
        for piece in pieces {
            guard let number = Int(piece), number >= 0 else { return nil }
            parts.append(number)
        }
        while parts.count < 3 { parts.append(0) }
        while parts.count > 3, parts.last == 0 { parts.removeLast() }
        self.parts = parts
    }

    public static func < (lhs: Version, rhs: Version) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let a = index < lhs.parts.count ? lhs.parts[index] : 0
            let b = index < rhs.parts.count ? rhs.parts[index] : 0
            if a != b { return a < b }
        }
        return false
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }
}

/// Finds out whether a newer Perch has been released. Releases are GitHub releases of the Perch
/// repository, each carrying the Mac app as `Perch-<version>.zip` and its changelog section as notes.
/// The repository may be private, so the check signs in with the Perch account's token; that works once
/// Perch's GitHub App is installed on the repository.
public struct UpdateChecker: Sendable {
    public struct Update: Equatable, Sendable {
        public var version: Version
        public var notes: String
        /// The API address of the zip, which downloads with the account's token.
        public var download: URL
        public var page: URL?
        public var size: Int
    }

    public enum Result: Equatable, Sendable {
        case upToDate
        case available(Update)
        /// GitHub won't show the repository to this account: Perch's GitHub App isn't installed on it.
        case noAccess
    }

    public var repository: String
    public var session: URLSession

    /// - Parameter repository: "owner/name", from the build (`PerchConfiguration.updateRepository`).
    public init(repository: String, session: URLSession = .shared) {
        self.repository = repository
        self.session = session
    }

    public func check(current: String, token: String) async throws -> Result {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        if status == 401 { throw SyncError.authentication }
        if status == 404 || status == 403 { return .noAccess }
        guard status < 400 else { throw SyncError.failed("GitHub couldn't say whether there's an update (HTTP \(status)).") }
        let release = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard let tag = release["tag_name"] as? String, let latest = Version(tag),
              let installed = Version(current), latest > installed else { return .upToDate }
        let assets = release["assets"] as? [[String: Any]] ?? []
        guard let asset = assets.first(where: { (($0["name"] as? String) ?? "").hasPrefix("Perch") && (($0["name"] as? String) ?? "").hasSuffix(".zip") }),
              let download = (asset["url"] as? String).flatMap(URL.init(string:)) else { return .upToDate }
        return .available(Update(
            version: latest, notes: (release["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            download: download, page: (release["html_url"] as? String).flatMap(URL.init(string:)), size: asset["size"] as? Int ?? 0
        ))
    }

    /// Downloads the update's zip into a folder. GitHub answers with a redirect to its file store, which
    /// must not be sent the token, so it is dropped when the redirect leaves github.com.
    public func download(_ update: Update, token: String, into folder: URL) async throws -> URL {
        var request = URLRequest(url: update.download)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 300
        let (file, response) = try await session.download(for: request, delegate: RedirectWithoutToken())
        guard ((response as? HTTPURLResponse)?.statusCode ?? 200) < 400 else { throw SyncError.failed("The update didn't download.") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent("Perch-\(update.version).zip")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: file, to: destination)
        return destination
    }
}

private final class RedirectWithoutToken: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        var request = request
        if let host = request.url?.host, !host.hasSuffix("github.com") { request.setValue(nil, forHTTPHeaderField: "Authorization") }
        return request
    }
}

/// CHANGELOG.md: a "## <version> (<date>)" heading per release, newest first, with "- " lines under it.
public enum Changelog {
    public struct Release: Equatable, Sendable, Identifiable {
        public var version: String
        public var date: String?
        public var items: [String]
        public var id: String { version }
    }

    public static func parse(_ markdown: String) -> [Release] {
        var releases: [Release] = []
        for line in markdown.components(separatedBy: .newlines) {
            if let heading = heading(line) {
                releases.append(Release(version: heading.version, date: heading.date, items: []))
            } else if !releases.isEmpty, line.hasPrefix("- ") {
                releases[releases.count - 1].items.append(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            }
        }
        return releases
    }

    /// The lines under one release's heading, as the notes for its GitHub release.
    public static func notes(for version: String, in markdown: String) -> String? {
        var lines: [String] = []
        var inside = false
        for line in markdown.components(separatedBy: .newlines) {
            if let heading = heading(line) {
                if inside { break }
                inside = Version(heading.version) == Version(version)
            } else if inside {
                lines.append(line)
            }
        }
        guard inside || !lines.isEmpty else { return nil }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func heading(_ line: String) -> (version: String, date: String?)? {
        guard line.hasPrefix("## ") else { return nil }
        let rest = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
        let version = rest.prefix { $0.isNumber || $0 == "." || $0 == "v" }
        guard Version(String(version)) != nil else { return nil }
        var date: String?
        if let open = rest.firstIndex(of: "("), let close = rest.firstIndex(of: ")"), open < close {
            date = String(rest[rest.index(after: open)..<close])
        }
        return (String(version).trimmingCharacters(in: CharacterSet(charactersIn: "vV")), date)
    }
}

#if os(macOS)
/// Puts a downloaded Perch in place of the installed one. Nothing is replaced unless the download is
/// this app at the version that was offered.
public enum UpdateInstaller {
    public static func install(zip: URL, replacing app: URL, bundleID: String, version: Version) throws {
        let manager = FileManager.default
        // Unpack beside the app, so the swap is a rename on the same disk.
        let work = app.deletingLastPathComponent().appendingPathComponent(".perch-update-\(UUID().uuidString)")
        try manager.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: work) }

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, work.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw SyncError.failed("The update couldn't be unpacked.") }

        guard let unpacked = try manager.contentsOfDirectory(at: work, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }) else {
            throw SyncError.failed("The update has no app in it.")
        }
        let info = NSDictionary(contentsOf: unpacked.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
        guard info["CFBundleIdentifier"] as? String == bundleID else { throw SyncError.failed("The download isn't Perch, so nothing was changed.") }
        guard (info["CFBundleShortVersionString"] as? String).flatMap(Version.init) == version else {
            throw SyncError.failed("The download isn't Perch \(version), so nothing was changed.")
        }
        _ = try manager.replaceItemAt(app, withItemAt: unpacked)
    }
}
#endif

/// When Perch looks for, and moves to, a new version by itself. See AutoUpdateTests.
public enum AutoUpdate {
    /// How often to look while Perch stays open, besides at launch.
    public static let checkEvery: TimeInterval = 3 * 3600
    /// How long Perch must have been in the background before it restarts onto a downloaded update.
    public static let quietFor: TimeInterval = 60

    public static func dueForCheck(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) > checkEvery
    }

    /// Never while Perch is the app in front; once it has been behind other apps for `quietFor`.
    public static func canRestart(isActive: Bool, inactiveSince: Date?, now: Date) -> Bool {
        guard !isActive, let inactiveSince else { return false }
        return now.timeIntervalSince(inactiveSince) > quietFor
    }
}
