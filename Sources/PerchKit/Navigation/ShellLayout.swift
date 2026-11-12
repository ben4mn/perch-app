import Foundation

// How the iPhone app arranges itself for the room it is given, and how one place in the app is shown
// in each arrangement. Nothing here knows about a device: a folded phone, an unfolded one, a phone on
// its side and an iPad window are all just a width and a height. The views read these answers, so
// opening or closing a folding phone changes the arrangement and never the place.

/// The four places the iPhone's navigation leads: the two sections, and Agents and Search beside them.
/// The tab bar and the sidebar both draw these, with the same names and icons.
public enum ShellDestination: String, CaseIterable, Identifiable, Sendable {
    case tasks, notes, agents, search

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tasks: return AppSection.tasks.title
        case .notes: return AppSection.notes.title
        case .agents: return "Agents"
        case .search: return "Search"
        }
    }

    public var symbol: String {
        switch self {
        case .tasks: return AppSection.tasks.symbol
        case .notes: return AppSection.notes.symbol
        case .agents: return "person.2"
        case .search: return "magnifyingglass"
        }
    }

    /// The section this destination is, when it is one.
    public var section: AppSection? {
        switch self {
        case .tasks: return .tasks
        case .notes: return .notes
        default: return nil
        }
    }

    public init(_ section: AppSection) { self = section == .tasks ? .tasks : .notes }
}

/// What the user last chose for the sidebar on a wide screen. Saved on each device.
public enum SidebarPreference: String, CaseIterable, Sendable {
    /// The whole sidebar: views, areas, the folder tree.
    case expanded
    /// A slim column of icons.
    case rail

    public static let storageKey = "shellSidebar"

    public var toggled: SidebarPreference { self == .expanded ? .rail : .expanded }
}

/// The arrangement for a given room.
public struct ShellLayout: Equatable, Sendable {
    public enum Navigation: Equatable, Sendable {
        /// The system tab bar, with chip bars above the content: a phone-sized screen.
        case tabs
        /// A slim column of icons on the leading edge. The full sidebar opens over the content as a drawer.
        case rail
        /// The full sidebar, always showing beside the content.
        case sidebar
    }

    /// The narrowest screen that gets the sidebar instead of tabs.
    public static let wideWidth = AdaptiveLayout.wideWidth
    /// A screen at least this tall counts as wide by its whole width, even when the system keeps a
    /// column of it for its own controls. See `init`.
    public static let tallHeight: Double = 600
    /// The least content a rail may leave beside it: the width of the largest ordinary phone.
    public static let minimumRailContent: Double = 440
    /// The narrowest content that is split into two panes: 310 points each.
    public static let splitWidth: Double = PaneLayout.minimumPane * 2
    public static let baseSidebarWidth: Double = 232
    public static let baseRailWidth: Double = 68
    /// The narrowest room that keeps the full sidebar open beside the content at the default
    /// interface size: the sidebar, its line, and two panes. A larger interface needs more, because
    /// its sidebar is wider; below this the sidebar is a drawer, so the content keeps its two panes.
    public static let pinnedSidebarWidth: Double = baseSidebarWidth + 1 + splitWidth

    public var navigation: Navigation
    /// Whether the full sidebar can stay open beside the content at this size.
    public var canPinSidebar: Bool
    public var sidebarWidth: Double
    public var railWidth: Double
    /// The width left for the content, beside whatever navigation is permanently showing.
    public var contentWidth: Double
    public var height: Double

