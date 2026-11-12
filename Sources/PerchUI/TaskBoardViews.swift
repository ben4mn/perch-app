import PerchKit
import SwiftUI

// Two views of Tasks that only exist where there is room: the Board (open tasks in columns by when
// they are due) and the panel that sits beside Today on a wide screen.

/// Open tasks in columns: Overdue, Today, Tomorrow, This week, Later, No date. Dragging a card to
/// another column reschedules it, through the same `AppModel.move` every other drag uses, so only its
/// `due` changes. The cards are the calendar week's cards.
struct TaskBoardScreen: View {
    @ObservedObject var model: AppModel
    @State private var moving: PerchTask?
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let gap: CGFloat = 8

    var body: some View {
        let today = model.today
        let columns = TaskBoard.columns(model.scopedTasks, today: today)
        let actions = CalendarActions(model: model, reduceMotion: reduceMotion) { moving = $0 }
        let open = columns.reduce(0) { $0 + $1.tasks.count }
        let overdue = columns.first { $0.kind == .overdue }?.tasks.count ?? 0
        VStack(spacing: 0) {
            ScreenHeader(title: TaskScope.title(view: .board, area: model.taskScope), stats: stats(open: open, overdue: overdue))
            if open == 0 {
                EmptyState(
                    symbol: "rectangle.split.3x1", title: "Nothing on the board" + (model.taskScope.map { " in " + QuickAdd.simplifiedArea($0) } ?? ""),
                    message: "Open tasks line up here by when they are due. Drag one to another column to reschedule it.",
                    actionTitle: "Add a task in Today", action: { model.show(view: .today) }
                )
            } else {
                GeometryReader { geometry in
                    let inner = geometry.size.width - Metrics.screenPadding * 2
                    let fitted = (inner - gap * CGFloat(columns.count - 1)) / CGFloat(max(columns.count, 1))
                    let width = max(fitted, Metrics.scaled(212))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: gap) {
                            ForEach(columns) { column in
                                TaskBoardColumn(column: column, today: today, actions: actions).frame(width: width)
                            }
                        }
                        .padding(.horizontal, Metrics.screenPadding)
                        .padding(.bottom, Metrics.gap)
                        .frame(height: geometry.size.height)
                    }
                    .scrollDisabled(fitted >= Metrics.scaled(212))
                }
            }
        }
        // Cards arrive, leave and change column together, whatever moved them.
        .motion(Motion.smooth, value: model.tasks.filter(\.isOpen).map { $0.id + ($0.due ?? "") })
        .motion(Motion.smooth, value: columns.map(\.id))
        .perchScreenBackground()
        .navigationTitle(TaskScope.title(view: .board, area: model.taskScope))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $moving) { MoveTaskSheet(model: model, task: $0) }
    }

    private func stats(open: Int, overdue: Int) -> [HeaderStat] {
        var stats = [HeaderStat(text: "\(open) open")]
        if overdue > 0 { stats.append(HeaderStat(text: "\(overdue) overdue", symbol: "exclamationmark.circle.fill", tint: theme.danger)) }
        return stats
    }
}

private struct TaskBoardColumn: View {
    let column: TaskBoard.Column
    let today: String
    let actions: CalendarActions
    @State private var targeted = false
    @State private var showAdd = false
    @Environment(\.perchTheme) private var theme

