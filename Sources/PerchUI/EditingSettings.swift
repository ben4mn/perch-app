import PerchKit
import SwiftUI

/// How strongly the editor shows Markdown's own marks: `#`, `**`, `>` and the like.
public enum EditorMarks: String, CaseIterable, Identifiable, Sendable {
    case dimmed, full
    public var id: String { rawValue }
    public var title: String { self == .dimmed ? "Dimmed" : "Full strength" }
}

/// How the editor looks and behaves, saved on this device and shared by the Mac and iPhone apps.
/// Nothing here is written to a note. Use as a plain property in a view: `private var editing = EditingSettings()`.
public struct EditingSettings: DynamicProperty {
    public enum Key {
        public static let font = "editorFont"
        public static let textSize = "editorTextSize"
        public static let openIn = "noteOpenIn"
        public static let editWithPreview = "noteEditWithPreview"
        public static let previewSide = "notePreviewSide"
        /// "compact", "comfortable" or "relaxed".
        public static let lineSpacing = "editorLineSpacing"
        /// "narrow", "medium", "wide" or "full".
        public static let lineWidth = "editorLineWidth"
        /// "dimmed" or "full".
        public static let marks = "editorMarks"
        public static let highlightLine = "editorHighlightLine"
        public static let continueLists = "editorContinueLists"
        public static let tabIndents = "editorTabIndents"
        public static let wrapSelection = "editorWrapSelection"
        /// "2", "4" or "tab".
        public static let indent = "editorIndent"
        public static let spellCheck = "editorSpellCheck"
        public static let autocorrect = "editorAutocorrect"
        public static let smartPunctuation = "editorSmartPunctuation"
        /// iPhone only.
        public static let autocapitalize = "editorAutocapitalize"
        /// The format bar: above the keyboard on the iPhone, above the editor on the Mac.
        public static let formattingBar = "editorFormattingBar"
        public static let syncPreviewScroll = "noteSyncPreviewScroll"
        /// HTML formatting tags are hidden except on the line being edited.
        public static let hideTags = "editorHideFormatTags"
        /// The colors used most recently, newest first: `#RRGGBB` separated by commas.
        public static let recentColors = "editorRecentColors"

        public static let all = [
            font, textSize, openIn, editWithPreview, previewSide, lineSpacing, lineWidth, marks, highlightLine,
            continueLists, tabIndents, wrapSelection, indent, spellCheck, autocorrect, smartPunctuation,
            autocapitalize, formattingBar, syncPreviewScroll, hideTags, recentColors,
        ]
    }

    /// The Mac editor has never underlined misspellings; the iPhone's always has. Each keeps that until asked.
    public static var spellCheckDefault: Bool {
        #if os(macOS)
        false
        #else
        true
        #endif
    }

    @AppStorage(Key.font) public var font = EditorFontChoice.mono
    /// Steps away from the default size; 0 is the default.
    @AppStorage(Key.textSize) public var textSize = 0
    @AppStorage(Key.openIn) public var openIn = NoteOpenMode.read
    @AppStorage(Key.editWithPreview) public var editWithPreview = true
    @AppStorage(Key.previewSide) public var previewSide = PreviewSide.right
    @AppStorage(Key.lineSpacing) public var lineSpacing = ReadingLineSpacing.comfortable
    @AppStorage(Key.lineWidth) public var lineWidth = ReadingLineWidth.medium
    @AppStorage(Key.marks) public var marks = EditorMarks.dimmed
    @AppStorage(Key.highlightLine) public var highlightLine = false
    @AppStorage(Key.continueLists) public var continueLists = true
    @AppStorage(Key.tabIndents) public var tabIndents = true
    @AppStorage(Key.wrapSelection) public var wrapSelection = true
    @AppStorage(Key.indent) public var indent = MarkdownEditing.IndentStyle.fourSpaces
    @AppStorage(Key.spellCheck) public var spellCheck = EditingSettings.spellCheckDefault
    /// On leaves autocorrect to the system's own keyboard setting; off turns it off in the editor.
    @AppStorage(Key.autocorrect) public var autocorrect = true
    @AppStorage(Key.smartPunctuation) public var smartPunctuation = false
    @AppStorage(Key.autocapitalize) public var autocapitalize = true
    @AppStorage(Key.formattingBar) public var formattingBar = true
    @AppStorage(Key.syncPreviewScroll) public var syncPreviewScroll = true
    @AppStorage(Key.hideTags) public var hideTags = true
    @AppStorage(Key.recentColors) public var recentColors = ""

