import PerchKit
import SwiftUI

/// What is in force at the caret, for format bars to show. Kept apart from `EditorActions` so that moving
/// the caret redraws a bar and nothing else.
@MainActor
public final class FormatState: ObservableObject {
    @Published public var active = ActiveFormats()
    /// Counts up each time the color palette is asked for from the keyboard (⌘⇧C).
    @Published var paletteRequests = 0
    /// How many bars are showing. With none, nobody needs to know what is at the caret.
    var watchers = 0 {
        didSet { if watchers > oldValue { refresh() } }
    }
    /// Asks the editor to say what is at the caret now.
    var refresh: () -> Void = {}

    public init() {}
}

/// The colors used most recently, newest first, saved as one comma-separated setting.
enum FormatRecents {
    static let limit = 6

    static func list(_ stored: String) -> [String] {
        var seen = Set<String>()
        return stored.split(separator: ",").compactMap { FormatPalette.normalizedHex(String($0)) }.filter { seen.insert($0).inserted }
    }

    static func adding(_ hex: String, to stored: String) -> String {
        guard let color = FormatPalette.normalizedHex(hex) else { return stored }
        return ([color] + list(stored).filter { $0 != color }).prefix(limit).joined(separator: ",")
    }
}

enum PaletteMode: String, Identifiable {
    case text, highlight
    var id: String { rawValue }
    var title: String { self == .text ? "Text color" : "Highlight" }
}

/// What a format button shows.
enum FormatGlyph: Equatable {
    case symbol(String)
    case label(String, mono: Bool = false)
    /// A letter A over a bar in the current text color.
    case textColor(String?)
    /// A highlighter over a bar in the current highlight color.
    case highlight(String?)
}

/// How big format controls are: compact for a Mac pointer, finger-sized above the iPhone keyboard.
struct FormatControlSize: Equatable {
    var touch: Bool

    /// A finger needs 44 points each way; the lit background is drawn a little inside that.
    @MainActor var width: CGFloat { touch ? 44 : Metrics.scaled(27) }
    @MainActor var height: CGFloat { touch ? 44 : Metrics.scaled(24) }
    var inset: CGFloat { touch ? 2 : 0 }
    var font: Font { touch ? .system(.body).weight(.medium) : .perchFixed(size: 13, weight: .medium) }
    var smallFont: Font { touch ? .system(.footnote).weight(.semibold) : .perchFixed(size: 11.5, weight: .semibold) }
}

/// One button in a format bar. Shows whether its format is on, and says so to VoiceOver.
struct FormatButton: View {
    var glyph: FormatGlyph
    var label: String
    /// The keyboard shortcut, for the tooltip.
    var keys: String?
    var isOn = false
    var size: FormatControlSize
    var action: () -> Void
    @Environment(\.perchTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            FormatGlyphView(glyph: glyph, size: size)
                .frame(minWidth: size.width, minHeight: size.height)
                .padding(.horizontal, isWide ? 5 : 0)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn ? theme.accent : theme.text.opacity(0.86))
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(isOn ? theme.accentSoft : (hovering ? theme.wash : Color.clear)).padding(size.inset))
        .onHover { hovering = $0 }
        .motion(Motion.quick, value: hovering)
        .motion(Motion.quick, value: isOn)
        #if os(macOS)
        // A click must leave the keyboard with the text.
        .focusable(false)
        .help(keys.map { "\(label) (\($0))" } ?? label)
        #endif
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var isWide: Bool {
        if case let .label(text, _) = glyph { return text.count > 2 }
        return false
    }
}

struct FormatGlyphView: View {
    var glyph: FormatGlyph
    var size: FormatControlSize
    @Environment(\.perchTheme) private var theme

    var body: some View {
        switch glyph {
        case let .symbol(name):
            Image(systemName: name).font(size.font)
        case let .label(text, mono):
            Text(text).font(mono ? size.smallFont.monospaced() : size.smallFont).lineLimit(1).fixedSize()
        case let .textColor(hex):
            VStack(spacing: 1.5) {
                Text("A").font(size.smallFont)
                bar(hex.flatMap { Color(hex: $0) } ?? theme.text)
            }
        case let .highlight(hex):
            VStack(spacing: 1.5) {
                Image(systemName: "highlighter").font(size.smallFont)
                bar(hex.map { $0.isEmpty ? theme.warning : (Color(hex: $0) ?? theme.warning) } ?? theme.warning.opacity(0.75))
            }
        }
    }

    private func bar(_ color: Color) -> some View {
        Capsule().fill(color).frame(width: size.touch ? 18 : 14, height: size.touch ? 3.5 : 3)
    }
}

