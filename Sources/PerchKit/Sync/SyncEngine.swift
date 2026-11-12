import Foundation

public struct SyncResult: Equatable, Sendable {
    public var pulled = 0
    public var pushed = 0
    public var conflicts: [String] = []
    public init() {}
}

public enum SyncError: Error, LocalizedError, Equatable {
    case failed(String)
    case authentication
    case notConfigured
    /// The Keychain didn't hand over the saved sign-in (Deny, a closed dialog, a locked Keychain). Not the
    /// same as signed out: the sign-in is still there.
    case keychainRefused

    public var errorDescription: String? {
        switch self {
        case let .failed(message): return message
        case .authentication: return "GitHub rejected your token. Check it in Settings."
        case .notConfigured: return "Sync isn't set up for this notebook."
        case .keychainRefused: return "The Keychain didn't let Perch read its GitHub sign-in, so it isn't syncing. Quit and reopen Perch to be asked again."
        }
    }
}

public protocol SyncEngine: Sendable {
    func sync() async throws -> SyncResult
}

/// What to do with a file both sides changed.
enum MergePolicy {
    /// Boards and whiteboards can't hold conflict blocks without damage, so they keep both copies.
    static func usesCopy(_ path: String) -> Bool {
        switch VaultFile.classify(path) {
        case .note, .task: return false
        default: return true
        }
    }

    static func conflictCopyPath(_ path: String, date: String) -> String {
        let name = VaultFile(path: path).name
        let suffixes = [".kanban.md", ".excalidraw.svg", ".excalidraw"]
        let folder = (path as NSString).deletingLastPathComponent
        let pathExtension = (name as NSString).pathExtension
        let suffix = suffixes.first { name.lowercased().hasSuffix($0) } ?? (pathExtension.isEmpty ? "" : "." + pathExtension)
        let base = String(name.dropLast(suffix.count))
        let copy = "\(base) (conflict \(date))\(suffix)"
        return folder.isEmpty ? copy : "\(folder)/\(copy)"
    }
}
