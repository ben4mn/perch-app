import Foundation

/// The inline formats Perch can put on text. Each is stored as ordinary Markdown or a small piece of
/// inline HTML that other Markdown apps and GitHub also read:
///
/// | Format          | In the file                                             |
/// | --------------- | ------------------------------------------------------- |
/// | bold            | `**text**`                                              |
/// | italic          | `*text*`                                                |
/// | strikethrough   | `~~text~~`                                              |
/// | underline       | `<u>text</u>`                                           |
/// | highlight       | `==text==`, or `<mark style="background-color: #RRGGBB">text</mark>` |
/// | text color      | `<span style="color: #RRGGBB">text</span>`              |
/// | text size       | `<span style="font-size: 1.15em">text</span>`           |
/// | subscript       | `~text~`                                                |
/// | superscript     | `^text^`                                                |
public enum InlineFormat: String, CaseIterable, Sendable {
    case bold, italic, strikethrough, underline, highlight, textColor, textSize, `subscript`, superscript

    /// The marks that open and close this format. `value` is the color or size; empty for formats without one,
    /// and for the plain yellow highlight.
    public func markers(value: String = "") -> (open: String, close: String) {
        switch self {
        case .bold: return ("**", "**")
        case .italic: return ("*", "*")
        case .strikethrough: return ("~~", "~~")
        case .underline: return ("<u>", "</u>")
        case .highlight:
            return value.isEmpty ? ("==", "==") : ("<mark style=\"background-color: \(value)\">", "</mark>")
        case .textColor: return ("<span style=\"color: \(value)\">", "</span>")
        case .textSize: return ("<span style=\"font-size: \(value)\">", "</span>")
        case .subscript: return ("~", "~")
        case .superscript: return ("^", "^")
        }
    }
}

/// The colors and sizes the format bar offers, and the rule that keeps a chosen color readable on any theme.
public enum FormatPalette {
    public struct Swatch: Equatable, Identifiable, Sendable {
        public var name: String
        public var hex: String
        public var id: String { hex }
    }

    public static let colors: [Swatch] = [
        .init(name: "Red", hex: "#D94F3D"), .init(name: "Orange", hex: "#E8843C"), .init(name: "Amber", hex: "#C99A1B"),
        .init(name: "Green", hex: "#3F9B5B"), .init(name: "Teal", hex: "#1F9E96"), .init(name: "Blue", hex: "#3B82D9"),
        .init(name: "Indigo", hex: "#6B5BD2"), .init(name: "Purple", hex: "#A855C7"), .init(name: "Pink", hex: "#D4588F"),
        .init(name: "Gray", hex: "#7A7F87"),
    ]

    /// Text sizes from smallest to largest. Normal text has no size written at all.
    public static let sizes = ["0.85em", "1.15em", "1.3em", "1.6em"]

    /// The name of a palette color, or the hex itself for a custom one.
    public static func name(for hex: String) -> String {
        colors.first { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }?.name ?? hex
    }

    /// `#RRGGBB` in capitals from `#rgb` or `#rrggbb`, with or without the `#`. Nil for anything else.
    public static func normalizedHex(_ value: String) -> String? {
        var text = value.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 3 || text.count == 6, text.utf8.count == text.count, text.allSatisfy(\.isHexDigit) else { return nil }
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        return "#" + text.uppercased()
    }

    /// How much of a size a size value is: 1.15 for "1.15em". Nil when it isn't one of the steps.
    public static func scale(for size: String) -> Double? {
        sizes.contains(size) ? Double(size.dropLast(2)) : nil
    }