    private var isOverdue: Bool { column.kind == .overdue }
    private var isToday: Bool { column.kind == .today }
    /// Columns that hold more than one day say which day each card is due.
    private var showsDay: Bool { column.kind == .thisWeek || column.kind == .later }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(column.title)
                    .font(.perchEyebrow).textCase(.uppercase).kerning(0.4)
                    .foregroundStyle(isOverdue ? theme.danger : (isToday ? theme.accent : theme.textSecondary))
                    .lineLimit(1)
                if !column.tasks.isEmpty { CountBadge(count: column.tasks.count, tint: isOverdue ? theme.danger : nil) }
                Spacer(minLength: 0)
                if let day = column.dropDay, column.kind == .today || column.kind == .tomorrow {
                    DayAddButton(day: day, today: today, actions: actions, isPresented: $showAdd)
                }
            }
            .frame(height: Metrics.scaled(24))
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(column.tasks) { CalendarCard(task: $0, today: today, actions: actions, showsDay: showsDay) }
                    if column.tasks.isEmpty {
                        Text(targeted && column.acceptsDrops ? "Drop to move here" : emptyText)
                            .font(.perchCaption)
                            .foregroundStyle(targeted && column.acceptsDrops ? AnyShapeStyle(theme.accent) : AnyShapeStyle(theme.textMuted))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: Metrics.cardRadius).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius).strokeBorder(border, lineWidth: targeted ? 1.5 : 1))
        .contentShape(Rectangle())
        .lift(targeted && column.acceptsDrops, scale: 1.015)
        .zIndex(targeted ? 1 : 0)
        .motion(Motion.quick, value: targeted)
        .dropDestination(for: String.self) { ids, _ in drop(ids) } isTargeted: { targeted = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(column.title), \(DayLabel.tasks(column.tasks.count))")
    }

    private var emptyText: String {
        switch column.kind {
        case .today: return "Nothing due today"
        case .noDate: return "Everything has a date"
        default: return "Nothing planned"
        }
    }

    private var fill: Color {
        if targeted, column.acceptsDrops { return theme.dropFill }
        if isOverdue { return theme.danger.opacity(0.06) }
        return isToday ? theme.accentSoft : theme.wash
    }

    private var border: Color {
        if targeted, column.acceptsDrops { return theme.accent }
        return isToday ? theme.accent.opacity(0.5) : .clear
    }

    /// Each dropped task goes where `TaskBoard.move` says: a day, no date, or nowhere.
    private func drop(_ ids: [String]) -> Bool {
        guard column.acceptsDrops else { return false }
        var moved = false
        for id in ids {
            guard let task = actions.model.task(id: id) else { continue }
            switch TaskBoard.move(task, to: column, today: today) {
            case .stay: continue
            case let .day(day): moved = actions.drop([id], on: day) || moved
            case .clearDate: moved = actions.drop([id], on: nil) || moved
            }
        }
        return moved
    }
}

// MARK: - Beside Today

/// What sits beside today's list on a wide screen: the week at a glance, what is coming next, and
/// anything an agent is waiting to have confirmed. Quiet on purpose: a few lines each, and a way to
/// the full view.
struct TodayCompanion: View {
    @ObservedObject var model: AppModel
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How many upcoming tasks are listed before "See Upcoming" takes over.
    private let upNextLimit = 6

    var body: some View {
        let today = model.today
        let scoped = model.scopedTasks
        let byDay = TaskCalendar.byDay(scoped)
        let ready = model.scopedReadyToTick
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionGap) {
                week(today: today, byDay: byDay)
                upNext(today: today, tasks: scoped)
                if !ready.isEmpty { proposals(ready) }
            }
            .padding(Metrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(theme.background)
        .motion(Motion.smooth, value: scoped.filter(\.isOpen).map { $0.id + ($0.due ?? "") })
    }

    // MARK: The week

    private func week(today: String, byDay: [String: [PerchTask]]) -> some View {
        let days = TaskCalendar.week(containing: today)
        return VStack(alignment: .leading, spacing: Metrics.tightGap) {
            heading("This week", action: "Calendar") { model.show(view: .calendar) }
            HStack(spacing: 4) {
                ForEach(days, id: \.self) { day in
                    WeekStripDay(day: day, today: today, count: byDay[day]?.count ?? 0) {
                        model.show(view: .calendar)
                    }
                }
            }
        }
    }

    // MARK: Up next

    @ViewBuilder
    private func upNext(today: String, tasks: [PerchTask]) -> some View {
        let days = TaskCalendar.upcoming(tasks, today: today, nearDays: 7, includeEmptyNearDays: false)
        let total = days.reduce(0) { $0 + $1.tasks.count }
        let shown = Self.limited(days, to: upNextLimit)
        VStack(alignment: .leading, spacing: Metrics.tightGap) {
            heading("Up next", action: total > upNextLimit ? "All \(total)" : "Upcoming") { model.show(view: .upcoming) }
            if shown.isEmpty {
                Text("Nothing is planned after today.")
                    .font(.perchBody).foregroundStyle(theme.textMuted)
                    .padding(.vertical, 4)
            }
            ForEach(shown) { day in
                Text(DayLabel.heading(day.date, today: today))
                    .font(.perchCaption.weight(.medium)).foregroundStyle(theme.textSecondary)
                    .padding(.top, 4)
                    .accessibilityAddTraits(.isHeader)
                ForEach(day.tasks) { task in UpNextRow(model: model, task: task) }
            }
        }
    }

