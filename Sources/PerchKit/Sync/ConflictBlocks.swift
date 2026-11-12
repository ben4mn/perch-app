import Foundation

/// NotesHub's conflict format, so both apps show and resolve conflicts the same way.
public enum ConflictBlocks {
    public static func wrap(remote: String, local: String) -> String {
        ":::conflict{variant=a}\n\(trimmed(remote))\n:::\n\n:::conflict{variant=d}\n\(trimmed(local))\n:::\n"
    }

    public static func contains(_ text: String) -> Bool { text.contains(":::conflict{variant=") }

    /// Turns Git's conflict markers into NotesHub blocks, keeping the merged parts around them.
    public static func fromGitMarkers(_ text: String) -> String {
        var output: [String] = []
        var ours: [String] = []
        var theirs: [String] = []
        enum State { case normal, ours, base, theirs }
        var state = State.normal
        for line in splitLines(text) {
            switch state {
            case .normal:
                if line.hasPrefix("<<<<<<< ") { state = .ours; ours = []; theirs = [] } else { output.append(line) }
            case .ours:
                if line.hasPrefix("||||||| ") { state = .base } else if line == "=======" { state = .theirs } else { ours.append(line) }
            case .base:
                if line == "=======" { state = .theirs }
            case .theirs:
                if line.hasPrefix(">>>>>>> ") {
                    output.append(wrap(remote: theirs.joined(separator: "\n"), local: ours.joined(separator: "\n")))
                    state = .normal
                } else {
                    theirs.append(line)
                }
            }
        }
        return output.joined(separator: "\n")
    }

    /// Keeps one variant of the conflict at `index`, counted in pairs, and removes the other.
    public static func resolve(_ text: String, blockIndex: Int, variant: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"^:::conflict\{variant=(\w+)\}\n([\s\S]*?)\n?^:::[ \t]*\n?\n?"#, options: [.anchorsMatchLines]) else { return text }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard blockIndex < matches.count else { return text }
        // Blocks come in adjacent groups. Find the group holding the chosen block.
        var groups: [[NSTextCheckingResult]] = []
        for match in matches {
            if let last = groups.last?.last, last.range.location + last.range.length == match.range.location {
                groups[groups.count - 1].append(match)
            } else {
                groups.append([match])
            }
        }
        let chosen = matches[blockIndex]
        guard let group = groups.first(where: { $0.contains(chosen) }),
              let first = group.first, let last = group.last,
              let start = Range(first.range, in: text), let end = Range(last.range, in: text),
              let body = Range(chosen.range(at: 2), in: text) else { return text }
        var result = text
        result.replaceSubrange(start.lowerBound..<end.upperBound, with: String(text[body]) + "\n")
        return result
    }

    private static func trimmed(_ text: String) -> String {
        var result = text
        while result.hasSuffix("\n") { result.removeLast() }
        return result
    }
}
