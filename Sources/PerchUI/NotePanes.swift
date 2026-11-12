import CoreGraphics
import Foundation

/// How the editor and the preview line up when they sit side by side.
///
/// The editor's text starts below its format bar and its own inset; the preview's starts at the page's top
/// padding. Scroll sync puts the editor's top line at that padding on the page, so the two only stay level
/// when the padding is the editor's height. Beside the editor the preview is given exactly that; on its own
/// it goes back to the page's spacing.
enum NotePanes {
    static func editorTextTop(barHeight: CGFloat, insetTop: CGFloat) -> CGFloat { barHeight + insetTop }

    /// Sync runs both ways: the editor brings the preview along, and scrolling the preview brings the editor.
    /// The page marks the scrolls it makes itself (because the editor moved it), and those never move the
    /// editor back, so the two can't chase each other.
    static func editorFollowsPreview(byUser: Bool, syncing: Bool) -> Bool { byUser && syncing }

    /// The reader's appearance, with its top padding set for the arrangement. `previewTop` is the editor's
    /// text top while they are side by side, and nil otherwise. The padding goes with the reading styles,
    /// which the page applies last, and is always sent: the page keeps a variable it isn't told about.
    static func readerAppearance(_ base: [String: Any], previewTop: CGFloat?) -> [String: Any] {
        var payload = base
        var style = (base["style"] as? [String: String]) ?? [:]
        style["--perch-pad-top"] = previewTop.map { "\(Int($0.rounded()))px" } ?? ""
        payload["style"] = style
        return payload
    }
}
