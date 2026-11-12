import Foundation

public struct WikiLink: Equatable, Sendable {
    public var target: String
    public var label: String?
    public var range: Range<String.Index>
}

public struct LinkMention: Equatable, Sendable {
    public var path: String
    public var title: String
    public var range: Range<String.Index>
}

public enum LinkResolution: Equatable, Sendable {
    case note(String)
    case folder(String)
    case ambiguous([String])
    case missing
}

public enum WikiLinks {
    private static let regex = try! NSRegularExpression(pattern: #"\[\[([^\[\]\n|]+)(?:\|([^\[\]\n]+))?\]\]"#)

    /// Finds `[[links]]`, skipping fenced code and inline code.
    public static func parse(_ text: String) -> [WikiLink] {
        let excluded = codeRanges(in: text)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let whole = Range(match.range, in: text), let target = Range(match.range(at: 1), in: text) else { return nil }
            if excluded.contains(where: { $0.overlaps(whole) }) { return nil }
            let label = Range(match.range(at: 2), in: text).map { jsTrim(String(text[$0])) }
            return WikiLink(target: jsTrim(String(text[target])), label: label, range: whole)
        }
    }

    /// Where a click on a link to a note that doesn't exist yet may make that note: beside the note
    /// holding the link, or in a folder under it. Nil when the target isn't a plain name: one that climbs
    /// out with `..`, starts at the root, or names a hidden file. Whatever a page says was clicked, a new
    /// note can only ever land inside the notebook, and never on top of the path of another file.
    public static func pathForNewNote(target: String, besideNoteIn folder: String) -> String? {
        var name = target
        if let hash = name.firstIndex(of: "#") { name = String(name[..<hash]) }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased().hasSuffix(".md") { name = String(name.dropLast(3)) }
        let parts = name.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !name.isEmpty, name.count <= 240, !name.contains("\\"), !name.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }),
              parts.allSatisfy({ !$0.isEmpty && !$0.hasPrefix(".") && $0 == $0.trimmingCharacters(in: .whitespaces) }) else { return nil }
        let cleanFolder = folder == "." ? "" : folder
        return (cleanFolder.isEmpty ? "" : cleanFolder + "/") + parts.joined(separator: "/") + ".md"
    }

    /// Renames a link target everywhere in a text, keeping labels and everything else.
    public static func rewrite(_ text: String, from old: String, to new: String) -> String {
        var result = text
        for link in parse(text).reversed() where link.target.caseInsensitiveCompare(old) == .orderedSame {
            let label = link.label.map { "|\($0)" } ?? ""
            result.replaceSubrange(link.range, with: "[[\(new)\(label)]]")
        }
        return result
    }

    static func codeRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var fenceStart: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let lineEnd = text[index...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[index..<lineEnd]
            let trimmed = line.drop { $0 == " " }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if let start = fenceStart {
                    ranges.append(start..<lineEnd)
                    fenceStart = nil
                } else {
                    fenceStart = index
                }
            } else if fenceStart == nil {
                var inline: String.Index?
                for position in line.indices where line[position] == "`" {
                    if let start = inline {
                        ranges.append(start..<line.index(after: position))
                        inline = nil
                    } else {
                        inline = position
                    }
                }
            }
            index = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
        }
        if let start = fenceStart { ranges.append(start..<text.endIndex) }
        return ranges
    }
}

/// Knows every title, alias, and link in a vault, and answers link questions.
public struct LinkIndex: Sendable {
    private var byKey: [String: Set<String>] = [:]
    private var titles: [String: String] = [:]
    private var folders: Set<String> = []
    private var outgoing: [String: [String]] = [:]
    private var incoming: [String: Set<String>] = [:]
    private var mentionKeys: [(key: String, path: String, title: String)] = []

    /// Titles too common to link automatically.
    public static let genericTitles: Set<String> = [
        "readme", "notes", "note", "index", "todo", "tasks", "untitled", "draft", "ideas", "meeting", "meetings", "misc", "home", "agents", "claude",
    ]

