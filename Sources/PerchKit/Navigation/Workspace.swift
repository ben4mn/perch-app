import Foundation

// EXPERIMENTAL: tabs and split view. Off unless the "Tabs and split view (experimental)" setting is on.
//
// Everything here is plain data: which places are open as tabs, in one pane or two, and which has the
// focus. Nothing knows about a view or a device, and nothing is ever written to the notebook; the
// apps keep a workspace in preferences. To remove the feature, delete this file, WorkspaceTests.swift,
// WorkspaceStore.swift and WorkspaceViews.swift, then the few hooks marked "Tabs:" that stop compiling.

/// A screen that is neither a task view, a folder nor a file.
public enum WorkspacePage: String, Codable, CaseIterable, Sendable {
    case insights, activity, importer, settings, agents

    public var title: String {
        switch self {
        case .insights: return "Insights"
        case .activity: return "Activity"
        case .importer: return "Import"
        case .settings: return "Settings"
        case .agents: return "Agents"
        }
    }

    public var symbol: String {
        switch self {
        case .insights: return "chart.bar"
        case .activity: return "bubble.left.and.text.bubble.right"
        case .importer: return "square.and.arrow.down"
        case .settings: return "gearshape"
        case .agents: return "person.2"
        }
    }
}

/// Somewhere a tab can be. The area in scope is not part of it: an area filters every task view in
/// the window at once, as it does without tabs.
public enum WorkspaceItem: Hashable, Sendable {
    case tasks(TaskViewKind)
    /// A folder in Notes. The empty path is the top level.
    case folder(String)
    /// A note, board, whiteboard or a task's own file.
    case file(String)
    case search
    case page(WorkspacePage)

    /// Where a new tab opens: Today in Tasks, the top folder in Notes.
    public static func home(for section: AppSection) -> WorkspaceItem {
        section == .tasks ? .tasks(.today) : .folder("")
    }

    /// The section this belongs to. Search and the pages belong to neither.
    public var section: AppSection? {
        switch self {
        case .tasks: return .tasks
        case .folder, .file: return .notes
        case .search, .page: return nil
        }
    }

    /// The file this shows, when it shows one.
    public var filePath: String? {
        if case let .file(path) = self { return path }
        return nil
    }

    public var title: String {
        switch self {
        case let .tasks(view): return view.title
        case let .folder(path): return path.isEmpty ? "Notes" : (path as NSString).lastPathComponent
        case let .file(path): return VaultFile(path: path).title
        case .search: return "Search"
        case let .page(page): return page.title
        }
    }

    public var symbol: String {
        switch self {
        case let .tasks(view): return view.symbol
        case let .folder(path): return path.isEmpty ? "tray.full" : "folder"
        case let .file(path):
            switch VaultFile.classify(path) {
            case .board: return "rectangle.split.3x1"
            case .whiteboard: return "scribble"
            case .notebook: return "curlybraces.square"
            case .task: return "checkmark.circle"
            default: return "doc.text"
            }
        case .search: return "magnifyingglass"
        case let .page(page): return page.symbol
        }
    }

    /// One line of text for this place: what is saved, and what snapshot steps and launch arguments
    /// type. `today`, `tasks:calendar`, `folder:Personal`, `file:Personal/Chess Project.md`, `search`,
    /// `page:insights`.
    public var token: String {
        switch self {
        case let .tasks(view): return "tasks:" + view.rawValue
        case let .folder(path): return "folder:" + path
        case let .file(path): return "file:" + path
        case .search: return "search"
        case let .page(page): return "page:" + page.rawValue
        }
    }

    public init?(token: String) {
        let parts = token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let rest = parts.count > 1 ? parts[1] : ""
        switch parts[0] {
        case "tasks":
            guard let view = TaskViewKind(rawValue: rest.isEmpty ? "today" : rest) else { return nil }
            self = .tasks(view)
        case "folder", "notes": self = .folder(rest)
        case "file":
            guard !rest.isEmpty else { return nil }
            self = .file(rest)
        case "search": self = .search
        case "page":
            guard let page = WorkspacePage(rawValue: rest) else { return nil }
            self = .page(page)
        default:
            guard parts.count == 1 else { return nil }
            if let view = TaskViewKind(rawValue: parts[0]) {
                self = .tasks(view)
            } else if let page = WorkspacePage(rawValue: parts[0]) {
                self = .page(page)
            } else {
                return nil
            }
        }
    }

