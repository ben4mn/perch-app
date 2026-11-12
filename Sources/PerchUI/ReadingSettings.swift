import PerchKit
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: Choices

/// The faces a note can be read in. All of them ship with macOS and iOS, so nothing is bundled.
public enum ReadingFont: String, CaseIterable, Identifiable, Sendable {
    case system, serif, rounded, mono, charter, iowan, georgia, avenir
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "System"
        case .serif: return "New York"
        case .rounded: return "Rounded"
        case .mono: return "Mono"
        case .charter: return "Charter"
        case .iowan: return "Iowan"
        case .georgia: return "Georgia"
        case .avenir: return "Avenir Next"
        }
    }

    /// The CSS font stack the reader uses.
    public var css: String {
        switch self {
        case .system: return #"-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif"#
        case .serif: return #"ui-serif, "New York", "Iowan Old Style", Georgia, serif"#
        case .rounded: return #"ui-rounded, "SF Pro Rounded", -apple-system, sans-serif"#
        case .mono: return #"ui-monospace, "SF Mono", SFMono-Regular, Menlo, monospace"#
        case .charter: return #"Charter, "Bitstream Charter", "Iowan Old Style", Georgia, serif"#
        case .iowan: return #""Iowan Old Style", Palatino, Georgia, serif"#
        case .georgia: return #"Georgia, "Times New Roman", serif"#
        case .avenir: return #""Avenir Next", Avenir, -apple-system, sans-serif"#
        }
    }

    var familyName: String? {
        switch self {
        case .charter: return "Charter"
        case .iowan: return "Iowan Old Style"
        case .georgia: return "Georgia"
        case .avenir: return "Avenir Next"
        default: return nil
        }
    }

    /// The same face for SwiftUI text, used to preview the choice.
    public func font(size: CGFloat) -> Font {
        switch self {
        case .system: return .system(size: size)
        case .serif: return .system(size: size, design: .serif)
        case .rounded: return .system(size: size, design: .rounded)
        case .mono: return .system(size: size, design: .monospaced)
        default: return .custom(familyName ?? "", size: size)
        }
    }

    /// The same face for the native editor.
    func platformFont(size: CGFloat) -> PlatformFont {
        switch self {
        case .system: return .systemFont(ofSize: size)
        case .mono: return .monospacedSystemFont(ofSize: size, weight: .regular)
        case .serif, .rounded:
            let base = PlatformFont.systemFont(ofSize: size)
            #if os(macOS)
            let descriptor = base.fontDescriptor.withDesign(self == .serif ? .serif : .rounded)
            return descriptor.flatMap { NSFont(descriptor: $0, size: size) } ?? base
            #else
            let descriptor = base.fontDescriptor.withDesign(self == .serif ? .serif : .rounded)
            return descriptor.map { UIFont(descriptor: $0, size: size) } ?? base
            #endif
        default:
            return PlatformFont(name: familyName ?? "", size: size) ?? .systemFont(ofSize: size)
        }
    }
}

public enum ReadingLineSpacing: String, CaseIterable, Identifiable, Sendable {
    case compact, comfortable, relaxed
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    /// CSS line-height for the reader.
    public var lineHeight: Double {
        switch self {
        case .compact: return 1.45
        case .comfortable: return 1.65
        case .relaxed: return 1.9
        }
    }
    /// Extra space between editor lines, as a share of the font size.
    var editorSpacing: CGFloat {
        switch self {
        case .compact: return 0.22
        case .comfortable: return 0.4
        case .relaxed: return 0.6
        }
    }
}

public enum ReadingLineWidth: String, CaseIterable, Identifiable, Sendable {
    case narrow, medium, wide, full
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    /// Characters per line, or nil for the whole width.
    public var characters: Int? {
        switch self {
        case .narrow: return 56
        case .medium: return 68
        case .wide: return 84
        case .full: return nil
        }
    }
    /// The CSS measure.
    public var measure: String { characters.map { "\($0)ch" } ?? "none" }
}

