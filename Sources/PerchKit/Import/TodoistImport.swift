import Foundation

/// The parts of Todoist's Sync API that the import uses. Unknown fields are ignored and
/// optional fields stay optional, so a small API change produces warnings instead of a crash.
public struct TodoistSnapshot: Codable, Equatable, Sendable {
    public struct Project: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var inbox_project: Bool?
        public var is_archived: Bool?
        public var is_deleted: Bool?
    }

    public struct Section: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var project_id: String
    }

    public struct Due: Codable, Equatable, Sendable {
        public var date: String
        public var string: String?
        public var is_recurring: Bool?
        public var timezone: String?
    }

    public struct Deadline: Codable, Equatable, Sendable {
        public var date: String
    }

    public struct Duration: Codable, Equatable, Sendable {
        public var amount: Int
        public var unit: String
    }

    public struct Item: Codable, Equatable, Sendable {
        public var id: String
        public var content: String
        public var description: String?
        public var project_id: String
        public var section_id: String?
        public var parent_id: String?
        public var labels: [String]?
        public var priority: Int?
        public var due: Due?
        public var deadline: Deadline?
        public var duration: Duration?
        public var child_order: Int?
        public var added_at: String?
        public var completed_at: String?
        public var checked: Bool?
        public var is_deleted: Bool?
    }

    public struct FileAttachment: Codable, Equatable, Sendable {
        public var file_name: String?
        public var file_url: String?
    }

    public struct Comment: Codable, Equatable, Sendable {
        public var id: String
        public var item_id: String
        public var content: String
        public var posted_at: String?
        public var posted_uid: String?
        public var is_deleted: Bool?
        public var file_attachment: FileAttachment?
    }

    public struct Reminder: Codable, Equatable, Sendable {
        public var id: String
        public var item_id: String
        public var type: String?
        public var due: Due?
        public var minute_offset: Int?
        public var is_deleted: Bool?
    }

    public var projects: [Project] = []
    public var sections: [Section] = []
    public var items: [Item] = []
    public var notes: [Comment] = []
    public var reminders: [Reminder] = []
    public var completed: [Item] = []

    public init() {}

    enum CodingKeys: String, CodingKey { case projects, sections, items, notes, reminders, completed }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projects = try container.decodeIfPresent([Project].self, forKey: .projects) ?? []
        sections = try container.decodeIfPresent([Section].self, forKey: .sections) ?? []
        items = try container.decodeIfPresent([Item].self, forKey: .items) ?? []
        notes = try container.decodeIfPresent([Comment].self, forKey: .notes) ?? []
        reminders = try container.decodeIfPresent([Reminder].self, forKey: .reminders) ?? []
        completed = try container.decodeIfPresent([Item].self, forKey: .completed) ?? []
    }
}

public struct TodoistImportOptions: Equatable, Sendable {
    /// The notebook's areas. A project with the same name as one (ignoring case and emoji) goes to it.
    public var areas: [String]
    /// Lowercase project name without emoji → vault area, ahead of `areas`; "inbox" names the Inbox.
    /// Anything else goes to `fallbackArea`, labeled with its project.
    public var areaByProject: [String: String]
    public var fallbackArea: String
    /// Labels that name who does a task. They become its owner.
    public var ownerLabels: Set<String>
    /// The person importing: the author of comments that came from no agent.
    public var ownerID: String
    /// Comments containing one of these came from an agent, even though Todoist shows your name.
    public var agentCommentPrefixes: [String: String]
    public var includeCompleted: Bool

    public init(
        areas: [String] = [],
        areaByProject: [String: String] = [:],
        fallbackArea: String = "Personal",
        ownerLabels: Set<String> = ["me", "claude", "pair"],
        ownerID: String = "me",
        agentCommentPrefixes: [String: String] = [:],
        includeCompleted: Bool = true
    ) {
        self.areas = areas
        self.areaByProject = areaByProject
        self.fallbackArea = fallbackArea
        self.ownerLabels = ownerLabels
        self.ownerID = ownerID
        self.agentCommentPrefixes = agentCommentPrefixes
        self.includeCompleted = includeCompleted
    }
}

public struct TodoistImportPlan: Sendable {
    public struct Summary: Equatable, Sendable {
        public var open = 0
        public var completed = 0
        public var subtasks = 0
        public var comments = 0
        public var reminders = 0
        public var repeating = 0
        public var withDetails = 0
        public var byArea: [String: Int] = [:]
        public var byOwner: [String: Int] = [:]
        public var byPriority: [Int: Int] = [:]
        public var alreadyImported = 0
    }

    public var tasks: [PerchTask] = []
    public var summary = Summary()
    public var warnings: [String] = []
}

