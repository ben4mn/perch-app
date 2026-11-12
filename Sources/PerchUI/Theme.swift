import PerchKit
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// Perch's themes, as SwiftUI sees them. The colour data, presets and contrast rules live in
// PerchKit (`ThemePalette`, `ThemePresets`, `ThemeSettings`); this file turns them into `Color`s,
// saves the user's choice, and hands the resolved theme to every view through the environment.
//
//     RootView().perchThemed(ThemeStore.shared)          // once, at the root
//     @Environment(\.perchTheme) private var theme       // in any view
//     Text("Overdue").foregroundStyle(theme.danger)

// MARK: - Hex and Color

public extension Color {
    /// A colour from `#RGB`, `#RRGGBB` or `#RRGGBBAA`. Nil if the text isn't a hex colour.
    init?(hex: String) {
        guard let rgb = ThemeRGB(hex: hex) else { return nil }
        self.init(rgb)
    }

    init(_ rgb: ThemeRGB) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: rgb.alpha)
    }

    /// This colour as sRGB components, resolved for the given environment (light or dark, contrast).
    func themeRGB(in environment: EnvironmentValues = EnvironmentValues()) -> ThemeRGB {
        let resolved = resolve(in: environment)
        return ThemeRGB(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue), alpha: Double(resolved.opacity))
    }

    /// This colour as `#RRGGBB`, the form themes store.
    func hexString(in environment: EnvironmentValues = EnvironmentValues()) -> String {
        var rgb = themeRGB(in: environment)
        rgb.alpha = 1
        return rgb.hex
    }
}

// MARK: - PerchTheme

/// A resolved theme: named colours ready to draw with. Build one from a `ThemePalette`,
/// or read the current one with `@Environment(\.perchTheme)`.
public struct PerchTheme: Equatable, Identifiable, Codable, Sendable {
    /// The hex values behind the colours.
    public let palette: ThemePalette
    /// The interface size, density and other Display choices. They ride with the theme so that every view
    /// drawing with it is drawn again when one of them changes. Not part of a saved or exported theme.
    public var display = PerchDisplay.standard

    /// The main pane behind notes and lists.
    public let background: Color
    public let sidebar: Color
    /// Cards, fields and anything raised off the background.
    public let surface: Color
    public let border: Color
    public let text: Color
    public let textSecondary: Color
    public let textMuted: Color
    public let accent: Color
    /// Text and icons drawn on top of the accent.
    public let accentText: Color
    /// Overdue and destructive.
    public let danger: Color
    public let warning: Color
    public let success: Color
    public let info: Color
    /// Behind code and other monospaced blocks.
    public let codeBackground: Color

    public init(_ palette: ThemePalette) {
        self.palette = palette
        func color(_ key: ThemeColorKey) -> Color { Color(hex: palette[key]) ?? .gray }
        background = color(.background)
        sidebar = color(.sidebar)
        surface = color(.surface)
        border = color(.border)
        text = color(.text)
        textSecondary = color(.textSecondary)
        textMuted = color(.textMuted)
        accent = color(.accent)
        accentText = color(.accentText)
        danger = color(.danger)
        warning = color(.warning)
        success = color(.success)
        info = color(.info)
        codeBackground = Color(hex: palette.codeBackground) ?? color(.surface)
    }

    public var id: String { palette.id }
    public var name: String { palette.name }
    public var isDark: Bool { palette.isDark }
    public var colorScheme: ColorScheme { palette.isDark ? .dark : .light }

    public func color(_ key: ThemeColorKey) -> Color { Color(hex: palette[key]) ?? .gray }
    public func hex(_ key: ThemeColorKey) -> String { palette[key] }

    /// This theme carrying the given Display choices.
    public func with(display: PerchDisplay) -> PerchTheme {
        var copy = self
        copy.display = display
        return copy
    }

    /// A soft wash of the accent, for selection and hover.
    public var accentSoft: Color { accent.opacity(isDark ? 0.18 : 0.12) }
    /// A hairline that is quieter than `border`.
    public var divider: Color { border.opacity(0.6) }

    /// CSS custom properties for the note renderer: `--perch-bg`, `--perch-text`, `--perch-muted`,
    /// `--perch-accent`, `--perch-surface`, `--perch-border` and friends, plus `colorScheme`.
    public var cssVariables: [String: String] { palette.cssVariables }

    public static let light = PerchTheme(ThemePresets.perchLight)
    public static let dark = PerchTheme(ThemePresets.perchDark)

    public static func == (lhs: PerchTheme, rhs: PerchTheme) -> Bool { lhs.palette == rhs.palette && lhs.display == rhs.display }

    public init(from decoder: Decoder) throws { self.init(try ThemePalette(from: decoder)) }
    public func encode(to encoder: Encoder) throws { try palette.encode(to: encoder) }
}

