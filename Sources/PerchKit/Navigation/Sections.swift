import Foundation

/// The two halves of the app. Everything else (search, settings, agents) sits beside them.
public enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case tasks, notes

    public var id: String { rawValue }
    public var title: String { self == .tasks ? "Tasks" : "Notes" }
    public var symbol: String { self == .tasks ? "checklist" : "doc.text" }
}

/// The ways of looking at tasks. Each one shows the area in scope, or every area.
public enum TaskViewKind: String, CaseIterable, Identifiable, Sendable {
    /// Board is only offered where there is room for its columns. See `offered(wide:ready:)`.
    case today, upcoming, list, calendar, board, ready

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        case .list: return "List"
        case .calendar: return "Calendar"
        case .board: return "Board"
        case .ready: return "Ready to tick"
        }
    }

    /// A shorter name for the view switcher, where room is tight.
    public var shortTitle: String { self == .ready ? "Ready" : title }

    public var symbol: String {
        switch self {
        case .today: return "sun.max"
        case .upcoming: return "calendar.badge.clock"
        case .list: return "list.bullet"
        case .calendar: return "calendar"
        case .board: return "rectangle.split.3x1"
        case .ready: return "checkmark.seal"
        }
    }

    /// The views on offer, in order. Board needs a wide screen; Ready to tick shows while something waits.
    public static func offered(wide: Bool, ready: Bool) -> [TaskViewKind] {
        allCases.filter { ($0 != .board || wide) && ($0 != .ready || ready) }
    }

    /// The view to draw. The Board has no narrow form, so a narrow screen draws Upcoming, which lists
    /// the same days one under another. The saved view stays Board, so unfolding the phone brings it back.
    public func effective(wide: Bool) -> TaskViewKind {
        self == .board && !wide ? .upcoming : self
    }
}

/// Which kinds of file the Notes section lists.
public enum NotesKind: String, CaseIterable, Identifiable, Sendable {
    case all, notes, boards, whiteboards

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "All"
        case .notes: return "Notes"
        case .boards: return "Boards"
        case .whiteboards: return "Whiteboards"
        }
    }

    public var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .notes: return "doc.text"
        case .boards: return "rectangle.split.3x1"
        case .whiteboards: return "scribble"
        }
    }

    public var kinds: Set<VaultFileKind> {
        switch self {
        case .all: return FolderListing.browsableKinds
        case .notes: return [.note, .notebook]
        case .boards: return [.board]
        case .whiteboards: return [.whiteboard]
        }
    }
}

// MARK: - Task scope

/// The area the Tasks section is looking at. Nil means every area.
public enum TaskScope {
    public struct Count: Equatable, Sendable {
        public var open = 0
        public var overdue = 0
        public init(open: Int = 0, overdue: Int = 0) {
            self.open = open
            self.overdue = overdue
        }
    }

    public static func contains(_ task: PerchTask, area: String?) -> Bool {
        area == nil || task.area == area
    }

    public static func filter(_ tasks: [PerchTask], area: String?) -> [PerchTask] {
        guard let area else { return tasks }
        return tasks.filter { $0.area == area }
    }

    /// A file belongs to an area when it lives under that area's top-level folder. Used for board cards.
    public static func contains(path: String, area: String?) -> Bool {
        guard let area else { return true }
        return path.hasPrefix(area + "/")
    }

    /// Open and overdue counts for every area, and for all of them together, in one pass.
    public static func counts(_ tasks: [PerchTask], today: String) -> (all: Count, byArea: [String: Count]) {
        var all = Count()
        var byArea: [String: Count] = [:]
        for task in tasks where task.isOpen {
            let late = task.isOverdue(today: today)
            all.open += 1
            byArea[task.area, default: Count()].open += 1
            if late {
                all.overdue += 1
                byArea[task.area, default: Count()].overdue += 1
            }
        }
        return (all, byArea)
    }

    /// The scope to use given the areas on offer: an area that has gone (hidden, or its last task moved) falls back to All.
    /// An area whose folder was renamed on another device to the same name with or without an emoji
    /// ("Work" to "✈️ Work") is followed to its new spelling.
    public static func resolved(_ area: String?, in areas: [String]) -> String? {
        area.flatMap { AreaList.match($0, in: areas) }
    }