/// A thin line between groups of buttons.
private struct FormatDivider: View {
    var touch = false
    @Environment(\.perchTheme) private var theme

    var body: some View {
        Rectangle().fill(theme.border).frame(width: 1, height: touch ? 22 : 15).padding(.horizontal, touch ? 5 : 4)
            .accessibilityHidden(true)
    }
}

// MARK: - Color palette

/// One color to pick. A ring marks the one in use.
private struct SwatchButton: View {
    var hex: String
    var name: String
    var isOn: Bool
    var diameter: CGFloat
    /// The least room the button takes, for fingers: the circle stays `diameter` across inside it.
    var target: CGFloat = 0
    var action: () -> Void
    @Environment(\.perchTheme) private var theme

    var body: some View {
        Button(action: action) {
            Circle().fill(Color(hex: hex) ?? .gray)
                .frame(width: diameter, height: diameter)
                .overlay(Circle().strokeBorder(theme.text.opacity(0.14), lineWidth: 1))
                .overlay {
                    if isOn { Image(systemName: "checkmark").font(.system(size: diameter * 0.46, weight: .bold)).foregroundStyle(.white) }
                }
                .padding(3)
                .overlay(Circle().strokeBorder(isOn ? theme.accent : Color.clear, lineWidth: 2))
                .frame(minWidth: target, minHeight: target)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .focusable(false)
        .help(name)
        #endif
        .accessibilityLabel(name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The Mac's color popover: the ten palette colors, recent colors, a custom color, and a way back to none.
struct ColorPalette: View {
    var mode: PaletteMode
    /// The color in use: nil for none, empty for the plain yellow highlight.
    var current: String?
    /// Nil removes the color; an empty highlight is the plain yellow one.
    var pick: (String?) -> Void
    @AppStorage(EditingSettings.Key.recentColors) private var recents = ""
    @State private var custom = Color(hex: "#3B82D9") ?? .blue
    @State private var hexText = ""
    @Environment(\.perchTheme) private var theme

    private var recentColors: [String] { FormatRecents.list(recents) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(mode.title).font(.perchHeading).foregroundStyle(theme.text).accessibilityAddTraits(.isHeader)
            HStack(spacing: 6) {
                choice(mode == .text ? "Automatic" : "None", symbol: mode == .text ? "circle.lefthalf.filled" : "circle.slash", isOn: current == nil) { pick(nil) }
                if mode == .highlight {
                    choice("Yellow", symbol: "highlighter", isOn: current == "") { pick("") }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 4), count: 5), spacing: 4) {
                ForEach(FormatPalette.colors) { swatch in
                    SwatchButton(hex: swatch.hex, name: swatch.name, isOn: current == swatch.hex, diameter: 24) { pick(swatch.hex) }
                }
            }
            if !recentColors.isEmpty {
                Text("RECENT").font(.perchEyebrow).kerning(0.4).foregroundStyle(theme.textMuted).accessibilityAddTraits(.isHeader)
                HStack(spacing: 4) {
                    ForEach(recentColors, id: \.self) { hex in
                        SwatchButton(hex: hex, name: FormatPalette.name(for: hex), isOn: current == hex, diameter: 20) { pick(hex) }
                    }
                }
            }
            Rectangle().fill(theme.border).frame(height: 1)
            HStack(spacing: 6) {
                ColorPicker("Custom color", selection: $custom, supportsOpacity: false).labelsHidden()
                TextField("#RRGGBB", text: $hexText)
                    .textFieldStyle(.roundedBorder)
                    .font(.perchFixed(size: 12, design: .monospaced))
                    .frame(width: 86)
                    .accessibilityLabel("Custom color as hex")
                    .onSubmit(applyCustom)
                Button("Apply", action: applyCustom)
                    .disabled(FormatPalette.normalizedHex(hexText) == nil)
            }
            .onChange(of: custom) { hexText = custom.hexString() }
        }
        .padding(12)
        .frame(width: 216)
        .onAppear {
            if let current, let color = Color(hex: current) {
                custom = color
                hexText = current
            } else {
                hexText = custom.hexString()
            }
        }
    }

    private func applyCustom() {
        if let hex = FormatPalette.normalizedHex(hexText) { pick(hex) }
    }

    private func choice(_ title: String, symbol: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.perchChip)
                .foregroundStyle(isOn ? theme.accent : theme.text)
                .padding(.horizontal, 9)
                .frame(minHeight: Metrics.scaled(24))
                .background(Capsule().fill(isOn ? theme.accentSoft : theme.wash))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .focusable(false)
        #endif
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Mac format bar

/// The format bar above the Mac editor. It stays put rather than floating over a selection: its buttons
/// show what is in force at the caret, it never covers the words being worked on, and block commands
/// (headings, lists, tables) are there with nothing selected.
struct FormatBar: View {
    @ObservedObject var state: FormatState
    var perform: (EditorCommand) -> Void
    @AppStorage(EditingSettings.Key.recentColors) private var recents = ""
    @State private var palette: PaletteMode?
    @Environment(\.perchTheme) private var theme
    /// Read so the bar is drawn again when the interface size changes.
    @Environment(\.perchDisplay) private var display

    private let size = FormatControlSize(touch: false)
    private var active: ActiveFormats { state.active }

    var body: some View {
        let _ = display
        ViewThatFits(in: .horizontal) {
            row(.full)
            row(.folded)
            row(.tight)
            ScrollView(.horizontal, showsIndicators: false) { row(.tight) }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Metrics.scaled(34))
        .background(theme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.border).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Formatting")
        .onAppear { state.watchers += 1 }
        .onDisappear { state.watchers -= 1 }
        .onChange(of: state.paletteRequests) { palette = .text }
    }

    private func button(_ glyph: FormatGlyph, _ label: String, keys: String? = nil, isOn: Bool = false, _ command: EditorCommand) -> FormatButton {
        FormatButton(glyph: glyph, label: label, keys: keys, isOn: isOn, size: size) { perform(command) }
    }

    /// How much of the bar is on show: everything, the common formats with the rest under •••, or (in a
    /// split view's narrow editor) just style, bold, italic, underline and color.
    private enum Fold { case full, folded, tight }

    @ViewBuilder
    private func row(_ fold: Fold) -> some View {
        let full = fold == .full, tight = fold == .tight
        HStack(spacing: 1) {
            styleMenu
            FormatDivider()
            button(.symbol("bold"), "Bold", keys: "⌘B", isOn: active.bold, .bold)
            button(.symbol("italic"), "Italic", keys: "⌘I", isOn: active.italic, .italic)
            button(.symbol("underline"), "Underline", keys: "⌘U", isOn: active.underline, .underline)
            if !tight { button(.symbol("strikethrough"), "Strikethrough", keys: "⇧⌘X", isOn: active.strikethrough, .strikethrough) }
            FormatDivider()
            colorButtons
            if full {
                button(.symbol("textformat.size.smaller"), "Smaller text", keys: "⇧⌘,", .sizeStep(-1))
                button(.symbol("textformat.size.larger"), "Larger text", keys: "⇧⌘.", isOn: active.textSize != nil, .sizeStep(1))
            }
            FormatDivider()
            if !tight {
                button(.symbol("list.bullet"), "Bulleted list", keys: "⇧⌘8", isOn: active.list == .bullet, .bullet)
                button(.symbol("list.number"), "Numbered list", keys: "⇧⌘7", isOn: active.list == .numbered, .numbered)
                button(.symbol("checklist"), "Task list", keys: "⇧⌘9", isOn: active.list == .task, .task)
                if full { quoteMenu }
                FormatDivider()
                button(.symbol("link"), "Link", keys: "⌘K", isOn: active.link, .link)
            }
            if full {
                button(.label("[[ ]]", mono: true), "Link to a note", keys: "⇧⌘K", .wikiLink)
                button(.symbol("chevron.left.forwardslash.chevron.right"), "Code", isOn: active.code, .code)
                codeBlockMenu
                tableMenu
                alignMenu
                FormatDivider()
                button(.symbol("eraser"), "Clear formatting", keys: "⌘\\", .clearFormatting)
            } else {
                moreMenu(tight: tight)
            }
        }
        .fixedSize()
    }

    // MARK: Pieces

    private func menuLabel(_ glyph: FormatGlyph, isOn: Bool = false) -> some View {
        HStack(spacing: 2) {
            FormatGlyphView(glyph: glyph, size: size)
            Image(systemName: "chevron.down").font(.perchFixed(size: 7, weight: .bold)).opacity(0.55)
        }
        .foregroundStyle(isOn ? theme.accent : theme.text.opacity(0.86))
        .padding(.horizontal, 5)
        .frame(minHeight: size.height)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(isOn ? theme.accentSoft : Color.clear))
        .contentShape(Rectangle())
    }

    private var styleName: String {
        active.headingLevel == 0 ? "Body" : "Heading \(active.headingLevel)"
    }

    private var styleMenu: some View {
        Menu {
            styleItems
        } label: {
            menuLabel(.label(styleName), isOn: active.headingLevel > 0).frame(minWidth: Metrics.scaled(74), alignment: .leading)
        }
        .modifier(ChipMenu())
        .help("Text style")
        .accessibilityLabel("Text style")
        .accessibilityValue(styleName)
    }

    @ViewBuilder
    private var styleItems: some View {
        Toggle("Body", isOn: toggle(active.headingLevel == 0, .setHeading(0)))
        ForEach(1...3, id: \.self) { level in
            Toggle("Heading \(level)", isOn: toggle(active.headingLevel == level, .setHeading(level)))
        }
    }

    /// A menu item with a check mark that runs a command when chosen.
    private func toggle(_ isOn: Bool, _ command: EditorCommand) -> Binding<Bool> {
        Binding(get: { isOn }, set: { _ in perform(command) })
    }

    @ViewBuilder
    private var colorButtons: some View {
        HStack(spacing: 0) {
            button(.highlight(active.highlight), "Highlight", keys: "⇧⌘H", isOn: active.highlight != nil, .highlight)
            Button { palette = .highlight } label: {
                Image(systemName: "chevron.down").font(.perchFixed(size: 7, weight: .bold)).opacity(0.55)
                    .frame(width: 11, height: size.height).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .foregroundStyle(theme.text)
            .help("Highlight color")
            .accessibilityLabel("Highlight color")
            .popover(isPresented: paletteBinding(.highlight), arrowEdge: .bottom) { paletteView(.highlight) }
        }
        Button { palette = .text } label: {
            menuLabel(.textColor(active.textColor), isOn: active.textColor != nil)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("Text color (⇧⌘C)")
        .accessibilityLabel("Text color")
        .accessibilityValue(active.textColor.map { FormatPalette.name(for: $0) } ?? "Automatic")
        .popover(isPresented: paletteBinding(.text), arrowEdge: .bottom) { paletteView(.text) }
    }

    private func paletteBinding(_ mode: PaletteMode) -> Binding<Bool> {
        Binding(get: { palette == mode }, set: { if !$0, palette == mode { palette = nil } })
    }

    private func paletteView(_ mode: PaletteMode) -> some View {
        ColorPalette(mode: mode, current: mode == .text ? active.textColor : active.highlight) { hex in
            palette = nil
            if let hex, !hex.isEmpty { recents = FormatRecents.adding(hex, to: recents) }
            perform(mode == .text ? .textColor(hex) : .highlightColor(hex))
        }
        .perchPresented()
    }

    private var quoteMenu: some View {
        Menu { quoteItems } label: { menuLabel(.symbol("text.quote"), isOn: active.quote) }
            .modifier(ChipMenu())
            .help("Quote or callout")
            .accessibilityLabel("Quote or callout")
    }

    @ViewBuilder
    private var quoteItems: some View {
        Toggle("Quote", isOn: toggle(active.quote && active.callout == nil, .quote))
        Divider()
        ForEach(MarkdownFormatting.calloutTypes, id: \.self) { type in
            Toggle("\(type.capitalized) callout", isOn: toggle(active.callout == type, .callout(type)))
        }
        if active.callout != nil {
            Divider()
            Button("Plain Quote") { perform(.callout(nil)) }
        }
    }

    private var codeBlockMenu: some View {
        Menu { codeBlockItems } label: { menuLabel(.symbol("curlybraces"), isOn: active.inCodeBlock) }
            .modifier(ChipMenu())
            .help("Code block")
            .accessibilityLabel("Code block")
    }

    static let languages = [("Plain", ""), ("Swift", "swift"), ("Python", "python"), ("JavaScript", "js"), ("JSON", "json"), ("Shell", "sh"), ("SQL", "sql"), ("Mermaid diagram", "mermaid")]

    @ViewBuilder
    private var codeBlockItems: some View {
        if active.inCodeBlock {
            Button("Remove Code Block") { perform(.codeBlock("")) }
        } else {
            ForEach(Self.languages, id: \.1) { name, language in
                Button(name) { perform(.codeBlock(language)) }
            }
        }
    }

    private var tableMenu: some View {
        Menu { tableItems } label: { menuLabel(.symbol("tablecells"), isOn: active.inTable) }
            .modifier(ChipMenu())
            .help("Table")
            .accessibilityLabel("Table")
    }

    @ViewBuilder
    private var tableItems: some View {
        if active.inTable {
            Button("Add Row Below") { perform(.tableAddRow) }
            Button("Add Column After") { perform(.tableAddColumn) }
            Button("Tidy Table") { perform(.tableTidy) }
                .help("Line the columns up, so the table reads as a table here too (⌃⌘T)")
            Divider()
        }
        ForEach(Self.tableSizes, id: \.title) { size in
            Button(size.title) { perform(.table(rows: size.rows, columns: size.columns)) }
        }
    }

    static let tableSizes: [(title: String, rows: Int, columns: Int)] = [(2, 2), (3, 2), (3, 3), (4, 3), (5, 4)].map {
        ("Insert \($0.1) × \($0.0) Table", $0.0, $0.1)
    }

    private var alignSymbol: String {
        switch active.alignment {
        case "center": return "text.aligncenter"
        case "right": return "text.alignright"
        default: return "text.alignleft"
        }
    }

    private var alignMenu: some View {
        Menu { alignItems } label: { menuLabel(.symbol(alignSymbol), isOn: active.alignment == "center" || active.alignment == "right") }
            .modifier(ChipMenu())
            .help("Alignment")
            .accessibilityLabel("Alignment")
    }

    @ViewBuilder
    private var alignItems: some View {
        let current = active.alignment == "center" || active.alignment == "right" ? active.alignment : nil
        Toggle("Left", isOn: toggle(current == nil, .align(nil)))
        Toggle("Center", isOn: toggle(current == "center", .align("center")))
        Toggle("Right", isOn: toggle(current == "right", .align("right")))
    }

    /// Everything the narrow bar has no room for.
    private func moreMenu(tight: Bool) -> some View {
        Menu {
            if tight {
                Toggle("Strikethrough", isOn: toggle(active.strikethrough, .strikethrough))
                Toggle("Bulleted List", isOn: toggle(active.list == .bullet, .bullet))
                Toggle("Numbered List", isOn: toggle(active.list == .numbered, .numbered))
                Toggle("Task List", isOn: toggle(active.list == .task, .task))
                Toggle("Link", isOn: toggle(active.link, .link))
                Divider()
            }
            Button("Smaller Text") { perform(.sizeStep(-1)) }
            Button("Larger Text") { perform(.sizeStep(1)) }
            Divider()
            Button("Link to a Note") { perform(.wikiLink) }
            Toggle("Code", isOn: toggle(active.code, .code))
            Menu("Code Block") { codeBlockItems }
            Menu("Quote or Callout") { quoteItems }
            Menu("Table") { tableItems }
            Menu("Alignment") { alignItems }
            Button("Divider") { perform(.divider) }
            Divider()
            Button("Clear Formatting") { perform(.clearFormatting) }
        } label: {
            menuLabel(.symbol("ellipsis"))
        }
        .modifier(ChipMenu())
        .help("More formatting")
        .accessibilityLabel("More formatting")
    }
}

// MARK: - iPhone keyboard bar

/// The row above the iPhone keyboard. It has two levels so everything is one or two taps away at the
/// width of a closed folding phone: the main row, and a strip for text style or color that takes its
/// place. Nothing here opens a sheet, so the keyboard and the selection stay where they are.
/// On a wide screen (an open folding phone) the style controls sit in the main row.
public struct KeyboardFormatBar: View {
    @ObservedObject var state: FormatState
    var perform: (EditorCommand) -> Void
    var dismiss: () -> Void
    /// Opens the system color picker; that one does need a sheet.
    var customColor: (PaletteMode) -> Void
    var startingStrip: Strip
    @AppStorage(EditingSettings.Key.recentColors) private var recents = ""
    @State private var strip: Strip = .main
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public enum Strip: Equatable, Sendable { case main, style, textColor, highlightColor }

    /// The bar is this tall at the default text size; it grows with Dynamic Type up to a point.
    public static let height: CGFloat = 46
    static let wideWidth: CGFloat = 640

    private let size = FormatControlSize(touch: true)
    private var active: ActiveFormats { state.active }

    public init(
        state: FormatState, perform: @escaping (EditorCommand) -> Void, dismiss: @escaping () -> Void = {},
        customColor: @escaping (String) -> Void = { _ in }, strip: Strip = .main
    ) {
        self.state = state
        self.perform = perform
        self.dismiss = dismiss
        self.customColor = { customColor($0.rawValue) }
        startingStrip = strip
        _strip = State(initialValue: strip)
    }

    public var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= Self.wideWidth
            HStack(spacing: 0) {
                ZStack {
                    switch strip {
                    case .main: scroller { mainRow(wide: wide) }.transition(.perchSwap(reduceMotion: reduceMotion))
                    case .style: scroller { styleStrip }.transition(.perchSwap(reduceMotion: reduceMotion))
                    case .textColor: scroller { colorStrip(.text) }.transition(.perchSwap(reduceMotion: reduceMotion))
                    case .highlightColor: scroller { colorStrip(.highlight) }.transition(.perchSwap(reduceMotion: reduceMotion))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(theme.border).frame(width: 1).padding(.vertical, 10).accessibilityHidden(true)
                FormatButton(glyph: .symbol("keyboard.chevron.compact.down"), label: "Hide keyboard", size: size, action: dismiss)
                    .padding(.horizontal, 3)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(theme.border).frame(height: 1) }
        // Larger text makes the symbols larger, but the bar must not swallow the screen.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Formatting")
        .onAppear { state.watchers += 1 }
        .onDisappear { state.watchers -= 1 }
        .onChange(of: state.paletteRequests) { show(.textColor) }
    }

    private func show(_ next: Strip) {
        withMotion(Motion.quick, reduceMotion: reduceMotion) { strip = next }
    }

    /// The row scrolls sideways. Its far end fades out, so a button cut off there reads as "more this way".
    private func scroller(@ViewBuilder _ content: () -> some View) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) { content() }.padding(.leading, 4).padding(.trailing, 18)
        }
        .mask {
            HStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 18)
            }
        }
    }

