import PerchKit
import SwiftUI

public struct PerchLinkStyle: ButtonStyle {
    @Environment(\.perchTheme) private var theme
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(theme.accent).opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension PerchTask {
    /// The first readable line of the details, as plain text, for task rows.
    var previewLine: String? { TaskText.firstLine(details) }
}

struct TaskRow: View {
    @ObservedObject var model: AppModel
    let task: PerchTask
    var indent = 0
    var showArea = true
    var hidesToday = false
    /// Leaves the date chip out, for rows that already sit under a heading for their day.
    var hidesDue = false
    /// Adds "3 days overdue" to the date chip of a late task.
    var showsOverdueAge = false
    /// Subtask counts worked out by the caller for the whole list, so long lists don't scan every task per row.
    var subtaskCount: TaskCalendar.SubtaskCount?
    /// Tabs: the workspace, where there is one, for "Open in New Tab" in the row's menu.
    @Environment(\.perchWorkspace) private var workspace
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Goes up once per tick, to set off the burst and the haptic.
    @State private var ticks = 0

    private var subtaskTally: TaskCalendar.SubtaskCount {
        if let subtaskCount { return subtaskCount }
        let subtasks = model.tasks.filter { $0.parent == task.id }
        return .init(done: subtasks.filter { !$0.isOpen }.count, total: subtasks.count)
    }
    /// Ticked a moment ago: the model holds the completion until the check has been seen.
    private var isCompleting: Bool { model.completing.contains(task.id) }
    private var isDone: Bool { task.status == .done || isCompleting }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CheckCircle(color: Palette.priority(task.priority, theme: theme), isDone: isDone, burst: ticks, action: toggle)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    StrikeSweepText(text: task.title, isDone: isDone, font: .perchRow, color: theme.text, doneColor: theme.textMuted)
                    if !task.details.isEmpty {
                        Image(systemName: "text.alignleft").font(.perchSmall).foregroundStyle(theme.textMuted).help("Has details")
                            .accessibilityLabel("Has details")
                    }
                }
                if theme.display.showsTaskPreview, let preview = task.previewLine {
                    Text(preview).font(.perchCaption).foregroundStyle(theme.textSecondary).lineLimit(1)
                }
                if theme.display.showsTaskChips, hasChips { chips.padding(.top, 3) }
            }
            Spacer(minLength: 6)
            if let owner = task.owner, owner != model.author {
                Avatar(name: owner, me: model.author, size: 20).padding(.top, 1)
            }
        }
        .padding(.leading, CGFloat(indent) * 22)
        .padding(.vertical, Metrics.rowPadding)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .opacity(isCompleting ? 0.6 : 1)
        .hoverHighlight(selected: model.selectedTaskID == task.id)
        .onTapGesture { model.selectedTaskID = task.id }
        .draggable(task.id) { TaskDragPreview(title: task.title, tint: Palette.priority(task.priority, theme: theme)).environment(\.perchTheme, theme) }
        .settle(on: task.due)
        .motion(Motion.quick, value: isCompleting)
        .sensoryFeedback(.success, trigger: ticks)
        .contextMenu {
            WorkspaceOpenButtons(store: workspace, item: .file(task.path))
            Button("Today") { reschedule(model.today) }
            Button("Tomorrow") { reschedule(DayMath.adding(days: 1, to: model.today) ?? model.today) }
            Button("No date") { model.move(taskIDs: [task.id], to: nil) }
            Menu("Priority") {
                ForEach(1...4, id: \.self) { value in
                    Button("P\(value)") {
                        var updated = task
                        updated.priority = value
                        model.update(updated)
                    }
                }
            }
            Divider()
            Button("Delete", role: .destructive) { model.pendingDelete = task }
        }
        .transition(.perchRow(reduceMotion: reduceMotion))
    }

    /// Ticking shows the check straight away and hands the write to the model, which waits a beat and
    /// can't lose it. Tapping again before then takes the tick back.
    private func toggle() {
        if task.status == .done {
            model.reopen(task)
        } else if isCompleting {
            model.cancelCompleting(task.id)
        } else {
            model.beginCompleting(task, after: Motion.completionDelay(reduceMotion: reduceMotion))
            if model.completing.contains(task.id) { ticks += 1 }
        }
    }

    private func reschedule(_ date: String) { model.reschedule([task], to: date) }

    private var overdueAge: String {
        guard showsOverdueAge, let days = TaskCalendar.daysOverdue(task, today: model.today) else { return "" }
        return " · " + TaskCalendar.overdueText(days: days).lowercased()
    }

    private var showsDue: Bool {
        guard let due = task.due else { return false }
        return !hidesDue && !(hidesToday && due == model.today)
    }

    private var shownLabels: [String] { Array(task.labels.filter { !$0.hasPrefix("section/") }.prefix(3)) }

    /// The area chip is left out wherever every row is in the same area: inside a scope, the area in
    /// scope goes without saying. A task from another area (a subtask under a parent here) keeps its chip.
    private var showsArea: Bool { showArea && task.area != model.taskScope }

    private var hasChips: Bool {
        showsDue || task.time != nil || task.deadline != nil || showsArea || subtaskTally.total > 0
            || !task.activity.isEmpty || !shownLabels.isEmpty || task.isReadyToTick
    }

    /// Facts as colored chips, so a glance tells you when, how big, and for whom.
    private var chips: some View {
        FlowLayout(spacing: 6) {
            if let due = task.due, showsDue {
                Chip(text: friendlyDate(due, today: model.today) + (task.time.map { " \($0)" } ?? "") + overdueAge,
                     symbol: task.recurrence == nil ? "calendar" : "repeat", tint: Palette.dueColor(task, today: model.today, theme: theme))
            } else if let time = task.time {
                Chip(text: time, symbol: "clock", tint: Palette.dueColor(task, today: model.today, theme: theme))
            }
            if let deadline = task.deadline {
                Chip(text: friendlyDate(deadline, today: model.today), symbol: "flag.checkered", tint: deadline < model.today ? theme.danger : theme.warning)
            }
            if showsArea {
                Chip(text: QuickAdd.simplifiedArea(task.area), symbol: nil, tint: Palette.area(task.area, theme: theme))
            }
            let tally = subtaskTally
            if tally.total > 0 {
                Chip(text: "\(tally.done)/\(tally.total)", symbol: tally.done == tally.total ? "checklist.checked" : "checklist", tint: theme.textSecondary, filled: false)
            }
            if !task.activity.isEmpty {
                Chip(text: "\(task.activity.count)", symbol: "bubble.left", tint: theme.textSecondary, filled: false)
            }
            ForEach(shownLabels, id: \.self) { label in
                Chip(text: "#" + label, symbol: nil, tint: Palette.label(label, theme: theme))
            }
            if task.isReadyToTick { Chip(text: "Ready to tick", symbol: "checkmark.seal.fill", tint: theme.success) }
        }
    }
}

