import PerchKit
import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
typealias TextStorageEditActions = NSTextStorageEditActions
#else
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
typealias TextStorageEditActions = NSTextStorage.EditActions
#endif

/// A native Markdown editor. Styling is display-only; the file stays plain text.
struct MarkdownEditor: View {
    @Binding var text: String
    var actions: EditorActions
    /// Generous margins and a centred column, for a note that fills its pane.
    var roomy: Bool
    /// False while the editor is kept behind the reader: it then takes no typing and gives up the keyboard.
    var isActive: Bool
    /// The Mac's format bar above the text. On the iPhone the bar rides above the keyboard instead.
    var formatBar: Bool
    var onCompletionQuery: (EditorCompletion?) -> Void
    private var reading = ReadingSettings()
    private var editing = EditingSettings()
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        text: Binding<String>, actions: EditorActions, roomy: Bool = false, isActive: Bool = true, formatBar: Bool = false,
        onCompletionQuery: @escaping (EditorCompletion?) -> Void = { _ in }
    ) {
        _text = text
        self.actions = actions
        self.roomy = roomy
        self.isActive = isActive
        self.formatBar = formatBar
        self.onCompletionQuery = onCompletionQuery
    }

    var body: some View {
        #if os(macOS)
        let showsBar = formatBar && editing.formattingBar
        VStack(spacing: 0) {
            if showsBar {
                FormatBar(state: actions.format, perform: { actions.perform($0) })
                    .transition(.perchBanner(from: .top, reduceMotion: reduceMotion))
            }
            editor
        }
        .motion(Motion.smooth, value: showsBar)
        .onAppear { measureTop(showsBar: showsBar) }
        .onChange(of: showsBar) { measureTop(showsBar: showsBar) }
        .onChange(of: theme.display) { measureTop(showsBar: showsBar) }
        // ⇧⌘C, and Color… in the right-click menu, still have somewhere to show the colors when there is no
        // bar: with the bar turned off, and in the small editors that never have one (a task's notes).
        .background(alignment: .topLeading) {
            if !showsBar { PaletteAnchor(state: actions.format, perform: { actions.perform($0) }) }
        }
        #else
        editor
            .onAppear { actions.textTop = NotePanes.editorTextTop(barHeight: 0, insetTop: PlatformEditor.textInsetTop(roomy: roomy)) }
        #endif
    }

    #if os(macOS)
    private func measureTop(showsBar: Bool) {
        actions.topInset = showsBar ? Metrics.scaled(34) : 0
        let top = NotePanes.editorTextTop(barHeight: actions.topInset, insetTop: PlatformEditor.textInsetTop(roomy: roomy))
        if actions.textTop != top { actions.textTop = top }
    }
    #endif

    private var editor: some View {
        PlatformEditor(
            text: $text, actions: actions, appearance: editing.appearance(readerFont: reading.font), behavior: editing.behavior,
            palette: theme.palette, roomy: roomy, isActive: isActive, onCompletionQuery: onCompletionQuery
        )
    }
}

#if os(macOS)
/// Shows the color palette at the top of the editor when the format bar is hidden.
private struct PaletteAnchor: View {
    @ObservedObject var state: FormatState
    var perform: (EditorCommand) -> Void
    @AppStorage(EditingSettings.Key.recentColors) private var recents = ""
    @State private var showing = false

    var body: some View {
        Color.clear.frame(width: 1, height: 1).padding(.leading, 40)
            .accessibilityHidden(true)
            .onAppear { state.watchers += 1 }
            .onDisappear { state.watchers -= 1 }
            .onChange(of: state.paletteRequests) { showing = true }
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                ColorPalette(mode: .text, current: state.active.textColor) { hex in
                    showing = false
                    if let hex { recents = FormatRecents.adding(hex, to: recents) }
                    perform(.textColor(hex))
                }
                .perchPresented()
            }
    }
}
#endif

public enum EditorCompletion: Equatable {
    case wiki(String)
    case slash(String)
}

/// The formatting actions shared by keyboard shortcuts, the format bars and the Format menu.
public enum EditorCommand: Sendable, Equatable {
    case bold, italic, code, strikethrough, link, wikiLink, heading, bullet, numbered, task, indent, outdent, undo, redo
    case underline, `subscript`, superscript
    /// The plain yellow highlight, on or off.
    case highlight
    /// A text color as `#RRGGBB`; nil goes back to the theme's own.
    case textColor(String?)
    /// A highlight color as `#RRGGBB`, empty for plain yellow, nil for none.
    case highlightColor(String?)
    /// One size larger (1) or smaller (-1).
    case sizeStep(Int)
    case clearFormatting
    /// 1 to 3, or 0 for body text. Asking for the level a line already has makes it body text.
    case setHeading(Int)
    case quote
    /// A callout of this type ("note", "tip"); nil turns one back into a plain quote.
    case callout(String?)
    /// Wraps the selected lines in a fence with this language, or unwraps the block the caret is in.
    case codeBlock(String)
    case divider
    case table(rows: Int, columns: Int)
    case tableAddRow, tableAddColumn, tableTidy
    /// "center" or "right"; nil takes the alignment away.
    case align(String?)
    /// Opens the color palette.
    case showColors
}

/// The editor's keyboard shortcuts, the same on the Mac and on an iPhone with a keyboard attached.
enum EditorShortcuts {
    struct Shortcut {
        var key: String
        var shift = false
        var control = false
        var command: EditorCommand
    }

    /// Every shortcut holds Command. ⌃⌘1 to ⌃⌘3 are the headings because ⌥⌘1 to ⌥⌘6 switch task views.
    static let all: [Shortcut] = [
        .init(key: "b", command: .bold), .init(key: "i", command: .italic), .init(key: "u", command: .underline),
        .init(key: "k", command: .link), .init(key: "\\", command: .clearFormatting),
        .init(key: "x", shift: true, command: .strikethrough), .init(key: "k", shift: true, command: .wikiLink),
        .init(key: "h", shift: true, command: .highlight), .init(key: "c", shift: true, command: .showColors),
        .init(key: "7", shift: true, command: .numbered), .init(key: "8", shift: true, command: .bullet),
        .init(key: "9", shift: true, command: .task),
        .init(key: ".", shift: true, command: .sizeStep(1)), .init(key: ",", shift: true, command: .sizeStep(-1)),
        .init(key: "1", control: true, command: .setHeading(1)), .init(key: "2", control: true, command: .setHeading(2)),
        .init(key: "3", control: true, command: .setHeading(3)),
    ]
}

/// Lets toolbars and menus reach into the text view.
@MainActor
public final class EditorActions: ObservableObject {
    var replaceTrigger: (String) -> Void = { _ in }
    /// The source line at the top of the editor, with a fraction for how far through it.
    var topLine: () -> Double = { 0 }
    var scrollToLine: (Double) -> Void = { _ in }
    /// Where the caret is, in the editor's own coordinates.
    var caretRect: () -> CGRect? = { nil }
    public var pasteImage: ((Data, String) -> String?)?

    /// Called as the editor scrolls, with its top line.
    var onScroll: ((Double) -> Void)?
    /// Called for Escape. Return true when it was used.
    var onEscape: (() -> Bool)?
    /// Where a new editor should start: the caret goes to this line and it is scrolled to the top.
    var initialLine: Double?
    var focusOnAppear = false
    /// Applies `initialLine` and `focusOnAppear` to an editor that already exists.
    var applyPending: () -> Void = {}
    /// What is in force at the caret, for format bars.
    public let format = FormatState()
    /// Runs a formatting command in the editor.
    public var perform: (EditorCommand) -> Void = { _ in }
    /// The same, but only while the editor has the keyboard: for the menu bar, whose shortcuts also fire
    /// when the caret is in some other field.
    var performIfFocused: (EditorCommand) -> Void = { _ in }
    /// Height of whatever sits above the text inside the editor (the Mac's format bar).
    var topInset: CGFloat = 0
    /// How far below the editor's top edge its text starts: the format bar, then the text's own inset.
    /// The preview beside it starts its text at the same height, so a line sits level on both sides.
    @Published var textTop: CGFloat = 0
    public init() {}
}

struct SlashCommand: Identifiable {
    var id: String { name }
    var name: String
    var symbol: String
    /// What is typed in place of the `/…`. `@DATE@` becomes today's date; `@CARET@` is where the caret lands.
    var insertion: String

    static let caret = "@CARET@"
}

