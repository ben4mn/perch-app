import Foundation

public enum TaskStatus: String, Codable, Sendable { case open, done, cancelled }

/// One task, stored as one Markdown file. NotesHub and GitHub show it as an ordinary note.
public struct PerchTask: Identifiable, Equatable, Sendable {
    public struct Activity: Equatable, Sendable {
        public var date: String
        public var author: String
        public var text: String
        public init(date: String, author: String, text: String) {
            self.date = date
            self.author = author
            self.text = text
        }
    }

    public var id: String
    public var path: String
    public var title: String
    public var status: TaskStatus = .open
    public var owner: String?
    public var due: String?
    public var time: String?
    public var deadline: String?
    public var recurrence: String?
    public var remind: [String] = []
    public var priority: Int = 4
    public var labels: [String] = []
    public var parent: String?
    public var durationMinutes: Int?
    public var created: String?
    public var completed: String?
    public var sourceID: String?
    public var proposedDoneBy: String?
    public var proposedDoneReason: String?
    /// When the agent proposed it, local time with offset, as the Relay writes it.
    public var proposedDoneAt: String?
    /// A link back to the session the proposal came from. See `Proposal.link`, which checks it.
    public var proposedDoneFrom: String?
    /// What the agent said it was doing at the time.
    public var proposedDoneWhile: String?
    public var details: String = ""
    public var activity: [Activity] = []

    /// Frontmatter keys Perch doesn't manage stay on the file untouched.
    var extraFields = FrontmatterFields()

    public init(id: String = TaskIDs.make(), path: String, title: String) {
        self.id = id
        self.path = path
        self.title = title
    }

    /// `✈️ Work/Tasks/x.md` belongs to the area `✈️ Work`.
    public var area: String {
        let parts = path.split(separator: "/").map(String.init)
        guard let index = parts.lastIndex(of: "Tasks"), index > 0 else { return parts.first ?? "" }
        return parts[..<index].joined(separator: "/")
    }

    public var isOpen: Bool { status == .open }

    public func isOverdue(today: String) -> Bool {
        guard isOpen, let due else { return false }
        return due < today
    }

    public func isDueTodayOrEarlier(today: String) -> Bool {
        guard isOpen, let due else { return false }
        return due <= today
    }

    public var isReadyToTick: Bool { isOpen && proposedDoneBy != nil }

    /// Forgets an agent's proposal, once the user has decided either way.
    public mutating func clearProposal() {
        proposedDoneBy = nil
        proposedDoneReason = nil
        proposedDoneAt = nil
        proposedDoneFrom = nil
        proposedDoneWhile = nil
    }
}

public enum TaskIDs {
    private static let alphabet = Array("23456789abcdefghjkmnpqrstuvwxyz")
    public static func make() -> String {
        "t" + String((0..<7).map { _ in alphabet.randomElement()! })
    }
}

public enum TaskFileError: Error, Equatable {
    case notATask
}

public enum TaskCodec {
    private static let activityHeading = "## Activity"

    /// A Markdown file is a task only if it declares both `id` and `status`.
    public static func decode(path: String, text: String) throws -> PerchTask {
        let document = MarkdownDocument(text: text)
        let fields = document.fields
        guard let id = fields["id"], let statusText = fields["status"], let status = TaskStatus(rawValue: statusText) else {
            throw TaskFileError.notATask
        }
        var task = PerchTask(id: id, path: path, title: fields["title"] ?? VaultFile(path: path).title)
        task.status = status
        task.owner = fields["owner"]
        task.due = fields["due"]
        task.time = fields["time"]
        task.deadline = fields["deadline"]
        task.recurrence = fields["repeat"]
        task.remind = fields.list("remind")
        task.priority = fields["priority"].flatMap(Int.init) ?? 4
        task.labels = fields.list("labels")
        task.parent = fields["parent"]
        task.durationMinutes = fields["duration"].flatMap(Int.init)
        task.created = fields["created"]
        task.completed = fields["completed"]
        task.sourceID = fields["source"]
        task.proposedDoneBy = fields["proposed_done_by"]
        task.proposedDoneReason = fields["proposed_done_reason"]
        task.proposedDoneAt = fields["proposed_done_at"]
        task.proposedDoneFrom = fields["proposed_done_from"]
        task.proposedDoneWhile = fields["proposed_done_while"]
        task.extraFields = fields

        let (details, activity) = splitBody(document.body)
        task.details = details
        task.activity = activity
        return task
    }

    public static func encode(_ task: PerchTask) -> String {
        var fields = task.extraFields
        // Perch-managed keys are rewritten in a stable order, after any unknown keys.
        for key in managedKeys { fields[key] = nil }
        fields["id"] = task.id
        fields["title"] = task.title
        fields["status"] = task.status.rawValue
        fields["owner"] = task.owner
        fields["due"] = task.due
        fields["time"] = task.time
        fields["deadline"] = task.deadline
        fields["repeat"] = task.recurrence
        fields.setList("remind", task.remind)
        fields["priority"] = task.priority == 4 ? nil : String(task.priority)
        fields.setList("labels", task.labels)
        fields["parent"] = task.parent
        fields["duration"] = task.durationMinutes.map(String.init)
        fields["created"] = task.created
        fields["completed"] = task.completed
        fields["source"] = task.sourceID
        fields["proposed_done_by"] = task.proposedDoneBy
        fields["proposed_done_reason"] = task.proposedDoneReason
        fields["proposed_done_at"] = task.proposedDoneAt
        fields["proposed_done_from"] = task.proposedDoneFrom
        fields["proposed_done_while"] = task.proposedDoneWhile

        var body = task.details
        if !task.activity.isEmpty {
            if !body.isEmpty { body += "\n\n" }
            body += activityHeading + "\n\n"
            body += task.activity.map(renderActivity).joined(separator: "\n")
        }
        if !body.isEmpty, !body.hasSuffix("\n") { body += "\n" }
        return fields.raw + body
    }

