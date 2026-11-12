import PerchKit
import SwiftUI

// How big and how dense Perch draws itself. The choices are saved in UserDefaults on this device and
// never touch a note. The sums live in PerchKit (`DisplayMetrics`); this file saves the choices, hands
// them to every view, and makes the shared sizes in `Metrics` and `Font.perch…` follow them.
//
// How it reaches every screen:
//   1. `.perchThemed(_:)` at the root of each window reads the saved choices, stores them in
//      `PerchDisplay.current`, and carries them inside the theme in the environment.
//   2. `Metrics.…` and (on the Mac) `Font.perch…` are worked out from `PerchDisplay.current` each time
//      they are asked for, so no call site changes.
//   3. Because the choices travel inside `\.perchTheme`, every view that reads the theme is drawn again
//      when one changes. Nothing is rebuilt, so no screen loses its place.
//   4. On iPhone the fonts are the system's text styles, and the root sets the text size they follow:
//      the iPhone's own size (or the standard one), moved by the interface size.

/// The Display choices as views use them.
public struct PerchDisplay: Equatable, Sendable {
    public var metrics: DisplayMetrics
    /// Task rows show the first line of their details.
    public var showsTaskPreview: Bool
    /// Task rows show their date, area, label and other chips.
    public var showsTaskChips: Bool
    /// Screens 640 points wide or more may use side-by-side and grid layouts.
    public var allowsWideLayouts: Bool

    public init(metrics: DisplayMetrics = .standard, showsTaskPreview: Bool = true, showsTaskChips: Bool = true, allowsWideLayouts: Bool = true) {
        self.metrics = metrics
        self.showsTaskPreview = showsTaskPreview
        self.showsTaskChips = showsTaskChips
        self.allowsWideLayouts = allowsWideLayouts
    }

    public static let standard = PerchDisplay()

    /// What the windows are drawing with right now. Set by `.perchThemed(_:)` before anything inside it
    /// is drawn, and read by `Metrics` and the Mac's `Font.perch…`.
    ///
    /// It starts as the saved choices, so anything drawn before a themed window (or outside one) already
    /// has the right size. Every window reads the same saved choices, so they always agree on it.
    /// Views are drawn on the main thread and that is the only place this is read or set; setting it
    /// from anywhere else stops a debug build.
    public static var current: PerchDisplay {
        get { stored }
        set {
            assert(Thread.isMainThread, "PerchDisplay.current is only set while drawing, on the main thread")
            stored = newValue
        }
    }
    nonisolated(unsafe) private static var stored = DisplaySettings.saved()

    public var scale: CGFloat { CGFloat(metrics.scale) }

    /// The width to choose a layout for: the real one, or a phone's when wide layouts are off.
    public func layoutWidth(_ width: CGFloat) -> CGFloat {
        CGFloat(AdaptiveLayout.effectiveWidth(Double(width), allowsWide: allowsWideLayouts))
    }

    /// The text size the iPhone app draws with, given the size set in the iPhone's settings.
    public func textSize(system: DynamicTypeSize, matchSystem: Bool) -> DynamicTypeSize {
        let all = DynamicTypeSize.allCases
        let index = metrics.textSizeIndex(system: all.firstIndex(of: system) ?? DisplayMetrics.defaultTextSizeIndex, matchSystem: matchSystem)
        return all[min(index, all.count - 1)]
    }
}

/// The saved Display choices. Use as a plain property in a view: `private var display = DisplaySettings()`.
public struct DisplaySettings: DynamicProperty {
    /// The storage keys, for anything that needs to read or set them outside a view.
    public enum Key {
        /// "small", "default", "large" or "extraLarge".
        public static let interfaceSize = "displayInterfaceSize"
        /// "compact", "comfortable" or "roomy".
        public static let density = "displayDensity"
        /// iPhone: start from the text size set in the iPhone's settings.
        public static let matchSystemTextSize = "displayMatchSystemTextSize"
        /// iPhone: let wide screens use side-by-side and grid layouts.
        public static let wideLayouts = "displayWideLayouts"
        public static let taskPreview = "displayTaskPreview"
        public static let taskChips = "displayTaskChips"

        public static let all = [interfaceSize, density, matchSystemTextSize, wideLayouts, taskPreview, taskChips]
    }

    @AppStorage(Key.interfaceSize) public var interfaceSize = InterfaceSize.standard
    @AppStorage(Key.density) public var density = InterfaceDensity.comfortable
    @AppStorage(Key.matchSystemTextSize) public var matchSystemTextSize = true
    @AppStorage(Key.wideLayouts) public var wideLayouts = true
    @AppStorage(Key.taskPreview) public var taskPreview = true
    @AppStorage(Key.taskChips) public var taskChips = true