public enum TodoistMapper {
    /// Builds the import without writing anything. `existing` makes a re-run safe.
    public static func plan(
        snapshot: TodoistSnapshot,
        existing: [PerchTask] = [],
        options: TodoistImportOptions = .init(),
        today: Date = Date()
    ) -> TodoistImportPlan {
        var plan = TodoistImportPlan()
        let projects = Dictionary(uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0) })
        let sections = Dictionary(uniqueKeysWithValues: snapshot.sections.map { ($0.id, $0) })
        let comments = Dictionary(grouping: snapshot.notes.filter { $0.is_deleted != true }, by: \.item_id)
        let reminders = Dictionary(grouping: snapshot.reminders.filter { $0.is_deleted != true }, by: \.item_id)
        let alreadyImported = Set(existing.compactMap(\.sourceID))

        var seen = Set<String>()
        var items: [TodoistSnapshot.Item] = []
        for item in snapshot.items where item.is_deleted != true {
            if seen.insert(item.id).inserted { items.append(item) }
        }
        if options.includeCompleted {
            for item in snapshot.completed where item.is_deleted != true {
                if seen.insert(item.id).inserted { items.append(item) }
            }
        }

        // Stable local IDs come from Todoist's, so subtasks can point to parents and re-runs match.
        func localID(_ todoistID: String) -> String { "td" + todoistID }

        for item in items {
            let source = "todoist:\(item.id)"
            if alreadyImported.contains(source) {
                plan.summary.alreadyImported += 1
                continue
            }
            let projectName = projects[item.project_id]?.name
            if projectName == nil { plan.warnings.append("Task “\(item.content)” points at an unknown project, so it goes to \(options.fallbackArea).") }
            let isInbox = projects[item.project_id]?.inbox_project == true
            let mappedArea = projectName.flatMap { options.areaByProject[simplified($0).lowercased()] }
                ?? (isInbox ? options.areaByProject["inbox"] : projectName.flatMap { name in options.areas.first { AreaList.isSame($0, name) } })
            let area = mappedArea ?? options.fallbackArea

            let id = localID(item.id)
            var task = PerchTask(id: id, path: "\(area)/Tasks/\(TaskCodec.fileName(title: item.content, id: id))", title: item.content)
            task.sourceID = source
            task.details = item.description ?? ""
            task.parent = item.parent_id.map(localID)
            task.created = item.added_at.map { String($0.prefix(10)) }

            var labels = item.labels ?? []
            // Owner labels match regardless of case, so "Alex" and "alex" are the same person.
            if let owner = labels.first(where: { options.ownerLabels.contains($0.lowercased()) }) {
                task.owner = owner.lowercased()
                labels.removeAll { options.ownerLabels.contains($0.lowercased()) }
            }
            // A project that folds into another area stays findable through a label.
            if let projectName, !isInbox, simplified(projectName).lowercased() != simplified(area).lowercased() {
                let label = simplified(projectName).lowercased()
                if !label.isEmpty, !labels.contains(label) { labels.append(label) }
            }
            if let sectionID = item.section_id, let section = sections[sectionID]?.name { labels.append("section/\(section)") }
            task.labels = labels

            // Todoist's API numbers priority backwards: 4 is P1, 1 is P4.
            if let priority = item.priority, (1...4).contains(priority) { task.priority = 5 - priority }

            if let due = item.due {
                let parts = due.date.split(separator: "T", maxSplits: 1).map(String.init)
                task.due = parts[0]
                if parts.count > 1 { task.time = String(parts[1].prefix(5)) }
                if due.is_recurring == true, let rule = due.string {
                    task.recurrence = rule
                    plan.summary.repeating += 1
                    if !Recurrence.isSupported(rule.lowercased()) {
                        plan.warnings.append("“\(item.content)” repeats “\(rule)”, which Perch doesn't calculate yet. Completing it will ask for the next date.")
                    }
                }
            }
            task.deadline = item.deadline?.date
            if let duration = item.duration {
                task.durationMinutes = duration.unit == "day" ? duration.amount * 1440 : duration.amount
            }

            for reminder in reminders[item.id] ?? [] {
                if let date = reminder.due?.date, !date.isEmpty {
                    task.remind.append(String(date.prefix(16)))
                } else if let offset = reminder.minute_offset, let due = item.due, due.date.contains("T") {
                    task.remind.append("-\(offset)m")
                } else {
                    plan.warnings.append("A reminder on “\(item.content)” couldn't be converted.")
                }
                plan.summary.reminders += 1
            }

            for comment in (comments[item.id] ?? []).sorted(by: { ($0.posted_at ?? "") < ($1.posted_at ?? "") }) {
                var text = comment.content
                if let file = comment.file_attachment, let url = file.file_url {
                    text += (text.isEmpty ? "" : "\n") + "[\(file.file_name ?? "Attachment")](\(url))"
                }
                let lower = text.lowercased()
                let author = options.agentCommentPrefixes.first { lower.contains($0.key) }?.value
                    ?? (lower.prefix(60).contains("triage") ? "triage-routine" : options.ownerID)
                task.activity.append(.init(date: String((comment.posted_at ?? "").prefix(10)), author: author, text: text))
                plan.summary.comments += 1
            }

            if item.checked == true || item.completed_at != nil {
                task.status = .done
                task.completed = item.completed_at.map { String($0.prefix(10)) }
                plan.summary.completed += 1
            } else {
                plan.summary.open += 1
            }
            if task.parent != nil { plan.summary.subtasks += 1 }
            if !task.details.isEmpty { plan.summary.withDetails += 1 }
            plan.summary.byArea[area, default: 0] += 1
            plan.summary.byOwner[task.owner ?? "(none)", default: 0] += 1
            plan.summary.byPriority[task.priority, default: 0] += 1
            plan.tasks.append(task)
        }

        // A subtask whose parent is missing would silently vanish from nested views.
        let knownIDs = Set(plan.tasks.map(\.id)).union(existing.map(\.id))
        for task in plan.tasks where task.parent != nil && !knownIDs.contains(task.parent!) {
            plan.warnings.append("“\(task.title)” has a parent that isn't in the import, so it will show as a top-level task.")
        }
        return plan
    }

    private static func simplified(_ name: String) -> String { QuickAdd.simplifiedArea(name) }

    @discardableResult
    public static func apply(_ plan: TodoistImportPlan, to vault: Vault) throws -> Int {
        let store = TaskStore(vault: vault)
        var written = 0
        for task in plan.tasks where !vault.exists(task.path) {
            try store.save(task)
            written += 1
        }
        return written
    }
}

