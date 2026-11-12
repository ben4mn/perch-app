import Foundation

/// When a file in the notebook was created and last edited, from the notebook's Git history.
///
/// A file's own dates on disk only say when this copy was written: a fresh clone, or the iPhone's first
/// sync, makes every file look new. Git remembers when each one was really added and changed.
public struct FileDates: Equatable, Codable, Sendable {
    public var created: Date
    public var edited: Date

    public init(created: Date, edited: Date) {
        self.created = created
        self.edited = edited
    }
}

public enum FileHistory {
    /// The `git log` arguments whose output `parse` reads. The Relay runs the same command, so the
    /// iPhone, which has no Git, parses exactly what the Mac does.
    ///
    /// - `--no-merges`: a merge only joins changes already made in the commits it merges.
    /// - `-M`: a moved or renamed file keeps the dates it had before.
    /// - `%at`: the author's time, when the change was written, not when it was synced.
    public static let logArguments = [
        "-c", "core.quotepath=off", "log", "-M", "--no-merges", "--format=%x1e%at", "--name-status",
    ]

    /// Reads `git log` output made with `logArguments`, newest commit first, into each file's dates,
    /// keyed by its path now.
    ///
    /// A move or rename (a 100% match) is neither an edit nor a new file: the file carries its old
    /// path's history with it. A file that was deleted and added again starts over from that add.
    public static func parse(_ log: String) -> [String: FileDates] {
        var created: [String: Date] = [:]
        var edited: [String: Date] = [:]
        /// An older path, and the path that file has now.
        var renamed: [String: String] = [:]
        /// Files whose first commit has been reached: anything older at their path is a different file.
        var born: Set<String> = []

        for record in log.split(separator: "\u{1e}", omittingEmptySubsequences: true) {
            var lines = record.split(separator: "\n", omittingEmptySubsequences: true).makeIterator()
            guard let stamp = lines.next(), let seconds = TimeInterval(stamp.trimmingCharacters(in: .whitespaces)) else { continue }
            let date = Date(timeIntervalSince1970: seconds)
            while let line = lines.next() {
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 2, let status = fields.first?.first else { continue }
                let isRename = status == "R" || status == "C"
                let path = unquote(isRename && fields.count >= 3 ? fields[2] : fields[1])
                let current = renamed[path] ?? path
                if status == "D" {
                    // Deleted here; what came before belongs to the file that was deleted, unless a later
                    // commit put a file back at this path (then that one is already born).
                    born.insert(current)
                    continue
                }
                guard !born.contains(current) else { continue }
                let isMove = status == "R" && fields[0].dropFirst() == "100"
                if !isMove, edited[current] == nil { edited[current] = date }
                created[current] = date
                switch status {
                case "A", "C":
                    born.insert(current)
                case "R":
                    renamed[unquote(fields[1])] = current
                default:
                    break
                }
            }
        }
        var result: [String: FileDates] = [:]
        for (path, made) in created {
            // A file only ever moved since it was added has the date it was added as its edit.
            result[path] = FileDates(created: made, edited: edited[path] ?? made)
        }
        return result
    }

    /// Git quotes a path holding a double quote, a backslash or a control character, as in C.
    static func unquote(_ path: String) -> String {
        guard path.count >= 2, path.hasPrefix("\""), path.hasSuffix("\"") else { return path }
        var bytes: [UInt8] = []
        var characters = Array(path.dropFirst().dropLast().utf8)[...]
        while let byte = characters.popFirst() {
            guard byte == UInt8(ascii: "\\"), let next = characters.popFirst() else {
                bytes.append(byte)
                continue
            }
            switch next {
            case UInt8(ascii: "n"): bytes.append(10)
            case UInt8(ascii: "t"): bytes.append(9)
            case UInt8(ascii: "r"): bytes.append(13)
            case UInt8(ascii: "a"): bytes.append(7)
            case UInt8(ascii: "b"): bytes.append(8)
            case UInt8(ascii: "f"): bytes.append(12)
            case UInt8(ascii: "v"): bytes.append(11)
            case UInt8(ascii: "0") ... UInt8(ascii: "7"):
                var value = Int(next - UInt8(ascii: "0"))
                for _ in 0 ..< 2 {
                    guard let digit = characters.first, (UInt8(ascii: "0") ... UInt8(ascii: "7")).contains(digit) else { break }
                    characters.removeFirst()
                    value = value * 8 + Int(digit - UInt8(ascii: "0"))
                }
                bytes.append(UInt8(truncatingIfNeeded: value))
            default: bytes.append(next)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Puts the history's dates on freshly scanned files.
    ///
    /// - `edited` comes from the history, unless the file has changes not committed yet (`uncommitted`),
    ///   when the time it was saved on disk is the truth.
    /// - A file not in the history yet (new, not synced) keeps its dates from disk.
    public static func apply(_ dates: [String: FileDates], uncommitted: Set<String> = [], to files: [VaultFile]) -> [VaultFile] {
        guard !dates.isEmpty else { return files }
        return files.map { file in
            guard let known = dates[file.path] else { return file }
            var dated = file
            dated.created = known.created
            if uncommitted.contains(file.path), let saved = file.modified, saved > known.edited {
                dated.edited = saved
            } else {
                dated.edited = known.edited
            }
            return dated
        }
    }
}