let slashCommands: [SlashCommand] = [
    .init(name: "Heading", symbol: "number", insertion: "## "),
    .init(name: "Checklist", symbol: "checklist", insertion: "- [ ] "),
    .init(name: "Table", symbol: "tablecells", insertion: "| Column | Column |\n| --- | --- |\n|  |  |\n"),
    .init(name: "Code", symbol: "chevron.left.forwardslash.chevron.right", insertion: "```\n\n```\n"),
    .init(name: "Mermaid diagram", symbol: "point.3.connected.trianglepath.dotted", insertion: "```mermaid\nflowchart LR\n  A --> B\n```\n"),
    .init(name: "Music (ABC)", symbol: "music.note", insertion: "```abc\nX:1\nT:Title\nM:4/4\nK:C\nCDEF GABc|\n```\n"),
    .init(name: "Math", symbol: "function", insertion: "$$\n\n$$\n"),
    .init(name: "Callout", symbol: "exclamationmark.bubble", insertion: "> [!note] Title\n> "),
    .init(name: "Footnote", symbol: "textformat.superscript", insertion: "[^1]\n\n[^1]: "),
    .init(name: "Frontmatter", symbol: "list.bullet.rectangle", insertion: "---\naliases: []\n---\n"),
    .init(name: "Divider", symbol: "minus", insertion: "---\n"),
    .init(name: "Today's date", symbol: "calendar", insertion: "@DATE@"),
    .init(name: "Heading 1", symbol: "1.square", insertion: "# "),
    .init(name: "Heading 3", symbol: "3.square", insertion: "### "),
    .init(name: "Bulleted list", symbol: "list.bullet", insertion: "- "),
    .init(name: "Numbered list", symbol: "list.number", insertion: "1. "),
    .init(name: "Quote", symbol: "text.quote", insertion: "> "),
    .init(name: "Tip callout", symbol: "lightbulb", insertion: "> [!tip] @CARET@\n> "),
    .init(name: "Info callout", symbol: "info.circle", insertion: "> [!info] @CARET@\n> "),
    .init(name: "Success callout", symbol: "checkmark.circle", insertion: "> [!success] @CARET@\n> "),
    .init(name: "Question callout", symbol: "questionmark.circle", insertion: "> [!question] @CARET@\n> "),
    .init(name: "Warning callout", symbol: "exclamationmark.triangle", insertion: "> [!warning] @CARET@\n> "),
    .init(name: "Danger callout", symbol: "flame", insertion: "> [!danger] @CARET@\n> "),
    .init(name: "Example callout", symbol: "list.bullet.rectangle", insertion: "> [!example] @CARET@\n> "),
    .init(name: "Table 3 × 3", symbol: "tablecells", insertion: "| @CARET@Column 1 | Column 2 | Column 3 |\n| --- | --- | --- |\n|  |  |  |\n|  |  |  |\n|  |  |  |\n"),
    .init(name: "Centered text", symbol: "text.aligncenter", insertion: "<div align=\"center\">\n\n@CARET@\n\n</div>\n"),
    .init(name: "Right-aligned text", symbol: "text.alignright", insertion: "<div align=\"right\">\n\n@CARET@\n\n</div>\n"),
    .init(name: "Highlight", symbol: "highlighter", insertion: "==@CARET@=="),
    .init(name: "Underline", symbol: "underline", insertion: "<u>@CARET@</u>"),
    .init(name: "Larger text", symbol: "textformat.size.larger", insertion: "<span style=\"font-size: 1.3em\">@CARET@</span>"),
    .init(name: "Smaller text", symbol: "textformat.size.smaller", insertion: "<span style=\"font-size: 0.85em\">@CARET@</span>"),
] + FormatPalette.colors.map {
    SlashCommand(name: "Colored text: \($0.name)", symbol: "paintpalette", insertion: "<span style=\"color: \($0.hex)\">@CARET@</span>")
}

extension NSAttributedString.Key {
    /// The block state before and after a line, so one paragraph can be restyled on its own.
    static let perchLineState = NSAttributedString.Key("perchLineState")
    /// Marks fenced code, which gets a full-width background.
    static let perchCodeBlock = NSAttributedString.Key("perchCodeBlock")
    /// What a highlight makes of the page behind text, as `#RRGGBB`, so the text on it can be kept readable.
    static let perchWash = NSAttributedString.Key("perchWash")
}

/// The editor's colours, taken from the theme.
struct EditorColors {
    var ink, dim, faint, accent, warning: PlatformColor
    var codeBlock, inlineCode, mark, selection, currentLine: PlatformColor

    init(_ palette: ThemePalette) {
        func color(_ hex: String, alpha: CGFloat = 1) -> PlatformColor {
            let rgb = ThemeRGB(hex: hex) ?? ThemeRGB(red: 0.5, green: 0.5, blue: 0.5)
            #if os(macOS)
            return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: alpha)
            #else
            return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: alpha)
            #endif
        }
        ink = color(palette.text)
        dim = color(palette.textSecondary)
        faint = color(palette.textMuted)
        accent = color(palette.accent)
        warning = color(palette.warning)
        codeBlock = color(palette.codeBackground)
        inlineCode = color(palette.text, alpha: palette.isDark ? 0.11 : 0.07)
        mark = color(palette.warning, alpha: CGFloat(FormatPalette.plainWashStrength))
        selection = color(palette.accent, alpha: palette.isDark ? 0.36 : 0.24)
        currentLine = color(palette.text, alpha: palette.isDark ? 0.075 : 0.055)
    }
}

/// Styles Markdown text in place, leaving the characters untouched.
@MainActor
final class MarkdownStyler {
    private(set) var appearance: EditorAppearance
    private(set) var palette: ThemePalette
    private(set) var colors: EditorColors
    private var base: PlatformFont
    private var mono: PlatformFont
    private var variants: [String: PlatformFont] = [:]
    private var prefixWidths: [String: CGFloat] = [:]
    private var paragraphs: [String: NSParagraphStyle] = [:]
    private var formatColors: [String: PlatformColor] = [:]
    /// The paragraphs the selection touches. Their HTML tags are shown; everywhere else they are hidden,
    /// when that setting is on.
    private(set) var revealed: NSRange?

    private var ink: PlatformColor { colors.ink }
    private var dim: PlatformColor { colors.dim }
    private var faint: PlatformColor { colors.faint }
    private var accent: PlatformColor { colors.accent }

    /// Notes longer than this stay plain, so typing never stalls.
    static let limit = 400_000

    init(appearance: EditorAppearance, palette: ThemePalette) {
        self.appearance = appearance
        self.palette = palette
        colors = EditorColors(palette)
        base = appearance.font.platformFont(size: appearance.size)
        mono = appearance.font == .mono ? base : ReadingFont.mono.platformFont(size: (appearance.size * 0.94).rounded())
    }

    /// Takes a new look. True when anything changed, so the text needs styling again.
    func update(_ appearance: EditorAppearance, palette: ThemePalette) -> Bool {
        guard appearance != self.appearance || palette != self.palette else { return false }
        if palette != self.palette {
            self.palette = palette
            colors = EditorColors(palette)
        }
        self.appearance = appearance
        base = appearance.font.platformFont(size: appearance.size)
        mono = appearance.font == .mono ? base : ReadingFont.mono.platformFont(size: (appearance.size * 0.94).rounded())
        variants = [:]
        prefixWidths = [:]
        paragraphs = [:]
        formatColors = [:]
        if !appearance.hidesTags { revealed = nil }
        return true
    }

    var baseFont: PlatformFont { base }

    /// The font hidden tags are set in: too small to see, so they take almost no room on the line.
    private lazy var hiddenFont = PlatformFont.systemFont(ofSize: 0.1)

    /// Width of the widest comfortable line, or nil for no limit.
    var maxLineWidth: CGFloat? {
        guard let characters = appearance.characters else { return nil }
        let zero = ("0" as NSString).size(withAttributes: [.font: base]).width
        return (CGFloat(characters) * zero).rounded()
    }

    var typingAttributes: [NSAttributedString.Key: Any] {
        [.font: base, .foregroundColor: ink, .paragraphStyle: paragraph(indent: 0, before: 0)]
    }

    // MARK: Fonts

