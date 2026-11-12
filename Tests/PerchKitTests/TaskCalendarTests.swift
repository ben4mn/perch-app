import XCTest
@testable import PerchKit

final class TaskCalendarTests: XCTestCase {
    private func calendar(firstWeekday: Int = 2, zone: String = "Europe/Dublin") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func task(
        _ title: String, due: String? = nil, priority: Int = 4, status: TaskStatus = .open,
        area: String = "Personal", time: String? = nil, parent: String? = nil
    ) -> PerchTask {
        var task = PerchTask(id: "t-" + title, path: "\(area)/Tasks/\(title).md", title: title)
        task.due = due
        task.priority = priority
        task.status = status
        task.time = time
        task.parent = parent
        return task
    }

    // MARK: Month grid

    func testMonthGridMondayFirst() {
        let grid = TaskCalendar.monthGrid(containing: "2026-11-09", calendar: calendar(firstWeekday: 2))
        XCTAssertEqual(grid.count, 6, "November 2026 starts on a Sunday, so a Monday-first grid needs six weeks")
        XCTAssertTrue(grid.allSatisfy { $0.count == 7 })
        XCTAssertEqual(grid.first?.first?.date, "2026-10-26")
        XCTAssertEqual(grid.first?.last?.date, "2026-11-01")
        XCTAssertEqual(grid.last?.first?.date, "2026-11-30")
        XCTAssertEqual(grid.last?.last?.date, "2026-12-06")
        XCTAssertEqual(grid[0].map(\.inMonth), [false, false, false, false, false, false, true])
        XCTAssertEqual(grid[0].map(\.isWeekend), [false, false, false, false, false, true, true])
        XCTAssertEqual(grid.flatMap { $0 }.filter(\.inMonth).count, 30)
        XCTAssertEqual(grid[2][0].number, 9)
    }

    func testMonthGridSundayFirst() {
        let grid = TaskCalendar.monthGrid(containing: "2026-11-30", calendar: calendar(firstWeekday: 1))
        XCTAssertEqual(grid.count, 5)
        XCTAssertEqual(grid.first?.first?.date, "2026-11-01")
        XCTAssertEqual(grid.last?.last?.date, "2026-12-05")
        XCTAssertEqual(grid[0].map(\.isWeekend), [true, false, false, false, false, false, true])
    }

    func testFebruaryFitsFourWeeksAndLeapYearsHaveTwentyNineDays() {
        // February 2026 starts on a Sunday and has 28 days: exactly four Sunday-first weeks.
        let short = TaskCalendar.monthGrid(containing: "2026-02-14", calendar: calendar(firstWeekday: 1))
        XCTAssertEqual(short.count, 4)
        XCTAssertTrue(short.flatMap { $0 }.allSatisfy(\.inMonth))
        XCTAssertEqual(TaskCalendar.monthGrid(containing: "2026-02-14", calendar: calendar(firstWeekday: 2)).count, 5)

        let leap = TaskCalendar.monthGrid(containing: "2028-02-10", calendar: calendar(firstWeekday: 2)).flatMap { $0 }
        XCTAssertEqual(leap.filter(\.inMonth).count, 29)
        XCTAssertEqual(leap.filter(\.inMonth).last?.date, "2028-02-29")
        XCTAssertEqual(leap.last?.date, "2028-03-05")
        let plain = TaskCalendar.monthGrid(containing: "2027-02-10", calendar: calendar(firstWeekday: 2)).flatMap { $0 }
        XCTAssertEqual(plain.filter(\.inMonth).count, 28)
    }