public enum EditorFontChoice: String, CaseIterable, Identifiable, Sendable {
    case mono, system, reader
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .mono: return "Mono"
        case .system: return "System"
        case .reader: return "Match reader"
        }
    }
}

public enum PreviewSide: String, CaseIterable, Identifiable, Sendable {
    case left, right
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public enum NoteOpenMode: String, CaseIterable, Identifiable, Sendable {
    case read, edit
    public var id: String { rawValue }
    public var title: String { self == .read ? "Reading" : "Editing" }
}

// MARK: Stored settings

/// How notes read, saved on this device and shared by the Mac and iPhone apps. Nothing here is written
/// to a note. Use as a plain property in a view: `private var reading = ReadingSettings()`.
/// The editor's own choices are in `EditingSettings`.
public struct ReadingSettings: DynamicProperty {
    /// The storage keys, for anything that needs to read or set them outside a view.
    public enum Key {
        public static let font = "readingFont"
        public static let textSize = "readingTextSize"
        public static let lineSpacing = "readingLineSpacing"
        public static let lineWidth = "readingLineWidth"
        public static let justify = "readingJustify"
        /// "tight", "normal" or "relaxed".
        public static let paragraphSpacing = "readingParagraphSpacing"
        /// "same", "serif" or "rounded".
        public static let headingFont = "readingHeadingFont"
        /// "scroll" or "wrap".
        public static let codeWrap = "readingCodeWrap"
        /// "smaller" or "same".
        public static let codeTextSize = "readingCodeTextSize"
        /// "automatic", "hidden", "collapsed" or "expanded".
        public static let properties = "readingProperties"
        public static let hyphenate = "readingHyphenate"
        public static let underlineLinks = "readingUnderlineLinks"
        /// "fit" or "full".
        public static let imageWidth = "readingImageWidth"
        public static let showOutline = "noteShowOutline"
        public static let splitFraction = "noteSplitFraction"

        // The editor's keys, kept here under their old names for anything that already uses them.
        public static let editorFont = EditingSettings.Key.font
        public static let editorTextSize = EditingSettings.Key.textSize
        public static let openIn = EditingSettings.Key.openIn
        public static let editWithPreview = EditingSettings.Key.editWithPreview
        public static let previewSide = EditingSettings.Key.previewSide

        /// Every reading key, for Reset to defaults.
        public static let all = [
            font, textSize, lineSpacing, lineWidth, justify, paragraphSpacing, headingFont, codeWrap, codeTextSize,
            properties, hyphenate, underlineLinks, imageWidth, showOutline,
        ]
    }

    @AppStorage(Key.font) public var font = ReadingFont.system
    /// Steps away from the default size; 0 is the default.
    @AppStorage(Key.textSize) public var textSize = 0
    @AppStorage(Key.lineSpacing) public var lineSpacing = ReadingLineSpacing.comfortable
    @AppStorage(Key.lineWidth) public var lineWidth = ReadingLineWidth.medium
    @AppStorage(Key.justify) public var justify = false
    @AppStorage(Key.paragraphSpacing) public var paragraphSpacing = ParagraphSpacing.normal
    @AppStorage(Key.headingFont) public var headingFont = HeadingFont.same
    @AppStorage(Key.codeWrap) public var codeWrap = CodeWrap.scroll
    @AppStorage(Key.codeTextSize) public var codeTextSize = CodeTextSize.smaller
    @AppStorage(Key.properties) public var properties = PropertiesDisplay.automatic
    @AppStorage(Key.hyphenate) public var hyphenate = false
    @AppStorage(Key.underlineLinks) public var underlineLinks = true
    @AppStorage(Key.imageWidth) public var imageWidth = ImageWidth.fit
    @AppStorage(Key.showOutline) public var showOutline = false

    // The editor's choices, still readable from here. `EditingSettings` is their home.
    @AppStorage(Key.editorFont) public var editorFont = EditorFontChoice.mono
    @AppStorage(Key.editorTextSize) public var editorTextSize = 0
    @AppStorage(Key.openIn) public var openIn = NoteOpenMode.read
    @AppStorage(Key.editWithPreview) public var editWithPreview = true
    @AppStorage(Key.previewSide) public var previewSide = PreviewSide.right

