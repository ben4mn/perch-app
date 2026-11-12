import PerchKit
import SwiftUI

// The two sections, Tasks and Notes, and the sub-section bars that sit above their content.
//
// Tasks: a bar of areas (All, Work, Personal…) that scopes every task view, and a switcher for the
// view (Today, Upcoming, List, Calendar, Ready). Notes: a bar of the top-level folders and a second row
// of the folders around where you are, above the folder browser. On a wide iPhone screen the first bar
// becomes a slim column beside the content. The Mac and the iPhone both draw these same views.

private struct SubsectionRailKey: EnvironmentKey {
    static var defaultValue: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }
}

public extension EnvironmentValues {
    /// Whether a wide screen may show sub-sections as a column beside the content. On for iPhone;
    /// off on the Mac, whose sidebar already is that column.
    var perchSubsectionRail: Bool {
        get { self[SubsectionRailKey.self] }
        set { self[SubsectionRailKey.self] = newValue }
    }
}

// MARK: - Pills

/// One choice in a bar: an area, a folder, a view.
struct PillItem: Identifiable, Equatable {
    var id: String
    var title: String
    /// Drawn before the title: an emoji, else an icon, else a dot of this color.
    var emoji: String?
    var symbol: String?
    var dot: Color?
    var count = 0
    /// A small red dot after the count: something here is overdue.
    var alert = false
    /// What VoiceOver says: the name, the count and anything else worth hearing.
    var spoken: String
}

/// A bar of pills with one selected. The selection's fill slides from pill to pill; under Reduce Motion
/// it fades. Horizontal bars scroll sideways when they don't fit, and keep the selected pill in view.
struct PillBar: View {
    /// `tabs` is plain text with a line under the selected one, for a quieter second row.
    enum Style { case chips, segmented, rows, tabs }

    var items: [PillItem]
    var selection: String?
    var style = Style.chips
    /// What the bar is, for VoiceOver: "Areas", "Folders", "View".
    var label: String
    /// Smaller pills, for a second row.
    var compact = false
    /// Chips with no fill until the pointer is over one, and a count only on the selected one.
    var quiet = false
    /// False draws the pills at their own width with no scrolling, for a bar that is known to fit.
    var scrolls = true
    /// Pills share the width equally. Only without scrolling.
    var fills = false
    var inset: CGFloat = Metrics.screenPadding
    var leading: AnyView?
    var trailing: AnyView?
    /// Quick jumps offered by a long press (or a secondary click) on a pill.
    var menu: ((PillItem) -> AnyView)?
    var select: (String) -> Void