    /// - Parameters:
    ///   - width: the room the app can draw in: the screen inside the safe area. Everything is laid
    ///     out within this.
    ///   - height: the same, top to bottom.
    ///   - sceneWidth: the whole screen's width, safe area or not. Leave it out when they are the same.
    ///   - sceneHeight: the whole screen's height. It must not shrink when the keyboard comes up, or
    ///     typing would change the arrangement.
    ///   - allowsWide: the Display setting "Use wide layouts on large screens". Off keeps the tabs.
    ///   - scale: the interface size's scale, so a larger interface gets a wider sidebar.
    ///
    /// Which arrangement:
    ///
    /// - **Wide or not.** 640 points of room is wide. So is a screen that is 640 points wide and
    ///   600 tall of which the system keeps a column: a folding phone, open and upright, is 669
    ///   points wide, and if iOS draws its status strip in a column there as it does on the cover
    ///   screen, the app is given about 583. That is still the big screen, and it gets the rail.
    ///   A short screen gets no such allowance: the same phone closed and on its side is 678 by 466
    ///   with 592 for the app, and there iOS already draws the tab bar in its own column, at no cost
    ///   to the content. A rail would be a second column beside it.
    /// - **Sidebar or rail.** The sidebar stays open where two panes still fit beside it. Otherwise
    ///   it is a drawer over the rail.
    public init(
        width: Double, height: Double, sceneWidth: Double? = nil, sceneHeight: Double? = nil,
        allowsWide: Bool = true, preference: SidebarPreference = .expanded, scale: Double = 1
    ) {
        let scale = min(max(scale, 0.9), 1.3)
        sidebarWidth = (Self.baseSidebarWidth * scale).rounded()
        railWidth = (Self.baseRailWidth * scale).rounded()
        self.height = height
        let room = AdaptiveLayout.effectiveWidth(width, allowsWide: allowsWide)
        let scene = AdaptiveLayout.effectiveWidth(max(sceneWidth ?? width, width), allowsWide: allowsWide)
        let tall = max(sceneHeight ?? height, height) >= Self.tallHeight
        // One point for the line between the navigation and the content.
        let besideRail = max(width - railWidth - 1, 0)
        let besideSidebar = max(width - sidebarWidth - 1, 0)
        let wide = room >= Self.wideWidth || (scene >= Self.wideWidth && tall && besideRail >= Self.minimumRailContent)
        guard wide else {
            navigation = .tabs
            canPinSidebar = false
            contentWidth = width
            return
        }
        canPinSidebar = besideSidebar >= Self.splitWidth
        navigation = canPinSidebar && preference == .expanded ? .sidebar : .rail
        contentWidth = navigation == .sidebar ? besideSidebar : besideRail
    }

    public var isWide: Bool { navigation != .tabs }

    /// Whether the content has room for two panes: a list and what is selected in it.
    public var splitsContent: Bool { isWide && contentWidth >= Self.splitWidth }

    /// Whether the Board view is offered: wherever the content has room for its columns, which
    /// includes a phone on its side that still has tabs.
    public var offersBoard: Bool { AdaptiveLayout.offersBoard(width: contentWidth) }

    /// Whether the content draws its own chip bars (areas and the view switcher, or folders). The
    /// expanded sidebar replaces them; tabs and the rail don't.
    public var showsContentBars: Bool { navigation != .sidebar }

    // MARK: The sidebar's swipe

    /// How far a swipe must travel, or be heading when it ends, to open or close the sidebar.
    public static let swipeDistance: Double = 44

    /// What a horizontal drag on the sidebar or rail asks for, or nil when it wasn't far enough to mean
    /// anything. Dragging away from the leading edge opens the sidebar; dragging toward it closes it.
    /// - Parameter translation: positive away from the leading edge (already flipped for right-to-left).
    public static func swipe(translation: Double, predicted: Double, vertical: Double) -> SidebarPreference? {
        let travel = abs(translation) >= swipeDistance ? translation : predicted
        guard abs(travel) >= swipeDistance, abs(translation) > abs(vertical) else { return nil }
        return travel > 0 ? .expanded : .rail
    }
}

/// The widths of two panes side by side, with a divider that can be dragged.
public enum PaneLayout {
    /// The narrowest a pane gets. Two of them fit beside the sidebar on an open folding phone held
    /// sideways even if the system keeps a column of that screen (865 - 233 = 632), and don't fit
    /// beside the rail when it is upright (669 - 69 = 600), where one wide pane reads better.
    public static let minimumPane: Double = 310
    public static let defaultFraction = 0.44
    public static let fractionRange = 0.3...0.62