    /// The same place after a file or folder was renamed or moved.
    func renamed(from old: String, to new: String) -> WorkspaceItem {
        func moved(_ path: String) -> String? {
            if path == old { return new }
            if path.hasPrefix(old + "/") { return new + path.dropFirst(old.count) }
            return nil
        }
        switch self {
        case let .file(path): return moved(path).map { .file($0) } ?? self
        case let .folder(path) where !path.isEmpty: return moved(path).map { .folder($0) } ?? self
        default: return self
        }
    }
}

extension WorkspaceItem: Codable {
    public init(from decoder: Decoder) throws {
        let token = try decoder.singleValueContainer().decode(String.self)
        guard let item = WorkspaceItem(token: token) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown place: \(token)"))
        }
        self = item
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(token)
    }
}

/// One tab: a place, and the places it showed before, so Back works inside it.
public struct WorkspaceTab: Identifiable, Hashable, Codable, Sendable {
    public static let historyLimit = 30

    public let id: String
    public internal(set) var item: WorkspaceItem
    public internal(set) var back: [WorkspaceItem] = []
    public internal(set) var forward: [WorkspaceItem] = []
    /// The file this tab shows has gone: renamed or deleted on another device, or deleted here while
    /// another tab was in front. The tab stays, saying so, until it is closed or the file comes back.
    public internal(set) var isMissing = false

    init(id: String, item: WorkspaceItem) {
        self.id = id
        self.item = item
    }

    public var title: String { item.title }
    public var symbol: String { isMissing ? "questionmark.folder" : item.symbol }
    public var canGoBack: Bool { !back.isEmpty }
    public var canGoForward: Bool { !forward.isEmpty }

    /// Shows somewhere else in this tab. Going to where it already is changes nothing.
    mutating func show(_ new: WorkspaceItem) {
        guard new != item else {
            isMissing = false
            return
        }
        back.append(item)
        if back.count > Self.historyLimit { back.removeFirst(back.count - Self.historyLimit) }
        forward = []
        item = new
        isMissing = false
    }

    mutating func goBack() -> Bool {
        guard let previous = back.popLast() else { return false }
        forward.append(item)
        item = previous
        isMissing = false
        return true
    }

    mutating func goForward() -> Bool {
        guard let next = forward.popLast() else { return false }
        back.append(item)
        item = next
        isMissing = false
        return true
    }
}

/// A pane: its tabs in order, and the one in front. Never empty.
public struct WorkspacePane: Hashable, Codable, Sendable {
    public internal(set) var tabs: [WorkspaceTab]
    public internal(set) var selectedID: String

    public var selectedIndex: Int { tabs.firstIndex { $0.id == selectedID } ?? 0 }
    public var selected: WorkspaceTab { tabs[selectedIndex] }
}

/// How two panes sit: beside each other, or one above the other.
public enum SplitAxis: String, Codable, Sendable {
    case horizontal, vertical
}

/// Where something opens.
public enum WorkspaceTarget: Sendable {
    /// In the tab in front, which remembers where it was.
    case current
    /// In a new tab of the focused pane, or the tab there that already shows it.
    case newTab
    /// In the other pane, splitting the workspace if it has one pane.
    case otherPane
}

/// The tabs and panes of one window. One pane or two; exactly one has the focus; a pane always has a
/// tab in front; and there is always at least one tab.
public struct Workspace: Hashable, Codable, Sendable {
    /// The most tabs a workspace holds, across both panes.
    public static let maxTabs = 24
    /// How many closed tabs can be brought back.
    public static let closedLimit = 12
    public static let fractionRange = 0.25...0.75

    /// A tab that was closed, and where it sat.
    public struct Closed: Hashable, Codable, Sendable {
        public var item: WorkspaceItem
        public var pane: Int
        public var index: Int
    }

    public internal(set) var panes: [WorkspacePane]
    /// The pane with the focus: 0, or 1 when there are two.
    public internal(set) var focus = 0
    public internal(set) var axis = SplitAxis.horizontal
    /// The first pane's share of the room.
    public internal(set) var fraction = 0.5
    public internal(set) var closed: [Closed] = []
    var nextID = 1