    public init(entries: [(file: VaultFile, text: String?)]) {
        var keyCounts: [String: Int] = [:]
        for (file, text) in entries where file.kind != .attachment && file.kind != .other {
            titles[file.path] = file.title
            add(key: file.title, path: file.path)
            add(key: stripExtension(file.path), path: file.path)
            keyCounts[file.title.lowercased(), default: 0] += 1
            var folder = file.folder
            while !folder.isEmpty, folder != "." {
                folders.insert(folder.lowercased())
                folder = (folder as NSString).deletingLastPathComponent
            }
            if let text {
                for alias in MarkdownDocument(text: text).fields.list("aliases") {
                    add(key: alias, path: file.path)
                }
            }
        }
        for (file, text) in entries {
            guard let text, file.kind == .note || file.kind == .task || file.kind == .board else { continue }
            let targets = WikiLinks.parse(text).compactMap { link -> String? in
                if case let .note(path) = resolve(link.target, from: file.path) { return path }
                return nil
            }
            outgoing[file.path] = targets
            for target in targets { incoming[target, default: []].insert(file.path) }
        }

        // Only unambiguous, specific names can link automatically. Task files only link by alias.
        var mentions: [(String, String, String)] = []
        for (key, paths) in byKey where paths.count == 1 {
            guard let path = paths.first, !key.contains("/"), key.count >= 4, !Self.genericTitles.contains(key),
                  VaultFile.classify(path) != .task || key != titles[path]?.lowercased() else { continue }
            mentions.append((key, path, titles[path] ?? key))
        }
        // Longest first, so "Pat Quill" beats "Pat".
        mentionKeys = mentions.sorted { $0.0.count > $1.0.count }.map { (key: $0.0, path: $0.1, title: $0.2) }
    }

    private mutating func add(key: String, path: String) {
        byKey[key.lowercased(), default: []].insert(path)
    }

    private func stripExtension(_ path: String) -> String {
        for suffix in [".kanban.md", ".excalidraw.svg", ".excalidraw", ".md"] where path.lowercased().hasSuffix(suffix) {
            return String(path.dropLast(suffix.count))
        }
        return path
    }

    public func resolve(_ target: String, from source: String? = nil) -> LinkResolution {
        var key = target.lowercased()
        if key.hasSuffix(".md") { key = String(key.dropLast(3)) }
        if let paths = byKey[key] {
            if paths.count == 1 { return .note(paths.first!) }
            // Prefer the candidate closest to the note holding the link.
            if let source {
                let folder = (source as NSString).deletingLastPathComponent
                let nearby = paths.filter { ($0 as NSString).deletingLastPathComponent == folder }
                if nearby.count == 1 { return .note(nearby.first!) }
            }
            return .ambiguous(paths.sorted())
        }
        if folders.contains(key) { return .folder(target) }
        return .missing
    }

    public func backlinks(to path: String) -> [String] {
        (incoming[path] ?? []).sorted()
    }

    public func outgoingLinks(from path: String) -> [String] {
        outgoing[path] ?? []
    }