    private static let managedKeys = [
        "id", "title", "status", "owner", "due", "time", "deadline", "repeat", "remind", "priority",
        "labels", "parent", "duration", "created", "completed", "source", "proposed_done_by", "proposed_done_reason",
        "proposed_done_at", "proposed_done_from", "proposed_done_while",
    ]

    private static func renderActivity(_ item: PerchTask.Activity) -> String {
        let lines = item.text.components(separatedBy: "\n")
        var rendered = "- \(item.date) @\(item.author): \(lines[0])"
        for line in lines.dropFirst() { rendered += "\n  \(line)" }
        return rendered
    }

    private static func splitBody(_ body: String) -> (String, [PerchTask.Activity]) {
        let lines = splitLines(body)
        guard let headingIndex = lines.lastIndex(where: { jsTrim($0) == activityHeading }) else {
            return (trimTrailingNewlines(body), [])
        }
        let details = trimTrailingNewlines(lines[..<headingIndex].joined(separator: "\n"))
        var activity: [PerchTask.Activity] = []
        let pattern = LineRegex(#"^- (\d{4}-\d{2}-\d{2}[^ ]*) @([^:\s]+): (.*)$"#)
        for line in lines[(headingIndex + 1)...] {
            if let match = pattern.firstMatch(in: line) {
                activity.append(.init(date: match[1], author: match[2], text: match[3]))
            } else if line.hasPrefix("  "), !activity.isEmpty {
                activity[activity.count - 1].text += "\n" + line.dropFirst(2)
            } else if !jsTrim(line).isEmpty {
                // Text someone added by hand stays visible rather than being lost.
                activity.append(.init(date: "", author: "note", text: line))
            }
        }
        return (details, activity)
    }

    private static func trimTrailingNewlines(_ text: String) -> String {
        var result = text
        while result.hasSuffix("\n") || result.hasSuffix("\r") { result.removeLast() }
        return result
    }

    /// A readable file name that's safe on every platform and within NotesHub's rules.
    public static func fileName(title: String, id: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|#%[]^\n\r\t")
        var cleaned = String(String.UnicodeScalarView(title.unicodeScalars.map { forbidden.contains($0) ? " " : $0 }))
        cleaned = cleaned.split(separator: " ").joined(separator: " ")
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        if cleaned.count > 80 { cleaned = jsTrim(String(cleaned.prefix(80))) }
        while cleaned.hasSuffix(".") { cleaned.removeLast() }
        if cleaned.isEmpty { cleaned = "Task" }
        return "\(cleaned) \(id).md"
    }
}

/// Creates, changes, and lists tasks on top of a vault's plain files.
public struct TaskStore: Sendable {
    public let vault: Vault

    public init(vault: Vault) { self.vault = vault }

    public func loadAll() -> [PerchTask] {
        guard let files = try? vault.scan() else { return [] }
        return files.filter { $0.kind == .task }.compactMap { file in
            guard let text = try? vault.read(file.path) else { return nil }
            return try? TaskCodec.decode(path: file.path, text: text)
        }
    }

    public func save(_ task: PerchTask) throws {
        try vault.write(TaskCodec.encode(task), to: task.path)
    }

    @discardableResult
    public func create(
        title: String,
        area: String,
        configure: (inout PerchTask) -> Void = { _ in },
        today: Date = Date()
    ) throws -> PerchTask {
        let id = TaskIDs.make()
        let path = "\(area)/Tasks/\(TaskCodec.fileName(title: title, id: id))"
        var task = PerchTask(id: id, path: path, title: title)
        task.created = DayMath.string(from: today)
        configure(&task)
        try save(task)
        return task
    }

    /// True when completing this task needs a next date from the person, because Perch
    /// can't calculate its repeat rule.
    public func needsManualNextDate(_ task: PerchTask) -> Bool {
        guard let rule = task.recurrence else { return false }
        return !Recurrence.isSupported(rule)
    }

    /// Completes a task. A repeating task moves to its next date and stays open.
    /// `manualNextDue` supplies the date when the repeat rule can't be calculated.
    @discardableResult
    public func complete(_ task: PerchTask, by author: String = PerchConfiguration.main.ownerID, manualNextDue: String? = nil, today: Date = Date(), calendar: Calendar = .current) throws -> PerchTask {
        var updated = task
        let todayString = DayMath.string(from: today, calendar: calendar)
        updated.clearProposal()
        if let manualNextDue {
            updated.due = manualNextDue
            updated.activity.append(.init(date: todayString, author: author, text: "Completed; next due \(manualNextDue)."))
        } else if let rule = task.recurrence, let due = task.due, let next = Recurrence.next(rule: rule, after: due, calendar: calendar) {
            var nextDue = next
            // A repeating task that fell behind jumps to its next future date.
            while nextDue <= todayString, let later = Recurrence.next(rule: rule, after: nextDue, calendar: calendar) { nextDue = later }
            updated.due = nextDue
            updated.activity.append(.init(date: todayString, author: author, text: "Completed; next due \(nextDue)."))
        } else {
            updated.status = .done
            updated.completed = todayString
        }
        try save(updated)
        return updated
    }

    public func reopen(_ task: PerchTask) throws {
        var updated = task
        updated.status = .open
        updated.completed = nil
        try save(updated)
    }
}