    @Namespace private var namespace
    @State private var barWidth: CGFloat = 0
    /// How wide the pills are together, to fade the bar's edge when they run past it.
    @State private var contentWidth: CGFloat = 0
    @Environment(\.perchTheme) private var theme
    /// Read so the bar is drawn again when the interface size or density changes.
    @Environment(\.perchDisplay) private var display
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let _ = display
        Group {
            if style == .rows {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 2) { content }
                            .padding(8)
                    }
                    .onChange(of: selection) { _, new in reveal(new, proxy) }
                    .task(id: items.map(\.id)) { await settle(proxy) }
                }
            } else if scrolls {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        row.padding(.horizontal, inset)
                            .background {
                                GeometryReader { geometry in
                                    Color.clear
                                        .onAppear { contentWidth = geometry.size.width.rounded() }
                                        .onChange(of: geometry.size.width) { _, new in contentWidth = new.rounded() }
                                }
                            }
                    }
                    // Pills that run past the edge fade out there, so the bar reads as "more this way"
                    // rather than a word cut in half.
                    .mask {
                        HStack(spacing: 0) {
                            Rectangle()
                            if contentWidth > barWidth + 1 {
                                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 36)
                            }
                        }
                    }
                    // A scroll view draws past its own edges, into the safe area and under whatever sits
                    // beside it. The bar stops where its frame does: at a button pinned after it, and at
                    // the screen's safe area, which on a folding phone can be a column of system controls.
                    .clipped()
                    .onChange(of: selection) { _, new in reveal(new, proxy) }
                    // The pills can arrive after the selection: a saved scope or folder is known at launch,
                    // its pill only once the notebook has loaded. A button arriving beside the bar, or the
                    // screen turning, changes how much of the bar shows. Either way, find the selection again.
                    .task(id: SettleKey(ids: items.map(\.id), width: barWidth)) { await settle(proxy) }
                    .background {
                        GeometryReader { geometry in
                            Color.clear
                                .onAppear { barWidth = geometry.size.width.rounded() }
                                .onChange(of: geometry.size.width) { _, new in barWidth = new.rounded() }
                        }
                    }
                }
            } else {
                row
            }
        }
        .motion(Motion.smooth, value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private var row: some View {
        HStack(spacing: style == .segmented ? 2 : (style == .tabs ? Metrics.tightGap + 6 : Metrics.tightGap)) { content }
            .padding(style == .segmented ? 3 : 0)
            .background {
                if style == .segmented {
                    RoundedRectangle(cornerRadius: Metrics.controlRadius + 2, style: .continuous).fill(theme.wash)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let leading { leading }
        ForEach(items) { item in
            Pill(
                item: item, isSelected: item.id == selection, style: style, compact: compact, quiet: quiet, fills: fills,
                namespace: namespace, action: { select(item.id) }
            )
            .contextMenu { if let menu { menu(item) } }
            .id(item.id)
        }
        if let trailing { trailing }
    }

    /// What the resting place of the bar depends on, besides the selection: which pills there are and how wide the bar is.
    private struct SettleKey: Equatable {
        var ids: [String]
        var width: CGFloat
    }

    /// Slides the selected pill into view, in the middle of the bar when there is room either side.
    /// Under Reduce Motion it jumps.
    private func reveal(_ id: String?, _ proxy: ScrollViewProxy) {
        guard let id else { return }
        // A beat later, once the new selection has been laid out, or the bar can stay where it was.
        DispatchQueue.main.async {
            withMotion(Motion.smooth, reduceMotion: reduceMotion) { proxy.scrollTo(id, anchor: .center) }
        }
    }

    /// Puts the selected pill in view without a slide, after the bar is first drawn or its pills or
    /// width change. The scroll view can only find a pill once it has been laid out, which on iPhone is
    /// a moment after the change that added it, so this waits for that and then checks once more.
    private func settle(_ proxy: ScrollViewProxy) async {
        for pause: UInt64 in [60_000_000, 300_000_000] {
            try? await Task.sleep(nanoseconds: pause)
            guard !Task.isCancelled, let selection, items.contains(where: { $0.id == selection }) else { return }
            proxy.scrollTo(selection, anchor: .center)
        }
    }

    /// How tall a pill is drawn. On iPhone its touch target is taller still.
    static func height(style: Style, compact: Bool) -> CGFloat {
        #if os(iOS)
        Metrics.scaled(style == .rows ? 40 : (compact ? 32 : (style == .segmented ? 32 : 36)))
        #else
        Metrics.scaled(style == .rows ? 28 : (compact ? 22 : (style == .segmented ? 22 : 26)))
        #endif
    }
}

private struct Pill: View {
    let item: PillItem
    let isSelected: Bool
    let style: PillBar.Style
    let compact: Bool
    let quiet: Bool
    let fills: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: AnyShape {
        style == .chips
            ? AnyShape(Capsule())
            : AnyShape(RoundedRectangle(cornerRadius: style == .rows ? 7 : Metrics.controlRadius, style: .continuous))
    }

    private var font: Font {
        if style == .tabs { return .perchCaption.weight(isSelected ? .semibold : .medium) }
        if style == .segmented || compact { return .perchCaption.weight(.medium) }
        return style == .rows ? .perchBody : .perchHeading
    }

    private var textColor: Color {
        if style == .tabs { return isSelected || hovering ? theme.text : theme.textSecondary }
        if !isSelected { return style == .rows ? theme.text : theme.textSecondary }
        return style == .chips ? theme.accent : theme.text
    }

    private var selectedFill: Color { style == .segmented ? theme.surface : theme.accentSoft }

    /// Extra touch height around the drawn pill on iPhone, so a 36-point pill is a 44-point target.
    private var touchPadding: CGFloat {
        #if os(iOS)
        max((Metrics.minTap - PillBar.height(style: style, compact: compact)) / 2, 0)
        #else
        0
        #endif
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                mark
                Text(item.title).lineLimit(1)
                if style == .rows || fills && style != .segmented { Spacer(minLength: 4) }
                // Quiet bars and tabs count only the selected pill; the listing below counts the rest.
                if item.count > 0, style != .tabs, !quiet || isSelected {
                    Text("\(item.count)")
                        .font(.perchSmall)
                        .monospacedDigit()
                        .foregroundStyle(isSelected && style != .segmented ? theme.accent : theme.textMuted)
                        .contentTransition(.numericText())
                }
                if item.alert {
                    Circle().fill(theme.danger).frame(width: 6, height: 6)
                }
            }
            .font(font)
            .foregroundStyle(textColor)
            .padding(.horizontal, style == .tabs ? 2 : (compact ? 9 : (style == .segmented ? 10 : 12)))
            .frame(minHeight: PillBar.height(style: style, compact: compact))
            .frame(maxWidth: style == .rows || fills ? .infinity : nil, alignment: style == .rows ? .leading : .center)
            .background { background }
            .padding(.vertical, touchPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(PerchPressStyle())
        .onHover { hovering = $0 }
        #if os(iOS)
        .hoverEffect(.highlight)
        #endif
        .motion(Motion.quick, value: hovering)
        .accessibilityLabel(item.spoken)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var mark: some View {
        if let emoji = item.emoji {
            Text(emoji)
        } else if let symbol = item.symbol {
            Image(systemName: symbol).imageScale(.small).fontWeight(.semibold)
                .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
        } else if let dot = item.dot {
            Circle().fill(dot).frame(width: 7, height: 7)
        }
    }

    private var background: some View {
        ZStack {
            if style == .tabs {
                // No fill: the selected tab is underlined, and the line slides from tab to tab.
                Color.clear
            } else if style == .chips, quiet {
                if hovering, !isSelected { shape.fill(theme.wash) }
            } else if style == .chips {
                shape.fill(hovering ? theme.washStrong : theme.wash)
            } else if hovering, !isSelected {
                shape.fill(theme.wash)
            }
            // The selection slides between pills. Under Reduce Motion each pill fades its own in and out.
            if reduceMotion {
                selection.opacity(isSelected ? 1 : 0)
            } else if isSelected {
                selection.matchedGeometryEffect(id: "selection", in: namespace)
            }
        }
    }

    @ViewBuilder
    private var selection: some View {
        if style == .tabs {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Capsule().fill(theme.accent).frame(height: 2)
            }
        } else if style == .chips {
            Capsule().fill(theme.accentSoft)
        } else {
            let box = RoundedRectangle(cornerRadius: style == .rows ? 7 : Metrics.controlRadius, style: .continuous)
            box.fill(selectedFill).overlay(box.strokeBorder(style == .segmented ? theme.border : Color.clear, lineWidth: 1))
        }
    }
}

/// A small button at the end of a bar: "+" to edit the areas, a jump to the other section.
private struct BarButton: View {
    var symbol: String
    var title: String?
    var spoken: String
    var compact = false
    var tint: Color?
    var action: () -> Void
    @State private var hovering = false
    @Environment(\.perchTheme) private var theme

    var body: some View {
        let height = PillBar.height(style: .chips, compact: compact)
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).imageScale(.small).fontWeight(.semibold)
                if let title { Text(title).lineLimit(1) }
            }
            .font(compact ? .perchCaption.weight(.medium) : .perchHeading)
            .foregroundStyle(tint ?? theme.textSecondary)
            .padding(.horizontal, title == nil ? 0 : 11)
            .frame(minWidth: height, minHeight: height)
            .background(Capsule().fill(hovering ? theme.washStrong : theme.wash))
            .padding(.vertical, touchPadding(height))
            .contentShape(Rectangle())
        }
        .buttonStyle(PerchPressStyle())
        .onHover { hovering = $0 }
        .motion(Motion.quick, value: hovering)
        .help(spoken)
        .accessibilityLabel(spoken)
    }

    private func touchPadding(_ height: CGFloat) -> CGFloat {
        #if os(iOS)
        max((Metrics.minTap - height) / 2, 0)
        #else
        0
        #endif
    }
}