    func testYearRollover() {
        let cal = calendar(firstWeekday: 2)
        let december = TaskCalendar.monthGrid(containing: "2026-12-31", calendar: cal)
        XCTAssertEqual(december.first?.first?.date, "2026-11-30")
        XCTAssertEqual(december.last?.last?.date, "2027-01-03")
        let january = TaskCalendar.monthGrid(containing: "2027-01-01", calendar: cal)
        XCTAssertEqual(january.first?.first?.date, "2026-12-28")
        XCTAssertEqual(TaskCalendar.addingMonths(1, to: "2026-12-31", calendar: cal), "2027-01-01")
        XCTAssertEqual(TaskCalendar.addingMonths(-1, to: "2027-01-15", calendar: cal), "2026-12-01")
        XCTAssertEqual(TaskCalendar.addingMonths(12, to: "2028-02-29", calendar: cal), "2029-02-01")
        XCTAssertEqual(TaskCalendar.monthStart(of: "2026-11-09", calendar: cal), "2026-11-01")
        XCTAssertEqual(TaskCalendar.week(containing: "2027-01-01", calendar: cal).first, "2026-12-28")
        XCTAssertEqual(TaskCalendar.week(containing: "2027-01-01", calendar: cal).last, "2027-01-03")
    }

    func testEveryGridRowIsSevenConsecutiveDaysAcrossAYear() {
        for firstWeekday in [1, 2, 7] {
            let cal = calendar(firstWeekday: firstWeekday, zone: "America/New_York")
            var month = "2026-01-01"
            for _ in 0..<24 {
                let days = TaskCalendar.monthGrid(containing: month, calendar: cal).flatMap { $0 }
                XCTAssertEqual(days.count % 7, 0)
                XCTAssertEqual(Set(days.map(\.date)).count, days.count, "no day repeats in \(month)")
                for (a, b) in zip(days, days.dropFirst()) {
                    XCTAssertEqual(DayMath.adding(days: 1, to: a.date, calendar: cal), b.date)
                }
                XCTAssertTrue(days.first!.inMonth || days[6].inMonth, "first row holds part of \(month)")
                XCTAssertTrue(days.last!.inMonth || days[days.count - 7].inMonth, "last row holds part of \(month)")
                month = TaskCalendar.addingMonths(1, to: month, calendar: cal)!
            }
        }
    }

    // MARK: Weeks

