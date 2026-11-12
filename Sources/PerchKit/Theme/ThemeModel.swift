import Foundation

// The pure half of Perch's themes: colours as hex strings, the built-in presets, contrast maths,
// what the user chose, and the JSON a theme travels in. No SwiftUI here, so it can all be unit tested.
// PerchUI wraps a `ThemePalette` in `PerchTheme`, which adds real `Color` values.

// MARK: - Colour maths

/// An sRGB colour with components from 0 to 1.
public struct ThemeRGB: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
        self.alpha = min(max(alpha, 0), 1)
    }

    /// Reads `#RGB`, `#RRGGBB` or `#RRGGBBAA`. The `#` is optional and case doesn't matter.
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard [3, 6, 8].contains(text.count), text.allSatisfy(\.isHexDigit), text.utf8.count == text.count else { return nil }
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        guard let value = UInt64(text, radix: 16) else { return nil }
        if text.count == 8 {
            self.init(
                red: Double((value >> 24) & 0xff) / 255, green: Double((value >> 16) & 0xff) / 255,
                blue: Double((value >> 8) & 0xff) / 255, alpha: Double(value & 0xff) / 255
            )
        } else {
            self.init(red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255, blue: Double(value & 0xff) / 255)
        }
    }

    /// `#RRGGBB`, or `#RRGGBBAA` when the colour isn't fully opaque.
    public var hex: String {
        func byte(_ value: Double) -> Int { Int((value * 255).rounded()) }
        let base = String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
        return byte(alpha) == 255 ? base : base + String(format: "%02X", byte(alpha))
    }

    /// WCAG relative luminance, ignoring alpha.
    public var luminance: Double {
        func linear(_ value: Double) -> Double { value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// This colour moved `amount` (0 to 1) of the way towards `other`.
    public func mixed(with other: ThemeRGB, amount: Double) -> ThemeRGB {
        let t = min(max(amount, 0), 1)
        return ThemeRGB(
            red: red + (other.red - red) * t, green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t, alpha: alpha + (other.alpha - alpha) * t
        )
    }
}

public enum ThemeContrast {
    /// Normal text, WCAG AA.
    public static let text = 4.5
    /// Large text and interface parts, WCAG AA. Perch also uses it for muted text and status colours.
    public static let large = 3.0

    /// WCAG contrast ratio between two colours, from 1 (identical) to 21 (black on white).
    public static func ratio(_ first: ThemeRGB, _ second: ThemeRGB) -> Double {
        let a = first.luminance, b = second.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// The ratio between two hex colours, or nil if either doesn't parse.
    public static func ratio(_ first: String, _ second: String) -> Double? {
        guard let a = ThemeRGB(hex: first), let b = ThemeRGB(hex: second) else { return nil }
        return ratio(a, b)
    }

    /// Near-black or white, whichever reads better on `hex`.
    public static func readableText(on hex: String) -> String {
        let dark = "#17131F", light = "#FFFFFF"
        return (ratio(dark, hex) ?? 0) >= (ratio(light, hex) ?? 0) ? dark : light
    }
}

// MARK: - Named colours

public enum ThemeColorGroup: String, CaseIterable, Sendable {
    case backgrounds, text, accent, status

    public var label: String {
        switch self {
        case .backgrounds: "Backgrounds"
        case .text: "Text"
        case .accent: "Accent"
        case .status: "Status"
        }
    }
}

/// Every colour a theme names. The raw value is the key used in JSON and in saved overrides.
public enum ThemeColorKey: String, CaseIterable, Codable, Sendable {
    case background, sidebar, surface, border
    case text, textSecondary, textMuted
    case accent, accentText
    case danger, warning, success, info

    public var label: String {
        switch self {
        case .background: "Main background"
        case .sidebar: "Sidebar"
        case .surface: "Cards and fields"
        case .border: "Borders"
        case .text: "Text"
        case .textSecondary: "Secondary text"
        case .textMuted: "Muted text"
        case .accent: "Accent"
        case .accentText: "Text on accent"
        case .danger: "Overdue"
        case .warning: "Warning"
        case .success: "Done"
        case .info: "Information"
        }
    }

    public var group: ThemeColorGroup {
        switch self {
        case .background, .sidebar, .surface, .border: .backgrounds
        case .text, .textSecondary, .textMuted: .text
        case .accent, .accentText: .accent
        case .danger, .warning, .success, .info: .status
        }
    }
}

/// One theme: a name, whether it is dark, and its named colours as hex strings.
public struct ThemePalette: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var isDark: Bool
    public var background: String
    public var sidebar: String
    public var surface: String
    public var border: String
    public var text: String
    public var textSecondary: String
    public var textMuted: String
    public var accent: String
    public var accentText: String
    public var danger: String
    public var warning: String
    public var success: String
    public var info: String

    public init(
        id: String, name: String, isDark: Bool, background: String, sidebar: String, surface: String, border: String,
        text: String, textSecondary: String, textMuted: String, accent: String, accentText: String,
        danger: String, warning: String, success: String, info: String
    ) {
        self.id = id
        self.name = name
        self.isDark = isDark
        self.background = background
        self.sidebar = sidebar
        self.surface = surface
        self.border = border
        self.text = text
        self.textSecondary = textSecondary
        self.textMuted = textMuted
        self.accent = accent
        self.accentText = accentText
        self.danger = danger
        self.warning = warning
        self.success = success
        self.info = info
    }

    public subscript(key: ThemeColorKey) -> String {
        get {
            switch key {
            case .background: background
            case .sidebar: sidebar
            case .surface: surface
            case .border: border
            case .text: text
            case .textSecondary: textSecondary
            case .textMuted: textMuted
            case .accent: accent
            case .accentText: accentText
            case .danger: danger
            case .warning: warning
            case .success: success
            case .info: info
            }
        }
        set {
            switch key {
            case .background: background = newValue
            case .sidebar: sidebar = newValue
            case .surface: surface = newValue
            case .border: border = newValue
            case .text: text = newValue
            case .textSecondary: textSecondary = newValue
            case .textMuted: textMuted = newValue
            case .accent: accent = newValue
            case .accentText: accentText = newValue
            case .danger: danger = newValue
            case .warning: warning = newValue
            case .success: success = newValue
            case .info: info = newValue
            }
        }
    }

    /// The colours as a dictionary keyed by `ThemeColorKey.rawValue`.
    public var colors: [String: String] {
        Dictionary(uniqueKeysWithValues: ThemeColorKey.allCases.map { ($0.rawValue, self[$0]) })
    }

    /// This theme with some colours replaced. Unknown keys and values that aren't hex colours are ignored.
    public func applying(_ overrides: [String: String]) -> ThemePalette {
        var copy = self
        for (name, value) in overrides {
            guard let key = ThemeColorKey(rawValue: name), let rgb = ThemeRGB(hex: value) else { continue }
            copy[key] = rgb.hex
        }
        return copy
    }

    /// The colours that differ from `base`, as overrides.
    public func differences(from base: ThemePalette) -> [String: String] {
        var result: [String: String] = [:]
        for key in ThemeColorKey.allCases where ThemeRGB(hex: self[key]) != ThemeRGB(hex: base[key]) { result[key.rawValue] = self[key] }
        return result
    }

    /// A slightly tinted background for code, derived so it always sits between the page and the text.
    public var codeBackground: String {
        guard let page = ThemeRGB(hex: background), let ink = ThemeRGB(hex: text) else { return surface }
        return page.mixed(with: ink, amount: isDark ? 0.09 : 0.06).hex
    }

    /// What the note renderer's stylesheet reads: CSS custom properties, plus `colorScheme`.
    public var cssVariables: [String: String] {
        [
            "--perch-bg": background,
            "--perch-sidebar": sidebar,
            "--perch-surface": surface,
            "--perch-border": border,
            "--perch-text": text,
            "--perch-text-secondary": textSecondary,
            "--perch-muted": textMuted,
            "--perch-accent": accent,
            "--perch-accent-text": accentText,
            "--perch-danger": danger,
            "--perch-warning": warning,
            "--perch-success": success,
            "--perch-info": info,
            "--perch-code-bg": codeBackground,
            "colorScheme": isDark ? "dark" : "light",
        ]
    }

    /// The variables as one CSS declaration block body, in a stable order, for `:root { ... }`.
    public var cssDeclarations: String {
        var lines = cssVariables.filter { $0.key.hasPrefix("--") }.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value);" }
        lines.append("color-scheme: \(isDark ? "dark" : "light");")
        return lines.joined(separator: " ")
    }
}