    private func variant(of font: PlatformFont, bold: Bool = false, italic: Bool = false, size: CGFloat? = nil) -> PlatformFont {
        let size = size ?? font.pointSize
        let key = "\(font.fontName)|\(size)|\(bold)|\(italic)"
        if let cached = variants[key] { return cached }
        #if os(macOS)
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        let result = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: size) ?? NSFont(descriptor: font.fontDescriptor, size: size) ?? font
        #else
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        let result = UIFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor, size: size)
        #endif
        variants[key] = result
        return result
    }

    /// Paragraph styles are shared between lines that look the same: a long note has thousands of lines
    /// and only a handful of different indents.
    private func paragraph(indent: CGFloat, before: CGFloat) -> NSParagraphStyle {
        let key = "\(indent)|\(before)"
        if let cached = paragraphs[key] { return cached }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = (CGFloat(appearance.size) * appearance.spacing).rounded()
        style.paragraphSpacingBefore = before
        style.headIndent = indent
        let fixed = style.copy() as? NSParagraphStyle ?? style
        if paragraphs.count > 400 { paragraphs = [:] }
        paragraphs[key] = fixed
        return fixed
    }

    private func prefixWidth(_ prefix: String) -> CGFloat {
        if let cached = prefixWidths[prefix] { return cached }
        let width = min((prefix.replacingOccurrences(of: "\t", with: "    ") as NSString).size(withAttributes: [.font: base]).width, 220)
        if prefixWidths.count > 400 { prefixWidths = [:] }
        prefixWidths[prefix] = width
        return width
    }

    /// A color picked for text, moved lighter or darker until it can be read on this theme's page.
    /// The note keeps the color that was picked; `alpha` under 1 gives the wash drawn behind highlighted text.
    private func formatColor(_ hex: String, alpha: CGFloat = 1) -> PlatformColor {
        let key = alpha < 1 ? hex + "/\(alpha)" : hex
        if let cached = formatColors[key] { return cached }
        var rgb = ThemeRGB(hex: hex) ?? ThemeRGB(red: 0.5, green: 0.5, blue: 0.5)
        if alpha == 1, let page = ThemeRGB(hex: palette.background) { rgb = FormatPalette.legible(rgb, on: page) }
        #if os(macOS)
        let color = NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: alpha)
        #else
        let color = UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: alpha)
        #endif
        if formatColors.count > 200 { formatColors = [:] }
        formatColors[key] = color
        return color
    }

    /// Text on a colored highlight is read against the highlight, not the page: red words on a red
    /// highlight, or the theme's own text on a dark one, are moved lighter or darker until they can be read.
    private func keepReadableOnHighlights(_ storage: NSTextStorage, in range: NSRange) {
        storage.enumerateAttribute(.perchWash, in: range) { value, washed, _ in
            guard let hex = value as? String, let behind = ThemeRGB(hex: hex) else { return }
            storage.enumerateAttribute(.foregroundColor, in: washed) { value, part, _ in
                guard let color = value as? PlatformColor, let rgb = color.themeRGB else { return }
                let readable = FormatPalette.legible(rgb, on: behind)
                guard readable != rgb else { return }
                #if os(macOS)
                storage.addAttribute(.foregroundColor, value: NSColor(srgbRed: readable.red, green: readable.green, blue: readable.blue, alpha: 1), range: part)
                #else
                storage.addAttribute(.foregroundColor, value: UIColor(red: readable.red, green: readable.green, blue: readable.blue, alpha: 1), range: part)
                #endif
            }
        }
    }

    /// The plain `==highlight==` as it lands on the page: the theme's warning color at the strength `EditorColors` draws it.
    private var plainWash: String {
        guard let page = ThemeRGB(hex: palette.background), let warning = ThemeRGB(hex: palette.warning) else { return palette.background }
        return FormatPalette.plainWash(warning, on: page).hex
    }

    /// The paragraphs a selection touches, or nil when tags aren't being hidden. A very long selection
    /// reveals nothing: restyling half a note on every drag would stall.
    func revealRange(for selection: NSRange, in text: NSString) -> NSRange? {
        guard appearance.hidesTags, text.length > 0, selection.length <= 20_000 else { return nil }
        let range = text.paragraphRange(for: selection.clamped(to: text.length))
        return range.length > 0 ? range : nil
    }

    /// Notes which paragraphs show their tags, without restyling. For use just before a restyle that covers them.
    func noteRevealed(_ range: NSRange?) { revealed = range }

    /// Shows the tags in these paragraphs and hides them again in the ones left behind.
    func reveal(_ range: NSRange?, in storage: NSTextStorage) {
        guard range != revealed else { return }
        let old = revealed
        revealed = range
        let text = storage.string as NSString
        guard text.length < Self.limit else { return }
        for part in [old, range].compactMap({ $0 }) {
            let clamped = text.paragraphRange(for: part.clamped(to: text.length))
            guard clamped.length > 0, text.range(of: "<", options: [], range: clamped).location != NSNotFound else { continue }
            restyle(storage, lines: clamped, allowWiden: false)
        }
    }

    // MARK: Styling

    func restyleAll(_ storage: NSTextStorage) {
        restyle(storage, lines: NSRange(location: 0, length: storage.length), allowWiden: false)
    }

    /// Restyles the paragraphs an edit touched. Widens to the whole note only when a fence or frontmatter changed.
    func restyle(_ storage: NSTextStorage, edited: NSRange) {
        let length = storage.length
        let start = min(edited.location, length)
        // One character further, so a line split off by Return is restyled too.
        let end = min(NSMaxRange(edited) + 1, length)
        restyle(storage, lines: NSRange(location: start, length: max(end - start, 0)), allowWiden: true)
    }

    private func storedState(_ storage: NSTextStorage, at index: Int, after: Bool) -> MarkdownBlockState? {
        guard index >= 0, index < storage.length,
              let stored = storage.attribute(.perchLineState, at: index, effectiveRange: nil) as? String else { return nil }
        let parts = stored.split(separator: "\u{1}", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return MarkdownBlockState(code: String(after ? parts[1] : parts[0]))
    }

    private func restyle(_ storage: NSTextStorage, lines requested: NSRange, allowWiden: Bool) {
        let text = storage.string as NSString
        let length = text.length
        guard length > 0 else { return }
        guard length < Self.limit else {
            storage.beginEditing()
            storage.setAttributes(typingAttributes, range: NSRange(location: 0, length: length))
            storage.endEditing()
            return
        }
        let range = text.lineRange(for: requested)
        var startState = MarkdownBlockState.normal
        if range.location > 0 {
            guard let stored = storedState(storage, at: range.location - 1, after: true) else {
                restyleAll(storage)
                return
            }
            startState = stored
        }
        let result = MarkdownHighlighter.highlight(text, range: range, startState: startState)
        if allowWiden {
            var widen = false
            let next = NSMaxRange(result.range)
            if next < length, storedState(storage, at: next, after: false) != result.endState { widen = true }
            // Frontmatter depends on a closing line further down, so check the first line still agrees.
            if !widen, range.location > 0, text.hasPrefix("---") {
                let first = MarkdownHighlighter.highlight(text, range: NSRange(location: 0, length: 0)).lines.first?.after
                if first != storedState(storage, at: 0, after: true) { widen = true }
            }
            if widen {
                restyleAll(storage)
                return
            }
        }
        storage.beginEditing()
        apply(result, to: storage, text: text)
        storage.endEditing()
    }

    private func apply(_ result: MarkdownHighlight, to storage: NSTextStorage, text: NSString) {
        let size = CGFloat(appearance.size)
        for line in result.lines where line.range.length > 0 {
            var indent: CGFloat = 0
            if line.prefixLength > 0, line.before == .normal {
                indent = prefixWidth(text.substring(with: NSRange(location: line.range.location, length: min(line.prefixLength, line.range.length))))
            }
            storage.setAttributes([
                .font: base, .foregroundColor: ink,
                .paragraphStyle: paragraph(indent: indent, before: 0),
                .perchLineState: line.before.code + "\u{1}" + line.after.code,
            ], range: line.range)
            // Whole lines, line endings included, so blank lines don't break a code block's background.
            let inCode: Bool = {
                if case .fence = line.before { return true }
                if case .fence = line.after { return true }
                return line.before == .math || line.after == .math
            }()
            if inCode { storage.addAttribute(.perchCodeBlock, value: true, range: line.range) }
        }
        func restyleFonts(_ range: NSRange, bold: Bool = false, italic: Bool = false) {
            storage.enumerateAttribute(.font, in: range) { value, part, _ in
                guard let font = value as? PlatformFont else { return }
                storage.addAttribute(.font, value: variant(of: font, bold: bold, italic: italic), range: part)
            }
        }
        for span in result.spans where span.range.length > 0 {
            let range = span.range
            switch span.kind {
            case let .heading(level):
                let scale: CGFloat = [1.6, 1.36, 1.18, 1.06, 1, 1][min(max(level, 1), 6) - 1]
                storage.addAttributes([
                    .font: variant(of: base, bold: true, size: (size * scale).rounded()),
                    .paragraphStyle: paragraph(indent: 0, before: range.location == 0 ? 0 : (size * (level <= 2 ? 0.7 : 0.45)).rounded()),
                ], range: range)
            case .marker:
                // Full strength leaves the marks in the text colour the line already has.
                if !appearance.fullStrengthMarks { storage.addAttribute(.foregroundColor, value: faint, range: range) }
            case .strong:
                restyleFonts(range, bold: true)
            case .emphasis:
                restyleFonts(range, italic: true)
            case .strikethrough:
                storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: dim], range: range)
            case .highlight:
                storage.addAttributes([.backgroundColor: colors.mark, .perchWash: plainWash], range: range)
                keepReadableOnHighlights(storage, in: range)
            case .inlineCode:
                storage.addAttributes([.font: mono, .backgroundColor: colors.inlineCode], range: range)
            case .codeBlock:
                storage.addAttributes([
                    .font: mono, .perchCodeBlock: true, .paragraphStyle: paragraph(indent: 0, before: 0),
                ], range: range)
            case .codeFence:
                storage.addAttribute(.foregroundColor, value: dim, range: range)
            case .linkText, .footnote:
                storage.addAttribute(.foregroundColor, value: accent, range: range)
            case .linkURL:
                storage.addAttribute(.foregroundColor, value: faint, range: range)
            case .wikiLink:
                storage.addAttribute(.foregroundColor, value: accent, range: range)
            case .listMarker:
                storage.addAttribute(.foregroundColor, value: accent, range: range)
            case let .taskBox(checked):
                storage.addAttributes([.foregroundColor: checked ? dim : accent, .font: mono], range: range)
            case .taskDone:
                storage.addAttribute(.foregroundColor, value: dim, range: range)
            case .blockquote:
                storage.addAttribute(.foregroundColor, value: dim, range: range)
            case .calloutTag:
                storage.addAttribute(.foregroundColor, value: accent, range: range)
                restyleFonts(range, bold: true)
            case .frontmatter:
                storage.addAttributes([.foregroundColor: faint, .font: mono], range: range)
            case .frontmatterKey:
                storage.addAttribute(.foregroundColor, value: dim, range: range)
            case .rule, .comment:
                storage.addAttribute(.foregroundColor, value: faint, range: range)
            case .table:
                storage.addAttributes([.font: mono, .paragraphStyle: paragraph(indent: 0, before: 0)], range: range)
            case .conflict:
                storage.addAttribute(.foregroundColor, value: colors.warning, range: range)
                restyleFonts(range, bold: true)
            case let .textColor(hex):
                storage.addAttribute(.foregroundColor, value: formatColor(hex), range: range)
                keepReadableOnHighlights(storage, in: range)
            case let .highlightColor(hex):
                var wash = hex
                if let color = ThemeRGB(hex: hex), let page = ThemeRGB(hex: palette.background) {
                    wash = FormatPalette.wash(color, on: page, dark: palette.isDark).hex
                }
                storage.addAttributes([
                    .backgroundColor: formatColor(hex, alpha: CGFloat(FormatPalette.washStrength(dark: palette.isDark))), .perchWash: wash,
                ], range: range)
                keepReadableOnHighlights(storage, in: range)
            case .underline:
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            case let .textSize(scale):
                storage.enumerateAttribute(.font, in: range) { value, part, _ in
                    guard let font = value as? PlatformFont else { return }
                    storage.addAttribute(.font, value: variant(of: font, size: (font.pointSize * CGFloat(scale) * 2).rounded() / 2), range: part)
                }
            case .subscript, .superscript:
                storage.enumerateAttribute(.font, in: range) { value, part, _ in
                    guard let font = value as? PlatformFont else { return }
                    storage.addAttribute(.font, value: variant(of: font, size: (font.pointSize * 0.8).rounded()), range: part)
                }
                storage.addAttribute(.baselineOffset, value: size * (span.kind == .superscript ? 0.32 : -0.18), range: range)
            case .htmlTag, .formatTag:
                // Only formatting tags hide. Other HTML is content, or structure the editor doesn't draw.
                let shown = span.kind == .htmlTag || !appearance.hidesTags
                    || revealed.map { $0.location <= range.location && NSMaxRange(range) <= NSMaxRange($0) } ?? false
                if shown {
                    // Small and faint, so the words between the tags are what the eye lands on.
                    storage.addAttribute(.font, value: variant(of: mono, size: (size * 0.78).rounded()), range: range)
                    if !appearance.fullStrengthMarks { storage.addAttribute(.foregroundColor, value: faint, range: range) }
                } else {
                    // Still in the text, and still copied and saved: just drawn too small to see or take up room.
                    storage.addAttributes([.font: hiddenFont, .foregroundColor: PlatformColor.clear], range: range)
                }
                storage.removeAttribute(.underlineStyle, range: range)
                storage.removeAttribute(.strikethroughStyle, range: range)
                storage.removeAttribute(.backgroundColor, range: range)
                storage.removeAttribute(.baselineOffset, range: range)
            }
        }
    }

    /// What the caret is in the middle of typing, if anything.
    nonisolated static func completion(in text: NSString, caret: Int) -> EditorCompletion? {
        guard caret <= text.length else { return nil }
        let lineRange = text.lineRange(for: NSRange(location: min(caret, max(text.length - 1, 0)), length: 0))
        let start = caret < lineRange.location ? caret : lineRange.location
        let before = text.substring(with: NSRange(location: start, length: caret - start))
        if let open = before.range(of: "[[", options: .backwards) {
            let query = String(before[open.upperBound...])
            if !query.contains("]") { return .wiki(query) }
        }
        if before.hasPrefix("/"), !before.dropFirst().contains(" ") { return .slash(String(before.dropFirst())) }
        return nil
    }
}