/// Space above a section's bars.
private var barTop: CGFloat {
    #if os(iOS)
    2
    #else
    12
    #endif
}

/// How wide the column of sub-sections is on a wide iPhone screen.
private var railWidth: CGFloat { Metrics.scaled(184) }

// MARK: - Tasks

/// The areas as a bar (or a column): All, then each area with its open count and a dot when something
/// is overdue, then "+" to edit the list.
struct TaskScopeBar: View {
    @ObservedObject var model: AppModel
    var vertical = false
    @State private var editing = false
    @Environment(\.perchTheme) private var theme

    var body: some View {
        let counts = TaskScope.counts(model.tasks, today: model.today)
        let items = [PillItem(
            id: "", title: "All", symbol: "tray.full", count: counts.all.open, alert: counts.all.overdue > 0,
            spoken: TaskScope.spoken(name: "All areas", count: counts.all)
        )] + model.visibleAreas.map { area -> PillItem in
            let count = counts.byArea[area] ?? .init()
            let name = QuickAdd.simplifiedArea(area)
            let emoji = Palette.emoji(area)
            return PillItem(
                id: area, title: name, emoji: emoji, dot: emoji == nil ? Palette.area(area, theme: theme) : nil,
                count: count.open, alert: count.overdue > 0, spoken: TaskScope.spoken(name: name, count: count)
            )
        }
        PillBar(
            items: items, selection: model.taskScope ?? "", style: vertical ? .rows : .chips, label: "Areas",
            trailing: AnyView(editButton),
            menu: vertical ? nil : { item in AnyView(AreaJumpMenu(model: model, area: item.id.isEmpty ? nil : item.id)) },
            select: { model.setScope($0.isEmpty ? nil : $0) }
        )
        .areaEditor(isPresented: $editing, model: model, selectsNewArea: true)
    }