    private func button(_ glyph: FormatGlyph, _ label: String, isOn: Bool = false, _ command: EditorCommand) -> FormatButton {
        FormatButton(glyph: glyph, label: label, isOn: isOn, size: size) { perform(command) }
    }

    private var back: some View {
        FormatButton(glyph: .symbol("chevron.left"), label: "Back to formatting", size: size) { show(.main) }
    }

    @ViewBuilder
    private func mainRow(wide: Bool) -> some View {
        if wide {
            headingButtons
            FormatDivider(touch: true)
        } else {
            FormatButton(glyph: .label("Aa"), label: "Text style, size and alignment", isOn: active.headingLevel > 0 || active.textSize != nil, size: size) { show(.style) }
        }
        button(.symbol("bold"), "Bold", isOn: active.bold, .bold)
        button(.symbol("italic"), "Italic", isOn: active.italic, .italic)
        button(.symbol("underline"), "Underline", isOn: active.underline, .underline)
        if wide { button(.symbol("strikethrough"), "Strikethrough", isOn: active.strikethrough, .strikethrough) }
        button(.highlight(active.highlight), "Highlight", isOn: active.highlight != nil, .highlight)
        FormatButton(glyph: .textColor(active.textColor), label: "Text and highlight color", isOn: active.textColor != nil, size: size) { show(.textColor) }
        if wide {
            button(.symbol("textformat.size.smaller"), "Smaller text", .sizeStep(-1))
            button(.symbol("textformat.size.larger"), "Larger text", isOn: active.textSize != nil, .sizeStep(1))
        }
        FormatDivider(touch: true)
        button(.symbol("list.bullet"), "Bulleted list", isOn: active.list == .bullet, .bullet)
        if wide { button(.symbol("list.number"), "Numbered list", isOn: active.list == .numbered, .numbered) }
        button(.symbol("checklist"), "Task list", isOn: active.list == .task, .task)
        button(.symbol("decrease.indent"), "Outdent", .outdent)
        button(.symbol("increase.indent"), "Indent", .indent)
        FormatDivider(touch: true)
        button(.symbol("link"), "Link", isOn: active.link, .link)
        button(.label("[[ ]]", mono: true), "Link to a note", .wikiLink)
        button(.symbol("arrow.uturn.backward"), "Undo", .undo)
        button(.symbol("arrow.uturn.forward"), "Redo", .redo)
        FormatDivider(touch: true)
        if wide {
            blockButtons
        } else {
            button(.symbol("strikethrough"), "Strikethrough", isOn: active.strikethrough, .strikethrough)
            button(.symbol("list.number"), "Numbered list", isOn: active.list == .numbered, .numbered)
            button(.symbol("chevron.left.forwardslash.chevron.right"), "Code", isOn: active.code, .code)
            button(.symbol("text.quote"), "Quote", isOn: active.quote, .quote)
        }
    }

