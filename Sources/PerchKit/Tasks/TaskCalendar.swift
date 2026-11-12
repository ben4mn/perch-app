import Foundation

/// The date arithmetic behind the task views: month grids, weeks, which day a task
/// lands on, how overdue it is, and how the Upcoming and List views group tasks.
///
/// Everything works on the same plain `yyyy-MM-dd` strings the task files use, and takes
/// the calendar as a parameter so it can be tested with any time zone or first weekday.
public enum TaskCalendar {
    // MARK: Days, weeks and months

    /// One cell of a month grid.
    public struct Day: Hashable, Sendable, Identifiable {
        public var date: String
        /// The day of the month, 1 to 31.
        public var number: Int
        /// False for the leading and trailing days borrowed from the months either side.
        public var inMonth: Bool
        public var isWeekend: Bool
        public var id: String { date }
    }

    /// The first day of the month `date` falls in.
    public static func monthStart(of date: String, calendar: Calendar = .current) -> String? {
        guard let value = DayMath.date(from: date, calendar: calendar) else { return nil }
        let parts = calendar.dateComponents([.year, .month], from: value)
        guard let year = parts.year, let month = parts.month else { return nil }
        return String(format: "%04d-%02d-01", year, month)
    }

    /// The first day of the month `months` away from the month `date` falls in.
    public static func addingMonths(_ months: Int, to date: String, calendar: Calendar = .current) -> String? {
        guard let start = monthStart(of: date, calendar: calendar),
              let value = DayMath.date(from: start, calendar: calendar),
              let moved = calendar.date(byAdding: .month, value: months, to: value) else { return nil }
        return DayMath.string(from: moved, calendar: calendar)
    }

    /// The seven days of the calendar week `date` falls in, starting on the calendar's first weekday.
    public static func week(containing date: String, calendar: Calendar = .current) -> [String] {
        guard let value = DayMath.date(from: date, calendar: calendar) else { return [] }
        let lead = (calendar.component(.weekday, from: value) - calendar.firstWeekday + 7) % 7
        guard let first = DayMath.adding(days: -lead, to: date, calendar: calendar) else { return [] }
        return (0..<7).compactMap { DayMath.adding(days: $0, to: first, calendar: calendar) }
    }

    /// The whole weeks that cover the month `date` falls in: four to six rows of seven days.
    public static func monthGrid(containing date: String, calendar: Calendar = .current) -> [[Day]] {
        guard let start = monthStart(of: date, calendar: calendar),
              let first = DayMath.date(from: start, calendar: calendar),
              let length = calendar.range(of: .day, in: .month, for: first)?.count,
              let gridStart = week(containing: start, calendar: calendar).first,
              let lead = daysBetween(gridStart, start, calendar: calendar) else { return [] }
        let month = start.prefix(7)
        let rows = (lead + length + 6) / 7
        return (0..<rows).map { row in
            (0..<7).compactMap { column in
                guard let day = DayMath.adding(days: row * 7 + column, to: gridStart, calendar: calendar),
                      let value = DayMath.date(from: day, calendar: calendar) else { return nil }
                return Day(
                    date: day, number: Int(day.suffix(2)) ?? 0,
                    inMonth: day.prefix(7) == month, isWeekend: calendar.isDateInWeekend(value)
                )
            }
        }
    }