    /// The first days of the list, cut off once `limit` tasks have been listed.
    static func limited(_ days: [TaskCalendar.UpcomingDay], to limit: Int) -> [TaskCalendar.UpcomingDay] {
        var left = limit
        var result: [TaskCalendar.UpcomingDay] = []
        for day in days where left > 0 && !day.tasks.isEmpty {
            var day = day
            day.tasks = Array(day.tasks.prefix(left))
            left -= day.tasks.count
            result.append(day)
        }
        return result
    }

    // MARK: Ready to tick

    private func proposals(_ ready: [PerchTask]) -> some View {
        VStack(alignment: .leading, spacing: Metrics.tightGap) {
            heading("Ready to tick", action: ready.count > 2 ? "All \(ready.count)" : "Open") { model.show(view: .ready) }
            ForEach(ready.prefix(2)) { task in
                Button { model.selectedTaskID = task.id } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.seal").font(.perchBody).foregroundStyle(theme.success).padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title).font(.perchCard).foregroundStyle(theme.text).lineLimit(2).multilineTextAlignment(.leading)
                            Text(Proposal(task).sentence)
                                .font(.perchCaption).foregroundStyle(theme.textSecondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(Metrics.spaced(10))
                    .frame(maxWidth: .infinity, minHeight: Metrics.minTap, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PerchPressStyle())
                .accessibilityLabel("\(task.title), \(Proposal(task).sentence)")
            }
        }
    }

    private func heading(_ title: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            SectionLabel(title)
            Spacer(minLength: 8)
            Button(action: perform) {
                HStack(spacing: 2) {
                    Text(action)
                    Image(systemName: "chevron.right").font(.perchFixed(size: 8, weight: .bold))
                }
                .font(.perchCaption.weight(.medium))
                .foregroundStyle(theme.accent)
                .frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(PerchPressStyle())
            .accessibilityLabel("\(title): open \(action)")
        }
    }
}

/// One day of the week strip: its letter, its number and a mark for how busy it is.
private struct WeekStripDay: View {
    let day: String
    let today: String
    let count: Int
    var action: () -> Void
    @Environment(\.perchTheme) private var theme

    var body: some View {
        let isToday = day == today
        let isPast = day < today
        let date = DayMath.date(from: day)
        Button(action: action) {
            VStack(spacing: 3) {
                Text(date?.formatted(.dateTime.weekday(.narrow)) ?? "")
                    .font(.perchSmall).foregroundStyle(isToday ? theme.accent : theme.textMuted)
                Text("\(Int(day.suffix(2)) ?? 0)")
                    .font(.perchCard.weight(isToday ? .bold : .regular)).monospacedDigit()
                    .foregroundStyle(isToday ? theme.accent : (isPast ? theme.textMuted : theme.text))
                Text(count > 0 ? "\(count)" : " ")
                    .font(.perchSmall).monospacedDigit()
                    .foregroundStyle(isPast && count > 0 ? theme.danger : theme.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: Metrics.row(54))
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(isToday ? theme.accentSoft : theme.wash.opacity(isPast ? 0.5 : 1)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PerchPressStyle())
        .accessibilityLabel(DayLabel.spoken(day, today: today, tasks: count, overdue: isPast))
        .accessibilityHint("Opens the calendar")
    }
}

/// A task in "Up next": its priority, its name and its time. Tapping opens it.
private struct UpNextRow: View {
    @ObservedObject var model: AppModel
    let task: PerchTask
    @Environment(\.perchTheme) private var theme

    var body: some View {
        Button { model.selectedTaskID = task.id } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().strokeBorder(Palette.priority(task.priority, theme: theme), lineWidth: 1.5)
                    .frame(width: 10, height: 10)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                Text(task.title).font(.perchCard).foregroundStyle(theme.text).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                if let time = task.time { Text(time).font(.perchSmall).monospacedDigit().foregroundStyle(theme.textSecondary) }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: Metrics.row(36))
            .contentShape(Rectangle())
            .hoverHighlight(selected: model.selectedTaskID == task.id)
        }
        .buttonStyle(PerchPressStyle())
        .accessibilityLabel(task.time.map { "\(task.title), \($0)" } ?? task.title)
    }
}