    /// A text color made readable on a background. The file keeps the color that was picked; this is only
    /// for showing it.
    ///
    /// The rule, kept simple so the reader's JavaScript can do the same:
    /// 1. If the color already has `minimum` WCAG contrast against the background, use it as it is.
    /// 2. Otherwise turn it into HSL and move its lightness in steps of 0.01, keeping hue and saturation:
    ///    up when the background is dark (relative luminance under 0.18), down when it is light.
    /// 3. Stop at the first lightness with enough contrast, or at white or black.
    public static func legible(_ color: ThemeRGB, on background: ThemeRGB, minimum: Double = ThemeContrast.text) -> ThemeRGB {
        guard ThemeContrast.ratio(color, background) < minimum else { return color }
        let (hue, saturation, start) = hsl(color)
        var lightness = start
        let step = background.luminance < 0.18 ? 0.01 : -0.01
        var result = color
        for _ in 0..<100 {
            lightness = min(max(lightness + step, 0), 1)
            result = rgb(hue: hue, saturation: saturation, lightness: lightness)
            if ThemeContrast.ratio(result, background) >= minimum || lightness <= 0 || lightness >= 1 { break }
        }
        return result
    }

    /// How strongly a highlight color is washed over the page: stronger on dark themes, where a thin wash disappears.
    public static func washStrength(dark: Bool) -> Double { dark ? 0.42 : 0.3 }

    /// The color a highlight makes on the page: the highlight color washed over the background.
    public static func wash(_ color: ThemeRGB, on background: ThemeRGB, dark: Bool) -> ThemeRGB {
        let strength = washStrength(dark: dark)
        return ThemeRGB(
            red: background.red + (color.red - background.red) * strength,
            green: background.green + (color.green - background.green) * strength,
            blue: background.blue + (color.blue - background.blue) * strength
        )
    }

    /// How strongly the plain `==highlight==` is washed over the page, in the theme's warning color.
    public static let plainWashStrength = 0.3

    public static func plainWash(_ warning: ThemeRGB, on background: ThemeRGB) -> ThemeRGB {
        ThemeRGB(
            red: background.red + (warning.red - background.red) * plainWashStrength,
            green: background.green + (warning.green - background.green) * plainWashStrength,
            blue: background.blue + (warning.blue - background.blue) * plainWashStrength
        )
    }

    /// Hue in turns (0 to 1), saturation and lightness, each 0 to 1.
    static func hsl(_ color: ThemeRGB) -> (hue: Double, saturation: Double, lightness: Double) {
        let high = max(color.red, color.green, color.blue), low = min(color.red, color.green, color.blue)
        let lightness = (high + low) / 2
        guard high > low else { return (0, 0, lightness) }
        let spread = high - low
        let saturation = lightness > 0.5 ? spread / (2 - high - low) : spread / (high + low)
        var hue: Double
        if high == color.red {
            hue = (color.green - color.blue) / spread + (color.green < color.blue ? 6 : 0)
        } else if high == color.green {
            hue = (color.blue - color.red) / spread + 2
        } else {
            hue = (color.red - color.green) / spread + 4
        }
        hue /= 6
        return (hue, saturation, lightness)
    }

    static func rgb(hue: Double, saturation: Double, lightness: Double) -> ThemeRGB {
        guard saturation > 0 else { return ThemeRGB(red: lightness, green: lightness, blue: lightness) }
        let q = lightness < 0.5 ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q
        func channel(_ shifted: Double) -> Double {
            var t = shifted
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        return ThemeRGB(red: channel(hue + 1 / 3), green: channel(hue), blue: channel(hue - 1 / 3))
    }
}

// MARK: Inline HTML

/// One HTML tag found in a line of Markdown.
struct HTMLTag: Equatable {
    var range: NSRange
    /// In small letters, whatever the file has.
    var name: String
    var isClose: Bool
    /// `<br>`, `<img …>` and anything written `<… />`: a tag with no partner.
    var isVoid: Bool
    var attributes: [Attribute]

    struct Attribute: Equatable {
        var name: String
        var value: String
    }

