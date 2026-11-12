import Foundation

/// Which addresses from a note Perch hands to the system to open.
public enum ExternalLink {
    /// The same list the reader page's click listener passes out as `openExternal` (Web/src/render.js).
    public static let schemes: Set<String> = ["http", "https", "mailto"]

    /// True for a web page or an email address, whatever the letter case of its scheme. Everything else a note
    /// can link to goes nowhere: `tel:`, `file:`, `javascript:`, the app's own `perch-app:` and `perch-vault:`
    /// pages, any other app's scheme, and an address with no scheme at all.
    public static func opens(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return schemes.contains(scheme)
    }
}
