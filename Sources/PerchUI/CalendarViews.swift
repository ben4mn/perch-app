import PerchKit
import SwiftUI

/// Tasks on a month or week calendar, dragged between days to reschedule.
///
/// Everything shown is derived from `model.tasks` on each update, and the only state kept here is
/// which period is showing, keyed by date strings, so the model's background reloads can't strand it.
struct CalendarScreen: View {
    @Environment(\.perchTheme) private var theme
    @ObservedObject var model: AppModel
    /// Opens in this mode without changing the saved one. The old Week planner uses "week".
    var startMode: String?
    /// "month" or "week". Stored so the app reopens in the mode you left.
    @AppStorage("calendarMode") private var storedMode = "month"
    /// Which tray is open above the calendar: "overdue", "nodate" or neither.
    @AppStorage("calendarTray") private var openTray = ""
    @State private var localMode: String?
    /// A day inside the period on show. Empty means "whichever period holds today".
    @State private var anchor = ""
    @State private var change = Change.swap
    @State private var selectedDay: String?
    @State private var moving: PerchTask?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass

    private enum Change: Equatable {
        case swap
        case slide(Edge)
    }

    private var mode: String {
        let value = startMode == nil ? storedMode : (localMode ?? startMode ?? "month")
        return value == "week" ? "week" : "month"
    }

    private var current: String { anchor.isEmpty ? model.today : anchor }

    /// The first day of the month or week on show: the identity of what's on screen.
    private var periodKey: String {
        if mode == "week" { return TaskCalendar.week(containing: current).first ?? current }
        return TaskCalendar.monthStart(of: current) ?? current
    }

    var body: some View {
        let plan = CalendarPlan(model: model)
        let actions = CalendarActions(model: model, reduceMotion: reduceMotion) { moving = $0 }
        // The layout follows the room there is, not the device: a folded phone, an unfolded one,
        // a phone on its side and a narrow Mac window each get what fits.
        GeometryReader { geometry in
            let isNarrow = theme.display.layoutWidth(geometry.size.width) < AdaptiveLayout.wideWidth
            VStack(spacing: 0) {
                header(today: plan.today)
                CalendarTray(plan: plan, actions: actions, open: $openTray, isCompact: isNarrow)
                    .padding(.horizontal, isNarrow ? Metrics.gap : Metrics.screenPadding)
                    .padding(.bottom, 10)
                GeometryReader { area in
                    ZStack {
                        period(plan: plan, actions: actions, size: area.size)
                            .id(mode + ":" + periodKey)
                            .transition(change == .swap ? .perchSwap(reduceMotion: reduceMotion) : .perchSlide(from: slideEdge, reduceMotion: reduceMotion))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                }
            }
        }
        // Pills and cards arrive, leave and change day together, whatever moved them.
        .motion(Motion.smooth, value: model.tasks.filter(\.isOpen).map { $0.id + ($0.due ?? "") })
        .perchScreenBackground()
        .navigationTitle(TaskScope.title(view: .calendar, area: model.taskScope))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $moving) { MoveTaskSheet(model: model, task: $0) }
    }

    private var slideEdge: Edge {
        if case let .slide(edge) = change { return edge }
        return .trailing
    }

    @ViewBuilder
    private func period(plan: CalendarPlan, actions: CalendarActions, size: CGSize) -> some View {
        let compactClass = sizeClass == .compact
        if mode == "week" {
            let days = TaskCalendar.week(containing: current)
            switch AdaptiveLayout.week(width: theme.display.layoutWidth(size.width), compactWidthClass: compactClass) {
            case .stacked: CompactWeekView(days: days, plan: plan, actions: actions, tiled: false)
            case .tiled: CompactWeekView(days: days, plan: plan, actions: actions, tiled: true)
            case .columns: WeekColumnsView(days: days, plan: plan, actions: actions)
            }
        } else {
            let grid = TaskCalendar.monthGrid(containing: current)
            switch AdaptiveLayout.month(width: theme.display.layoutWidth(size.width), height: size.height, compactWidthClass: compactClass) {
            case .stacked: CompactMonthView(grid: grid, plan: plan, actions: actions, selected: $selectedDay, sideBySide: false)
            case .split: CompactMonthView(grid: grid, plan: plan, actions: actions, selected: $selectedDay, sideBySide: true)
            case .grid: MonthGridView(grid: grid, plan: plan, actions: actions)
            }
        }
    }

    // MARK: Header