/// A completion circle. Ticking it fills the circle with a spring, draws the check on, and throws a small burst.
struct CheckCircle: View {
    var color: Color
    var isDone: Bool
    /// Raise this to set off the burst.
    var burst = 0
    /// Nil follows the Display settings. Worked out as the circle is drawn, not when it is made, so a
    /// circle whose parent isn't drawn again still takes a new interface size.
    var fixedSize: CGFloat?
    var action: () -> Void
    @Environment(\.perchTheme) private var theme
    @State private var hovering = false

    private var size: CGFloat { fixedSize ?? Metrics.checkSize }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(color, lineWidth: 1.6)
                Circle().fill(color).scaleEffect(isDone ? 1 : (hovering ? 0.4 : 0.001)).opacity(isDone ? 1 : 0.35)
                    .motion(Motion.bouncy, value: isDone)
                    .motion(Motion.quick, value: hovering)
                CheckMarkShape()
                    .trim(from: 0, to: isDone ? 1 : 0)
                    .stroke(theme.background, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round, lineJoin: .round))
                    .motion(.easeOut(duration: 0.22).delay(isDone ? 0.08 : 0), value: isDone)
                CompletionBurst(color: color, trigger: burst)
            }
            .frame(width: size, height: size)
            // A small circle to look at, with a full-size target around it.
            .padding(hitPadding)
            .contentShape(Circle())
            .padding(-hitPadding)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(isDone ? "Reopen" : "Complete")
    }

    private var hitPadding: CGFloat { max((Metrics.minTap - size) / 2, 0) }
}

struct CompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

/// A task plus its open subtasks, nested and collapsible.
struct TaskTree: View {
    @ObservedObject var model: AppModel
    let task: PerchTask
    var depth = 0
    var showArea = true
    var showDone = false
    @State private var collapsed = false
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var children: [PerchTask] {
        model.subtasks(of: task).filter { showDone || $0.isOpen }
    }

    var body: some View {
        let children = children
        HStack(alignment: .top, spacing: 0) {
            if !children.isEmpty {
                Button {
                    withMotion(Motion.smooth, reduceMotion: reduceMotion) { collapsed.toggle() }
                } label: {
                    Image(systemName: "chevron.right").font(.perchSmall.weight(.bold)).foregroundStyle(theme.textMuted)
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                        .frame(width: 14, height: Metrics.checkSize + Metrics.rowPadding * 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(collapsed ? "Show subtasks" : "Hide subtasks")
            } else {
                Color.clear.frame(width: 14, height: 1)
            }
            TaskRow(model: model, task: task, indent: depth, showArea: showArea)
        }
        .transition(.perchRow(reduceMotion: reduceMotion))
        if !collapsed {
            ForEach(children) { child in
                // A subtask filed in another area says so; one in its parent's area doesn't repeat it.
                TaskTree(model: model, task: child, depth: depth + 1, showArea: child.area != task.area, showDone: showDone)
            }
        }
    }
}

struct QuickAddField: View {
    @ObservedObject var model: AppModel
    var defaultArea: String?
    var placeholder = "Add a task"
    var parent: PerchTask?
    /// The screen's own field: the one a "new task" shortcut puts the keyboard in.
    var takesNewTask = false
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.perchTheme) private var theme

    private var parsed: QuickAdd { QuickAdd.parse(text, areas: model.areas) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.perchBody.weight(.semibold)).foregroundStyle(focused ? theme.accent : theme.textMuted)
                    .frame(width: Metrics.checkSize)
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.perchRow)
                    .foregroundStyle(theme.text)
                    .focused($focused)
                    .onSubmit(add)
            }
            if !text.isEmpty, hasDetails {
                FlowLayout(spacing: 6) {
                    if let due = parsed.due { Chip(text: friendlyDate(due, today: model.today) + (parsed.time.map { " \($0)" } ?? ""), symbol: "calendar", tint: theme.info) }
                    if let rule = parsed.recurrence { Chip(text: rule, symbol: "repeat", tint: theme.info) }
                    if let area = parsed.area { Chip(text: QuickAdd.simplifiedArea(area), symbol: "square.stack", tint: Palette.area(area, theme: theme)) }
                    if let priority = parsed.priority { Chip(text: "P\(priority)", symbol: "flag.fill", tint: Palette.priority(priority, theme: theme)) }
                    if let owner = parsed.owner { Chip(text: "@\(owner)", symbol: nil, tint: theme.textSecondary) }
                    ForEach(parsed.labels, id: \.self) { Chip(text: "#\($0)", symbol: nil, tint: Palette.label($0, theme: theme)) }
                }
                .padding(.leading, Metrics.checkSize + 10)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, Metrics.rowPadding + 1)
        .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).fill(focused ? theme.surface : theme.wash))
        .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).strokeBorder(focused ? theme.accent.opacity(0.7) : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .motion(Motion.quick, value: focused)
        .motion(Motion.quick, value: hasDetails && !text.isEmpty)
        .onChange(of: model.newTaskRequests) { _, _ in if takesNewTask { focused = true } }
        .help("Try: Call the vet tomorrow 5pm #Personal !p2")
    }

    private var hasDetails: Bool {
        parsed.due != nil || parsed.area != nil || parsed.priority != nil || parsed.owner != nil || !parsed.labels.isEmpty
    }

    private func add() {
        if model.quickAdd(text, defaultArea: defaultArea, parent: parent) != nil { text = "" }
    }
}

