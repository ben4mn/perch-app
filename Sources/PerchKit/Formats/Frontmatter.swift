import Foundation

/// A Markdown file split into its YAML frontmatter and body, without changing any bytes.
public struct MarkdownDocument: Equatable, Sendable {
    /// Everything from the opening `---` through the closing `---` line ending, or "".
    public var rawFrontmatter: String
    public var body: String

    public init(rawFrontmatter: String = "", body: String) {
        self.rawFrontmatter = rawFrontmatter
        self.body = body
    }

    public init(text: String) {
        var offset = text.utf8.startIndex
        let utf8 = text.utf8
        func lineEnd(from start: String.UTF8View.Index) -> String.UTF8View.Index {
            utf8[start...].firstIndex(of: 0x0A).map { utf8.index(after: $0) } ?? utf8.endIndex
        }
        func lineText(_ start: String.UTF8View.Index, _ end: String.UTF8View.Index) -> String {
            var line = String(decoding: utf8[start..<end], as: UTF8.self)
            while line.utf8.last == 0x0A || line.utf8.last == 0x0D { line = String(decoding: line.utf8.dropLast(), as: UTF8.self) }
            return line
        }
        let firstEnd = lineEnd(from: offset)
        guard lineText(offset, firstEnd) == "---" else {
            self.init(rawFrontmatter: "", body: text)
            return
        }
        offset = firstEnd
        while offset < utf8.endIndex {
            let end = lineEnd(from: offset)
            if lineText(offset, end) == "---" {
                self.init(
                    rawFrontmatter: String(decoding: utf8[utf8.startIndex..<end], as: UTF8.self),
                    body: String(decoding: utf8[end...], as: UTF8.self)
                )
                return
            }
            offset = end
        }
        self.init(rawFrontmatter: "", body: text)
    }

    public var text: String { rawFrontmatter + body }

    public var fields: FrontmatterFields {
        get { FrontmatterFields(raw: rawFrontmatter) }
        set { rawFrontmatter = newValue.isEmpty ? "" : newValue.raw }
    }
}

/// An ordered, simple YAML mapping. Keys Perch doesn't know about keep their exact lines.
public struct FrontmatterFields: Equatable, Sendable {
    private enum Entry: Equatable, Sendable {
        /// `key` is nil for comments, blank lines, and continuation lines.
        case line(key: String?, raw: String)
    }

    private var entries: [Entry] = []

    public init() {}

    public init(raw: String) {
        guard !raw.isEmpty else { return }
        var lines = splitLines(raw)
        if lines.last == "" { lines.removeLast() }
        guard lines.count >= 2 else { return }
        for line in lines[1..<(lines.count - 1)] {
            let cleaned = line.hasSuffix("\r") ? String(line.dropLast()) : line
            if let key = Self.key(of: cleaned) {
                entries.append(.line(key: key, raw: cleaned))
            } else {
                entries.append(.line(key: nil, raw: cleaned))
            }
        }
    }

    private static func key(of line: String) -> String? {
        guard let first = line.first, first != " ", first != "\t", first != "#", first != "-" else { return nil }
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let after = line.index(after: colon)
        guard after == line.endIndex || line[after] == " " else { return nil }
        return String(line[..<colon])
    }

    public var isEmpty: Bool { entries.isEmpty }

    public var keys: [String] {
        entries.compactMap { if case let .line(key?, _) = $0 { return key } else { return nil } }
    }

    public subscript(key: String) -> String? {
        get {
            for entry in entries {
                if case let .line(entryKey?, raw) = entry, entryKey == key {
                    let value = jsTrim(String(raw.dropFirst(key.count + 1)))
                    return value.isEmpty ? nil : Self.unquote(value)
                }
            }
            return nil
        }
        set {
            let replacement = newValue.map { "\(key): \(Self.quoteIfNeeded($0))" }
            if let index = entries.firstIndex(where: { if case let .line(entryKey?, _) = $0 { return entryKey == key } else { return false } }) {
                if let replacement {
                    entries[index] = .line(key: key, raw: replacement)
                } else {
                    entries.remove(at: index)
                    removeContinuation(at: index)
                }
            } else if let replacement {
                entries.append(.line(key: key, raw: replacement))
            }
        }
    }

    /// Reads `key: [a, b]` or a block list of `- a` lines.
    public func list(_ key: String) -> [String] {
        guard let index = entries.firstIndex(where: { if case let .line(entryKey?, _) = $0 { return entryKey == key } else { return false } }),
              case let .line(_, raw) = entries[index] else { return [] }
        let value = jsTrim(String(raw.dropFirst(key.count + 1)))
        if value.hasPrefix("["), value.hasSuffix("]") {
            return value.dropFirst().dropLast().split(separator: ",").map { Self.unquote(jsTrim(String($0))) }.filter { !$0.isEmpty }
        }
        if !value.isEmpty { return [Self.unquote(value)] }
        var items: [String] = []
        for entry in entries[(index + 1)...] {
            guard case let .line(entryKey, line) = entry, entryKey == nil else { break }
            let trimmed = jsTrim(line)
            guard trimmed.hasPrefix("- ") else { break }
            items.append(Self.unquote(jsTrim(String(trimmed.dropFirst(2)))))
        }
        return items
    }

    public mutating func setList(_ key: String, _ values: [String]) {
        self[key] = nil
        guard !values.isEmpty else { return }
        let rendered = values.map(Self.quoteIfNeeded).joined(separator: ", ")
        entries.append(.line(key: key, raw: "\(key): [\(rendered)]"))
    }

    private mutating func removeContinuation(at index: Int) {
        while index < entries.count, case let .line(entryKey, line) = entries[index], entryKey == nil, jsTrim(line).hasPrefix("- ") {
            entries.remove(at: index)
        }
    }

    public var raw: String {
        var lines = ["---"]
        for case let .line(_, raw) in entries { lines.append(raw) }
        lines.append("---")
        return lines.joined(separator: "\n") + "\n"
    }

    static func unquote(_ value: String) -> String {
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            let data = Data(value.utf8)
            if let decoded = try? JSONDecoder().decode(String.self, from: data) { return decoded }
            return String(value.dropFirst().dropLast())
        }
        if value.count >= 2, value.hasPrefix("'"), value.hasSuffix("'") {
            return String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return value
    }

    static func quoteIfNeeded(_ value: String) -> String {
        let plainSafe = value.range(of: "^[A-Za-z0-9][A-Za-z0-9 _./+-]*$", options: .regularExpression) != nil
        if plainSafe, value == jsTrim(value) { return value }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let quoted = String(data: data, encoding: .utf8) else { return value }
        return quoted
    }
}