    @ViewBuilder
    private var headingButtons: some View {
        button(.label("Body"), "Body text", isOn: active.headingLevel == 0, .setHeading(0))
        ForEach(1...3, id: \.self) { level in
            button(.label("H\(level)"), "Heading \(level)", isOn: active.headingLevel == level, .setHeading(level))
        }
    }

    @ViewBuilder
    private var blockButtons: some View {
        button(.symbol("text.aligncenter"), "Center", isOn: active.alignment == "center", .align("center"))
        button(.symbol("text.alignright"), "Align right", isOn: active.alignment == "right", .align("right"))
        button(.symbol("chevron.left.forwardslash.chevron.right"), "Code", isOn: active.code, .code)
        button(.symbol("text.quote"), "Quote", isOn: active.quote && active.callout == nil, .quote)
        button(.symbol("exclamationmark.bubble"), "Note callout", isOn: active.callout != nil, .callout(active.callout == nil ? "note" : nil))
        button(.symbol("curlybraces"), "Code block", isOn: active.inCodeBlock, .codeBlock(""))
        button(.symbol("tablecells"), active.inTable ? "Add table row" : "Table", isOn: active.inTable, active.inTable ? .tableAddRow : .table(rows: 2, columns: 2))
        button(.symbol("minus"), "Divider", .divider)
        button(.symbol("eraser"), "Clear formatting", .clearFormatting)
    }

