import Foundation

/// What each agent did last, for the notch's Agents card when nobody is working right now.
///
/// Two sources: the notebook's Git history (every write an agent makes through the Relay is a commit
/// under its own name, with an address ending @perch.local), which lasts; and the Relay's recent events
/// (status lines, claims, messages), which are live but forgotten when the Relay restarts. Each agent
/// shows the newest thing from either.
public enum AgentHistory {
    public struct Commit: Equatable, Sendable {
        public var author: String
        public var email: String
        public var date: Date
        public var subject: String

        public init(author: String, email: String, date: Date, subject: String) {
            self.author = author
            self.email = email
            self.date = date
            self.subject = subject
        }
    }

    public struct Event: Equatable, Sendable {
        public var agent: String
        public var kind: String
        public var text: String
        public var path: String?
        public var date: Date

        public init(agent: String, kind: String, text: String, path: String?, date: Date) {
            self.agent = agent
            self.kind = kind
            self.text = text
            self.path = path
            self.date = date
        }
    }

    public struct Deed: Equatable, Sendable, Identifiable {
        public var agent: String
        public var text: String
        public var date: Date
        public var id: String { agent }

        public init(agent: String, text: String, date: Date) {
            self.agent = agent
            self.text = text
            self.date = date
        }
    }

    /// How an agent is drawn: one of a few marks, for the agents the build names (`PERCH_AGENT_MARKS`,
    /// read into `PerchConfiguration.agentMarks`; only Claude by default), or its initial.
    public enum Mark: Equatable, Sendable {
        /// Claude's spark.
        case claude
        /// A plain dot.
        case dot
        /// A house, for a home assistant.
        case house
        case initial(String)

        /// A mark by the name a build's configuration gives it.
        public init?(kind: String) {
            switch kind.lowercased() {
            case "claude": self = .claude
            case "dot": self = .dot
            case "house": self = .house
            default: return nil
            }
        }
    }

    public static let maximumAgents = 4

    /// The agent's newest deed, one per agent, newest first.
    public static func latest(commits: [Commit], events: [Event]) -> [Deed] {
        var newest: [String: Deed] = [:]
        func offer(_ deed: Deed) {
            if let current = newest[deed.agent], current.date >= deed.date { return }
            newest[deed.agent] = deed
        }
        for commit in commits where isAgent(email: commit.email) {
            offer(Deed(agent: commit.author, text: describe(subject: commit.subject), date: commit.date))
        }
        for event in events where !event.agent.isEmpty {
            offer(Deed(agent: event.agent, text: describe(event), date: event.date))
        }
        return newest.values.sorted { $0.date > $1.date }.prefix(maximumAgents).map { $0 }
    }

    /// The Relay commits as `<agent>@perch.local`; people commit with their own addresses.
    public static func isAgent(email: String) -> Bool { email.lowercased().hasSuffix("@perch.local") }

    /// A Relay commit subject as a short sentence.
    public static func describe(subject: String) -> String {
        let quoted: [(String, (String) -> String)] = [
            ("Add task: ", { "Added “\($0)”" }),
            ("Update task: ", { "Updated “\($0)”" }),
            ("Complete task: ", { "Completed “\($0)”" }),
            ("Propose done: ", { "Thinks “\($0)” is done" }),
        ]
        for (prefix, sentence) in quoted where subject.hasPrefix(prefix) { return sentence(String(subject.dropFirst(prefix.count))) }
        let files: [(String, String)] = [("Add card to ", "Added a card to "), ("Add to ", "Added to "), ("Create ", "Created "), ("Update ", "Edited ")]
        for (prefix, verb) in files where subject.hasPrefix(prefix) {
            let file = String(subject.dropFirst(prefix.count))
            if file.lowercased().hasSuffix(".md") { return verb + title(of: file) }
        }
        return subject
    }

    /// A Relay event as a short sentence.
    public static func describe(_ event: Event) -> String {
        let file = event.path.map(title(of:))
        switch event.kind {
        case "message": return "Left you a message: \(event.text)"
        case "claim": return file.map { "Working on \($0)" } ?? event.text
        case "release": return file.map { "Finished \($0)" } ?? event.text
        case "write":
            // The Relay's generic words for a write are only useful with the file's name.
            if let file, ["Edited", "Appended"].contains(event.text) { return "\(event.text) \(file)" }
            return event.text
        default: return event.text
        }
    }

    /// The mark for an agent: its own when the build names it, or its initial.
    public static func mark(for agent: String, marks: [String: Mark] = PerchConfiguration.main.agentMarks) -> Mark {
        if let name = configuredName(agent, in: marks), let mark = marks[name] { return mark }
        return .initial(String(agent.prefix(1)).uppercased())
    }

    /// An agent the build names is called by that name, capitalized; any other by its own name.
    public static func displayName(for agent: String, marks: [String: Mark] = PerchConfiguration.main.agentMarks) -> String {
        guard let name = configuredName(agent, in: marks) else { return agent }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// The name in `marks` an agent goes by: the same name in any case, or that name and a suffix after
    /// a hyphen, so "claude-code" and "Claude" are both "claude".
    private static func configuredName(_ agent: String, in marks: [String: Mark]) -> String? {
        let lowered = agent.lowercased()
        if marks[lowered] != nil { return lowered }
        return marks.keys.filter { lowered.hasPrefix($0 + "-") }.max { $0.count < $1.count }
    }

    /// A file's name without its folders or its Markdown, board or whiteboard ending.
    static func title(of path: String) -> String {
        var name = (path as NSString).lastPathComponent
        for suffix in [".kanban.md", ".excalidraw.svg", ".excalidraw", ".md"] where name.lowercased().hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
            break
        }
        return name
    }
}