    @ViewBuilder
    private var editButton: some View {
        if vertical {
            Button { editing = true } label: {
                Label("Edit areas…", systemImage: "slider.horizontal.3")
                    .font(.perchBody)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: PillBar.height(style: .rows, compact: false), alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PerchPressStyle())
            .padding(.top, 6)
        } else {
            BarButton(symbol: "plus", spoken: "Edit areas", action: { editing = true })
        }
    }
}

/// The quick jumps behind a long press on an area: straight to one of its views, or to its notes.
struct AreaJumpMenu: View {
    @ObservedObject var model: AppModel
    /// Nil is every area.
    let area: String?

    var body: some View {
        let name = area.map { QuickAdd.simplifiedArea($0) } ?? "all areas"
        Section("Jump to \(name)") {
            ForEach(TaskViewKind.offered(wide: false, ready: false)) { view in
                Button {
                    model.showTasks(area: area)
                    model.show(view: view)
                } label: { Label(view.title, systemImage: view.symbol) }
            }
        }
        if let folder = model.notesFolder(forArea: area) {
            Button { model.route = .folder(folder) } label: { Label("Notes in \(name)", systemImage: "folder") }
        }
    }
}

/// Today, Upcoming, List and Calendar, plus Board where there is room and Ready to tick while
/// something is waiting.
struct TaskViewSwitcher: View {
    @ObservedObject var model: AppModel
    var scrolls = true
    var showsSymbols = false
    /// Offers the Board. On a screen too narrow for it, a saved Board shows as Upcoming.
    var offersBoard = false
    /// Tabs: the view a workspace pane is showing. Nil is the model's, as without tabs.
    var selected: TaskViewKind?