    /// Titles for `[[` autocomplete, most specific matches first.
    public func completions(for query: String, limit: Int = 12) -> [(title: String, path: String)] {
        let lower = query.lowercased()
        let matches = titles.filter { lower.isEmpty || $0.value.lowercased().contains(lower) }
        return matches
            .map { (title: $0.value, path: $0.key) }
            .sorted {
                let a = $0.title.lowercased().hasPrefix(lower), b = $1.title.lowercased().hasPrefix(lower)
                if a != b { return a }
                return $0.title.count < $1.title.count
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Finds known names in text. This reads only and never changes the file.
    ///
    /// Longer names win over shorter ones that overlap them, a name only counts as a whole word, and
    /// nothing is found inside code, existing links or frontmatter. Built to stay quick on a long note in
    /// a notebook of thousands of titles: only names whose every word occurs in the note are searched for.
    /// - Parameter isCancelled: asked between names; answering true ends the search with nothing found.
    public func mentions(in text: String, excluding source: String? = nil, isCancelled: () -> Bool = { false }) -> [LinkMention] {
        guard !mentionKeys.isEmpty, !text.isEmpty else { return [] }
        var excluded = WikiLinks.codeRanges(in: text) + WikiLinks.parse(text).map(\.range)
        let frontmatter = MarkdownDocument(text: text).rawFrontmatter
        if !frontmatter.isEmpty, let body = text.range(of: frontmatter) { excluded.append(body) }

        // Everything below counts in UTF-16 units of a copy held as UTF-16, where searching is quick.
        let units = NSMutableString(string: text)
        let length = units.length
        var taken = Intervals(excluded.map { NSRange($0, in: text) })
        let words = Self.words(in: text.lowercased())
        var found: [(range: NSRange, entry: Int)] = []

        for (number, entry) in mentionKeys.enumerated() where entry.path != source {
            // A name can only be in the note if each of its words is. Names with letters outside ASCII are
            // always searched for: lowercasing and case-blind comparison don't always agree on those.
            if entry.key.utf8.allSatisfy({ $0 < 0x80 }), !Self.words(in: entry.key).isSubset(of: words) { continue }
            if isCancelled() { return [] }
            var start = 0
            while start < length {
                let range = units.range(of: entry.key, options: .caseInsensitive, range: NSRange(location: start, length: length - start))
                guard range.location != NSNotFound, range.length > 0 else { break }
                start = range.location + range.length
                guard let whole = Range(range, in: text) else { continue }
                let beforeOK = whole.lowerBound == text.startIndex || !text[text.index(before: whole.lowerBound)].isWordLike
                let afterOK = whole.upperBound == text.endIndex || !text[whole.upperBound].isWordLike
                guard beforeOK, afterOK, taken.insertIfFree(range) else { continue }
                found.append((range, number))
            }
        }
        return found.sorted { $0.range.location < $1.range.location }.compactMap { item in
            guard let range = Range(item.range, in: text) else { return nil }
            return LinkMention(path: mentionKeys[item.entry].path, title: mentionKeys[item.entry].title, range: range)
        }
    }

    /// The runs of letters and digits in lowercased text.
    private static func words(in lowercased: String) -> Set<Substring> {
        Set(lowercased.split(whereSeparator: { !($0.isLetter || $0.isNumber) }))
    }

    /// The search as it was first written: every name looked for in the whole note. Kept as the
    /// definition of what `mentions(in:)` must answer; the tests compare the two.
    func mentionsBySearchingForEveryName(in text: String, excluding source: String? = nil) -> [LinkMention] {
        var excluded = WikiLinks.codeRanges(in: text) + WikiLinks.parse(text).map(\.range)
        if let body = MarkdownDocument(text: text).rawFrontmatter.isEmpty ? nil : text.range(of: MarkdownDocument(text: text).rawFrontmatter) {
            excluded.append(body)
        }
        var found: [LinkMention] = []
        for entry in mentionKeys where entry.path != source {
            var searchStart = text.startIndex
            while let range = text.range(of: entry.key, options: .caseInsensitive, range: searchStart..<text.endIndex) {
                searchStart = range.upperBound
                let beforeOK = range.lowerBound == text.startIndex || !text[text.index(before: range.lowerBound)].isWordLike
                let afterOK = range.upperBound == text.endIndex || !text[range.upperBound].isWordLike
                guard beforeOK, afterOK else { continue }
                if excluded.contains(where: { $0.overlaps(range) }) { continue }
                if found.contains(where: { $0.range.overlaps(range) }) { continue }
                found.append(LinkMention(path: entry.path, title: entry.title, range: range))
            }
        }
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }
}

/// Stretches of text that are spoken for, kept in order so asking about one more is quick.
private struct Intervals {
    /// Sorted by start, none overlapping or touching another.
    private var spans: [(low: Int, high: Int)] = []

    init(_ ranges: [NSRange]) {
        for range in ranges.filter({ $0.location != NSNotFound && $0.length > 0 }).sorted(by: { $0.location < $1.location }) {
            let high = range.location + range.length
            if let last = spans.last, range.location <= last.high { spans[spans.count - 1].high = max(last.high, high) }
            else { spans.append((range.location, high)) }
        }
    }

    /// Adds the range and answers true, unless it overlaps one already here.
    mutating func insertIfFree(_ range: NSRange) -> Bool {
        let low = range.location, high = range.location + range.length
        // The first span that ends after this range starts.
        var from = 0, to = spans.count
        while from < to {
            let middle = (from + to) / 2
            if spans[middle].high <= low { from = middle + 1 } else { to = middle }
        }
        if from < spans.count, spans[from].low < high { return false }
        spans.insert((low, high), at: from)
        return true
    }
}

private extension Character {
    var isWordLike: Bool { isLetter || isNumber || self == "_" || self == "-" }
}
