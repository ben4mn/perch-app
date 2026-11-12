import Foundation

/// An agent's proposal that one of the user's tasks can be closed, as the app shows it everywhere: in the
/// notch, Ready to tick, the task itself and the Board. Agents can't close the user's tasks; they propose,
/// and nothing changes until the user decides.
public struct Proposal: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The work is done.
        case done
        /// The task no longer needs doing: the meeting has passed, the ask went away. Agents say so by
        /// starting the reason with "Moot:".
        case noLongerNeeded
    }

    /// The agent's name as the user knows it: "Claude" for claude-code, or the agent's own name.
    public var agent: String
    public var kind: Kind
    public var reason: String?
    /// When it was proposed, when the Relay recorded it.
    public var date: Date?
    /// What the agent said it was doing at the time.
    public var during: String?
    /// Opens the session the proposal came from, for the apps Perch knows how to open.
    public var link: URL?

    public init(_ task: PerchTask) {
        agent = AgentHistory.displayName(for: task.proposedDoneBy ?? "An agent")
        var reason = task.proposedDoneReason?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let text = reason, text.lowercased().hasPrefix("moot:") {
            kind = .noLongerNeeded
            reason = String(text.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        } else {
            kind = .done
        }
        self.reason = reason?.isEmpty == true ? nil : reason
        date = task.proposedDoneAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        during = task.proposedDoneWhile?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        link = task.proposedDoneFrom.flatMap(SessionLink.url)
    }

    private var verdict: String { kind == .noLongerNeeded ? "thinks this is no longer needed" : "thinks this is done" }
    /// "Thinks this is done", for a line under the agent's name.
    public var headline: String { verdict.prefix(1).uppercased() + verdict.dropFirst() }
    /// "Claude thinks this is done", for a line on its own.
    public var sentence: String { "\(agent) \(verdict)" }
    /// Agreeing closes the task either way; the words say which kind of closing it is.
    public var acceptTitle: String { kind == .noLongerNeeded ? "Close task" : "Mark done" }
    public var declineTitle: String { "Keep open" }
    /// "Open the Claude session", when there is a session to open.
    public var linkTitle: String? { link.map(SessionLink.title) }
}

/// A link back to the session an agent was working in, in Claude or Codex.
public enum SessionLink {
    /// The link, if it is one Perch opens. A task file is plain text anyone can edit, so only a link to a
    /// Claude desktop session or a Codex thread, in exactly the form the Relay writes (and the form those
    /// apps accept), is ever opened from one.
    public static func url(_ text: String) -> URL? {
        let patterns = [
            #"^claude://code/continue\?session=local_[A-Za-z0-9-]{1,64}$"#,
            #"^codex://threads/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"#,
        ]
        guard patterns.contains(where: { text.range(of: $0, options: .regularExpression) != nil }) else { return nil }
        return URL(string: text)
    }

    public static func title(for url: URL) -> String {
        url.scheme == "codex" ? "Open the Codex thread" : "Open the Claude session"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