    @ViewBuilder
    private var styleStrip: some View {
        back
        FormatDivider(touch: true)
        headingButtons
        FormatDivider(touch: true)
        button(.symbol("textformat.size.smaller"), "Smaller text", .sizeStep(-1))
        button(.symbol("textformat.size.larger"), "Larger text", isOn: active.textSize != nil, .sizeStep(1))
        FormatDivider(touch: true)
        blockButtons
    }

    @ViewBuilder
    private func colorStrip(_ mode: PaletteMode) -> some View {
        let current = mode == .text ? active.textColor : active.highlight
        back
        // Text or highlight: the swatches that follow apply to whichever is chosen.
        FormatButton(glyph: .textColor(active.textColor), label: "Text color", isOn: mode == .text, size: size) { show(.textColor) }
        FormatButton(glyph: .highlight(active.highlight), label: "Highlight color", isOn: mode == .highlight, size: size) { show(.highlightColor) }
        FormatDivider(touch: true)
        FormatButton(glyph: .symbol(mode == .text ? "circle.lefthalf.filled" : "circle.slash"), label: mode == .text ? "Automatic color" : "No highlight", isOn: current == nil, size: size) {
            pick(nil, mode)
        }
        ForEach(FormatPalette.colors) { swatch in
            SwatchButton(hex: swatch.hex, name: swatch.name, isOn: current == swatch.hex, diameter: 30, target: 44) { pick(swatch.hex, mode) }
        }
        let recent = FormatRecents.list(recents).filter { hex in !FormatPalette.colors.contains { $0.hex == hex } }
        if !recent.isEmpty {
            FormatDivider(touch: true)
            ForEach(recent, id: \.self) { hex in
                SwatchButton(hex: hex, name: "Recent color \(hex)", isOn: current == hex, diameter: 30, target: 44) { pick(hex, mode) }
            }
        }
        FormatDivider(touch: true)
        FormatButton(glyph: .symbol("eyedropper"), label: "Custom color", size: size) { customColor(mode) }
    }