/// Draws a soft, full-width background behind fenced code.
final class PerchLayoutManager: NSLayoutManager {
    var codeBlockColor = PlatformColor.gray.withAlphaComponent(0.12)
    /// The fill behind the line the caret is on, or nil when that setting is off.
    var currentLineColor: PlatformColor?
    /// Where the caret is, or nil while text is selected.
    var caretLocation: Int?

    /// The whole paragraph holding the caret, so a wrapped line is highlighted as one.
    private func currentLineRect(in storage: NSTextStorage) -> CGRect? {
        guard currentLineColor != nil, let caret = caretLocation, caret <= storage.length else { return nil }
        let text = storage.string as NSString
        if caret == text.length, text.length == 0 || text.character(at: text.length - 1) == 0x0A {
            // The empty last line has no characters of its own.
            let extra = extraLineFragmentRect
            return extra.height > 0 ? extra : nil
        }
        let paragraph = text.paragraphRange(for: NSRange(location: min(caret, max(text.length - 1, 0)), length: 0))
        var rect = CGRect.null
        enumerateLineFragments(forGlyphRange: glyphRange(forCharacterRange: paragraph, actualCharacterRange: nil)) { fragment, _, _, _, _ in
            rect = rect.union(fragment)
        }
        return rect.isNull ? nil : rect
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        if let storage = textStorage, let container = textContainers.first {
            #if os(macOS)
            let context = NSGraphicsContext.current?.cgContext
            #else
            let context = UIGraphicsGetCurrentContext()
            #endif
            // This is called for a few lines at a time. Clip to them, so a block drawn in pieces isn't painted twice.
            var showing = CGRect.null
            enumerateLineFragments(forGlyphRange: glyphsToShow) { rect, _, _, _, _ in showing = showing.union(rect) }
            let padding = container.lineFragmentPadding
            let left = origin.x + padding - 8, width = container.size.width - padding * 2 + 16
            context?.saveGState()
            if !showing.isNull { context?.clip(to: CGRect(x: left, y: origin.y + showing.minY, width: width, height: showing.height)) }
            if let line = currentLineRect(in: storage), let color = currentLineColor {
                let frame = CGRect(x: left, y: origin.y + line.minY, width: width, height: line.height)
                color.setFill()
                #if os(macOS)
                NSBezierPath(roundedRect: frame, xRadius: 5, yRadius: 5).fill()
                #else
                UIBezierPath(roundedRect: frame, cornerRadius: 5).fill()
                #endif
            }
            let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
            var index = characters.location
            let end = NSMaxRange(characters)
            while index < end, index < storage.length {
                var effective = NSRange(location: 0, length: 0)
                let value = storage.attribute(.perchCodeBlock, at: index, longestEffectiveRange: &effective, in: NSRange(location: 0, length: storage.length))
                if value != nil, effective.length > 0 {
                    let glyphs = glyphRange(forCharacterRange: effective, actualCharacterRange: nil)
                    var block = CGRect.null
                    enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in block = block.union(rect) }
                    if !block.isNull {
                        let frame = CGRect(x: left, y: origin.y + block.minY, width: width, height: block.height)
                        codeBlockColor.setFill()
                        #if os(macOS)
                        NSBezierPath(roundedRect: frame, xRadius: 7, yRadius: 7).fill()
                        #else
                        UIBezierPath(roundedRect: frame, cornerRadius: 7).fill()
                        #endif
                    }
                }
                index = max(NSMaxRange(effective), index + 1)
            }
            context?.restoreGState()
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }
}

/// Builds the text system by hand. The caller must keep the storage alive: a text view made this way doesn't.
private func makeTextStack() -> (storage: NSTextStorage, container: NSTextContainer) {
    let storage = NSTextStorage()
    let layout = PerchLayoutManager()
    layout.allowsNonContiguousLayout = true
    storage.addLayoutManager(layout)
    let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
    container.widthTracksTextView = true
    layout.addTextContainer(container)
    return (storage, container)
}

/// The middle of `new` that differs from `old`, so an outside change keeps the caret and scroll position.
private func changedSpan(from old: NSString, to new: NSString) -> (range: NSRange, replacement: String) {
    let limit = min(old.length, new.length)
    var prefix = 0
    while prefix < limit, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
    var suffix = 0
    while suffix < limit - prefix, old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) { suffix += 1 }
    // Never cut a surrogate pair in half.
    while prefix > 0, UTF16.isLeadSurrogate(old.character(at: prefix - 1)) { prefix -= 1 }
    while suffix > 0, UTF16.isTrailSurrogate(old.character(at: old.length - suffix)) { suffix -= 1 }
    return (
        NSRange(location: prefix, length: old.length - prefix - suffix),
        new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix))
    )
}

extension PlatformColor {
    /// The color's red, green and blue, or nil for one that is see-through (dimmed marks, hidden tags).
    var themeRGB: ThemeRGB? {
        #if os(macOS)
        guard let color = usingColorSpace(.sRGB), color.alphaComponent >= 1 else { return nil }
        return ThemeRGB(red: Double(color.redComponent), green: Double(color.greenComponent), blue: Double(color.blueComponent))
        #else
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha), alpha >= 1 else { return nil }
        return ThemeRGB(red: Double(red), green: Double(green), blue: Double(blue))
        #endif
    }
}

extension NSRange {
    /// This range pulled back inside text of the given length, so a selection can never point past the end.
    func clamped(to length: Int) -> NSRange {
        let start = Swift.min(Swift.max(location, 0), length)
        return NSRange(location: start, length: Swift.min(Swift.max(self.length, 0), length - start))
    }
}

/// The parts of the editor that are the same on the Mac and the iPhone.
@MainActor
class EditorCoordinatorBase: NSObject, NSTextStorageDelegate {
    var text: Binding<String>
    var actions: EditorActions
    var onCompletionQuery: (EditorCompletion?) -> Void
    let styler: MarkdownStyler
    /// The typing helpers and text checking that are on. Changes take effect on the next key.
    var behavior: EditorBehavior
    weak var view: PerchTextView?
    var isApplying = false
    /// The text last handed to the binding, and the editor's length then, so `sync(to:)` can tell at once
    /// that the binding is only giving back what the editor gave it.
    private var lastPublished: (text: String, length: Int)?
    private var pending: NSRange?
    private var flushScheduled = false

    init(
        text: Binding<String>, actions: EditorActions, appearance: EditorAppearance, behavior: EditorBehavior, palette: ThemePalette,
        onCompletionQuery: @escaping (EditorCompletion?) -> Void
    ) {
        self.text = text
        self.actions = actions
        self.behavior = behavior
        self.onCompletionQuery = onCompletionQuery
        styler = MarkdownStyler(appearance: appearance, palette: palette)
    }

    nonisolated func textStorage(
        _ textStorage: NSTextStorage, didProcessEditing editedMask: TextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        MainActor.assumeIsolated {
            if var range = pending {
                // Keep the earlier range lined up with the text as it is now.
                if editedRange.location <= range.location { range.location = max(editedRange.location, range.location + delta) }
                pending = NSUnionRange(range, editedRange)
            } else {
                pending = editedRange
            }
            guard !flushScheduled else { return }
            flushScheduled = true
            DispatchQueue.main.async { [weak self] in self?.flushStyles() }
        }
    }

    /// Styles whatever changed since the last pass. Safe to call at any time.
    func flushStyles() {
        flushScheduled = false
        // Text still being composed (Japanese, Chinese, accents) is left alone until it is committed.
        guard let range = pending, let view, !view.isComposing, let storage = view.textStorageIfLoaded else { return }
        pending = nil
        let clamped = NSRange(location: min(range.location, storage.length), length: min(range.length, storage.length - min(range.location, storage.length)))
        // The edit moved the text, so where tags are shown is worked out again from the selection as it is now.
        let wasRevealed = styler.revealed
        let nowRevealed = styler.revealRange(for: view.selection, in: view.content)
        styler.noteRevealed(nowRevealed)
        styler.restyle(storage, edited: clamped)
        if let wasRevealed, wasRevealed != nowRevealed {
            // Wherever the caret came from may still be showing its tags.
            styler.noteRevealed(wasRevealed.clamped(to: storage.length))
            styler.reveal(nowRevealed, in: storage)
        }
    }

    func restyleEverything() {
        pending = nil
        guard let storage = view?.textStorageIfLoaded else { return }
        styler.restyleAll(storage)
    }

    /// Runs after every change to the text, whoever made it.
    func contentChanged() {
        guard let view else { return }
        flushStyles()
        // A native copy, compared exactly: see TextIdentity. Swift's == on the editor's bridged text was most
        // of what a keystroke cost in a long note.
        let current = TextIdentity.native(view.content as String)
        lastPublished = (current, view.content.length)
        if !TextIdentity.same(text.wrappedValue, current) { text.wrappedValue = current }
        onCompletionQuery(MarkdownStyler.completion(in: view.content, caret: view.selection.location))
        caretMoved()
    }