    public init() {}

    /// Editor text size in points.
    public var pointSize: Double {
        ReadingSettings.editorSizes[min(max(ReadingSettings.editorBase + textSize, 0), ReadingSettings.editorSizes.count - 1)]
    }

    public func stepTextSize(_ delta: Int) {
        let range = ReadingSettings.editorTextSizeRange
        textSize = min(max(textSize + delta, range.lowerBound), range.upperBound)
    }

    /// What the editor should look like right now. "Match reader" needs to know the reader's font.
    func appearance(readerFont: ReadingFont) -> EditorAppearance {
        let face: ReadingFont = switch font {
        case .mono: .mono
        case .system: .system
        case .reader: readerFont
        }
        return EditorAppearance(
            font: face, size: pointSize, spacing: lineSpacing.editorSpacing, characters: Self.characters(lineWidth, mono: face == .mono),
            fullStrengthMarks: marks == .full, highlightsCurrentLine: highlightLine, hidesTags: hideTags
        )
    }

    /// The editor's longest line in characters, or nil for no limit. Mono letters are wider than the
    /// reader's, and code wants room, so Mono gets more of them: 80 at Medium, as the editor has always
    /// had, with Narrow and Wide in the same proportion. Each width is a real step for every font.
    static func characters(_ width: ReadingLineWidth, mono: Bool) -> Int? {
        guard mono else { return width.characters }
        switch width {
        case .narrow: return 66
        case .medium: return 80
        case .wide: return 100
        case .full: return nil
        }
    }

    /// The typing helpers that are on.
    public var typing: MarkdownEditing.Options {
        MarkdownEditing.Options(continuesLists: continueLists, tabIndentsLists: tabIndents, wrapsSelection: wrapSelection, indent: indent)
    }

    var behavior: EditorBehavior {
        EditorBehavior(
            typing: typing, spellCheck: spellCheck, autocorrect: autocorrect, smartPunctuation: smartPunctuation,
            autocapitalize: autocapitalize, formattingBar: formattingBar
        )
    }

    public var isDefault: Bool {
        font == .mono && textSize == 0 && openIn == .read && editWithPreview && previewSide == .right
            && lineSpacing == .comfortable && lineWidth == .medium && marks == .dimmed && !highlightLine
            && behavior == EditorBehavior() && syncPreviewScroll && hideTags && recentColors.isEmpty
    }

    /// Back to how Perch ships. Removes the saved values instead of writing defaults over them.
    public func reset() {
        font = .mono
        textSize = 0
        openIn = .read
        editWithPreview = true
        previewSide = .right
        lineSpacing = .comfortable
        lineWidth = .medium
        marks = .dimmed
        highlightLine = false
        continueLists = true
        tabIndents = true
        wrapSelection = true
        indent = .fourSpaces
        spellCheck = Self.spellCheckDefault
        autocorrect = true
        smartPunctuation = false
        autocapitalize = true
        formattingBar = true
        syncPreviewScroll = true
        hideTags = true
        recentColors = ""
        SettingsReset.remove(Key.all)
    }
}

struct EditorAppearance: Equatable {
    var font: ReadingFont = .mono
    var size: Double = 13.5
    var spacing: CGFloat = 0.4
    /// Longest line in characters, or nil for no limit.
    var characters: Int?
    /// Markdown's marks in the text colour instead of the faint one.
    var fullStrengthMarks = false
    var highlightsCurrentLine = false
    /// HTML formatting tags (`<span style=…>`, `</u>`) are hidden on every line but the one being edited.
    var hidesTags = true
}

/// What the editor does as you type, beyond how it looks.
struct EditorBehavior: Equatable {
    var typing = MarkdownEditing.Options.standard
    var spellCheck = EditingSettings.spellCheckDefault
    /// True leaves autocorrect to the system's keyboard setting; false turns it off.
    var autocorrect = true
    /// Curly quotes and long dashes. Off by default: they break Markdown and code.
    var smartPunctuation = false
    var autocapitalize = true
    var formattingBar = true
}