/// Reads from Todoist only. It never creates, changes, or deletes anything there.
public struct TodoistClient: Sendable {
    public var token: String
    public var session: URLSession
    public var baseURL: URL

    public init(token: String, session: URLSession = .shared, baseURL: URL = URL(string: "https://api.todoist.com/api/v1")!) {
        self.token = token
        self.session = session
        self.baseURL = baseURL
    }

    public enum ClientError: Error, LocalizedError, Equatable {
        case invalidToken
        case http(Int, String)

        public var errorDescription: String? {
            switch self {
            case .invalidToken: return "Todoist rejected that API token. Copy it again from Settings → Integrations → Developer."
            case let .http(code, detail): return "Todoist returned HTTP \(code). \(detail)"
            }
        }
    }

    /// Fetches everything active in one call, then as much completed history as Todoist offers.
    public func fetchSnapshot(completedMonths: Int = 24, today: Date = Date(), warnings: inout [String]) async throws -> TodoistSnapshot {
        var request = URLRequest(url: baseURL.appendingPathComponent("sync"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"sync_token=*&resource_types=["projects","sections","items","notes","reminders"]"#.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!.utf8)
        var snapshot = try JSONDecoder().decode(TodoistSnapshot.self, from: try await send(request))

        // The completed-tasks endpoint is unverified against a live account, so a failure
        // only loses history. It never blocks importing your open tasks.
        do {
            snapshot.completed = try await fetchCompleted(months: completedMonths, today: today)
        } catch {
            warnings.append("Completed history wasn't imported: \(error.localizedDescription)")
        }
        return snapshot
    }

    private func fetchCompleted(months: Int, today: Date) async throws -> [TodoistSnapshot.Item] {
        struct Page: Decodable { var items: [TodoistSnapshot.Item]?; var next_cursor: String? }
        var items: [TodoistSnapshot.Item] = []
        let calendar = Calendar(identifier: .gregorian)
        let formatter = ISO8601DateFormatter()
        var until = today
        // Todoist limits each request's date range, so walk back three months at a time.
        for _ in 0..<max(1, months / 3) {
            guard let since = calendar.date(byAdding: .month, value: -3, to: until) else { break }
            var cursor: String?
            repeat {
                var components = URLComponents(url: baseURL.appendingPathComponent("tasks/completed/by_completion_date"), resolvingAgainstBaseURL: false)!
                components.queryItems = [
                    .init(name: "since", value: formatter.string(from: since)),
                    .init(name: "until", value: formatter.string(from: until)),
                    .init(name: "limit", value: "200"),
                ]
                if let cursor { components.queryItems?.append(.init(name: "cursor", value: cursor)) }
                var request = URLRequest(url: components.url!)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let page = try JSONDecoder().decode(Page.self, from: try await send(request))
                items += page.items ?? []
                cursor = page.next_cursor
            } while cursor != nil
            until = since
        }
        return items
    }

    private func send(_ request: URLRequest) async throws -> Data {
        for attempt in 0..<4 {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 || status == 403 { throw ClientError.invalidToken }
            if status == 429, attempt < 3 {
                let wait = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? Double(5 * (attempt + 1))
                try await Task.sleep(nanoseconds: UInt64(min(wait, 60) * 1_000_000_000))
                continue
            }
            guard (200..<300).contains(status) else {
                throw ClientError.http(status, String(decoding: data.prefix(200), as: UTF8.self))
            }
            return data
        }
        throw ClientError.http(429, "Rate limit didn't clear.")
    }
}