    /// Keeps the current-line highlight under the caret. Does nothing while that setting is off.
    func caretMoved() {
        guard let view, let layout = view.layoutManagerIfLoaded as? PerchLayoutManager else { return }
        let selection = view.selection
        revealGeneration += 1
        if view.isSelectingWithMouse {
            // Showing a line's tags moves its words. Not under the pointer in the middle of a click, a
            // double-click or a drag: wait for the mouse to come up and stay up.
            revealWhenMouseSettles()
        } else if !view.isComposing, let storage = view.textStorageIfLoaded {
            styler.reveal(styler.revealRange(for: selection, in: view.content), in: storage)
        }
        formatStateChanged()
        let caret: Int? = styler.appearance.highlightsCurrentLine && selection.length == 0 ? selection.location : nil
        guard caret != layout.caretLocation else { return }
        let length = view.content.length
        let old = layout.caretLocation
        layout.caretLocation = caret
        for location in [old, caret].compactMap({ $0 }) where length > 0 {
            let paragraph = view.content.paragraphRange(for: NSRange(location: min(location, length - 1), length: 0))
            layout.invalidateDisplay(forCharacterRange: paragraph)
        }
        view.redrawBackground()
    }

    private var revealGeneration = 0

    private func revealWhenMouseSettles() {
        let generation = revealGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, generation == self.revealGeneration, let view = self.view else { return }
            guard !view.isMouseDown else { return self.revealWhenMouseSettles() }
            guard !view.isComposing, let storage = view.textStorageIfLoaded else { return }
            self.styler.reveal(self.styler.revealRange(for: view.selection, in: view.content), in: storage)
        }
    }

    /// Takes new typing helpers and text checking, and applies the ones the text view owns.
    func update(_ behavior: EditorBehavior) {
        guard behavior != self.behavior else { return }
        self.behavior = behavior
        view?.apply(behavior)
    }

    func apply(_ edit: TextEdit) {
        guard let view else { return }
        // Some commands only move the selection (Tab between table cells): nothing to undo.
        if edit.range.length == 0, edit.replacement.isEmpty {
            view.selection = edit.selection.clamped(to: view.content.length)
            view.revealSelection()
            caretMoved()
            return
        }
        isApplying = true
        view.applyEdit(edit)
        isApplying = false
        contentChanged()
    }

    private var formatScheduled = false

    /// Tells the format bars what is at the caret. Worked out once per turn of the run loop, and only
    /// while a bar is showing.
    func formatStateChanged() {
        guard actions.format.watchers > 0, !formatScheduled else { return }
        formatScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.formatScheduled = false
            guard let view = self.view, !view.isComposing else { return }
            let content = view.content
            let active = content.length < MarkdownStyler.limit
                ? MarkdownFormatting.formats(in: content as String, selection: view.selection.clamped(to: content.length))
                : ActiveFormats()
            if active != self.actions.format.active { self.actions.format.active = active }
        }
    }

    func perform(_ command: EditorCommand) {
        guard let view, !view.isComposing else { return }
        let string = view.content as String
        let selection = view.selection
        /// A command that can't be done here (bold inside a code block, say) does nothing.
        func run(_ edit: TextEdit?) { if let edit { apply(edit) } }
        func toggle(_ format: InlineFormat) { run(MarkdownFormatting.toggle(format, in: string, selection: selection)) }
        switch command {
        case .bold: toggle(.bold)
        case .italic: toggle(.italic)
        case .strikethrough: toggle(.strikethrough)
        case .underline: toggle(.underline)
        case .highlight: toggle(.highlight)
        case .subscript: toggle(.subscript)
        case .superscript: toggle(.superscript)
        case .code: run(MarkdownFormatting.toggleCode(in: string, selection: selection))
        case let .textColor(hex): run(MarkdownFormatting.set(.textColor, value: hex, in: string, selection: selection))
        case let .highlightColor(hex): run(MarkdownFormatting.set(.highlight, value: hex, in: string, selection: selection))
        case let .sizeStep(delta): run(MarkdownFormatting.stepSize(delta, in: string, selection: selection))
        case .clearFormatting: run(MarkdownFormatting.clearFormatting(in: string, selection: selection))
        case let .setHeading(level): run(MarkdownFormatting.setHeading(level, in: string, selection: selection))
        case .quote: run(MarkdownFormatting.toggleQuote(in: string, selection: selection))
        case let .callout(type): run(MarkdownFormatting.setCallout(type, in: string, selection: selection))
        case let .codeBlock(language): run(MarkdownFormatting.toggleCodeBlock(language: language, in: string, selection: selection))
        case .divider: run(MarkdownFormatting.insertDivider(in: string, selection: selection))
        case let .table(rows, columns): run(MarkdownFormatting.insertTable(rows: rows, columns: columns, in: string, selection: selection))
        case .tableAddRow: run(MarkdownFormatting.tableAddRow(in: string, selection: selection))
        case .tableAddColumn: run(MarkdownFormatting.tableAddColumn(in: string, selection: selection))
        case .tableTidy: run(MarkdownFormatting.tidyTable(in: string, selection: selection))
        case let .align(alignment): run(MarkdownFormatting.setAlignment(alignment, in: string, selection: selection))
        case .showColors: actions.format.paletteRequests += 1
        case .link: apply(MarkdownEditing.link(in: string, selection: selection))
        case .wikiLink: apply(MarkdownEditing.wikiLink(in: string, selection: selection))
        case .heading: apply(MarkdownEditing.cycleHeading(in: string, selection: selection))
        case .bullet: apply(MarkdownEditing.toggleList(in: string, selection: selection, kind: .bullet))
        case .numbered: apply(MarkdownEditing.toggleList(in: string, selection: selection, kind: .numbered))
        case .task: apply(MarkdownEditing.toggleList(in: string, selection: selection, kind: .task))
        case .indent:
            let unit = behavior.typing.indent.unit
            apply(MarkdownEditing.indent(in: string, selection: selection, outdent: false, options: behavior.typing)
                ?? TextEdit(range: selection, replacement: unit, selection: NSRange(location: selection.location + (unit as NSString).length, length: 0)))
        case .outdent:
            // Shift-Tab in a table goes back a cell.
            if let edit = MarkdownFormatting.tableMove(forward: false, in: string, selection: selection) {
                apply(edit)
            } else if let edit = MarkdownEditing.indent(in: string, selection: selection, outdent: true, options: behavior.typing) {
                apply(edit)
            }
        case .undo:
            view.undoManager?.undo()
        case .redo:
            view.undoManager?.redo()
        }
    }

    /// Return, Tab and typing a mark over a selection. True when the key was handled here.
    func handleTyped(_ typed: String, replacing range: NSRange) -> Bool {
        // Never step in while an input method is composing, and leave code blocks to plain typing.
        guard !isApplying, let view, !view.isComposing, NSMaxRange(range) <= view.content.length else { return false }
        flushStyles()
        guard !isInsideCode(at: range.location) else { return false }
        let string = view.content as String
        // Tab in a table goes to the next cell, and adds a row after the last one.
        if typed == "\t", behavior.typing.tabIndentsLists, let edit = MarkdownFormatting.tableMove(forward: true, in: string, selection: range) {
            apply(edit)
            return true
        }
        // Each helper can be turned off in Settings; one that is off leaves the key to do what it normally does.
        if let edit = MarkdownEditing.edit(forTyping: typed, in: string, selection: range, options: behavior.typing) {
            apply(edit)
            return true
        }
        return false
    }

    /// Backspace or Delete on part of a formatting tag. While tags are hidden away they are treated as one
    /// thing: the key takes the whole pair, so the markup can't be left half-deleted. With the setting off,
    /// tags are plain text like any other. True when the key was handled here.
    func handleDeletion(of range: NSRange) -> Bool {
        guard styler.appearance.hidesTags, range.length == 1, !isApplying, let view, !view.isComposing, !view.isUndoingOrRedoing,
              NSMaxRange(range) <= view.content.length, view.content.length < MarkdownStyler.limit,
              view.content.character(at: range.location) != 0x0A else { return false }
        // Cheap test first: this runs on every Backspace.
        let content = view.content
        let line = content.lineRange(for: range)
        guard content.range(of: "<", options: [], range: line).location != NSNotFound,
              let edit = MarkdownFormatting.deletingTag(in: content as String, range: range) else { return false }
        apply(edit)
        return true
    }

    /// True when the line holding `location` is inside a fenced code or `$$` block.
    func isInsideCode(at location: Int) -> Bool {
        guard let view, let storage = view.textStorageIfLoaded, storage.length > 0 else { return false }
        let content = view.content
        let lineStart = content.lineRange(for: NSRange(location: min(location, content.length), length: 0)).location
        let stored: String?
        let after: Bool
        if lineStart < storage.length {
            stored = storage.attribute(.perchLineState, at: lineStart, effectiveRange: nil) as? String
            after = false
        } else {
            // An empty last line has no characters of its own: go by how the line above ended.
            stored = storage.attribute(.perchLineState, at: storage.length - 1, effectiveRange: nil) as? String
            after = true
        }
        guard let parts = stored?.split(separator: "\u{1}", maxSplits: 1, omittingEmptySubsequences: false), parts.count == 2 else { return false }
        switch MarkdownBlockState(code: String(after ? parts[1] : parts[0])) {
        case .fence, .math: return true
        case .normal, .frontmatter: return false
        }
    }

    /// Brings the text view in line with a change made elsewhere, touching only what differs.
    func sync(to new: String) {
        guard let view else { return }
        if let last = lastPublished, last.length == view.content.length, TextIdentity.same(last.text, new) { return }
        guard !TextIdentity.same(TextIdentity.native(view.content as String), new) else { return }
        let old = view.content.copy() as? NSString ?? view.content
        let change = changedSpan(from: old, to: new as NSString)
        let caret = view.selection
        var selection = caret
        if caret.location >= NSMaxRange(change.range) {
            selection.location += (change.replacement as NSString).length - change.range.length
        } else if NSMaxRange(caret) > change.range.location {
            selection = NSRange(location: min(caret.location, change.range.location), length: 0)
        }
        selection.location = min(max(selection.location, 0), (new as NSString).length)
        selection.length = min(selection.length, (new as NSString).length - selection.location)
        isApplying = true
        view.applyEdit(TextEdit(range: change.range, replacement: change.replacement, selection: selection), reveal: false)
        isApplying = false
        lastPublished = (new, view.content.length)
        flushStyles()
    }

    func bindCommon(_ view: PerchTextView) {
        self.view = view
        view.commandHandler = { [weak self] in self?.perform($0) }
        view.escapeHandler = { [weak self] in self?.actions.onEscape?() ?? false }
        view.focusHandler = { [weak self] focused in
            guard let self else { return }
            if focused { FormatTarget.shared.focus(self.actions) } else { FormatTarget.shared.blur(self.actions) }
            // A click where the caret already was moves nothing, but that line should now show its tags.
            if focused { self.caretMoved() }
        }
        actions.perform = { [weak self] command in
            guard let self, let view = self.view, view.isEditable else { return }
            self.perform(command)
            view.keepFocus()
        }
        actions.performIfFocused = { [weak self] command in
            guard let self, let view = self.view, view.isEditable, view.hasKeyboard else { return }
            self.perform(command)
        }
        actions.format.refresh = { [weak self] in self?.formatStateChanged() }
        actions.replaceTrigger = { [weak self] typed in
            guard let self, let view = self.view else { return }
            // `@CARET@` in a slash command marks where the caret should land.
            let pieces = typed.components(separatedBy: SlashCommand.caret)
            let text = pieces.joined()
            let caretOffset = pieces.count > 1 ? (pieces[0] as NSString).length : (text as NSString).length
            let source = view.content
            let caret = view.selection.location
            let line = source.lineRange(for: NSRange(location: min(caret, max(source.length - 1, 0)), length: 0))
            let lineStart = min(line.location, caret)
            let before = source.substring(with: NSRange(location: lineStart, length: caret - lineStart)) as NSString
            let wiki = before.range(of: "[[", options: .backwards)
            let start = wiki.location != NSNotFound ? lineStart + wiki.location : lineStart
            self.apply(TextEdit(
                range: NSRange(location: start, length: caret - start), replacement: text,
                selection: NSRange(location: start + caretOffset, length: 0)
            ))
        }
        actions.topLine = { [weak view] in view?.topLine() ?? 0 }
        actions.scrollToLine = { [weak view] in view?.scroll(toLine: $0) }
        actions.caretRect = { [weak view, weak actions] in view?.caretRectInEditor()?.offsetBy(dx: 0, dy: actions?.topInset ?? 0) }
        actions.applyPending = { [weak self] in self?.applyInitialPosition() }
    }

    /// Places a new editor where the reader was, once it has a size.
    func applyInitialPosition() {
        guard let view else { return }
        let line = actions.initialLine
        let focus = actions.focusOnAppear
        actions.initialLine = nil
        actions.focusOnAppear = false
        guard line != nil || focus else { return }
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            if let line {
                let location = MarkdownEditing.location(ofLine: Int(line), in: view.content)
                view.selection = NSRange(location: location, length: 0)
                view.scroll(toLine: line)
            }
            if focus {
                view.isEditable = true
                view.takeFocus()
            }
        }
    }

    /// Applies the theme's colours to the parts of the text view that aren't text.
    func applyColors() {
        guard let view else { return }
        let layout = view.layoutManagerIfLoaded as? PerchLayoutManager
        layout?.codeBlockColor = styler.colors.codeBlock
        layout?.currentLineColor = styler.appearance.highlightsCurrentLine ? styler.colors.currentLine : nil
        caretMoved()
        view.applyColors(styler.colors)
        view.typingAttributes = styler.typingAttributes
    }

    /// Hands the keyboard back when the editor goes behind the reader, so typing can't change a note unseen.
    func setActive(_ active: Bool) {
        guard let view, view.isEditable != active else { return }
        if !active { view.giveUpFocus() }
        view.isEditable = active
    }
}