    public init(_ item: WorkspaceItem = .tasks(.today)) {
        panes = [WorkspacePane(tabs: [WorkspaceTab(id: "t0", item: item)], selectedID: "t0")]
    }

    // MARK: Reading

    public var isSplit: Bool { panes.count > 1 }
    public var tabCount: Int { panes.reduce(0) { $0 + $1.tabs.count } }
    public var isFull: Bool { tabCount >= Self.maxTabs }
    public var focusedPane: WorkspacePane { panes[focus] }
    public var focusedTab: WorkspaceTab { panes[focus].selected }
    public var focusedItem: WorkspaceItem { focusedTab.item }
    public var canReopen: Bool { !closed.isEmpty }

    public func tab(_ id: String) -> WorkspaceTab? {
        location(of: id).map { panes[$0.pane].tabs[$0.index] }
    }

    public func pane(of id: String) -> Int? { location(of: id)?.pane }

    /// Every file open in a tab.
    public var openFiles: Set<String> {
        Set(panes.flatMap { $0.tabs.compactMap(\.item.filePath) })
    }

    private func location(of id: String) -> (pane: Int, index: Int)? {
        for (paneIndex, pane) in panes.enumerated() {
            if let index = pane.tabs.firstIndex(where: { $0.id == id }) { return (paneIndex, index) }
        }
        return nil
    }

    private mutating func makeTab(_ item: WorkspaceItem) -> WorkspaceTab {
        defer { nextID += 1 }
        return WorkspaceTab(id: "t\(nextID)", item: item)
    }

    // MARK: Opening

    /// Opens a place. False when it needed a new tab and the workspace is full.
    @discardableResult
    public mutating func open(_ item: WorkspaceItem, in target: WorkspaceTarget = .current) -> Bool {
        switch target {
        case .current:
            panes[focus].tabs[panes[focus].selectedIndex].show(item)
            return true
        case .newTab:
            if let existing = panes[focus].tabs.first(where: { $0.item == item && !$0.isMissing }) {
                panes[focus].selectedID = existing.id
                return true
            }
            return newTab(item, after: panes[focus].selectedIndex)
        case .otherPane:
            guard isSplit else { return split(axis, showing: item) }
            let other = 1 - focus
            if let existing = panes[other].tabs.first(where: { $0.item == item && !$0.isMissing }) {
                panes[other].selectedID = existing.id
            } else {
                guard !isFull else { return false }
                let tab = makeTab(item)
                panes[other].tabs.append(tab)
                panes[other].selectedID = tab.id
            }
            focus = other
            return true
        }
    }

    /// Adds a tab to the focused pane and brings it to the front: at the end, or after `index`.
    @discardableResult
    public mutating func newTab(_ item: WorkspaceItem, after index: Int? = nil) -> Bool {
        guard !isFull else { return false }
        let tab = makeTab(item)
        let position = index.map { min($0 + 1, panes[focus].tabs.count) } ?? panes[focus].tabs.count
        panes[focus].tabs.insert(tab, at: position)
        panes[focus].selectedID = tab.id
        return true
    }

    /// A second tab showing the same place, beside the first.
    @discardableResult
    public mutating func duplicate(_ id: String) -> Bool {
        guard let place = location(of: id), !isFull else { return false }
        let tab = makeTab(panes[place.pane].tabs[place.index].item)
        panes[place.pane].tabs.insert(tab, at: place.index + 1)
        panes[place.pane].selectedID = tab.id
        focus = place.pane
        return true
    }

    @discardableResult
    public mutating func goBack() -> Bool { panes[focus].tabs[panes[focus].selectedIndex].goBack() }

    @discardableResult
    public mutating func goForward() -> Bool { panes[focus].tabs[panes[focus].selectedIndex].goForward() }

    /// Coming back from a layout with no tabs (a folding phone was closed, used, and opened again):
    /// the focused tab follows to wherever that layout was left. Every other tab is as it was.
    public mutating func adopt(_ item: WorkspaceItem) {
        if focusedItem != item || focusedTab.isMissing { open(item) }
    }

    // MARK: Selecting

    /// Brings a tab to the front and gives its pane the focus.
    public mutating func select(_ id: String) {
        guard let place = location(of: id) else { return }
        panes[place.pane].selectedID = id
        focus = place.pane
    }

