import Foundation

/// Turns Markdown that agents and people write into text fit for a one-line preview or a short caption.
public enum TaskText {
    /// Markdown as plain reading text: `[[Note|alias]]` becomes "alias", `[text](url)` becomes "text",
    /// and bold, italic, code, heading, quote and list marks are dropped.
    public static func plain(_ markdown: String) -> String {
        var text = simplifyingLinks(markdown)
        text = text.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?m)^\s{0,3}(#{1,6}\s+|>\s?|[-*+]\s+\[[ xX]\]\s+|[-*+]\s+|\d+[.)]\s+)"#, with: "", options: .regularExpression)
        for mark in ["**", "__", "~~", "`"] { text = text.replacingOccurrences(of: mark, with: "") }
        text = text.replacingOccurrences(of: #"(?<![\w*])[*_](\S(?:[^*_\n]*\S)?)[*_](?![\w*])"#, with: "$1", options: .regularExpression)
        return text
    }

    /// The first line with something to read, as plain text. Nil when there is none.
    public static func firstLine(_ markdown: String) -> String? {
        for line in markdown.components(separatedBy: "\n") {
            let cleaned = plain(line).trimmingCharacters(in: .whitespaces)
            if !cleaned.isEmpty, cleaned != "---" { return cleaned }
        }
        return nil
    }

    /// Wiki links written out as their visible text, leaving other Markdown alone, so the result can be
    /// handed to an inline Markdown renderer: `[[Folder/Note]]` becomes "Note", `[[Note|alias]]` becomes "alias".
    public static func simplifyingLinks(_ markdown: String) -> String {
        var result = ""
        var rest = Substring(markdown)
        while let open = rest.range(of: "[["), let close = rest[open.upperBound...].range(of: "]]") {
            result += rest[..<open.lowerBound]
            let inner = rest[open.upperBound..<close.lowerBound]
            if inner.contains("\n") {
                result += rest[open.lowerBound..<close.upperBound]
            } else if let bar = inner.firstIndex(of: "|") {
                result += inner[inner.index(after: bar)...].trimmingCharacters(in: .whitespaces)
            } else {
                let target = inner.split(separator: "#").first.map(String.init) ?? String(inner)
                result += (target as NSString).lastPathComponent
            }
            rest = rest[close.upperBound...]
        }
        return result + rest
    }
}

/// How a screen arranges itself for the room it has. Decided from the size alone, never the device,
/// so a folding phone, a rotated phone and a narrow Mac window all get the layout that fits.
public enum AdaptiveLayout {
    /// The narrowest width that gets a side-by-side or multi-column layout.
    public static let wideWidth: Double = 640
    /// The narrowest width where a month of task pills stays readable.
    public static let gridWidth: Double = 720
    /// Below this height a full month of pills has no room, as on a phone held sideways.
    public static let shortHeight: Double = 520

    public enum Month: Equatable, Sendable {
        /// Dots for each day, with the chosen day's tasks underneath.
        case stacked
        /// Dots for each day, with the chosen day's tasks beside the grid.
        case split
        /// Every day showing its tasks as pills.
        case grid
    }

    public static func month(width: Double, height: Double, compactWidthClass: Bool) -> Month {
        if width < wideWidth { return .stacked }
        if compactWidthClass || width < gridWidth || height < shortHeight { return .split }
        return .grid
    }

    public enum Week: Equatable, Sendable {
        /// The seven days one under another.
        case stacked
        /// The days in two or more columns of day lists.
        case tiled
        /// Seven columns side by side.
        case columns
    }

    /// From this width the week is seven columns whatever the size class says: an unfolded phone is
    /// "compact" to iOS but has the room.
    public static let weekColumnsWidth: Double = 860

    public static func week(width: Double, compactWidthClass: Bool) -> Week {
        if width < wideWidth { return .stacked }
        if width >= weekColumnsWidth { return .columns }
        if compactWidthClass || width < gridWidth { return .tiled }
        return .columns
    }

    /// Whether a folder with no saved choice shows a grid. Narrow touch screens get a list.
    public static func folderGrid(width: Double, prefersList: Bool) -> Bool {
        !prefersList || width >= wideWidth
    }
}