// MARK: Shared text view behaviour

extension PerchTextView {
    /// The fractional source line sitting at the top of the visible text.
    func topLine() -> Double {
        guard let layout = layoutManagerIfLoaded, let container = containerIfLoaded else { return 0 }
        let y = visibleTop
        guard y > 0, content.length > 0 else { return 0 }
        let glyph = layout.glyphIndex(for: CGPoint(x: 4, y: y), in: container)
        let character = layout.characterIndexForGlyph(at: glyph)
        let paragraph = content.paragraphRange(for: NSRange(location: min(character, content.length), length: 0))
        let rect = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: paragraph, actualCharacterRange: nil), in: container)
        let fraction = rect.height > 0 ? min(max((y - rect.minY) / rect.height, 0), 0.999) : 0
        return Double(MarkdownEditing.lineNumber(of: paragraph.location, in: content)) + Double(fraction)
    }

    func scroll(toLine line: Double) {
        guard let layout = layoutManagerIfLoaded, let container = containerIfLoaded else { return }
        guard line > 0, content.length > 0 else {
            visibleTop = 0
            return
        }
        let location = MarkdownEditing.location(ofLine: Int(line), in: content)
        let paragraph = content.paragraphRange(for: NSRange(location: min(location, content.length), length: 0))
        let rect = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: paragraph, actualCharacterRange: nil), in: container)
        visibleTop = rect.minY + rect.height * CGFloat(line - line.rounded(.down))
    }
}

#if os(macOS)
#if DEBUG
/// For snapshot checks: where the note editor inside a view is scrolled.
public enum EditorDebug {
    /// The note editor in a window, for the note stress test, which types into it.
    public static func editor(in view: NSView) -> NSTextView? {
        func editors(in view: NSView) -> [PerchTextView] {
            (view as? PerchTextView).map { [$0] } ?? view.subviews.flatMap(editors)
        }
        return editors(in: view).first { $0.window != nil && !$0.isHiddenOrHasHiddenAncestor }
    }

    public static func report(in view: NSView) -> [String: Any]? {
        func editors(in view: NSView) -> [PerchTextView] {
            (view as? PerchTextView).map { [$0] } ?? view.subviews.flatMap(editors)
        }
        guard let editor = editors(in: view).first(where: { $0.window != nil }) else { return nil }
        return [
            "visibleTop": Double(editor.visibleTop), "topLine": editor.topLine(),
            "insetTop": Double(editor.textContainerInset.height),
            "clipHeight": Double(editor.enclosingScrollView?.contentView.bounds.height ?? 0),
            "contentInsetTop": Double(editor.enclosingScrollView?.contentInsets.top ?? 0),
            "frameHeight": Double(editor.frame.height), "length": editor.content.length,
            "selection": editor.selection.location,
        ]
    }
}
#endif

final class PerchTextView: NSTextView {
    var pasteImageData: ((Data, String) -> String?)?
    var ownedStorage: NSTextStorage?
    var commandHandler: ((EditorCommand) -> Void)?
    var escapeHandler: (() -> Bool)?
    var maxLineWidth: CGFloat?
    var minimumInset = NSSize(width: 18, height: 16) { didSet { updateInsets() } }

    var content: NSString { string as NSString }
    var selection: NSRange {
        get { selectedRange() }
        set { setSelectedRange(newValue) }
    }
    var textStorageIfLoaded: NSTextStorage? { textStorage }
    var layoutManagerIfLoaded: NSLayoutManager? { layoutManager }
    var containerIfLoaded: NSTextContainer? { textContainer }