    /// The trailing pane's width: the saved fraction of the content, never under 310 points for
    /// either pane. With less than 620 points there is no split and the answer is 0.
    public static func trailingWidth(content: Double, fraction: Double = defaultFraction) -> Double {
        guard content >= minimumPane * 2 else { return 0 }
        let wanted = content * min(max(fraction, fractionRange.lowerBound), fractionRange.upperBound)
        return min(max(wanted, minimumPane), content - minimumPane).rounded()
    }

    /// The fraction to save after the divider was dragged to give the trailing pane `width`.
    public static func fraction(trailingWidth width: Double, content: Double) -> Double {
        guard content > 0 else { return defaultFraction }
        let clamped = min(max(width, minimumPane), max(content - minimumPane, minimumPane))
        return min(max(clamped / content, fractionRange.lowerBound), fractionRange.upperBound)
    }

    /// The leading list's width beside a reading pane: narrower than half, since the list is for picking.
    public static func listWidth(content: Double, scale: Double = 1) -> Double {
        guard content >= minimumPane * 2 else { return content }
        return min(max((content * 0.38).rounded(), minimumPane), max(minimumPane, (380 * scale).rounded()), content - minimumPane)
    }
}

// MARK: - Workspace panes (experimental tabs and split view)

/// How two workspace panes share the content. One rule for the Mac window and the iPhone's wide
/// layout: each is just a width and a height.
public enum WorkspaceLayout {
    public enum Arrangement: Equatable, Sendable {
        /// One pane on screen: the workspace has one, or there is no room for two and the focused one shows.
        case single
        case sideBySide
        /// One above the other.
        case stacked
    }

    /// The narrowest a pane gets beside another: the same 310 points as a list beside its detail. An
    /// open folding phone on its side has 718 points beside the sidebar (632 if the system keeps a
    /// column), so two fit; upright it has 600 beside the rail, so they don't.
    public static let minimumPaneWidth = PaneLayout.minimumPane
    /// The shortest a pane gets above another: its tab strip, a navigation bar and a few rows.
    /// An open folding phone upright has about 870 points, so two fit, at about 435 each. A phone
    /// on its side (430 points) and the folding phone on its side (669) are too short to stack.
    public static let minimumPaneHeight: Double = 340
    /// The line between the panes.
    public static let divider: Double = 1

    /// - Parameter preferred: the way the user split. Nil picks whichever fits, side by side first:
    ///   the iPhone, where turning the phone decides. A preferred way that doesn't fit gives way to
    ///   the other, and when neither fits only the focused pane shows.
    public static func arrangement(
        width: Double, height: Double, isSplit: Bool, preferred: SplitAxis? = nil,
        minimumWidth: Double = minimumPaneWidth, minimumHeight: Double = minimumPaneHeight
    ) -> Arrangement {
        guard isSplit else { return .single }
        let beside = width >= minimumWidth * 2 + divider
        let above = height >= minimumHeight * 2 + divider
        if preferred == .vertical, above { return .stacked }
        if beside { return .sideBySide }
        return above ? .stacked : .single
    }

    /// The first pane's length (its width side by side, its height stacked): the saved share of the
    /// room, leaving both panes at least `minimum`.
    public static func firstLength(total: Double, fraction: Double, minimum: Double) -> Double {
        let room = total - divider
        guard room >= minimum * 2 else { return max(room / 2, 0).rounded() }
        let share = min(max(fraction, Workspace.fractionRange.lowerBound), Workspace.fractionRange.upperBound)
        return min(max(room * share, minimum), room - minimum).rounded()
    }

    /// The share to save after the divider was dragged to give the first pane `length`.
    public static func fraction(firstLength length: Double, total: Double, minimum: Double) -> Double {
        let room = total - divider
        guard room > 0 else { return 0.5 }
        let clamped = min(max(length, minimum), max(room - minimum, minimum))
        return min(max(clamped / room, Workspace.fractionRange.lowerBound), Workspace.fractionRange.upperBound)
    }
}

// MARK: - One place, two arrangements

