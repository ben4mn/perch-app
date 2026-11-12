import Foundation

/// What a stretch of Markdown source is, so an editor can style it. Display only: nothing here changes text.
public enum MarkdownSpanKind: Equatable, Sendable {
    case heading(level: Int)
    /// Syntax characters such as `#`, `**`, backticks and brackets, shown dimmed.
    case marker
    case strong
    case emphasis
    case strikethrough
    case highlight
    case inlineCode
    /// A whole line inside a fenced code or `$$` block, delimiters included.
    case codeBlock
    /// The opening or closing fence line itself.
    case codeFence
    case linkText
    case linkURL
    case wikiLink
    case listMarker
    case taskBox(checked: Bool)
    /// The text of a ticked task item.
    case taskDone
    case blockquote
    case calloutTag
    case frontmatter
    case frontmatterKey
    case rule
    case footnote
    case table
    case conflict
    case comment
    /// An HTML tag itself, such as `<br>`, `<details>` or `<kbd>`: shown small and dim.
    case htmlTag
    /// One of a pair of tags whose effect the editor draws, such as `<span style="color: #D94F3D">` and its
    /// `</span>`: shown small and dim, or hidden, since the words between them already show what it does.
    case formatTag
    /// Text inside a span with a color, as `#RRGGBB`.
    case textColor(String)
    /// Text inside a `<mark>` with its own background, as `#RRGGBB`.
    case highlightColor(String)
    case underline
    /// Text inside a span with a font size: 1.15 for `1.15em`.
    case textSize(Double)
    case `subscript`
    case superscript
}

public struct MarkdownSpan: Equatable, Sendable {
    public var range: NSRange
    public var kind: MarkdownSpanKind

    public init(range: NSRange, kind: MarkdownSpanKind) {
        self.range = range
        self.kind = kind
    }
}

/// The block a line sits in. Carried from one line to the next, so part of a note can be styled on its own.
public enum MarkdownBlockState: Equatable, Sendable {
    case normal
    case frontmatter
    /// Inside a fenced code block opened with this marker, such as "```" or "~~~~".
    case fence(String)
    case math

    /// A short text form, for storing on text as an attribute.
    public var code: String {
        switch self {
        case .normal: return "n"
        case .frontmatter: return "y"
        case let .fence(marker): return "f" + marker
        case .math: return "m"
        }
    }

    public init(code: String) {
        switch code.first {
        case "y": self = .frontmatter
        case "f": self = .fence(String(code.dropFirst()))
        case "m": self = .math
        default: self = .normal
        }
    }
}

public struct MarkdownLine: Equatable, Sendable {
    /// The line with its line ending.
    public var range: NSRange
    public var before: MarkdownBlockState
    public var after: MarkdownBlockState
    /// Length of the quote and list prefix, so wrapped lines can hang under the text.
    public var prefixLength: Int
}

public struct MarkdownHighlight: Equatable, Sendable {
    public var range: NSRange
    public var spans: [MarkdownSpan]
    public var lines: [MarkdownLine]
    public var endState: MarkdownBlockState
}