    /// Distance scrolled, in text coordinates.
    var visibleTop: CGFloat {
        get { enclosingScrollView?.contentView.bounds.minY ?? 0 }
        set {
            guard let scroll = enclosingScrollView else { return }
            layoutManager?.ensureLayout(for: textContainer!)
            let limit = max(frame.height - scroll.contentView.bounds.height, 0)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: min(max(newValue, 0), limit)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    /// Makes one change through the text view's own editing calls, so it is a single step to undo.
    func applyEdit(_ edit: TextEdit, reveal: Bool = true) {
        guard NSMaxRange(edit.range) <= content.length, shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        let selection = edit.selection.clamped(to: content.length)
        setSelectedRange(selection)
        if reveal { scrollRangeToVisible(selection) }
    }

    func takeFocus() { window?.makeFirstResponder(self) }

    func giveUpFocus() {
        if window?.firstResponder === self { window?.makeFirstResponder(nil) }
    }

    /// After a click on the format bar: the keyboard stays with the text.
    func keepFocus() {
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
    }

    var hasKeyboard: Bool { window?.firstResponder === self }
    var focusHandler: ((Bool) -> Void)?

    func revealSelection() { scrollRangeToVisible(selectedRange()) }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { focusHandler?(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { focusHandler?(false) }
        return resigned
    }

    var isComposing: Bool { hasMarkedText() }
    /// True while a click or drag in the text is what is moving the selection.
    var isSelectingWithMouse: Bool {
        guard let type = NSApp.currentEvent?.type else { return false }
        return type == .leftMouseDown || type == .leftMouseDragged
    }
    var isMouseDown: Bool { NSEvent.pressedMouseButtons & 1 != 0 }
    var isUndoingOrRedoing: Bool { undoManager?.isUndoing == true || undoManager?.isRedoing == true }

    func applyColors(_ colors: EditorColors) {
        insertionPointColor = colors.accent
        selectedTextAttributes = [.backgroundColor: colors.selection]
        needsDisplay = true
    }

    func redrawBackground() { needsDisplay = true }

    /// Spelling, autocorrect and smart punctuation, from the Editing settings.
    func apply(_ behavior: EditorBehavior) {
        isContinuousSpellCheckingEnabled = behavior.spellCheck
        // On follows the Mac's own "Correct spelling automatically" setting, as the editor always has.
        isAutomaticSpellingCorrectionEnabled = behavior.autocorrect && NSSpellChecker.isAutomaticSpellingCorrectionEnabled
        isAutomaticQuoteSubstitutionEnabled = behavior.smartPunctuation
        isAutomaticDashSubstitutionEnabled = behavior.smartPunctuation
        // Never, whatever the Mac's keyboard settings say: these rewrite what was typed ("(c)" to ©, a
        // web address to a link), and a note is plain text. A new text view would otherwise follow the system.
        isAutomaticTextReplacementEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
    }

    func caretRectInEditor() -> CGRect? {
        guard let layout = layoutManager, let container = textContainer, let scroll = enclosingScrollView else { return nil }
        let caret = min(selectedRange().location, content.length)
        let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: caret, length: 0), actualCharacterRange: nil)
        var rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
        if caret == content.length, content.length > 0, layout.extraLineFragmentTextContainer != nil { rect = layout.extraLineFragmentRect }
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        var converted = convert(rect, to: scroll)
        if !scroll.isFlipped { converted.origin.y = scroll.bounds.height - converted.maxY }
        return converted
    }

    func updateInsets() {
        var horizontal = minimumInset.width
        if let maxLineWidth, bounds.width > maxLineWidth + minimumInset.width * 2 {
            horizontal = ((bounds.width - maxLineWidth) / 2).rounded(.down)
        }
        let inset = NSSize(width: horizontal, height: minimumInset.height)
        if textContainerInset != inset { textContainerInset = inset }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged { updateInsets() }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, event.type == .keyDown, isEditable {
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            // The key itself, whatever Shift turns it into: ⇧⌘8 arrives as "*" otherwise.
            let key = (event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers)?.lowercased()
            if flags.contains(.command), !flags.contains(.option),
               let shortcut = EditorShortcuts.all.first(where: { $0.key == key && $0.shift == flags.contains(.shift) && $0.control == flags.contains(.control) }) {
                commandHandler?(shortcut.command)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    /// The right-click menu gains a Format group, so formatting is one click from a selection.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)
        guard isEditable, let menu else { return menu }
        let format = NSMenu(title: "Format")
        for (index, entry) in Self.contextCommands.enumerated() {
            let item = NSMenuItem(title: entry.title, action: #selector(runContextCommand(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            format.addItem(item)
        }
        let parent = NSMenuItem(title: "Format", action: nil, keyEquivalent: "")
        parent.submenu = format
        menu.insertItem(parent, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    private static let contextCommands: [(title: String, command: EditorCommand)] = [
        ("Bold", .bold), ("Italic", .italic), ("Underline", .underline), ("Strikethrough", .strikethrough),
        ("Highlight", .highlight), ("Color…", .showColors), ("Clear Formatting", .clearFormatting),
    ]

    @objc private func runContextCommand(_ sender: NSMenuItem) {
        guard Self.contextCommands.indices.contains(sender.tag) else { return }
        commandHandler?(Self.contextCommands[sender.tag].command)
    }

    override func paste(_ sender: Any?) {
        let board = NSPasteboard.general
        if let types = board.types, !types.contains(.string) || types.contains(.png) {
            for (type, fileExtension) in [(NSPasteboard.PasteboardType.png, "png"), (.tiff, "png")] {
                if var data = board.data(forType: type) {
                    if type == .tiff, let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) { data = png }
                    if let link = pasteImageData?(data, fileExtension) {
                        insertText(link, replacementRange: selectedRange())
                        return
                    }
                }
            }
        }
        if let html = board.string(forType: .html), board.string(forType: .string) != nil, html.contains("<") {
            insertText(HTMLToMarkdown.convert(html), replacementRange: selectedRange())
            return
        }
        pasteAsPlainText(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let board = sender.draggingPasteboard
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            var inserted = false
            for url in urls {
                guard let data = try? Data(contentsOf: url), let link = pasteImageData?(data, url.pathExtension) else { continue }
                insertText(link + "\n", replacementRange: selectedRange())
                inserted = true
            }
            if inserted { return true }
        }
        return super.performDragOperation(sender)
    }
}

private struct PlatformEditor: NSViewRepresentable {
    /// The space above the first line of text, inside the scrolling area.
    static func textInsetTop(roomy: Bool) -> CGFloat { roomy ? 26 : 12 }

    @Binding var text: String
    var actions: EditorActions
    var appearance: EditorAppearance
    var behavior: EditorBehavior
    var palette: ThemePalette
    var roomy: Bool
    var isActive: Bool
    var onCompletionQuery: (EditorCompletion?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, actions: actions, appearance: appearance, behavior: behavior, palette: palette, onCompletionQuery: onCompletionQuery)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let stack = makeTextStack()
        let view = PerchTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), textContainer: stack.container)
        view.ownedStorage = stack.storage
        view.autoresizingMask = [.width]
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = view
        view.drawsBackground = false
        view.delegate = coordinator
        view.isRichText = false
        view.allowsUndo = true
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        view.apply(behavior)
        view.maxLineWidth = roomy ? coordinator.styler.maxLineWidth : nil
        view.minimumInset = NSSize(width: roomy ? 28 : 14, height: Self.textInsetTop(roomy: roomy))
        view.typingAttributes = coordinator.styler.typingAttributes
        view.font = coordinator.styler.baseFont
        view.textStorage?.delegate = coordinator
        view.string = text
        view.pasteImageData = actions.pasteImage
        view.registerForDraggedTypes([.fileURL, .string])
        coordinator.bindCommon(view)
        coordinator.applyColors()
        coordinator.restyleEverything()
        view.isEditable = isActive
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            coordinator, selector: #selector(Coordinator.didScroll), name: NSView.boundsDidChangeNotification, object: scroll.contentView
        )
        coordinator.applyInitialPosition()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.text = $text
        coordinator.onCompletionQuery = onCompletionQuery
        guard let view = scroll.documentView as? PerchTextView else { return }
        view.pasteImageData = actions.pasteImage
        coordinator.update(behavior)
        if coordinator.styler.update(appearance, palette: palette) {
            view.maxLineWidth = roomy ? coordinator.styler.maxLineWidth : nil
            coordinator.applyColors()
            view.updateInsets()
            coordinator.restyleEverything()
        }
        coordinator.sync(to: text)
        coordinator.setActive(isActive)
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    @MainActor
    final class Coordinator: EditorCoordinatorBase, NSTextViewDelegate {
        func textDidChange(_ notification: Notification) {
            guard !isApplying else { return }
            contentChanged()
        }

        func textViewDidChangeSelection(_ notification: Notification) { caretMoved() }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            if replacementString == "", handleDeletion(of: range) { return false }
            guard !isApplying, let typed = replacementString, typed.count == 1, typed != "\n", typed != "\t" else { return true }
            return !handleTyped(typed, replacing: range)
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let view = textView as? PerchTextView else { return false }
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                return handleTyped("\n", replacing: view.selectedRange())
            case #selector(NSResponder.insertTab(_:)):
                return handleTyped("\t", replacing: view.selectedRange())
            case #selector(NSResponder.insertBacktab(_:)):
                perform(.outdent)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                return actions.onEscape?() ?? false
            default:
                return false
            }
        }

        @objc func didScroll() {
            guard let onScroll = actions.onScroll, let view else { return }
            onScroll(view.topLine())
        }
    }
}
#else
final class PerchTextView: UITextView {
    var pasteImageData: ((Data, String) -> String?)?
    var ownedStorage: NSTextStorage?
    var commandHandler: ((EditorCommand) -> Void)?
    var escapeHandler: (() -> Bool)?
    var maxLineWidth: CGFloat?
    var minimumInset = UIEdgeInsets(top: 14, left: 12, bottom: 80, right: 12) { didSet { setNeedsLayout() } }

    var content: NSString { textStorage.string as NSString }
    var selection: NSRange {
        get { selectedRange }
        set { selectedRange = newValue }
    }
    var textStorageIfLoaded: NSTextStorage? { textStorage }
    var layoutManagerIfLoaded: NSLayoutManager? { layoutManager }
    var containerIfLoaded: NSTextContainer? { textContainer }

    /// Distance scrolled, in text coordinates.
    var visibleTop: CGFloat {
        get { contentOffset.y + adjustedContentInset.top }
        set {
            layoutIfNeeded()
            let limit = max(contentSize.height + adjustedContentInset.bottom - bounds.height, -adjustedContentInset.top)
            setContentOffset(CGPoint(x: 0, y: min(max(newValue - adjustedContentInset.top, -adjustedContentInset.top), limit)), animated: false)
        }
    }

    func applyEdit(_ edit: TextEdit, reveal: Bool = true) {
        guard NSMaxRange(edit.range) <= content.length,
              let start = position(from: beginningOfDocument, offset: edit.range.location),
              let end = position(from: start, offset: edit.range.length),
              let range = textRange(from: start, to: end) else { return }
        // Going through UITextInput keeps undo working, and makes the change one step to undo.
        let offset = contentOffset
        replace(range, withText: edit.replacement)
        selectedRange = edit.selection.clamped(to: content.length)
        if !reveal { setContentOffset(offset, animated: false) }
    }

    func takeFocus() { becomeFirstResponder() }

    func giveUpFocus() {
        if isFirstResponder { resignFirstResponder() }
    }

    /// The bar above the keyboard never takes the keyboard away, so there is nothing to take back.
    func keepFocus() {}

    var hasKeyboard: Bool { isFirstResponder }
    var focusHandler: ((Bool) -> Void)?