// MARK: - ThemeStore

/// Remembers the user's theme and publishes changes. Use `ThemeStore.shared` in the apps;
/// pass your own `UserDefaults` in previews and tests.
@MainActor
public final class ThemeStore: ObservableObject {
    public static let shared = ThemeStore()

    /// Where the choice is saved. All plain values, so launch arguments can override any of them.
    public enum Keys {
        /// A preset id, an imported theme's id, or "system". String.
        public static let selected = "themeID"
        /// "auto", "light" or "dark"; used while System is selected. String.
        public static let appearance = "themeAppearance"
        /// A hex colour used as the accent over every theme, or absent. String.
        public static let accent = "themeAccent"
        /// JSON: `{ themeID: { colourKey: hex } }`. String.
        public static let overrides = "themeOverrides"
        /// JSON array of pasted-in themes. String.
        public static let imported = "themeImported"
    }

    @Published public private(set) var settings: ThemeSettings
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = Self.read(defaults)
    }

    /// Reads the saved choice again without saving anything. Snapshot runs use this after
    /// setting a theme in the launch-argument domain.
    public func reload() {
        let fresh = Self.read(defaults)
        if fresh != settings { settings = fresh }
    }

    // MARK: Reading the theme

    /// The theme to draw with, including the user's changes. `colorScheme` matters only for System on Auto.
    public func theme(for colorScheme: ColorScheme) -> PerchTheme {
        PerchTheme(settings.palette(systemIsDark: colorScheme == .dark))
    }

    /// The selected theme as shipped, before the user's changes.
    public func baseTheme(for colorScheme: ColorScheme) -> PerchTheme {
        PerchTheme(settings.basePalette(systemIsDark: colorScheme == .dark))
    }

    /// Light or dark when the theme pins one; nil when the device decides.
    public var preferredColorScheme: ColorScheme? {
        settings.forcedDark.map { $0 ? .dark : .light }
    }

    public var selectedID: String { settings.followsSystem ? ThemePresets.systemID : settings.selectedID }
    public var appearance: ThemeAppearance { settings.appearance }
    public var accentOverride: String? { settings.accent }
    public var importedThemes: [PerchTheme] { settings.imported.map(PerchTheme.init) }

    public func isCustomised(for colorScheme: ColorScheme) -> Bool {
        settings.isCustomised(systemIsDark: colorScheme == .dark)
    }

    public func isOverridden(_ key: ThemeColorKey, for colorScheme: ColorScheme) -> Bool {
        settings.isOverridden(key, systemIsDark: colorScheme == .dark)
    }

    // MARK: Changing it

    public func select(_ id: String) { change { $0.selectedID = id } }
    public func setAppearance(_ appearance: ThemeAppearance) { change { $0.appearance = appearance } }

    /// One accent over every theme. Nil goes back to each theme's own.
    public func setAccent(_ hex: String?) {
        change { $0.setAccent(hex) }
    }

    /// Changes one colour of the showing theme. Nil puts the shipped colour back.
    public func setColor(_ key: ThemeColorKey, to hex: String?, for colorScheme: ColorScheme) {
        change { $0.setColor(key, to: hex, systemIsDark: colorScheme == .dark) }
    }

    /// Back to the selected theme as shipped: clears the quick accent and every changed colour.
    public func resetCustomisation() { change { $0.resetCustomisation() } }

    /// The showing theme as JSON, for copying to another device or saving to a file.
    public func exportJSON(for colorScheme: ColorScheme) -> String {
        settings.exportedJSON(systemIsDark: colorScheme == .dark)
    }

    /// Takes a theme from JSON and selects it. Throws `ThemeImportError.notATheme` if it can't be read.
    @discardableResult
    public func importJSON(_ json: String) throws -> PerchTheme {
        var copy = settings
        let palette = try copy.importTheme(json: json)
        if copy != settings {
            settings = copy
            save()
        }
        return PerchTheme(palette)
    }

    public func removeImported(id: String) { change { $0.removeImported(id: id) } }

    private func change(_ body: (inout ThemeSettings) -> Void) {
        var copy = settings
        body(&copy)
        guard copy != settings else { return }
        settings = copy
        save()
    }

    // MARK: Saving

    private static func read(_ defaults: UserDefaults) -> ThemeSettings {
        // Anything unreadable falls back to its default, so old or damaged settings never stop the app drawing.
        ThemeSettings(
            selectedID: defaults.string(forKey: Keys.selected) ?? ThemePresets.systemID,
            appearance: defaults.string(forKey: Keys.appearance).flatMap(ThemeAppearance.init) ?? .auto,
            accent: defaults.string(forKey: Keys.accent).flatMap { ThemeRGB(hex: $0)?.hex },
            overrides: defaults.string(forKey: Keys.overrides).map(ThemeSettings.overrides(savedJSON:)) ?? [:],
            imported: defaults.string(forKey: Keys.imported).map(ThemeSettings.importedThemes(savedJSON:)) ?? []
        )
    }

    private func save() {
        func json<Value: Encodable>(_ value: Value) -> String? {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) }
        }
        // Defaults are removed rather than written, so someone who never changes anything stores nothing.
        // Only what changed is written: dragging in a colour picker calls this many times a second.
        func set(_ value: String?, _ key: String) {
            guard defaults.string(forKey: key) != value else { return }
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        set(settings.selectedID == ThemePresets.systemID ? nil : settings.selectedID, Keys.selected)
        set(settings.appearance == .auto ? nil : settings.appearance.rawValue, Keys.appearance)
        set(settings.accent, Keys.accent)
        set(settings.overrides.isEmpty ? nil : json(settings.overrides), Keys.overrides)
        set(settings.imported.isEmpty ? nil : json(settings.imported), Keys.imported)
    }
}

