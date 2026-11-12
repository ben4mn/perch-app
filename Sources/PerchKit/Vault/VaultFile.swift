import Foundation

public enum VaultFileKind: String, Codable, Sendable {
    case note, task, board, whiteboard, notebook, attachment, other
}

public struct VaultFile: Identifiable, Hashable, Sendable {
    /// Path relative to the vault root, using `/`.
    public var path: String
    public var kind: VaultFileKind
    /// When this copy of the file was last written to disk. It decides when the file is read again.
    public var modified: Date?
    /// When the file was first added to the notebook: from Git's history, else from disk.
    public var created: Date?
    /// When the file's contents last changed, from Git's history. See `lastEdited`.
    public var edited: Date?

    /// When the contents last changed: Git's date, or the disk's for a file Git doesn't know yet.
    public var lastEdited: Date? { edited ?? modified }

    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }
    public var folder: String { (path as NSString).deletingLastPathComponent }

    /// The title NotesHub shows: the file name without its format suffixes.
    public var title: String {
        for suffix in [".kanban.md", ".excalidraw.svg", ".excalidraw", ".md"] where name.lowercased().hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    public init(path: String, kind: VaultFileKind? = nil, modified: Date? = nil, created: Date? = nil, edited: Date? = nil) {
        self.path = path
        self.kind = kind ?? VaultFile.classify(path)
        self.modified = modified
        self.created = created
        self.edited = edited
    }

    public static func classify(_ path: String) -> VaultFileKind {
        let lower = path.lowercased()
        if path.split(separator: "/").contains(".attachments") { return .attachment }
        if lower.hasSuffix(".kanban.md") { return .board }
        if lower.hasSuffix(".excalidraw.svg") || lower.hasSuffix(".excalidraw") { return .whiteboard }
        if lower.hasSuffix(".ipynb") { return .notebook }
        if lower.hasSuffix(".md") {
            return path.split(separator: "/").dropLast().last == "Tasks" ? .task : .note
        }
        return .other
    }
}

/// A folder of plain files. It reads and writes the files directly and keeps no database.
public struct Vault: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root.standardizedFileURL }

    public func url(for path: String) -> URL { root.appendingPathComponent(path) }

    public func scan() throws -> [VaultFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .creationDateKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: []) else {
            return []
        }
        let rootPath = root.resolvingSymlinksInPath().path
        var files: [VaultFile] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name == ".git" {
                enumerator.skipDescendants()
                continue
            }
            // Calling skipDescendants on a file would skip its siblings too.
            if name == ".DS_Store" || name == ".gitkeep" { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            let full = url.resolvingSymlinksInPath().path
            guard full.hasPrefix(rootPath + "/") else { continue }
            files.append(VaultFile(
                path: String(full.dropFirst(rootPath.count + 1)),
                modified: values?.contentModificationDate, created: values?.creationDate
            ))
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    public func read(_ path: String) throws -> String {
        try String(contentsOf: url(for: path), encoding: .utf8)
    }

    public func readData(_ path: String) throws -> Data {
        try Data(contentsOf: url(for: path))
    }

    /// Writes atomically, so a crash can't leave a half-written note.
    public func write(_ text: String, to path: String) throws {
        let target = url(for: path)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: target, options: .atomic)
    }

    public func writeData(_ data: Data, to path: String) throws {
        let target = url(for: path)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
    }

    public func move(_ path: String, to newPath: String) throws {
        let target = url(for: newPath)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: url(for: path), to: target)
    }

    public func delete(_ path: String) throws {
        try FileManager.default.removeItem(at: url(for: path))
    }

    public func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: path).path)
    }
}