    public init() {}

    static let readingSizes: [Double] = [12, 13, 14, 15, 16, 17, 18, 20, 22, 24, 28]
    static let editorSizes: [Double] = [11, 12, 13, 14, 15, 16, 17, 18, 20, 22, 24]
    #if os(macOS)
    static let readingBase = 4, editorBase = 3
    #else
    static let readingBase = 5, editorBase = 5
    #endif

    public static let textSizeRange = -readingBase...(readingSizes.count - 1 - readingBase)
    public static let editorTextSizeRange = -editorBase...(editorSizes.count - 1 - editorBase)

    /// Reader text size in CSS pixels.
    public var readingPointSize: Double {
        Self.readingSizes[min(max(Self.readingBase + textSize, 0), Self.readingSizes.count - 1)]
    }

    /// Editor text size in points.
    public var editorPointSize: Double {
        Self.editorSizes[min(max(Self.editorBase + editorTextSize, 0), Self.editorSizes.count - 1)]
    }

    public func stepTextSize(_ delta: Int) {
        textSize = min(max(textSize + delta, Self.textSizeRange.lowerBound), Self.textSizeRange.upperBound)
    }

    public func stepEditorTextSize(_ delta: Int) {
        editorTextSize = min(max(editorTextSize + delta, Self.editorTextSizeRange.lowerBound), Self.editorTextSizeRange.upperBound)
    }

    /// The reading choices beyond font and size.
    public var style: ReaderStyle {
        ReaderStyle(
            paragraphSpacing: paragraphSpacing, headingFont: headingFont, codeWrap: codeWrap, codeTextSize: codeTextSize,
            properties: properties, hyphenate: hyphenate, justify: justify, underlineLinks: underlineLinks, imageWidth: imageWidth
        )
    }

    /// What the reader should look like right now.
    public var appearance: ReadingAppearance {
        ReadingAppearance(font: font, size: readingPointSize, lineHeight: lineSpacing.lineHeight, measure: lineWidth.measure, justify: justify, style: style)
    }

    public var isDefault: Bool {
        appearance == ReadingAppearance.standard && textSize == 0 && !showOutline
    }

    /// Back to how Perch ships. Removes the saved values instead of writing defaults over them.
    public func reset() {
        font = .system
        textSize = 0
        lineSpacing = .comfortable
        lineWidth = .medium
        justify = false
        paragraphSpacing = .normal
        headingFont = .same
        codeWrap = .scroll
        codeTextSize = .smaller
        properties = .automatic
        hyphenate = false
        underlineLinks = true
        imageWidth = .fit
        showOutline = false
        SettingsReset.remove(Key.all)
    }
}

/// The reader's look, ready to hand to the web page.
public struct ReadingAppearance: Equatable, Sendable {
    public var font: ReadingFont
    public var size: Double
    public var lineHeight: Double
    public var measure: String
    public var justify: Bool
    public var style: ReaderStyle

    public init(font: ReadingFont, size: Double, lineHeight: Double, measure: String, justify: Bool, style: ReaderStyle = .standard) {
        self.font = font
        self.size = size
        self.lineHeight = lineHeight
        self.measure = measure
        self.justify = justify
        self.style = style
    }

    /// The reader as it ships.
    public static var standard: ReadingAppearance {
        ReadingAppearance(
            font: .system, size: ReadingSettings.readingSizes[ReadingSettings.readingBase],
            lineHeight: ReadingLineSpacing.comfortable.lineHeight, measure: ReadingLineWidth.medium.measure, justify: false
        )
    }

