import Foundation

/// Space between paragraphs, lists and quotes in the reader.
public enum ParagraphSpacing: String, CaseIterable, Identifiable, Sendable {
    case tight, normal, relaxed
    public var id: String { rawValue }
    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    /// The CSS gap under a paragraph.
    public var css: String {
        switch self {
        case .tight: return ".55em"
        case .normal: return ".95em"
        case .relaxed: return "1.4em"
        }
    }
    /// The same gap as a share of the font size, for native previews.
    public var ems: Double {
        switch self {
        case .tight: return 0.55
        case .normal: return 0.95
        case .relaxed: return 1.4
        }
    }
}

/// The face headings are set in.
public enum HeadingFont: String, CaseIterable, Identifiable, Sendable {
    case same, serif, rounded
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .same: return "Same as text"
        case .serif: return "Serif"
        case .rounded: return "Rounded"
        }
    }
    /// The CSS font stack, or nil to follow the body text.
    public var css: String? {
        switch self {
        case .same: return nil
        case .serif: return #"ui-serif, "New York", "Iowan Old Style", Georgia, serif"#
        case .rounded: return #"ui-rounded, "SF Pro Rounded", -apple-system, sans-serif"#
        }
    }
}

/// What long lines in a code block do.
public enum CodeWrap: String, CaseIterable, Identifiable, Sendable {
    case scroll, wrap
    public var id: String { rawValue }
    public var title: String { self == .scroll ? "Scroll sideways" : "Wrap long lines" }
}

public enum CodeTextSize: String, CaseIterable, Identifiable, Sendable {
    case smaller, same
    public var id: String { rawValue }
    public var title: String { self == .smaller ? "Smaller" : "Same as text" }
    public var css: String { self == .smaller ? ".86em" : "1em" }
}

/// How a note's frontmatter shows at the top of the reader.
public enum PropertiesDisplay: String, CaseIterable, Identifiable, Sendable {
    /// Open when there are only a few, closed otherwise.
    case automatic
    case hidden, collapsed, expanded
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .hidden: return "Hidden"
        case .collapsed: return "Collapsed"
        case .expanded: return "Expanded"
        }
    }
}

public enum ImageWidth: String, CaseIterable, Identifiable, Sendable {
    case fit, full
    public var id: String { rawValue }
    public var title: String { self == .fit ? "Fit text column" : "Full width" }
}

/// The reading choices beyond font and size, and how each one reaches the reader page.
/// The defaults are what the reader did before these settings existed, and send nothing at all:
/// every variable is cleared, so the page's own stylesheet decides.
public struct ReaderStyle: Equatable, Sendable {
    public var paragraphSpacing: ParagraphSpacing
    public var headingFont: HeadingFont
    public var codeWrap: CodeWrap
    public var codeTextSize: CodeTextSize
    public var properties: PropertiesDisplay
    /// Break long words at line ends. Justified text is always hyphenated, whatever this says.
    public var hyphenate: Bool
    public var justify: Bool
    public var underlineLinks: Bool
    public var imageWidth: ImageWidth

    public init(
        paragraphSpacing: ParagraphSpacing = .normal, headingFont: HeadingFont = .same, codeWrap: CodeWrap = .scroll,
        codeTextSize: CodeTextSize = .smaller, properties: PropertiesDisplay = .automatic, hyphenate: Bool = false,
        justify: Bool = false, underlineLinks: Bool = true, imageWidth: ImageWidth = .fit
    ) {
        self.paragraphSpacing = paragraphSpacing
        self.headingFont = headingFont
        self.codeWrap = codeWrap
        self.codeTextSize = codeTextSize
        self.properties = properties
        self.hyphenate = hyphenate
        self.justify = justify
        self.underlineLinks = underlineLinks
        self.imageWidth = imageWidth
    }

    public static let standard = ReaderStyle()

    /// Whether words are hyphenated: asked for, or needed because the text is justified.
    public var hyphenates: Bool { hyphenate || justify }

    /// CSS custom properties for the reader's root element. An empty value clears the property, which
    /// puts the stylesheet's default back; every key is always present so a changed setting can be undone.
    public var cssVariables: [String: String] {
        [
            "--perch-paragraph-gap": paragraphSpacing == .normal ? "" : paragraphSpacing.css,
            "--perch-font-heading": headingFont.css ?? "",
            "--perch-code-size": codeTextSize == .smaller ? "" : codeTextSize.css,
            "--perch-code-white-space": codeWrap == .scroll ? "" : "pre-wrap",
            "--perch-code-overflow-wrap": codeWrap == .scroll ? "" : "anywhere",
            "--perch-text-align": justify ? "justify" : "",
            "--perch-hyphens": hyphenates ? "auto" : "",
            "--perch-link-decoration": underlineLinks ? "" : "none",
        ]
    }

    /// `data-` attributes for the reader's root element, for choices CSS variables can't carry.
    /// An empty value removes the attribute.
    public var attributes: [String: String] {
        [
            "properties": properties == .automatic ? "" : properties.rawValue,
            "images": imageWidth == .fit ? "" : imageWidth.rawValue,
        ]
    }
}