    /// The next tab in the focused pane (or the previous one), going round at the ends.
    public mutating func selectAdjacent(_ offset: Int) {
        let count = panes[focus].tabs.count
        guard count > 1 else { return }
        let index = ((panes[focus].selectedIndex + offset) % count + count) % count
        panes[focus].selectedID = panes[focus].tabs[index].id
    }

    public mutating func focus(pane: Int) {
        focus = min(max(pane, 0), panes.count - 1)
    }

    // MARK: Closing

    /// Closes a tab and brings its neighbor to the front. Closing a pane's last tab closes the split;
    /// closing the last tab of all leaves `home` in its place, so there is always something showing.
    public mutating func close(_ id: String, home: WorkspaceItem = .tasks(.today)) {
        guard let place = location(of: id) else { return }
        let tab = panes[place.pane].tabs[place.index]
        if panes[place.pane].tabs.count > 1 {
            remember(tab, at: place)
            panes[place.pane].tabs.remove(at: place.index)
            if panes[place.pane].selectedID == id {
                let neighbor = min(place.index, panes[place.pane].tabs.count - 1)
                panes[place.pane].selectedID = panes[place.pane].tabs[neighbor].id
            }
        } else if isSplit {
            remember(tab, at: place)
            panes.remove(at: place.pane)
            focus = 0
        } else {
            if tab.item != home || tab.isMissing { remember(tab, at: place) }
            let fresh = makeTab(home)
            panes[0] = WorkspacePane(tabs: [fresh], selectedID: fresh.id)
        }
    }

    /// Closes every other tab in the same pane.
    public mutating func closeOthers(keeping id: String) {
        guard let place = location(of: id) else { return }
        for (index, tab) in panes[place.pane].tabs.enumerated() where tab.id != id {
            remember(tab, at: (place.pane, index))
        }
        panes[place.pane].tabs = [panes[place.pane].tabs[place.index]]
        panes[place.pane].selectedID = id
        focus = place.pane
    }

    private mutating func remember(_ tab: WorkspaceTab, at place: (pane: Int, index: Int)) {
        guard !tab.isMissing else { return }
        closed.append(Closed(item: tab.item, pane: place.pane, index: place.index))
        if closed.count > Self.closedLimit { closed.removeFirst(closed.count - Self.closedLimit) }
    }

    /// Brings back the tab closed last, where it was if that pane is still there.
    @discardableResult
    public mutating func reopenClosed() -> Bool {
        guard !isFull, let last = closed.popLast() else { return false }
        let pane = min(max(last.pane, 0), panes.count - 1)
        let tab = makeTab(last.item)
        panes[pane].tabs.insert(tab, at: min(max(last.index, 0), panes[pane].tabs.count))
        panes[pane].selectedID = tab.id
        focus = pane
        return true
    }

    // MARK: Splitting

    /// Splits into two panes, the new one showing `item` (or the same place again) and taking the
    /// focus. Already split, it only changes which way the panes sit.
    @discardableResult
    public mutating func split(_ axis: SplitAxis, showing item: WorkspaceItem? = nil) -> Bool {
        guard !isSplit else {
            self.axis = axis
            return true
        }
        guard !isFull else { return false }
        let tab = makeTab(item ?? focusedItem)
        panes.append(WorkspacePane(tabs: [tab], selectedID: tab.id))
        focus = 1
        self.axis = axis
        return true
    }

    /// Back to one pane holding every tab, with the tab that had the focus in front.
    public mutating func closeSplit() {
        guard isSplit else { return }
        let front = focusedTab.id
        panes = [WorkspacePane(tabs: panes[0].tabs + panes[1].tabs, selectedID: front)]
        focus = 0
    }

    /// The two panes change places, and the focus stays with the pane that had it.
    public mutating func swapPanes() {
        guard isSplit else { return }
        panes.swapAt(0, 1)
        focus = 1 - focus
        fraction = min(max(1 - fraction, Self.fractionRange.lowerBound), Self.fractionRange.upperBound)
    }

    public mutating func setFraction(_ value: Double) {
        fraction = value.isFinite ? min(max(value, Self.fractionRange.lowerBound), Self.fractionRange.upperBound) : 0.5
    }