    var body: some View {
        if scrolls {
            // A phone's width: icons and names when they fit, names alone when those fit, and
            // otherwise the full bar scrolling sideways. A name is never cut short.
            ViewThatFits(in: .horizontal) {
                bar(symbols: true, scrolls: false).padding(.horizontal, Metrics.screenPadding)
                bar(symbols: false, scrolls: false).padding(.horizontal, Metrics.screenPadding)
                bar(symbols: true, scrolls: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            bar(symbols: showsSymbols, scrolls: false)
        }
    }

    private func bar(symbols: Bool, scrolls: Bool) -> some View {
        let ready = model.scopedReadyToTick.count
        // Ready is offered while something in scope is waiting: another area's proposals don't show here.
        let items = TaskViewKind.offered(wide: offersBoard, ready: model.offersReadyView).map { view in
            PillItem(
                id: view.rawValue, title: view.shortTitle, symbol: symbols ? view.symbol : nil,
                count: view == .ready ? ready : 0,
                spoken: view == .ready && ready > 0 ? "\(view.title), \(ready) waiting" : view.title
            )
        }
        return PillBar(
            items: items, selection: (selected ?? model.taskView).effective(wide: offersBoard).rawValue, style: .segmented, label: "View", scrolls: scrolls,
            select: { id in TaskViewKind(rawValue: id).map { model.show(view: $0) } }
        )
    }
}

/// The Tasks section: the areas, the view switcher, and the view in scope.
public struct TasksSectionView: View {
    @ObservedObject var model: AppModel
    /// Opens the calendar in this mode without changing the saved one, for the old Week route.
    var calendarStartMode: String?
    /// False leaves out the areas and the view switcher, where a sidebar beside this already has them.
    var showsBars = true
    @State private var width: CGFloat = 700
    @Environment(\.perchSubsectionRail) private var allowsRail
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Set by a layout that has already decided whether the Board is on offer, so the Board stays the
    /// Board while a pane beside it takes some of its width. Nil decides from this view's own width.
    var board: Bool?
    /// Tabs: the view to draw, for a workspace pane. Nil draws the model's, as without tabs.
    var view: TaskViewKind?

    public init(model: AppModel, calendarStartMode: String? = nil, showsBars: Bool = true, offersBoard: Bool? = nil, view: TaskViewKind? = nil) {
        self.model = model
        self.calendarStartMode = calendarStartMode
        self.showsBars = showsBars
        board = offersBoard
        self.view = view
    }

    private var shownView: TaskViewKind { view ?? model.taskView }

    /// The Board is offered, and drawn, where the content has room for its columns.
    private var offersBoard: Bool { board ?? AdaptiveLayout.offersBoard(width: Double(theme.display.layoutWidth(width))) }

    public var body: some View {
        let layoutWidth = Double(theme.display.layoutWidth(width))
        let offersBoard = offersBoard
        Group {
            if !showsBars {
                content
            } else if allowsRail, AdaptiveLayout.subsectionRail(width: layoutWidth) {
                // A wide iPhone screen: the areas down the side, so the content keeps its height.
                HStack(spacing: 0) {
                    TaskScopeBar(model: model, vertical: true)
                        .frame(width: railWidth)
                        .background(theme.sidebar)
                    Rectangle().fill(theme.hairline).frame(width: 1)
                    VStack(spacing: 0) {
                        HStack(spacing: Metrics.gap) {
                            TaskViewSwitcher(model: model, scrolls: false, showsSymbols: true, offersBoard: offersBoard, selected: view)
                            Spacer(minLength: 0)
                            notesJump(showsTitle: true)
                        }
                        .padding(.horizontal, Metrics.screenPadding)
                        .padding(.top, barTop + 4)
                        content
                    }
                }
            } else if layoutWidth >= AdaptiveLayout.gridWidth {
                VStack(spacing: 0) {
                    HStack(spacing: Metrics.gap) {
                        TaskScopeBar(model: model)
                        notesJump(showsTitle: true)
                        // The switcher keeps its own width, so no view's name is cut short; the areas
                        // beside it scroll in whatever is left.
                        TaskViewSwitcher(model: model, scrolls: false, showsSymbols: layoutWidth >= 900, offersBoard: offersBoard, selected: view)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                            .padding(.trailing, Metrics.screenPadding)
                    }
                    .padding(.top, barTop)
                    content
                }
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: Metrics.tightGap) {
                        TaskScopeBar(model: model)
                        notesJump(showsTitle: false).padding(.trailing, Metrics.screenPadding)
                    }
                    .padding(.top, barTop)
                    TaskViewSwitcher(model: model, offersBoard: offersBoard, selected: view).padding(.top, compactGap)
                    content
                }
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { width = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, new in width = new }
            }
        }
        .perchScreenBackground()
    }

    private var compactGap: CGFloat {
        #if os(iOS)
        0
        #else
        Metrics.tightGap
        #endif
    }

    /// One tap from an area's tasks to its folder of notes, when the area is also a folder.
    @ViewBuilder
    private func notesJump(showsTitle: Bool) -> some View {
        if let folder = model.notesFolder(forArea: model.taskScope) {
            let name = QuickAdd.simplifiedArea(folder)
            BarButton(symbol: "folder", title: showsTitle ? "Notes" : nil, spoken: "Notes in \(name)") {
                model.route = .folder(folder)
            }
            .transition(.perchPop(reduceMotion: reduceMotion))
        }
    }