    private func pick(_ hex: String?, _ mode: PaletteMode) {
        if let hex, !hex.isEmpty { recents = FormatRecents.adding(hex, to: recents) }
        perform(mode == .text ? .textColor(hex) : .highlightColor(hex))
    }
}

/// Gives a bar that lives outside the app's windows (above the keyboard) the theme the app is using.
struct BarTheme<Content: View>: View {
    @ObservedObject var store: ThemeStore
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = store.theme(for: store.preferredColorScheme ?? colorScheme)
        content
            .environment(\.perchTheme, theme)
            .environment(\.colorScheme, theme.colorScheme)
            .tint(theme.accent)
    }
}

// MARK: - Mac menu

/// Where the Format menu sends its commands: the editor that last had the keyboard.
@MainActor
public final class FormatTarget: ObservableObject {
    public static let shared = FormatTarget()
    @Published public private(set) var isAvailable = false
    private weak var actions: EditorActions?

    func focus(_ actions: EditorActions) {
        self.actions = actions
        if !isAvailable { isAvailable = true }
    }

    func blur(_ actions: EditorActions) {
        guard self.actions === actions else { return }
        self.actions = nil
        isAvailable = false
    }

    public func perform(_ command: EditorCommand) { actions?.performIfFocused(command) }
}

#if os(macOS)
/// The Format menu in the Mac's menu bar. The same commands as the format bar, with their shortcuts.
public struct FormatCommands: Commands {
    @ObservedObject private var target = FormatTarget.shared