    /// Weekday numbers (1 is Sunday) in the order the calendar shows them.
    public static func weekdayOrder(calendar: Calendar = .current) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    /// Whole calendar days from one date to another. Negative when `to` is earlier.
    public static func daysBetween(_ from: String, _ to: String, calendar: Calendar = .current) -> Int? {
        guard let start = DayMath.date(from: from, calendar: calendar),
              let end = DayMath.date(from: to, calendar: calendar) else { return nil }
        // Counted at midday so a 23 or 25 hour day around a clock change is still one day.
        let noonStart = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: start) ?? start
        let noonEnd = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: end) ?? end
        return calendar.dateComponents([.day], from: noonStart, to: noonEnd).day
    }

    // MARK: Reading and changing a task's day

    /// The `yyyy-MM-dd` day a `due` value names, or nil when there is none or it isn't a real date.
    /// Anything after the first ten characters (a time someone typed by hand, say) is ignored.
    ///
    /// Every planning view reads dates through this, so a hand-edited `due: soon` or `due: 2026-13-45`
    /// is treated as "no date" everywhere (the List's No date group and the Calendar's No date tray)
    /// instead of sorting by accident or disappearing.
    public static func dayKey(_ due: String?) -> String? {
        guard let due else { return nil }
        let bytes = Array(due.utf8.prefix(10))
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45 else { return nil }
        var numbers = [0, 0, 0]
        for (index, byte) in bytes.enumerated() where index != 4 && index != 7 {
            guard byte >= 48, byte <= 57 else { return nil }
            let part = index < 4 ? 0 : (index < 7 ? 1 : 2)
            numbers[part] = numbers[part] * 10 + Int(byte) - 48
        }
        let (year, month, day) = (numbers[0], numbers[1], numbers[2])
        guard (1...12).contains(month), day >= 1 else { return nil }
        let isLeap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let length = [31, isLeap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
        guard day <= length else { return nil }
        return due.utf8.count == 10 ? due : String(due.prefix(10))
    }

    /// The task as it should be saved after moving it to `day`, or to no date when `day` is nil.
    /// Only `due` changes: the time, repeat rule, reminders and deadline are left exactly as they were.
    /// Returns nil when there is nothing to save: the task isn't open, or it is already on that day.
    public static func rescheduled(_ task: PerchTask, to day: String?) -> PerchTask? {
        guard task.isOpen else { return nil }
        if let day {
            guard dayKey(day) != nil, dayKey(task.due) != day else { return nil }
        } else if task.due == nil {
            return nil
        }
        var moved = task
        moved.due = day
        return moved
    }

    // MARK: Overdue

    /// How many days late an open task is, or nil when it isn't overdue.
    public static func daysOverdue(_ task: PerchTask, today: String, calendar: Calendar = .current) -> Int? {
        guard task.isOpen, let due = dayKey(task.due), due < today,
              let days = daysBetween(due, today, calendar: calendar), days > 0 else { return nil }
        return days
    }

    /// "1 day overdue", "3 days overdue", "2 weeks overdue", "4 months overdue", "Over a year overdue".
    public static func overdueText(days: Int) -> String {
        switch days {
        case ..<1: return ""
        case 1: return "1 day overdue"
        case ..<14: return "\(days) days overdue"
        case ..<60: return "\(days / 7) weeks overdue"
        case ..<365: return "\(days / 30) months overdue"
        default: return "Over a year overdue"
        }
    }

    /// Open tasks whose date has passed, oldest first.
    public static func overdue(_ tasks: [PerchTask], today: String) -> [PerchTask] {
        tasks.filter { isOverdue($0, today: today) }.sorted { a, b in
            a.due != b.due ? (a.due ?? "") < (b.due ?? "") : inPriorityOrder(a, b)
        }
    }

    /// Open, with a real date before today. A `due` that isn't a date is never overdue; it counts as no date.
    public static func isOverdue(_ task: PerchTask, today: String) -> Bool {
        guard task.isOpen, let due = dayKey(task.due) else { return false }
        return due < today
    }

    // MARK: Buckets

    /// Open tasks keyed by their due day, each day in the order it should be read:
    /// timed tasks first by time, then by priority, then by title.
    public static func byDay(_ tasks: [PerchTask]) -> [String: [PerchTask]] {
        var days: [String: [PerchTask]] = [:]
        for task in tasks where task.isOpen {
            guard let day = dayKey(task.due) else { continue }
            days[day, default: []].append(task)
        }
        return days.mapValues { $0.sorted(by: inDayOrder) }
    }

    /// Open tasks waiting to be scheduled: top-level ones with no date, and any task whose `due`
    /// isn't a real date, so a mistyped date can be seen and fixed by moving the task onto a day.
    public static func undated(_ tasks: [PerchTask]) -> [PerchTask] {
        tasks.filter { $0.isOpen && ($0.due == nil ? $0.parent == nil : dayKey($0.due) == nil) }.sorted(by: inPriorityOrder)
    }

    public static func inDayOrder(_ a: PerchTask, _ b: PerchTask) -> Bool {
        switch (a.time.map(minutes), b.time.map(minutes)) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return inPriorityOrder(a, b)
        }
    }

    /// Minutes after midnight for "9:30", "09:30" or "16:30", so times sort by the clock and not as text.
    /// A time that can't be read sorts after the ones that can.
    static func minutes(_ time: String) -> Int {
        let parts = time.split(separator: ":").map { Int($0.prefix(2)) }
        guard let first = parts.first, let hour = first, (0...23).contains(hour) else { return Int.max }
        let minute = parts.count > 1 ? (parts[1] ?? 0) : 0
        return hour * 60 + min(max(minute, 0), 59)
    }

    /// Priority, then date (dated before undated), then title.
    public static func inPriorityOrder(_ a: PerchTask, _ b: PerchTask) -> Bool {
        if a.priority != b.priority { return a.priority < b.priority }
        return inDateOrder(a, b, thenPriority: false)
    }

    private static func inDateOrder(_ a: PerchTask, _ b: PerchTask, thenPriority: Bool) -> Bool {
        switch (a.due, b.due) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default:
            if thenPriority, a.priority != b.priority { return a.priority < b.priority }
            let order = a.title.localizedStandardCompare(b.title)
            return order == .orderedSame ? a.id < b.id : order == .orderedAscending
        }
    }

    // MARK: Upcoming

    /// One day in the Upcoming view.
    public struct UpcomingDay: Identifiable, Equatable, Sendable {
        public var date: String
        public var tasks: [PerchTask]
        /// Inside the day-by-day run straight after today, where empty days are shown too.
        public var isNearTerm: Bool
        /// Set to `yyyy-MM` on the first day of each later month, so the view can draw a month divider.
        public var monthHeading: String?
        public var id: String { date }
    }

    /// Future open tasks grouped by day. The next `nearDays` days are listed one by one, including
    /// empty ones when `includeEmptyNearDays` is set, so there is always somewhere to drop a task.
    /// Returns nothing at all when no task has a future date.
    public static func upcoming(
        _ tasks: [PerchTask], today: String, nearDays: Int = 7, includeEmptyNearDays: Bool = true,
        calendar: Calendar = .current
    ) -> [UpcomingDay] {
        let future = byDay(tasks).filter { $0.key > today }
        guard !future.isEmpty else { return [] }
        let near = (1...max(nearDays, 1)).compactMap { DayMath.adding(days: $0, to: today, calendar: calendar) }
        let nearSet = Set(near)
        var result: [UpcomingDay] = []
        for day in near where includeEmptyNearDays || future[day] != nil {
            result.append(UpcomingDay(date: day, tasks: future[day] ?? [], isNearTerm: true, monthHeading: nil))
        }
        var month = String((near.last ?? today).prefix(7))
        for day in future.keys.sorted() where !nearSet.contains(day) {
            let dayMonth = String(day.prefix(7))
            result.append(UpcomingDay(date: day, tasks: future[day] ?? [], isNearTerm: false, monthHeading: dayMonth == month ? nil : dayMonth))
            month = dayMonth
        }
        return result
    }

    // MARK: List groups

    public enum Grouping: String, CaseIterable, Sendable { case due, area, priority, none }
    public enum Sort: String, CaseIterable, Sendable { case priority, due, title, newest }

    public struct Group: Identifiable, Equatable, Sendable {
        public enum Kind: Hashable, Sendable {
            case overdue, today, tomorrow, thisWeek, later, noDate
            case area(String)
            case priority(Int)
            case all, completed
        }

        public var kind: Kind
        public var tasks: [PerchTask]

        public var id: String {
            switch kind {
            case .overdue: return "overdue"
            case .today: return "today"
            case .tomorrow: return "tomorrow"
            case .thisWeek: return "thisWeek"
            case .later: return "later"
            case .noDate: return "noDate"
            case let .area(name): return "area:" + name
            case let .priority(value): return "priority:\(value)"
            case .all: return "all"
            case .completed: return "completed"
        }
        }
    }

    /// Which date group an open task belongs to. "This week" is the rest of the calendar week after tomorrow,
    /// so it is empty on the week's last two days. A `due` that isn't a real date counts as no date.
    public static func dueKind(of task: PerchTask, today: String, calendar: Calendar = .current) -> Group.Kind {
        dueKind(
            of: task, today: today, tomorrow: DayMath.adding(days: 1, to: today, calendar: calendar),
            weekEnd: week(containing: today, calendar: calendar).last ?? today
        )
    }

    private static func dueKind(of task: PerchTask, today: String, tomorrow: String?, weekEnd: String) -> Group.Kind {
        guard let due = dayKey(task.due) else { return .noDate }
        if due < today { return .overdue }
        if due == today { return .today }
        if due == tomorrow { return .tomorrow }
        return due <= weekEnd ? .thisWeek : .later
    }

    /// The List view's groups, in display order, with empty groups left out. Cancelled tasks never appear;
    /// completed ones are gathered into a final group when `includeCompleted` is set.
    public static func groups(
        _ tasks: [PerchTask], by grouping: Grouping, sort: Sort, today: String,
        includeCompleted: Bool = false, areaOrder: [String] = [], calendar: Calendar = .current
    ) -> [Group] {
        let open = tasks.filter(\.isOpen)
        var groups: [Group] = []
        switch grouping {
        case .due:
            // The week's last day is worked out once, not once per task.
            let tomorrow = DayMath.adding(days: 1, to: today, calendar: calendar)
            let weekEnd = week(containing: today, calendar: calendar).last ?? today
            let buckets = Dictionary(grouping: open) { dueKind(of: $0, today: today, tomorrow: tomorrow, weekEnd: weekEnd) }
            for kind in [Group.Kind.overdue, .today, .tomorrow, .thisWeek, .later, .noDate] {
                if let list = buckets[kind] { groups.append(Group(kind: kind, tasks: list)) }
            }
        case .area:
            let buckets = Dictionary(grouping: open, by: \.area)
            let known = areaOrder.filter { buckets[$0] != nil }
            let rest = buckets.keys.filter { !known.contains($0) }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            for area in known + rest { groups.append(Group(kind: .area(area), tasks: buckets[area] ?? [])) }
        case .priority:
            let buckets = Dictionary(grouping: open, by: \.priority)
            for value in buckets.keys.sorted() { groups.append(Group(kind: .priority(value), tasks: buckets[value] ?? [])) }
        case .none:
            if !open.isEmpty { groups.append(Group(kind: .all, tasks: open)) }
        }
        groups = groups.map { Group(kind: $0.kind, tasks: sorted($0.tasks, by: sort)) }
        if includeCompleted {
            let done = tasks.filter { $0.status == .done }.sorted { a, b in
                a.completed != b.completed ? (a.completed ?? "") > (b.completed ?? "") : inPriorityOrder(a, b)
            }
            if !done.isEmpty { groups.append(Group(kind: .completed, tasks: done)) }
        }
        return groups
    }

    public static func sorted(_ tasks: [PerchTask], by sort: Sort) -> [PerchTask] {
        switch sort {
        case .priority: return tasks.sorted(by: inPriorityOrder)
        case .due: return tasks.sorted { inDateOrder($0, $1, thenPriority: true) }
        case .title:
            return tasks.sorted { a, b in
                let order = a.title.localizedStandardCompare(b.title)
                return order == .orderedSame ? a.id < b.id : order == .orderedAscending
            }
        case .newest:
            return tasks.sorted { a, b in
                a.created != b.created ? (a.created ?? "") > (b.created ?? "") : inPriorityOrder(a, b)
            }
        }
    }

    /// Done and total subtask counts for every task that has subtasks, built in one pass.
    public static func subtaskCounts(_ tasks: [PerchTask]) -> [String: SubtaskCount] {
        var counts: [String: SubtaskCount] = [:]
        for task in tasks {
            guard let parent = task.parent else { continue }
            counts[parent, default: SubtaskCount()].total += 1
            if !task.isOpen { counts[parent, default: SubtaskCount()].done += 1 }
        }
        return counts
    }

    public struct SubtaskCount: Equatable, Sendable {
        public var done = 0
        public var total = 0
        public init(done: Int = 0, total: Int = 0) {
            self.done = done
            self.total = total
        }
    }
}