/// Where the user is, in terms that don't depend on the arrangement. Folding or unfolding the phone
/// changes the `ShellLayout` and so the `ShellPresentation`; it never changes this.
public struct ShellPlace: Equatable, Sendable {
    public var destination: ShellDestination
    /// The saved task view. `ShellPresentation.taskView` is the one drawn.
    public var taskView: TaskViewKind
    /// The task whose detail is open, by id.
    public var selectedTask: String?
    /// The files opened in Notes, the one showing last. A link followed inside a note adds to it.
    public var notesFiles: [String]
    /// The files opened from Search, the one showing last.
    public var searchFiles: [String]

    public init(
        destination: ShellDestination = .tasks, taskView: TaskViewKind = .today, selectedTask: String? = nil,
        notesFiles: [String] = [], searchFiles: [String] = []
    ) {
        self.destination = destination
        self.taskView = taskView
        self.selectedTask = selectedTask
        self.notesFiles = notesFiles
        self.searchFiles = searchFiles
    }
}

/// How a place is shown in an arrangement.
public struct ShellPresentation: Equatable, Sendable {
    public enum TaskDetail: Equatable, Sendable {
        case none
        /// Over the screen: narrow screens, and any destination with no pane for it.
        case sheet
        /// In the trailing pane, beside the list it was picked from.
        case pane
    }

    public enum File: Equatable, Sendable {
        case none
        /// Pushed over the list, with Back.
        case pushed
        /// Beside the list.
        case pane
    }

    /// What fills the trailing pane of Tasks.
    public enum TasksTrailing: Equatable, Sendable {
        /// No pane: the view has the whole width.
        case none
        /// The selected task.
        case detail
        /// Today's companion: up next, the week, proposals.
        case dashboard
        /// "Choose a task", beside a list.
        case placeholder
    }

    public var taskDetail: TaskDetail
    public var note: File
    public var searchResult: File
    /// The task view drawn: the saved one, or Upcoming where the Board has no room.
    public var taskView: TaskViewKind
    public var tasksTrailing: TasksTrailing
    /// The Search pane shows the selected task instead of a file.
    public var searchShowsTask: Bool

    public init(place: ShellPlace, layout: ShellLayout) {
        let split = layout.splitsContent
        taskView = place.taskView.effective(wide: layout.offersBoard)
        note = place.notesFiles.isEmpty ? .none : (split ? .pane : .pushed)

        let hasTask = place.selectedTask != nil
        // The pane for a task exists in Tasks and in Search. Anywhere else a task opens over the screen.
        let paneForTask = split && (place.destination == .tasks || place.destination == .search)
        taskDetail = hasTask ? (paneForTask ? .pane : .sheet) : .none

        searchShowsTask = split && place.destination == .search && hasTask
        searchResult = place.searchFiles.isEmpty ? .none : (split ? .pane : .pushed)

        if !split {
            tasksTrailing = .none
        } else if hasTask {
            tasksTrailing = .detail
        } else {
            switch taskView {
            case .today: tasksTrailing = .dashboard
            case .upcoming, .list, .ready: tasksTrailing = .placeholder
            // The calendar and the board use the whole width until a task is picked.
            case .calendar, .board: tasksTrailing = .none
            }
        }
    }
}

public extension ShellPlace {
    /// Opens a file in Notes. From the browser it replaces what was open; from a link inside a note it
    /// is added on top, so Back (or closing it) returns to the note the link was in.
    mutating func openNote(_ path: String, fromLink: Bool) {
        if notesFiles.last == path { return }
        if fromLink { notesFiles.append(path) } else { notesFiles = [path] }
    }

    /// Closes the file on top. Returns the file now showing, if any.
    @discardableResult
    mutating func closeNote() -> String? {
        if !notesFiles.isEmpty { notesFiles.removeLast() }
        return notesFiles.last
    }

    /// A file was renamed or moved: whatever had it open has it open still, under its new path.
    mutating func rename(_ old: String, to new: String) {
        notesFiles = notesFiles.map { $0 == old ? new : $0 }
        searchFiles = searchFiles.map { $0 == old ? new : $0 }
    }

    /// Drops files that no longer exist (deleted, renamed on another device) from what is open.
    mutating func prune(existing: (String) -> Bool) {
        notesFiles.removeAll { !existing($0) }
        searchFiles.removeAll { !existing($0) }
    }
}
