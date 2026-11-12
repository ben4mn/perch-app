import PerchKit
import SwiftUI

// MARK: Shared pieces for the planning views

/// How days are written in the Upcoming, List and Calendar views.
enum DayLabel {
    /// "Tue 10 Nov", with the year added when it isn't this year.
    static func weekdayDate(_ day: String, today: String) -> String {
        guard let value = DayMath.date(from: day) else { return day }
        let style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        return value.formatted(day.prefix(4) == today.prefix(4) ? style : style.year())
    }

    /// "Today", "Tomorrow" or "Yesterday" when the day is one of those.
    static func relative(_ day: String, today: String) -> String? {
        if day == today { return "Today" }
        if day == DayMath.adding(days: 1, to: today) { return "Tomorrow" }
        if day == DayMath.adding(days: -1, to: today) { return "Yesterday" }
        return nil
    }

    /// "Tomorrow · Tue 10 Nov", or just "Thu 12 Nov".
    static func heading(_ day: String, today: String) -> String {
        let date = weekdayDate(day, today: today)
        return relative(day, today: today).map { "\($0) · \(date)" } ?? date
    }

    /// "Monday 9 November, today", written out in full for VoiceOver.
    static func spoken(_ day: String, today: String) -> String {
        guard let value = DayMath.date(from: day) else { return day }
        let style = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide)
        let date = value.formatted(day.prefix(4) == today.prefix(4) ? style : style.year())
        return relative(day, today: today).map { "\(date), \($0.lowercased())" } ?? date
    }

    /// "Monday 9 November, today, 14 tasks", with "overdue" added for a past day that still has tasks.
    static func spoken(_ day: String, today: String, tasks count: Int, overdue: Bool) -> String {
        spoken(day, today: today) + ", " + tasks(count) + (overdue && count > 0 ? ", overdue" : "")
    }

    /// "1 task" or "14 tasks".
    static func tasks(_ count: Int) -> String { count == 1 ? "1 task" : "\(count) tasks" }

    /// "December 2026" from any day in that month, or from "2026-12".
    static func month(_ day: String) -> String {
        guard let value = DayMath.date(from: String(day.prefix(7)) + "-01") else { return day }
        return value.formatted(.dateTime.month(.wide).year())
    }

    /// "9 – 15 Nov" for a week, with the year added when it isn't this year.
    static func span(_ days: [String], today: String) -> String {
        guard let first = days.first.flatMap({ DayMath.date(from: $0) }), let last = days.last.flatMap({ DayMath.date(from: $0) }), first <= last else { return "" }
        let sameYear = days.allSatisfy { $0.prefix(4) == today.prefix(4) }
        let style = Date.IntervalFormatStyle().day().month(.abbreviated)
        return (first..<last).formatted(sameYear ? style : style.year())
    }
}

/// The "Move to" choices offered on every task in the planning views, for when dragging is awkward.
struct MoveMenu: View {
    @ObservedObject var model: AppModel
    let task: PerchTask
    var pickDate: () -> Void

    var body: some View {
        Button { model.selectedTaskID = task.id } label: { Label("Open", systemImage: "arrow.up.forward.square") }
        Divider()
        Section("Move to") {
            Button { move(model.today) } label: { Label("Today", systemImage: "sun.max") }
            Button { move(DayMath.adding(days: 1, to: model.today)) } label: { Label("Tomorrow", systemImage: "sunrise") }
            Button { move(nextWeek) } label: { Label("Next week", systemImage: "calendar.badge.plus") }
            Button(action: pickDate) { Label("Pick a date…", systemImage: "calendar") }
            if task.due != nil {
                Button { model.move(taskIDs: [task.id], to: nil) } label: { Label("No date", systemImage: "tray") }
            }
        }
    }

    private var nextWeek: String? {
        DayMath.adding(days: 7, to: model.today).flatMap { TaskCalendar.week(containing: $0).first }
    }

    private func move(_ day: String?) {
        guard let day else { return }
        model.move(taskIDs: [task.id], to: day)
    }
}