    public init() {}

    public var state: PerchDisplay {
        Self.display(size: interfaceSize, density: density, taskPreview: taskPreview, taskChips: taskChips, wideLayouts: wideLayouts)
    }

    private static func display(size: InterfaceSize, density: InterfaceDensity, taskPreview: Bool, taskChips: Bool, wideLayouts: Bool) -> PerchDisplay {
        #if os(iOS)
        let wide = wideLayouts
        #else
        // The Mac has no such setting: a wide window always gets the wide layouts.
        let wide = true
        #endif
        return PerchDisplay(
            metrics: DisplayMetrics(size: size, density: density),
            showsTaskPreview: taskPreview, showsTaskChips: taskChips, allowsWideLayouts: wide
        )
    }

    /// The saved choices read straight from UserDefaults, for before any view exists. The same answer
    /// `state` gives inside a view; a missing or unreadable value is its default.
    public static func saved(defaults: UserDefaults = .standard) -> PerchDisplay {
        func flag(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
        return display(
            size: defaults.string(forKey: Key.interfaceSize).flatMap(InterfaceSize.init) ?? .standard,
            density: defaults.string(forKey: Key.density).flatMap(InterfaceDensity.init) ?? .comfortable,
            taskPreview: flag(Key.taskPreview), taskChips: flag(Key.taskChips), wideLayouts: flag(Key.wideLayouts)
        )
    }

    public var isDefault: Bool {
        interfaceSize == .standard && density == .comfortable && matchSystemTextSize && wideLayouts && taskPreview && taskChips
    }

    /// Back to how Perch ships. Removes the saved values instead of writing defaults over them.
    public func reset() {
        interfaceSize = .standard
        density = .comfortable
        matchSystemTextSize = true
        wideLayouts = true
        taskPreview = true
        taskChips = true
        SettingsReset.remove(Key.all)
    }

    /// Steps the saved interface size from outside a view, for the Mac's zoom shortcuts. Zero goes back to Default.
    public static func stepSavedInterfaceSize(_ delta: Int, defaults: UserDefaults = .standard) {
        let current = defaults.string(forKey: Key.interfaceSize).flatMap(InterfaceSize.init) ?? .standard
        let next = delta == 0 ? InterfaceSize.standard : current.stepped(by: delta)
        guard next != current else { return }
        if next == .standard { defaults.removeObject(forKey: Key.interfaceSize) } else { defaults.set(next.rawValue, forKey: Key.interfaceSize) }
    }
}

/// Clearing saved settings. A removed key reads as its default, and leaves nothing behind in UserDefaults.
enum SettingsReset {
    static func remove(_ keys: [String], from defaults: UserDefaults = .standard) {
        for key in keys { defaults.removeObject(forKey: key) }
    }
}

private struct PerchDisplayKey: EnvironmentKey {
    static let defaultValue = PerchDisplay.standard
}

public extension EnvironmentValues {
    /// The Display choices, set by `.perchThemed(_:)` at the root. The same value as `perchTheme.display`;
    /// read this one in a view that sizes itself with `Metrics` or `Font.perch…` but uses no theme colour,
    /// so it is drawn again when the interface size or density changes.
    var perchDisplay: PerchDisplay {
        get { self[PerchDisplayKey.self] }
        set { self[PerchDisplayKey.self] = newValue }
    }
}

/// Reads the saved Display choices at the root of a window and applies them to everything inside.
struct PerchDisplayed<Inner: View>: View {
    private var settings = DisplaySettings()
    @Environment(\.dynamicTypeSize) private var systemTextSize
    var content: (PerchDisplay) -> Inner

    init(@ViewBuilder content: @escaping (PerchDisplay) -> Inner) { self.content = content }

    var body: some View {
        let display = settings.state
        // Set before anything inside is drawn: `Metrics` and the Mac fonts read it as they are asked for.
        let _ = (PerchDisplay.current = display)
        content(display)
            .environment(\.perchDisplay, display)
            #if os(iOS)
            .dynamicTypeSize(display.textSize(system: systemTextSize, matchSystem: settings.matchSystemTextSize))
            #else
            // System controls (pickers, toggles, fields) can't take a point size, so they step a size
            // up or down at the ends of the range.
            .controlSize(display.metrics.size == .extraLarge ? .large : display.metrics.size == .small ? .small : .regular)
            #endif
    }
}