    /// Moves a tab: to another place in its pane, or to the other pane. Moving to pane 1 of an unsplit
    /// workspace makes the split; moving a pane's last tab away closes it.
    /// - Parameter index: the position among the target pane's tabs as they are now. Nil is the end.
    public mutating func move(_ id: String, toPane target: Int, at index: Int? = nil, axis newAxis: SplitAxis? = nil) {
        guard let from = location(of: id), target == 0 || target == 1 else { return }
        let tab = panes[from.pane].tabs[from.index]
        if target >= panes.count {
            // Out to a pane that doesn't exist yet. A lone tab has nowhere to leave from.
            guard panes[0].tabs.count > 1 else { return }
            removeForMove(from)
            panes.append(WorkspacePane(tabs: [tab], selectedID: tab.id))
            focus = 1
            if let newAxis { axis = newAxis }
            return
        }
        if from.pane == target {
            var position = min(max(index ?? panes[target].tabs.count, 0), panes[target].tabs.count)
            if from.index < position { position -= 1 }
            panes[target].tabs.remove(at: from.index)
            panes[target].tabs.insert(tab, at: min(position, panes[target].tabs.count))
            panes[target].selectedID = id
            focus = target
            return
        }
        let position = min(max(index ?? panes[target].tabs.count, 0), panes[target].tabs.count)
        panes[target].tabs.insert(tab, at: position)
        panes[target].selectedID = id
        focus = target
        if panes[from.pane].tabs.count == 1 {
            panes.remove(at: from.pane)
            focus = 0
        } else {
            removeForMove(from)
        }
    }

    private mutating func removeForMove(_ place: (pane: Int, index: Int)) {
        let id = panes[place.pane].tabs[place.index].id
        panes[place.pane].tabs.remove(at: place.index)
        if panes[place.pane].selectedID == id {
            let neighbor = min(place.index, panes[place.pane].tabs.count - 1)
            panes[place.pane].selectedID = panes[place.pane].tabs[neighbor].id
        }
    }

    // MARK: Files that change under a tab

    /// A file or folder was renamed or moved: every tab showing it, or something inside it, follows.
    public mutating func renamed(from old: String, to new: String) {
        guard !old.isEmpty, old != new else { return }
        for pane in panes.indices {
            for index in panes[pane].tabs.indices {
                panes[pane].tabs[index].item = panes[pane].tabs[index].item.renamed(from: old, to: new)
                panes[pane].tabs[index].back = panes[pane].tabs[index].back.map { $0.renamed(from: old, to: new) }
                panes[pane].tabs[index].forward = panes[pane].tabs[index].forward.map { $0.renamed(from: old, to: new) }
            }
        }
        closed = closed.map { Closed(item: $0.item.renamed(from: old, to: new), pane: $0.pane, index: $0.index) }
    }

    /// Checks every tab against the notebook as it is now. A tab whose file has gone is marked missing
    /// (and unmarked if the file returns); a folder that has gone becomes the nearest one above that
    /// exists; gone files leave each tab's history and the closed tabs.
    /// - Parameters:
    ///   - fileExists: whether a file is in the notebook.
    ///   - folder: the folder to show for a path: itself, or the nearest folder above that exists.
    public mutating func validate(fileExists: (String) -> Bool, folder: (String) -> String) {
        func keeps(_ item: WorkspaceItem) -> Bool { item.filePath.map(fileExists) ?? true }
        func settled(_ item: WorkspaceItem) -> WorkspaceItem {
            if case let .folder(path) = item, !path.isEmpty { return .folder(folder(path)) }
            return item
        }
        for pane in panes.indices {
            for index in panes[pane].tabs.indices {
                var tab = panes[pane].tabs[index]
                tab.item = settled(tab.item)
                tab.isMissing = !keeps(tab.item)
                tab.back = tab.back.filter(keeps).map(settled)
                tab.forward = tab.forward.filter(keeps).map(settled)
                panes[pane].tabs[index] = tab
            }
        }
        closed = closed.filter { keeps($0.item) }
    }

    /// Closes every tab marked missing, for a workspace read back from preferences: what was open
    /// last time and has since gone is not offered again.
    public mutating func dropMissing(home: WorkspaceItem = .tasks(.today)) {
        let missing = panes.flatMap { $0.tabs.filter(\.isMissing).map(\.id) }
        for id in missing { close(id, home: home) }
    }