/// A small sheet for choosing any date for a task.
struct MoveTaskSheet: View {
    /// Read so this is drawn again when the interface size or density changes.
    @Environment(\.perchDisplay) private var display
    @ObservedObject var model: AppModel
    let task: PerchTask
    @State private var date = Date()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let _ = display
        VStack(alignment: .leading, spacing: Metrics.gap) {
            SectionLabel("Move to…")
            Text(task.title).font(.perchHeading).lineLimit(2)
            DatePicker("Date", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
            HStack {
                if task.due != nil {
                    Button("No date") { finish(nil) }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Move") { finish(DayMath.string(from: date)) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Metrics.screenPadding)
        .frame(minWidth: 300)
        .perchPresented()
        .presentationDetents([.medium, .large])
        .onAppear { date = task.due.flatMap { DayMath.date(from: $0) } ?? Date() }
    }

    private func finish(_ day: String?) {
        model.move(taskIDs: [task.id], to: day)
        dismiss()
    }
}

// MARK: Group headings

/// A heading above a group of tasks: a chevron when it collapses, an icon, a title, a count and a note.
struct GroupHeaderRow<Trailing: View>: View {
    var title: String
    var symbol: String?
    var tint: Color?
    var count: Int?
    var detail: String?
    /// Washes the whole heading in the tint, as the Overdue group does.
    var isTinted = false
    var isCollapsed = false
    var toggle: (() -> Void)?
    @ViewBuilder var trailing: Trailing
    @Environment(\.perchTheme) private var theme
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Button { toggle?() } label: {
                HStack(spacing: 7) {
                    if toggle != nil {
                        Image(systemName: "chevron.right")
                            .font(.perchSmall.weight(.bold))
                            .foregroundStyle(theme.textMuted)
                            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                            .frame(width: 10)
                    }
                    if let symbol { Image(systemName: symbol).font(.perchCaption.weight(.semibold)).foregroundStyle(tint ?? theme.textSecondary) }
                    Text(title).font(.perchHeading).foregroundStyle(isTinted ? (tint ?? theme.text) : theme.text).lineLimit(1)
                    if let count { CountBadge(count: count, tint: isTinted ? tint : nil) }
                    if let detail { Text(detail).font(.perchCaption).foregroundStyle(theme.textSecondary).lineLimit(1) }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(toggle == nil)
            trailing
        }
        .padding(.horizontal, 8)
        .frame(minHeight: headerHeight)
        .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).fill(fill))
        .onHover { hovering = $0 }
        .motion(Motion.quick, value: hovering)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(count.map { "\(title), \(DayLabel.tasks($0))" } ?? title)
        .accessibilityHint(toggle == nil ? "" : (isCollapsed ? "Expands the group" : "Collapses the group"))
    }

    private var fill: Color {
        if isTinted, let tint { return tint.opacity(hovering ? 0.16 : 0.1) }
        return hovering && toggle != nil ? theme.washStrong : theme.wash
    }

    private var headerHeight: CGFloat {
        #if os(iOS)
        38
        #else
        28
        #endif
    }
}

extension GroupHeaderRow where Trailing == EmptyView {
    init(title: String, symbol: String? = nil, tint: Color? = nil, count: Int? = nil, detail: String? = nil, isTinted: Bool = false, isCollapsed: Bool = false, toggle: (() -> Void)? = nil) {
        self.init(title: title, symbol: symbol, tint: tint, count: count, detail: detail, isTinted: isTinted, isCollapsed: isCollapsed, toggle: toggle, trailing: { EmptyView() })
    }
}

/// A collapsible heading for one of `TaskCalendar`'s groups. The Overdue group is tinted.
struct TaskGroupHeader: View {
    let group: TaskCalendar.Group
    let today: String
    let isCollapsed: Bool
    var toggle: () -> Void
    @Environment(\.perchTheme) private var theme

    var body: some View {
        GroupHeaderRow(
            title: title, symbol: symbol, tint: tint, count: group.tasks.count, detail: detail,
            isTinted: group.kind == .overdue, isCollapsed: isCollapsed, toggle: toggle
        )
    }

    private var title: String {
        switch group.kind {
        case .overdue: return "Overdue"
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .thisWeek: return "This week"
        case .later: return "Later"
        case .noDate: return "No date"
        case let .area(name): return name
        case let .priority(value): return value >= 4 ? "No priority" : "Priority \(value)"
        case .all: return "All tasks"
        case .completed: return "Completed"
        }
    }

