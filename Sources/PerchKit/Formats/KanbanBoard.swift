import Foundation

/// Reads and writes NotesHub `*.kanban.md` files.
///
/// This mirrors the parser and serializer in NotesHub's `noteshub-skills/kanban.py` (MIT),
/// so a board saved here matches what NotesHub itself writes.
public struct KanbanCard: Equatable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var title: String
    public var isCompleted = false
    public var details = ""
    /// Normalized `yyyy-MM-dd` date, or nil.
    public var dueDate: String?
    public var tags: [String] = []
    public var mentions: [String] = []
    public var estimateValue: Int?
    public var estimateUnit: String?

    public init(title: String) { self.title = title }

    public var taskCounts: (total: Int, completed: Int) {
        guard !details.isEmpty else { return (0, 0) }
        var total = 0, completed = 0
        for line in details.components(separatedBy: "\n") {
            guard let match = KanbanCodec.taskRegex.firstMatch(in: line) else { continue }
            total += 1
            if match[1] != " " { completed += 1 }
        }
        return (total, completed)
    }
}

public struct KanbanList: Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var cards: [KanbanCard]
    public init(name: String, cards: [KanbanCard] = []) {
        self.name = name
        self.cards = cards
    }
}

public struct KanbanBoard: Equatable, Sendable {
    public var lists: [KanbanList]
    public init(lists: [KanbanList] = []) { self.lists = lists }
}

public struct KanbanParseResult: Sendable {
    public var board: KanbanBoard
    /// Lines NotesHub ignores, and would drop on its next save.
    public var droppedLines: [(line: Int, text: String)]
}

public enum KanbanCodec {
    private static let dot = "[^\\n\\r\\u2028\\u2029]"
    fileprivate static let columnRegex = LineRegex("^#{2,4} (\(dot)+)")
    fileprivate static let cardRegex = LineRegex("^- (\\[( |x)\\] )?(\(dot)+)")
    fileprivate static let detailsRegex = LineRegex("^(\\t| {2})(\(dot)*)")
    fileprivate static let estimateRegex = LineRegex("^(\(dot)+?)~([0-9]+)(m|h|d|w)?$")
    fileprivate static let dueRegex = LineRegex("^(\(dot)+?)([0-9]{4}-[0-9]{2}-[0-9]{2})$")
    fileprivate static let taskRegex = LineRegex("^\\s*[*+-] \\[(x| )\\]", caseInsensitive: true)

    public static func parse(_ markdown: String) -> KanbanParseResult {
        var board = KanbanBoard()
        var dropped: [(Int, String)] = []
        var currentCard: (list: Int, card: Int)?

        for (index, line) in splitLines(markdown).enumerated() {
            if let match = columnRegex.firstMatch(in: line) {
                board.lists.append(KanbanList(name: jsTrim(match[1])))
                continue
            }
            if let match = cardRegex.firstMatch(in: line), !board.lists.isEmpty {
                var card = createCard(rawTitle: jsTrim(match[3]))
                card.isCompleted = match[2] == "x"
                board.lists[board.lists.count - 1].cards.append(card)
                currentCard = (board.lists.count - 1, board.lists[board.lists.count - 1].cards.count - 1)
                continue
            }
            // As in NotesHub, indented lines after a heading still join the previous card.
            if let match = detailsRegex.firstMatch(in: line), let position = currentCard {
                let text = match[2]
                let existing = board.lists[position.list].cards[position.card].details
                board.lists[position.list].cards[position.card].details = existing.isEmpty ? text : existing + "\n" + text
                continue
            }
            if !jsTrim(line).isEmpty { dropped.append((index + 1, line)) }
        }
        return KanbanParseResult(board: board, droppedLines: dropped)
    }

    public static func serialize(_ board: KanbanBoard) -> String {
        var lines: [String] = []
        for (index, list) in board.lists.enumerated() {
            lines.append("## \(list.name)")
            let hasCompleted = list.cards.contains { $0.isCompleted }
            for card in list.cards {
                var titleLine = jsTrim(card.title)
                if let value = card.estimateValue { titleLine += " ~\(value)\(card.estimateUnit ?? "")" }
                if !card.tags.isEmpty { titleLine += " " + card.tags.map { "#" + $0 }.joined(separator: " ") }
                if !card.mentions.isEmpty { titleLine += " " + card.mentions.map { "@" + $0 }.joined(separator: " ") }
                if let due = card.dueDate { titleLine += " " + due }
                if hasCompleted {
                    lines.append("- [\(card.isCompleted ? "x" : " ")] \(titleLine)  ")
                } else {
                    lines.append("- \(titleLine)  ")
                }
                if !card.details.isEmpty {
                    for detail in card.details.components(separatedBy: "\n") { lines.append("  " + detail) }
                }
            }
            if index < board.lists.count - 1 { lines.append("") }
        }
        return lines.joined(separator: "\n")
    }