    func testWeekRespectsFirstWeekday() {
        XCTAssertEqual(
            TaskCalendar.week(containing: "2026-11-09", calendar: calendar(firstWeekday: 2)),
            ["2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-14", "2026-11-15"]
        )
        let sundayFirst = TaskCalendar.week(containing: "2026-11-09", calendar: calendar(firstWeekday: 1))
        XCTAssertEqual(sundayFirst.first, "2026-11-08")
        XCTAssertEqual(sundayFirst.last, "2026-11-14")
        // A Sunday belongs to the week ending that day when weeks start on Monday.
        XCTAssertEqual(TaskCalendar.week(containing: "2026-11-15", calendar: calendar(firstWeekday: 2)).first, "2026-11-09")
        XCTAssertEqual(TaskCalendar.weekdayOrder(calendar: calendar(firstWeekday: 2)), [2, 3, 4, 5, 6, 7, 1])
        XCTAssertEqual(TaskCalendar.weekdayOrder(calendar: calendar(firstWeekday: 1)), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(TaskCalendar.week(containing: "not a date", calendar: calendar()), [])
    }

    func testWeeksAroundClockChanges() {
        // Clocks go back in Dublin on 25 Oct 2026 and forward on 29 Mar 2026.
        let dublin = calendar(firstWeekday: 2)
        XCTAssertEqual(
            TaskCalendar.week(containing: "2026-10-25", calendar: dublin),
            ["2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22", "2026-10-23", "2026-10-24", "2026-10-25"]
        )
        XCTAssertEqual(
            TaskCalendar.week(containing: "2026-03-29", calendar: dublin),
            ["2026-03-23", "2026-03-24", "2026-03-25", "2026-03-26", "2026-03-27", "2026-03-28", "2026-03-29"]
        )
        XCTAssertEqual(TaskCalendar.daysBetween("2026-10-24", "2026-10-26", calendar: dublin), 2)
        XCTAssertEqual(TaskCalendar.daysBetween("2026-03-28", "2026-03-30", calendar: dublin), 2)
        XCTAssertEqual(TaskCalendar.daysBetween("2026-03-30", "2026-03-28", calendar: dublin), -2)

        // New York changes on 8 Mar and 1 Nov 2026; the grids must still be whole and in order.
        let newYork = calendar(firstWeekday: 1, zone: "America/New_York")
        XCTAssertEqual(
            TaskCalendar.week(containing: "2026-11-01", calendar: newYork),
            ["2026-11-01", "2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06", "2026-11-07"]
        )
        XCTAssertEqual(TaskCalendar.week(containing: "2026-03-10", calendar: newYork).first, "2026-03-08")
        XCTAssertEqual(TaskCalendar.daysBetween("2026-03-07", "2026-03-09", calendar: newYork), 2)

        // Clocks change at midnight in some places, so that day has no 00:00 at all.
        let santiago = calendar(firstWeekday: 2, zone: "America/Santiago")
        let september = TaskCalendar.monthGrid(containing: "2026-09-01", calendar: santiago).flatMap { $0 }
        XCTAssertEqual(september.filter(\.inMonth).count, 30)
        XCTAssertEqual(Set(september.map(\.date)).count, september.count)
        XCTAssertEqual(TaskCalendar.daysBetween("2026-09-01", "2026-09-30", calendar: santiago), 29)
    }

    // MARK: Overdue

    func testDaysOverdue() {
        let cal = calendar()
        let today = "2026-11-09"
        XCTAssertEqual(TaskCalendar.daysOverdue(task("a", due: "2026-11-06"), today: today, calendar: cal), 3)
        XCTAssertEqual(TaskCalendar.daysOverdue(task("b", due: "2026-11-08"), today: today, calendar: cal), 1)
        XCTAssertEqual(TaskCalendar.daysOverdue(task("c", due: "2026-10-20"), today: today, calendar: cal), 20, "counts across the clock change")
        XCTAssertEqual(TaskCalendar.daysOverdue(task("d", due: "2025-11-09"), today: today, calendar: cal), 365)
        XCTAssertNil(TaskCalendar.daysOverdue(task("e", due: today), today: today, calendar: cal))
        XCTAssertNil(TaskCalendar.daysOverdue(task("f", due: "2026-11-10"), today: today, calendar: cal))
        XCTAssertNil(TaskCalendar.daysOverdue(task("g"), today: today, calendar: cal))
        XCTAssertNil(TaskCalendar.daysOverdue(task("h", due: "2026-11-01", status: .done), today: today, calendar: cal), "finished tasks are never overdue")
    }

    func testOverdueWording() {
        XCTAssertEqual(TaskCalendar.overdueText(days: 0), "")
        XCTAssertEqual(TaskCalendar.overdueText(days: 1), "1 day overdue")
        XCTAssertEqual(TaskCalendar.overdueText(days: 3), "3 days overdue")
        XCTAssertEqual(TaskCalendar.overdueText(days: 13), "13 days overdue")
        XCTAssertEqual(TaskCalendar.overdueText(days: 14), "2 weeks overdue")
        XCTAssertEqual(TaskCalendar.overdueText(days: 59), "8 weeks overdue")
        XCTAssertEqual(TaskCalendar.overdueText(days: 60), "2 months overdue")
        XCTAssertEqual(TaskCalendar.overdueText(days: 364), "12 months overdue")
        XCTAssertEqual(TaskCalendar.overdueText(days: 365), "Over a year overdue")
    }

    func testOverdueListIsOldestFirstAndOpenOnly() {
        let tasks = [
            task("recent", due: "2026-11-08"), task("old", due: "2026-01-02"), task("today", due: "2026-11-09"),
            task("done", due: "2026-01-01", status: .done), task("undated"), task("urgent", due: "2026-11-08", priority: 1),
        ]
        XCTAssertEqual(TaskCalendar.overdue(tasks, today: "2026-11-09").map(\.title), ["old", "urgent", "recent"])
    }

    // MARK: Buckets

    func testByDayKeepsOpenDatedTasksInReadingOrder() {
        let tasks = [
            task("low", due: "2026-11-12"), task("high", due: "2026-11-12", priority: 1),
            task("afternoon", due: "2026-11-12", time: "15:00"), task("morning", due: "2026-11-12", priority: 3, time: "09:30"),
            task("done", due: "2026-11-12", status: .done), task("cancelled", due: "2026-11-12", status: .cancelled),
            task("other", due: "2026-11-13"), task("undated"),
        ]
        let days = TaskCalendar.byDay(tasks)
        XCTAssertEqual(Set(days.keys), ["2026-11-12", "2026-11-13"])
        XCTAssertEqual(days["2026-11-12"]?.map(\.title), ["morning", "afternoon", "high", "low"])
        XCTAssertEqual(days["2026-11-13"]?.map(\.title), ["other"])
    }

    func testUndatedLeavesOutSubtasksAndFinishedTasks() {
        let tasks = [
            task("b"), task("a", priority: 2), task("child", parent: "t-b"), task("done", status: .done), task("dated", due: "2026-11-12"),
        ]
        XCTAssertEqual(TaskCalendar.undated(tasks).map(\.title), ["a", "b"])
    }

    // MARK: Upcoming

    func testUpcomingListsTheNextWeekDayByDayThenLaterDaysWithMonthDividers() {
        let cal = calendar()
        let tasks = [
            task("today", due: "2026-11-09"), task("overdue", due: "2026-11-01"), task("undated"),
            task("tomorrow", due: "2026-11-10"), task("thursday b", due: "2026-11-12"), task("thursday a", due: "2026-11-12", priority: 2),
            task("edge", due: "2026-11-16"), task("later", due: "2026-11-20"), task("done", due: "2026-11-11", status: .done),
            task("december 1", due: "2026-12-03"), task("december 2", due: "2026-12-20"), task("march", due: "2027-03-01"),
        ]
        let days = TaskCalendar.upcoming(tasks, today: "2026-11-09", calendar: cal)
        XCTAssertEqual(days.map(\.date), [
            "2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-14", "2026-11-15", "2026-11-16",
            "2026-11-20", "2026-12-03", "2026-12-20", "2027-03-01",
        ])
        XCTAssertEqual(days.map(\.isNearTerm), [true, true, true, true, true, true, true, false, false, false, false])
        XCTAssertEqual(days.map { $0.tasks.count }, [1, 0, 2, 0, 0, 0, 1, 1, 1, 1, 1])
        XCTAssertEqual(days[2].tasks.map(\.title), ["thursday a", "thursday b"])
        XCTAssertEqual(days.map(\.monthHeading), [nil, nil, nil, nil, nil, nil, nil, nil, "2026-12", nil, "2027-03"])

        let compact = TaskCalendar.upcoming(tasks, today: "2026-11-09", includeEmptyNearDays: false, calendar: cal)
        XCTAssertEqual(compact.map(\.date), ["2026-11-10", "2026-11-12", "2026-11-16", "2026-11-20", "2026-12-03", "2026-12-20", "2027-03-01"])
    }

    func testUpcomingIsEmptyWithoutFutureTasksAndCrossesMonthEnds() {
        let cal = calendar()
        XCTAssertEqual(TaskCalendar.upcoming([task("today", due: "2026-11-09"), task("undated")], today: "2026-11-09", calendar: cal), [])

        // The day-by-day run crosses into December, so the first later day in December needs no divider.
        let days = TaskCalendar.upcoming(
            [task("a", due: "2026-11-30"), task("b", due: "2026-12-10"), task("c", due: "2027-01-02")], today: "2026-11-28", calendar: cal
        )
        XCTAssertEqual(days.first?.date, "2026-11-29")
        XCTAssertEqual(days.filter(\.isNearTerm).last?.date, "2026-12-05")
        XCTAssertEqual(days.filter { !$0.isNearTerm }.map(\.monthHeading), [nil, "2027-01"])
    }

    // MARK: List groups

    func testGroupsByDueDate() {
        // 9 Nov 2026 is a Monday; with Monday-first weeks the week ends on Sunday the 15th.
        let cal = calendar(firstWeekday: 2)
        let tasks = [
            task("no date"), task("later", due: "2026-11-16"), task("this week", due: "2026-11-15"), task("tomorrow", due: "2026-11-10"),
            task("today", due: "2026-11-09"), task("late", due: "2026-11-08"), task("very late", due: "2025-12-01", priority: 1),
            task("done", due: "2026-11-09", status: .done), task("cancelled", status: .cancelled),
        ]
        let groups = TaskCalendar.groups(tasks, by: .due, sort: .due, today: "2026-11-09", calendar: cal)
        XCTAssertEqual(groups.map(\.kind), [.overdue, .today, .tomorrow, .thisWeek, .later, .noDate])
        XCTAssertEqual(groups[0].tasks.map(\.title), ["very late", "late"])
        XCTAssertEqual(groups.map { $0.tasks.count }, [2, 1, 1, 1, 1, 1])
        XCTAssertEqual(Set(groups.map(\.id)).count, groups.count)

        // With Sunday-first weeks the week ends on Saturday the 14th, so the 15th is "later".
        let sundayFirst = TaskCalendar.groups(tasks, by: .due, sort: .due, today: "2026-11-09", calendar: calendar(firstWeekday: 1))
        XCTAssertEqual(sundayFirst.first { $0.kind == .later }?.tasks.map(\.title), ["this week", "later"])
        XCTAssertNil(sundayFirst.first { $0.kind == .thisWeek })

        // On the last day of the week, tomorrow is still "Tomorrow", not "Later".
        XCTAssertEqual(TaskCalendar.dueKind(of: task("x", due: "2026-11-16"), today: "2026-11-15", calendar: cal), .tomorrow)
        XCTAssertEqual(TaskCalendar.dueKind(of: task("x", due: "2026-11-17"), today: "2026-11-15", calendar: cal), .later)
        XCTAssertEqual(TaskCalendar.dueKind(of: task("x"), today: "2026-11-15", calendar: cal), .noDate)
    }

    func testGroupsByAreaPriorityAndNone() {
        let cal = calendar()
        let tasks = [
            task("zebra", priority: 3, area: "Personal"), task("apple", priority: 1, area: "Work"),
            task("mango", due: "2026-11-10", priority: 3, area: "Personal"), task("extra", area: "Archive"),
            task("finished", status: .done, area: "Work"),
        ]
        let areas = TaskCalendar.groups(tasks, by: .area, sort: .title, today: "2026-11-09", areaOrder: ["Work", "Personal", "Empty"], calendar: cal)
        XCTAssertEqual(areas.map(\.kind), [.area("Work"), .area("Personal"), .area("Archive")])
        XCTAssertEqual(areas[1].tasks.map(\.title), ["mango", "zebra"])

        let priorities = TaskCalendar.groups(tasks, by: .priority, sort: .priority, today: "2026-11-09", calendar: cal)
        XCTAssertEqual(priorities.map(\.kind), [.priority(1), .priority(3), .priority(4)])
        XCTAssertEqual(priorities[1].tasks.map(\.title), ["mango", "zebra"], "dated before undated within a priority")

        let flat = TaskCalendar.groups(tasks, by: .none, sort: .priority, today: "2026-11-09", includeCompleted: true, calendar: cal)
        XCTAssertEqual(flat.map(\.kind), [.all, .completed])
        XCTAssertEqual(flat[0].tasks.map(\.title), ["apple", "mango", "zebra", "extra"])
        XCTAssertEqual(flat[1].tasks.map(\.title), ["finished"])
        XCTAssertEqual(TaskCalendar.groups([], by: .none, sort: .priority, today: "2026-11-09", calendar: cal), [])
    }

    func testSortsAndSubtaskCounts() {
        var old = task("old", due: "2026-11-20")
        old.created = "2026-01-01"
        var new = task("new", due: "2026-11-10", priority: 2)
        new.created = "2026-11-01"
        let undated = task("undated", priority: 1)
        XCTAssertEqual(TaskCalendar.sorted([old, new, undated], by: .newest).map(\.title), ["new", "old", "undated"])
        XCTAssertEqual(TaskCalendar.sorted([old, new, undated], by: .due).map(\.title), ["new", "old", "undated"])
        XCTAssertEqual(TaskCalendar.sorted([old, new, undated], by: .priority).map(\.title), ["undated", "new", "old"])
        XCTAssertEqual(TaskCalendar.sorted([old, new, undated], by: .title).map(\.title), ["new", "old", "undated"])

        let family = [
            task("parent"), task("one", parent: "t-parent"), task("two", status: .done, parent: "t-parent"), task("loner"),
        ]
        XCTAssertEqual(TaskCalendar.subtaskCounts(family), ["t-parent": .init(done: 1, total: 2)])
    }

    // MARK: Review additions

    func testMonthGridSaturdayFirstAndRowCounts() {
        let saturday = calendar(firstWeekday: 7)
        let november = TaskCalendar.monthGrid(containing: "2026-11-09", calendar: saturday)
        XCTAssertEqual(november.count, 5)
        XCTAssertEqual(november.first?.first?.date, "2026-10-31")
        XCTAssertEqual(november.last?.last?.date, "2026-12-04")
        XCTAssertEqual(TaskCalendar.weekdayOrder(calendar: saturday), [7, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(TaskCalendar.week(containing: "2026-11-09", calendar: saturday), (7...13).map { String(format: "2026-11-%02d", $0) })

        // Four, five and six rows, for each first weekday.
        XCTAssertEqual(TaskCalendar.monthGrid(containing: "2026-02-10", calendar: calendar(firstWeekday: 1)).count, 4)
        XCTAssertEqual(TaskCalendar.monthGrid(containing: "2027-02-10", calendar: calendar(firstWeekday: 2)).count, 4)
        XCTAssertEqual(TaskCalendar.monthGrid(containing: "2026-08-10", calendar: calendar(firstWeekday: 7)).count, 5)
        XCTAssertEqual(TaskCalendar.monthGrid(containing: "2026-08-10", calendar: calendar(firstWeekday: 2)).count, 6)
        XCTAssertEqual(TaskCalendar.monthGrid(containing: "2026-05-10", calendar: calendar(firstWeekday: 1)).count, 6)
        // December into January, and stepping a month across the year end.
        let december = TaskCalendar.monthGrid(containing: "2026-12-31", calendar: calendar(firstWeekday: 2))
        XCTAssertEqual(december.last?.last?.date, "2027-01-03")
        XCTAssertEqual(TaskCalendar.addingMonths(1, to: "2026-12-31", calendar: calendar()), "2027-01-01")
        XCTAssertEqual(TaskCalendar.addingMonths(-1, to: "2027-01-15", calendar: calendar()), "2026-12-01")
        XCTAssertEqual(TaskCalendar.addingMonths(1, to: "2027-01-31", calendar: calendar()), "2027-02-01", "never skips a short month")
    }

    func testOnlyRealDatesCountAsDays() {
        XCTAssertEqual(TaskCalendar.dayKey("2026-11-09"), "2026-11-09")
        XCTAssertEqual(TaskCalendar.dayKey("2026-11-09T16:30"), "2026-11-09")
        XCTAssertEqual(TaskCalendar.dayKey("2028-02-29"), "2028-02-29")
        for bad in ["", "soon", "2026-1-5", "2026-13-01", "2026-02-30", "2027-02-29", "2026-11-00", "09/11/2026", "2026-11-9 ", "２０２６-11-09"] {
            XCTAssertNil(TaskCalendar.dayKey(bad), bad)
        }
        XCTAssertNil(TaskCalendar.dayKey(nil))
    }

    /// A task whose `due` was mistyped by hand must stay visible and never crash a view.
    func testMistypedDatesShowAsNoDateEverywhere() {
        let cal = calendar()
        let today = "2026-11-09"
        var child = task("child", due: "tomorrow-ish")
        child.parent = "t-parent"
        let tasks = [task("soon", due: "soon"), task("short", due: "2026-1-5"), task("feb", due: "2026-02-30"), task("empty", due: ""), child, task("ok", due: "2026-11-10")]

        XCTAssertEqual(TaskCalendar.byDay(tasks).keys.sorted(), ["2026-11-10"])
        XCTAssertEqual(Set(TaskCalendar.undated(tasks).map(\.title)), ["soon", "short", "feb", "empty", "child"], "the No date tray")
        XCTAssertEqual(TaskCalendar.overdue(tasks, today: today), [])
        XCTAssertNil(TaskCalendar.daysOverdue(tasks[1], today: today, calendar: cal))
        XCTAssertEqual(TaskCalendar.upcoming(tasks, today: today, calendar: cal).flatMap(\.tasks).map(\.title), ["ok"])
        let groups = TaskCalendar.groups(tasks, by: .due, sort: .due, today: today, calendar: cal)
        XCTAssertEqual(groups.map(\.id), ["tomorrow", "noDate"])
        XCTAssertEqual(groups.last?.tasks.count, 5, "the List's No date group")
        for sort in TaskCalendar.Sort.allCases {
            XCTAssertEqual(TaskCalendar.groups(tasks, by: .none, sort: sort, today: today, calendar: cal).first?.tasks.count, 6)
        }
    }

    func testTimesSortByTheClock() {
        let day = "2026-11-12"
        let tasks = [
            task("afternoon", due: day, time: "16:30"), task("unpadded", due: day, time: "9:30"), task("padded", due: day, time: "09:15"),
            task("midnight", due: day, time: "00:05"), task("odd", due: day, priority: 1, time: "after lunch"), task("untimed", due: day, priority: 1),
        ]
        XCTAssertEqual(TaskCalendar.byDay(tasks)[day]?.map(\.title), ["midnight", "padded", "unpadded", "afternoon", "odd", "untimed"])
        XCTAssertEqual(TaskCalendar.minutes("9:30"), TaskCalendar.minutes("09:30"))
    }

    func testThisWeekOnTheLastDaysOfTheWeek() {
        let cal = calendar(firstWeekday: 2)
        // Sunday 15 November is the last day of a Monday-first week: tomorrow is already next week.
        let sunday = "2026-11-15"
        XCTAssertEqual(TaskCalendar.dueKind(of: task("x", due: "2026-11-15"), today: sunday, calendar: cal), .today)
        XCTAssertEqual(TaskCalendar.dueKind(of: task("x", due: "2026-11-16"), today: sunday, calendar: cal), .tomorrow)
        XCTAssertEqual(TaskCalendar.dueKind(of: task("x", due: "2026-11-17"), today: sunday, calendar: cal), .later)
        XCTAssertEqual(TaskCalendar.dueKind(of: task("x", due: "2026-11-14"), today: sunday, calendar: cal), .overdue)
        // Saturday: tomorrow is the week's last day, so "This week" is empty rather than repeating it.
        let groups = TaskCalendar.groups([task("a", due: "2026-11-15"), task("b", due: "2026-11-16")], by: .due, sort: .due, today: "2026-11-14", calendar: cal)
        XCTAssertEqual(groups.map(\.id), ["tomorrow", "later"])
        // Friday: Sunday is still this week.
        XCTAssertEqual(TaskCalendar.dueKind(of: task("x", due: "2026-11-15"), today: "2026-11-13", calendar: cal), .thisWeek)
        // The same Sunday is the first day of a Sunday-first week.
        XCTAssertEqual(TaskCalendar.dueKind(of: task("x", due: "2026-11-21"), today: sunday, calendar: calendar(firstWeekday: 1)), .thisWeek)
    }

    func testOverdueWordingNeverSaysOneWeekOrOneMonthInThePlural() {
        XCTAssertEqual(TaskCalendar.overdueText(days: 6), "6 days overdue")
        XCTAssertEqual(TaskCalendar.overdueText(days: 7), "7 days overdue")
        XCTAssertEqual(TaskCalendar.overdueText(days: 21), "3 weeks overdue")
        XCTAssertEqual(TaskCalendar.overdueText(days: 27), "3 weeks overdue")
        XCTAssertEqual(TaskCalendar.overdueText(days: 90), "3 months overdue")
        for days in 1...400 {
            let text = TaskCalendar.overdueText(days: days)
            XCTAssertFalse(text.hasPrefix("1 weeks") || text.hasPrefix("1 months") || text.hasPrefix("0 "), text)
        }
    }
}
