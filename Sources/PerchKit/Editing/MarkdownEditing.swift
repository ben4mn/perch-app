import Foundation

/// One change to make to a note's text, with where the selection should land afterwards.
/// Ranges are UTF-16, the way text views count.
public struct TextEdit: Equatable, Sendable {
    /// The part of the current text to replace.
    public var range: NSRange
    public var replacement: String
    /// The selection once the replacement is in.
    public var selection: NSRange

    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }

    /// The text after this edit, for tests and previews.
    public func applied(to text: String) -> String {
        (text as NSString).replacingCharacters(in: range, with: replacement)
    }
}

/// The typing helpers a Markdown editor needs. Pure text in, edits out.
public enum MarkdownEditing {
    public enum ListKind: Sendable, Equatable { case bullet, numbered, task }

    public static let indentUnit = "    "

    /// What one level of list indent is made of.
    public enum IndentStyle: String, CaseIterable, Identifiable, Sendable {
        case twoSpaces = "2"
        case fourSpaces = "4"
        case tab

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .twoSpaces: return "2 spaces"
            case .fourSpaces: return "4 spaces"
            case .tab: return "Tab"
            }
        }

        /// The characters one level adds.
        public var unit: String {
            switch self {
            case .twoSpaces: return "  "
            case .fourSpaces: return "    "
            case .tab: return "\t"
            }
        }

        /// The most leading spaces one outdent takes away. A tab-indented note may still hold lines
        /// indented with spaces, so Tab takes away up to four, as it always has.
        var outdentSpaces: Int { self == .twoSpaces ? 2 : 4 }
    }

    /// Which typing helpers are on. The defaults are how the editor has always behaved.
    public struct Options: Equatable, Sendable {
        /// Return inside a list, a task list or a quote starts the next item.
        public var continuesLists: Bool
        /// Tab on a list item moves it in a level.
        public var tabIndentsLists: Bool
        /// Typing `*`, `_`, `` ` ``, `[`, `(`, `~` or `"` over a selection wraps it.
        public var wrapsSelection: Bool
        public var indent: IndentStyle

        public init(continuesLists: Bool = true, tabIndentsLists: Bool = true, wrapsSelection: Bool = true, indent: IndentStyle = .fourSpaces) {
            self.continuesLists = continuesLists
            self.tabIndentsLists = tabIndentsLists
            self.wrapsSelection = wrapsSelection
            self.indent = indent
        }

        public static let standard = Options()
    }

    /// What typing one character should do instead of inserting it: Return in a list, Tab on a list
    /// item, or a mark typed over a selection. Nil means the key does what it normally does, which is
    /// also the answer for any helper that is turned off.
    public static func edit(forTyping typed: String, in string: String, selection: NSRange, options: Options = .standard) -> TextEdit? {
        if typed == "\n" {
            return options.continuesLists ? newline(in: string, selection: selection, options: options) : nil
        }
        if typed == "\t" {
            return options.tabIndentsLists ? indent(in: string, selection: selection, outdent: false, options: options) : nil
        }
        if selection.length > 0, options.wrapsSelection {
            return wrapSelection(typing: typed, in: string, selection: selection)
        }
        return nil
    }

    private static let item = try! NSRegularExpression(
        pattern: #"^([ \t]*)((?:>[ \t]?)*)(?:([-*+])|(\d{1,9})([.)]))([ \t]+)(?:(\[[ xX]\])([ \t]+|$))?"#
    )
    private static let quote = try! NSRegularExpression(pattern: #"^([ \t]*)((?:>[ \t]?)+)"#)
    private static let headingPrefix = try! NSRegularExpression(pattern: #"^(#{1,6})[ \t]+"#)

    struct Item {
        var indent: String
        var quote: String
        var bullet: String?
        var number: Int?
        var numberSuffix: String
        var gap: String
        var box: String?
        /// Length of everything before the item's text.
        var prefixLength: Int
    }

    static func parseItem(_ line: String) -> Item? {
        let source = line as NSString
        guard let match = item.firstMatch(in: line, range: NSRange(location: 0, length: source.length)) else { return nil }
        func group(_ index: Int) -> String? {
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : source.substring(with: range)
        }
        return Item(
            indent: group(1) ?? "", quote: group(2) ?? "", bullet: group(3), number: group(4).flatMap { Int($0) },
            numberSuffix: group(5) ?? ".", gap: group(6) ?? " ", box: group(7), prefixLength: match.range.length
        )
    }

    static func contents(of text: NSString, lineAt location: Int) -> NSRange {
        var start = 0, contentsEnd = 0
        text.getLineStart(&start, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: min(location, text.length), length: 0))
        return NSRange(location: start, length: contentsEnd - start)
    }

    // MARK: Return

    /// What Return should do inside a list, a task list or a quote. Nil means an ordinary new line.
    public static func newline(in string: String, selection: NSRange, options: Options = .standard) -> TextEdit? {
        let text = string as NSString
        guard selection.length == 0, selection.location <= text.length else { return nil }
        let lineRange = contents(of: text, lineAt: selection.location)
        let line = text.substring(with: lineRange)
        let caret = selection.location - lineRange.location

        if let item = parseItem(line) {
            guard caret >= item.prefixLength else { return nil }
            let rest = (line as NSString).substring(from: item.prefixLength)
            if rest.trimmingCharacters(in: .whitespaces).isEmpty {
                // Return on an empty item steps out one level, or ends the list.
                if !item.indent.isEmpty, let edit = indent(in: string, selection: selection, outdent: true, options: options) { return edit }
                let keep = item.quote
                return TextEdit(range: lineRange, replacement: keep, selection: NSRange(location: lineRange.location + (keep as NSString).length, length: 0))
            }
            var marker = item.bullet ?? ""
            if let number = item.number { marker = "\(number + 1)\(item.numberSuffix)" }
            let prefix = item.indent + item.quote + marker + " " + (item.box == nil ? "" : "[ ] ")
            let insertion = "\n" + prefix
            let caretAfter = NSRange(location: selection.location + (insertion as NSString).length, length: 0)
            if let number = item.number {
                // The items below move down one, so their numbers do too.
                let renumbered = renumberedTail(in: text, after: selection.location, item: item, from: number + 1)
                if renumbered.range.length > 0 {
                    return TextEdit(
                        range: NSRange(location: selection.location, length: renumbered.range.length),
                        replacement: insertion + renumbered.text, selection: caretAfter
                    )
                }
            }
            return TextEdit(range: selection, replacement: insertion, selection: caretAfter)
        }

        if let match = quote.firstMatch(in: line, range: NSRange(location: 0, length: lineRange.length)) {
            guard caret >= match.range.length else { return nil }
            let rest = (line as NSString).substring(from: match.range.length)
            if rest.trimmingCharacters(in: .whitespaces).isEmpty {
                return TextEdit(range: lineRange, replacement: "", selection: NSRange(location: lineRange.location, length: 0))
            }
            var prefix = (line as NSString).substring(with: match.range)
            if !prefix.hasSuffix(" ") { prefix += " " }
            let insertion = "\n" + prefix
            return TextEdit(range: selection, replacement: insertion, selection: NSRange(location: selection.location + (insertion as NSString).length, length: 0))
        }
        return nil
    }

    /// The text from `location` to the end of the last numbered item that follows on in sequence, with each
    /// of those numbers raised by one. Only the digits change. An empty range means nothing needs renumbering.
    private static func renumberedTail(in text: NSString, after location: Int, item: Item, from first: Int) -> (range: NSRange, text: String) {
        var lineEnd = 0
        text.getLineStart(nil, end: &lineEnd, contentsEnd: nil, for: NSRange(location: location, length: 0))
        var scan = lineEnd
        var expected = first
        var digits: [NSRange] = []
        var checked = 0
        let indentLength = (item.indent as NSString).length
        while scan < text.length, checked < 500 {
            checked += 1
            var start = 0, end = 0, contentsEnd = 0
            text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: scan, length: 0))
            let line = text.substring(with: NSRange(location: start, length: contentsEnd - start))
            if let next = parseItem(line), next.indent == item.indent, next.quote == item.quote {
                guard next.number == expected, next.numberSuffix == item.numberSuffix else { break }
                digits.append(NSRange(location: start + indentLength + (item.quote as NSString).length, length: ("\(expected)" as NSString).length))
                expected += 1
            } else {
                // Anything indented further belongs to the item above it; anything else ends the list.
                let lead = (line.prefix { $0 == " " || $0 == "\t" } as Substring).utf16.count
                guard lead > indentLength, lead < (line as NSString).length else { break }
            }
            if end <= scan { break }
            scan = end
        }
        guard let last = digits.last else { return (NSRange(location: location, length: 0), "") }
        var result = ""
        var cursor = location
        var number = first
        for range in digits {
            result += text.substring(with: NSRange(location: cursor, length: range.location - cursor))
            number += 1
            result += "\(number)"
            cursor = NSMaxRange(range)
        }
        return (NSRange(location: location, length: NSMaxRange(last) - location), result)
    }

    // MARK: Indent

    /// Tab and Shift-Tab. Moves list items, or every selected line, one level in or out.
    /// Nil means the key should do what it normally does.
    public static func indent(in string: String, selection: NSRange, outdent: Bool, options: Options = .standard) -> TextEdit? {
        let text = string as NSString
        guard NSMaxRange(selection) <= text.length else { return nil }
        let first = contents(of: text, lineAt: selection.location)
        let last = contents(of: text, lineAt: NSMaxRange(selection))
        // A selection that ends at the start of a line doesn't include that line.
        let endsAtLineStart = selection.length > 0 && NSMaxRange(selection) == last.location && last.location > first.location
        let blockEnd = endsAtLineStart ? last.location - 1 : NSMaxRange(last)
        let block = NSRange(location: first.location, length: max(blockEnd - first.location, 0))
        let lines = text.substring(with: block).components(separatedBy: "\n")
        let single = lines.count == 1
        if single, selection.length == 0, !outdent, parseItem(lines[0]) == nil { return nil }

        var changed: [String] = []
        var firstDelta = 0, total = 0
        for (index, line) in lines.enumerated() {
            var result = line
            if outdent {
                if line.hasPrefix("\t") {
                    result = String(line.dropFirst())
                } else {
                    let spaces = line.prefix(options.indent.outdentSpaces).prefix { $0 == " " }.count
                    result = String(line.dropFirst(spaces))
                }
            } else if !line.isEmpty || single {
                result = options.indent.unit + line
            }
            let delta = (result as NSString).length - (line as NSString).length
            if index == 0 { firstDelta = delta }
            total += delta
            changed.append(result)
        }
        guard total != 0 else { return nil }
        let replacement = changed.joined(separator: "\n")
        let newSelection: NSRange
        if selection.length == 0 {
            newSelection = NSRange(location: max(first.location, selection.location + firstDelta), length: 0)
        } else {
            newSelection = NSRange(location: block.location, length: (replacement as NSString).length)
        }
        return TextEdit(range: block, replacement: replacement, selection: newSelection)
    }

    // MARK: Wrapping

    private static func run(of character: unichar, in text: NSString, endingAt location: Int) -> Int {
        var count = 0
        while location - count - 1 >= 0, text.character(at: location - count - 1) == character { count += 1 }
        return count
    }

    private static func run(of character: unichar, in text: NSString, startingAt location: Int) -> Int {
        var count = 0
        while location + count < text.length, text.character(at: location + count) == character { count += 1 }
        return count
    }

    private static func isSurrounded(_ text: NSString, _ selection: NSRange, left: String, right: String) -> Bool {
        let leftLength = (left as NSString).length, rightLength = (right as NSString).length
        guard selection.location >= leftLength, NSMaxRange(selection) + rightLength <= text.length,
              text.substring(with: NSRange(location: selection.location - leftLength, length: leftLength)) == left,
              text.substring(with: NSRange(location: NSMaxRange(selection), length: rightLength)) == right else { return false }
        // `*` beside `**bold**` is not italic: count the whole run of marks.
        if left == right, Set(left).count == 1, let scalar = left.utf16.first, scalar == 0x2A || scalar == 0x5F {
            let before = run(of: scalar, in: text, endingAt: selection.location)
            let after = run(of: scalar, in: text, startingAt: NSMaxRange(selection))
            let count = min(before, after)
            return leftLength == 1 ? count % 2 == 1 : count >= 2
        }
        return true
    }

    /// Bold, italic, code and the like: wraps the selection, or unwraps it when it is already wrapped.
    /// With nothing selected it inserts the pair and puts the caret between.
    public static func toggleWrap(in string: String, selection: NSRange, left: String, right: String) -> TextEdit {
        let text = string as NSString
        let leftLength = (left as NSString).length, rightLength = (right as NSString).length
        let selected = text.substring(with: selection)
        if isSurrounded(text, selection, left: left, right: right) {
            let outer = NSRange(location: selection.location - leftLength, length: selection.length + leftLength + rightLength)
            return TextEdit(range: outer, replacement: selected, selection: NSRange(location: outer.location, length: selection.length))
        }
        if selection.length >= leftLength + rightLength, selected.hasPrefix(left), selected.hasSuffix(right),
           !(left == "*" && selected.hasPrefix("**") && !selected.hasPrefix("***")) {
            let inner = (selected as NSString).substring(with: NSRange(location: leftLength, length: selection.length - leftLength - rightLength))
            return TextEdit(range: selection, replacement: inner, selection: NSRange(location: selection.location, length: (inner as NSString).length))
        }
        return TextEdit(
            range: selection, replacement: left + selected + right,
            selection: NSRange(location: selection.location + leftLength, length: selection.length)
        )
    }

    private static let pairs: [String: String] = ["*": "*", "_": "_", "`": "`", "[": "]", "(": ")", "~": "~", "\"": "\""]

    /// Typing an opening mark over a selection wraps it instead of replacing it. Nil for anything else.
    public static func wrapSelection(typing typed: String, in string: String, selection: NSRange) -> TextEdit? {
        guard selection.length > 0, let close = pairs[typed] else { return nil }
        let text = string as NSString
        guard NSMaxRange(selection) <= text.length else { return nil }
        let selected = text.substring(with: selection)
        guard !selected.contains("\n") else { return nil }
        return TextEdit(
            range: selection, replacement: typed + selected + close,
            selection: NSRange(location: selection.location + (typed as NSString).length, length: selection.length)
        )
    }

    /// Makes a Markdown link from the selection. A selected address becomes the target; other text becomes the label.
    public static func link(in string: String, selection: NSRange) -> TextEdit {
        let text = string as NSString
        let selected = text.substring(with: selection)
        let trimmed = selected.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("mailto:") {
            return TextEdit(range: selection, replacement: "[](\(trimmed))", selection: NSRange(location: selection.location + 1, length: 0))
        }
        let placeholder = "url"
        let replacement = "[\(selected)](\(placeholder))"
        if selected.isEmpty {
            return TextEdit(range: selection, replacement: "[]()", selection: NSRange(location: selection.location + 1, length: 0))
        }
        return TextEdit(
            range: selection, replacement: replacement,
            selection: NSRange(location: selection.location + selection.length + 3, length: (placeholder as NSString).length)
        )
    }

    /// Wraps the selection as a wiki link, or opens one so the note picker appears.
    public static func wikiLink(in string: String, selection: NSRange) -> TextEdit {
        let selected = (string as NSString).substring(with: selection)
        if selected.isEmpty {
            return TextEdit(range: selection, replacement: "[[", selection: NSRange(location: selection.location + 2, length: 0))
        }
        return TextEdit(range: selection, replacement: "[[\(selected)]]", selection: NSRange(location: selection.location + 2, length: selection.length))
    }

    // MARK: Line prefixes

    /// Steps the caret's line through no heading, `#`, `##`, `###` and back.
    public static func cycleHeading(in string: String, selection: NSRange) -> TextEdit {
        let text = string as NSString
        let lineRange = contents(of: text, lineAt: selection.location)
        let line = text.substring(with: lineRange)
        var oldPrefix = 0, level = 0
        if let match = headingPrefix.firstMatch(in: line, range: NSRange(location: 0, length: lineRange.length)) {
            oldPrefix = match.range.length
            level = match.range(at: 1).length
        }
        let next = level >= 3 ? 0 : level + 1
        let newPrefix = next == 0 ? "" : String(repeating: "#", count: next) + " "
        let delta = (newPrefix as NSString).length - oldPrefix
        // A selection that started inside the old marks can't keep its length: there is less text now.
        let start = max(lineRange.location, selection.location + delta)
        let end = max(start, NSMaxRange(selection) + delta)
        return TextEdit(
            range: NSRange(location: lineRange.location, length: oldPrefix), replacement: newPrefix,
            selection: NSRange(location: start, length: end - start)
        )
    }

    /// Turns the selected lines into a list of this kind, or back into plain lines when they already are one.
    public static func toggleList(in string: String, selection: NSRange, kind: ListKind) -> TextEdit {
        let text = string as NSString
        let first = contents(of: text, lineAt: selection.location)
        let last = contents(of: text, lineAt: NSMaxRange(selection))
        let block = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        let lines = text.substring(with: block).components(separatedBy: "\n")

        func matches(_ item: Item?) -> Bool {
            guard let item else { return false }
            switch kind {
            case .bullet: return item.bullet != nil && item.box == nil
            case .numbered: return item.number != nil
            case .task: return item.box != nil
            }
        }
        let filled = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let removing = !filled.isEmpty && filled.allSatisfy { matches(parseItem($0)) }
        var number = 0
        var firstDelta = 0
        var changed: [String] = []
        for (index, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty, lines.count > 1 {
                changed.append(line)
                continue
            }
            let item = parseItem(line)
            let indent = item?.indent ?? String(line.prefix { $0 == " " || $0 == "\t" })
            let quote = item?.quote ?? ""
            let body = item.map { (line as NSString).substring(from: $0.prefixLength) } ?? String(line.dropFirst(indent.count))
            var marker = ""
            if !removing {
                switch kind {
                case .bullet: marker = (item?.bullet ?? "-") + " "
                case .numbered:
                    number += 1
                    marker = "\(number). "
                case .task: marker = (item?.bullet ?? "-") + " [ ] "
                }
            }
            let result = indent + quote + marker + body
            if index == 0 { firstDelta = (result as NSString).length - (line as NSString).length }
            changed.append(result)
        }
        let replacement = changed.joined(separator: "\n")
        let newSelection: NSRange
        if selection.length == 0 {
            newSelection = NSRange(location: min(max(first.location, selection.location + firstDelta), block.location + (replacement as NSString).length), length: 0)
        } else {
            newSelection = NSRange(location: block.location, length: (replacement as NSString).length)
        }
        return TextEdit(range: block, replacement: replacement, selection: newSelection)
    }

    // MARK: Task boxes

    /// Ticks or unticks the task on one line, for a click on its box in the reader. Lines are counted from
    /// zero the way the reader counts them. Only the one character between the brackets changes; nil when
    /// that line isn't a task, or is already as asked. Pass `checked` nil to flip it.
    public static func setTaskBox(in string: String, line: Int, checked: Bool? = nil) -> TextEdit? {
        let text = string as NSString
        guard line >= 0, let start = location(ofRenderedLine: line, in: text) else { return nil }
        let lineRange = contents(of: text, lineAt: start)
        let source = text.substring(with: lineRange)
        guard let match = item.firstMatch(in: source, range: NSRange(location: 0, length: lineRange.length)) else { return nil }
        let box = match.range(at: 7)
        guard box.location != NSNotFound, box.length == 3 else { return nil }
        let mark = NSRange(location: lineRange.location + box.location + 1, length: 1)
        let isChecked = text.substring(with: mark) != " "
        let wanted = checked ?? !isChecked
        guard wanted != isChecked else { return nil }
        return TextEdit(range: mark, replacement: wanted ? "x" : " ", selection: NSRange(location: mark.location, length: 0))
    }

    /// Where a zero-based line starts, counting line breaks the way the Markdown reader does:
    /// `\n`, `\r\n` and a lone `\r` each end a line. Nil when the text has fewer lines.
    private static func location(ofRenderedLine line: Int, in text: NSString) -> Int? {
        guard line > 0 else { return 0 }
        var seen = 0, index = 0
        let length = text.length
        while index < length {
            let character = text.character(at: index)
            if character == 0x0A || character == 0x0D {
                if character == 0x0D, index + 1 < length, text.character(at: index + 1) == 0x0A { index += 1 }
                seen += 1
                if seen == line { return index + 1 }
            }
            index += 1
        }
        return nil
    }

    // MARK: Lines

    /// The zero-based line a UTF-16 location falls on.
    public static func lineNumber(of location: Int, in text: NSString) -> Int {
        var line = 0
        scanBlocks(of: text, to: min(max(location, 0), text.length)) { block, _ in
            newlines(in: block) { _ in
                line += 1
                return true
            }
            return true
        }
        return line
    }

    /// The UTF-16 location where a zero-based line starts. Past the end gives the end.
    public static func location(ofLine line: Int, in text: NSString) -> Int {
        guard line > 0 else { return 0 }
        var seen = 0
        var found: Int?
        scanBlocks(of: text, to: text.length) { block, offset in
            newlines(in: block) { index in
                seen += 1
                guard seen == line else { return true }
                found = offset + index + 1
                return false
            }
            return found == nil
        }
        return found ?? text.length
    }

    /// Calls `visit` with the index of each newline in a block, until it returns false. `memchr` jumps
    /// between them, so the work is per line, not per character, even in a debug build. In UTF-16 a newline
    /// is the bytes 0A 00; a 0A byte that is half of another character is passed over.
    private static func newlines(in block: UnsafeBufferPointer<unichar>, _ visit: (Int) -> Bool) {
        guard let base = block.baseAddress, !block.isEmpty else { return }
        let raw = UnsafeRawPointer(base)
        let bytes = block.count * MemoryLayout<unichar>.stride
        var from = 0
        while from < bytes, let hit = memchr(raw + from, 0x0A, bytes - from) {
            let at = raw.distance(to: UnsafeRawPointer(hit))
            if at % 2 == 0, block[at / 2] == 0x0A {
                guard visit(at / 2) else { return }
                from = at + 2
            } else {
                from = at + 1
            }
        }
    }

    /// Reads the text from its start in blocks of characters, which is many times quicker than asking for
    /// one character at a time: in a long note that was most of what scrolling and typing cost. `body` gets
    /// each block and where it starts, and returns false to stop.
    private static func scanBlocks(of text: NSString, to end: Int, _ body: (UnsafeBufferPointer<unichar>, Int) -> Bool) {
        let size = 8192
        var buffer = [unichar](repeating: 0, count: size)
        var start = 0
        while start < end {
            let count = min(size, end - start)
            let keepGoing = buffer.withUnsafeMutableBufferPointer { storage -> Bool in
                text.getCharacters(storage.baseAddress!, range: NSRange(location: start, length: count))
                return body(UnsafeBufferPointer(rebasing: storage[0..<count]), start)
            }
            guard keepGoing else { return }
            start += count
        }
    }
}
