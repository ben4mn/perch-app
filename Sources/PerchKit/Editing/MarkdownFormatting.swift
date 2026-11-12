import Foundation

/// The formatting in force at the caret or across a selection, for toolbars to show.
public struct ActiveFormats: Equatable, Sendable {
    public var bold = false
    public var italic = false
    public var underline = false
    public var strikethrough = false
    public var code = false
    public var `subscript` = false
    public var superscript = false
    public var link = false
    /// Nil for none, empty for the plain yellow highlight, otherwise `#RRGGBB`.
    public var highlight: String?
    /// `#RRGGBB`, or nil for the theme's own text color.
    public var textColor: String?
    /// One of `FormatPalette.sizes`, or nil for normal text.
    public var textSize: String?
    /// 0 for body text.
    public var headingLevel = 0
    public var list: MarkdownEditing.ListKind?
    public var quote = false
    /// The callout's type in small letters ("note", "tip"), or nil outside a callout.
    public var callout: String?
    /// "center" or "right", or nil.
    public var alignment: String?
    public var inCodeBlock = false
    public var inTable = false

    public init() {}

    public func isOn(_ format: InlineFormat) -> Bool {
        switch format {
        case .bold: return bold
        case .italic: return italic
        case .strikethrough: return strikethrough
        case .underline: return underline
        case .highlight: return highlight != nil
        case .textColor: return textColor != nil
        case .textSize: return textSize != nil
        case .subscript: return self.subscript
        case .superscript: return superscript
        }
    }
}

extension TextEdit {
    /// The smallest single edit that turns `old` into `new`.
    static func difference(from old: String, to new: String, selection: NSRange) -> TextEdit? {
        guard old != new else { return nil }
        let before = old as NSString, after = new as NSString
        let limit = min(before.length, after.length)
        var prefix = 0
        while prefix < limit, before.character(at: prefix) == after.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < limit - prefix, before.character(at: before.length - 1 - suffix) == after.character(at: after.length - 1 - suffix) { suffix += 1 }
        // Never cut a surrogate pair in half.
        while prefix > 0, UTF16.isLeadSurrogate(before.character(at: prefix - 1)) { prefix -= 1 }
        while suffix > 0, UTF16.isTrailSurrogate(before.character(at: before.length - suffix)) { suffix -= 1 }
        return TextEdit(
            range: NSRange(location: prefix, length: before.length - prefix - suffix),
            replacement: after.substring(with: NSRange(location: prefix, length: after.length - prefix - suffix)),
            selection: selection
        )
    }
}