    private var detail: String? {
        switch group.kind {
        case .overdue:
            guard let oldest = group.tasks.compactMap({ TaskCalendar.dayKey($0.due) }).min(), let days = TaskCalendar.daysBetween(oldest, today) else { return nil }
            return "oldest " + TaskCalendar.overdueText(days: days).lowercased().replacingOccurrences(of: " overdue", with: "")
        case .today: return DayLabel.weekdayDate(today, today: today)
        case .tomorrow: return DayMath.adding(days: 1, to: today).map { DayLabel.weekdayDate($0, today: today) }
        case .thisWeek: return TaskCalendar.week(containing: today).last.map { "until " + DayLabel.weekdayDate($0, today: today) }
        default: return nil
        }
    }

    private var symbol: String? {
        switch group.kind {
        case .overdue: return "exclamationmark.circle.fill"
        case .today: return "sun.max.fill"
        case .tomorrow: return "sunrise.fill"
        case .thisWeek: return "calendar"
        case .later: return "calendar.badge.clock"
        case .noDate: return "tray"
        case .area: return "circle.fill"
        case let .priority(value): return value >= 4 ? "flag" : "flag.fill"
        case .all: return nil
        case .completed: return "checkmark.circle.fill"
        }
    }

    private var tint: Color? {
        switch group.kind {
        case .overdue: return theme.danger
        case .today: return theme.success
        case .tomorrow: return theme.warning
        case .thisWeek: return theme.info
        case let .area(name): return Palette.area(name, theme: theme)
        case let .priority(value): return Palette.priority(value, theme: theme)
        case .completed: return theme.success
        default: return nil
        }
    }
}

// MARK: Upcoming

/// A day heading in Upcoming: "Tomorrow · Tue 10 Nov" and a count. Drop a task on it to move it to that day.
struct UpcomingDayHeader: View {
    @ObservedObject var model: AppModel
    let day: TaskCalendar.UpcomingDay
    @State private var targeted = false
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let today = model.today
        VStack(alignment: .leading, spacing: 8) {
            if let month = day.monthHeading {
                HStack(spacing: 8) {
                    SectionLabel(DayLabel.month(month))
                    Rectangle().fill(theme.hairline).frame(height: 1)
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let relative = DayLabel.relative(day.date, today: today) {
                    Text(relative).font(.perchHeading).foregroundStyle(theme.text)
                    Text(DayLabel.weekdayDate(day.date, today: today)).font(.perchCaption).foregroundStyle(theme.textSecondary)
                } else {
                    Text(DayLabel.weekdayDate(day.date, today: today)).font(.perchHeading).foregroundStyle(day.tasks.isEmpty ? theme.textSecondary : theme.text)
                }
                Spacer(minLength: 8)
                if targeted {
                    Label("Move here", systemImage: "arrow.down.to.line").labelStyle(CompactLabel()).font(.perchCaption.weight(.medium)).foregroundStyle(theme.accent)
                        .transition(.opacity)
                } else if day.tasks.isEmpty {
                    Text("Nothing planned").font(.perchCaption).foregroundStyle(theme.textMuted)
                } else {
                    CountBadge(count: day.tasks.count)
                }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 28)
            .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).fill(targeted ? theme.dropFill : (day.tasks.isEmpty ? Color.clear : theme.wash)))
            .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).strokeBorder(targeted ? theme.accent : Color.clear, lineWidth: 1.5))
            .lift(targeted, scale: 1.015)
            .motion(Motion.quick, value: targeted)
        }
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { ids, _ in
            var moved = false
            withMotion(Motion.bouncy, reduceMotion: reduceMotion) { moved = !model.move(taskIDs: ids, to: day.date).isEmpty }
            return moved
        } isTargeted: { targeted = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: List

/// Every open task in one sortable list. Inside an area it is that area's whole plan: its tasks as
/// trees, with their subtasks nested under them.
struct AllTasksScreen: View {
    @ObservedObject var model: AppModel
    @AppStorage("listGrouping") private var groupingName = TaskCalendar.Grouping.due.rawValue
    @AppStorage("listSort") private var sortName = TaskCalendar.Sort.due.rawValue
    @State private var filter = ""
    @State private var owner = "Everyone"
    @State private var showDone = false
    @State private var collapsed: Set<String> = []
    /// On a compact screen the filter, grouping and sorting sit behind a button in the counts line.
    @State private var showsControls = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.perchTheme) private var theme

    private var grouping: TaskCalendar.Grouping {
        let saved = TaskCalendar.Grouping(rawValue: groupingName) ?? .due
        // Inside one area there is nothing to group by area.
        return model.taskScope != nil && saved == .area ? .due : saved
    }
    private var title: String { TaskScope.title(view: .list, area: model.taskScope) }
    private var sort: TaskCalendar.Sort { TaskCalendar.Sort(rawValue: sortName) ?? .due }
    private var isFiltering: Bool { owner != "Everyone" || !jsTrim(filter).isEmpty }

    var body: some View {
        // Everything is worked out once per update, in a few passes over the tasks.
        let today = model.today
        let scope = model.taskScope
        let matching = model.scopedTasks.filter(matches)
        // In an area, subtasks sit under their parents, so only the top of each tree is grouped.
        let listed = scope == nil ? matching : model.roots(matching.filter { showDone || $0.isOpen })
        let groups = TaskCalendar.groups(listed, by: grouping, sort: sort, today: today, includeCompleted: showDone, areaOrder: model.areas)
        let subtaskCounts = scope == nil ? TaskCalendar.subtaskCounts(model.tasks) : [:]
        let openCount = matching.reduce(0) { $0 + ($1.isOpen ? 1 : 0) }
        let overdueCount = matching.reduce(0) { $0 + (TaskCalendar.isOverdue($1, today: today) ? 1 : 0) }

        HeaderScroll {
            header(open: openCount, overdue: overdueCount)
        } content: {
                LazyVStack(alignment: .leading, spacing: 0) {
                    QuickAddField(model: model, defaultArea: scope, takesNewTask: true).padding(.bottom, 8)
                    if groups.isEmpty { emptyState.frame(minHeight: 340) }
                    ForEach(groups) { group in
                        TaskGroupHeader(group: group, today: today, isCollapsed: collapsed.contains(group.id)) {
                            withMotion(Motion.smooth, reduceMotion: reduceMotion) {
                                if collapsed.contains(group.id) { collapsed.remove(group.id) } else { collapsed.insert(group.id) }
                            }
                        }
                        .padding(.top, group.id == groups.first?.id ? 2 : Metrics.gap)
                        if !collapsed.contains(group.id) {
                            if scope != nil {
                                ForEach(group.tasks) { TaskTree(model: model, task: $0, showArea: false, showDone: showDone) }
                            } else {
                                ForEach(group.tasks) { task in
                                    TaskRow(
                                        model: model, task: task, showArea: grouping != .area,
                                        hidesDue: group.kind == .today || group.kind == .tomorrow,
                                        showsOverdueAge: true, subtaskCount: subtaskCounts[task.id] ?? .init()
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Metrics.screenPadding - 8)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        #if os(iOS)
        .refreshable { await model.syncNow() }
        .scrollDismissesKeyboard(.interactively)
        #endif
        .motion(Motion.smooth, value: model.tasks.filter(\.isOpen).map { $0.id + ($0.due ?? "") })
        .motion(Motion.smooth, value: groupingName + sortName)
        .perchScreenBackground()
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: Header and controls

    private func header(open: Int, overdue: Int) -> some View {
        var stats = [HeaderStat(text: "\(open) open")]
        if overdue > 0 { stats.append(HeaderStat(text: "\(overdue) overdue", symbol: "exclamationmark.circle.fill", tint: theme.danger)) }
        let folds = sizeClass == .compact
        // A filter that is on always shows, so what is narrowing the list is never out of sight.
        let open = !folds || showsControls || isFiltering
        return ScreenHeader(title: title, stats: stats) {
            if folds {
                FilterToggle(isOpen: open, isFiltering: isFiltering) {
                    withMotion(Motion.smooth, reduceMotion: reduceMotion) {
                        if open {
                            filter = ""
                            owner = "Everyone"
                        }
                        showsControls = !open
                    }
                }
            }
        } controls: {
            if open {
                #if os(iOS)
                // No ViewThatFits around menus on the iPhone: on iOS 27.1 measuring both arrangements
                // never finished and the app stopped taking touches. See FolderScreen's header.
                VStack(alignment: .leading, spacing: 8) {
                    FilterField(text: $filter, prompt: "Filter tasks, or #label")
                    ScrollView(.horizontal, showsIndicators: false) { controls }
                }
                .transition(.opacity)
                #else
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        FilterField(text: $filter, prompt: "Filter tasks, or #label").frame(maxWidth: 260)
                        controls
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        FilterField(text: $filter, prompt: "Filter tasks, or #label")
                        ScrollView(.horizontal, showsIndicators: false) { controls }
                    }
                }
                .transition(.opacity)
                #endif
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Group by", selection: $groupingName) {
                    ForEach(TaskCalendar.Grouping.allCases.filter { model.taskScope == nil || $0 != .area }, id: \.rawValue) { Text(Self.name($0)).tag($0.rawValue) }
                }
                .pickerStyle(.inline)
            } label: {
                ControlChip(symbol: "square.grid.2x2", text: "Group: " + Self.name(grouping))
            }
            .modifier(ChipMenu())
            .help("Choose how tasks are grouped")

            Menu {
                Picker("Sort by", selection: $sortName) {
                    ForEach(TaskCalendar.Sort.allCases, id: \.rawValue) { Text(Self.name($0)).tag($0.rawValue) }
                }
                .pickerStyle(.inline)
            } label: {
                ControlChip(symbol: "arrow.up.arrow.down", text: "Sort: " + Self.name(sort))
            }
            .modifier(ChipMenu())
            .help("Choose the order inside each group")

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

            Button { showDone.toggle() } label: {
                ControlChip(symbol: showDone ? "checkmark.circle.fill" : "checkmark.circle", text: "Completed", isOn: showDone, showsChevron: false)
            }
            .buttonStyle(.plain)
            .help(showDone ? "Hide completed tasks" : "Show completed tasks")
            .accessibilityLabel("Show completed")
            .accessibilityAddTraits(showDone ? .isSelected : [])
        }
    }

    private static func name(_ grouping: TaskCalendar.Grouping) -> String {
        switch grouping {
        case .due: return "Due date"
        case .area: return "Area"
        case .priority: return "Priority"
        case .none: return "None"
        }
    }

    private static func name(_ sort: TaskCalendar.Sort) -> String {
        switch sort {
        case .priority: return "Priority"
        case .due: return "Due date"
        case .title: return "Title"
        case .newest: return "Newest"
        }
    }

    // MARK: Filtering

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
    private var emptyState: some View {
        if isFiltering {
            EmptyState(symbol: "line.3.horizontal.decrease.circle", title: "Nothing matches", message: "No task matches this filter.", actionTitle: "Clear filter") {
                filter = ""
                owner = "Everyone"
            }
        } else if let area = model.taskScope {
            let name = QuickAdd.simplifiedArea(area)
            if model.tasks.contains(where: { $0.area == area }) {
                EmptyState(
                    symbol: "tray", title: "No open tasks in \(name)",
                    message: "An area gathers the tasks for one part of your life. Add one above and it is filed here.",
                    actionTitle: showDone ? nil : "Show completed", action: { showDone = true }
                )
            } else {
                // An area added by name, before its first task.
                EmptyState(
                    symbol: "square.stack.3d.up", title: "\(name) is ready for its first task",
                    message: "Add a task above and Perch files it in “\(area)/Tasks” in your notebook. Nothing is created until then."
                        + (name.contains(" ") ? "" : " From anywhere, type #\(name) in a quick add.")
                )
            }
        } else {
            EmptyState(symbol: "checkmark.circle", title: "All clear", message: "Every open task shows up here, whatever its date or area. Add one above, like “Book flights friday #Personal”.")
        }
    }
}

// MARK: Hosts

public struct AllTasksHost: View {
    @ObservedObject var model: AppModel
    public init(model: AppModel) { self.model = model }
    public var body: some View { AllTasksScreen(model: model) }
}

public struct CalendarHost: View {
    @ObservedObject var model: AppModel
    public init(model: AppModel) { self.model = model }
    public var body: some View { CalendarScreen(model: model) }
}