    private var content: some View {
        ZStack {
            // Changing the area keeps the view where it is (the calendar stays on its month); changing
            // the view swaps one screen for the next.
            screen
                .id(shownView.effective(wide: offersBoard))
                .transition(.perchSwap(reduceMotion: reduceMotion))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .motion(Motion.smooth, value: shownView.effective(wide: offersBoard))
        .motion(Motion.smooth, value: model.taskScope)
    }

    @ViewBuilder
    private var screen: some View {
        switch shownView.effective(wide: offersBoard) {
        case .today: TaskListScreen(model: model, route: .today)
        case .upcoming: TaskListScreen(model: model, route: .upcoming)
        case .ready: TaskListScreen(model: model, route: .ready)
        case .list: AllTasksScreen(model: model)
        case .calendar: CalendarScreen(model: model, startMode: calendarStartMode)
        case .board: TaskBoardScreen(model: model)
        }
    }
}

// MARK: - Notes

/// The folder chips above the notes browser.
struct NotesFolderBars: View {
    @ObservedObject var model: AppModel
    let path: String
    var showsTop = true
    var go: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let sections = NotesSubsections(files: model.files, path: path, kinds: model.notesKind.kinds)
        VStack(spacing: rowGap) {
            if showsTop {
                HStack(spacing: Metrics.tightGap) {
                    NotesTopBar(model: model, sections: sections, go: go)
                    tasksJump.padding(.trailing, Metrics.screenPadding)
                }
            }
            if !sections.row.isEmpty {
                PillBar(
                    items: sections.row.map(Self.item), selection: sections.selectedInRow, style: .tabs, label: "Folders in \(name(sections.rowParent))",
                    compact: true, leading: sections.up.map { up in
                        AnyView(BarButton(symbol: "chevron.left", title: up.name, spoken: "Up to \(up.name)", compact: true) { go(up.path) })
                    },
                    select: go
                )
                .transition(.opacity)
            }
        }
        .padding(.top, barTop)
        .motion(Motion.smooth, value: sections.rowParent)
    }

    private var rowGap: CGFloat {
        #if os(iOS)
        0
        #else
        Metrics.tightGap
        #endif
    }

    private func name(_ path: String) -> String { (path as NSString).lastPathComponent }

    static func item(_ chip: NotesSubsections.Chip) -> PillItem {
        PillItem(id: chip.path, title: chip.name, count: chip.count, spoken: "\(chip.name), \(FolderListing.counted(chip.count, "item"))")
    }

    /// One tap from a folder to its area's tasks, when the folder sits in an area.
    @ViewBuilder
    var tasksJump: some View {
        if let area = model.area(forFolder: path) {
            BarButton(symbol: "checklist", title: sizeClass == .compact ? nil : "Tasks", spoken: "Tasks in \(QuickAdd.simplifiedArea(area))") { model.showTasks(area: area) }
                .transition(.perchPop(reduceMotion: reduceMotion))
        }
    }
}

/// All, then every top-level folder, as a bar or a column.
private struct NotesTopBar: View {
    @ObservedObject var model: AppModel
    let sections: NotesSubsections
    var vertical = false
    var go: (String) -> Void

    var body: some View {
        let items = [PillItem(
            id: "", title: "All", symbol: "tray.full", count: sections.total,
            spoken: "All notes, \(FolderListing.counted(sections.total, "item"))"
        )] + sections.top.map(NotesFolderBars.item)
        PillBar(items: items, selection: sections.selectedTop ?? "", style: vertical ? .rows : .chips, label: "Folders", quiet: !vertical, select: go)
    }
}

/// The Notes section: the folder bars above the folder browser.
public struct NotesSectionView: View {
    @ObservedObject var model: AppModel
    let path: String
    /// Where a tap goes. Leave it out on the Mac, which changes `model.route`; the iPhone changes the
    /// folder in place and pushes files onto its own stack.
    let open: ((Route) -> Void)?
    /// False leaves out the folder chips, where a sidebar beside this already has the folder tree.
    var showsBars = true
    @State private var width: CGFloat = 700
    @Environment(\.perchSubsectionRail) private var allowsRail
    @Environment(\.perchTheme) private var theme

    public init(model: AppModel, path: String, showsBars: Bool = true, open: ((Route) -> Void)? = nil) {
        self.model = model
        self.path = path
        self.showsBars = showsBars
        self.open = open
    }

    public var body: some View {
        let rail = allowsRail && AdaptiveLayout.subsectionRail(width: Double(theme.display.layoutWidth(width)))
        Group {
            if !showsBars {
                browser
            } else if rail {
                HStack(spacing: 0) {
                    NotesTopBar(model: model, sections: NotesSubsections(files: model.files, path: path, kinds: model.notesKind.kinds), vertical: true, go: goToFolder)
                        .frame(width: railWidth)
                        .background(theme.sidebar)
                    Rectangle().fill(theme.hairline).frame(width: 1)
                    VStack(spacing: 0) {
                        NotesFolderBars(model: model, path: path, showsTop: false, go: goToFolder)
                        browser
                    }
                }
            } else {
                VStack(spacing: 0) {
                    NotesFolderBars(model: model, path: path, go: goToFolder)
                    browser
                }
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { width = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, new in width = new }
            }
        }
        .perchScreenBackground()
    }