    public init() {}

    private func item(_ title: String, _ command: EditorCommand) -> Button<Text> {
        Button(title) { target.perform(command) }
    }

    public var body: some Commands {
        CommandMenu("Format") {
            Group {
                item("Bold", .bold).keyboardShortcut("b")
                item("Italic", .italic).keyboardShortcut("i")
                item("Underline", .underline).keyboardShortcut("u")
                item("Strikethrough", .strikethrough).keyboardShortcut("x", modifiers: [.command, .shift])
                item("Highlight", .highlight).keyboardShortcut("h", modifiers: [.command, .shift])
                item("Code", .code)
                Divider()
                Menu("Text Color") {
                    item("Automatic", .textColor(nil))
                    Divider()
                    ForEach(FormatPalette.colors) { swatch in item(swatch.name, .textColor(swatch.hex)) }
                    Divider()
                    item("Show Colors…", .showColors).keyboardShortcut("c", modifiers: [.command, .shift])
                }
                Menu("Highlight Color") {
                    item("None", .highlightColor(nil))
                    item("Yellow", .highlightColor(""))
                    Divider()
                    ForEach(FormatPalette.colors) { swatch in item(swatch.name, .highlightColor(swatch.hex)) }
                }
                item("Larger Text", .sizeStep(1)).keyboardShortcut(".", modifiers: [.command, .shift])
                item("Smaller Text", .sizeStep(-1)).keyboardShortcut(",", modifiers: [.command, .shift])
            }
            .disabled(!target.isAvailable)
            Divider()
            Group {
                // Control with Command: ⌥⌘1 to ⌥⌘6 already switch task views.
                item("Heading 1", .setHeading(1)).keyboardShortcut("1", modifiers: [.command, .control])
                item("Heading 2", .setHeading(2)).keyboardShortcut("2", modifiers: [.command, .control])
                item("Heading 3", .setHeading(3)).keyboardShortcut("3", modifiers: [.command, .control])
                item("Body", .setHeading(0))
                Divider()
                item("Bulleted List", .bullet).keyboardShortcut("8", modifiers: [.command, .shift])
                item("Numbered List", .numbered).keyboardShortcut("7", modifiers: [.command, .shift])
                item("Task List", .task).keyboardShortcut("9", modifiers: [.command, .shift])
                item("Quote", .quote)
                Menu("Callout") {
                    ForEach(MarkdownFormatting.calloutTypes, id: \.self) { type in item(type.capitalized, .callout(type)) }
                    Divider()
                    item("Plain Quote", .callout(nil))
                }
            }
            .disabled(!target.isAvailable)
            Divider()
            Group {
                item("Link", .link).keyboardShortcut("k")
                item("Link to a Note", .wikiLink).keyboardShortcut("k", modifiers: [.command, .shift])
                Menu("Code Block") {
                    ForEach(FormatBar.languages, id: \.1) { name, language in item(name, .codeBlock(language)) }
                }
                Menu("Table") {
                    ForEach(FormatBar.tableSizes, id: \.title) { size in
                        item(size.title, .table(rows: size.rows, columns: size.columns))
                    }
                    Divider()
                    item("Add Row Below", .tableAddRow)
                    item("Add Column After", .tableAddColumn)
                    item("Tidy Table", .tableTidy).keyboardShortcut("t", modifiers: [.command, .control])
                }
                item("Divider", .divider)
                Menu("Alignment") {
                    item("Left", .align(nil))
                    item("Center", .align("center"))
                    item("Right", .align("right"))
                }
                Divider()
                item("Clear Formatting", .clearFormatting).keyboardShortcut("\\")
            }
            .disabled(!target.isAvailable)
        }
    }
}
#endif

