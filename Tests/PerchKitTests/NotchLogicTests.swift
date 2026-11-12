import XCTest
@testable import PerchKit

final class NotchLogicTests: XCTestCase {
    private let closed = NotchOutline(width: 185, height: 32, topRadius: 6, bottomRadius: 9)
    private let open = NotchOutline(width: 852, height: 312, topRadius: 12, bottomRadius: 26)
    private let prompt = NotchOutline(width: 360, height: 84, neckWidth: 185, neckHeight: 32, topRadius: 6, bottomRadius: 18)

    private func task(_ title: String, due: String? = nil, time: String? = nil, remind: [String] = [], area: String = "Personal") -> PerchTask {
        var task = PerchTask(id: "t-" + title, path: "\(area)/Tasks/\(title).md", title: title)
        task.due = due
        task.time = time
        task.remind = remind
        return task
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Dublin")!
        return calendar
    }

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter.date(from: text)!
    }

    // MARK: Outline

    func testMixEndsAtItsEnds() {
        XCTAssertEqual(NotchOutline.mix(closed, open, 0), closed)
        XCTAssertEqual(NotchOutline.mix(closed, open, 1), open)
        let half = NotchOutline.mix(closed, open, 0.5)
        XCTAssertEqual(half.width, (185 + 852) / 2, accuracy: 0.001)
        XCTAssertEqual(half.height, (32 + 312) / 2, accuracy: 0.001)
    }

    func testOpeningNeverKinks() {
        // Through the whole opening, and a spring's overshoot either side, corners fit their edges.
        for step in -10...115 {
            let outline = NotchOutline.mix(closed, open, Double(step) / 100).resolved
            XCTAssertGreaterThanOrEqual(outline.top, 0)
            XCTAssertGreaterThanOrEqual(outline.bottom, 0)
            XCTAssertLessThanOrEqual(outline.top + outline.bottom, outline.height + 0.0001, "corners overlap at \(step)%")
            XCTAssertLessThanOrEqual(outline.bottom * 2, outline.width + 0.0001)
            XCTAssertFalse(outline.hasShoulder, "a plain notch opening has no shoulder")
        }
    }

    func testPromptGrowsAShoulderBelowTheMenuBar() {
        let outline = prompt.resolved
        XCTAssertTrue(outline.hasShoulder)
        XCTAssertEqual(outline.neckWidth, 185)
        XCTAssertEqual(outline.neckHeight, 32)
        XCTAssertEqual(outline.width, 360)
        for step in 0...100 {
            let between = NotchOutline.mix(closed, prompt, Double(step) / 100).resolved
            XCTAssertEqual(between.neckWidth, 185, accuracy: 0.001, "the neck keeps to the notch, so menus are never covered")
            if between.hasShoulder {
                let overhang = (between.width - between.neckWidth) / 2
                XCTAssertLessThanOrEqual(between.shoulderInner + between.shoulderOuter, overhang + 0.0001)
                XCTAssertLessThanOrEqual(between.shoulderOuter + between.bottom, between.height - between.neckHeight + 0.0001)
                XCTAssertLessThanOrEqual(between.top + between.shoulderInner, between.neckHeight + 0.0001)
            }
        }
    }

    func testPromptToOpenLosesItsShoulderSmoothly() {
        var last = Double.infinity
        for step in 0...100 {
            let between = NotchOutline.mix(prompt, open, Double(step) / 100)
            let overhang = (between.width - between.neckWidth) / 2
            XCTAssertLessThanOrEqual(overhang, last + 0.0001, "the shoulder only shrinks on the way to open")
            last = overhang
        }
        XCTAssertEqual(last, 0, accuracy: 0.0001)
    }

    func testNothingNegativeFromNonsense() {
        let outline = NotchOutline(width: -20, height: -4, neckWidth: 50, neckHeight: 90, topRadius: 40, bottomRadius: 40).resolved
        XCTAssertEqual(outline.width, 0)
        XCTAssertEqual(outline.height, 0)
        XCTAssertEqual(outline.top, 0)
        XCTAssertEqual(outline.bottom, 0)
    }

    func testAScreenWithoutANotchGrowsFromNothing() {
        let nothing = NotchOutline(width: 180, height: 0, topRadius: 6, bottomRadius: 9)
        XCTAssertEqual(nothing.resolved.height, 0)
        let started = NotchOutline.mix(nothing, open, 0.02).resolved
        XCTAssertGreaterThan(started.height, 0)
        XCTAssertLessThanOrEqual(started.top + started.bottom, started.height + 0.0001)
    }

    // MARK: Reveal

    func testContentWaitsForTheShape() {
        XCTAssertEqual(NotchReveal.amount(progress: 0, index: 0), 0)
        XCTAssertEqual(NotchReveal.amount(progress: 0.3, index: 0), 0, "the shape leads: nothing shows in a notch-sized sliver")
        XCTAssertEqual(NotchReveal.amount(progress: 1, index: 0), 1)
        XCTAssertEqual(NotchReveal.amount(progress: 1, index: 9), 1, "everything is in place when the opening ends, however many items")
    }

    func testContentArrivesInOrderAndNeverGoesBack() {
        for index in 0..<5 {
            var last = 0.0
            for step in 0...100 {
                let amount = NotchReveal.amount(progress: Double(step) / 100, index: index)
                XCTAssertGreaterThanOrEqual(amount, last)
                last = amount
            }
        }
        XCTAssertGreaterThan(NotchReveal.amount(progress: 0.5, index: 0), NotchReveal.amount(progress: 0.5, index: 2))
    }

    // MARK: Cards

    func testCardOrderSurvivesBadStorage() {
        XCTAssertEqual(NotchCardOrder.decode(nil), NotchCardOrder.standard)
        XCTAssertEqual(NotchCardOrder.decode(""), NotchCardOrder.standard)
        XCTAssertEqual(NotchCardOrder.decode("agents,today"), [.agents, .today, .focus, .notepad], "cards it doesn't mention go on the end")
        XCTAssertEqual(NotchCardOrder.decode("focus,focus,events, notepad"), [.focus, .notepad, .today, .agents])
        let order: [NotchCardKind] = [.notepad, .agents, .today, .focus]
        XCTAssertEqual(NotchCardOrder.decode(NotchCardOrder.encode(order)), order)
    }

    func testPanelSizeFollowsTheScreen() {
        XCTAssertEqual(NotchLayout.openSize(screenWidth: 1470).width, 853)
        XCTAssertEqual(NotchLayout.openSize(screenWidth: 2560).width, 880, "never wider than is comfortable")
        XCTAssertEqual(NotchLayout.openSize(screenWidth: 1024).width, 760)
        XCTAssertEqual(NotchLayout.openSize(screenWidth: 600).width, 552, "always leaves the screen's edges clear")
    }

    func testCardWidthsFillTheRow() {
        let order = NotchCardOrder.standard
        let widths = NotchLayout.widths(order, available: 824)
        let used = order.compactMap { widths[$0] }.reduce(0, +) + NotchLayout.cardSpacing * 3
        XCTAssertLessThanOrEqual(used, 824)
        XCTAssertGreaterThan(used, 820)
        XCTAssertGreaterThan(widths[.today]!, widths[.focus]!)
        XCTAssertEqual(widths[.focus], widths[.agents])
        let origins = NotchLayout.origins(order, widths: widths)
        XCTAssertEqual(origins[.today], 0)
        XCTAssertEqual(origins[.focus], widths[.today]! + NotchLayout.cardSpacing)
    }

    func testNarrowPanelsDropTheLastCards() {
        XCTAssertEqual(NotchLayout.visibleCards(NotchCardOrder.standard, available: 824), NotchCardOrder.standard)
        XCTAssertEqual(NotchLayout.visibleCards(NotchCardOrder.standard, available: 524), [.today, .focus, .notepad])
        XCTAssertEqual(NotchLayout.visibleCards([.agents, .today, .focus, .notepad], available: 370), [.agents, .today])
        XCTAssertEqual(NotchLayout.visibleCards(NotchCardOrder.standard, available: 60), [.today], "one card always shows")
    }

    func testWeekShowsAsManyDaysAsStayReadable() {
        XCTAssertEqual(NotchLayout.weekDays(available: 825, listWidth: 180), 7)
        XCTAssertEqual(NotchLayout.weekDays(available: 732, listWidth: 180), 6)
        XCTAssertEqual(NotchLayout.weekDays(available: 524, listWidth: 180), 3)
        XCTAssertEqual(NotchLayout.weekDays(available: 100, listWidth: 180), 3, "never fewer than three")
        XCTAssertEqual(NotchLayout.weekDays(available: 4000, listWidth: 180), 7)
    }

    func testDraggingACardReordersByNearestSlot() {
        let order = NotchCardOrder.standard
        let widths = NotchLayout.widths(order, available: 824)
        let origins = NotchLayout.origins(order, widths: widths)
        let focusCentre = origins[.focus]! + widths[.focus]! / 2
        XCTAssertEqual(NotchLayout.reordered(order, dragging: .focus, centerX: focusCentre, widths: widths), order, "held where it is, nothing moves")
        XCTAssertEqual(NotchLayout.reordered(order, dragging: .focus, centerX: 800, widths: widths), [.today, .notepad, .agents, .focus])
        XCTAssertEqual(NotchLayout.reordered(order, dragging: .focus, centerX: -40, widths: widths), [.focus, .today, .notepad, .agents])
        XCTAssertEqual(NotchLayout.reordered(order, dragging: .agents, centerX: origins[.notepad]! + 10, widths: widths), [.today, .focus, .agents, .notepad])
    }

    func testDraggingIsStableAcrossTheRow() {
        // Sweeping a card across the row moves it one place at a time and never backwards.
        let order = NotchCardOrder.standard
        let widths = NotchLayout.widths(order, available: 824)
        var lastIndex = 0
        for x in stride(from: 0.0, through: 824.0, by: 4) {
            let result = NotchLayout.reordered(order, dragging: .today, centerX: x, widths: widths)
            let index = result.firstIndex(of: .today)!
            XCTAssertGreaterThanOrEqual(index, lastIndex)
            XCTAssertLessThanOrEqual(index - lastIndex, 1)
            XCTAssertEqual(result.filter { $0 != .today }, [.focus, .notepad, .agents], "the other cards keep their order")
            lastIndex = index
        }
        XCTAssertEqual(lastIndex, 3)
    }

    func testMotionLevelFromStorage() {
        XCTAssertEqual(NotchMotionLevel(stored: nil), .full)
        XCTAssertEqual(NotchMotionLevel(stored: "subtle"), .subtle)
        XCTAssertEqual(NotchMotionLevel(stored: "off"), .off)
        XCTAssertEqual(NotchMotionLevel(stored: "wild"), .full)
    }

    func testTintsAreFourDifferentHuesFromTheAccent() {
        XCTAssertEqual(NotchTints.hue(of: ThemeRGB(red: 1, green: 0, blue: 0)), 0, accuracy: 0.01)
        XCTAssertEqual(NotchTints.hue(of: ThemeRGB(red: 0, green: 1, blue: 0)), 120, accuracy: 0.01)
        XCTAssertEqual(NotchTints.hue(of: ThemeRGB(red: 0, green: 0, blue: 1)), 240, accuracy: 0.01)
        XCTAssertEqual(NotchTints.hue(of: ThemeRGB(red: 0.5, green: 0.5, blue: 0.5)), 0)
        for accent in [0.0, 24, 215, 300, 359] {
            let hues = NotchCardKind.allCases.map { NotchTints.hue(for: $0, accentHue: accent) }
            XCTAssertEqual(hues[0], accent, "Today wears the accent itself")
            for (index, hue) in hues.enumerated() {
                XCTAssertTrue((0..<360).contains(hue))
                for other in hues[(index + 1)...] {
                    let apart = min(abs(hue - other), 360 - abs(hue - other))
                    XCTAssertGreaterThanOrEqual(apart, 30)
                }
            }
        }
    }

    // MARK: Reminders

    func testATimedTaskRingsAtItsTime() {
        let moments = TaskReminders.moments(for: task("Call", due: "2026-11-09", time: "16:30"), calendar: calendar)
        XCTAssertEqual(moments.count, 1)
        XCTAssertEqual(moments[0].key, "t-Call|2026-11-09T16:30")
        XCTAssertEqual(moments[0].date, date("2026-11-09T16:30"))
        XCTAssertTrue(TaskReminders.moments(for: task("No time", due: "2026-11-09"), calendar: calendar).isEmpty)
    }

    func testRemindEntriesReplaceTheDueTime() {
        let moments = TaskReminders.moments(for: task("Call", due: "2026-11-09", time: "16:30", remind: ["-15m", "2026-11-08T09:00"]), calendar: calendar)
        XCTAssertEqual(moments.map(\.date), [date("2026-11-09T16:15"), date("2026-11-08T09:00")])
        XCTAssertEqual(moments.map(\.key), ["t-Call|2026-11-09|-15m", "t-Call|2026-11-08T09:00"])
    }

    func testDoneTasksNeverRing() {
        var done = task("Call", due: "2026-11-09", time: "16:30")
        done.status = .done
        XCTAssertTrue(TaskReminders.moments(for: done, calendar: calendar).isEmpty)
    }

    func testDueRingsOnceAndSkipsWhatItSleptThrough() {
        let tasks = [
            task("Now", due: "2026-11-09", time: "16:30"),
            task("Later", due: "2026-11-09", time: "18:00"),
            task("Yesterday", due: "2026-11-08", time: "09:00"),
        ]
        let first = TaskReminders.due(tasks: tasks, now: date("2026-11-09T16:31"), fired: [], calendar: calendar)
        XCTAssertEqual(first.rings.map(\.title), ["Now"])
        XCTAssertEqual(first.rings.first?.detail, "Due at 16:30")
        XCTAssertEqual(Set(first.passed), ["t-Now|2026-11-09T16:30", "t-Yesterday|2026-11-08T09:00"], "the old one is remembered but stays quiet")
        let second = TaskReminders.due(tasks: tasks, now: date("2026-11-09T16:32"), fired: Set(first.passed), calendar: calendar)
        XCTAssertTrue(second.rings.isEmpty)
        XCTAssertTrue(second.passed.isEmpty)
    }

    func testATaskRingsOnceEvenWithTwoMomentsDue() {
        let both = task("Call", due: "2026-11-09", time: "16:30", remind: ["-15m", "-5m"])
        let result = TaskReminders.due(tasks: [both], now: date("2026-11-09T16:28"), fired: [], calendar: calendar)
        XCTAssertEqual(result.rings.count, 1)
        XCTAssertEqual(result.passed.count, 2)
    }

    // MARK: Prompt queue

    private func reminder(_ id: String) -> NotchPrompt {
        NotchPrompt(id: "r-" + id, kind: .reminder(taskID: id), title: id, detail: "Due at 16:30")
    }

    private func proposal(_ id: String) -> NotchPrompt {
        NotchPrompt(id: "p-" + id, kind: .proposal(taskID: id, agent: "claude"), title: id, detail: "claude says it's done")
    }

    func testPromptsShowOneAtATimeInOrder() {
        var queue = NotchPromptQueue()
        XCTAssertTrue(queue.enqueue(reminder("a")))
        XCTAssertTrue(queue.enqueue(reminder("b")))
        XCTAssertFalse(queue.enqueue(reminder("a")), "the same prompt isn't queued twice")
        XCTAssertFalse(queue.enqueue(reminder("b")))
        XCTAssertEqual(queue.current?.id, "r-a")
        XCTAssertEqual(queue.waiting.map(\.id), ["r-b"])
        queue.finishCurrent()
        XCTAssertEqual(queue.current?.id, "r-b")
        queue.finishCurrent()
        XCTAssertNil(queue.current)
        queue.finishCurrent()
        XCTAssertNil(queue.current)
    }

    func testRemindersGoAheadOfProposalsButNeverInterrupt() {
        var queue = NotchPromptQueue()
        queue.enqueue(proposal("x"))
        queue.enqueue(proposal("y"))
        queue.enqueue(reminder("a"))
        XCTAssertEqual(queue.current?.id, "p-x", "what's showing stays until it's answered")
        XCTAssertEqual(queue.waiting.map(\.id), ["r-a", "p-y"])
    }

    func testSnoozeComesBackAfterFiveMinutes() {
        var queue = NotchPromptQueue()
        let start = date("2026-11-09T16:30")
        queue.enqueue(reminder("a"))
        queue.snoozeCurrent(now: start)
        XCTAssertNil(queue.current)
        XCTAssertEqual(queue.nextWake, start.addingTimeInterval(300))
        XCTAssertFalse(queue.enqueue(reminder("a")), "a snoozed prompt isn't added again")
        queue.wake(now: start.addingTimeInterval(299))
        XCTAssertNil(queue.current)
        queue.wake(now: start.addingTimeInterval(300))
        XCTAssertEqual(queue.current?.id, "r-a")
        XCTAssertNil(queue.nextWake)
    }

    func testUnansweredReminderReturnsTwiceThenStops() {
        var queue = NotchPromptQueue()
        var now = date("2026-11-09T16:30")
        queue.enqueue(reminder("a"))
        for expected in [1, 0] {
            queue.timeOutCurrent(now: now)
            XCTAssertNil(queue.current)
            now = now.addingTimeInterval(300)
            queue.wake(now: now)
            XCTAssertEqual(queue.current?.repeatsLeft, expected)
        }
        queue.timeOutCurrent(now: now)
        XCTAssertNil(queue.current)
        XCTAssertTrue(queue.snoozed.isEmpty, "after two returns it gives up")
    }

    func testUnansweredProposalJustGoes() {
        var queue = NotchPromptQueue()
        queue.enqueue(proposal("x"))
        queue.timeOutCurrent(now: date("2026-11-09T16:30"))
        XCTAssertNil(queue.current)
        XCTAssertTrue(queue.snoozed.isEmpty)
    }

    func testCompletingATaskElsewhereClearsItsPrompts() {
        var queue = NotchPromptQueue()
        queue.enqueue(reminder("a"))
        queue.enqueue(proposal("a"))
        queue.enqueue(reminder("b"))
        queue.snoozeCurrent(now: date("2026-11-09T16:30"))
        queue.enqueue(reminder("c"))
        queue.removeAll(forTask: "a")
        XCTAssertEqual(queue.current?.id, "r-b")
        XCTAssertEqual(queue.waiting.map(\.id), ["r-c"])
        XCTAssertTrue(queue.snoozed.isEmpty)
        queue.removeAll(forTask: "b")
        XCTAssertEqual(queue.current?.id, "r-c", "removing the one showing brings up the next")
    }

    func testPruneDropsStalePrompts() {
        var queue = NotchPromptQueue()
        queue.enqueue(proposal("x"))
        queue.enqueue(proposal("y"))
        queue.enqueue(reminder("a"))
        queue.prune { prompt in
            if case .proposal = prompt.kind { return true }
            return false
        }
        XCTAssertEqual(queue.current?.id, "r-a")
        XCTAssertTrue(queue.waiting.isEmpty)
    }

    func testLifetimesAreSensible() {
        for prompt in [reminder("a"), proposal("x"), NotchPrompt(id: "f", kind: .focusFinished(taskID: nil), title: "Focus", detail: "25 min"), NotchPrompt(id: "e", kind: .event, title: "Standup", detail: "Starts 10:00")] {
            XCTAssertTrue((8...60).contains(prompt.lifetime))
        }
        XCTAssertEqual(reminder("a").repeatsLeft, 2)
        XCTAssertEqual(proposal("x").repeatsLeft, 0)
    }

    // MARK: Proposals

    func testOnlyNewProposalsPrompt() {
        var tracker = ProposalTracker()
        var first = task("One")
        first.proposedDoneBy = "claude"
        XCTAssertTrue(tracker.newProposals(in: [first, task("Two")]).isEmpty, "what was already proposed at launch waits quietly")
        var second = task("Two")
        second.proposedDoneBy = "codex"
        XCTAssertEqual(tracker.newProposals(in: [first, second]).map(\.title), ["Two"])
        XCTAssertTrue(tracker.newProposals(in: [first, second]).isEmpty)
        // Declined, then proposed again later: that is news.
        XCTAssertTrue(tracker.newProposals(in: [first, task("Two")]).isEmpty)
        XCTAssertEqual(tracker.newProposals(in: [first, second]).map(\.title), ["Two"])
    }

    // MARK: The day

    func testTodayIncludesOverdueAndOtherDaysDoNot() {
        var done = task("Done", due: "2026-11-09")
        done.status = .done
        done.completed = "2026-11-09"
        let tasks = [
            task("Old", due: "2026-11-01"), task("Today", due: "2026-11-09"), task("Tomorrow", due: "2026-11-10"),
            task("Work", due: "2026-11-09", area: "Work"), task("Someday"), done,
        ]
        XCTAssertEqual(NotchDay.open(tasks, day: "2026-11-09", today: "2026-11-09").map(\.title), ["Old", "Today", "Work"])
        XCTAssertEqual(NotchDay.open(tasks, day: "2026-11-10", today: "2026-11-09").map(\.title), ["Tomorrow"])
        XCTAssertEqual(NotchDay.open(tasks, day: "2026-11-09", today: "2026-11-09", area: "Work").map(\.title), ["Work"])
        XCTAssertEqual(NotchDay.done(tasks, day: "2026-11-09").map(\.title), ["Done"])
        XCTAssertTrue(NotchDay.done(tasks, day: "2026-11-09", area: "Work").isEmpty)
    }

    func testDayProgress() {
        XCTAssertEqual(NotchDay.progress(open: 0, done: 0), 0, "an empty day isn't a finished one")
        XCTAssertEqual(NotchDay.progress(open: 3, done: 1), 0.25)
        XCTAssertEqual(NotchDay.progress(open: 0, done: 4), 1)
    }

    // MARK: Review additions

    /// Every pair of states the notch moves between, well past both ends of a spring, stays drawable:
    /// finite numbers, nothing negative, and no corner larger than the edge it rounds.
    func testEveryTransitionSurvivesOvershoot() {
        let ears = NotchOutline(width: 185 + 108, height: 32, topRadius: 6, bottomRadius: 9)
        let peek = NotchOutline(width: 197, height: 35, topRadius: 6, bottomRadius: 12)
        let tab = NotchOutline(width: 185, height: 54, topRadius: 6, bottomRadius: 12)
        let sliver = NotchOutline(width: 180, height: 0, topRadius: 5, bottomRadius: 5)
        let stem = NotchOutline(width: 420, height: 76, neckWidth: 112, neckHeight: 24, topRadius: 6, bottomRadius: 18, shoulderRadius: 9)
        let narrowOpen = NotchOutline(width: 760, height: 312, topRadius: 10, bottomRadius: 24)
        let states = [closed, ears, peek, tab, sliver, prompt, stem, open, narrowOpen]
        for from in states {
            for to in states {
                for step in stride(from: -30, through: 130, by: 1) {
                    let r = NotchOutline.mix(from, to, Double(step) / 100).resolved
                    let label = "\(from) to \(to) at \(step)%"
                    for value in [r.width, r.height, r.neckWidth, r.neckHeight, r.top, r.shoulderInner, r.shoulderOuter, r.bottom] {
                        XCTAssertTrue(value.isFinite, label)
                        XCTAssertGreaterThanOrEqual(value, 0, label)
                    }
                    XCTAssertLessThanOrEqual(r.neckWidth, r.width + 0.0001, label)
                    XCTAssertLessThanOrEqual(r.neckHeight, r.height + 0.0001, label)
                    XCTAssertLessThanOrEqual(r.top * 2, r.neckWidth + 0.0001, label)
                    XCTAssertLessThanOrEqual(r.bottom * 2, r.width + 0.0001, label)
                    if r.hasShoulder {
                        let overhang = (r.width - r.neckWidth) / 2, depth = r.height - r.neckHeight
                        XCTAssertLessThanOrEqual(r.shoulderInner + r.shoulderOuter, overhang + 0.0001, label)
                        XCTAssertLessThanOrEqual(r.shoulderOuter + r.bottom, depth + 0.0001, label)
                        XCTAssertLessThanOrEqual(r.top + r.shoulderInner, r.neckHeight + 0.0001, label)
                    } else {
                        XCTAssertLessThanOrEqual(r.top + r.bottom, r.height + 0.0001, label)
                        XCTAssertEqual(r.shoulderInner + r.shoulderOuter, 0, label)
                    }
                }
            }
        }
    }

    func testNotANumberNeverReachesThePath() {
        let r = NotchOutline(width: .nan, height: 40, neckWidth: .nan, neckHeight: .infinity, topRadius: .nan, bottomRadius: .nan, shoulderRadius: .nan).resolved
        for value in [r.width, r.height, r.neckWidth, r.neckHeight, r.top, r.shoulderInner, r.shoulderOuter, r.bottom] {
            XCTAssertTrue(value.isFinite)
            XCTAssertGreaterThanOrEqual(value, 0)
        }
    }

    func testHiddenFocusLeavesTheRowAndKeepsItsPlace() {
        let saved: [NotchCardKind] = [.notepad, .focus, .today, .agents]
        let shown = NotchCardOrder.shown(saved, focusHidden: true)
        XCTAssertEqual(shown, [.notepad, .today, .agents])
        XCTAssertEqual(NotchCardOrder.shown(saved, focusHidden: false), saved)
        // The three that are left fill the whole row.
        let widths = NotchLayout.widths(shown, available: 824)
        XCTAssertEqual(widths.values.reduce(0, +) + 2 * NotchLayout.cardSpacing, 824, accuracy: 3)
        // Reordering them leaves Focus second, for when it is shown again.
        XCTAssertEqual(NotchCardOrder.merging([.agents, .notepad, .today], into: saved), [.agents, .focus, .notepad, .today])
        XCTAssertEqual(NotchCardOrder.merging(shown, into: saved), saved, "a drop that changes nothing saves nothing new")
        // A card that didn't fit keeps its place too.
        XCTAssertEqual(NotchCardOrder.merging([.focus, .today], into: NotchCardOrder.standard), [.focus, .today, .notepad, .agents])
    }

    func testMovingACardWithoutDragging() {
        let order = NotchCardOrder.standard
        XCTAssertEqual(NotchCardOrder.moved(order, .focus, by: -1), [.focus, .today, .notepad, .agents])
        XCTAssertEqual(NotchCardOrder.moved(order, .focus, by: 1), [.today, .notepad, .focus, .agents])
        XCTAssertEqual(NotchCardOrder.moved(order, .today, by: -1), order, "the first card can't go further left")
        XCTAssertEqual(NotchCardOrder.moved(order, .agents, by: 1), order)
        XCTAssertEqual(NotchCardOrder.moved([.today, .notepad], .focus, by: 1), [.today, .notepad], "a card that isn't shown doesn't move")
    }

    func testFocusIsHiddenUntilAskedFor() {
        let name = "perch.focus.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(FocusAvailability.hiddenKey, "focusHidden")
        XCTAssertTrue(FocusAvailability.isHidden(defaults), "hidden by default")
        XCTAssertFalse(FocusAvailability.isAvailable(defaults))
        defaults.set(false, forKey: FocusAvailability.hiddenKey)
        XCTAssertFalse(FocusAvailability.isHidden(defaults))
        XCTAssertTrue(FocusAvailability.isAvailable(defaults))
        defaults.set(true, forKey: FocusAvailability.hiddenKey)
        XCTAssertTrue(FocusAvailability.isHidden(defaults))
    }

    func testAReminderStopsApplyingWhenItsTaskChanges() {
        var call = task("Call", due: "2026-11-09", time: "16:30")
        let now = date("2026-11-09T16:31")
        let key = TaskReminders.moments(for: call, calendar: calendar)[0].key
        XCTAssertTrue(TaskReminders.stillApplies(key: key, to: call, now: now, calendar: calendar))
        XCTAssertFalse(TaskReminders.stillApplies(key: key, to: nil, now: now, calendar: calendar), "deleted")
        call.due = "2026-11-10"
        XCTAssertFalse(TaskReminders.stillApplies(key: key, to: call, now: now, calendar: calendar), "moved to tomorrow")
        call.due = "2026-11-09"
        call.time = "18:00"
        XCTAssertFalse(TaskReminders.stillApplies(key: key, to: call, now: now, calendar: calendar), "moved to later today")
        call.time = "16:30"
        call.status = .done
        XCTAssertFalse(TaskReminders.stillApplies(key: key, to: call, now: now, calendar: calendar), "completed")
    }

    func testARepeatingTaskCompletedOnceDropsItsReminder() {
        // Completing a repeating task moves its date on and leaves it open: the old reminder must not come back.
        var water = task("Water", due: "2026-11-09", time: "09:00")
        let key = TaskReminders.moments(for: water, calendar: calendar)[0].key
        water.due = "2026-11-10"
        XCTAssertFalse(TaskReminders.stillApplies(key: key, to: water, now: date("2026-11-09T09:06"), calendar: calendar))
        // And tomorrow's is a new reminder, not one already rung.
        let next = TaskReminders.due(tasks: [water], now: date("2026-11-10T09:00"), fired: [key], calendar: calendar)
        XCTAssertEqual(next.rings.count, 1)
    }

    func testRemindersAcrossClockChanges() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        // 02:30 doesn't exist on the night the clocks go forward: it still rings, at the first real moment after.
        let skipped = TaskReminders.moments(for: task("Skipped", due: "2026-03-08", time: "02:30"), calendar: newYork)
        XCTAssertEqual(skipped.count, 1)
        if let moment = skipped.first {
            let hour = newYork.component(.hour, from: moment.date)
            XCTAssertEqual(newYork.component(.day, from: moment.date), 8)
            XCTAssertTrue(hour == 3, "rings at \(hour) o'clock")
        }
        // 15 minutes before 03:10 that night is 01:55 on the clock, 15 real minutes earlier.
        let before = TaskReminders.moments(for: task("Before", due: "2026-03-08", time: "03:10", remind: ["-15m"]), calendar: newYork)
        XCTAssertEqual(newYork.dateComponents([.hour, .minute], from: before[0].date), DateComponents(hour: 1, minute: 55))
        // 01:30 happens twice when the clocks go back: one reminder, rung once.
        let twice = task("Twice", due: "2026-11-01", time: "01:30")
        let moments = TaskReminders.moments(for: twice, calendar: newYork)
        XCTAssertEqual(moments.count, 1)
        let first = TaskReminders.due(tasks: [twice], now: moments[0].date.addingTimeInterval(60), fired: [], calendar: newYork)
        XCTAssertEqual(first.rings.count, 1)
        let again = TaskReminders.due(tasks: [twice], now: moments[0].date.addingTimeInterval(3660), fired: Set(first.passed), calendar: newYork)
        XCTAssertTrue(again.rings.isEmpty)
    }

    func testTheSameWallClockTimeInAnotherZoneIsStillOneReminder() {
        // The key is the written date and time, so travelling doesn't ring yesterday's reminders again.
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let call = task("Call", due: "2026-11-09", time: "16:30")
        XCTAssertEqual(TaskReminders.moments(for: call, calendar: calendar)[0].key, TaskReminders.moments(for: call, calendar: tokyo)[0].key)
    }

    func testAfterARelaunchOldRemindersStayQuiet() {
        // Nothing saved as rung (a first launch, or the saved list was lost): only the last hour rings,
        // one prompt per task, and everything older is marked as rung without a sound.
        let tasks = (0..<40).map { task("Old \($0)", due: "2026-11-0\($0 % 8 + 1)", time: "10:00") }
            + [task("Recent", due: "2026-11-09", time: "16:00"), task("Just now", due: "2026-11-09", time: "16:29")]
        let due = TaskReminders.due(tasks: tasks, now: date("2026-11-09T16:30"), fired: [], calendar: calendar)
        XCTAssertEqual(due.rings.map(\.title), ["Recent", "Just now"])
        XCTAssertEqual(due.passed.count, 42)
        let second = TaskReminders.due(tasks: tasks, now: date("2026-11-09T16:31"), fired: Set(due.passed), calendar: calendar)
        XCTAssertTrue(second.rings.isEmpty)
        XCTAssertTrue(second.passed.isEmpty)
    }

    func testRememberedRingsForgetTheOldestFirst() {
        XCTAssertEqual(TaskReminders.remembered(["a", "b"], adding: ["b", "c"]), ["a", "b", "c"])
        XCTAssertEqual(TaskReminders.remembered(["a", "b", "c"], adding: ["d"], limit: 3), ["b", "c", "d"])
        XCTAssertEqual(TaskReminders.remembered([], adding: [], limit: 3), [])
    }

    func testSnoozedReminderIsPrunedWhenItsTaskMoves() {
        var call = task("Call", due: "2026-11-09", time: "16:30")
        let now = date("2026-11-09T16:30")
        let key = TaskReminders.moments(for: call, calendar: calendar)[0].key
        var queue = NotchPromptQueue()
        queue.enqueue(NotchPrompt(id: key, kind: .reminder(taskID: call.id), title: call.title, detail: ""))
        queue.snoozeCurrent(now: now)
        XCTAssertFalse(queue.isEmpty)
        call.due = "2026-11-12"
        let tasks = [call]
        queue.prune { prompt in
            guard case let .reminder(id) = prompt.kind else { return false }
            return !TaskReminders.stillApplies(key: prompt.id, to: tasks.first { $0.id == id }, now: now.addingTimeInterval(60), calendar: self.calendar)
        }
        XCTAssertTrue(queue.isEmpty)
        queue.wake(now: now.addingTimeInterval(400))
        XCTAssertNil(queue.current)
    }

    func testNextTimeUsesTheTwentyFourHourClock() {
        let tasks = [task("Morning", due: "2026-11-09", time: "09:00"), task("Evening", due: "2026-11-09", time: "18:15"), task("Tomorrow", due: "2026-11-10", time: "17:00")]
        XCTAssertEqual(NotchDay.clock(date("2026-11-09T16:05"), calendar: calendar), "16:05")
        // At five past four in the afternoon, nine in the morning has gone.
        XCTAssertEqual(NotchDay.nextTime(tasks, today: "2026-11-09", now: date("2026-11-09T16:05"), calendar: calendar), "18:15")
        XCTAssertEqual(NotchDay.nextTime(tasks, today: "2026-11-09", now: date("2026-11-09T08:00"), calendar: calendar), "09:00")
        XCTAssertNil(NotchDay.nextTime(tasks, today: "2026-11-09", now: date("2026-11-09T19:00"), calendar: calendar))
    }
}