    private var browser: some View {
        FolderScreen(
            model: model, path: path, kinds: model.notesKind.kinds, rootTitle: "Notes",
            kind: Binding(get: { model.notesKind }, set: { model.setNotesKind($0) }),
            besideFolderChips: showsBars,
            open: { go($0) }
        )
        // A new folder, or another kind of file, is a new listing: it arrives with the folder's own entrance.
        .id(path + "|" + model.notesKind.rawValue)
    }

    private func goToFolder(_ path: String) { go(.folder(path)) }

    private func go(_ route: Route) {
        if let open { open(route) } else { model.route = route }
    }
}

// MARK: - Editing the areas

/// Add an area by name, change the order, hide one. Nothing here touches the notebook.
public struct AreaEditor: View {
    @ObservedObject var model: AppModel
    /// Scopes Tasks to an area as soon as it is added, when the editor was opened from the bar.
    var selectsNewArea = false
    /// Leaves out the title, Done and the scrolling, when the editor sits inside a screen that has its own.
    var embedded = false
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.perchTheme) private var theme
    @Environment(\.perchDisplay) private var display
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: AppModel, selectsNewArea: Bool = false, embedded: Bool = false) {
        self.model = model
        self.selectsNewArea = selectsNewArea
        self.embedded = embedded
    }

    private var suggestions: [String] {
        let folders = FolderListing(files: model.files, path: "").folders.map(\.name)
        return AreaList.suggestions(topLevelFolders: folders, existing: model.areas, extras: ["Consulting"])
    }

    public var body: some View {
        let _ = display
        if embedded {
            form
        } else {
            ScrollView { form.padding(Metrics.screenPadding) }
                #if os(macOS)
                .frame(minWidth: 360, idealWidth: 400, minHeight: 320, idealHeight: 460)
                #endif
        }
    }

    private var form: some View {
        let areas = model.areas
        let counts = TaskScope.counts(model.tasks, today: model.today).byArea
        return VStack(alignment: .leading, spacing: Metrics.gap) {
                if !embedded {
                    HStack {
                        Text("Areas").font(.perchStyle(.headline)).foregroundStyle(theme.text)
                        Spacer()
                        Button("Done") { dismiss() }.buttonStyle(PerchButtonStyle()).keyboardShortcut(.cancelAction)
                    }
                }
                Text("Areas are the sub-sections of Tasks: one for each part of your life or work. Pick one and Today, Upcoming, List and Calendar show only its tasks.")
                    .font(.perchCaption).foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Metrics.tightGap) {
                    FilterField(text: $name, prompt: "New area, like Consulting", symbol: "plus")
                        .onSubmit(addTyped)
                    Button("Add", action: addTyped)
                        .buttonStyle(PerchButtonStyle(prominent: true))
                        .disabled(AreaList.cleaned(name) == nil)
                }
                if let problem = AreaList.problem(with: name) {
                    Label(problem, systemImage: "exclamationmark.circle")
                        .font(.perchCaption).foregroundStyle(theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }

                let suggestions = suggestions
                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: Metrics.tightGap) {
                        SectionLabel("Add with one tap")
                        FlowLayout(spacing: Metrics.tightGap) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button { add(suggestion) } label: {
                                    ControlChip(symbol: "plus", text: suggestion, showsChevron: false)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Add \(suggestion)")
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel("Your areas").padding(.bottom, 4)
                    ForEach(Array(areas.enumerated()), id: \.element) { index, area in
                        row(area, index: index, last: areas.count - 1, open: counts[area]?.open ?? 0)
                    }
                }
                .motion(Motion.smooth, value: areas)

                Text("Adding an area writes nothing to your notebook. Its Tasks folder appears when you add its first task. A hidden area leaves the bar; its tasks still show under All.")
                    .font(.perchCaption).foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ area: String, index: Int, last: Int, open: Int) -> some View {
        let hidden = AreaList.isHidden(area, in: model.areas, preferences: model.areaPreferences)
        let name = QuickAdd.simplifiedArea(area)
        let hasTasks = model.tasks.contains { $0.area == area }
        return HStack(spacing: Metrics.tightGap) {
            Group {
                if let emoji = Palette.emoji(area) {
                    Text(emoji)
                } else {
                    Circle().fill(Palette.area(area, theme: theme)).frame(width: 8, height: 8)
                }
            }
            .frame(width: Metrics.scaled(22))
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.perchRow).foregroundStyle(hidden ? theme.textMuted : theme.text).lineLimit(1)
                Text(hidden ? "Hidden" : (hasTasks ? "\(open) open" : "No tasks yet"))
                    .font(.perchCaption).foregroundStyle(theme.textMuted)
            }
            Spacer(minLength: 4)
            icon("chevron.up", "Move \(name) up", disabled: index == 0) { change { AreaList.move(area, by: -1, in: model.areas, preferences: &$0) } }
            icon("chevron.down", "Move \(name) down", disabled: index == last) { change { AreaList.move(area, by: 1, in: model.areas, preferences: &$0) } }
            icon(hidden ? "eye.slash" : "eye", hidden ? "Show \(name)" : "Hide \(name)") { change { AreaList.setHidden(!hidden, area: area, in: &$0) } }
            if model.canRemoveArea(area) {
                icon("trash", "Remove \(name)", tint: theme.danger) { change { AreaList.remove(area, from: &$0) } }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, Metrics.dense(5))
        .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).fill(theme.wash))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(name)
    }

    private func icon(_ symbol: String, _ label: String, disabled: Bool = false, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.perchCaption.weight(.semibold))
                .foregroundStyle(tint ?? theme.textSecondary)
                .frame(width: iconSize, height: iconSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(PerchPressStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
        .help(label)
        .accessibilityLabel(label)
    }

    private var iconSize: CGFloat {
        #if os(iOS)
        Metrics.minTap - 4
        #else
        Metrics.scaled(26)
        #endif
    }

    private func change(_ body: (inout AreaPreferences) -> Void) {
        var preferences = model.areaPreferences
        body(&preferences)
        withMotion(Motion.smooth, reduceMotion: reduceMotion) { model.areaPreferences = preferences }
    }

    private func addTyped() {
        guard AreaList.cleaned(name) != nil else { return }
        add(name)
        name = ""
    }

    private func add(_ name: String) {
        withMotion(Motion.smooth, reduceMotion: reduceMotion) {
            if let area = model.addArea(name), selectsNewArea { model.setScope(area) }
        }
    }
}