/// Today, Upcoming and Ready to tick, for the area in scope or for every area.
struct TaskListScreen: View {
    @ObservedObject var model: AppModel
    let route: Route
    @State private var filter = ""
    @State private var owner = "Everyone"
    @State private var rescheduleDate = Date()
    @State private var showReschedule = false
    @AppStorage("overdueExpanded") private var overdueExpanded = false
    /// On a compact screen the filter sits behind a button in the counts line until it is asked for.
    @State private var showsFilter = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HeaderScroll {
            header
        } content: {
            LazyVStack(alignment: .leading, spacing: 0) {
                if route != .ready {
                    QuickAddField(model: model, defaultArea: defaultArea, takesNewTask: true).padding(.bottom, 8)
                }
                content
            }
            .padding(.horizontal, Metrics.screenPadding - 8)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        #if os(iOS)
        .refreshable { await model.syncNow() }
        .scrollDismissesKeyboard(.interactively)
        #endif
        // Rows leaving, arriving and changing day all move together.
        .motion(Motion.smooth, value: model.tasks.filter(\.isOpen).map { $0.id + ($0.due ?? "") })
        .perchScreenBackground()
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// Quick add files a new task in the area in scope.
    private var defaultArea: String? { model.taskScope }

    private var view: TaskViewKind {
        switch route {
        case .upcoming: return .upcoming
        case .ready: return .ready
        default: return .today
        }
    }

    /// Says where you are: "Today", or "Personal · Today" inside an area.
    private var title: String { TaskScope.title(view: view, area: model.taskScope) }

    /// " in Personal" inside an area, for empty states.
    private var inScope: String { model.taskScope.map { " in " + QuickAdd.simplifiedArea($0) } ?? "" }

    private var isFiltering: Bool { owner != "Everyone" || !jsTrim(filter).isEmpty }

    private func clearFilter() {
        filter = ""
        owner = "Everyone"
    }

    // MARK: Header

    private var header: some View {
        let folds = sizeClass == .compact
        // A filter that is on always shows, so what is narrowing the list is never out of sight.
        let open = !folds || showsFilter || isFiltering
        return ScreenHeader(title: title, stats: stats) {
            if folds {
                FilterToggle(isOpen: open, isFiltering: isFiltering) {
                    withMotion(Motion.smooth, reduceMotion: reduceMotion) {
                        if open { clearFilter() }
                        showsFilter = !open
                    }
                }
            }
        } controls: {
            if open {
                #if os(iOS)
                // No ViewThatFits around menus on the iPhone (iOS 27.1 hang; see FolderScreen's header).
                VStack(alignment: .leading, spacing: 8) {
                    FilterField(text: $filter, prompt: "Filter, or #label")
                    ScrollView(.horizontal, showsIndicators: false) { controls }
                }
                .transition(.opacity)
                #else
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        FilterField(text: $filter, prompt: "Filter, or #label").frame(maxWidth: 260)
                        controls
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        FilterField(text: $filter, prompt: "Filter, or #label")
                        controls
                    }
                }
                .transition(.opacity)
                #endif
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 8) {
            if owners.count > 2 {
                Menu {
                    Picker("Owner", selection: $owner) {
                        ForEach(owners, id: \.self) { Text($0 == "Everyone" ? $0 : "@" + $0).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    ControlChip(symbol: "person", text: owner == "Everyone" ? "Everyone" : "@" + owner, isOn: owner != "Everyone")
                }
                .modifier(ChipMenu())
                .help("Show one person's or agent's tasks")
            }
        }
    }

    private var stats: [HeaderStat] {
        let today = model.today
        switch route {
        case .today:
            let list = model.scopedTasks.filter { $0.isDueTodayOrEarlier(today: today) }
            let overdue = list.filter { $0.isOverdue(today: today) }.count
            var stats = [HeaderStat(text: DayLabel.weekdayDate(today, today: today)), HeaderStat(text: "\(list.count - overdue) due")]
            if overdue > 0 { stats.append(HeaderStat(text: "\(overdue) overdue", symbol: "exclamationmark.circle.fill", tint: theme.danger)) }
            return stats
        case .upcoming:
            let count = model.scopedTasks.filter { $0.isOpen && ($0.due.map { String($0.prefix(10)) } ?? "") > today }.count
            return [HeaderStat(text: count == 1 ? "1 task ahead" : "\(count) tasks ahead")]
        case .ready:
            return [HeaderStat(text: "\(model.scopedReadyToTick.count) waiting for you")]
        default: return []
        }
    }

    private var owners: [String] {
        ["Everyone"] + Array(Set(model.scopedTasks.compactMap(\.owner))).sorted()
    }

    private func matches(_ task: PerchTask) -> Bool {
        if owner != "Everyone", task.owner != owner { return false }
        let query = jsTrim(filter)
        guard !query.isEmpty else { return true }
        if query.hasPrefix("#") {
            return task.labels.contains { $0.localizedCaseInsensitiveContains(query.dropFirst()) }
        }
        return task.title.localizedCaseInsensitiveContains(query) || task.details.localizedCaseInsensitiveContains(query)
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .today: todaySections
        case .upcoming: upcomingSections
        case .ready: readySection
        default: EmptyView()
        }
    }

    private var noMatches: some View {
        EmptyState(
            symbol: "line.3.horizontal.decrease.circle", title: "Nothing matches",
            message: "No task here matches this filter.", actionTitle: "Clear filter", action: clearFilter
        )
        .frame(minHeight: 320)
    }

    // MARK: Today

    @ViewBuilder
    private var todaySections: some View {
        let today = model.today
        let scoped = model.scopedTasks
        let list = scoped.filter { $0.isDueTodayOrEarlier(today: today) && matches($0) }.sorted(by: AppModel.ordered)
        let overdue = list.filter { $0.isOverdue(today: today) }
        let due = list.filter { !$0.isOverdue(today: today) }
        let cards = cards
        let finishedToday = scoped.filter { $0.status == .done && ($0.completed ?? "").hasPrefix(today) }.count
        let showArea = model.taskScope == nil
        if due.isEmpty {
            if isFiltering {
                if overdue.isEmpty, cards.isEmpty { noMatches }
            } else if finishedToday > 0 {
                // The last one for today just went: a small moment, not a party.
                EmptyState(
                    symbol: "checkmark", title: "Done for today" + inScope,
                    message: overdue.isEmpty
                        ? "You finished \(DayLabel.tasks(finishedToday))\(inScope) today. Enjoy it, or pull something forward from Upcoming."
                        : "You finished \(DayLabel.tasks(finishedToday))\(inScope) today. Only the overdue ones are left.",
                    actionTitle: overdue.isEmpty ? "See Upcoming" : nil, celebrates: true,
                    action: { model.show(view: .upcoming) }
                )
                .frame(minHeight: overdue.isEmpty && cards.isEmpty ? 340 : 220)
            } else if overdue.isEmpty, cards.isEmpty {
                EmptyState(
                    symbol: "sun.max", title: "Nothing due today" + inScope,
                    message: model.taskScope == nil
                        ? "Tasks dated today, and anything overdue, show up here. Add one above, like “Call the vet today 5pm”."
                        : "\(QuickAdd.simplifiedArea(model.taskScope ?? ""))’s tasks dated today, and anything overdue, show up here. Add one above and it is filed in this area."
                )
                .frame(minHeight: 340)
            }
        }
        ForEach(due) { TaskRow(model: model, task: $0, showArea: showArea, hidesToday: true) }
        if !overdue.isEmpty {
            GroupHeaderRow(
                title: "Overdue", symbol: "exclamationmark.circle.fill", tint: theme.danger, count: overdue.count,
                isTinted: true, isCollapsed: !overdueExpanded,
                toggle: { withMotion(Motion.smooth, reduceMotion: reduceMotion) { overdueExpanded.toggle() } }
            ) {
                Button("Reschedule") { showReschedule = true }
                    .buttonStyle(.plain)
                    .font(.perchCaption.weight(.medium))
                    .foregroundStyle(theme.accent)
                    .popover(isPresented: $showReschedule) { reschedulePopover(overdue) }
            }
            .padding(.top, due.isEmpty ? 4 : Metrics.sectionGap)
            if overdueExpanded {
                ForEach(overdue) { TaskRow(model: model, task: $0, showArea: showArea) }
            }
        }
        if !cards.isEmpty {
            SectionLabel("Board cards").padding(.horizontal, 8).padding(.top, Metrics.sectionGap).padding(.bottom, 4)
            ForEach(cards) { reference in
                Button { model.route = .file(reference.path) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "rectangle.split.3x1").font(.perchCaption).foregroundStyle(theme.info).frame(width: Metrics.checkSize)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reference.card.title).font(.perchRow).foregroundStyle(theme.text).lineLimit(1)
                            Text("\(reference.board) · \(reference.list)").font(.perchCaption).foregroundStyle(theme.textSecondary).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        let due = String((reference.card.dueDate ?? "").prefix(10))
                        Chip(text: friendlyDate(due, today: today), symbol: "calendar", tint: due < today ? theme.danger : theme.success)
                    }
                    .padding(.horizontal, 8).padding(.vertical, Metrics.rowPadding)
                    .contentShape(Rectangle())
                    .hoverHighlight()
                }
                .buttonStyle(.plain)
                .help("Opens the \(reference.board) board")
            }
        }
    }

    private var cards: [BoardCardReference] {
        model.scopedBoardCards.filter { ($0.card.dueDate ?? "9") <= model.today }
    }

    private func reschedulePopover(_ list: [PerchTask]) -> some View {
        VStack(spacing: 10) {
            Text("Move \(list.count) overdue tasks").font(.perchStyle(.headline))
            DatePicker("Date", selection: $rescheduleDate, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden()
            HStack {
                Button("Today") { apply(model.today, list) }
                Button("Tomorrow") { apply(DayMath.adding(days: 1, to: model.today) ?? model.today, list) }
                Button("Move") { apply(DayMath.string(from: rescheduleDate), list) }.buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .perchPresented()
        .presentationDetents([.medium, .large])
    }

    private func apply(_ date: String, _ list: [PerchTask]) {
        withMotion(Motion.smooth, reduceMotion: reduceMotion) { model.reschedule(list, to: date) }
        showReschedule = false
    }

    // MARK: Upcoming

    @ViewBuilder
    private var upcomingSections: some View {
        let days = TaskCalendar.upcoming(model.scopedTasks.filter(matches), today: model.today, includeEmptyNearDays: !isFiltering)
        let showArea = model.taskScope == nil
        // Counted once for the whole list, so each row doesn't scan every task for its subtasks.
        let subtaskCounts = TaskCalendar.subtaskCounts(model.tasks)
        if days.isEmpty {
            if isFiltering {
                noMatches
            } else {
                EmptyState(
                    symbol: "calendar.badge.clock", title: "Nothing coming up" + inScope,
                    message: "Tasks with a date after today appear here, a day at a time. Add one above, like “Call the vet friday”, or drag a task onto a day in the Calendar.",
                    actionTitle: "Open Calendar", action: { model.show(view: .calendar) }
                )
                .frame(minHeight: 340)
            }
        }
        ForEach(days) { day in
            UpcomingDayHeader(model: model, day: day)
                .padding(.top, day.id == days.first?.id ? 2 : Metrics.gap)
            ForEach(day.tasks) { task in
                TaskRow(model: model, task: task, showArea: showArea, hidesDue: true, subtaskCount: subtaskCounts[task.id] ?? .init())
            }
        }
    }

    // MARK: Ready to tick

    @ViewBuilder
    private var readySection: some View {
        let list = model.scopedReadyToTick.filter(matches)
        if list.isEmpty {
            if isFiltering {
                noMatches
            } else {
                EmptyState(
                    symbol: "checkmark.seal", title: "Nothing waiting for you" + inScope,
                    message: "When an agent thinks it has finished one of your tasks, the task lands here with its reason, for you to confirm or send back.",
                    actionTitle: "Back to Today", action: { model.show(view: .today) }
                )
                .frame(minHeight: 340)
            }
        }
        ForEach(list) { task in
            ProposalCard(model: model, task: task).padding(.bottom, Metrics.gap)
        }
    }
}

/// A task an agent thinks is finished: who says so, when and why, what they were doing, a way back to
/// their session, and the two answers. Agents can't close the user's tasks, so nothing changes until the user answers.
struct ProposalCard: View {
    @ObservedObject var model: AppModel
    let task: PerchTask
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let proposal = Proposal(task)
        VStack(alignment: .leading, spacing: 4) {
            TaskRow(model: model, task: task)
            HStack(alignment: .top, spacing: 10) {
                Avatar(name: task.proposedDoneBy ?? "agent", me: model.author, size: Metrics.checkSize)
                VStack(alignment: .leading, spacing: 8) {
                    ProposalText(proposal: proposal)
                    ProposalButtons(proposal: proposal) {
                        withMotion(Motion.smooth, reduceMotion: reduceMotion) { model.acceptProposal(task) }
                    } decline: {
                        withMotion(Motion.smooth, reduceMotion: reduceMotion) { model.rejectProposal(task) }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
        .transition(.perchRow(reduceMotion: reduceMotion))
    }

    /// The agent's reason with its inline Markdown shown as formatting, and wiki links as their names.
    public static func rendered(_ markdown: String) -> AttributedString {
        let source = TaskText.simplifyingLinks(markdown)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(TaskText.plain(markdown))
    }
}

struct TaskDetailView: View {
    @ObservedObject var model: AppModel
    @State private var draft: PerchTask
    @StateObject private var host: WebHost
    @State private var comment = ""
    @State private var editingDetails = false
    @State private var detailsHeight: CGFloat = 40
    @State private var showDate = false
    @State private var showDeadline = false
    @State private var newLabel = ""
    @State private var showLabel = false
    @StateObject private var actions = EditorActions()
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: AppModel, task: PerchTask) {
        self.model = model
        _draft = State(initialValue: task)
        _host = StateObject(wrappedValue: WebHost.reader { [weak model] in
            MainActor.assumeIsolated { model?.vault?.root }
        })
    }

    /// The parts of a task that completing, reopening or rescheduling it change. Ordinary typing here never
    /// changes these on its own, so watching them can't fight with the text being edited.
    private struct Outcome: Equatable {
        var status: TaskStatus?
        var completed: String?
        var due: String?
        var activityCount = 0
        var path: String?
    }

    private static func outcome(of task: PerchTask?) -> Outcome {
        Outcome(status: task?.status, completed: task?.completed, due: task?.due, activityCount: task?.activity.count ?? 0, path: task?.path)
    }

    private var ownerChoices: [String] {
        var choices = [model.author] + model.configuration.otherOwners.filter { $0 != model.author }
        for owner in model.tasks.compactMap(\.owner) where !choices.contains(owner) { choices.append(owner) }
        return choices
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                propertyBar
                if draft.isReadyToTick { proposalCard }
                details
                if !model.subtasks(of: draft).isEmpty || draft.parent == nil { subtasks }
                activity
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
        .scrollContentBackground(.hidden)
        .background(theme.background.ignoresSafeArea())
        .foregroundStyle(theme.text)
        .onChange(of: draft) { _, updated in
            if updated != model.task(id: updated.id) { model.update(updated) }
            renderDetails()
        }
        .onChange(of: TaskDetailView.outcome(of: model.task(id: draft.id))) { _, _ in
            // The task was completed, reopened or moved to its next date somewhere else: a tick in the
            // list behind this view, another device, an agent. Take that copy, or the next edit made here
            // would save the old one over it and quietly undo the completion.
            if let fresh = model.task(id: draft.id), fresh != draft { draft = fresh }
        }
        .onAppear(perform: configure)
        // The closure the page reports to holds this view, which holds the page: disconnect it, or the page lives on.
        .onDisappear { host.onMessage = nil }
        // The page recolours itself for a new theme; the details are not rendered again.
        .onChange(of: theme) { host.call("setAppearance", arguments: theme.webAppearance(paintsBackground: false)) }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            CheckCircle(color: Palette.priority(draft.priority, theme: theme), isDone: draft.status == .done || model.completing.contains(draft.id), fixedSize: Metrics.checkSize + 3) {
                // `complete` also settles a tick still waiting in the list behind, so the task is completed once.
                if draft.status == .done { model.reopen(draft) } else { model.complete(draft) }
                close()
            }
            .padding(.top, 3)
            TextField("Title", text: $draft.title, axis: .vertical)
                .font(.perchFixed(size: 19, weight: .semibold))
                .textFieldStyle(.plain)
            Button(action: close) {
                Image(systemName: "xmark").font(.perchFixed(size: 11, weight: .bold)).foregroundStyle(theme.textSecondary)
                    .frame(width: 26, height: 26).background(Circle().fill(theme.wash))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .keyboardShortcut(.cancelAction)
            #if DEBUG
            .background(GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                Color.clear
                    .onAppear { DebugProbes.taskPanelClose[draft.id] = frame }
                    .onChange(of: frame) { _, frame in DebugProbes.taskPanelClose[draft.id] = frame }
                    .onDisappear { DebugProbes.taskPanelClose[draft.id] = nil }
            })
            #endif
        }
    }

    /// Closes the panel by forgetting the task. Every place that shows it (the Mac's inspector, the iPhone's
    /// sheet and its side pane) is bound to `selectedTaskID`, so this is all closing takes. It never calls
    /// `dismiss()`: from the Mac's inspector that closed the whole main window.
    private func close() {
        model.selectedTaskID = nil
    }

    // MARK: Properties

    /// Every property is a chip you can click; unset ones live behind the plus.
    private var propertyBar: some View {
        FlowLayout(spacing: 7) {
            dateChip
            Menu {
                ForEach(1...4, id: \.self) { value in
                    Button { draft.priority = value } label: { Label("Priority \(value)", systemImage: value < 4 ? "flag.fill" : "flag") }
                }
            } label: {
                PropertyChip(symbol: draft.priority < 4 ? "flag.fill" : "flag", text: "P\(draft.priority)", tint: Palette.priority(draft.priority, theme: theme))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()

            Menu {
                ForEach(model.areas, id: \.self) { area in
                    Button(area) {
                        model.move(draft, toArea: area)
                        draft.path = "\(area)/Tasks/\((draft.path as NSString).lastPathComponent)"
                    }
                }
            } label: {
                PropertyChip(symbol: "square.stack.fill", text: QuickAdd.simplifiedArea(draft.area), tint: Palette.area(draft.area, theme: theme))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()

            Menu {
                ForEach(ownerChoices, id: \.self) { name in Button("@\(name)") { draft.owner = name } }
            } label: {
                HStack(spacing: 5) {
                    Avatar(name: draft.owner ?? model.author, me: model.author, size: 16)
                    Text(draft.owner ?? model.author).font(.perchChip).foregroundStyle(theme.text)
                }
                .padding(.leading, 3).padding(.trailing, 9).padding(.vertical, 3)
                .background(Capsule().fill(theme.wash))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()

            if let deadline = draft.deadline {
                Button { showDeadline = true } label: {
                    PropertyChip(symbol: "flag.checkered", text: "Due by " + friendlyDate(deadline, today: model.today), tint: deadline < model.today ? theme.danger : theme.warning)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showDeadline) { deadlinePopover }
            }
            ForEach(draft.labels, id: \.self) { label in
                Button { draft.labels.removeAll { $0 == label } } label: {
                    PropertyChip(symbol: "number", text: label.replacingOccurrences(of: "section/", with: ""), tint: Palette.label(label, theme: theme))
                }
                .buttonStyle(.plain)
                .help("Click to remove")
            }
            if !draft.remind.isEmpty {
                PropertyChip(symbol: "bell.fill", text: draft.remind.count == 1 ? draft.remind[0].replacingOccurrences(of: "T", with: " ") : "\(draft.remind.count) reminders", tint: theme.info)
            }
            Menu {
                if draft.deadline == nil { Button("Deadline") { draft.deadline = draft.due ?? model.today; showDeadline = true } }
                Button("Label") { showLabel = true }
                if draft.due != nil, draft.recurrence == nil { Button("Repeat weekly") { draft.recurrence = "every week" } }
                if let due = draft.due {
                    Button("Reminder at 9:00") { draft.remind.append("\(due)T09:00") }
                }
                if !draft.remind.isEmpty { Button("Clear reminders") { draft.remind = [] } }
            } label: {
                Image(systemName: "plus").font(.perchFixed(size: 11, weight: .bold)).foregroundStyle(theme.textSecondary)
                    .frame(width: 26, height: 24).background(Capsule().fill(theme.wash))
                    .accessibilityLabel("Add a property")
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .popover(isPresented: $showLabel) {
                HStack {
                    TextField("Label", text: $newLabel).textFieldStyle(.roundedBorder).frame(width: 160)
                        .onSubmit {
                            let label = jsTrim(newLabel).replacingOccurrences(of: "#", with: "")
                            if !label.isEmpty, !draft.labels.contains(label) { draft.labels.append(label) }
                            newLabel = ""
                            showLabel = false
                        }
                }
                .padding(10)
                .perchPresented()
            }
        }
    }

    private var dateChip: some View {
        Button { showDate = true } label: {
            if let due = draft.due {
                PropertyChip(symbol: draft.recurrence == nil ? "calendar" : "repeat",
                             text: friendlyDate(due, today: model.today) + (draft.time.map { " · \($0)" } ?? ""),
                             tint: Palette.dueColor(draft, today: model.today, theme: theme))
            } else {
                PropertyChip(symbol: "calendar", text: "No date", tint: nil)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showDate) { datePopover }
    }

    private var datePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                quickDate("Today", model.today, "sun.max.fill", theme.success)
                quickDate("Tomorrow", DayMath.adding(days: 1, to: model.today), "sunrise.fill", theme.warning)
                quickDate("Next week", DayMath.adding(days: 7, to: model.today), "calendar.badge.plus", theme.info)
                Button { draft.due = nil; draft.time = nil; draft.recurrence = nil; showDate = false } label: {
                    Label("None", systemImage: "xmark.circle").labelStyle(.iconOnly)
                }
                .help("Remove date")
                .accessibilityLabel("Remove date")
            }
            DatePicker("", selection: dateBinding(\.due), displayedComponents: .date).datePickerStyle(.graphical).labelsHidden()
            HStack {
                Image(systemName: "clock").foregroundStyle(theme.textSecondary)
                TextField("Time, e.g. 09:00", text: Binding(get: { draft.time ?? "" }, set: { draft.time = $0.isEmpty ? nil : $0 }))
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Image(systemName: "repeat").foregroundStyle(theme.textSecondary)
                TextField("Repeat, e.g. every monday", text: Binding(get: { draft.recurrence ?? "" }, set: { draft.recurrence = $0.isEmpty ? nil : $0 }))
                    .textFieldStyle(.roundedBorder)
            }
            if let rule = draft.recurrence, !Recurrence.isSupported(rule.lowercased()) {
                Text("Perch will ask for the next date when you complete this.").font(.perchCaption).foregroundStyle(theme.textSecondary)
            }
        }
        .padding(14)
        .frame(width: 280)
        .perchPresented()
    }

    private func quickDate(_ title: String, _ date: String?, _ symbol: String, _ tint: Color) -> some View {
        Button {
            draft.due = date
            showDate = false
        } label: {
            Label(title, systemImage: symbol).font(.perchStyle(.caption).weight(.medium)).foregroundStyle(tint)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var deadlinePopover: some View {
        VStack(spacing: 8) {
            DatePicker("", selection: dateBinding(\.deadline), displayedComponents: .date).datePickerStyle(.graphical).labelsHidden()
            Button("Remove deadline") { draft.deadline = nil; showDeadline = false }
        }
        .padding(12)
        .perchPresented()
    }

    private func dateBinding(_ keyPath: WritableKeyPath<PerchTask, String?>) -> Binding<Date> {
        Binding {
            draft[keyPath: keyPath].flatMap { DayMath.date(from: $0) } ?? Date()
        } set: {
            draft[keyPath: keyPath] = DayMath.string(from: $0)
        }
    }

    private var proposalCard: some View {
        let proposal = Proposal(draft)
        return HStack(alignment: .top, spacing: 10) {
            Avatar(name: draft.proposedDoneBy ?? "agent", me: model.author, size: 24)
            VStack(alignment: .leading, spacing: 6) {
                ProposalText(proposal: proposal, prominent: true)
                ProposalButtons(proposal: proposal) {
                    model.acceptProposal(draft); model.selectedTaskID = nil
                } decline: {
                    model.rejectProposal(draft); model.selectedTaskID = nil
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(theme.success.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(theme.success.opacity(0.3), lineWidth: 1))
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Details", trailing: editingDetails ? "Done" : (draft.details.isEmpty ? "Add" : "Edit")) {
                withMotion(Motion.smooth, reduceMotion: reduceMotion) { editingDetails.toggle() }
                renderDetails()
            }
            if editingDetails {
                MarkdownEditor(text: $draft.details, actions: actions)
                    .frame(minHeight: 200)
                    .background(RoundedRectangle(cornerRadius: Metrics.controlRadius).fill(theme.wash))
            } else if draft.details.isEmpty {
                Text("No details yet. Choose Add to write some.").font(.perchBody).foregroundStyle(theme.textMuted)
            } else {
                WebHostView(host: host, embedded: true).frame(height: detailsHeight)
            }
        }
    }

    private func configure() {
        host.onMessage = { message in
            switch message["type"] as? String {
            case "ready": renderDetails()
            case "rendered", "height":
                if let height = message["height"] as? Double { withMotion(Motion.smooth, reduceMotion: reduceMotion) { detailsHeight = max(24, CGFloat(height)) } }
            case "openWiki":
                if let target = message["target"] as? String, case let .note(path) = model.links.resolve(target, from: draft.path) {
                    model.selectedTaskID = nil
                    model.route = .file(path)
                }
            case "openNote":
                // The path comes from the page: only a file that is in the notebook can be opened.
                if let path = message["path"] as? String, model.files.contains(where: { $0.path == path }) {
                    model.selectedTaskID = nil
                    model.route = .file(path)
                }
            case "openExternal":
                if let string = message["url"] as? String, let url = URL(string: string) { PlatformOpen.url(url) }
            case "toggleTask":
                if let line = message["line"] as? Int { toggleCheckbox(line: line, checked: message["checked"] as? Bool) }
            case "saveMention":
                if let text = message["text"] as? String, let path = message["path"] as? String { saveMention(text, path) }
            default: break
            }
        }
        renderDetails()
    }

    private func renderDetails() {
        guard !editingDetails, !draft.details.isEmpty else { return }
        var seen = Set<String>()
        let text = draft.details
        let mentions: [[String: String]] = model.links.mentions(in: text, excluding: draft.path).compactMap { mention in
            let key = String(text[mention.range]).lowercased()
            guard seen.insert(key).inserted else { return nil }
            return ["key": key, "path": mention.path, "title": mention.title]
        }
        host.call("render", arguments: [
            "markdown": text, "basePath": draft.path, "mentions": mentions, "resolved": [String: Bool](), "compact": true,
            // The theme's colours, on a see-through page: the details sit on the task's own card.
            "appearance": theme.webAppearance(paintsBackground: false),
        ])
    }

    /// Ticks the box the page says was clicked, to the state it asks for. Exactly one character of the
    /// details changes: the same rule as a note's reader, so line endings and other boxes are left alone.
    private func toggleCheckbox(line: Int, checked: Bool?) {
        if let edit = MarkdownEditing.setTaskBox(in: draft.details, line: line, checked: checked) {
            draft.details = edit.applied(to: draft.details)
        } else {
            // The click didn't land on a task in the text: draw the details again so the box shows the truth.
            renderDetails()
        }
    }

    private func saveMention(_ text: String, _ path: String) {
        guard let range = model.links.mentions(in: draft.details, excluding: draft.path).first(where: {
            $0.path == path && String(draft.details[$0.range]).caseInsensitiveCompare(text) == .orderedSame
        })?.range else { return }
        let title = VaultFile(path: path).title
        let spelled = String(draft.details[range])
        draft.details.replaceSubrange(range, with: spelled == title ? "[[\(title)]]" : "[[\(title)|\(spelled)]]")
    }

    // MARK: Subtasks and activity

    private var subtasks: some View {
        VStack(alignment: .leading, spacing: 2) {
            let children = model.subtasks(of: draft)
            sectionTitle(children.isEmpty ? "Subtasks" : "Subtasks · \(children.filter { !$0.isOpen }.count)/\(children.count)")
            ForEach(children) { TaskRow(model: model, task: $0, showArea: false) }
            QuickAddField(model: model, placeholder: "Add a subtask", parent: draft).padding(.top, 4)
        }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Activity")
            ForEach(Array(draft.activity.enumerated().reversed()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 10) {
                    Avatar(name: item.author, me: model.author, size: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(item.author).font(.perchCaption.weight(.semibold))
                            Text(relativeDay(item.date, today: model.today)).font(.perchCaption).foregroundStyle(theme.textMuted)
                        }
                        Text(ProposalCard.rendered(item.text)).font(.perchBody).foregroundStyle(theme.textSecondary).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: 8) {
                Avatar(name: model.author, me: model.author, size: 22)
                TextField("Comment", text: $comment, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: Metrics.controlRadius).fill(theme.wash))
                    .onSubmit(post)
                if !jsTrim(comment).isEmpty {
                    Button(action: post) { Image(systemName: "arrow.up.circle.fill").font(.perchStyle(.title3)) }
                        .buttonStyle(.plain).foregroundStyle(theme.accent)
                        .accessibilityLabel("Post comment")
                        .transition(.perchPop(reduceMotion: reduceMotion))
                }
            }
            .motion(Motion.quick, value: jsTrim(comment).isEmpty)
        }
    }

    private func post() {
        guard !jsTrim(comment).isEmpty else { return }
        withMotion(Motion.smooth, reduceMotion: reduceMotion) { draft.activity.append(.init(date: model.today, author: model.author, text: jsTrim(comment))) }
        comment = ""
    }

    private func sectionTitle(_ title: String, trailing: String? = nil, action: (() -> Void)? = nil) -> some View {
        HStack {
            SectionLabel(title)
            Spacer()
            if let trailing, let action {
                Button(trailing, action: action).buttonStyle(.plain).font(.perchCaption.weight(.medium)).foregroundStyle(theme.accent)
            }
        }
    }
}

/// A clickable property: icon and value in a tinted capsule.
struct PropertyChip: View {
    var symbol: String
    var text: String
    /// Nil draws it in the theme's quiet colours, for a property that isn't set.
    var tint: Color?
    @State private var hovering = false
    @Environment(\.perchTheme) private var theme

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).imageScale(.small).fontWeight(.semibold)
            Text(text).lineLimit(1)
        }
        .font(.perchChip)
        .foregroundStyle(tint ?? theme.textSecondary)
        .padding(.horizontal, 9).padding(.vertical, 4.5)
        .background(Capsule().fill((tint ?? theme.text).opacity(hovering ? 0.2 : 0.12)))
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        .motion(Motion.quick, value: hovering)
    }
}


/// Asks for a date when Perch can't work out the next repeat.
struct NextDateSheet: View {
    @ObservedObject var model: AppModel
    let task: PerchTask
    @State private var date = Date()
    @Environment(\.perchTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("When's the next one?").font(.perchStyle(.headline))
            Text("“\(task.title)” repeats \(task.recurrence ?? ""), which Perch can't calculate yet.").font(.perchStyle(.callout)).foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            DatePicker("Next date", selection: $date, displayedComponents: .date)
            HStack {
                Button("Cancel") { model.needsNextDate = nil }
                Spacer()
                Button("Complete") {
                    model.needsNextDate = nil
                    model.complete(task, manualNextDue: DayMath.string(from: date))
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 320)
        .perchPresented()
    }
}

/// Public wrapper, so each app can place task details however suits its layout.
public struct TaskDetailHost: View {
    @ObservedObject var model: AppModel
    let task: PerchTask

    public init(model: AppModel, task: PerchTask) {
        self.model = model
        self.task = task
    }

    public var body: some View { TaskDetailView(model: model, task: task) }
}

/// What an agent's proposal says: who thinks what and how long ago, why, and what they were doing.
struct ProposalText: View {
    let proposal: Proposal
    /// Bigger, for the top of a task's own page.
    var prominent = false
    @Environment(\.perchTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(proposal.sentence)
                    .font(prominent ? .perchHeading : .perchCaption.weight(.semibold))
                    .foregroundStyle(prominent ? theme.text : theme.textSecondary)
                if let date = proposal.date {
                    Text(date, format: .relative(presentation: .named)).font(.perchCaption).foregroundStyle(theme.textMuted)
                }
            }
            if let reason = proposal.reason {
                Text(ProposalCard.rendered(reason)).font(.perchBody).foregroundStyle(prominent ? theme.textSecondary : theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if let during = proposal.during {
                Text("While: \(during)").font(.perchCaption).foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }
}

/// The two answers, and the way back to the agent's session. On one line when it fits, else the link
/// goes under the answers.
struct ProposalButtons: View {
    let proposal: Proposal
    var accept: () -> Void
    var decline: () -> Void

    var body: some View {
        #if os(iOS)
        // No ViewThatFits on the iPhone (iOS 27.1 hang; see FolderScreen's header): always stacked.
        stacked
        #else
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { answers; OpenSessionButton(proposal: proposal) }
            stacked
        }
        #endif
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) { answers }
            OpenSessionButton(proposal: proposal)
        }
    }

    @ViewBuilder private var answers: some View {
        Button(action: accept) { Label(proposal.acceptTitle, systemImage: "checkmark").lineLimit(1) }
            .buttonStyle(PerchButtonStyle(prominent: true))
        Button(action: decline) { Text(proposal.declineTitle).lineLimit(1) }
            .buttonStyle(PerchButtonStyle())
    }
}

/// Opens the session the proposal came from, in Claude or Codex, when Perch knows it.
struct OpenSessionButton: View {
    let proposal: Proposal
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let link = proposal.link, let title = proposal.linkTitle {
            Button { openURL(link) } label: { Label(title, systemImage: "arrow.up.right").lineLimit(1) }
                .buttonStyle(PerchButtonStyle())
                .help("See what \(proposal.agent) was doing when it asked")
        }
    }
}