    /// The argument for `Perch.setAppearance` in the render page. `style` and `attributes` carry the
    /// newer reading settings; the page applies them without drawing the note again.
    public var payload: [String: Any] {
        [
            "fontBody": font.css, "fontSize": size, "lineHeight": lineHeight, "measure": measure, "justify": justify,
            "style": style.cssVariables, "attributes": style.attributes,
        ]
    }
}

// MARK: Views

/// − / size / + with a reset, used for both the reader and the editor.
struct TextSizeStepper: View {
    /// Read so this is drawn again when the interface size or density changes.
    @Environment(\.perchDisplay) private var display
    var size: Double
    var step: Int
    var range: ClosedRange<Int>
    var change: (Int) -> Void
    var reset: () -> Void

    var body: some View {
        let _ = display
        HStack(spacing: 6) {
            Button { change(-1) } label: { Image(systemName: "textformat.size.smaller").frame(width: 26, height: 20) }
                .disabled(step <= range.lowerBound)
                .accessibilityLabel("Smaller text")
            Text("\(Int(size))")
                .font(.perchStyle(.callout).weight(.medium).monospacedDigit())
                .frame(minWidth: 24)
                .contentTransition(.numericText())
                .motion(Motion.quick, value: size)
                .accessibilityLabel("Text size \(Int(size))")
            Button { change(1) } label: { Image(systemName: "textformat.size.larger").frame(width: 26, height: 20) }
                .disabled(step >= range.upperBound)
                .accessibilityLabel("Larger text")
            Button("Reset", action: reset)
                .disabled(step == 0)
                .font(.perchStyle(.callout))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

/// The compact "Aa" panel inside a note. Changes apply to the open note as they are made.
struct ReadingQuickSettings: View {
    var showsEditor: Bool
    private var reading = ReadingSettings()
    @Environment(\.perchTheme) private var theme
    /// The sample letters grow with the system text size on iPhone.
    @ScaledMetric(relativeTo: .body) private var sampleSize: CGFloat = 19

    init(showsEditor: Bool) { self.showsEditor = showsEditor }

    private let columns = [GridItem(.adaptive(minimum: 68), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                group("Font") {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(ReadingFont.allCases) { face in fontChip(face) }
                    }
                }
                group("Size") {
                    TextSizeStepper(
                        size: reading.readingPointSize, step: reading.textSize, range: ReadingSettings.textSizeRange,
                        change: reading.stepTextSize, reset: { reading.textSize = 0 }
                    )
                }
                group("Line spacing") {
                    Picker("Line spacing", selection: reading.$lineSpacing) {
                        ForEach(ReadingLineSpacing.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                group("Line width") {
                    Picker("Line width", selection: reading.$lineWidth) {
                        ForEach(ReadingLineWidth.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                if showsEditor {
                    Divider()
                    group("Editor") {
                        Picker("Editor font", selection: reading.$editorFont) {
                            ForEach(EditorFontChoice.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden()
                        TextSizeStepper(
                            size: reading.editorPointSize, step: reading.editorTextSize, range: ReadingSettings.editorTextSizeRange,
                            change: reading.stepEditorTextSize, reset: { reading.editorTextSize = 0 }
                        )
                    }
                }
                Divider()
                // Everything else lives in Settings: this panel is for the changes made mid-read.
                MoreSettingsLink(pane: showsEditor ? .editing : .reading)
            }
            .padding(16)
        }
        #if os(macOS)
        .frame(width: 330)
        .frame(maxHeight: 560)
        #endif
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased()).font(.perchStyle(.caption2).weight(.semibold)).foregroundStyle(theme.textSecondary).kerning(0.4)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func fontChip(_ face: ReadingFont) -> some View {
        let selected = reading.font == face
        return Button {
            reading.font = face
        } label: {
            VStack(spacing: 2) {
                Text("Aa").font(face.font(size: sampleSize))
                Text(face.title).font(.perchStyle(.caption2)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.vertical, 2)
            .foregroundStyle(selected ? theme.accent : theme.text)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(selected ? theme.accentSoft : theme.text.opacity(0.06))
            )
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? theme.accent.opacity(0.6) : .clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .motion(Motion.quick, value: selected)
        .accessibilityLabel(face.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