private struct AreaEditorPresenter: ViewModifier {
    @Binding var isPresented: Bool
    @ObservedObject var model: AppModel
    var selectsNewArea: Bool
    @Environment(\.perchTheme) private var theme

    func body(content: Content) -> some View {
        #if os(iOS)
        content.sheet(isPresented: $isPresented) {
            AreaEditor(model: model, selectsNewArea: selectsNewArea)
                .perchPresented()
                .presentationDetents([.medium, .large])
        }
        #else
        content.popover(isPresented: $isPresented, arrowEdge: .bottom) {
            AreaEditor(model: model, selectsNewArea: selectsNewArea).perchPresented()
        }
        #endif
    }
}

extension View {
    /// Shows the area editor: a sheet on iPhone, a popover on the Mac.
    func areaEditor(isPresented: Binding<Bool>, model: AppModel, selectsNewArea: Bool = false) -> some View {
        modifier(AreaEditorPresenter(isPresented: isPresented, model: model, selectsNewArea: selectsNewArea))
    }
}

// MARK: - The section switcher

/// Tasks | Notes, at the top of the Mac's sidebar. One click, and each side comes back where it was left.
struct SectionSwitcher: View {
    @ObservedObject var model: AppModel
    /// The section to mark, when it isn't simply the model's: none while Agents or Search is in front.
    var selection: AppSection??
    /// What a tap does, when it isn't simply showing the section.
    var select: ((AppSection) -> Void)?

    var body: some View {
        let selected: AppSection? = selection ?? model.section
        PillBar(
            items: AppSection.allCases.map { PillItem(id: $0.rawValue, title: $0.title, symbol: $0.symbol, spoken: $0.title) },
            selection: selected?.rawValue, style: .segmented, label: "Section", scrolls: false, fills: true,
            select: { id in
                guard let section = AppSection(rawValue: id) else { return }
                if let select { select(section) } else { model.show(section) }
            }
        )
    }
}