    // MARK: Saving

    /// This workspace with its own bookkeeping put right, whatever state it was read in: one or two
    /// panes, none empty, ids all different, a tab in front in each, no more tabs than the limit.
    public func sanitized() -> Workspace {
        var result = self
        var panes = result.panes.filter { !$0.tabs.isEmpty }
        if panes.count > 2 {
            let extra = panes[2...].flatMap(\.tabs)
            panes = Array(panes.prefix(2))
            panes[1].tabs += extra
        }
        if panes.isEmpty { return Workspace() }
        // The limit: tabs are dropped from the end of the last pane first, and a pane keeps at least one.
        var over = panes.reduce(0) { $0 + $1.tabs.count } - Self.maxTabs
        for index in panes.indices.reversed() where over > 0 {
            let drop = min(over, panes[index].tabs.count - 1)
            panes[index].tabs.removeLast(drop)
            over -= drop
        }
        // Two tabs with one id: the first keeps it, the other is given a new one.
        let original = Set(panes.flatMap { $0.tabs.map(\.id) })
        var seen = Set<String>()
        var next = 0
        for pane in panes.indices {
            for index in panes[pane].tabs.indices {
                var tab = panes[pane].tabs[index]
                if seen.contains(tab.id) || tab.id.isEmpty {
                    var id: String
                    repeat {
                        id = "r\(next)"
                        next += 1
                    } while original.contains(id) || seen.contains(id)
                    var fresh = WorkspaceTab(id: id, item: tab.item)
                    fresh.back = tab.back
                    fresh.forward = tab.forward
                    fresh.isMissing = tab.isMissing
                    tab = fresh
                }
                tab.back = Array(tab.back.suffix(WorkspaceTab.historyLimit))
                tab.forward = Array(tab.forward.suffix(WorkspaceTab.historyLimit))
                seen.insert(tab.id)
                panes[pane].tabs[index] = tab
            }
            if !panes[pane].tabs.contains(where: { $0.id == panes[pane].selectedID }) {
                panes[pane].selectedID = panes[pane].tabs[0].id
            }
        }
        result.panes = panes
        result.focus = min(max(result.focus, 0), panes.count - 1)
        result.setFraction(result.fraction)
        result.closed = Array(result.closed.suffix(Self.closedLimit))
        // New ids must never repeat one already in use.
        let highest = seen.compactMap { $0.hasPrefix("t") ? Int($0.dropFirst()) : nil }.max() ?? 0
        result.nextID = max(result.nextID, highest + 1, 1)
        return result
    }

    /// The layout alone, for a saved workspace: the tabs and panes, without history or closed tabs.
    public var layoutOnly: Workspace {
        var result = self
        result.closed = []
        for pane in result.panes.indices {
            for index in result.panes[pane].tabs.indices {
                result.panes[pane].tabs[index].back = []
                result.panes[pane].tabs[index].forward = []
            }
        }
        return result
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    /// Reads a saved workspace. Nil when the data isn't one; anything else is put right by `sanitized`.
    public static func decoded(_ data: Data?) -> Workspace? {
        guard let data, let workspace = try? JSONDecoder().decode(Workspace.self, from: data) else { return nil }
        return workspace.sanitized()
    }

    /// What is wrong with this workspace's bookkeeping. Empty when everything holds; the tests check
    /// it after every operation.
    public var invariantFailures: [String] {
        var failures: [String] = []
        if !(1...2).contains(panes.count) { failures.append("\(panes.count) panes") }
        if !panes.indices.contains(focus) { failures.append("focus \(focus) is not a pane") }
        for (index, pane) in panes.enumerated() {
            if pane.tabs.isEmpty { failures.append("pane \(index) is empty") }
            if !pane.tabs.contains(where: { $0.id == pane.selectedID }) { failures.append("pane \(index) has no tab in front") }
            for tab in pane.tabs where tab.back.count > WorkspaceTab.historyLimit || tab.forward.count > WorkspaceTab.historyLimit {
                failures.append("tab \(tab.id) remembers too much")
            }
        }
        let ids = panes.flatMap { $0.tabs.map(\.id) }
        if Set(ids).count != ids.count { failures.append("two tabs share an id") }
        if ids.count > Self.maxTabs { failures.append("\(ids.count) tabs") }
        if !Self.fractionRange.contains(fraction) { failures.append("fraction \(fraction)") }
        if closed.count > Self.closedLimit { failures.append("\(closed.count) closed tabs remembered") }
        return failures
    }
}

// MARK: - One place, two arrangements

/// How the iPhone's shell (its tab bar, or its sidebar) shows a workspace item. Nil leaves that part
/// of the shell as it is.
public struct WorkspaceShellPlace: Equatable, Sendable {
    public var destination: ShellDestination
    public var taskView: TaskViewKind?
    public var notesFolder: String?
    /// The file open in Notes. Nil is the folder browser alone.
    public var notesFile: String?