/// Formatting commands for a Markdown note. Pure text in, one edit out: nothing here touches a file, and
/// every command changes only the marks it names. A command that can't be done safely returns nil.
public enum MarkdownFormatting {
    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let delimiterRow = regex(#"^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$"#)
    private static let loneTag = regex(#"^\s*</?[A-Za-z][A-Za-z0-9-]*(?:\s[^<>]*)?>\s*$"#)
    private static let footnoteDefinition = regex(#"\[\^[^\]\s]+\]:[ \t]*"#)
    private static let calloutLead = regex(#"\[!([\w-]+)\][+-]?[ \t]*"#)
    private static let headingLead = regex(#"^(#{1,6})[ \t]+"#)
    private static let quoteLead = regex(#"^([ \t]*)((?:>[ \t]?)+)"#)
    private static let divOpen = regex(#"^[ \t]*<div\s+align\s*=\s*["']?(left|center|right)["']?\s*>[ \t]*$"#, [.caseInsensitive])
    private static let divClose = regex(#"^[ \t]*</div\s*>[ \t]*$"#, [.caseInsensitive])
    private static let wordCharacters = CharacterSet.alphanumerics

    // MARK: Lines

    struct Line {
        /// The line without its line ending.
        var content: NSRange
        /// The line with its line ending.
        var full: NSRange
        var before: MarkdownBlockState
        var after: MarkdownBlockState
        /// Indented code, or a block of raw HTML: Markdown doesn't read marks in either, so none are written there.
        var raw = false

        /// Not inside, opening or closing a fenced code block, math block or frontmatter.
        var isMarkdown: Bool { before == .normal && after == .normal }
        /// Ordinary Markdown that formatting can be written into.
        var isText: Bool { isMarkdown && !raw }
    }

    /// Tags that start a block of raw HTML wherever they begin a line. The block runs to the next blank line.
    private static let blockTags: Set<String> = [
        "address", "article", "aside", "base", "basefont", "blockquote", "body", "caption", "center", "col", "colgroup", "dd",
        "details", "dialog", "dir", "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form", "frame", "frameset",
        "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hr", "html", "iframe", "legend", "li", "link", "main", "menu",
        "menuitem", "nav", "noframes", "ol", "optgroup", "option", "p", "param", "search", "section", "summary", "table",
        "tbody", "td", "tfoot", "th", "thead", "title", "tr", "track", "ul",
    ]
    /// Tags whose block runs to their own closing tag, blank lines and all.
    private static let verbatimTags: Set<String> = ["pre", "script", "style", "textarea"]
    private static let blockTagLead = regex(#"^ {0,3}<(/?)([A-Za-z][A-Za-z0-9-]*)(?=[\s/>]|$)"#)

    /// Marks the lines Markdown reads as indented code or raw HTML, by CommonMark's rules: four spaces or
    /// a tab after a blank line (and not under a list item) is code; a line that starts with a block tag,
    /// or is nothing but a tag, begins HTML that runs to the next blank line.
    private static func markRaw(_ text: NSString, _ lines: inout [Line]) {
        enum HTML { case none, untilBlank, until(String) }
        var html = HTML.none
        var afterBlank = true, inCode = false, inList = false
        for index in lines.indices {
            let line = lines[index]
            guard line.isMarkdown else {
                html = .none
                inCode = false
                inList = false
                // The line that closes a block is the last of it: what follows starts fresh.
                afterBlank = line.after == .normal
                continue
            }
            let blank = isBlank(text, line.content)
            switch html {
            case .untilBlank:
                if blank { html = .none } else { lines[index].raw = true }
                afterBlank = blank
                continue
            case let .until(closing):
                lines[index].raw = true
                if text.range(of: closing, options: .caseInsensitive, range: line.content).location != NSNotFound {
                    html = .none
                    afterBlank = true
                }
                continue
            case .none:
                break
            }
            if blank {
                afterBlank = true
                continue
            }
            var columns = 0, lead = line.content.location
            while lead < NSMaxRange(line.content) {
                let character = text.character(at: lead)
                if character == 0x20 { columns += 1 } else if character == 0x09 { columns += 4 - columns % 4 } else { break }
                lead += 1
            }
            let source = text.substring(with: line.content)
            let local = NSRange(location: 0, length: line.content.length)
            if columns >= 4 {
                if inCode || (afterBlank && !inList) {
                    lines[index].raw = true
                    inCode = true
                    afterBlank = false
                    continue
                }
            } else {
                inCode = false
                if text.character(at: lead) == 0x3C {
                    if (source as NSString).substring(from: lead - line.content.location).hasPrefix("<!--") {
                        lines[index].raw = true
                        if !source.contains("-->") { html = .until("-->") }
                        afterBlank = false
                        continue
                    }
                    if let tag = blockTagLead.firstMatch(in: source, range: local) {
                        let name = (source as NSString).substring(with: tag.range(at: 2)).lowercased()
                        let closes = tag.range(at: 1).length > 0
                        if verbatimTags.contains(name), !closes {
                            lines[index].raw = true
                            if source.range(of: "</\(name)", options: .caseInsensitive) == nil { html = .until("</\(name)") }
                            afterBlank = false
                            continue
                        }
                        if blockTags.contains(name) || (afterBlank && loneTag.firstMatch(in: source, range: local) != nil) {
                            lines[index].raw = true
                            html = .untilBlank
                            afterBlank = false
                            continue
                        }
                    }
                }
            }
            if MarkdownEditing.parseItem(source) != nil {
                inList = true
            } else if columns == 0, afterBlank {
                inList = false
            }
            afterBlank = false
        }
    }

    /// The lines of the note last asked about. Where code blocks are depends on everything above, so the
    /// whole note is read; a format bar asks again on every move of the caret, and the note is usually the same.
    private final class LineCache: @unchecked Sendable {
        private let lock = NSLock()
        private var text: NSString?
        private var lines: [Line] = []

        func lines(for text: NSString, make: (NSString) -> [Line]) -> [Line] {
            lock.lock()
            defer { lock.unlock() }
            if let known = self.text, known.length == text.length, known.isEqual(to: text as String) { return lines }
            // A text view's string changes underneath us: keep a copy that can't.
            // (`copy`, not `NSString(string:)`, which drops a byte order mark and puts every range out by one.)
            let fixed = text.copy() as? NSString ?? text
            lines = make(fixed)
            self.text = fixed
            return lines
        }
    }

    private static let lineCache = LineCache()

    /// Every line of the note, with the block each is in. `location` is where the caller is working; lines
    /// past it come back too.
    static func lines(_ text: NSString, through location: Int) -> [Line] {
        lineCache.lines(for: text) { allLines($0) }
    }

    private static func allLines(_ text: NSString) -> [Line] {
        let location = text.length
        let structure = MarkdownHighlighter.structure(text, through: location + 1)
        var lines: [Line] = structure.lines.map { line in
            var contentsEnd = 0
            text.getLineStart(nil, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: line.range.location, length: 0))
            return Line(content: NSRange(location: line.range.location, length: contentsEnd - line.range.location), full: line.range, before: line.before, after: line.after)
        }
        // The empty line after a final line break has no characters, so the highlighter doesn't list it.
        let end = lines.last.map { NSMaxRange($0.full) } ?? 0
        if end == text.length, location >= end, text.length == 0 || text.character(at: text.length - 1) == 0x0A || text.character(at: text.length - 1) == 0x0D {
            lines.append(Line(content: NSRange(location: end, length: 0), full: NSRange(location: end, length: 0), before: structure.endState, after: structure.endState))
        }
        markRaw(text, &lines)
        return lines
    }

    /// The lines a selection touches. A selection that ends at the start of a line doesn't include that line.
    static func selectedLines(_ text: NSString, selection: NSRange, all: [Line]? = nil) -> [Line] {
        let lines = all ?? self.lines(text, through: NSMaxRange(selection))
        let end = NSMaxRange(selection)
        return lines.filter { line in
            let lineEnd = NSMaxRange(line.content)
            if selection.length == 0 { return line.content.location <= end && end <= lineEnd }
            if line.content.location == end, line.content.location > selection.location { return false }
            return line.content.location <= end && lineEnd >= selection.location
        }
    }

    private static func isBlank(_ text: NSString, _ range: NSRange) -> Bool {
        for index in range.location..<NSMaxRange(range) {
            let character = text.character(at: index)
            if character != 0x20, character != 0x09, character != 0x0D, character != 0x0A { return false }
        }
        return true
    }

    private static func trimmed(_ text: NSString, _ range: NSRange) -> NSRange {
        var start = range.location, end = NSMaxRange(range)
        while start < end, text.character(at: start) == 0x20 || text.character(at: start) == 0x09 { start += 1 }
        while end > start, text.character(at: end - 1) == 0x20 || text.character(at: end - 1) == 0x09 { end -= 1 }
        return NSRange(location: start, length: end - start)
    }

    /// The line ending this note uses.
    private static func lineBreak(_ text: NSString) -> String {
        text.range(of: "\r\n").location != NSNotFound ? "\r\n" : "\n"
    }

    /// How one line is laid out: where its words are.
    enum Layout: Equatable {
        /// Nothing to format: a blank line, a rule, a lone HTML tag, a table's rule row.
        case structure
        /// The words after the heading hashes, quote marks, list marker and task box. May be empty.
        case body(NSRange)
        /// A table row's cells, spaces included.
        case cells([NSRange])
    }

    static func layout(_ text: NSString, line: Line) -> Layout {
        guard line.isText, !isBlank(text, line.content) else { return .structure }
        let content = line.content
        let source = text.substring(with: content)
        let local = NSRange(location: 0, length: content.length)
        let lead = source.trimmingCharacters(in: .whitespaces)
        if lead.hasPrefix(":::") || lead.hasPrefix("$$") { return .structure }
        if loneTag.firstMatch(in: source, range: local) != nil { return .structure }
        if MarkdownHighlighter.rule.firstMatch(in: source, range: local) != nil { return .structure }
        var start = 0
        if let heading = headingLead.firstMatch(in: source, range: local) {
            start = heading.range.length
        } else {
            if let quote = quoteLead.firstMatch(in: source, range: local) {
                start = quote.range.length
                if let tag = calloutLead.firstMatch(in: source, options: .anchored, range: NSRange(location: start, length: content.length - start)) {
                    start = NSMaxRange(tag.range)
                }
            }
            let rest = NSRange(location: start, length: content.length - start)
            if let item = MarkdownHighlighter.listPrefix.firstMatch(in: source, options: .anchored, range: rest) {
                start = NSMaxRange(item.range)
            } else if let note = footnoteDefinition.firstMatch(in: source, options: .anchored, range: rest) {
                start = NSMaxRange(note.range)
            } else if (source as NSString).substring(from: start).trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                if delimiterRow.firstMatch(in: source, range: rest) != nil { return .structure }
                return .cells(cells(text, NSRange(location: content.location + start, length: content.length - start)))
            }
        }
        return .body(trimmed(text, NSRange(location: content.location + start, length: content.length - start)))
    }

    /// The stretches of a line that hold its words: everything after the heading hashes, quote marks, list
    /// marker and task box, or each cell of a table row. Formatting marks are only ever written inside these,
    /// so block syntax stays where Markdown needs it.
    static func segments(_ text: NSString, line: Line) -> [NSRange] {
        switch layout(text, line: line) {
        case .structure: return []
        case let .body(body): return body.length > 0 ? [body] : []
        case let .cells(cells): return cells.map { trimmed(text, $0) }.filter { $0.length > 0 }
        }
    }

    /// The cells of a table row, spaces included, without the pipes around them.
    static func cells(_ text: NSString, _ row: NSRange) -> [NSRange] {
        var cells: [NSRange] = []
        var start: Int?
        var inCode = false
        var index = row.location
        let end = NSMaxRange(row)
        while index < end {
            let character = text.character(at: index)
            if character == 0x5C {
                index += 2
                continue
            }
            if character == 0x60 { inCode.toggle() }
            if character == 0x7C, !inCode {
                if let start { cells.append(NSRange(location: start, length: index - start)) }
                start = index + 1
            }
            index += 1
        }
        // A row may leave off its last pipe.
        if let start, start < end, !isBlank(text, NSRange(location: start, length: end - start)) {
            cells.append(NSRange(location: start, length: end - start))
        }
        return cells
    }

    // MARK: Retagging one stretch of text

    private struct Item {
        enum Kind: Equatable { case text, space, atom, stray, open(Int), close(Int), dropped }
        var range: NSRange
        var kind: Kind
    }

    /// One stretch of a line with the part of the selection that falls in it.
    private struct Target {
        var scan: InlineScan
        var range: NSRange
    }

    private struct Retag {
        var range: NSRange
        var replacement: String
        /// Each piece of the old text that was kept: where it was, and where it starts in the replacement.
        var kept: [(old: NSRange, new: Int)]
        /// Where the formatted words start and end in the replacement, when marks were pulled in past
        /// punctuation: the selection follows them, so the same command again takes the format off.
        var formatted: (start: Int, end: Int)?

        func map(_ position: Int, toEnd: Bool) -> Int {
            if toEnd {
                guard let item = kept.last(where: { $0.old.location < position }) else { return 0 }
                return item.new + item.old.length
            }
            return kept.first { NSMaxRange($0.old) > position }?.new ?? (replacement as NSString).length
        }
    }

    /// A space of any width. Marks go inside the spaces around a selection, never outside them.
    private static func isSpace(_ character: unichar) -> Bool {
        character != 0x0A && character != 0x0D && InlineScanner.isSpace(character)
    }

    /// The value of the innermost `format` pair around a location, or nil.
    private static func value(of format: InlineFormat, at location: Int, in scan: InlineScan, inclusive: Bool = false) -> String? {
        var found: String?
        for pair in scan.pairs where pair.format == format {
            let inner = pair.inner
            if inner.location <= location, inclusive ? location <= NSMaxRange(inner) : location < NSMaxRange(inner) { found = pair.value }
        }
        return found
    }

    /// Widens a selection so it never cuts a mark, a link or a code span in half, then drops the spaces at its ends.
    private static func normalized(_ requested: NSRange, in scan: InlineScan, text: NSString) -> NSRange? {
        var range = NSIntersectionRange(requested, scan.range)
        guard range.length > 0 else { return nil }
        var tokens = scan.atoms + scan.strays
        for pair in scan.pairs { tokens += [pair.open, pair.close] }
        var changed = true
        while changed {
            changed = false
            for token in tokens {
                let shared = NSIntersectionRange(token, range).length
                if shared > 0, shared < token.length {
                    range = NSUnionRange(range, token)
                    changed = true
                }
            }
        }
        var start = range.location, end = NSMaxRange(range)
        while start < end, isSpace(text.character(at: start)) { start += 1 }
        while end > start, isSpace(text.character(at: end - 1)) { end -= 1 }
        return end > start ? NSRange(location: start, length: end - start) : nil
    }

    /// The text of `hull` cut into marks, atoms and characters. Marks of `dropping` are flagged so they can be left out.
    private static func items(_ text: NSString, scan: InlineScan, hull: NSRange, dropping: InlineFormat?) -> [Item] {
        var tokens: [Item] = scan.atoms.map { Item(range: $0, kind: .atom) } + scan.strays.map { Item(range: $0, kind: .stray) }
        for (index, pair) in scan.pairs.enumerated() {
            let dropped = dropping != nil && pair.format == dropping
            tokens.append(Item(range: pair.open, kind: dropped ? .dropped : .open(index)))
            tokens.append(Item(range: pair.close, kind: dropped ? .dropped : .close(index)))
        }
        tokens = tokens.filter { $0.range.location >= hull.location && NSMaxRange($0.range) <= NSMaxRange(hull) && $0.range.length > 0 }
            .sorted { $0.range.location < $1.range.location }
        var items: [Item] = []
        var position = hull.location
        var next = 0
        let end = NSMaxRange(hull)
        while position < end {
            while next < tokens.count, tokens[next].range.location < position { next += 1 }
            if next < tokens.count, tokens[next].range.location == position {
                items.append(tokens[next])
                position = NSMaxRange(tokens[next].range)
                next += 1
                continue
            }
            let limit = next < tokens.count ? tokens[next].range.location : end
            let stop = max(min(NSMaxRange(text.rangeOfComposedCharacterSequence(at: position)), limit, end), position + 1)
            items.append(Item(range: NSRange(location: position, length: stop - position), kind: isSpace(text.character(at: position)) ? .space : .text))
            position = stop
        }
        return items
    }

    /// Sets `format` to `value` (nil removes it) across `range`, rewriting every mark of that format the range
    /// touches so the result has one clean span per run: no nesting, no empty spans, and no span that starts
    /// inside one link or emphasis and ends outside it.
    ///
    /// Nil when the marks it would write wouldn't read back as this format, or would change how other
    /// formatting on the line reads (a `~` beside another `~`, say). Nothing is written then.
    private static func retag(_ text: NSString, target: Target, format: InlineFormat, value: String?) -> Retag? {
        let scan = target.scan, range = target.range
        var hull = range
        var changed = true
        while changed {
            changed = false
            for pair in scan.pairs where pair.format == format {
                let outer = pair.outer
                let touches = outer.location <= NSMaxRange(hull) && NSMaxRange(outer) >= hull.location
                let inside = outer.location >= hull.location && NSMaxRange(outer) <= NSMaxRange(hull)
                if touches, !inside {
                    hull = NSUnionRange(hull, outer)
                    changed = true
                }
            }
        }
        let items = items(text, scan: scan, hull: hull, dropping: format)
        let values: [String?] = items.map { item in
            if item.kind == .dropped { return nil }
            if item.range.location >= range.location, NSMaxRange(item.range) <= NSMaxRange(range) { return value }
            return self.value(of: format, at: item.range.location, in: scan)
        }

        // Markdown only reads `**`, `*`, `~~` and `==` as marks when they hug a word: `foo**(bar)**baz` stays
        // plain text, with its asterisks showing. So a piece gives up punctuation at an end where the marks
        // wouldn't count, and `foo(**bar**)baz` is written instead.
        let flanks = format == .bold || format == .italic || format == .strikethrough || (format == .highlight && (value ?? "").isEmpty)
        func neighbor(before index: Int) -> unichar? {
            var position = index - 1
            while position >= 0, items[position].kind == .dropped { position -= 1 }
            if position >= 0 { return text.character(at: NSMaxRange(items[position].range) - 1) }
            return hull.location > scan.range.location ? text.character(at: hull.location - 1) : nil
        }
        func neighbor(after index: Int) -> unichar? {
            var position = index + 1
            while position < items.count, items[position].kind == .dropped { position += 1 }
            if position < items.count { return text.character(at: items[position].range.location) }
            return NSMaxRange(hull) < NSMaxRange(scan.range) ? text.character(at: NSMaxRange(hull)) : nil
        }
        var pieces: [(first: Int, last: Int, value: String)] = []
        var pulledIn = false
        func addPiece(_ from: Int, _ to: Int, _ value: String) {
            var first = from, last = to
            while true {
                while first <= last, items[first].kind == .space || items[first].kind == .dropped { first += 1 }
                while last >= first, items[last].kind == .space || items[last].kind == .dropped { last -= 1 }
                guard first <= last else { return }
                // New marks go inside marks that already wrap exactly these words: bold on `<u>word</u>` is
                // written `<u>**word**</u>`, which Markdown reads more reliably than `**<u>word</u>**`.
                // (Not into `~x~` or `^x^`, which can't hold a tag: tags have spaces in them.)
                if case let .open(opened) = items[first].kind, case let .close(closed) = items[last].kind, opened == closed,
                   scan.pairs[opened].format != .subscript, scan.pairs[opened].format != .superscript {
                    first += 1
                    last -= 1
                    continue
                }
                if flanks {
                    if items[first].kind == .text,
                       !InlineScanner.canOpen(before: neighbor(before: first), after: text.character(at: items[first].range.location)) {
                        first += 1
                        pulledIn = true
                        continue
                    }
                    if items[last].kind == .text,
                       !InlineScanner.canClose(before: text.character(at: NSMaxRange(items[last].range) - 1), after: neighbor(after: last)) {
                        last -= 1
                        pulledIn = true
                        continue
                    }
                }
                break
            }
            guard (first...last).contains(where: { items[$0].kind == .text || items[$0].kind == .atom }) else { return }
            pieces.append((first, last, value))
        }
        var index = 0
        while index < items.count {
            guard items[index].kind != .dropped, let run = values[index] else {
                index += 1
                continue
            }
            var stop = index, last = index
            while stop < items.count, items[stop].kind == .dropped || values[stop] == run {
                if items[stop].kind != .dropped { last = stop }
                stop += 1
            }
            // A span must not start inside a link or emphasis and end outside it: cut the run at every
            // mark whose partner lies outside the run.
            var open: [Int] = []
            var cuts: [Int] = []
            for position in index...last {
                switch items[position].kind {
                case .stray:
                    cuts.append(position)
                case .open:
                    open.append(position)
                case let .close(pair):
                    if let top = open.last, items[top].kind == .open(pair) { open.removeLast() } else { cuts.append(position) }
                default:
                    break
                }
            }
            // `~x~` and `^x^` can't hold a space: each word gets its own.
            if format == .subscript || format == .superscript {
                cuts += (index...last).filter { items[$0].kind == .space }
            }
            cuts = (cuts + open).sorted()
            var start = index
            for cut in cuts + [last + 1] {
                if cut > start { addPiece(start, cut - 1, run) }
                start = cut + 1
            }
            index = stop
        }

        var opens: [Int: String] = [:], closes: [Int: String] = [:]
        for piece in pieces {
            let marks = format.markers(value: piece.value)
            opens[piece.first] = marks.open
            closes[piece.last] = marks.close
        }
        let output = NSMutableString()
        var kept: [(old: NSRange, new: Int)] = []
        var openedAt: [Int: Int] = [:], closedAt: [Int: Int] = [:], movedTo: [Int: Int] = [:]
        for (position, item) in items.enumerated() {
            if let mark = opens[position] {
                openedAt[position] = output.length
                output.append(mark)
            }
            if item.kind != .dropped {
                kept.append((item.range, output.length))
                movedTo[item.range.location] = output.length
                output.append(text.substring(with: item.range))
            }
            if let mark = closes[position] {
                closedAt[position] = output.length
                output.append(mark)
            }
        }
        var result = Retag(range: hull, replacement: output as String, kept: kept)
        guard result.replacement != text.substring(with: hull) else { return result }
        if pulledIn, value != nil, let first = pieces.first, let last = pieces.last,
           let start = movedTo[items[first.first].range.location], let end = movedTo[items[last.last].range.location] {
            result.formatted = (start, end + items[last.last].range.length)
        }

        // Read the line back as it will be. Every span written must be there, exactly where it was put,
        // and every other mark on the line must still pair up the way it did.
        let lead = text.substring(with: NSRange(location: scan.range.location, length: hull.location - scan.range.location))
        let tail = text.substring(with: NSRange(location: NSMaxRange(hull), length: NSMaxRange(scan.range) - NSMaxRange(hull)))
        let line = lead + result.replacement + tail
        let base = (lead as NSString).length
        let delta = output.length - hull.length
        let after = InlineScanner.scan(line as NSString, source: line, range: NSRange(location: 0, length: (line as NSString).length))
        let read = line as NSString
        /// Marks made of one character run together (`***word***`), and which asterisk belongs to the bold
        /// is anyone's guess: two spans are the same when only such characters lie between their ends.
        func onlyMarks(_ from: Int, _ to: Int) -> Bool {
            for index in min(from, to)..<max(from, to) {
                guard [0x2A, 0x5F, 0x7E, 0x3D, 0x5E].contains(Int(read.character(at: index))) else { return false }
            }
            return true
        }
        func has(_ wanted: InlineFormat?, value wantedValue: String? = nil, open: Int, close: Int) -> Bool {
            after.pairs.contains {
                $0.format == wanted && (wantedValue == nil || $0.value == wantedValue)
                    && onlyMarks($0.inner.location, open) && onlyMarks(NSMaxRange($0.inner), close)
            }
        }
        for piece in pieces {
            guard let open = openedAt[piece.first], let close = closedAt[piece.last],
                  has(format, value: piece.value, open: base + open + (opens[piece.first]! as NSString).length, close: base + close) else { return nil }
        }
        func moved(_ mark: NSRange) -> Int? {
            if mark.location < hull.location { return mark.location - scan.range.location }
            if mark.location >= NSMaxRange(hull) { return mark.location - scan.range.location + delta }
            return movedTo[mark.location].map { base + $0 }
        }
        // Code, addresses, link targets and stray tags are still what they were: a mark between `]` and `(`
        // would turn a link's address into ordinary words.
        for (before, now) in [(scan.atoms, after.atoms), (scan.strays, after.strays)] {
            for token in before {
                guard let location = moved(token), now.contains(where: { $0.location == location && $0.length == token.length }) else { return nil }
            }
        }
        for pair in scan.pairs where pair.format != format || NSMaxRange(pair.outer) <= hull.location || pair.outer.location >= NSMaxRange(hull) {
            guard let open = moved(pair.open), let close = moved(pair.close), has(pair.format, open: open + pair.open.length, close: close) else { return nil }
        }
        return result
    }

    /// `empty` is a stretch with nothing to judge by: no words, only punctuation.
    private enum Coverage: Equatable { case none, mixed, all(String), empty }

    /// What the targets have in common: `none` when any word lacks the format.
    private static func coverage(_ text: NSString, targets: [Target], format: InlineFormat) -> Coverage {
        for punctuation in [false, true] {
            var result: Coverage?
            for target in targets {
                let found = commonValue(text, target: target, format: format, punctuation: punctuation)
                if found == .none { return .none }
                if found == .empty { continue }
                if let known = result, known != found { result = .mixed } else { result = found }
            }
            if let result { return result }
        }
        return .none
    }

    private static func commonValue(_ text: NSString, target: Target, format: InlineFormat, punctuation: Bool) -> Coverage {
        var seen: String?
        var mixed = false
        var words = items(text, scan: target.scan, hull: target.range, dropping: format).filter { $0.kind == .text || $0.kind == .atom }
        // Markdown's own marks can't always take in the punctuation at the ends of a selection (`foo(**bar**)`),
        // so for those formats the words decide: bold words with a plain bracket beside them are bold.
        // A selection of nothing but punctuation is judged by the punctuation.
        if !punctuation, format.markers().open.first != "<" {
            words = words.filter { $0.kind == .atom || !InlineScanner.isPunctuation(text.character(at: $0.range.location)) }
        }
        for item in words {
            guard let value = value(of: format, at: item.range.location, in: target.scan) else { return .none }
            if let seen, seen != value { mixed = true }
            seen = value
        }
        guard let seen else { return .empty }
        return mixed ? .mixed : .all(seen)
    }

    // MARK: Finding what a command applies to

    private enum Scope {
        /// Stretches of text to format, and whether they came from the word under the caret.
        case targets([Target], isWord: Bool)
        /// The caret is somewhere an empty pair of marks can be typed into.
        case emptyCaret
        /// Nothing can be formatted here: a code block, or the middle of a mark.
        case nowhere
    }

    private static func scope(_ text: NSString, source: String, selection: NSRange) -> Scope {
        guard NSMaxRange(selection) <= text.length else { return .nowhere }
        let lines = selectedLines(text, selection: selection)
        if selection.length > 0 {
            var targets: [Target] = []
            for line in lines {
                for segment in segments(text, line: line) where NSIntersectionRange(segment, selection).length > 0 {
                    let scan = InlineScanner.scan(text, source: source, range: segment)
                    // A selection that only clips a link's address or a tag on this line has no words here.
                    if let range = normalized(selection, in: scan, text: text),
                       items(text, scan: scan, hull: range, dropping: nil).contains(where: { $0.kind == .text || $0.kind == .atom }) {
                        targets.append(Target(scan: scan, range: range))
                    }
                }
            }
            return targets.isEmpty ? .nowhere : .targets(targets, isWord: false)
        }
        guard let line = lines.first, line.isText else { return .nowhere }
        let caret = selection.location
        guard let segment = caretSegment(text, line: line, caret: caret) else { return .nowhere }
        guard segment.length > 0, segment.location <= caret, caret <= NSMaxRange(segment) else { return .emptyCaret }
        let scan = InlineScanner.scan(text, source: source, range: segment)
        var tokens = scan.atoms.map { ($0, true) } + scan.strays.map { ($0, false) }
        for pair in scan.pairs { tokens += [(pair.open, false), (pair.close, false)] }
        for (token, isAtom) in tokens where token.location < caret && caret < NSMaxRange(token) {
            return isAtom ? .targets([Target(scan: scan, range: token)], isWord: true) : .nowhere
        }
        func isWord(_ index: Int) -> Bool {
            guard index >= segment.location, index < NSMaxRange(segment), !tokens.contains(where: { NSLocationInRange(index, $0.0) }),
                  let scalar = UnicodeScalar(text.character(at: index)) else { return false }
            return wordCharacters.contains(scalar)
        }
        var start = caret, end = caret
        while isWord(start - 1) { start -= 1 }
        while isWord(end) { end += 1 }
        guard end > start else { return .emptyCaret }
        return .targets([Target(scan: scan, range: NSRange(location: start, length: end - start))], isWord: true)
    }

    /// The words the caret is among. An empty range means the caret is somewhere a pair of marks can be
    /// typed (a blank line, an empty list item or table cell); nil means it is among the line's own syntax.
    private static func caretSegment(_ text: NSString, line: Line, caret: Int) -> NSRange? {
        if line.isText, isBlank(text, line.content) { return NSRange(location: caret, length: 0) }
        switch layout(text, line: line) {
        case .structure:
            return nil
        case let .body(body):
            guard caret >= body.location else { return nil }
            return caret <= NSMaxRange(body) ? body : NSRange(location: caret, length: 0)
        case let .cells(cells):
            guard let cell = cells.first(where: { $0.location <= caret && caret <= NSMaxRange($0) }) else { return nil }
            let words = trimmed(text, cell)
            return words.length > 0 && words.location <= caret && caret <= NSMaxRange(words) ? words : NSRange(location: caret, length: 0)
        }
    }

    /// The span of this format the caret sits in, when the caret isn't on a word.
    private static func enclosing(_ text: NSString, source: String, format: InlineFormat, caret: Int) -> (target: Target, value: String)? {
        guard let line = selectedLines(text, selection: NSRange(location: caret, length: 0)).first, line.isText,
              let segment = caretSegment(text, line: line, caret: caret), segment.length > 0 else { return nil }
        let scan = InlineScanner.scan(text, source: source, range: segment)
        guard let pair = scan.pairs.last(where: { $0.format == format && $0.inner.location <= caret && caret <= NSMaxRange($0.inner) && $0.inner.length > 0 }),
              let range = normalized(pair.inner, in: scan, text: text) else { return nil }
        return (Target(scan: scan, range: range), pair.value)
    }

    /// An empty pair of this format's marks with the caret between them, as `toggle` leaves when there is
    /// nothing to wrap. Returns the whole pair.
    private static func emptyPair(_ text: NSString, source: String, format: InlineFormat, caret: Int) -> NSRange? {
        // Never in code or frontmatter, where `**` is just two asterisks.
        guard let row = selectedLines(text, selection: NSRange(location: caret, length: 0)).first, row.isMarkdown else { return nil }
        // Among a line's words, or else the pair must be the whole line: one typed on an empty line reads as
        // something else until it is typed into (`****` is a rule), and asking again still takes it away.
        let whole = trimmed(text, row.content)
        var line = whole
        var isWholeLine = true
        if row.isText, let segment = caretSegment(text, line: row, caret: caret), segment.length > 0 {
            line = segment
            isWholeLine = false
        }
        guard line.length > 0, line.location <= caret, caret <= NSMaxRange(line) else { return nil }
        let scan = InlineScanner.scan(text, source: source, range: line)
        var found: NSRange?
        if let pair = scan.pairs.first(where: { $0.format == format && NSMaxRange($0.open) == caret && $0.close.location == caret }) {
            found = pair.outer
        } else {
            let mark = format.markers().open
            guard mark == format.markers().close, let character = mark.utf16.first, Set(mark.utf16).count == 1 else { return nil }
            var before = 0, after = 0
            while caret - before - 1 >= line.location, text.character(at: caret - before - 1) == character { before += 1 }
            while caret + after < NSMaxRange(line), text.character(at: caret + after) == character { after += 1 }
            let count = min(before, after), width = mark.utf16.count
            guard width == 1 ? count % 2 == 1 : count >= 2 else { return nil }
            let candidate = NSRange(location: caret - width, length: width * 2)
            // The caret in the middle of the `**` that opens real bold text is not between an empty pair of `*`:
            // taking those two away would break the bold. The same goes for code, links and addresses.
            var taken = scan.atoms + scan.strays
            for pair in scan.pairs where pair.inner.length > 0 { taken += [pair.open, pair.close] }
            guard !taken.contains(where: { NSIntersectionRange($0, candidate).length > 0 }) else { return nil }
            found = candidate
        }
        guard let found, !isWholeLine || NSEqualRanges(found, whole) else { return nil }
        return found
    }

    /// An empty pair of marks to type into, with the caret between them. Nil where the marks would read as
    /// something else: `~~~~` at the start of a line opens a code block that swallows the rest of the note.
    /// And marks typed straight after a bare web address would become part of the address.
    private static func emptyInsertion(_ format: InlineFormat, value: String, text: NSString, source: String, selection: NSRange) -> TextEdit? {
        let caret = selection.location
        guard let row = selectedLines(text, selection: selection).first else { return nil }
        if format == .strikethrough {
            let lead = text.substring(with: NSRange(location: row.content.location, length: caret - row.content.location))
            let marks = CharacterSet(charactersIn: " \t>-*+[]xX.)0123456789")
            if lead.unicodeScalars.allSatisfy({ marks.contains($0) }) { return nil }
        }
        if let segment = caretSegment(text, line: row, caret: caret), segment.length > 0, caret > segment.location {
            let closers: Set<unichar> = [0x29, 0x5D, 0x60, 0x3E]
            let atoms = InlineScanner.scan(text, source: source, range: segment).atoms
            if atoms.contains(where: { NSMaxRange($0) == caret }), !closers.contains(text.character(at: caret - 1)) { return nil }
        }
        let marks = format.markers(value: value)
        return TextEdit(
            range: selection, replacement: marks.open + marks.close,
            selection: NSRange(location: selection.location + (marks.open as NSString).length, length: 0)
        )
    }

    private static func apply(_ format: InlineFormat, value: String?, to targets: [Target], isWord: Bool, text: NSString, selection: NSRange) -> TextEdit? {
        var edits: [Retag] = []
        for target in targets {
            guard let edit = retag(text, target: target, format: format, value: value) else { return nil }
            edits.append(edit)
        }
        edits.sort { $0.range.location < $1.range.location }
        guard let first = edits.first, let last = edits.last,
              edits.contains(where: { $0.replacement != text.substring(with: $0.range) }) else { return nil }
        let range = NSRange(location: first.range.location, length: NSMaxRange(last.range) - first.range.location)
        var replacement = ""
        var cursor = range.location
        for edit in edits {
            guard edit.range.location >= cursor else { return nil }
            replacement += text.substring(with: NSRange(location: cursor, length: edit.range.location - cursor)) + edit.replacement
            cursor = NSMaxRange(edit.range)
        }
        func map(_ position: Int, toEnd: Bool) -> Int {
            var delta = 0
            for edit in edits {
                if position < edit.range.location { return position + delta }
                if position <= NSMaxRange(edit.range) { return edit.range.location + delta + edit.map(position, toEnd: toEnd) }
                delta += (edit.replacement as NSString).length - edit.range.length
            }
            return position + delta
        }
        let newSelection: NSRange
        if selection.length == 0 {
            let atStart = isWord && selection.location == (targets.first?.range.location ?? -1)
            newSelection = NSRange(location: map(selection.location, toEnd: !atStart), length: 0)
        } else {
            var start = map(selection.location, toEnd: false)
            var end = max(map(NSMaxRange(selection), toEnd: true), start)
            var delta = 0
            for (index, edit) in edits.enumerated() {
                if let formatted = edit.formatted {
                    if index == 0 { start = min(max(start, edit.range.location + delta + formatted.start), end) }
                    if index == edits.count - 1 { end = max(min(end, edit.range.location + delta + formatted.end), start) }
                }
                delta += (edit.replacement as NSString).length - edit.range.length
            }
            newSelection = NSRange(location: start, length: end - start)
        }
        return TextEdit(range: range, replacement: replacement, selection: newSelection)
    }

    // MARK: Inline commands

    /// A selection moved out to the edges of the characters it cuts into, so marks never land inside an
    /// emoji or between a letter and its accent. Text views don't hand over such selections; this is a backstop.
    private static func wholeCharacters(_ selection: NSRange, in text: NSString) -> NSRange {
        var start = selection.location, end = NSMaxRange(selection)
        if start < text.length { start = text.rangeOfComposedCharacterSequence(at: start).location }
        if end < text.length, end > 0 {
            let character = text.rangeOfComposedCharacterSequence(at: end)
            if character.location < end { end = selection.length == 0 ? character.location : NSMaxRange(character) }
        }
        return NSRange(location: start, length: max(end - start, 0))
    }

    /// Turns a format on for the selection, or off when all of it already has it. With nothing selected it
    /// acts on the word under the caret; with no word there, it types an empty pair of marks and puts the
    /// caret between them (and takes that pair away again if asked twice). `value` is the color or size.
    public static func toggle(_ format: InlineFormat, value: String = "", in string: String, selection: NSRange) -> TextEdit? {
        let text = string as NSString
        guard NSMaxRange(selection) <= text.length else { return nil }
        let selection = wholeCharacters(selection, in: text)
        if selection.length == 0, let pair = emptyPair(text, source: string, format: format, caret: selection.location) {
            return TextEdit(range: pair, replacement: "", selection: NSRange(location: pair.location, length: 0))
        }
        switch scope(text, source: string, selection: selection) {
        case .nowhere:
            return nil
        case .emptyCaret:
            // Between words inside a span of this format: the whole span comes off.
            if let inside = enclosing(text, source: string, format: format, caret: selection.location) {
                return apply(format, value: nil, to: [inside.target], isWord: false, text: text, selection: selection)
            }
            return emptyInsertion(format, value: value, text: text, source: string, selection: selection)
        case let .targets(targets, isWord):
            let covered = coverage(text, targets: targets, format: format) != .none
            return apply(format, value: covered ? nil : value, to: targets, isWord: isWord, text: text, selection: selection)
        }
    }

    /// Gives the selection (or the word under the caret) this exact value, replacing whatever value of the
    /// same format it had: a new color replaces the old one instead of nesting inside it. Nil removes the format.
    public static func set(_ format: InlineFormat, value: String?, in string: String, selection: NSRange) -> TextEdit? {
        let text = string as NSString
        guard NSMaxRange(selection) <= text.length else { return nil }
        let selection = wholeCharacters(selection, in: text)
        if selection.length == 0, let pair = emptyPair(text, source: string, format: format, caret: selection.location) {
            guard let value else { return TextEdit(range: pair, replacement: "", selection: NSRange(location: pair.location, length: 0)) }
            let marks = format.markers(value: value)
            guard text.substring(with: pair) != marks.open + marks.close else { return nil }
            return TextEdit(
                range: pair, replacement: marks.open + marks.close,
                selection: NSRange(location: pair.location + (marks.open as NSString).length, length: 0)
            )
        }
        switch scope(text, source: string, selection: selection) {
        case .nowhere:
            return nil
        case .emptyCaret:
            if let inside = enclosing(text, source: string, format: format, caret: selection.location) {
                return apply(format, value: value, to: [inside.target], isWord: false, text: text, selection: selection)
            }
            guard let value else { return nil }
            return emptyInsertion(format, value: value, text: text, source: string, selection: selection)
        case let .targets(targets, isWord):
            return apply(format, value: value, to: targets, isWord: isWord, text: text, selection: selection)
        }
    }

    /// Makes the selected text one size larger (1) or smaller (-1): 0.85em, normal, 1.15em, 1.3em, 1.6em.
    public static func stepSize(_ delta: Int, in string: String, selection: NSRange) -> TextEdit? {
        let steps = [FormatPalette.sizes[0], ""] + FormatPalette.sizes.dropFirst()
        let current = formats(in: string, selection: selection, blocks: false).textSize ?? ""
        guard let index = steps.firstIndex(of: current) else { return nil }
        let next = min(max(index + delta, 0), steps.count - 1)
        guard next != index else { return nil }
        return set(.textSize, value: steps[next].isEmpty ? nil : steps[next], in: string, selection: selection)
    }

    /// Backspace or Delete on one character of a formatting tag (`<span style="color: …">`, `</u>`, `<mark …>`)
    /// takes the whole pair of tags away and leaves the words: half a tag is never left behind as stray
    /// text. Nil when the character isn't part of a tag pair Perch writes, and the key does what it always does.
    public static func deletingTag(in string: String, range: NSRange) -> TextEdit? {
        let text = string as NSString
        guard range.length == 1, NSMaxRange(range) <= text.length,
              let line = selectedLines(text, selection: NSRange(location: range.location, length: 0)).first, line.isText else { return nil }
        for segment in segments(text, line: line) where segment.location <= range.location && NSMaxRange(range) <= NSMaxRange(segment) {
            let scan = InlineScanner.scan(text, source: string, range: segment)
            // The innermost pair with a tag under the key.
            let hit = scan.pairs.last { pair in
                pair.format != nil && text.character(at: pair.open.location) == 0x3C
                    && (NSIntersectionRange(pair.open, range).length > 0 || NSIntersectionRange(pair.close, range).length > 0)
            }
            guard let pair = hit else { return nil }
            let inOpen = NSIntersectionRange(pair.open, range).length > 0
            return TextEdit(
                range: pair.outer, replacement: text.substring(with: pair.inner),
                selection: NSRange(location: pair.open.location + (inOpen ? 0 : pair.inner.length), length: 0)
            )
        }
        return nil
    }

    /// Takes bold, italic, strikethrough, underline, highlight, color, size, subscript and superscript off
    /// the selection. Links and code stay.
    public static func clearFormatting(in string: String, selection: NSRange) -> TextEdit? {
        var working = string
        var range = selection
        for format in InlineFormat.allCases {
            guard let edit = set(format, value: nil, in: working, selection: range) else { continue }
            working = edit.applied(to: working)
            range = edit.selection
        }
        return TextEdit.difference(from: string, to: working, selection: range)
    }

    /// Inline code: wraps the selection, or the word under the caret, in backticks; unwraps it when it already is.
    public static func toggleCode(in string: String, selection: NSRange) -> TextEdit? {
        let text = string as NSString
        guard NSMaxRange(selection) <= text.length, !text.substring(with: selection).contains("\n") else { return nil }
        guard let line = selectedLines(text, selection: selection).first, line.isText else { return nil }
        if selection.length == 0, case let .targets(targets, _) = scope(text, source: string, selection: selection), let word = targets.first?.range {
            let source = text.substring(with: word)
            if source.hasPrefix("`"), source.hasSuffix("`"), word.length >= 2 {
                let inner = (source as NSString).substring(with: NSRange(location: 1, length: word.length - 2))
                return TextEdit(range: word, replacement: inner, selection: NSRange(location: max(word.location, min(selection.location - 1, word.location + word.length - 2)), length: 0))
            }
            return TextEdit(range: word, replacement: "`" + source + "`", selection: NSRange(location: selection.location + 1, length: 0))
        }
        return MarkdownEditing.toggleWrap(in: string, selection: selection, left: "`", right: "`")
    }

    // MARK: What is active

    /// The formatting at the caret, or shared by everything selected.
    public static func formats(in string: String, selection: NSRange) -> ActiveFormats {
        formats(in: string, selection: selection, blocks: true)
    }

    private static func formats(in string: String, selection: NSRange, blocks: Bool) -> ActiveFormats {
        var active = ActiveFormats()
        let text = string as NSString
        guard NSMaxRange(selection) <= text.length else { return active }
        let all = lines(text, through: NSMaxRange(selection))
        let selected = selectedLines(text, selection: selection, all: all)
        guard let first = selected.first else { return active }

        if blocks {
            switch first.before {
            case .fence, .math: active.inCodeBlock = true
            default:
                if case .fence = first.after { active.inCodeBlock = true }
                if first.after == .math { active.inCodeBlock = true }
            }
            let source = text.substring(with: first.content)
            let local = NSRange(location: 0, length: first.content.length)
            if first.isText {
                if let heading = headingLead.firstMatch(in: source, range: local) { active.headingLevel = heading.range(at: 1).length }
                if let item = MarkdownEditing.parseItem(source) {
                    active.list = item.box != nil ? .task : (item.number != nil ? .numbered : .bullet)
                }
                active.inTable = source.trimmingCharacters(in: .whitespaces).hasPrefix("|")
                if quoteLead.firstMatch(in: source, range: local) != nil {
                    active.quote = true
                    if let index = all.firstIndex(where: { $0.content.location == first.content.location }) {
                        active.callout = calloutHeader(text, lines: all, at: index)?.type
                    }
                }
            }
            // Only a note that opens a `<div align>` above the caret is read to its end to find the close.
            if first.isMarkdown, let index = all.firstIndex(where: { $0.content.location == first.content.location }), hasDivAbove(text, lines: all, at: index) {
                active.alignment = enclosingDiv(text, lines: lines(text, through: text.length), at: index)?.alignment
            }
        }

        if selection.length == 0 {
            guard first.isText, let segment = caretSegment(text, line: first, caret: selection.location), segment.length > 0 else { return active }
            let scan = InlineScanner.scan(text, source: string, range: segment)
            let caret = selection.location
            func at(_ format: InlineFormat) -> String? { value(of: format, at: caret, in: scan, inclusive: true) }
            active.bold = at(.bold) != nil
            active.italic = at(.italic) != nil
            active.strikethrough = at(.strikethrough) != nil
            active.underline = at(.underline) != nil
            active.subscript = at(.subscript) != nil
            active.superscript = at(.superscript) != nil
            active.highlight = at(.highlight)
            active.textColor = at(.textColor)
            active.textSize = at(.textSize)
            active.link = scan.pairs.contains { $0.format == nil && $0.open.length == 1 && text.character(at: $0.open.location) == 0x5B && $0.inner.location <= caret && caret <= NSMaxRange($0.inner) }
            active.code = scan.atoms.contains { $0.location < caret && caret < NSMaxRange($0) && text.character(at: $0.location) == 0x60 }
            return active
        }
        guard case let .targets(targets, _) = scope(text, source: string, selection: selection) else { return active }
        func common(_ format: InlineFormat) -> Coverage { coverage(text, targets: targets, format: format) }
        func single(_ format: InlineFormat) -> String? {
            if case let .all(value) = common(format) { return value }
            return nil
        }
        active.bold = common(.bold) != .none
        active.italic = common(.italic) != .none
        active.strikethrough = common(.strikethrough) != .none
        active.underline = common(.underline) != .none
        active.subscript = common(.subscript) != .none
        active.superscript = common(.superscript) != .none
        active.highlight = single(.highlight)
        active.textColor = single(.textColor)
        active.textSize = single(.textSize)
        active.code = targets.allSatisfy { target in
            target.scan.atoms.contains { $0.location <= target.range.location && NSMaxRange($0) >= NSMaxRange(target.range) && text.character(at: $0.location) == 0x60 }
        }
        active.link = targets.allSatisfy { target in
            target.scan.pairs.contains { $0.format == nil && text.character(at: $0.open.location) == 0x5B && $0.inner.location <= target.range.location && NSMaxRange($0.inner) >= NSMaxRange(target.range) }
        }
        return active
    }

    // MARK: Block commands

    /// Where a selection ends up after `range` is replaced by text of `length`.
    private static func shifted(_ selection: NSRange, replacing range: NSRange, length: Int) -> NSRange {
        func move(_ position: Int) -> Int {
            if position <= range.location { return position }
            if position >= NSMaxRange(range) { return position + length - range.length }
            return min(position, range.location + length)
        }
        let start = move(selection.location)
        return NSRange(location: start, length: max(move(NSMaxRange(selection)) - start, 0))
    }

    /// Rewrites each selected line with `change`, as one edit. Lines keep their own line endings.
    /// `change` gets the line without its ending and its place in the selection; nil leaves the line alone.
    private static func rewriteLines(
        _ text: NSString, selection: NSRange, lines: [Line], _ change: (String, Int, Line) -> String?
    ) -> TextEdit? {
        guard let first = lines.first, let last = lines.last else { return nil }
        let block = NSRange(location: first.content.location, length: NSMaxRange(last.content) - first.content.location)
        var replacement = ""
        var firstDelta = 0
        var changedAny = false
        for (index, line) in lines.enumerated() {
            let old = text.substring(with: line.content)
            let new = change(old, index, line) ?? old
            if new != old { changedAny = true }
            if index == 0 { firstDelta = (new as NSString).length - line.content.length }
            replacement += new
            if index < lines.count - 1 {
                replacement += text.substring(with: NSRange(location: NSMaxRange(line.content), length: lines[index + 1].content.location - NSMaxRange(line.content)))
            }
        }
        guard changedAny else { return nil }
        let length = (replacement as NSString).length
        let newSelection = selection.length == 0
            ? NSRange(location: min(max(first.content.location, selection.location + firstDelta), block.location + length), length: 0)
            : NSRange(location: block.location, length: length)
        return TextEdit(range: block, replacement: replacement, selection: newSelection)
    }

    /// Makes the selected lines headings of this level (1 to 6), or body text for 0. Asking for the level
    /// they already have turns them back into body text.
    public static func setHeading(_ level: Int, in string: String, selection: NSRange) -> TextEdit? {
        let text = string as NSString
        guard NSMaxRange(selection) <= text.length else { return nil }
        let chosen = selectedLines(text, selection: selection)
        let lines = chosen.filter { $0.isText && (chosen.count == 1 || !isBlank(text, $0.content)) }
        guard !lines.isEmpty else { return nil }
        func current(_ line: Line) -> Int {
            let source = text.substring(with: line.content)
            return headingLead.firstMatch(in: source, range: NSRange(location: 0, length: line.content.length))?.range(at: 1).length ?? 0
        }
        let target = level > 0 && lines.allSatisfy({ current($0) == level }) ? 0 : min(max(level, 0), 6)
        return rewriteLines(text, selection: selection, lines: chosen) { source, _, line in
            guard line.isText, chosen.count == 1 || !isBlank(text, line.content) else { return nil }
            let local = NSRange(location: 0, length: (source as NSString).length)
            let prefix = target == 0 ? "" : String(repeating: "#", count: target) + " "
            if let heading = headingLead.firstMatch(in: source, range: local) {
                return prefix + (source as NSString).substring(from: heading.range.length)
            }
            guard target > 0 else { return nil }
            // A heading can sit inside a quote, but not inside a list item: the list marker goes.
            if let item = MarkdownEditing.parseItem(source) {
                return item.quote + prefix + (source as NSString).substring(from: item.prefixLength)
            }
            if let quote = quoteLead.firstMatch(in: source, range: local) {
                return (source as NSString).substring(to: quote.range.length) + prefix + (source as NSString).substring(from: quote.range.length)
            }
            return prefix + source.drop { $0 == " " || $0 == "\t" }
        }
    }

    /// Quotes the selected lines with `> `, or takes one level of quoting off when they all have it.
    public static func toggleQuote(in string: String, selection: NSRange) -> TextEdit? {
        let text = string as NSString
        guard NSMaxRange(selection) <= text.length else { return nil }
        let lines = selectedLines(text, selection: selection)
        guard !lines.isEmpty, canQuote(lines) else { return nil }
        let filled = lines.filter { !isBlank(text, $0.content) }
        func isQuoted(_ line: Line) -> Bool {
            quoteLead.firstMatch(in: text.substring(with: line.content), range: NSRange(location: 0, length: line.content.length)) != nil
        }
        let removing = !filled.isEmpty && filled.allSatisfy(isQuoted)
        return rewriteLines(text, selection: selection, lines: lines) { source, _, line in
            if removing {
                guard let quote = quoteLead.firstMatch(in: source, range: NSRange(location: 0, length: (source as NSString).length)) else { return nil }
                let marks = (source as NSString).substring(with: quote.range(at: 2))
                var rest = String(marks.dropFirst())
                if rest.hasPrefix(" ") || rest.hasPrefix("\t") { rest.removeFirst() }
                return (source as NSString).substring(with: quote.range(at: 1)) + rest + (source as NSString).substring(from: quote.range.length)
            }
            return isBlank(text, line.content) && lines.count > 1 ? ">" + source : "> " + source
        }
    }

    /// Quote marks may go in front of ordinary lines, and in front of a whole code block, fences and all.
    /// Never in front of part of one, which would put `> ` inside the code, and never in frontmatter.
    private static func canQuote(_ lines: [Line]) -> Bool {
        guard let first = lines.first, let last = lines.last, first.before == .normal, last.after == .normal else { return false }
        return !lines.contains { $0.before == .frontmatter || $0.after == .frontmatter || $0.raw }
    }

    public static let calloutTypes = ["note", "tip", "info", "success", "question", "warning", "danger", "example", "quote"]

    private static func calloutHeader(_ text: NSString, lines: [Line], at index: Int) -> (line: Int, type: String, tag: NSRange)? {
        func quote(_ line: Line) -> NSTextCheckingResult? {
            guard line.isText else { return nil }
            return quoteLead.firstMatch(in: text.substring(with: line.content), range: NSRange(location: 0, length: line.content.length))
        }
        guard quote(lines[index]) != nil else { return nil }
        var top = index
        while top > 0, quote(lines[top - 1]) != nil { top -= 1 }
        guard let lead = quote(lines[top]) else { return nil }
        let source = text.substring(with: lines[top].content)
        guard let tag = calloutLead.firstMatch(in: source, options: .anchored, range: NSRange(location: lead.range.length, length: lines[top].content.length - lead.range.length)) else { return nil }
        let type = (source as NSString).substring(with: tag.range(at: 1)).lowercased()
        return (top, type, NSRange(location: lines[top].content.location + tag.range.location, length: tag.range.length))
    }

    /// Makes a callout of this type (`> [!note]`), or changes the type of the one the caret is in. Nil
    /// turns a callout back into a plain quote.
    public static func setCallout(_ type: String?, in string: String, selection: NSRange) -> TextEdit? {
        let text = string as NSString
        guard NSMaxRange(selection) <= text.length else { return nil }
        let all = lines(text, through: NSMaxRange(selection))
        let chosen = selectedLines(text, selection: selection, all: all)
        guard let first = chosen.first, let index = all.firstIndex(where: { $0.content.location == first.content.location }) else { return nil }
        let eol = lineBreak(text)
        if let header = calloutHeader(text, lines: all, at: index) {
            guard let type else {
                return TextEdit(range: header.tag, replacement: "", selection: shifted(selection, replacing: header.tag, length: 0))
            }
            guard type.lowercased() != header.type else { return nil }
            let word = NSRange(location: header.tag.location + 2, length: (header.type as NSString).length)
            return TextEdit(range: word, replacement: type, selection: shifted(selection, replacing: word, length: (type as NSString).length))
        }
        guard let type, canQuote(chosen) else { return nil }
        if chosen.count == 1, isBlank(text, first.content) {
            let insertion = "> [!\(type)] Title" + eol + "> "
            return TextEdit(range: first.content, replacement: insertion, selection: NSRange(location: first.content.location + (insertion as NSString).length, length: 0))
        }
        let head = "> [!\(type)]" + eol
        let quoted = text.substring(with: first.content).hasPrefix(">")
        guard let last = chosen.last else { return nil }
        let block = NSRange(location: first.content.location, length: NSMaxRange(last.content) - first.content.location)
        var body = ""
        for (position, line) in chosen.enumerated() {
            let source = text.substring(with: line.content)
            body += quoted ? source : (isBlank(text, line.content) ? ">" + source : "> " + source)
            if position < chosen.count - 1 {
                body += text.substring(with: NSRange(location: NSMaxRange(line.content), length: chosen[position + 1].content.location - NSMaxRange(line.content)))
            }
        }
        let headLength = (head as NSString).length
        let newSelection = selection.length == 0
            ? NSRange(location: selection.location + headLength + (quoted ? 0 : 2), length: 0)
            : NSRange(location: block.location + headLength, length: (body as NSString).length)
        return TextEdit(range: block, replacement: head + body, selection: newSelection)
    }

    /// Wraps the selected lines in a fenced code block, or takes the fences off the block the caret is in.
    public static func toggleCodeBlock(language: String = "", in string: String, selection: NSRange) -> TextEdit? {
        let text = string as NSString
        guard NSMaxRange(selection) <= text.length else { return nil }
        let all = lines(text, through: text.length)
        let chosen = selectedLines(text, selection: selection, all: all)
        guard let first = chosen.first, let last = chosen.last, let index = all.firstIndex(where: { $0.content.location == first.content.location }) else { return nil }
        func isFence(_ state: MarkdownBlockState) -> Bool { if case .fence = state { return true } else { return false } }
        let eol = lineBreak(text)
        if isFence(first.before) || isFence(first.after) {
            var open = index
            while open > 0, isFence(all[open].before) { open -= 1 }
            guard all[open].before == .normal, isFence(all[open].after) else { return nil }
            var close = open + 1
            while close < all.count, !(isFence(all[close].before) && all[close].after == .normal) { close += 1 }
            let innerStart = NSMaxRange(all[open].full)
            guard close < all.count else {
                // Never closed: only the opening line goes.
                return TextEdit(range: all[open].full, replacement: "", selection: NSRange(location: max(selection.location - all[open].full.length, all[open].full.location), length: 0))
            }
            let innerEnd = close > open + 1 ? NSMaxRange(all[close - 1].content) : innerStart
            let inner = innerEnd > innerStart ? text.substring(with: NSRange(location: innerStart, length: innerEnd - innerStart)) : ""
            let range = NSRange(location: all[open].full.location, length: NSMaxRange(all[close].content) - all[open].full.location)
            let caret = min(max(selection.location - all[open].full.length, range.location), range.location + (inner as NSString).length)
            return TextEdit(range: range, replacement: inner, selection: NSRange(location: caret, length: 0))
        }
        // Indented code and raw HTML can go inside a fence; a block that is already fenced, math or frontmatter can't.
        guard chosen.allSatisfy({ $0.isMarkdown }) else { return nil }
        let block = NSRange(location: first.content.location, length: NSMaxRange(last.content) - first.content.location)
        let head = "```" + language + eol
        let body = text.substring(with: block)
        let headLength = (head as NSString).length
        let newSelection = selection.length == 0
            ? NSRange(location: selection.location + headLength, length: 0)
            : NSRange(location: block.location + headLength, length: block.length)
        return TextEdit(range: block, replacement: head + body + eol + "```", selection: newSelection)
    }

    /// Where a new block goes: in place of a blank line, or under the caret's line with a blank line between.
    private static func insertBlock(_ block: String, text: NSString, selection: NSRange, select: NSRange? = nil) -> TextEdit? {
        guard NSMaxRange(selection) <= text.length else { return nil }
        let all = lines(text, through: NSMaxRange(selection))
        guard let line = selectedLines(text, selection: NSRange(location: NSMaxRange(selection), length: 0), all: all).first, line.isText,
              let index = all.firstIndex(where: { $0.content.location == line.content.location }) else { return nil }
        let eol = lineBreak(text)
        let blank = isBlank(text, line.content)
        let previousBlank = index == 0 || isBlank(text, all[index - 1].content)
        let lead = blank ? (previousBlank ? "" : eol) : eol + eol
        let range = blank ? line.content : NSRange(location: NSMaxRange(line.content), length: 0)
        let start = range.location + (lead as NSString).length
        let replacement = lead + block + eol
        let newSelection = select.map { NSRange(location: start + $0.location, length: $0.length) }
            ?? NSRange(location: range.location + (replacement as NSString).length, length: 0)
        return TextEdit(range: range, replacement: replacement, selection: newSelection)
    }

    /// Adds a `---` divider under the caret's line.
    public static func insertDivider(in string: String, selection: NSRange) -> TextEdit? {
        insertBlock("---", text: string as NSString, selection: selection)
    }

    /// Adds a table with a header row and this many rows and columns under the caret's line, with the first
    /// header selected ready to type over.
    public static func insertTable(rows: Int, columns: Int, in string: String, selection: NSRange) -> TextEdit? {
        let text = string as NSString
        let eol = lineBreak(text)
        let columns = min(max(columns, 1), 12), rows = min(max(rows, 1), 50)
        let header = "| " + (1...columns).map { "Column \($0)" }.joined(separator: " | ") + " |"
        let rule = "|" + String(repeating: " --- |", count: columns)
        let row = "|" + String(repeating: "  |", count: columns)
        let table = ([header, rule] + Array(repeating: row, count: rows)).joined(separator: eol)
        return insertBlock(table, text: text, selection: selection, select: NSRange(location: 2, length: 8))
    }

    private struct Table {
        var rows: [Line]
        /// The row holding the caret.
        var row: Int
        /// The cells of each row, spaces included.
        var cells: [[NSRange]]
        var isRule: [Bool]
    }

    private static func table(_ text: NSString, at location: Int) -> Table? {
        let all = lines(text, through: text.length)
        guard let index = all.firstIndex(where: { $0.content.location <= location && location <= NSMaxRange($0.content) }) else { return nil }
        func isRow(_ line: Line) -> Bool {
            line.isText && text.substring(with: line.content).trimmingCharacters(in: .whitespaces).hasPrefix("|")
        }
        guard isRow(all[index]) else { return nil }
        var top = index, bottom = index
        while top > 0, isRow(all[top - 1]) { top -= 1 }
        while bottom + 1 < all.count, isRow(all[bottom + 1]) { bottom += 1 }
        let rows = Array(all[top...bottom])
        return Table(
            rows: rows, row: index - top, cells: rows.map { cells(text, $0.content) },
            isRule: rows.map { delimiterRow.firstMatch(in: text.substring(with: $0.content), range: NSRange(location: 0, length: $0.content.length)) != nil }
        )
    }

    /// Where the caret goes in a cell: around its words, or just inside an empty one.
    private static func cellSelection(_ text: NSString, _ cell: NSRange) -> NSRange {
        let words = trimmed(text, cell)
        if words.length > 0 { return words }
        return NSRange(location: cell.location + (cell.length >= 2 ? 1 : 0), length: 0)
    }

    private static func emptyRow(columns: Int) -> String {
        "|" + String(repeating: "  |", count: max(columns, 1))
    }

    /// How a table's column is aligned, from the marks in its rule row.
    private enum ColumnAlignment {
        case none, left, center, right

        init(rule: String) {
            let starts = rule.hasPrefix(":"), ends = rule.count > 1 && rule.hasSuffix(":")
            self = starts && ends ? .center : starts ? .left : ends ? .right : .none
        }

        /// The rule row's cell for a column this wide.
        func rule(width: Int) -> String {
            switch self {
            case .none: String(repeating: "-", count: width)
            case .left: ":" + String(repeating: "-", count: width - 1)
            case .right: String(repeating: "-", count: width - 1) + ":"
            case .center: ":" + String(repeating: "-", count: max(width - 2, 1)) + ":"
            }
        }

        /// The spaces before a cell's words, out of the room it has to spare.
        func lead(_ spare: Int) -> Int { self == .right ? spare : self == .center ? spare / 2 : 0 }
    }

    /// How many columns of the editor's fixed-width font text takes: two for emoji and for East Asian wide
    /// letters, one for everything else (an accent rides on its letter).
    static func displayWidth(_ text: String) -> Int {
        text.reduce(0) { total, character in
            guard let scalar = character.unicodeScalars.first else { return total }
            let value = scalar.value
            let wide = scalar.properties.isEmojiPresentation || character.unicodeScalars.contains { $0.value == 0xFE0F }
                || (0x1100...0x115F).contains(value) || (0x2E80...0xA4CF).contains(value) || (0xAC00...0xD7A3).contains(value)
                || (0xF900...0xFAFF).contains(value) || (0xFE30...0xFE4F).contains(value) || (0xFF00...0xFF60).contains(value)
                || (0xFFE0...0xFFE6).contains(value) || (0x20000...0x3FFFD).contains(value)
            return total + (wide ? 2 : 1)
        }
    }

    /// Tidy Table: pads every cell so the table's pipes line up in the editor's fixed-width font, with each
    /// column's alignment kept (and followed: right-aligned words sit at the right). A row short of cells gets
    /// empty ones up to the header's; cells past the header's are kept, never dropped. The table keeps its
    /// indent and line endings, and the caret stays where it was in its cell. Nil when the caret isn't in a
    /// table, or the table is already tidy.
    public static func tidyTable(in string: String, selection: NSRange) -> TextEdit? {
        let text = string as NSString
        guard NSMaxRange(selection) <= text.length, let table = table(text, at: selection.location),
              let first = table.rows.first, let last = table.rows.last, let header = table.cells.first, let opening = header.first else { return nil }
        let words = table.cells.map { $0.map { text.substring(with: trimmed(text, $0)) } }
        let columns = words.map(\.count).max() ?? 0
        var alignment = [ColumnAlignment](repeating: .none, count: columns)
        if let rule = table.isRule.firstIndex(of: true) {
            for (column, marks) in words[rule].enumerated() where column < columns { alignment[column] = ColumnAlignment(rule: marks) }
        }
        // At least three wide, the shortest rule a column can have.
        var widths = [Int](repeating: 3, count: columns)
        for (row, cells) in words.enumerated() where !table.isRule[row] {
            for (column, word) in cells.enumerated() { widths[column] = max(widths[column], displayWidth(word)) }
        }
        let start = first.content.location
        let indent = text.substring(with: NSRange(location: start, length: opening.location - 1 - start))

        // The caret: its cell, and how far into the cell's words.
        let caret = selection.location
        let caretCells = table.cells[table.row]
        let caretColumn = caretCells.lastIndex { $0.location - 1 <= caret }
        var caretOffset = 0
        if let caretColumn {
            let span = trimmed(text, caretCells[caretColumn])
            caretOffset = min(max(caret - span.location, 0), span.length)
        }

        let eol = lineBreak(text)
        var lines: [String] = []
        var written = 0
        var newCaret: Int?
        for (row, cells) in words.enumerated() {
            let count = table.isRule[row] ? header.count : max(cells.count, header.count)
            var line = indent + "|"
            for column in 0..<count {
                let width = widths[column]
                line += " "
                let here = row == table.row && column == caretColumn
                if table.isRule[row] {
                    if here { newCaret = written + (line as NSString).length }
                    line += alignment[column].rule(width: width)
                } else {
                    let word = column < cells.count ? cells[column] : ""
                    let spare = max(width - displayWidth(word), 0)
                    let lead = alignment[column].lead(spare)
                    if here { newCaret = written + (line as NSString).length + lead + min(caretOffset, (word as NSString).length) }
                    line += String(repeating: " ", count: lead) + word + String(repeating: " ", count: spare - lead)
                }
                line += " |"
            }
            lines.append(line)
            written += (line as NSString).length + (eol as NSString).length
        }
        let block = NSRange(location: start, length: NSMaxRange(last.content) - start)
        let replacement = lines.joined(separator: eol)
        guard replacement != text.substring(with: block) else { return nil }
        return TextEdit(range: block, replacement: replacement, selection: NSRange(location: start + (newCaret ?? 0), length: 0))
    }

    /// Tab and Shift-Tab inside a table: selects the next or previous cell. Tab in the last cell adds a row.
    /// Nil when the caret isn't in a table. An edit with nothing to replace only moves the selection.
    public static func tableMove(forward: Bool, in string: String, selection: NSRange) -> TextEdit? {
        let text = string as NSString
        guard NSMaxRange(selection) <= text.length, let table = table(text, at: selection.location) else { return nil }
        var places: [(row: Int, cell: NSRange)] = []
        for (row, cells) in table.cells.enumerated() where !table.isRule[row] { places += cells.map { (row, $0) } }
        guard !places.isEmpty else { return nil }
        let caret = selection.location
        let current = places.lastIndex { $0.row == table.row && $0.cell.location - 1 <= caret } ?? places.firstIndex { $0.row >= table.row }
        guard let current else { return nil }
        let next = current + (forward ? 1 : -1)
        if next < 0 { return TextEdit(range: NSRange(location: caret, length: 0), replacement: "", selection: selection) }
        if next >= places.count { return tableAddRow(in: string, selection: selection) }
        return TextEdit(range: NSRange(location: caret, length: 0), replacement: "", selection: cellSelection(text, places[next].cell))
    }

    /// Adds an empty row under the caret's row (under the header's rule when the caret is in the header).
    public static func tableAddRow(in string: String, selection: NSRange) -> TextEdit? {
        let text = string as NSString
        guard NSMaxRange(selection) <= text.length, let table = table(text, at: selection.location) else { return nil }
        var after = table.row
        if after + 1 < table.rows.count, table.isRule[after + 1] { after += 1 }
        let columns = table.cells.first?.count ?? table.cells[table.row].count
        let insertion = lineBreak(text) + emptyRow(columns: columns)
        let location = NSMaxRange(table.rows[after].content)
        return TextEdit(
            range: NSRange(location: location, length: 0), replacement: insertion,
            selection: NSRange(location: location + (insertion as NSString).length - (emptyRow(columns: columns) as NSString).length + 2, length: 0)
        )
    }

    /// Adds an empty column after the caret's column, in every row of the table.
    public static func tableAddColumn(in string: String, selection: NSRange) -> TextEdit? {
        let text = string as NSString
        guard NSMaxRange(selection) <= text.length, let table = table(text, at: selection.location), let first = table.rows.first, let last = table.rows.last else { return nil }
        let caret = selection.location
        let column = max(table.cells[table.row].lastIndex { $0.location - 1 <= caret } ?? 0, 0)
        let block = NSRange(location: first.content.location, length: NSMaxRange(last.content) - first.content.location)
        var replacement = ""
        var caretShift = 0
        var newCaret: Int?
        for (row, line) in table.rows.enumerated() {
            let cells = table.cells[row]
            let filler = table.isRule[row] ? " --- |" : "  |"
            let source = text.substring(with: line.content)
            let new: String
            if column < cells.count {
                // After the pipe that closes this cell.
                let split = min(NSMaxRange(cells[column]) + 1, NSMaxRange(line.content)) - line.content.location
                let closed = NSMaxRange(cells[column]) < NSMaxRange(line.content)
                new = (source as NSString).substring(to: split) + (closed ? "" : " |") + filler + (source as NSString).substring(from: split)
                if row == 0 { newCaret = block.location + (replacement as NSString).length + split + (closed ? 0 : 2) + 1 }
            } else {
                new = source + (source.trimmingCharacters(in: .whitespaces).hasSuffix("|") ? "" : " |") + filler
            }
            if row < table.row { caretShift += (new as NSString).length - line.content.length }
            replacement += new
            if row < table.rows.count - 1 {
                replacement += text.substring(with: NSRange(location: NSMaxRange(line.content), length: table.rows[row + 1].content.location - NSMaxRange(line.content)))
            }
        }
        return TextEdit(range: block, replacement: replacement, selection: NSRange(location: newCaret ?? caret + caretShift, length: 0))
    }

    private struct Div {
        var open: Int
        var close: Int
        var alignment: String
    }

    /// True when a `<div align>` opens at or above a line with no `</div>` in between.
    private static func hasDivAbove(_ text: NSString, lines: [Line], at index: Int) -> Bool {
        var line = index
        var steps = 0
        while line >= 0, steps < 5000 {
            if lines[line].isMarkdown, lines[line].content.length > 0, text.character(at: lines[line].content.location) == 0x3C || text.character(at: lines[line].content.location) == 0x20 || text.character(at: lines[line].content.location) == 0x09 {
                let source = text.substring(with: lines[line].content)
                let local = NSRange(location: 0, length: lines[line].content.length)
                if divOpen.firstMatch(in: source, range: local) != nil { return true }
                if line < index, divClose.firstMatch(in: source, range: local) != nil { return false }
            }
            line -= 1
            steps += 1
        }
        return false
    }

    /// The `<div align="…">` block around a line, if it is properly closed.
    private static func enclosingDiv(_ text: NSString, lines: [Line], at index: Int) -> Div? {
        func alignment(_ line: Line) -> String? {
            guard line.isMarkdown else { return nil }
            let source = text.substring(with: line.content)
            guard let match = divOpen.firstMatch(in: source, range: NSRange(location: 0, length: line.content.length)) else { return nil }
            return (source as NSString).substring(with: match.range(at: 1)).lowercased()
        }
        func closes(_ line: Line) -> Bool {
            line.isMarkdown && divClose.firstMatch(in: text.substring(with: line.content), range: NSRange(location: 0, length: line.content.length)) != nil
        }
        var open = index
        var steps = 0
        while true {
            if let found = alignment(lines[open]) {
                var close = open + 1
                while close < lines.count, !closes(lines[close]) {
                    if alignment(lines[close]) != nil { return nil }
                    close += 1
                }
                guard close < lines.count, close >= index else { return nil }
                return Div(open: open, close: close, alignment: found)
            }
            if open < index, closes(lines[open]) { return nil }
            guard open > 0, steps < 5000 else { return nil }
            open -= 1
            steps += 1
        }
    }

    /// Centers or right-aligns the selected lines by wrapping them in `<div align="…">`, with blank lines
    /// inside so the Markdown between still reads as Markdown. Nil, "left", or the alignment the block
    /// already has takes the wrapper away.
    public static func setAlignment(_ alignment: String?, in string: String, selection: NSRange) -> TextEdit? {
        let text = string as NSString
        guard NSMaxRange(selection) <= text.length else { return nil }
        let wanted: String? = alignment == "center" || alignment == "right" ? alignment : nil
        let all = lines(text, through: text.length)
        let chosen = selectedLines(text, selection: selection, all: all)
        guard let first = chosen.first, let last = chosen.last, let index = all.firstIndex(where: { $0.content.location == first.content.location }) else { return nil }
        let eol = lineBreak(text)
        if let div = enclosingDiv(text, lines: all, at: index) {
            let open = all[div.open], close = all[div.close]
            if let wanted, wanted != div.alignment {
                let source = text.substring(with: open.content)
                let indent = String(source.prefix { $0 == " " || $0 == "\t" })
                let line = indent + "<div align=\"\(wanted)\">"
                return TextEdit(range: open.content, replacement: line, selection: shifted(selection, replacing: open.content, length: (line as NSString).length))
            }
            var innerStart = NSMaxRange(open.full)
            var firstInner = div.open + 1
            if firstInner < div.close, isBlank(text, all[firstInner].content) {
                innerStart = NSMaxRange(all[firstInner].full)
                firstInner += 1
            }
            var lastInner = div.close - 1
            if lastInner >= firstInner, isBlank(text, all[lastInner].content) { lastInner -= 1 }
            let innerEnd = lastInner >= firstInner ? NSMaxRange(all[lastInner].content) : innerStart
            let inner = innerEnd > innerStart ? text.substring(with: NSRange(location: innerStart, length: innerEnd - innerStart)) : ""
            let range = NSRange(location: open.full.location, length: NSMaxRange(close.content) - open.full.location)
            let innerLength = (inner as NSString).length
            let start = min(max(selection.location - (innerStart - range.location), range.location), range.location + innerLength)
            let end = min(max(NSMaxRange(selection) - (innerStart - range.location), start), range.location + innerLength)
            return TextEdit(range: range, replacement: inner, selection: NSRange(location: start, length: end - start))
        }
        guard let wanted, chosen.allSatisfy({ $0.isText }) else { return nil }
        let block = NSRange(location: first.content.location, length: NSMaxRange(last.content) - first.content.location)
        let head = "<div align=\"\(wanted)\">" + eol + eol
        var tail = eol + eol + "</div>"
        // Markdown treats whatever follows `</div>` on the next line as more HTML, so leave a blank line.
        if let next = all.first(where: { $0.content.location > last.content.location }), !isBlank(text, next.content) { tail += eol }
        let headLength = (head as NSString).length
        let newSelection = selection.length == 0
            ? NSRange(location: selection.location + headLength, length: 0)
            : NSRange(location: block.location + headLength, length: block.length)
        return TextEdit(range: block, replacement: head + text.substring(with: block) + tail, selection: newSelection)
    }
}