// MARK: - Contrast checks

/// A pair of colours in a theme that is harder to read than it should be.
public struct ThemeContrastIssue: Equatable, Sendable {
    public var foreground: ThemeColorKey
    public var background: ThemeColorKey
    public var ratio: Double
    public var required: Double

    public var message: String {
        String(format: "Hard to read on %@ (%.1f:1, aim for %.1f:1)", background.label.lowercased(), ratio, required)
    }
}

public extension ThemePalette {
    /// The pairs Perch checks, and the least contrast each needs.
    static let contrastRules: [(foreground: ThemeColorKey, background: ThemeColorKey, required: Double)] = [
        (.text, .background, ThemeContrast.text), (.text, .sidebar, ThemeContrast.text), (.text, .surface, ThemeContrast.text),
        (.textSecondary, .background, ThemeContrast.text), (.textSecondary, .sidebar, ThemeContrast.text), (.textSecondary, .surface, ThemeContrast.text),
        (.textMuted, .background, ThemeContrast.large), (.textMuted, .sidebar, ThemeContrast.large), (.textMuted, .surface, ThemeContrast.large),
        (.accent, .background, ThemeContrast.large), (.accentText, .accent, ThemeContrast.text),
        (.danger, .background, ThemeContrast.large), (.warning, .background, ThemeContrast.large),
        (.success, .background, ThemeContrast.large), (.info, .background, ThemeContrast.large),
    ]