// MARK: - Environment

private struct PerchThemeKey: EnvironmentKey {
    static let defaultValue = PerchTheme.dark
}

public extension EnvironmentValues {
    /// The theme to draw with. Set by `.perchThemed(_:)` at the root.
    var perchTheme: PerchTheme {
        get { self[PerchThemeKey.self] }
        set { self[PerchThemeKey.self] = newValue }
    }
}

private struct PerchThemed: ViewModifier {
    @ObservedObject var store: ThemeStore
    var paintsBackground: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let forced = store.preferredColorScheme
        let plain = store.theme(for: forced ?? colorScheme)
        // The Display choices (interface size, density) are applied here too, so one modifier sets up a window.
        PerchDisplayed { display in
            let theme = plain.with(display: display)
            content
                .environment(\.perchTheme, theme)
                .tint(theme.accent)
                .background { if paintsBackground { theme.background.ignoresSafeArea() } }
                // The theme's own light or dark setting wins over the window's, including for system controls.
                .transformEnvironment(\.colorScheme) { if let forced { $0 = forced } }
                .themeColorScheme(forced, theme: theme, paintsWindow: paintsBackground)
                // A change of theme, of one colour in it, or of the interface size cross-fades instead of snapping.
                .motion(Motion.smooth, value: theme)
        }
    }
}

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
/// On the Mac the window paints most of what you see behind a split view, so the theme has to reach
/// the window itself: its background colour, and its light or dark appearance.
private struct WindowThemeSetter: NSViewRepresentable {
    var theme: PerchTheme
    var forced: ColorScheme?
    var paintsBackground: Bool

    /// The windows a theme has pinned light or dark. Only these are handed back when the theme stops
    /// pinning, so a window Perch never pinned keeps whatever appearance it had.
    @MainActor private static let pinned = NSHashTable<NSWindow>.weakObjects()

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        let rgb = ThemeRGB(hex: theme.palette.background)
        let background = rgb.map { NSColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: 1) }
        let forced = forced
        let paintsBackground = paintsBackground
        // The view may not be in its window yet, and a window shouldn't change in the middle of a view update.
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            if let forced {
                let name: NSAppearance.Name = forced == .dark ? .darkAqua : .aqua
                if window.appearance?.name != name { window.appearance = NSAppearance(named: name) }
                Self.pinned.add(window)
            } else if Self.pinned.contains(window) {
                // Nil follows the app, which follows the Mac, so System keeps tracking light and dark live.
                window.appearance = nil
                Self.pinned.remove(window)
            }
            if paintsBackground, let background, window.backgroundColor != background { window.backgroundColor = background }
        }
    }
}
#endif

extension View {
    /// Pins the window light or dark when `forced` says so, and follows the device when it is nil.
    /// With `paintsWindow`, a Mac window's own background takes the theme's too.
    @ViewBuilder
    func themeColorScheme(_ forced: ColorScheme?, theme: PerchTheme, paintsWindow: Bool) -> some View {
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        // Not `preferredColorScheme` on the Mac: once it has pinned a window, passing nil doesn't let go,
        // and the app stays dark (or light) after going back to System. The window is set directly instead.
        background(WindowThemeSetter(theme: theme, forced: forced, paintsBackground: paintsWindow))
        #else
        preferredColorScheme(forced)
        #endif
    }
}

public extension View {
    /// Applies the user's theme to everything inside: puts it in the environment as `\.perchTheme`,
    /// tints controls with its accent, pins light or dark when the theme calls for it, and paints
    /// the main background. Use once at the root of each window.
    /// - Parameter paintsBackground: pass false for windows that should keep the system's own
    ///   background, such as the Mac settings window.
    func perchThemed(_ store: ThemeStore, paintsBackground: Bool = true) -> some View {
        modifier(PerchThemed(store: store, paintsBackground: paintsBackground))
    }
}