public enum MarkdownHighlighter {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are fixed and checked by the tests.
        try! NSRegularExpression(pattern: pattern)
    }

    static let fenceOpen = regex(#"^ {0,3}(`{3,}|~{3,})(.*)$"#)
    static let heading = regex(#"^(#{1,6})[ \t]+.*$"#)
    static let rule = regex(#"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
    static let quotePrefix = regex(#"^[ \t]*(?:>[ \t]?)+"#)
    static let callout = regex(#"\[![\w-]+\][+-]?"#)
    static let listPrefix = regex(#"^([ \t]*)([-*+]|\d{1,9}[.)])([ \t]+)(?:(\[[ xX]\])([ \t]+|$))?"#)
    private static let frontmatterKey = regex(#"^[\w][\w .-]*:"#)
    static let code = regex(#"(`+)(?!`)(.+?)(?<!`)\1(?!`)"#)
    static let wiki = regex(#"\[\[[^\[\]\n]+\]\]"#)
    static let link = regex(#"(!?\[)([^\]\n]*)(\]\()([^)\n]*)(\))"#)
    static let url = regex(#"(?<![\w(\[])https?://[^\s<>\])]+"#)
    static let footnote = regex(#"\[\^[^\]\s]+\]"#)
    private static let strongEmphasis = regex(#"(\*\*\*|___)(?=\S)(.+?)(?<=\S)\1"#)
    private static let strong = regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let starEmphasis = regex(#"(?<![*\\])(\*)(?=[^\s*])([^*\n]+?)(?<=[^\s*])\*(?!\*)"#)
    private static let underscoreEmphasis = regex(#"(?<![\w\\])(_)(?=[^\s_])([^_\n]+?)(?<=[^\s_])_(?!\w)"#)
    static let strike = regex(#"(~~)(?=\S)(.+?)(?<=\S)~~"#)
    static let mark = regex(#"(==)(?=\S)(.+?)(?<=\S)=="#)
    static let comment = regex(#"<!--.*?-->"#)

    /// The state at the very start of a note.
    public static let initialState = MarkdownBlockState.normal

    /// Styles the lines touched by `range`. `startState` is the state after the line before them.
    public static func highlight(_ live: NSString, range requested: NSRange, startState: MarkdownBlockState = .normal) -> MarkdownHighlight {
        highlight(live, range: requested, startState: startState, inline: true)
    }

    /// The lines of a note and the block each sits in, without styling what is inside them. For the
    /// formatting commands, which need to know where code blocks are and nothing more.
    static func structure(_ text: NSString, through location: Int) -> MarkdownHighlight {
        highlight(text, range: NSRange(location: 0, length: min(max(location, 0), text.length)), startState: .normal, inline: false)
    }

    private static func highlight(_ live: NSString, range requested: NSRange, startState: MarkdownBlockState, inline: Bool) -> MarkdownHighlight {
        // A text view's string changes underneath us and is slow to bridge, so work on a fixed copy.
        let text = live.copy() as? NSString ?? live
        let source = text as String
        let length = text.length
        let clamped = NSRange(location: min(requested.location, length), length: min(requested.length, length - min(requested.location, length)))
        let range = text.lineRange(for: clamped)
        var spans: [MarkdownSpan] = []
        var lines: [MarkdownLine] = []
        var state = startState
        var location = range.location
        let end = NSMaxRange(range)
        while location < end {
            var lineStart = 0, lineEnd = 0, contentsEnd = 0
            text.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let content = NSRange(location: lineStart, length: contentsEnd - lineStart)
            let before = state
            var prefixLength = 0
            state = styleLine(text, source, content: content, state: before, inline: inline, spans: &spans, prefixLength: &prefixLength)
            lines.append(MarkdownLine(range: NSRange(location: lineStart, length: lineEnd - lineStart), before: before, after: state, prefixLength: prefixLength))
            if lineEnd <= location { break }
            location = lineEnd
        }
        return MarkdownHighlight(range: range, spans: spans, lines: lines, endState: state)
    }

    /// Styles a whole note.
    public static func highlight(_ string: String) -> MarkdownHighlight {
        let text = string as NSString
        return highlight(text, range: NSRange(location: 0, length: text.length))
    }

    // MARK: Lines

    private static func styleLine(
        _ text: NSString, _ source: String, content: NSRange, state: MarkdownBlockState, inline: Bool, spans: inout [MarkdownSpan], prefixLength: inout Int
    ) -> MarkdownBlockState {
        let line = text.substring(with: content)
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        switch state {
        case .frontmatter:
            spans.append(.init(range: content, kind: .frontmatter))
            if trimmed == "---" || trimmed == "..." { return .normal }
            if let key = frontmatterKey.firstMatch(in: line, range: NSRange(location: 0, length: content.length)) {
                spans.append(.init(range: shift(key.range, by: content.location), kind: .frontmatterKey))
            }
            return .frontmatter
        case let .fence(marker):
            spans.append(.init(range: content, kind: .codeBlock))
            if closes(trimmed, fence: marker), leadingSpaces(line) <= 3 {
                spans.append(.init(range: content, kind: .codeFence))
                return .normal
            }
            return state
        case .math:
            spans.append(.init(range: content, kind: .codeBlock))
            if trimmed.hasSuffix("$$") {
                if trimmed == "$$" { spans.append(.init(range: content, kind: .codeFence)) }
                return .normal
            }
            return .math
        case .normal:
            break
        }

        guard !trimmed.isEmpty else { return .normal }
        let local = NSRange(location: 0, length: content.length)
        // Most lines are plain prose. A look at the first character saves running patterns that can't match.
        let lead = trimmed.utf16.first ?? 0

        if content.location == 0, trimmed == "---", hasFrontmatterEnd(text, after: NSMaxRange(content)) {
            spans.append(.init(range: content, kind: .frontmatter))
            return .frontmatter
        }
        if lead == 0x60 || lead == 0x7E, let open = fenceOpen.firstMatch(in: line, range: local) {
            let marker = (line as NSString).substring(with: open.range(at: 1))
            // A backtick fence can't have backticks in its info text; that is inline code.
            if !(marker.hasPrefix("`") && (line as NSString).substring(with: open.range(at: 2)).contains("`")) {
                spans.append(.init(range: content, kind: .codeBlock))
                spans.append(.init(range: content, kind: .codeFence))
                return .fence(marker)
            }
        }
        if lead == 0x24, trimmed.hasPrefix("$$") {
            if trimmed == "$$" {
                spans.append(.init(range: content, kind: .codeBlock))
                spans.append(.init(range: content, kind: .codeFence))
                return .math
            }
            if trimmed.count >= 4, trimmed.hasSuffix("$$") {
                spans.append(.init(range: content, kind: .codeBlock))
                return .normal
            }
        }
        if lead == 0x3A, trimmed.hasPrefix(":::") {
            spans.append(.init(range: content, kind: .conflict))
            return .normal
        }
        if lead == 0x23, let match = heading.firstMatch(in: line, range: local) {
            let hashes = match.range(at: 1)
            spans.append(.init(range: content, kind: .heading(level: hashes.length)))
            if inline { styleInline(text, source, range: NSRange(location: content.location + hashes.length, length: content.length - hashes.length), spans: &spans) }
            spans.append(.init(range: shift(hashes, by: content.location), kind: .marker))
            return .normal
        }
        if lead == 0x2D || lead == 0x2A || lead == 0x5F, rule.firstMatch(in: line, range: local) != nil {
            spans.append(.init(range: content, kind: .rule))
            return .normal
        }

        var bodyStart = 0
        if lead == 0x3E, let quote = quotePrefix.firstMatch(in: line, range: local) {
            spans.append(.init(range: content, kind: .blockquote))
            bodyStart = quote.range.length
            if let tag = callout.firstMatch(in: line, options: .anchored, range: NSRange(location: bodyStart, length: content.length - bodyStart)) {
                spans.append(.init(range: shift(tag.range, by: content.location), kind: .calloutTag))
            }
            spans.append(.init(range: NSRange(location: content.location, length: bodyStart), kind: .marker))
        }
        let rest = NSRange(location: bodyStart, length: content.length - bodyStart)
        var doneRange: NSRange?
        // After a quote the item starts further in, so only skip the pattern on lines with no quote.
        let mayBeItem = bodyStart > 0 || lead == 0x2D || lead == 0x2A || lead == 0x2B || (lead >= 0x30 && lead <= 0x39)
        if mayBeItem, let item = listPrefix.firstMatch(in: line, options: .anchored, range: rest) {
            spans.append(.init(range: shift(item.range(at: 2), by: content.location), kind: .listMarker))
            let box = item.range(at: 4)
            if box.location != NSNotFound {
                let checked = (line as NSString).substring(with: box) != "[ ]"
                spans.append(.init(range: shift(box, by: content.location), kind: .taskBox(checked: checked)))
                if checked { doneRange = NSRange(location: content.location + NSMaxRange(item.range), length: content.length - NSMaxRange(item.range)) }
            }
            bodyStart = NSMaxRange(item.range)
        } else if trimmed.hasPrefix("|") {
            spans.append(.init(range: content, kind: .table))
        }
        prefixLength = bodyStart
        if let doneRange, doneRange.length > 0 { spans.append(.init(range: doneRange, kind: .taskDone)) }
        if inline { styleInline(text, source, range: NSRange(location: content.location + bodyStart, length: content.length - bodyStart), spans: &spans) }
        return .normal
    }

    private static func leadingSpaces(_ line: String) -> Int {
        line.prefix { $0 == " " }.count
    }

    private static func closes(_ trimmed: String, fence marker: String) -> Bool {
        guard let character = marker.first, trimmed.count >= marker.count else { return false }
        return trimmed.allSatisfy { $0 == character }
    }

    /// Frontmatter only counts when it is closed, the same rule the reader uses.
    private static func hasFrontmatterEnd(_ text: NSString, after location: Int) -> Bool {
        var search = NSRange(location: location, length: text.length - location)
        while search.length > 0 {
            let found = text.range(of: "\n---", range: search)
            guard found.location != NSNotFound else { return false }
            var lineEnd = 0, contentsEnd = 0
            text.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: found.location + 1, length: 0))
            let tail = text.substring(with: NSRange(location: NSMaxRange(found), length: contentsEnd - NSMaxRange(found)))
            if tail.allSatisfy({ $0 == " " || $0 == "\t" }) { return true }
            search = NSRange(location: lineEnd, length: text.length - lineEnd)
            if lineEnd <= found.location { return false }
        }
        return false
    }

    private static func shift(_ range: NSRange, by offset: Int) -> NSRange {
        NSRange(location: range.location + offset, length: range.length)
    }

    // MARK: Inline

    private static func styleInline(_ text: NSString, _ source: String, range: NSRange, spans: inout [MarkdownSpan]) {
        guard range.length > 1 else { return }
        // One pass to see which characters are present saves running patterns that can't match.
        var hasTick = false, hasBracket = false, hasStar = false, hasUnderscore = false, hasTilde = false
        var hasEquals = false, hasColon = false, hasAngle = false, hasCaret = false
        for index in range.location..<NSMaxRange(range) {
            switch text.character(at: index) {
            case 0x60: hasTick = true
            case 0x5B: hasBracket = true
            case 0x2A: hasStar = true
            case 0x5F: hasUnderscore = true
            case 0x7E: hasTilde = true
            case 0x3D: hasEquals = true
            case 0x3A: hasColon = true
            case 0x3C: hasAngle = true
            case 0x5E: hasCaret = true
            default: break
            }
        }
        var masked: [NSRange] = []
        var markers: [NSRange] = []
        func isMasked(_ candidate: NSRange) -> Bool {
            masked.contains { NSIntersectionRange($0, candidate).length > 0 }
        }

        if hasTick {
            for match in code.matches(in: source, range: range) {
                spans.append(.init(range: match.range, kind: .inlineCode))
                let ticks = match.range(at: 1).length
                markers.append(NSRange(location: match.range.location, length: ticks))
                markers.append(NSRange(location: NSMaxRange(match.range) - ticks, length: ticks))
                masked.append(match.range)
            }
        }
        var tags: [HTMLTag] = []
        var formatting: [NSRange] = []
        var styled: [MarkdownSpan] = []
        if hasAngle {
            for match in comment.matches(in: source, range: range) where !isMasked(match.range) {
                spans.append(.init(range: match.range, kind: .comment))
                masked.append(match.range)
            }
            for match in InlineHTML.tag.matches(in: source, range: range) where !isMasked(match.range) {
                tags.append(InlineHTML.parse(match, in: text))
                masked.append(match.range)
            }
            // What sits between a tag and its partner on the same line takes the tag's look.
            for (open, close) in InlineHTML.pair(tags).pairs {
                let inner = NSRange(location: NSMaxRange(open.range), length: close.range.location - NSMaxRange(open.range))
                guard inner.length > 0 else { continue }
                let look = open.look
                // Only tags whose effect shows on the words may be hidden. Everything else (`<br>`, `<kbd>`,
                // `<details>`, a tag with no partner, an empty pair) stays in sight: hiding it would hide content.
                if look != TagLook() { formatting += [open.range, close.range] }
                if let color = look.color { styled.append(.init(range: inner, kind: .textColor(color))) }
                if let background = look.background {
                    styled.append(.init(range: inner, kind: .highlightColor(background)))
                } else if look.mark {
                    styled.append(.init(range: inner, kind: .highlight))
                }
                if let scale = look.scale { styled.append(.init(range: inner, kind: .textSize(scale))) }
                if look.underline { styled.append(.init(range: inner, kind: .underline)) }
                if look.bold { styled.append(.init(range: inner, kind: .strong)) }
                if look.italic { styled.append(.init(range: inner, kind: .emphasis)) }
                if look.strikethrough { styled.append(.init(range: inner, kind: .strikethrough)) }
                if look.sub { styled.append(.init(range: inner, kind: .subscript)) }
                if look.sup { styled.append(.init(range: inner, kind: .superscript)) }
            }
            styled.sort { $0.range.location < $1.range.location }
        }
        if hasBracket {
            for match in wiki.matches(in: source, range: range) where !isMasked(match.range) {
                spans.append(.init(range: match.range, kind: .wikiLink))
                markers.append(NSRange(location: match.range.location, length: 2))
                markers.append(NSRange(location: NSMaxRange(match.range) - 2, length: 2))
                masked.append(match.range)
            }
            for match in link.matches(in: source, range: range) where !isMasked(match.range) {
                spans.append(.init(range: match.range(at: 2), kind: .linkText))
                markers.append(match.range(at: 1))
                let target = NSRange(location: match.range(at: 3).location, length: NSMaxRange(match.range) - match.range(at: 3).location)
                spans.append(.init(range: target, kind: .linkURL))
                masked.append(target)
            }
            for match in footnote.matches(in: source, range: range) where !isMasked(match.range) {
                spans.append(.init(range: match.range, kind: .footnote))
                masked.append(match.range)
            }
        }
        if hasColon {
            for match in url.matches(in: source, range: range) where !isMasked(match.range) {
                spans.append(.init(range: match.range, kind: .linkText))
                masked.append(match.range)
            }
        }

        func delimited(_ expression: NSRegularExpression, _ kinds: [MarkdownSpanKind]) {
            for match in expression.matches(in: source, range: range) {
                let width = match.range(at: 1).length
                let open = NSRange(location: match.range.location, length: width)
                let close = NSRange(location: NSMaxRange(match.range) - width, length: width)
                guard !isMasked(open), !isMasked(close) else { continue }
                for kind in kinds { spans.append(.init(range: match.range(at: 2), kind: kind)) }
                markers.append(open)
                markers.append(close)
            }
        }
        if hasStar || hasUnderscore {
            delimited(strongEmphasis, [.strong, .emphasis])
            delimited(strong, [.strong])
            if hasStar { delimited(starEmphasis, [.emphasis]) }
            if hasUnderscore { delimited(underscoreEmphasis, [.emphasis]) }
        }
        if hasTilde {
            delimited(strike, [.strikethrough])
            delimited(InlineScanner.sub, [.subscript])
        }
        if hasEquals { delimited(mark, [.highlight]) }
        if hasCaret { delimited(InlineScanner.sup, [.superscript]) }
        // Colors go on after links and emphasis so they win, and the marks and tags themselves stay dim.
        spans += styled
        for marker in markers { spans.append(.init(range: marker, kind: .marker)) }
        for tag in tags { spans.append(.init(range: tag.range, kind: formatting.contains(tag.range) ? .formatTag : .htmlTag)) }
    }
}