    public static func createCard(rawTitle: String) -> KanbanCard {
        var title = jsTrim(rawTitle)
        var due: String?
        var tags: [String] = []
        var mentions: [String] = []
        var estimate: (Int, String?)?

        while true {
            if let (prefix, token) = suffixToken(title, sigil: "#") {
                title = jsTrim(prefix)
                if !tags.contains(token) { tags.insert(token, at: 0) }
                continue
            }
            if let (prefix, token) = suffixToken(title, sigil: "@") {
                title = jsTrim(prefix)
                if !mentions.contains(token) { mentions.insert(token, at: 0) }
                continue
            }
            if let match = estimateRegex.firstMatch(in: title) {
                title = jsTrim(match[1])
                if estimate == nil { estimate = (Int(match[2]) ?? 0, match.optional(3)) }
                continue
            }
            if let match = dueRegex.firstMatch(in: title) {
                title = jsTrim(match[1])
                if due == nil { due = parseSerializedDate(match[2]) }
                continue
            }
            break
        }
        var card = KanbanCard(title: title)
        card.dueDate = due
        card.tags = tags
        card.mentions = mentions
        card.estimateValue = estimate?.0
        card.estimateUnit = estimate?.1
        return card
    }

    /// Mirrors JavaScript `new Date(y, m - 1, d)`, including its rollover behavior.
    static func parseSerializedDate(_ string: String) -> String? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var year = parts[0]
        if (0...99).contains(year) { year += 1900 }
        let monthIndex = parts[1] - 1
        let floorQuotient = Int((Double(monthIndex) / 12).rounded(.down))
        year += floorQuotient
        let month = monthIndex - floorQuotient * 12 + 1
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard
            let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
            let date = calendar.date(byAdding: .day, value: parts[2] - 1, to: first)
        else { return nil }
        let result = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%d-%02d-%02d", result.year!, result.month!, result.day!)
    }

    /// Matches `/(.+?)<sigil>([\p{L}\p{N}]+)$/u`.
    private static func suffixToken(_ title: String, sigil: Unicode.Scalar) -> (String, String)? {
        let scalars = Array(title.unicodeScalars)
        for (index, scalar) in scalars.enumerated() where scalar == sigil && index > 0 {
            let prefix = scalars[..<index]
            if prefix.contains(where: { [0x0A, 0x0D, 0x2028, 0x2029].contains($0.value) }) { continue }
            let rest = scalars[(index + 1)...]
            if !rest.isEmpty, rest.allSatisfy(isLetterOrNumber) {
                return (string(prefix), string(rest))
            }
        }
        return nil
    }

    private static func string(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    private static func isLetterOrNumber(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }
}

/// `split("\n")` by Unicode scalar. Swift treats `\r\n` as one Character, which would
/// otherwise change how lines split compared with JavaScript.
public func splitLines(_ text: String) -> [String] {
    var result: [String] = []
    var current = String.UnicodeScalarView()
    for scalar in text.unicodeScalars {
        if scalar == "\n" {
            result.append(String(current))
            current = String.UnicodeScalarView()
        } else {
            current.append(scalar)
        }
    }
    result.append(String(current))
    return result
}

/// The characters JavaScript's `String.prototype.trim()` removes.
public func jsTrim(_ text: String) -> String {
    let scalars = Array(text.unicodeScalars)
    func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            return true
        default:
            return false
        }
    }
    guard let start = scalars.firstIndex(where: { !isSpace($0) }),
          let end = scalars.lastIndex(where: { !isSpace($0) }) else { return "" }
    var view = String.UnicodeScalarView()
    view.append(contentsOf: scalars[start...end])
    return String(view)
}

/// A small wrapper for NSRegularExpression, which uses UTF-16 semantics like JavaScript.
struct LineRegex: @unchecked Sendable {
    let regex: NSRegularExpression

    init(_ pattern: String, caseInsensitive: Bool = false) {
        regex = try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    struct Match {
        fileprivate let groups: [String?]
        subscript(index: Int) -> String { groups[index] ?? "" }
        func optional(_ index: Int) -> String? { groups[index] }
    }

    func firstMatch(in text: String) -> Match? {
        let range = NSRange(text.startIndex..., in: text)
        guard let result = regex.firstMatch(in: text, range: range) else { return nil }
        let groups: [String?] = (0..<result.numberOfRanges).map { index in
            let groupRange = result.range(at: index)
            guard groupRange.location != NSNotFound, let swiftRange = Range(groupRange, in: text) else { return nil }
            return String(text[swiftRange])
        }
        return Match(groups: groups)
    }
}