// MARK: - For snapshots

#if DEBUG
/// Format controls drawn on their own with a made-up selection, for checking how they look without typing.
public struct FormatGallery: View {
    public enum Piece: String, Sendable { case bar, palette, highlightPalette, keyboard, keyboardStyle, keyboardColor }
    var piece: Piece
    @StateObject private var state = FormatState()
    @Environment(\.perchTheme) private var theme

    public init(_ piece: Piece) { self.piece = piece }

    public var body: some View {
        VStack(spacing: 0) {
            switch piece {
            case .bar:
                FormatBar(state: state, perform: { _ in })
                sample
            case .palette:
                ColorPalette(mode: .text, current: "#3B82D9") { _ in }.background(theme.surface)
            case .highlightPalette:
                ColorPalette(mode: .highlight, current: "") { _ in }.background(theme.surface)
            case .keyboard, .keyboardStyle, .keyboardColor:
                sample
                KeyboardFormatBar(
                    state: state, perform: { _ in },
                    strip: piece == .keyboard ? .main : (piece == .keyboardStyle ? .style : .textColor)
                )
                .frame(height: KeyboardFormatBar.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.background)
        .onAppear {
            var active = ActiveFormats()
            active.bold = true
            active.headingLevel = 2
            active.textColor = "#3B82D9"
            active.list = .bullet
            state.active = active
        }
    }

    private var sample: some View {
        Text("The bar is showing a bold, blue, second-level heading in a bulleted list.")
            .font(.perchCaption).foregroundStyle(theme.textSecondary)
            .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
#endif