    private func header(today: String) -> some View {
        let title = mode == "week" ? DayLabel.span(TaskCalendar.week(containing: current), today: today) : DayLabel.month(current)
        let showsToday = mode == "week"
            ? TaskCalendar.week(containing: current).contains(today)
            : TaskCalendar.monthStart(of: current) == TaskCalendar.monthStart(of: today)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Metrics.gap) {
                titleText(title)
                Spacer(minLength: Metrics.gap)
                navigation(showsToday: showsToday)
                modePicker.frame(width: 170)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    titleText(title)
                    Spacer(minLength: Metrics.gap)
                    navigation(showsToday: showsToday)
                }
                modePicker
            }
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, headerTop)
        .padding(.bottom, 10)
    }

    private var headerTop: CGFloat {
        #if os(iOS)
        8
        #else
        20
        #endif
    }

    /// The month or week, with the area in scope beside it: "November 2026  Personal".
    private func titleText(_ title: String) -> some View {
        let period = Text(title)
            .font(.perchTitle)
            .foregroundStyle(theme.text)
            .lineLimit(1)
            .contentTransition(.opacity)
            .motion(Motion.quick, value: title)
        return Group {
            if let area = model.taskScope {
                // The month comes first. Where both don't fit (large text on a phone) the area's name
                // gives way: the bar above already shows which area is in scope.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        period.fixedSize()
                        Text(QuickAdd.simplifiedArea(area))
                            .font(.perchBody.weight(.medium))
                            .foregroundStyle(Palette.area(area, theme: theme))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    period.minimumScaleFactor(0.7)
                }
                .transition(.opacity)
            } else {
                period.minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.taskScope.map { "\(title), \(QuickAdd.simplifiedArea($0))" } ?? title)
        .accessibilityAddTraits(.isHeader)
    }

    private func navigation(showsToday: Bool) -> some View {
        HStack(spacing: 2) {
            Button { step(-1) } label: { Image(systemName: "chevron.left").frame(width: navSize + 2, height: navSize).contentShape(Rectangle()) }
                .help(mode == "week" ? "Previous week" : "Previous month")
                .accessibilityLabel(mode == "week" ? "Previous week" : "Previous month")
            Button(action: goToToday) {
                Text("Today").font(.perchChip).padding(.horizontal, 8).frame(height: navSize).contentShape(Rectangle())
            }
            .disabled(showsToday)
            .opacity(showsToday ? 0.45 : 1)
            .help("Jump to today")
            Button { step(1) } label: { Image(systemName: "chevron.right").frame(width: navSize + 2, height: navSize).contentShape(Rectangle()) }
                .help(mode == "week" ? "Next week" : "Next month")
                .accessibilityLabel(mode == "week" ? "Next week" : "Next month")
        }
        .buttonStyle(PerchPressStyle())
        .font(.perchChip.weight(.semibold))
        .foregroundStyle(theme.text)
        .padding(2)
        .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).fill(theme.wash))
    }

    private var navSize: CGFloat {
        #if os(iOS)
        Metrics.scaled(34)
        #else
        Metrics.scaled(24)
        #endif
    }

    private var modePicker: some View {
        Picker("View", selection: Binding(get: { mode }, set: setMode)) {
            Text("Month").tag("month")
            Text("Week").tag("week")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: Moving around

    private func step(_ amount: Int) {
        let target = mode == "week"
            ? DayMath.adding(days: amount * 7, to: current)
            : TaskCalendar.addingMonths(amount, to: current)
        guard let target else { return }
        show(target, from: amount > 0 ? .trailing : .leading)
    }

    private func goToToday() {
        show("", from: model.today < periodKey ? .leading : .trailing)
    }

    /// The direction is set a beat before the period changes, so the outgoing page leaves the right way.
    private func show(_ target: String, from edge: Edge) {
        change = .slide(edge)
        DispatchQueue.main.async {
            withMotion(Motion.smooth, reduceMotion: reduceMotion) { anchor = target }
        }
    }

    private func setMode(_ value: String) {
        guard value != mode else { return }
        change = .swap
        DispatchQueue.main.async {
            withMotion(Motion.smooth, reduceMotion: reduceMotion) {
                if startMode == nil { storedMode = value } else { localMode = value }
            }
        }
    }
}

// MARK: Data and actions

/// One update's worth of calendar data, worked out in a single pass over the tasks.
struct CalendarPlan {
    var today: String
    var days: [String: [PerchTask]]
    var cards: [String: [BoardCardReference]]
    var overdue: [PerchTask]
    var undated: [PerchTask]

    @MainActor
    init(model: AppModel) {
        today = model.today
        // Only the area in scope: the grid, the trays and their counts all follow it.
        let tasks = model.scopedTasks
        days = TaskCalendar.byDay(tasks)
        overdue = TaskCalendar.overdue(tasks, today: today)
        undated = TaskCalendar.undated(tasks)
        cards = Dictionary(grouping: model.scopedBoardCards.filter { ($0.card.dueDate ?? "").count >= 10 }) { String(($0.card.dueDate ?? "").prefix(10)) }
    }

    func tasks(on day: String) -> [PerchTask] { days[day] ?? [] }
    func cards(on day: String) -> [BoardCardReference] { cards[day] ?? [] }
}

/// What the calendar's cells and cards can do. Every change goes through `AppModel`.
@MainActor
struct CalendarActions {
    let model: AppModel
    let reduceMotion: Bool
    var pickDate: (PerchTask) -> Void

    /// Reschedules dropped tasks, or clears their date when `day` is nil. The moved pill settles with a bounce.
    func drop(_ ids: [String], on day: String?) -> Bool {
        var moved = false
        withMotion(Motion.bouncy, reduceMotion: reduceMotion) {
            moved = !model.move(taskIDs: ids, to: day).isEmpty
        }
        return moved
    }

    func open(_ task: PerchTask) { model.selectedTaskID = task.id }

    /// Ticks a task, or takes the tick back if it hasn't been written yet. True when a tick started.
    func complete(_ task: PerchTask) -> Bool {
        if model.completing.contains(task.id) {
            model.cancelCompleting(task.id)
            return false
        }
        model.beginCompleting(task, after: Motion.completionDelay(reduceMotion: reduceMotion))
        return model.completing.contains(task.id)
    }

    /// Adds a task on a day, written to disk once. A date typed in the text still wins, as everywhere else.
    func add(_ text: String, on day: String) -> Bool {
        var added = false
        withMotion(Motion.bouncy, reduceMotion: reduceMotion) {
            added = model.quickAdd(text, defaultArea: model.taskScope, defaultDue: day) != nil
        }
        return added
    }
}

// MARK: Small pieces

/// A day number. Today's is filled with the accent colour.
private struct DayNumber: View {
    @Environment(\.perchTheme) private var theme
    var number: Int
    var isToday: Bool
    var size: CGFloat = 12

    var body: some View {
        Text("\(number)")
            .font(.perchFixed(size: size, weight: isToday ? .bold : .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(isToday ? theme.accentText : theme.text)
            .frame(minWidth: Metrics.scaled(size) + 10, minHeight: Metrics.scaled(size) + 10)
            .background(Circle().fill(isToday ? theme.accent : Color.clear))
            .pulseOnce(isToday, color: theme.accent)
            .accessibilityLabel(isToday ? "Today, \(number)" : "\(number)")
    }
}

/// The row of weekday names above a grid.
private struct WeekdayHeader: View {
    @Environment(\.perchTheme) private var theme
    var days: [TaskCalendar.Day]
    var spacing: CGFloat = 4
    var narrow = false

    var body: some View {
        let symbols = narrow ? Calendar.current.veryShortStandaloneWeekdaySymbols : Calendar.current.shortStandaloneWeekdaySymbols
        HStack(spacing: spacing) {
            ForEach(days) { day in
                let weekday = DayMath.date(from: day.date).map { Calendar.current.component(.weekday, from: $0) } ?? 1
                Text(symbols[(weekday - 1) % symbols.count])
                    .font(.perchEyebrow)
                    .textCase(.uppercase)
                    .foregroundStyle(day.isWeekend ? theme.textMuted : theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: narrow ? .center : .leading)
                    .padding(.leading, narrow ? 0 : 8)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A one-line task on the calendar: a priority dot and the title. Drag it to another day.
struct CalendarPill: View {
    @Environment(\.perchTheme) private var theme
    let task: PerchTask
    let isOverdue: Bool
    let actions: CalendarActions
    var trailing: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            if isOverdue {
                Image(systemName: "exclamationmark.circle.fill").font(.perchFixed(size: 8.5, weight: .bold)).foregroundStyle(theme.danger)
            } else if task.priority < 4 {
                Circle().fill(Palette.priority(task.priority, theme: theme)).frame(width: 6, height: 6)
            } else {
                Circle().strokeBorder(theme.textSecondary, lineWidth: 1.2).frame(width: 6, height: 6)
            }
            if let time = task.time {
                Text(time).font(.perchFixed(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(theme.textSecondary)
            }
            Text(task.title).font(.perchFixed(size: 11)).foregroundStyle(theme.text).lineLimit(1)
            if let trailing {
                Spacer(minLength: 4)
                Text(trailing).font(.perchFixed(size: 10, weight: .medium)).foregroundStyle(isOverdue ? theme.danger : theme.textSecondary).lineLimit(1).layoutPriority(1)
            }
        }
        .padding(.horizontal, 5)
        .frame(height: Metrics.row(18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 5).fill(fill))
        .contentShape(RoundedRectangle(cornerRadius: 5))
        .onTapGesture { actions.open(task) }
        .draggable(task.id) { TaskDragPreview(title: task.title, tint: Palette.priority(task.priority, theme: theme)).environment(\.perchTheme, theme) }
        .onHover { hovering = $0 }
        .motion(Motion.quick, value: hovering)
        .contextMenu { MoveMenu(model: actions.model, task: task) { actions.pickDate(task) } }
        .transition(.perchPop(reduceMotion: reduceMotion))
        .help(task.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(task.title + (isOverdue ? ", overdue" : ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { actions.open(task) }
    }

    private var fill: Color {
        if isOverdue { return theme.danger.opacity(hovering ? 0.24 : 0.15) }
        if task.priority < 4 { return Palette.priority(task.priority, theme: theme).opacity(hovering ? 0.24 : 0.15) }
        return hovering ? theme.washStrong : theme.wash
    }
}

/// A dated Kanban card. It belongs to its board, so it opens the board and can't be dragged.
private struct BoardCardPill: View {
    @Environment(\.perchTheme) private var theme
    let reference: BoardCardReference
    let actions: CalendarActions

    var body: some View {
        Button { actions.model.route = .file(reference.path) } label: {
            HStack(spacing: 4) {
                Image(systemName: "rectangle.split.3x1").font(.perchFixed(size: 8.5, weight: .semibold))
                Text(reference.card.title).font(.perchFixed(size: 11)).lineLimit(1)
            }
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 5)
            .frame(height: Metrics.row(18))
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(theme.textMuted.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(reference.card.title), a card on the \(reference.board) board")
    }
}

/// A task with a little more detail, for week columns and day lists.
struct CalendarCard: View {
    @Environment(\.perchTheme) private var theme
    let task: PerchTask
    let today: String
    let actions: CalendarActions
    /// Adds the day the task is due, for a column that holds more than one day.
    var showsDay = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var ticks = 0

    var body: some View {
        let overdueDays = TaskCalendar.daysOverdue(task, today: today)
        let isSelected = actions.model.selectedTaskID == task.id
        let day = showsDay && overdueDays == nil ? TaskCalendar.dayKey(task.due) : nil
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 6) {
                CheckCircle(color: Palette.priority(task.priority, theme: theme), isDone: actions.model.completing.contains(task.id), burst: ticks, fixedSize: Metrics.checkSize - 3) {
                    if actions.complete(task) { ticks += 1 }
                }
                .sensoryFeedback(.success, trigger: ticks)
                Text(task.title).font(.perchCard).foregroundStyle(theme.text).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            // Inside a scope every card is in the same area, so its chip is left out, as in the lists.
            let showsArea = task.area != actions.model.taskScope
            if overdueDays != nil || task.time != nil || task.recurrence != nil || showsArea || day != nil {
                // The chips run the card's full width, so they still fit in a narrow week column.
                FlowLayout(spacing: 4) {
                    if let overdueDays {
                        Chip(text: TaskCalendar.overdueText(days: overdueDays), symbol: nil, tint: theme.danger, small: true)
                    }
                    if let day { Chip(text: DayLabel.weekdayDate(day, today: today), symbol: "calendar", tint: theme.info, small: true) }
                    if let time = task.time { Chip(text: time, symbol: "clock", tint: theme.textSecondary, small: true) }
                    if task.recurrence != nil { Chip(text: "Repeats", symbol: "repeat", tint: theme.textSecondary, filled: false, small: true) }
                    if showsArea {
                        Chip(text: QuickAdd.simplifiedArea(task.area), symbol: nil, tint: Palette.area(task.area, theme: theme), small: true)
                    }
                }
                .padding(.leading, 2)
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(overdueDays == nil ? theme.surface : theme.danger.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? theme.accent : (overdueDays == nil ? theme.border.opacity(hovering ? 1 : 0.7) : theme.danger.opacity(0.25)), lineWidth: isSelected ? 1.5 : 1))
        .opacity(actions.model.completing.contains(task.id) ? 0.6 : 1)
        .overlay(alignment: .leading) {
            if overdueDays != nil {
                UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8).fill(theme.danger).frame(width: 3)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { actions.open(task) }
        .draggable(task.id) { TaskDragPreview(title: task.title, tint: Palette.priority(task.priority, theme: theme)).environment(\.perchTheme, theme) }
        .onHover { hovering = $0 }
        .lift(hovering, scale: 1.012)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .contextMenu { MoveMenu(model: actions.model, task: task) { actions.pickDate(task) } }
        .transition(.perchPop(reduceMotion: reduceMotion))
    }
}

/// A dated Kanban card shown among a day's task cards.
private struct BoardCardRow: View {
    @Environment(\.perchTheme) private var theme
    let reference: BoardCardReference
    let actions: CalendarActions

    var body: some View {
        Button { actions.model.route = .file(reference.path) } label: {
            HStack(spacing: 7) {
                Image(systemName: "rectangle.split.3x1").font(.perchFixed(size: 11)).foregroundStyle(theme.textSecondary).frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reference.card.title).font(.perchCard).foregroundStyle(theme.text).lineLimit(2).multilineTextAlignment(.leading)
                    Text("\(reference.board) · \(reference.list)").font(.perchSmall).foregroundStyle(theme.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.textMuted.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Opens the \(reference.board) board")
    }
}

/// A plus button that opens a small field for adding a task on one day.
struct DayAddButton: View {
    @Environment(\.perchTheme) private var theme
    let day: String
    let today: String
    let actions: CalendarActions
    @Binding var isPresented: Bool
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        Button { isPresented = true } label: {
            Image(systemName: "plus")
                .font(.perchFixed(size: 10, weight: .bold))
                .foregroundStyle(theme.textSecondary)
                .frame(width: Metrics.scaled(20), height: Metrics.scaled(20))
                .background(Circle().fill(theme.wash))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // A small circle to look at, with room around it to hit on a touch screen.
        .padding(touchPadding)
        .contentShape(Rectangle())
        .padding(-touchPadding)
        .help("Add a task on \(DayLabel.weekdayDate(day, today: today))")
        .accessibilityLabel("Add a task on \(DayLabel.spoken(day, today: today))")
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 8) {
                Text(DayLabel.heading(day, today: today)).font(.perchEyebrow).textCase(.uppercase).foregroundStyle(theme.textSecondary)
                HStack {
                    TextField("New task", text: $text)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .onSubmit(add)
                    Button("Add", action: add).disabled(jsTrim(text).isEmpty)
                }
            }
            .padding(Metrics.cardPadding)
            .frame(minWidth: 280)
            .perchPresented()
            .presentationDetents([.height(140)])
            .onAppear { focused = true }
        }
    }

    private var touchPadding: CGFloat {
        #if os(iOS)
        10
        #else
        0
        #endif
    }

    private func add() {
        guard actions.add(text, on: day) else { return }
        text = ""
        isPresented = false
    }
}

/// A day's whole list, shown from "+3 more".
private struct DayDetailList: View {
    @Environment(\.perchTheme) private var theme
    let day: String
    let plan: CalendarPlan
    let actions: CalendarActions

    var body: some View {
        let tasks = plan.tasks(on: day)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(DayLabel.heading(day, today: plan.today)).font(.perchHeading)
                CountBadge(count: tasks.count, tint: day < plan.today ? theme.danger : nil)
                Spacer()
            }
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(tasks) { CalendarCard(task: $0, today: plan.today, actions: actions) }
                    ForEach(plan.cards(on: day)) { BoardCardRow(reference: $0, actions: actions) }
                }
            }
        }
        .padding(Metrics.cardPadding)
        .frame(minWidth: 300, idealWidth: 320, maxHeight: 440)
        .perchPresented()
        .presentationDetents([.medium, .large])
    }
}

// MARK: Trays

/// Overdue and undated tasks, kept above the calendar so they can be dragged onto any day.
private struct CalendarTray: View {
    @Environment(\.perchTheme) private var theme
    let plan: CalendarPlan
    let actions: CalendarActions
    @Binding var open: String
    var isCompact: Bool
    @State private var noDateTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if !plan.overdue.isEmpty {
                    button("overdue", title: "Overdue", symbol: "exclamationmark.circle.fill", count: plan.overdue.count, tint: theme.danger)
                }
                button("nodate", title: "No date", symbol: "tray", count: plan.undated.count, tint: theme.textSecondary)
                    .background(Capsule().fill(noDateTargeted ? theme.dropFill : Color.clear))
                    .overlay(Capsule().strokeBorder(noDateTargeted ? theme.accent : Color.clear, lineWidth: 1.5))
                    .lift(noDateTargeted, scale: 1.06)
                    .motion(Motion.quick, value: noDateTargeted)
                    .dropDestination(for: String.self) { ids, _ in actions.drop(ids, on: nil) } isTargeted: { noDateTargeted = $0 }
                    .help("Tasks without a date. Drop a task here to clear its date.")
                Spacer(minLength: 0)
                if !open.isEmpty, !isCompact {
                    Text("Drag onto a day to schedule").font(.perchCaption).foregroundStyle(theme.textMuted).transition(.opacity)
                }
            }
            if open == "overdue", !plan.overdue.isEmpty {
                strip(plan.overdue, overdue: true)
            } else if open == "nodate" {
                if plan.undated.isEmpty {
                    Text("Every open task has a date. Drop one on “No date” to clear it.")
                        .font(.perchCaption).foregroundStyle(theme.textSecondary)
                        .transition(.perchSwap(reduceMotion: reduceMotion))
                } else {
                    strip(plan.undated, overdue: false)
                }
            }
        }
    }

    private func button(_ name: String, title: String, symbol: String, count: Int, tint: Color) -> some View {
        Button {
            withMotion(Motion.smooth, reduceMotion: reduceMotion) { open = open == name ? "" : name }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.perchFixed(size: 10.5, weight: .semibold))
                Text(title).font(.perchChip)
                Text("\(count)").font(.perchChip.weight(.semibold)).monospacedDigit().contentTransition(.numericText())
                Image(systemName: "chevron.right").font(.perchFixed(size: 8, weight: .bold)).rotationEffect(.degrees(open == name ? 90 : 0)).opacity(0.7)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .frame(minHeight: trayHeight)
            .background(Capsule().fill(tint.opacity(open == name ? 0.22 : 0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(PerchPressStyle())
        .motion(Motion.smooth, value: count)
        .accessibilityLabel("\(title), \(DayLabel.tasks(count))")
        .accessibilityHint(open == name ? "Hides these tasks" : "Shows these tasks so they can be moved onto a day")
    }

    private var trayHeight: CGFloat {
        #if os(iOS)
        Metrics.scaled(34)
        #else
        Metrics.scaled(26)
        #endif
    }

    private func strip(_ tasks: [PerchTask], overdue: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: [GridItem(.fixed(Metrics.row(18)), spacing: 5), GridItem(.fixed(Metrics.row(18)), spacing: 5)], spacing: 6) {
                ForEach(tasks) { task in
                    CalendarPill(
                        task: task, isOverdue: overdue, actions: actions,
                        trailing: overdue ? task.due.map { friendlyDate(String($0.prefix(10)), today: plan.today) } : nil
                    )
                    .frame(width: 210)
                }
            }
            .padding(.vertical, 1)
        }
        .frame(height: Metrics.row(18) * 2 + 7)
        .transition(.perchSwap(reduceMotion: reduceMotion))
    }
}

// MARK: Month

/// A month of real calendar weeks. Each day shows as many tasks as fit, then "+3 more".
private struct MonthGridView: View {
    @Environment(\.perchTheme) private var theme
    let grid: [[TaskCalendar.Day]]
    let plan: CalendarPlan
    let actions: CalendarActions
    private let gap: CGFloat = 4
    /// Room for the day number and one task. Below this the weeks scroll instead of squashing,
    /// as in a short window or on a large iPhone held sideways.
    private var minRowHeight: CGFloat { Metrics.scaled(56) }

    var body: some View {
        VStack(spacing: 6) {
            WeekdayHeader(days: grid.first ?? [], spacing: gap)
            GeometryReader { geometry in
                let rows = CGFloat(max(grid.count, 1))
                let fitted = (geometry.size.height - gap * (rows - 1)) / rows
                let rowHeight = max(fitted, minRowHeight)
                let capacity = max(1, Int((rowHeight - Metrics.scaled(22) - 14) / (Metrics.row(18) + 3)))
                ScrollView {
                    VStack(spacing: gap) {
                        ForEach(grid, id: \.first?.date) { week in
                            HStack(spacing: gap) {
                                ForEach(week) { day in
                                    MonthDayCell(
                                        day: day, tasks: plan.tasks(on: day.date), cards: plan.cards(on: day.date),
                                        plan: plan, capacity: capacity, actions: actions
                                    )
                                }
                            }
                            .frame(height: rowHeight)
                        }
                    }
                }
                .scrollDisabled(fitted >= minRowHeight)
                .scrollClipDisabled(fitted >= minRowHeight)
                .scrollIndicators(.never)
            }
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.bottom, Metrics.gap)
    }
}

private struct MonthDayCell: View {
    @Environment(\.perchTheme) private var theme
    let day: TaskCalendar.Day
    let tasks: [PerchTask]
    let cards: [BoardCardReference]
    let plan: CalendarPlan
    let capacity: Int
    let actions: CalendarActions
    @State private var targeted = false
    @State private var hovering = false
    @State private var showMore = false
    @State private var showAdd = false

    var body: some View {
        let isToday = day.date == plan.today
        let isPast = day.date < plan.today
        let total = tasks.count + cards.count
        let room = total <= capacity ? capacity : max(capacity - 1, 0)
        let shownTasks = tasks.prefix(room)
        let shownCards = cards.prefix(max(room - shownTasks.count, 0))
        let hidden = total - shownTasks.count - shownCards.count

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                DayNumber(number: day.number, isToday: isToday)
                if day.number == 1, let date = DayMath.date(from: day.date) {
                    Text(date.formatted(.dateTime.month(.abbreviated))).font(.perchEyebrow).textCase(.uppercase).foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 0)
                DayAddButton(day: day.date, today: plan.today, actions: actions, isPresented: $showAdd)
                    .opacity(hovering || showAdd ? 1 : restingAddOpacity)
            }
            .frame(height: Metrics.scaled(22))
            ForEach(shownTasks) { CalendarPill(task: $0, isOverdue: isPast, actions: actions) }
            ForEach(shownCards) { BoardCardPill(reference: $0, actions: actions) }
            if hidden > 0 {
                Button { showMore = true } label: {
                    Text("+\(hidden) more")
                        .font(.perchFixed(size: 10.5, weight: .semibold))
                        .foregroundStyle(isPast ? theme.danger : theme.textSecondary)
                        .padding(.horizontal, 5)
                        .frame(height: Metrics.scaled(16))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show everything on \(DayLabel.weekdayDate(day.date, today: plan.today))")
                .accessibilityLabel("\(hidden) more on \(DayLabel.spoken(day.date, today: plan.today))")
                .popover(isPresented: $showMore) { DayDetailList(day: day.date, plan: plan, actions: actions) }
            }
            Spacer(minLength: 0)
        }
        .padding(5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(day.inMonth ? 1 : 0.45)
        .clipped()
        .background(RoundedRectangle(cornerRadius: 8).fill(fill(isToday: isToday)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(targeted || isToday ? theme.accent.opacity(targeted ? 1 : 0.5) : (hovering ? theme.hairline : Color.clear), lineWidth: targeted ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { showAdd = true }
        .onHover { hovering = $0 }
        .lift(targeted, scale: 1.03)
        .zIndex(targeted ? 1 : 0)
        .motion(Motion.quick, value: targeted)
        .motion(Motion.quick, value: hovering)
        .dropDestination(for: String.self) { ids, _ in actions.drop(ids, on: day.date) } isTargeted: { targeted = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(DayLabel.spoken(day.date, today: plan.today, tasks: tasks.count, overdue: isPast))
    }

    /// The plus shows on hover on a Mac. Where there's no pointer to hover with, it stays faintly visible.
    private var restingAddOpacity: Double {
        #if os(iOS)
        0.55
        #else
        0
        #endif
    }

    private func fill(isToday: Bool) -> Color {
        if targeted { return theme.dropFill }
        if isToday { return theme.accentSoft }
        if !day.inMonth { return theme.wash.opacity(0.45) }
        return (day.isWeekend ? theme.washStrong.opacity(0.7) : theme.wash)
    }
}

/// The month on a narrow screen: dots for each day's tasks, and the chosen day's list underneath.
private struct CompactMonthView: View {
    @Environment(\.perchTheme) private var theme
    let grid: [[TaskCalendar.Day]]
    let plan: CalendarPlan
    let actions: CalendarActions
    @Binding var selected: String?
    /// Puts the chosen day's list beside the grid instead of under it.
    var sideBySide: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The chosen day if it's on this page, otherwise today, otherwise the first of the month.
    private var chosen: String {
        let days = grid.flatMap { $0 }
        if let selected, days.contains(where: { $0.date == selected }) { return selected }
        if days.contains(where: { $0.date == plan.today && $0.inMonth }) { return plan.today }
        return days.first(where: \.inMonth)?.date ?? plan.today
    }

    var body: some View {
        let chosen = chosen
        if sideBySide {
            // Wide enough for both: the month on one side, the chosen day's tasks beside it.
            HStack(alignment: .top, spacing: 0) {
                ScrollView { monthGrid(chosen).padding(.horizontal, Metrics.gap).padding(.bottom, Metrics.gap) }
                    .frame(maxWidth: 440)
                    .scrollBounceBehavior(.basedOnSize)
                Rectangle().fill(theme.hairline).frame(width: 1).padding(.bottom, Metrics.gap)
                ScrollView {
                    dayList(chosen).padding(.horizontal, Metrics.gap).padding(.top, 2).padding(.bottom, Metrics.screenPadding)
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    monthGrid(chosen)
                    dayList(chosen).padding(.top, 10)
                }
                .padding(.horizontal, Metrics.gap)
                .padding(.bottom, Metrics.screenPadding)
            }
        }
    }

    private func monthGrid(_ chosen: String) -> some View {
        VStack(spacing: 6) {
            WeekdayHeader(days: grid.first ?? [], spacing: 3, narrow: true)
            ForEach(grid, id: \.first?.date) { week in
                HStack(spacing: 3) {
                    ForEach(week) { day in
                        CompactDayCell(day: day, tasks: plan.tasks(on: day.date), hasCards: !plan.cards(on: day.date).isEmpty, today: plan.today, isSelected: day.date == chosen, short: sideBySide, actions: actions) {
                            withMotion(Motion.quick, reduceMotion: reduceMotion) { selected = day.date }
                        }
                    }
                }
            }
        }
    }

    private func dayList(_ chosen: String) -> some View {
        AgendaDay(day: chosen, plan: plan, actions: actions, emptyText: "", showsEmptyState: true)
            .id(chosen)
            .transition(.perchSwap(reduceMotion: reduceMotion))
    }
}

private struct CompactDayCell: View {
    @Environment(\.perchTheme) private var theme
    let day: TaskCalendar.Day
    let tasks: [PerchTask]
    let hasCards: Bool
    let today: String
    let isSelected: Bool
    /// A shorter cell, for a short screen such as a phone on its side.
    var short = false
    let actions: CalendarActions
    var select: () -> Void
    @State private var targeted = false

    var body: some View {
        let isPast = day.date < today
        Button(action: select) {
            VStack(spacing: 3) {
                DayNumber(number: day.number, isToday: day.date == today, size: 13)
                HStack(spacing: 2.5) {
                    ForEach(tasks.prefix(3)) { task in
                        Circle().fill(isPast ? theme.danger : (task.priority < 4 ? Palette.priority(task.priority, theme: theme) : theme.textSecondary)).frame(width: 5, height: 5)
                    }
                    if tasks.count > 3 {
                        Text("+").font(.perchFixed(size: 8, weight: .heavy)).foregroundStyle(isPast ? theme.danger : theme.textSecondary)
                    } else if tasks.isEmpty, hasCards {
                        RoundedRectangle(cornerRadius: 1).strokeBorder(theme.textSecondary, lineWidth: 1).frame(width: 6, height: 5)
                    }
                }
                .frame(height: 7)
            }
            .frame(maxWidth: .infinity, minHeight: Metrics.row(short ? 40 : 46))
            .opacity(day.inMonth ? 1 : 0.4)
            .background(RoundedRectangle(cornerRadius: 9).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(isSelected || targeted ? theme.accent : Color.clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(PerchPressStyle())
        .motion(Motion.quick, value: targeted)
        .lift(targeted, scale: 1.08)
        .dropDestination(for: String.self) { ids, _ in actions.drop(ids, on: day.date) } isTargeted: { targeted = $0 }
        .accessibilityLabel(DayLabel.spoken(day.date, today: today, tasks: tasks.count, overdue: isPast))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fill: Color {
        if targeted { return theme.dropFill }
        if isSelected { return theme.accentSoft }
        return (day.isWeekend && day.inMonth ? theme.wash : theme.wash.opacity(0.45))
    }
}

// MARK: Week

/// Seven columns for the calendar week, each a scrolling stack of task cards.
private struct WeekColumnsView: View {
    @Environment(\.perchTheme) private var theme
    let days: [String]
    let plan: CalendarPlan
    let actions: CalendarActions
    private let gap: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            let inner = geometry.size.width - Metrics.screenPadding * 2
            let fitted = (inner - gap * 6) / 7
            let width = max(fitted, 112)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: gap) {
                    ForEach(days, id: \.self) { day in
                        WeekDayColumn(day: day, plan: plan, actions: actions).frame(width: width)
                    }
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.bottom, Metrics.gap)
                .frame(height: geometry.size.height)
            }
            .scrollDisabled(fitted >= 112)
        }
    }
}

private struct WeekDayColumn: View {
    @Environment(\.perchTheme) private var theme
    let day: String
    let plan: CalendarPlan
    let actions: CalendarActions
    @State private var targeted = false
    @State private var showAdd = false

    var body: some View {
        let tasks = plan.tasks(on: day)
        let cards = plan.cards(on: day)
        let date = DayMath.date(from: day)
        let isToday = day == plan.today
        let isPast = day < plan.today
        let isWeekend = date.map { Calendar.current.isDateInWeekend($0) } ?? false

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(date?.formatted(.dateTime.weekday(.abbreviated)) ?? "")
                    .font(.perchEyebrow).textCase(.uppercase)
                    .fixedSize()
                    .foregroundStyle(isToday ? theme.accent : theme.textSecondary)
                DayNumber(number: Int(day.suffix(2)) ?? 0, isToday: isToday, size: 13)
                Spacer(minLength: 0)
                if !tasks.isEmpty { CountBadge(count: tasks.count, tint: isPast ? theme.danger : nil) }
                DayAddButton(day: day, today: plan.today, actions: actions, isPresented: $showAdd)
            }
            .frame(height: Metrics.scaled(24))
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(tasks) { CalendarCard(task: $0, today: plan.today, actions: actions) }
                    ForEach(cards) { BoardCardRow(reference: $0, actions: actions) }
                    if tasks.isEmpty, cards.isEmpty {
                        Text(targeted ? "Drop to move here" : (isPast ? "Nothing left over" : "Nothing planned"))
                            .font(.perchCaption)
                            .foregroundStyle(targeted ? AnyShapeStyle(theme.accent) : AnyShapeStyle(theme.textMuted))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(6)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: Metrics.cardRadius).fill(fill(isToday: isToday, isWeekend: isWeekend)))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius).strokeBorder(targeted || isToday ? theme.accent.opacity(targeted ? 1 : 0.5) : Color.clear, lineWidth: targeted ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { showAdd = true }
        .lift(targeted, scale: 1.02)
        .zIndex(targeted ? 1 : 0)
        .motion(Motion.quick, value: targeted)
        .dropDestination(for: String.self) { ids, _ in actions.drop(ids, on: day) } isTargeted: { targeted = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(DayLabel.spoken(day, today: plan.today, tasks: tasks.count, overdue: isPast))
    }

    private func fill(isToday: Bool, isWeekend: Bool) -> Color {
        if targeted { return theme.dropFill }
        if isToday { return theme.accentSoft }
        return (isWeekend ? theme.washStrong.opacity(0.7) : theme.wash)
    }
}

/// The week without room for seven columns: the days one under another, or in two columns when `tiled`.
private struct CompactWeekView: View {
    @Environment(\.perchTheme) private var theme
    let days: [String]
    let plan: CalendarPlan
    let actions: CalendarActions
    var tiled: Bool

    var body: some View {
        ScrollView {
            // Two columns read down then across, each as tall as its own days, so a busy day
            // doesn't leave a hole beside a quiet one.
            let split = tiled ? (days.count + 1) / 2 : days.count
            HStack(alignment: .top, spacing: Metrics.gap) {
                column(Array(days.prefix(split)))
                if tiled { column(Array(days.dropFirst(split))) }
            }
            .padding(.horizontal, Metrics.gap)
            .padding(.top, 2)
            .padding(.bottom, Metrics.screenPadding)
        }
    }
}

extension CompactWeekView {
    fileprivate func column(_ days: [String]) -> some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(days, id: \.self) { day in
                AgendaDay(day: day, plan: plan, actions: actions, emptyText: day < plan.today ? "Nothing left over" : "Nothing planned")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// One day's heading and task cards, for narrow screens. The heading is a drop target too.
private struct AgendaDay: View {
    @Environment(\.perchTheme) private var theme
    let day: String
    let plan: CalendarPlan
    let actions: CalendarActions
    var emptyText: String
    /// Explains the empty day and offers to add a task, where the day has the space to itself.
    var showsEmptyState = false
    @State private var targeted = false
    @State private var showAdd = false

    var body: some View {
        let tasks = plan.tasks(on: day)
        let cards = plan.cards(on: day)
        let isToday = day == plan.today
        let isPast = day < plan.today
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if isToday { Circle().fill(theme.accent).frame(width: 7, height: 7) }
                Text(DayLabel.heading(day, today: plan.today))
                    .font(.perchHeading)
                    .foregroundStyle(isToday ? theme.accent : theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !tasks.isEmpty { CountBadge(count: tasks.count, tint: isPast ? theme.danger : nil) }
                Spacer(minLength: 0)
                DayAddButton(day: day, today: plan.today, actions: actions, isPresented: $showAdd)
            }
            .padding(.horizontal, 8).padding(.vertical, Metrics.dense(5))
            .background(RoundedRectangle(cornerRadius: 8).fill(targeted ? theme.dropFill : (isToday ? theme.accentSoft : theme.wash)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(targeted ? theme.accent : Color.clear, lineWidth: 1.5))
            ForEach(tasks) { CalendarCard(task: $0, today: plan.today, actions: actions) }
            ForEach(cards) { BoardCardRow(reference: $0, actions: actions) }
            if tasks.isEmpty, cards.isEmpty {
                if showsEmptyState {
                    EmptyState(
                        symbol: "calendar.badge.plus", title: isPast ? "Nothing left over" : "Nothing on this day",
                        message: "Add a task for this day, or move one here from a task's Move to menu.",
                        actionTitle: "Add a task", action: { showAdd = true }
                    )
                    .frame(minHeight: 220)
                } else {
                    Text(targeted ? "Drop to move here" : emptyText).font(.perchCaption).foregroundStyle(targeted ? theme.accent : theme.textMuted).padding(.horizontal, 8)
                }
            }
        }
        .contentShape(Rectangle())
        .motion(Motion.quick, value: targeted)
        .lift(targeted, scale: 1.015)
        .dropDestination(for: String.self) { ids, _ in actions.drop(ids, on: day) } isTargeted: { targeted = $0 }
    }
}