    public init(destination: ShellDestination, taskView: TaskViewKind? = nil, notesFolder: String? = nil, notesFile: String? = nil) {
        self.destination = destination
        self.taskView = taskView
        self.notesFolder = notesFolder
        self.notesFile = notesFile
    }
}

public extension WorkspaceItem {
    /// Where the shell goes to show this. A folded phone has no tabs: it shows the focused tab's place
    /// in its ordinary tab bar layout, and this is that place.
    var shellPlace: WorkspaceShellPlace {
        switch self {
        case let .tasks(view): return WorkspaceShellPlace(destination: .tasks, taskView: view)
        case let .folder(path): return WorkspaceShellPlace(destination: .notes, notesFolder: path)
        case let .file(path): return WorkspaceShellPlace(destination: .notes, notesFile: path)
        case .search: return WorkspaceShellPlace(destination: .search)
        case .page(.agents): return WorkspaceShellPlace(destination: .agents)
        // The Mac's own pages have no place on the phone; Tasks stands in.
        case .page: return WorkspaceShellPlace(destination: .tasks)
        }
    }

    /// The item the shell is showing, so the focused tab can follow it.
    init(destination: ShellDestination, taskView: TaskViewKind, notesFolder: String, openNote: String?) {
        switch destination {
        case .tasks: self = .tasks(taskView)
        case .notes: self = openNote.map { .file($0) } ?? .folder(notesFolder)
        case .agents: self = .page(.agents)
        case .search: self = .search
        }
    }
}

// MARK: - Saved workspaces

/// A layout saved under a name: "Planning" is Today beside the Calendar.
public struct SavedWorkspace: Identifiable, Hashable, Codable, Sendable {
    public var name: String
    public var layout: Workspace
    public var id: String { name }
}

/// The named layouts, newest last. Kept in preferences on each device.
public struct SavedWorkspaces: Hashable, Codable, Sendable {
    public static let limit = 8
    public static let nameLimit = 40

    public private(set) var items: [SavedWorkspace] = []

    public init() {}

    public var isFull: Bool { items.count >= Self.limit }

    /// A name that can be used: trimmed, on one line, not empty and not too long.
    public static func cleaned(_ name: String) -> String? {
        let clean = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return clean.isEmpty || clean.count > nameLimit ? nil : clean
    }

    private func index(of name: String) -> Int? {
        items.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Saves a layout under a name, replacing one of the same name. False when the name can't be used
    /// or there are already eight others.
    @discardableResult
    public mutating func save(_ workspace: Workspace, as name: String) -> Bool {
        guard let clean = Self.cleaned(name) else { return false }
        let saved = SavedWorkspace(name: clean, layout: workspace.layoutOnly)
        if let index = index(of: clean) {
            items[index] = saved
            return true
        }
        guard !isFull else { return false }
        items.append(saved)
        return true
    }

    @discardableResult
    public mutating func rename(_ name: String, to new: String) -> Bool {
        guard let index = index(of: name), let clean = Self.cleaned(new) else { return false }
        if let taken = self.index(of: clean), taken != index { return false }
        items[index].name = clean
        return true
    }

    public mutating func delete(_ name: String) {
        if let index = index(of: name) { items.remove(at: index) }
    }

    public func layout(named name: String) -> Workspace? {
        index(of: name).map { items[$0].layout.sanitized() }
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    public static func decoded(_ data: Data?) -> SavedWorkspaces {
        guard let data, var saved = try? JSONDecoder().decode(SavedWorkspaces.self, from: data) else { return SavedWorkspaces() }
        saved.items = Array(saved.items.prefix(limit))
        return saved
    }
}