    /// Where you are, for a header: "Today" with every area, "Personal · Upcoming" inside one.
    public static func title(view: TaskViewKind, area: String?) -> String {
        guard let area else { return view.title }
        return "\(QuickAdd.simplifiedArea(area)) · \(view.title)"
    }

    /// "Personal, 12 open, 3 overdue", for VoiceOver.
    public static func spoken(name: String, count: Count) -> String {
        var parts = [name, count.open == 0 ? "no open tasks" : "\(count.open) open"]
        if count.overdue > 0 { parts.append("\(count.overdue) overdue") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Areas

/// What the user has changed about the list of areas. Kept in preferences on each device; nothing here
/// is written to the notebook. An added area's `Tasks` folder appears with its first task.
public struct AreaPreferences: Equatable, Sendable {
    /// Areas added by name that may not have a folder or a task yet.
    public var extra: [String]
    /// The order chosen for the areas. Areas not listed follow, in the order they were found.
    public var order: [String]
    /// Areas left out of the sub-section bars. Their tasks still show under All.
    public var hidden: [String]

    public init(extra: [String] = [], order: [String] = [], hidden: [String] = []) {
        self.extra = extra
        self.order = order
        self.hidden = hidden
    }

    public enum Key {
        public static let extra = "taskAreasExtra"
        public static let order = "taskAreasOrder"
        public static let hidden = "taskAreasHidden"
        public static let all = [extra, order, hidden]
    }

    public static func load(from defaults: UserDefaults) -> AreaPreferences {
        AreaPreferences(
            extra: defaults.stringArray(forKey: Key.extra) ?? [],
            order: defaults.stringArray(forKey: Key.order) ?? [],
            hidden: defaults.stringArray(forKey: Key.hidden) ?? []
        )
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(extra, forKey: Key.extra)
        defaults.set(order, forKey: Key.order)
        defaults.set(hidden, forKey: Key.hidden)
    }
}

/// The fixed colours some areas have, so they look the same everywhere. Every other area gets a colour
/// from its name.
public enum AreaTint: Equatable, Sendable {
    /// The first standard area besides Personal (a work area, say).
    case first
    case personal

    /// An area whose name contains the first standard area's name (ignoring case and a leading emoji) is
    /// `first`; one whose name contains "personal" is `personal`.
    public static func fixed(for area: String, standard: [String]) -> AreaTint? {
        let plain = QuickAdd.simplifiedArea(area).lowercased()
        let names = standard.map { QuickAdd.simplifiedArea($0).lowercased() }
        if let first = names.first(where: { !$0.isEmpty && $0 != "personal" }), plain.contains(first) { return .first }
        if plain.contains("personal") { return .personal }
        return nil
    }
}

public enum AreaList {
    /// The areas the notebook itself implies: the standard ones that exist as top-level folders, then every
    /// area that already has a task. The standard areas, and their order, come from the build
    /// (`PerchConfiguration.standardAreas`). Only a notebook with no areas at all is given one, the first
    /// standard area, so a new task has somewhere to go; a notebook with its own areas shows exactly those.
    public static func discovered(topLevelFolders: Set<String>, taskAreas: [String], standard: [String]) -> [String] {
        var result = standard.filter { topLevelFolders.contains($0) }
        for area in taskAreas where !result.contains(area) { result.append(area) }
        if result.isEmpty { result = [standard.first ?? "Personal"] }
        return result
    }

    /// The same name, ignoring case and a leading emoji: "work" is "✈️ Work".
    public static func isSame(_ a: String, _ b: String) -> Bool {
        a == b || QuickAdd.simplifiedArea(a).caseInsensitiveCompare(QuickAdd.simplifiedArea(b)) == .orderedSame
    }

    /// The area in `areas` that a saved name means: the very same name, or failing that the one that
    /// differs only by case or a leading emoji. Preferences are saved per device, and a folder can be
    /// renamed on another one, so a saved name is followed to the folder's new spelling.
    public static func match(_ name: String, in areas: [String]) -> String? {
        areas.contains(name) ? name : areas.first { isSame($0, name) }
    }

    /// Every area: what the notebook implies plus the ones added by name, in the chosen order.
    /// Hidden areas are included, so quick add and "move to area" can still name them.
    public static func all(discovered: [String], preferences: AreaPreferences, transient: [String] = []) -> [String] {
        var result = discovered
        for name in preferences.extra + transient where !result.contains(where: { isSame($0, name) }) { result.append(name) }
        guard !preferences.order.isEmpty else { return result }
        var ranked: [String] = []
        for name in preferences.order {
            if let area = match(name, in: result), !ranked.contains(area) { ranked.append(area) }
        }
        return ranked + result.filter { !ranked.contains($0) }
    }

    /// The areas shown as sub-sections.
    public static func visible(_ all: [String], preferences: AreaPreferences) -> [String] {
        let hidden = Set(preferences.hidden.compactMap { match($0, in: all) })
        return all.filter { !hidden.contains($0) }
    }

    public static func isHidden(_ area: String, in all: [String], preferences: AreaPreferences) -> Bool {
        preferences.hidden.contains { match($0, in: all) == area }
    }

    /// Characters a folder name can't hold on every device that syncs the notebook, plus `#`, which
    /// would stop `#Name` in quick add from ever naming the area.
    private static let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|#")

    /// The longest name an area can have.
    public static let nameLimit = 60

    /// A name that can be an area: one folder name. Spaces at the ends and dots at the end go, runs of
    /// spaces become one, and the text is stored the way the file system composes it.
    /// Nil when it can't be used: empty, hidden (a leading dot), holding a character a folder can't,
    /// too long, nothing but emoji, or "Tasks", which is the name of the folder inside every area.
    public static func cleaned(_ name: String) -> String? {
        // Tabs and line breaks (from a paste) count as spaces. Any other control character is refused.
        var clean = name.precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !clean.unicodeScalars.contains(where: { forbidden.contains($0) || CharacterSet.controlCharacters.contains($0) }) else { return nil }
        while clean.hasSuffix(".") || clean.hasSuffix(" ") { clean.removeLast() }
        guard !clean.isEmpty, !clean.hasPrefix("."), clean.count <= nameLimit else { return nil }
        // Something must be left once an emoji is set aside, or `#Name` in quick add could never match it.
        let plain = QuickAdd.simplifiedArea(clean)
        guard !plain.isEmpty, plain.caseInsensitiveCompare("Tasks") != .orderedSame else { return nil }
        return clean
    }

    /// Why a typed name can't be an area, in a sentence. Nil when it can, or when nothing is typed yet.
    public static func problem(with name: String) -> String? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, cleaned(name) == nil else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(".") { return "A name can't start with a dot." }
        if trimmed.count > nameLimit { return "Keep the name under \(nameLimit) characters." }
        if QuickAdd.simplifiedArea(trimmed).caseInsensitiveCompare("Tasks") == .orderedSame { return "Every area already has a Tasks folder inside it. Pick another name." }
        if QuickAdd.simplifiedArea(trimmed).isEmpty { return "Add a word to the name, so #Name can find it." }
        return "A name can't contain / \\ : * ? \" < > | or #."
    }

    /// Adds an area by name. Returns the area it resolves to: an existing one when the name matches it
    /// (which is shown again if it was hidden), otherwise the new name. Nil when the name can't be used.
    ///
    /// A top-level folder that is the same name, ignoring case and a leading emoji, lends its spelling:
    /// typing "consulting" beside a "💼 Consulting" folder adds "💼 Consulting", so the first task is
    /// filed in the folder that is already there and not in a second one beside it.
    public static func add(_ name: String, to preferences: inout AreaPreferences, existing: [String], topLevelFolders: [String] = []) -> String? {
        guard var clean = cleaned(name) else { return nil }
        if let match = match(clean, in: existing) {
            preferences.hidden.removeAll { self.match($0, in: existing) == match }
            return match
        }
        if let folder = self.match(clean, in: topLevelFolders.sorted()) { clean = folder }
        preferences.extra.append(clean)
        if !preferences.order.isEmpty { preferences.order.append(clean) }
        return clean
    }

    /// Takes an added area off the list. Areas the notebook implies can only be hidden.
    public static func remove(_ area: String, from preferences: inout AreaPreferences) {
        preferences.extra.removeAll { $0 == area }
        preferences.order.removeAll { $0 == area }
        preferences.hidden.removeAll { $0 == area }
    }

    public static func setHidden(_ hidden: Bool, area: String, in preferences: inout AreaPreferences) {
        preferences.hidden.removeAll { isSame($0, area) }
        if hidden { preferences.hidden.append(area) }
    }

    /// Moves an area `offset` places in the list (-1 is up), stopping at the ends, and records the whole order.
    public static func move(_ area: String, by offset: Int, in all: [String], preferences: inout AreaPreferences) {
        guard let index = all.firstIndex(of: area) else { return }
        let target = min(max(index + offset, 0), all.count - 1)
        guard target != index else { return }
        var order = all
        order.remove(at: index)
        order.insert(area, at: target)
        preferences.order = order
    }

    /// Names worth offering when adding an area: top-level folders that aren't areas yet, after any
    /// `extras` the caller wants first. Nothing already on the list is offered.
    public static func suggestions(topLevelFolders: [String], existing: [String], extras: [String] = [], limit: Int = 6) -> [String] {
        var result: [String] = []
        for name in extras + topLevelFolders {
            guard cleaned(name) != nil, !existing.contains(where: { isSame($0, name) }), !result.contains(where: { isSame($0, name) }) else { continue }
            result.append(name)
        }
        return Array(result.prefix(limit))
    }
}

// MARK: - Notes sub-sections

/// The folder chips above the notes browser: the top-level folders, and one row of the folders around
/// where you are, so you can hop sideways and drill down without leaving the screen.
public struct NotesSubsections: Equatable, Sendable {
    public struct Chip: Identifiable, Hashable, Sendable {
        public var path: String
        public var name: String
        /// Matching files inside, at any depth.
        public var count: Int
        public var id: String { path }

        public init(path: String, name: String, count: Int) {
            self.path = path
            self.name = name
            self.count = count
        }
    }

    /// Every matching file in the notebook, for the All chip.
    public var total: Int
    /// The top-level folders.
    public var top: [Chip]
    /// The top-level folder the current one sits in. Nil at the top level.
    public var selectedTop: String?
    /// The second row. At a top-level folder these are its sub-folders; deeper down they are the
    /// current folder and its siblings, so the one you are in is among them.
    public var row: [Chip]
    /// The folder whose sub-folders `row` lists. Empty when there is no second row.
    public var rowParent: String
    /// The chip in `row` that is the current folder, when it is one of them.
    public var selectedInRow: String?
    /// Where the "up" chip leads: set when `rowParent` is itself below the top level.
    public var up: Chip?

    public init(files: [VaultFile], path: String, kinds: Set<VaultFileKind> = FolderListing.browsableKinds) {
        let parts = path.split(separator: "/").map(String.init)
        let current = parts.joined(separator: "/")
        let root = FolderListing(files: files, path: "", kinds: kinds)
        total = root.itemCount
        top = root.folders.map { Chip(path: $0.path, name: $0.name, count: $0.itemCount) }
        selectedTop = parts.first
        if parts.isEmpty {
            row = []
            rowParent = ""
            selectedInRow = nil
            up = nil
            return
        }
        let parent = parts.count == 1 ? current : parts.dropLast().joined(separator: "/")
        let listing = FolderListing(files: files, path: parent, kinds: kinds)
        row = listing.folders.map { Chip(path: $0.path, name: $0.name, count: $0.itemCount) }
        rowParent = row.isEmpty ? "" : parent
        selectedInRow = parts.count > 1 && row.contains(where: { $0.path == current }) ? current : nil
        if parts.count > 2, !row.isEmpty {
            up = Chip(path: parent, name: parts[parts.count - 2], count: listing.itemCount)
        } else {
            up = nil
        }
    }

    /// The folder to show for a saved path: itself while anything lives in it, otherwise the nearest
    /// folder above that still exists, ending at the top level.
    public static func existing(_ path: String, files: [VaultFile]) -> String {
        var parts = path.split(separator: "/").map(String.init)
        while !parts.isEmpty {
            let prefix = parts.joined(separator: "/") + "/"
            if files.contains(where: { $0.path.hasPrefix(prefix) }) { return parts.joined(separator: "/") }
            parts.removeLast()
        }
        return ""
    }
}

// MARK: - Remembering where you were

/// Where each section was left, so switching back returns to the same place. Saved on each device.
public struct NavigationState: Equatable, Sendable {
    /// Somewhere a section can be. Anything else (search, settings) belongs to neither and changes nothing.
    public enum Place: Equatable, Sendable {
        case tasks(TaskViewKind)
        case area(String)
        case folder(String)
        case file(String)
    }

    public var section = AppSection.tasks
    public var taskView = TaskViewKind.today
    /// Nil is every area.
    public var taskScope: String?
    /// The folder the notes browser was showing. Empty is the top level.
    public var notesFolder = ""
    /// The file the Notes section was showing, when it was a file.
    public var notesFile: String?
    public var notesKind = NotesKind.all

    public init() {}

    /// Notes what is now showing. Going to an area means its tasks: the scope, in the List view.
    public mutating func visit(_ place: Place) {
        switch place {
        case let .tasks(view):
            section = .tasks
            taskView = view
        case let .area(name):
            section = .tasks
            taskScope = name.isEmpty ? nil : name
            taskView = .list
        case let .folder(path):
            section = .notes
            notesFolder = path
            notesFile = nil
        case let .file(path):
            section = .notes
            notesFile = path
        }
    }

    /// The place to return to in a section.
    public func place(in section: AppSection) -> Place {
        switch section {
        case .tasks: return .tasks(taskView)
        case .notes: return notesFile.map { .file($0) } ?? .folder(notesFolder)
        }
    }

    public enum Key {
        public static let section = "navSection"
        public static let taskView = "navTaskView"
        public static let taskScope = "navTaskScope"
        public static let notesFolder = "navNotesFolder"
        public static let notesFile = "navNotesFile"
        public static let notesKind = "navNotesKind"
        public static let all = [section, taskView, taskScope, notesFolder, notesFile, notesKind]
    }

    public static func load(from defaults: UserDefaults) -> NavigationState {
        var state = NavigationState()
        if let value = defaults.string(forKey: Key.section).flatMap(AppSection.init(rawValue:)) { state.section = value }
        if let value = defaults.string(forKey: Key.taskView).flatMap(TaskViewKind.init(rawValue:)) { state.taskView = value }
        if let value = defaults.string(forKey: Key.taskScope), !value.isEmpty { state.taskScope = value }
        state.notesFolder = defaults.string(forKey: Key.notesFolder) ?? ""
        if let value = defaults.string(forKey: Key.notesFile), !value.isEmpty { state.notesFile = value }
        if let value = defaults.string(forKey: Key.notesKind).flatMap(NotesKind.init(rawValue:)) { state.notesKind = value }
        return state
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(section.rawValue, forKey: Key.section)
        defaults.set(taskView.rawValue, forKey: Key.taskView)
        defaults.set(taskScope ?? "", forKey: Key.taskScope)
        defaults.set(notesFolder, forKey: Key.notesFolder)
        defaults.set(notesFile ?? "", forKey: Key.notesFile)
        defaults.set(notesKind.rawValue, forKey: Key.notesKind)
    }
}

public extension AdaptiveLayout {
    /// The narrowest width where a section's sub-sections sit in a column beside the content
    /// instead of a bar above it. Below this the content needs the whole width.
    static let railWidth: Double = 800

    static func subsectionRail(width: Double) -> Bool { width >= railWidth }

    /// The narrowest content that is offered the Board view: two columns and the edge of a third,
    /// which is what says the board scrolls sideways. An open folding phone, upright, has 514 points
    /// beside the rail when the system keeps a column of the screen.
    static let boardWidth: Double = 500

    static func offersBoard(width: Double) -> Bool { width >= boardWidth }
}