    func revealSelection() { scrollRangeToVisible(selectedRange) }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { focusHandler?(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { focusHandler?(false) }
        return resigned
    }

    var isComposing: Bool { markedTextRange != nil }
    /// A finger can't see under itself anyway, and the keyboard comes up as it lands: tags show at once.
    var isSelectingWithMouse: Bool { false }
    var isMouseDown: Bool { false }
    var isUndoingOrRedoing: Bool { undoManager?.isUndoing == true || undoManager?.isRedoing == true }

    func applyColors(_ colors: EditorColors) {
        // The tint draws both the caret and the selection.
        tintColor = colors.accent
    }

    func redrawBackground() { setNeedsDisplay() }

    /// The row above the keyboard, kept so turning the setting off and on again reuses it.
    var formattingBar: UIView?

    /// Spelling, autocorrect, smart punctuation, capitals and the formatting bar, from the Editing settings.
    func apply(_ behavior: EditorBehavior) {
        spellCheckingType = behavior.spellCheck ? .default : .no
        // On leaves it to the iPhone's own keyboard setting, as the editor always has.
        autocorrectionType = behavior.autocorrect ? .default : .no
        smartQuotesType = behavior.smartPunctuation ? .yes : .no
        smartDashesType = behavior.smartPunctuation ? .yes : .no
        autocapitalizationType = behavior.autocapitalize ? .sentences : .none
        let bar = behavior.formattingBar ? formattingBar : nil
        if inputAccessoryView !== bar { inputAccessoryView = bar }
        // The keyboard only picks these up when it next appears, unless it is asked to look again.
        if isFirstResponder { reloadInputViews() }
    }

    func caretRectInEditor() -> CGRect? {
        guard let position = selectedTextRange?.end else { return nil }
        return caretRect(for: position).offsetBy(dx: -contentOffset.x, dy: -contentOffset.y)
    }

    func updateInsets() {
        var horizontal = minimumInset.left
        if let maxLineWidth, bounds.width > maxLineWidth + minimumInset.left * 2 {
            horizontal = ((bounds.width - maxLineWidth) / 2).rounded(.down)
        }
        let inset = UIEdgeInsets(top: minimumInset.top, left: horizontal, bottom: minimumInset.bottom, right: horizontal)
        if textContainerInset != inset { textContainerInset = inset }
    }

    override func layoutSubviews() {
        updateInsets()
        super.layoutSubviews()
    }

    /// With a keyboard attached, the same shortcuts as the Mac.
    override var keyCommands: [UIKeyCommand]? {
        var commands = EditorShortcuts.all.enumerated().map { index, shortcut in
            var flags: UIKeyModifierFlags = .command
            if shortcut.shift { flags.insert(.shift) }
            if shortcut.control { flags.insert(.control) }
            return UIKeyCommand(action: #selector(keyShortcut(_:)), input: shortcut.key, modifierFlags: flags, propertyList: index)
        }
        commands += [
            UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(keyOutdent)),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(keyEscape)),
        ]
        commands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return commands
    }

    @objc private func keyShortcut(_ sender: UIKeyCommand) {
        guard let index = sender.propertyList as? Int, EditorShortcuts.all.indices.contains(index) else { return }
        commandHandler?(EditorShortcuts.all[index].command)
    }

    @objc private func keyOutdent() { commandHandler?(.outdent) }
    @objc private func keyEscape() { if escapeHandler?() != true { resignFirstResponder() } }

    override func paste(_ sender: Any?) {
        if let image = UIPasteboard.general.image, let data = image.pngData(), let link = pasteImageData?(data, "png") {
            insertText(link)
            return
        }
        if let html = UIPasteboard.general.value(forPasteboardType: "public.html") as? String, html.contains("<") {
            insertText(HTMLToMarkdown.convert(html))
            return
        }
        if let string = UIPasteboard.general.string { insertText(string) }
    }
}

/// The row above the iPhone keyboard. The bar itself is SwiftUI (`KeyboardFormatBar`); this is the frame
/// the keyboard asks for, sized to follow Dynamic Type.
final class EditorAccessoryBar: UIInputView {
    private let host: UIHostingController<AnyView>
    private var height: NSLayoutConstraint?

    init(
        state: FormatState, perform: @escaping (EditorCommand) -> Void, dismiss: @escaping () -> Void,
        customColor: @escaping (String) -> Void
    ) {
        host = UIHostingController(rootView: AnyView(BarTheme(store: ThemeStore.shared) {
            KeyboardFormatBar(state: state, perform: perform, dismiss: dismiss, customColor: customColor)
        }))
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: KeyboardFormatBar.height), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        autoresizingMask = [.flexibleWidth]
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        // The bar sizes itself to this view; it must not add the keyboard's safe area a second time.
        if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
        addSubview(host.view)
        let height = heightAnchor.constraint(equalToConstant: scaledHeight)
        self.height = height
        NSLayoutConstraint.activate([
            height,
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: topAnchor),
            host.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Taller with larger text, but never so tall that it crowds the note.
    private var scaledHeight: CGFloat {
        min(UIFontMetrics(forTextStyle: .body).scaledValue(for: KeyboardFormatBar.height, compatibleWith: traitCollection), 62)
    }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: scaledHeight) }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        guard previous?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else { return }
        height?.constant = scaledHeight
        invalidateIntrinsicContentSize()
    }
}

/// Shows the system color picker for a custom color and reports the choice when it closes.
final class CustomColorPicker: NSObject, UIColorPickerViewControllerDelegate {
    private var finish: ((String?) -> Void)?
    private var changed = false

    func present(from view: UIView, title: String, finish: @escaping (String?) -> Void) {
        guard var top = view.window?.rootViewController else { return finish(nil) }
        while let next = top.presentedViewController { top = next }
        self.finish = finish
        changed = false
        let picker = UIColorPickerViewController()
        picker.title = title
        picker.supportsAlpha = false
        picker.delegate = self
        if let sheet = picker.sheetPresentationController { sheet.detents = [.medium(), .large()] }
        top.present(picker, animated: true)
    }

    func colorPickerViewController(_ viewController: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
        changed = true
    }

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        let color = viewController.selectedColor
        let hex = changed && color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            ? ThemeRGB(red: Double(red), green: Double(green), blue: Double(blue)).hex : nil
        finish?(hex)
        finish = nil
    }
}

private struct PlatformEditor: UIViewRepresentable {
    /// The space above the first line of text, inside the scrolling area.
    static func textInsetTop(roomy: Bool) -> CGFloat { roomy ? 18 : 12 }

    @Binding var text: String
    var actions: EditorActions
    var appearance: EditorAppearance
    var behavior: EditorBehavior
    var palette: ThemePalette
    var roomy: Bool
    var isActive: Bool
    var onCompletionQuery: (EditorCompletion?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, actions: actions, appearance: appearance, behavior: behavior, palette: palette, onCompletionQuery: onCompletionQuery)
    }

    func makeUIView(context: Context) -> PerchTextView {
        let coordinator = context.coordinator
        let stack = makeTextStack()
        let view = PerchTextView(frame: .zero, textContainer: stack.container)
        view.ownedStorage = stack.storage
        view.delegate = coordinator
        view.backgroundColor = .clear
        view.alwaysBounceVertical = true
        view.adjustsFontForContentSizeCategory = false
        view.maxLineWidth = roomy ? coordinator.styler.maxLineWidth : nil
        view.minimumInset = roomy
            ? UIEdgeInsets(top: Self.textInsetTop(roomy: true), left: 16, bottom: 120, right: 16)
            : UIEdgeInsets(top: Self.textInsetTop(roomy: false), left: 10, bottom: 40, right: 10)
        view.font = coordinator.styler.baseFont
        view.typingAttributes = coordinator.styler.typingAttributes
        view.textStorage.delegate = coordinator
        view.text = text
        view.pasteImageData = actions.pasteImage
        view.isEditable = isActive
        view.keyboardDismissMode = .interactive
        view.formattingBar = EditorAccessoryBar(
            state: actions.format,
            perform: { [weak coordinator] in coordinator?.perform($0) },
            dismiss: { [weak view] in view?.resignFirstResponder() },
            customColor: { [weak coordinator] in coordinator?.pickCustomColor(mode: $0) }
        )
        view.apply(behavior)
        coordinator.bindCommon(view)
        coordinator.applyColors()
        coordinator.restyleEverything()
        coordinator.applyInitialPosition()
        return view
    }

    func updateUIView(_ view: PerchTextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.text = $text
        coordinator.onCompletionQuery = onCompletionQuery
        view.pasteImageData = actions.pasteImage
        coordinator.update(behavior)
        if coordinator.styler.update(appearance, palette: palette) {
            view.maxLineWidth = roomy ? coordinator.styler.maxLineWidth : nil
            coordinator.applyColors()
            view.setNeedsLayout()
            coordinator.restyleEverything()
        }
        coordinator.sync(to: text)
        coordinator.setActive(isActive)
    }

    @MainActor
    final class Coordinator: EditorCoordinatorBase, UITextViewDelegate {
        func textViewDidChange(_ textView: UITextView) {
            guard !isApplying else { return }
            contentChanged()
            // UIKit carries the last character's look forward; keep new text plain until it is styled.
            textView.typingAttributes = styler.typingAttributes
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text.isEmpty, handleDeletion(of: range) { return false }
            guard !isApplying, text.count == 1 else { return true }
            return !handleTyped(text, replacing: range)
        }

        func textViewDidChangeSelection(_ textView: UITextView) { caretMoved() }

        /// Adds a Format group to the menu that appears over selected text.
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0, textView.isEditable else { return nil }
            func action(_ title: String, _ symbol: String, _ command: EditorCommand) -> UIAction {
                UIAction(title: title, image: UIImage(systemName: symbol)) { [weak self] _ in self?.perform(command) }
            }
            let format = UIMenu(title: "Format", image: UIImage(systemName: "textformat"), children: [
                action("Bold", "bold", .bold), action("Italic", "italic", .italic), action("Underline", "underline", .underline),
                action("Highlight", "highlighter", .highlight), action("Color…", "paintpalette", .showColors),
                action("Clear Formatting", "eraser", .clearFormatting),
            ])
            return UIMenu(children: suggestedActions + [format])
        }

        private let colorPicker = CustomColorPicker()

        /// A custom color needs the system picker, which takes the keyboard. The selection is kept and
        /// the keyboard brought back once a color is chosen.
        func pickCustomColor(mode: String) {
            guard let view else { return }
            let selection = view.selection
            colorPicker.present(from: view, title: mode == PaletteMode.highlight.rawValue ? "Highlight Color" : "Text Color") { [weak self, weak view] hex in
                guard let self, let view else { return }
                view.takeFocus()
                view.selection = selection.clamped(to: view.content.length)
                guard let hex else { return }
                let key = EditingSettings.Key.recentColors
                UserDefaults.standard.set(FormatRecents.adding(hex, to: UserDefaults.standard.string(forKey: key) ?? ""), forKey: key)
                self.perform(mode == PaletteMode.highlight.rawValue ? .highlightColor(hex) : .textColor(hex))
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let onScroll = actions.onScroll, let view else { return }
            onScroll(view.topLine())
        }
    }
}
#endif
