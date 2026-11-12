import Foundation

/// The Board view of Tasks: open tasks in columns by when they are due, dragged between columns to
/// reschedule. The columns are the List view's date groups, so a task is in the same place in both.
///
/// Columns are by date and not by area, even with every area in scope, because a drop between date
/// columns only changes `due`, the one cheap and safe edit; a drop between areas would move the task's
/// file to another folder. The area is one tap away as the scope, and each card names its area.
public enum TaskBoard {
    public struct Column: Identifiable, Equatable, Sendable {
        public var kind: TaskCalendar.Group.Kind
        public var tasks: [PerchTask]
        /// The day a task dropped here moves to. Nil for a column that takes no drops (Overdue), and
        /// for No date, where `clearsDate` is set instead.
        public var dropDay: String?
        /// Dropping here removes the task's date.
        public var clearsDate: Bool

        public var id: String { TaskCalendar.Group(kind: kind, tasks: []).id }
        public var acceptsDrops: Bool { dropDay != nil || clearsDate }

        public var title: String {
            switch kind {
            case .overdue: return "Overdue"
            case .today: return "Today"
            case .tomorrow: return "Tomorrow"
            case .thisWeek: return "This week"
            case .later: return "Later"
            default: return "No date"
            }
        }
    }

    /// The board's columns, left to right. Today, Tomorrow, Later and No date are always there, so there
    /// is always somewhere to drop a task. Overdue shows only while something is overdue, and This week
    /// only while the week has days left after tomorrow.
    public static func columns(_ tasks: [PerchTask], today: String, calendar: Calendar = .current) -> [Column] {
        let tomorrow = DayMath.adding(days: 1, to: today, calendar: calendar)
        let dayAfter = DayMath.adding(days: 2, to: today, calendar: calendar)
        let weekEnd = TaskCalendar.week(containing: today, calendar: calendar).last ?? today
        let nextWeek = DayMath.adding(days: 1, to: weekEnd, calendar: calendar)
        let weekHasRoom = (dayAfter ?? "9") <= weekEnd

        let groups = TaskCalendar.groups(tasks, by: .due, sort: .due, today: today, calendar: calendar)
        var byKind: [TaskCalendar.Group.Kind: [PerchTask]] = [:]
        for group in groups { byKind[group.kind] = group.tasks }
        // Within a day, timed tasks come first; across the days of a column, the earlier day does.
        func ordered(_ kind: TaskCalendar.Group.Kind) -> [PerchTask] {
            (byKind[kind] ?? []).sorted { a, b in
                let (x, y) = (TaskCalendar.dayKey(a.due) ?? "", TaskCalendar.dayKey(b.due) ?? "")
                return x != y ? x < y : TaskCalendar.inDayOrder(a, b)
            }
        }

        var result: [Column] = []
        if let overdue = byKind[.overdue], !overdue.isEmpty {
            result.append(Column(kind: .overdue, tasks: ordered(.overdue), dropDay: nil, clearsDate: false))
        }
        result.append(Column(kind: .today, tasks: ordered(.today), dropDay: today, clearsDate: false))
        result.append(Column(kind: .tomorrow, tasks: ordered(.tomorrow), dropDay: tomorrow, clearsDate: false))
        if weekHasRoom {
            result.append(Column(kind: .thisWeek, tasks: ordered(.thisWeek), dropDay: dayAfter, clearsDate: false))
        }
        // A task dropped on Later lands on the first day after this week, or the day after tomorrow
        // when that is already next week.
        let laterDay = weekHasRoom ? nextWeek : dayAfter
        result.append(Column(kind: .later, tasks: ordered(.later), dropDay: laterDay, clearsDate: false))
        // Subtasks without a date follow their parent, as in the List; only top-level ones wait here.
        result.append(Column(kind: .noDate, tasks: TaskCalendar.undated(tasks), dropDay: nil, clearsDate: true))
        return result
    }

    /// What dropping a task on a column does.
    public enum Move: Equatable, Sendable {
        /// Nothing: the column takes no drops, or the task is already in it.
        case stay
        case day(String)
        case clearDate
    }

    /// What a drop does. A task already in the column stays on its own day: one due Thursday dropped
    /// on This week is still due Thursday.
    public static func move(_ task: PerchTask, to column: Column, today: String, calendar: Calendar = .current) -> Move {
        guard task.isOpen, column.acceptsDrops,
              TaskCalendar.dueKind(of: task, today: today, calendar: calendar) != column.kind else { return .stay }
        // A task whose date can't be read is shown under No date. Dropped back there it is left alone,
        // unreadable date and all; only a task with a real date has it cleared.
        if column.clearsDate { return .clearDate }
        guard let day = column.dropDay else { return .stay }
        return .day(day)
    }
}
