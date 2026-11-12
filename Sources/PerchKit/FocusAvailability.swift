import Foundation

/// Whether the focus timer is part of the app. It is hidden until someone asks for it in Settings,
/// and the Mac and the iPhone both read the answer here, so they agree on the default.
public enum FocusAvailability {
    /// The setting's key. True hides the timer everywhere: its notch card, the start buttons on tasks,
    /// the live timer beside the notch, its prompts and its figures in Insights.
    public static let hiddenKey = "focusHidden"
    /// What the setting is until someone changes it.
    public static let hiddenByDefault = true

    public static func isHidden(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: hiddenKey) == nil ? hiddenByDefault : defaults.bool(forKey: hiddenKey)
    }

    public static func isAvailable(_ defaults: UserDefaults = .standard) -> Bool { !isHidden(defaults) }
}
