import Foundation

public struct FocusSession: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var start: Date
    public var seconds: Int
    public var taskID: String?

    public init(start: Date, seconds: Int, taskID: String? = nil) {
        self.start = start
        self.seconds = seconds
        self.taskID = taskID
    }
}

/// Focus history stays on this device, in app storage rather than your notes.
public final class FocusLog: @unchecked Sendable {
    private let url: URL
    public private(set) var sessions: [FocusSession] = []

    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([FocusSession].self, from: data) {
            sessions = saved
        }
    }

    public func add(_ session: FocusSession) {
        guard session.seconds >= 60 else { return }
        sessions.append(session)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(sessions).write(to: url, options: .atomic)
    }
}

public struct Insights: Equatable, Sendable {
    public struct Day: Equatable, Identifiable, Sendable {
        public var date: String
        public var completed: Int
        public var id: String { date }
    }

    public var open = 0
    public var overdue = 0
    public var completedThisWeek = 0
    public var streakDays = 0
    public var focusMinutesThisWeek = 0
    public var lastSevenDays: [Day] = []
    public var peakHour: Int?
    public var oldestOverdue: PerchTask?

    public static func compute(tasks: [PerchTask], focus: [FocusSession], today: Date = Date(), calendar: Calendar = .current) -> Insights {
        var result = Insights()
        let todayString = DayMath.string(from: today, calendar: calendar)
        let completions = Dictionary(grouping: tasks.compactMap(\.completed), by: { $0 })

        result.open = tasks.filter(\.isOpen).count
        let overdue = tasks.filter { $0.isOverdue(today: todayString) }.sorted { ($0.due ?? "") < ($1.due ?? "") }
        result.overdue = overdue.count
        result.oldestOverdue = overdue.first

        for offset in (0..<7).reversed() {
            let date = DayMath.adding(days: -offset, to: todayString, calendar: calendar) ?? todayString
            result.lastSevenDays.append(.init(date: date, completed: completions[date]?.count ?? 0))
        }
        result.completedThisWeek = result.lastSevenDays.map(\.completed).reduce(0, +)

        // Today can't break a streak until it's over.
        var cursor = (completions[todayString]?.isEmpty == false) ? todayString : (DayMath.adding(days: -1, to: todayString, calendar: calendar) ?? todayString)
        while completions[cursor]?.isEmpty == false {
            result.streakDays += 1
            guard let previous = DayMath.adding(days: -1, to: cursor, calendar: calendar) else { break }
            cursor = previous
        }

        let weekStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: today)) ?? today
        let recent = focus.filter { $0.start >= weekStart }
        result.focusMinutesThisWeek = recent.map(\.seconds).reduce(0, +) / 60
        var byHour: [Int: Int] = [:]
        for session in recent { byHour[calendar.component(.hour, from: session.start), default: 0] += session.seconds }
        result.peakHour = byHour.max { $0.value < $1.value }?.key
        return result
    }
}