    /// The `style` attribute as property and value pairs, properties in small letters.
    var style: [(property: String, value: String)] {
        guard let style = attributes.first(where: { $0.name == "style" })?.value else { return [] }
        return style.split(separator: ";").compactMap { part in
            guard let colon = part.firstIndex(of: ":") else { return nil }
            let property = part[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = part[part.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            return property.isEmpty || value.isEmpty ? nil : (property, value)
        }
    }

    /// The format this opening tag stands for, when it is exactly one Perch writes: one tag, one job, nothing
    /// extra. Anything richer (two style properties, a class, an id) is left alone as somebody else's markup.
    var format: (format: InlineFormat, value: String)? {
        guard !isClose, !isVoid else { return nil }
        switch name {
        case "u":
            return attributes.isEmpty ? (.underline, "") : nil
        case "mark":
            if attributes.isEmpty { return (.highlight, "") }
            guard attributes.count == 1, style.count == 1, ["background-color", "background"].contains(style[0].property),
                  let hex = FormatPalette.normalizedHex(style[0].value) else { return nil }
            return (.highlight, hex)
        case "span":
            guard attributes.count == 1, style.count == 1 else { return nil }
            if style[0].property == "color", let hex = FormatPalette.normalizedHex(style[0].value) { return (.textColor, hex) }
            if style[0].property == "font-size" {
                let size = style[0].value.lowercased().replacingOccurrences(of: " ", with: "")
                let tidy = size.hasPrefix(".") ? "0" + size : size
                if FormatPalette.sizes.contains(tidy) { return (.textSize, tidy) }
            }
            return nil
        default:
            return nil
        }
    }

    /// How the text inside this tag should look in the editor. More forgiving than `format`: a span with
    /// several style properties still shows its color.
    var look: TagLook {
        var look = TagLook()
        switch name {
        case "u", "ins": look.underline = true
        case "b", "strong": look.bold = true
        case "i", "em": look.italic = true
        case "s", "del", "strike": look.strikethrough = true
        case "sub": look.sub = true
        case "sup": look.sup = true
        case "mark": look.mark = true
        default: break
        }
        for (property, value) in style {
            switch property {
            case "color": look.color = FormatPalette.normalizedHex(value) ?? look.color
            case "background-color", "background": look.background = FormatPalette.normalizedHex(value) ?? look.background
            case "font-size":
                let size = value.lowercased().replacingOccurrences(of: " ", with: "")
                if size.hasSuffix("em"), !size.hasSuffix("rem"), let scale = Double(size.dropLast(2)) { look.scale = min(max(scale, 0.5), 2.5) }
                if size.hasSuffix("%"), let percent = Double(size.dropLast()) { look.scale = min(max(percent / 100, 0.5), 2.5) }
            case "text-decoration", "text-decoration-line":
                if value.lowercased().contains("underline") { look.underline = true }
                if value.lowercased().contains("line-through") { look.strikethrough = true }
            case "font-weight":
                if value.lowercased() == "bold" || (Int(value) ?? 0) >= 600 { look.bold = true }
            case "font-style":
                if value.lowercased() == "italic" { look.italic = true }
            default: break
            }
        }
        return look
    }
}

struct TagLook: Equatable {
    var color: String?
    var background: String?
    var scale: Double?
    var underline = false, bold = false, italic = false, strikethrough = false, sub = false, sup = false
    /// A bare `<mark>`: the theme's own highlight.
    var mark = false
}

enum InlineHTML {
    static let tag = try! NSRegularExpression(pattern: #"<(/?)([A-Za-z][A-Za-z0-9-]*)((?:\s[^<>]*)?)>"#)
    private static let attribute = try! NSRegularExpression(
        pattern: #"([A-Za-z_:][-A-Za-z0-9_:.]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?"#
    )
    private static let voidNames: Set<String> = ["br", "hr", "img", "input", "wbr", "col", "source", "area", "base", "embed", "link", "meta", "track"]

    static func parse(_ match: NSTextCheckingResult, in text: NSString) -> HTMLTag {
        let name = text.substring(with: match.range(at: 2)).lowercased()
        let rest = text.substring(with: match.range(at: 3))
        var attributes: [HTMLTag.Attribute] = []
        let source = rest as NSString
        for found in attribute.matches(in: rest, range: NSRange(location: 0, length: source.length)) {
            var value = ""
            for group in 2...4 where found.range(at: group).location != NSNotFound { value = source.substring(with: found.range(at: group)) }
            attributes.append(.init(name: source.substring(with: found.range(at: 1)).lowercased(), value: value))
        }
        let selfClosing = rest.trimmingCharacters(in: .whitespaces).hasSuffix("/")
        return HTMLTag(
            range: match.range, name: name, isClose: match.range(at: 1).length > 0,
            isVoid: selfClosing || voidNames.contains(name), attributes: attributes
        )
    }

    /// Matches each opening tag with the closing tag that ends it. Tags left over (never closed, never
    /// opened, or with no partner by nature) come back as strays.
    static func pair(_ tags: [HTMLTag]) -> (pairs: [(open: HTMLTag, close: HTMLTag)], strays: [HTMLTag]) {
        var pairs: [(open: HTMLTag, close: HTMLTag)] = []
        var strays: [HTMLTag] = []
        var open: [HTMLTag] = []
        for tag in tags {
            if tag.isVoid {
                strays.append(tag)
            } else if !tag.isClose {
                open.append(tag)
            } else if let index = open.lastIndex(where: { $0.name == tag.name }) {
                strays.append(contentsOf: open[(index + 1)...])
                pairs.append((open[index], tag))
                open.removeSubrange(index...)
            } else {
                strays.append(tag)
            }
        }
        strays.append(contentsOf: open)
        return (pairs, strays)
    }
}

// MARK: Scanning a line

/// A stretch of text between an opening and a closing mark: `**…**`, `<u>…</u>`, `[…](url)`.
struct InlinePair: Equatable {
    /// Nil for marks that aren't a format Perch sets: links, and HTML it didn't write.
    var format: InlineFormat?
    var value: String
    var open: NSRange
    var close: NSRange

    var inner: NSRange { NSRange(location: NSMaxRange(open), length: close.location - NSMaxRange(open)) }
    var outer: NSRange { NSRange(location: open.location, length: NSMaxRange(close) - open.location) }
}

/// What the inline marks in one line's text are. Pairs never cross each other; everything else that must
/// stay in one piece (code, wiki links, images, addresses, `<br>`) is an atom.
struct InlineScan {
    var range: NSRange
    var pairs: [InlinePair]
    var atoms: [NSRange]
    /// Tags and marks with no partner on this line: a `<span>` closed on a later line, a stray `</u>`.
    /// A span Perch writes never wraps one, since that would cross whatever it belongs to.
    var strays: [NSRange] = []
}

enum InlineScanner {
    private static func regex(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern) }

    private static let image = regex(#"!\[[^\]\n]*\]\([^)\n]*\)"#)
    private static let destination = regex(#"(?<=\])\([^)\s]*\)"#)
    static let sub = regex(#"(?<![~\\])(~)([^~\s]+)~(?!~)"#)
    static let sup = regex(#"(?<![\^\\\[])(\^)([^\^\s]+)\^"#)
    private static let punctuation = CharacterSet.punctuationCharacters.union(.symbols)

    /// White space as the reader's Markdown library counts it. The start or end of the text counts too.
    static func isSpace(_ character: unichar?) -> Bool {
        guard let character else { return true }
        switch character {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x202F, 0x205F, 0x3000: return true
        default: return false
        }
    }

    static func isPunctuation(_ character: unichar?) -> Bool {
        guard let character, let scalar = UnicodeScalar(character) else { return false }
        return punctuation.contains(scalar)
    }

    /// Markdown's rule for where emphasis may start: marks can open when what follows them isn't a space,
    /// and isn't punctuation unless what comes before is a space or punctuation.
    static func canOpen(before: unichar?, after: unichar?) -> Bool {
        !isSpace(after) && (!isPunctuation(after) || isSpace(before) || isPunctuation(before))
    }

    /// The same rule turned around, for where emphasis may end.
    static func canClose(before: unichar?, after: unichar?) -> Bool {
        !isSpace(before) && (!isPunctuation(before) || isSpace(after) || isPunctuation(after))
    }

    /// Finds the marks in `range`, which should be the text of one line or one table cell.
    static func scan(_ text: NSString, source: String, range: NSRange) -> InlineScan {
        var pairs: [InlinePair] = []
        var atoms: [NSRange] = []
        guard range.length > 0 else { return InlineScan(range: range, pairs: [], atoms: []) }
        var masked = [Bool](repeating: false, count: range.length)
        func mask(_ part: NSRange) {
            for index in max(part.location, range.location)..<min(NSMaxRange(part), NSMaxRange(range)) { masked[index - range.location] = true }
        }
        func isMasked(_ part: NSRange) -> Bool {
            for index in part.location..<NSMaxRange(part) where masked[index - range.location] { return true }
            return false
        }
        func atom(_ part: NSRange) {
            atoms.append(part)
            mask(part)
        }

        var has: Set<unichar> = []
        for index in range.location..<NSMaxRange(range) { has.insert(text.character(at: index)) }

        if has.contains(0x60) {
            for match in MarkdownHighlighter.code.matches(in: source, range: range) { atom(match.range) }
        }
        var tags: [HTMLTag] = []
        var looseDestinations: [NSRange] = []
        if has.contains(0x3C) {
            for match in MarkdownHighlighter.comment.matches(in: source, range: range) where !isMasked(match.range) { atom(match.range) }
            for match in InlineHTML.tag.matches(in: source, range: range) where !isMasked(match.range) {
                tags.append(InlineHTML.parse(match, in: text))
                mask(match.range)
            }
        }
        if has.contains(0x5B) {
            for match in MarkdownHighlighter.wiki.matches(in: source, range: range) where !isMasked(match.range) { atom(match.range) }
            for match in image.matches(in: source, range: range) where !isMasked(match.range) { atom(match.range) }
            for match in MarkdownHighlighter.link.matches(in: source, range: range) {
                let open = match.range(at: 1)
                let close = NSRange(location: match.range(at: 3).location, length: NSMaxRange(match.range) - match.range(at: 3).location)
                guard !isMasked(open), !isMasked(close) else { continue }
                pairs.append(InlinePair(format: nil, value: "", open: open, close: close))
                mask(open)
                mask(close)
            }
            // Where a link goes is never formatted, even when the link itself is one this scanner can't
            // read (`[a [b] c](address)`). Nothing may wrap it either: a tag between `]` and `(` breaks the link.
            for match in destination.matches(in: source, range: range) where !isMasked(match.range) {
                looseDestinations.append(match.range)
                mask(match.range)
            }
            for match in MarkdownHighlighter.footnote.matches(in: source, range: range) where !isMasked(match.range) { atom(match.range) }
        }
        if has.contains(0x3A) {
            for match in MarkdownHighlighter.url.matches(in: source, range: range) where !isMasked(match.range) { atom(match.range) }
        }

        if has.contains(0x2A) || has.contains(0x5F) { pairs += emphasis(text, range: range, masked: masked) }

        func character(_ index: Int) -> unichar? {
            index >= range.location && index < NSMaxRange(range) ? text.character(at: index) : nil
        }
        /// `flanking` is for `~~` and `==`, which the reader holds to the same rule as `**`: marks open
        /// before a word and close after one. `foo==(bar)==baz` is not a highlight.
        func delimited(_ expression: NSRegularExpression, _ format: InlineFormat, flanking: Bool = false) {
            for match in expression.matches(in: source, range: range) {
                let width = match.range(at: 1).length
                let open = NSRange(location: match.range(at: 1).location, length: width)
                let close = NSRange(location: NSMaxRange(match.range) - width, length: width)
                guard !isMasked(open), !isMasked(close) else { continue }
                if flanking {
                    guard canOpen(before: character(open.location - 1), after: character(NSMaxRange(open))),
                          canClose(before: character(close.location - 1), after: character(NSMaxRange(close))) else { continue }
                }
                pairs.append(InlinePair(format: format, value: "", open: open, close: close))
                mask(open)
                mask(close)
            }
        }
        if has.contains(0x7E) {
            delimited(MarkdownHighlighter.strike, .strikethrough, flanking: true)
            delimited(sub, .subscript)
        }
        if has.contains(0x3D) { delimited(MarkdownHighlighter.mark, .highlight, flanking: true) }
        if has.contains(0x5E) { delimited(sup, .superscript) }

        let paired = InlineHTML.pair(tags)
        for (open, close) in paired.pairs {
            let format = open.format
            pairs.append(InlinePair(format: format?.format, value: format?.value ?? "", open: open.range, close: close.range))
        }
        var strays = looseDestinations
        for tag in paired.strays {
            if tag.isVoid { atoms.append(tag.range) } else { strays.append(tag.range) }
        }

        // Pairs found by different rules can cross (`**a <u>b** c</u>`). The one that opened later gives way
        // and its two marks become plain atoms, so what is left nests cleanly.
        pairs.sort { $0.open.location < $1.open.location }
        var nested: [InlinePair] = []
        var ends: [Int] = []
        for pair in pairs {
            while let last = ends.last, last <= pair.open.location { ends.removeLast() }
            if let parent = ends.last, NSMaxRange(pair.close) > parent {
                strays.append(pair.open)
                strays.append(pair.close)
                continue
            }
            nested.append(pair)
            ends.append(pair.close.location)
        }
        return InlineScan(
            range: range, pairs: nested, atoms: atoms.sorted { $0.location < $1.location },
            strays: strays.sorted { $0.location < $1.location }
        )
    }

    /// `*` and `_` emphasis, matched the way CommonMark matches it.
    private static func emphasis(_ text: NSString, range: NSRange, masked: [Bool]) -> [InlinePair] {
        struct Run {
            var location: Int
            var count: Int
            let original: Int
            let character: unichar
            let canOpen: Bool
            let canClose: Bool
        }
        var runs: [Run] = []
        let end = NSMaxRange(range)
        var index = range.location
        while index < end {
            let character = text.character(at: index)
            let hidden = masked[index - range.location]
            if character == 0x5C, !hidden {
                index += 2
                continue
            }
            guard character == 0x2A || character == 0x5F, !hidden else {
                index += 1
                continue
            }
            var stop = index
            while stop < end, text.character(at: stop) == character, !masked[stop - range.location] { stop += 1 }
            let before: unichar? = index > range.location ? text.character(at: index - 1) : nil
            let after: unichar? = stop < end ? text.character(at: stop) : nil
            let left = canOpen(before: before, after: after)
            let right = canClose(before: before, after: after)
            let star = character == 0x2A
            runs.append(Run(
                location: index, count: stop - index, original: stop - index, character: character,
                canOpen: star ? left : left && (!right || isPunctuation(before)),
                canClose: star ? right : right && (!left || isPunctuation(after))
            ))
            index = stop
        }
        var pairs: [InlinePair] = []
        var closer = 0
        while closer < runs.count {
            guard runs[closer].canClose, runs[closer].count > 0 else {
                closer += 1
                continue
            }
            var found = -1
            var opener = closer - 1
            while opener >= 0 {
                let candidate = runs[opener]
                if candidate.character == runs[closer].character, candidate.canOpen, candidate.count > 0 {
                    let sum = candidate.original + runs[closer].original
                    let blocked = (candidate.canClose || runs[closer].canOpen) && sum % 3 == 0
                        && !(candidate.original % 3 == 0 && runs[closer].original % 3 == 0)
                    if !blocked {
                        found = opener
                        break
                    }
                }
                opener -= 1
            }
            guard found >= 0 else {
                closer += 1
                continue
            }
            let width = runs[found].count >= 2 && runs[closer].count >= 2 ? 2 : 1
            let open = NSRange(location: runs[found].location + runs[found].count - width, length: width)
            let close = NSRange(location: runs[closer].location, length: width)
            runs[found].count -= width
            runs[closer].location += width
            runs[closer].count -= width
            if found + 1 < closer { for between in (found + 1)..<closer { runs[between].count = 0 } }
            pairs.append(InlinePair(format: width == 2 ? .bold : .italic, value: "", open: open, close: close))
            if runs[closer].count == 0 { closer += 1 }
        }
        return pairs
    }
}