    /// Every checked pair that falls short. Empty for all built-in themes.
    var contrastIssues: [ThemeContrastIssue] {
        Self.contrastRules.compactMap { rule in
            guard let ratio = ThemeContrast.ratio(self[rule.foreground], self[rule.background]), ratio < rule.required else { return nil }
            return ThemeContrastIssue(foreground: rule.foreground, background: rule.background, ratio: ratio, required: rule.required)
        }
    }

    /// The issues that involve `key`, on either side of the pair.
    func contrastIssues(for key: ThemeColorKey) -> [ThemeContrastIssue] {
        contrastIssues.filter { $0.foreground == key || $0.background == key }
    }
}

// MARK: - JSON

extension ThemePalette: Codable {
    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Forgiving on purpose, so a theme made by a newer or older Perch still loads: unknown keys are ignored,
    /// colours may sit under `colors` or at the top level, and anything missing or malformed falls back to
    /// the built-in Perch light or dark theme.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        let nested = try? container.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("colors"))
        func color(_ key: ThemeColorKey) -> String? {
            let found = (try? nested?.decodeIfPresent(String.self, forKey: AnyKey(key.rawValue))) ?? (try? container.decodeIfPresent(String.self, forKey: AnyKey(key.rawValue)))
            return found.flatMap { ThemeRGB(hex: $0)?.hex }
        }
        let found = Dictionary(uniqueKeysWithValues: ThemeColorKey.allCases.compactMap { key in color(key).map { (key, $0) } })
        guard !found.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "No theme colors found"))
        }
        let dark: Bool
        if let stated = try? container.decodeIfPresent(Bool.self, forKey: AnyKey("isDark")) {
            dark = stated
        } else if let page = found[.background].flatMap({ ThemeRGB(hex: $0) }) {
            dark = page.luminance < 0.4
        } else {
            dark = true
        }
        var palette = dark ? ThemePresets.perchDark : ThemePresets.perchLight
        for (key, value) in found { palette[key] = value }
        // An accent without its own text colour gets one that reads on it.
        if found[.accent] != nil, found[.accentText] == nil { palette.accentText = ThemeContrast.readableText(on: palette.accent) }
        let name = ((try? container.decodeIfPresent(String.self, forKey: AnyKey("name"))) ?? nil)?.trimmingCharacters(in: .whitespacesAndNewlines)
        palette.name = String((name?.isEmpty == false ? name! : "Imported theme").prefix(60))
        let id = ((try? container.decodeIfPresent(String.self, forKey: AnyKey("id"))) ?? nil)?.trimmingCharacters(in: .whitespacesAndNewlines)
        palette.id = id?.isEmpty == false ? String(id!.prefix(80)) : "custom-" + ThemePalette.slug(palette.name)
        palette.isDark = dark
        self = palette
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyKey.self)
        try container.encode("perch-theme", forKey: AnyKey("format"))
        try container.encode(1, forKey: AnyKey("version"))
        try container.encode(id, forKey: AnyKey("id"))
        try container.encode(name, forKey: AnyKey("name"))
        try container.encode(isDark, forKey: AnyKey("isDark"))
        try container.encode(colors, forKey: AnyKey("colors"))
    }

    /// Readable JSON for copying, pasting or saving to a file.
    public func exportedJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// Reads a theme from JSON text. Throws if it isn't JSON or names no usable colours.
    public init(json: String) throws {
        self = try JSONDecoder().decode(ThemePalette.self, from: Data(json.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
    }

    static func slug(_ text: String) -> String {
        let cleaned = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let slug = String(cleaned).split(separator: "-").joined(separator: "-")
        return slug.isEmpty ? "theme" : slug
    }
}

// MARK: - Presets

public enum ThemePresets {
    /// The id of the choice that follows the device's light or dark setting.
    public static let systemID = "system"

    // Perch's own pair: the ember of the app icon, over a dusk sky.
    public static let perchLight = ThemePalette(
        id: "perch-light", name: "Perch Light", isDark: false,
        background: "#FFFCF8", sidebar: "#F6F1EA", surface: "#FFFFFF", border: "#E6DED3",
        text: "#1F1A24", textSecondary: "#5A5263", textMuted: "#857C8C", accent: "#C94A22", accentText: "#FFFFFF",
        danger: "#C7362F", warning: "#A8650A", success: "#1E8A6E", info: "#2F6FDB"
    )

    public static let perchDark = ThemePalette(
        id: "perch-dark", name: "Perch Dark", isDark: true,
        background: "#15131C", sidebar: "#100E17", surface: "#1F1C29", border: "#2E2A3B",
        text: "#ECE8F2", textSecondary: "#B5AFC4", textMuted: "#8A849B", accent: "#FF8A4C", accentText: "#1A0F08",
        danger: "#FF6B6B", warning: "#FFC56B", success: "#4FD1B5", info: "#8AB4FF"
    )

    public static let light: [ThemePalette] = [
        perchLight,
        ThemePalette(
            id: "paper", name: "Paper", isDark: false,
            background: "#F8F1E3", sidebar: "#EFE6D3", surface: "#FDF8EE", border: "#DDD0B8",
            text: "#3B2F20", textSecondary: "#6B5A45", textMuted: "#8A775E", accent: "#A0522D", accentText: "#FFF8EE",
            danger: "#B3362B", warning: "#9A6208", success: "#4F7A28", info: "#2F6C8F"
        ),
        ThemePalette(
            id: "solarized-light", name: "Solarized Light", isDark: false,
            background: "#FDF6E3", sidebar: "#EEE8D5", surface: "#FFFBF0", border: "#DDD6C1",
            text: "#073642", textSecondary: "#536870", textMuted: "#657B83", accent: "#1E76B8", accentText: "#FFFFFF",
            danger: "#DC322F", warning: "#A57C00", success: "#788A00", info: "#23958C"
        ),
        ThemePalette(
            id: "catppuccin-latte", name: "Catppuccin Latte", isDark: false,
            background: "#EFF1F5", sidebar: "#E6E9EF", surface: "#F9FAFC", border: "#CCD0DA",
            text: "#4C4F69", textSecondary: "#5C5F77", textMuted: "#7C7F93", accent: "#8839EF", accentText: "#FFFFFF",
            danger: "#D20F39", warning: "#BF7600", success: "#3C962A", info: "#1E66F5"
        ),
        ThemePalette(
            id: "rose-pine-dawn", name: "Rosé Pine Dawn", isDark: false,
            background: "#FAF4ED", sidebar: "#F2E9E1", surface: "#FFFAF3", border: "#DFDAD9",
            text: "#575279", textSecondary: "#6A6688", textMuted: "#827D94", accent: "#286983", accentText: "#FFFAF3",
            danger: "#B4637A", warning: "#B8771A", success: "#56949F", info: "#907AA9"
        ),
        ThemePalette(
            id: "github-light", name: "GitHub Light", isDark: false,
            background: "#FFFFFF", sidebar: "#F6F8FA", surface: "#F6F8FA", border: "#D0D7DE",
            text: "#1F2328", textSecondary: "#59636E", textMuted: "#818B98", accent: "#0969DA", accentText: "#FFFFFF",
            danger: "#CF222E", warning: "#9A6700", success: "#1A7F37", info: "#0969DA"
        ),
        ThemePalette(
            id: "nord-light", name: "Nord Light", isDark: false,
            background: "#ECEFF4", sidebar: "#E5E9F0", surface: "#F8F9FB", border: "#D8DEE9",
            text: "#2E3440", textSecondary: "#4C566A", textMuted: "#6B7689", accent: "#52749C", accentText: "#FFFFFF",
            danger: "#BF616A", warning: "#A9712B", success: "#5F8052", info: "#5E81AC"
        ),
    ]

    public static let dark: [ThemePalette] = [
        perchDark,
        ThemePalette(
            id: "graphite", name: "Graphite", isDark: true,
            background: "#1A1A1A", sidebar: "#141414", surface: "#262626", border: "#383838",
            text: "#E6E6E6", textSecondary: "#B0B0B0", textMuted: "#888888", accent: "#4C8DFF", accentText: "#0B1220",
            danger: "#EF4444", warning: "#F59E0B", success: "#4ADE80", info: "#60A5FA"
        ),
        ThemePalette(
            id: "midnight", name: "Midnight Blue", isDark: true,
            background: "#0D1117", sidebar: "#0A0E14", surface: "#161B22", border: "#30363D",
            text: "#C9D1D9", textSecondary: "#8B949E", textMuted: "#7D8590", accent: "#58A6FF", accentText: "#0D1117",
            danger: "#FF7B72", warning: "#E3B341", success: "#3FB950", info: "#79C0FF"
        ),
        ThemePalette(
            id: "dracula", name: "Dracula", isDark: true,
            background: "#282A36", sidebar: "#21222C", surface: "#343746", border: "#44475A",
            text: "#F8F8F2", textSecondary: "#C3C5D9", textMuted: "#8B93BA", accent: "#BD93F9", accentText: "#21222C",
            danger: "#FF5555", warning: "#F1FA8C", success: "#50FA7B", info: "#8BE9FD"
        ),
        ThemePalette(
            id: "nord", name: "Nord", isDark: true,
            background: "#2E3440", sidebar: "#272C36", surface: "#3B4252", border: "#434C5E",
            text: "#D8DEE9", textSecondary: "#AEB9CC", textMuted: "#8490A8", accent: "#88C0D0", accentText: "#2E3440",
            danger: "#BF616A", warning: "#EBCB8B", success: "#A3BE8C", info: "#81A1C1"
        ),
        ThemePalette(
            id: "solarized-dark", name: "Solarized Dark", isDark: true,
            background: "#002B36", sidebar: "#00212B", surface: "#073642", border: "#0F4A59",
            text: "#93A1A1", textSecondary: "#8C9C9E", textMuted: "#6F858D", accent: "#268BD2", accentText: "#00212B",
            danger: "#DC322F", warning: "#B58900", success: "#859900", info: "#2AA198"
        ),
        ThemePalette(
            id: "gruvbox", name: "Gruvbox", isDark: true,
            background: "#282828", sidebar: "#1D2021", surface: "#3C3836", border: "#504945",
            text: "#EBDBB2", textSecondary: "#BDAE93", textMuted: "#928374", accent: "#FE8019", accentText: "#1D2021",
            danger: "#FB4934", warning: "#FABD2F", success: "#B8BB26", info: "#83A598"
        ),
        ThemePalette(
            id: "tokyo-night", name: "Tokyo Night", isDark: true,
            background: "#1A1B26", sidebar: "#16161E", surface: "#24283B", border: "#2F3549",
            text: "#C0CAF5", textSecondary: "#A9B1D6", textMuted: "#737AA2", accent: "#7AA2F7", accentText: "#16161E",
            danger: "#F7768E", warning: "#E0AF68", success: "#9ECE6A", info: "#7DCFFF"
        ),
        ThemePalette(
            id: "one-dark", name: "One Dark", isDark: true,
            background: "#282C34", sidebar: "#21252B", surface: "#323842", border: "#3E4451",
            text: "#ABB2BF", textSecondary: "#9DA5B4", textMuted: "#7F848E", accent: "#61AFEF", accentText: "#21252B",
            danger: "#E06C75", warning: "#E5C07B", success: "#98C379", info: "#56B6C2"
        ),
        ThemePalette(
            id: "catppuccin-mocha", name: "Catppuccin Mocha", isDark: true,
            background: "#1E1E2E", sidebar: "#181825", surface: "#313244", border: "#45475A",
            text: "#CDD6F4", textSecondary: "#BAC2DE", textMuted: "#7F849C", accent: "#CBA6F7", accentText: "#1E1E2E",
            danger: "#F38BA8", warning: "#F9E2AF", success: "#A6E3A1", info: "#89B4FA"
        ),
        ThemePalette(
            id: "rose-pine", name: "Rosé Pine", isDark: true,
            background: "#191724", sidebar: "#14121D", surface: "#26233A", border: "#393552",
            text: "#E0DEF4", textSecondary: "#908CAA", textMuted: "#74708C", accent: "#EBBCBA", accentText: "#191724",
            danger: "#EB6F92", warning: "#F6C177", success: "#9CCFD8", info: "#C4A7E7"
        ),
        ThemePalette(
            id: "kanagawa", name: "Kanagawa", isDark: true,
            background: "#1F1F28", sidebar: "#16161D", surface: "#2A2A37", border: "#363646",
            text: "#DCD7BA", textSecondary: "#C8C093", textMuted: "#7A7971", accent: "#7E9CD8", accentText: "#16161D",
            danger: "#E46876", warning: "#E6C384", success: "#98BB6C", info: "#7FB4CA"
        ),
        ThemePalette(
            id: "everforest", name: "Everforest", isDark: true,
            background: "#2D353B", sidebar: "#232A2E", surface: "#374247", border: "#475258",
            text: "#D3C6AA", textSecondary: "#A3AFA6", textMuted: "#859289", accent: "#A7C080", accentText: "#232A2E",
            danger: "#E67E80", warning: "#DBBC7F", success: "#83C092", info: "#7FBBB3"
        ),
        ThemePalette(
            id: "synthwave", name: "Synthwave", isDark: true,
            background: "#262335", sidebar: "#1B182A", surface: "#34294F", border: "#463465",
            text: "#E0D8F0", textSecondary: "#B6B1CE", textMuted: "#8673A8", accent: "#FF7EDB", accentText: "#241B2F",
            danger: "#FE4450", warning: "#FEDE5D", success: "#72F1B8", info: "#36F9F6"
        ),
        ThemePalette(
            id: "ayu", name: "Ayu", isDark: true,
            background: "#0B0E14", sidebar: "#07090D", surface: "#131721", border: "#1F2430",
            text: "#BFBDB6", textSecondary: "#8B8A85", textMuted: "#6C7380", accent: "#E6B450", accentText: "#0B0E14",
            danger: "#D95757", warning: "#FFB454", success: "#AAD94C", info: "#59C2FF"
        ),
        ThemePalette(
            id: "horizon", name: "Horizon", isDark: true,
            background: "#1C1E26", sidebar: "#16171D", surface: "#232530", border: "#2E303E",
            text: "#D5D8DA", textSecondary: "#9DA0A8", textMuted: "#6C6F93", accent: "#E95678", accentText: "#16171D",
            danger: "#F43E5C", warning: "#FAB795", success: "#29D398", info: "#26BBD9"
        ),
        ThemePalette(
            id: "moonlight", name: "Moonlight", isDark: true,
            background: "#222436", sidebar: "#1E2030", surface: "#2F334D", border: "#3B4261",
            text: "#C8D3F5", textSecondary: "#A9B8E8", textMuted: "#7A88CF", accent: "#82AAFF", accentText: "#1E2030",
            danger: "#FF757F", warning: "#FFC777", success: "#C3E88D", info: "#86E1FC"
        ),
    ]

    /// Every built-in theme, light first.
    public static let all: [ThemePalette] = light + dark

    public static func preset(id: String) -> ThemePalette? { all.first { $0.id == id } }

    /// A few accents for the quick accent picker, starting with Perch's ember.
    public static let accentChoices: [(name: String, light: String, dark: String)] = [
        ("Ember", "#C94A22", "#FF8A4C"), ("Rose", "#C2376B", "#FF7EA8"), ("Violet", "#7447D6", "#B79CFF"),
        ("Blue", "#1F6FE0", "#6CA8FF"), ("Teal", "#0E7C86", "#4FD1C5"), ("Green", "#2C7D3F", "#7DD68B"),
        ("Gold", "#946200", "#F2C55C"), ("Graphite", "#4A4F5A", "#B4BAC6"),
    ]

    /// The shade of a quick accent that suits a light or dark theme, so one choice reads on both.
    /// A colour that isn't one of `accentChoices` comes back as it is.
    public static func accent(_ hex: String, isDark: Bool) -> String {
        guard let rgb = ThemeRGB(hex: hex) else { return hex }
        guard let choice = accentChoices.first(where: { ThemeRGB(hex: $0.light) == rgb || ThemeRGB(hex: $0.dark) == rgb }) else { return rgb.hex }
        return isDark ? choice.dark : choice.light
    }
}

// MARK: - What the user chose

public enum ThemeAppearance: String, CaseIterable, Codable, Sendable {
    /// Follow the device.
    case auto
    case light
    case dark

    public var label: String {
        switch self {
        case .auto: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

public enum ThemeImportError: Error, Equatable {
    case notATheme
}

/// The whole theme choice: which preset, how System behaves, and any colours the user changed.
/// Pure data; `ThemeStore` in PerchUI saves it and publishes changes.
public struct ThemeSettings: Equatable, Sendable {
    /// A preset id, an imported theme's id, or `ThemePresets.systemID`.
    public var selectedID: String
    /// Used only while System is selected.
    public var appearance: ThemeAppearance
    /// One accent applied over whichever theme is showing. Nil keeps each theme's own.
    public var accent: String?
    /// Changed colours, keyed by theme id and then by `ThemeColorKey.rawValue`.
    public var overrides: [String: [String: String]]
    /// Themes pasted in from elsewhere that aren't built in.
    public var imported: [ThemePalette]

    public init(
        selectedID: String = ThemePresets.systemID, appearance: ThemeAppearance = .auto, accent: String? = nil,
        overrides: [String: [String: String]] = [:], imported: [ThemePalette] = []
    ) {
        self.selectedID = selectedID
        self.appearance = appearance
        self.accent = accent
        self.overrides = overrides
        self.imported = imported
    }

    public var followsSystem: Bool { selectedID == ThemePresets.systemID || palette(id: selectedID) == nil }

    public func palette(id: String) -> ThemePalette? {
        ThemePresets.preset(id: id) ?? imported.first { $0.id == id }
    }

    /// True or false when the choice pins dark or light; nil when the device decides.
    public var forcedDark: Bool? {
        if followsSystem {
            switch appearance {
            case .auto: return nil
            case .light: return false
            case .dark: return true
            }
        }
        return palette(id: selectedID)?.isDark
    }

    /// The selected theme as shipped, before the user's changes.
    public func basePalette(systemIsDark: Bool) -> ThemePalette {
        if !followsSystem, let chosen = palette(id: selectedID) { return chosen }
        return (forcedDark ?? systemIsDark) ? ThemePresets.perchDark : ThemePresets.perchLight
    }

    /// The theme to draw with: the selected one, then the quick accent, then per-colour changes.
    public func palette(systemIsDark: Bool) -> ThemePalette {
        let result = withQuickAccent(basePalette(systemIsDark: systemIsDark))
        return result.applying(overrides[result.id] ?? [:])
    }

    /// `base` with the quick accent laid over it, in the shade that suits a light or dark theme.
    private func withQuickAccent(_ base: ThemePalette) -> ThemePalette {
        guard let accent, ThemeRGB(hex: accent) != nil else { return base }
        var result = base
        result.accent = ThemePresets.accent(accent, isDark: base.isDark)
        result.accentText = ThemeContrast.readableText(on: result.accent)
        return result
    }

    /// One accent over every theme; nil goes back to each theme's own. Either way it replaces any
    /// hand-picked accent on the theme that is showing (both halves of System), and on no other theme.
    public mutating func setAccent(_ hex: String?) {
        accent = hex.flatMap { ThemeRGB(hex: $0)?.hex }
        let showing = followsSystem ? [ThemePresets.perchLight.id, ThemePresets.perchDark.id] : [selectedID]
        for id in showing {
            guard var changes = overrides[id] else { continue }
            changes[ThemeColorKey.accent.rawValue] = nil
            changes[ThemeColorKey.accentText.rawValue] = nil
            overrides[id] = changes.isEmpty ? nil : changes
        }
    }

    public func isCustomised(systemIsDark: Bool) -> Bool {
        accent != nil || !(overrides[basePalette(systemIsDark: systemIsDark).id] ?? [:]).isEmpty
    }

    public func isOverridden(_ key: ThemeColorKey, systemIsDark: Bool) -> Bool {
        overrides[basePalette(systemIsDark: systemIsDark).id]?[key.rawValue] != nil
    }

    /// Changes one colour of the showing theme. Setting it back to the shipped value removes the change.
    public mutating func setColor(_ key: ThemeColorKey, to hex: String?, systemIsDark: Bool) {
        let base = basePalette(systemIsDark: systemIsDark)
        var changes = overrides[base.id] ?? [:]
        if let hex, let rgb = ThemeRGB(hex: hex) {
            let shipped = withQuickAccent(base)
            changes[key.rawValue] = ThemeRGB(hex: shipped[key]) == rgb ? nil : rgb.hex
        } else {
            changes[key.rawValue] = nil
        }
        overrides[base.id] = changes.isEmpty ? nil : changes
    }

    /// Drops the quick accent and every changed colour of the selected theme (both halves of System).
    public mutating func resetCustomisation() {
        accent = nil
        if followsSystem {
            overrides[ThemePresets.perchLight.id] = nil
            overrides[ThemePresets.perchDark.id] = nil
        } else {
            overrides[selectedID] = nil
        }
    }

    /// The showing theme, with the user's changes baked in, as JSON.
    public func exportedJSON(systemIsDark: Bool) -> String {
        palette(systemIsDark: systemIsDark).exportedJSON()
    }

    /// Takes a theme from JSON and selects it. A built-in theme comes back as that preset plus its changed
    /// colours; anything else joins the imported themes. Returns the theme that is now showing.
    @discardableResult
    public mutating func importTheme(json: String) throws -> ThemePalette {
        // A theme is a few hundred bytes. Anything huge on the clipboard isn't one, so don't parse it.
        guard json.utf8.count <= Self.importSizeLimit, let incoming = try? ThemePalette(json: json) else { throw ThemeImportError.notATheme }
        if let preset = ThemePresets.preset(id: incoming.id) {
            let changes = incoming.differences(from: preset)
            overrides[preset.id] = changes.isEmpty ? nil : changes
            accent = nil
            // Perch's own pair stays under System, pinned to the half that was shared.
            if preset.id == ThemePresets.perchLight.id || preset.id == ThemePresets.perchDark.id, followsSystem {
                selectedID = ThemePresets.systemID
                appearance = preset.isDark ? .dark : .light
            } else {
                selectedID = preset.id
            }
            return preset.applying(changes)
        }
        var theme = incoming
        if theme.id == ThemePresets.systemID { theme.id = "custom-system" }
        imported.removeAll { $0.id == theme.id }
        imported.append(theme)
        // Keep the newest; the oldest fall off rather than letting saved settings grow without end.
        for dropped in imported.dropLast(Self.importedLimit) { overrides[dropped.id] = nil }
        imported = Array(imported.suffix(Self.importedLimit))
        overrides[theme.id] = nil
        accent = nil
        selectedID = theme.id
        return theme
    }

    public mutating func removeImported(id: String) {
        // Only an imported theme can be removed; a preset's changes are not touched.
        guard imported.contains(where: { $0.id == id }) else { return }
        imported.removeAll { $0.id == id }
        overrides[id] = nil
        if selectedID == id { selectedID = ThemePresets.systemID }
    }

    // MARK: Saved forms

    /// The largest JSON text `importTheme` will look at, in bytes.
    public static let importSizeLimit = 64 * 1024
    /// How many imported themes are kept.
    public static let importedLimit = 40

    /// Reads saved imported themes, keeping what is usable: entries that aren't themes are skipped,
    /// as are ids that clash with a built-in theme or System, and a repeated id keeps its last entry.
    public static func importedThemes(savedJSON: String) -> [ThemePalette] {
        struct Entry: Decodable {
            var theme: ThemePalette?
            init(from decoder: Decoder) throws { theme = try? ThemePalette(from: decoder) }
        }
        guard let entries = try? JSONDecoder().decode([Entry].self, from: Data(savedJSON.utf8)) else { return [] }
        var result: [ThemePalette] = []
        for theme in entries.compactMap(\.theme) where theme.id != ThemePresets.systemID && ThemePresets.preset(id: theme.id) == nil {
            result.removeAll { $0.id == theme.id }
            result.append(theme)
        }
        return Array(result.suffix(importedLimit))
    }

    /// Reads saved colour changes, keeping what is usable: unknown colour names and values that
    /// aren't hex colours are dropped, and so is a theme left with no changes.
    public static func overrides(savedJSON: String) -> [String: [String: String]] {
        guard let raw = try? JSONSerialization.jsonObject(with: Data(savedJSON.utf8)) as? [String: Any] else { return [:] }
        var result: [String: [String: String]] = [:]
        for (id, value) in raw {
            guard let colours = value as? [String: Any] else { continue }
            var kept: [String: String] = [:]
            for (name, hex) in colours {
                guard ThemeColorKey(rawValue: name) != nil, let hex = hex as? String, let rgb = ThemeRGB(hex: hex) else { continue }
                kept[name] = rgb.hex
            }
            if !kept.isEmpty { result[id] = kept }
        }
        return result
    }
}
