import PerchKit
import SwiftUI

private struct SelectedPathKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// The file showing in a pane beside the list being drawn, so the list can mark its row.
    var perchSelectedPath: String? {
        get { self[SelectedPathKey.self] }
        set { self[SelectedPathKey.self] = newValue }
    }
}

/// Where the iPhone app is, apart from what `AppModel` already remembers: which destination is in
/// front and which files are open in Notes, Search and Agents.
///
/// The tab bar layout and the wide layout both read and change this one object, so switching between
/// them (opening or closing a folding phone, turning it) keeps the place: a note pushed onto the Notes
/// stack is the note in the pane, and the other way round.
@MainActor
public final class ShellState: ObservableObject {
    @Published public var destination: ShellDestination
    /// The files opened in Notes, the one showing last.
    @Published public var notesPath: [Route] = []
    /// What was opened from Search and from Agents: files, and folders reached from them.
    @Published public var searchPath: [Route] = []
    @Published public var agentsPath: [Route] = []
    /// The sidebar is open over the content, on a screen too narrow to keep it open beside it.
    @Published public var drawerOpen = false
    /// Goes up each time Search is asked for by name (the sidebar, the rail, ⌘F), so its field takes
    /// the keyboard. `takeSearchFocus` says whether that has still to happen.
    @Published public private(set) var searchRequests = 0
    private var searchFocusPending = false
    /// The arrangement last drawn. Not published: views are handed the layout; this is for decisions
    /// made outside a view's body, such as whether closing a sheet should forget the task it showed.
    public var layout: ShellLayout?
    /// Tabs: set while the workspace draws the content. True when the focused pane has room to show
    /// the selected task beside its list; false sends it to a sheet. Nil without tabs.
    public var workspaceTaskPane: Bool?

    public init(destination: ShellDestination = .tasks) {
        self.destination = destination
    }

    /// Brings a destination to the front. Tasks and Notes also become the model's section, which it
    /// remembers for the next launch.
    public func show(_ destination: ShellDestination, model: AppModel) {
        if self.destination != destination { self.destination = destination }
        if let section = destination.section { model.selectSection(section) }
    }

    public func showSearch(model: AppModel) {
        show(.search, model: model)
        searchFocusPending = true
        searchRequests += 1
    }

    /// True once for each time Search was asked for by name.
    public func takeSearchFocus() -> Bool {
        defer { searchFocusPending = false }
        return searchFocusPending
    }

    /// How the place is shown in the arrangement last drawn.
    public func presentation(model: AppModel) -> ShellPresentation? {
        guard var presentation = layout.map({ ShellPresentation(place: place(model: model), layout: $0) }) else { return nil }
        if let inPane = workspaceTaskPane, presentation.taskDetail != .none { presentation.taskDetail = inPane ? .pane : .sheet }
        return presentation
    }

    /// The place, in the terms `ShellPresentation` understands.
    public func place(model: AppModel) -> ShellPlace {
        ShellPlace(
            destination: destination, taskView: model.taskView, selectedTask: model.task(id: model.selectedTaskID)?.id,
            notesFiles: Self.files(notesPath), searchFiles: Self.files(searchPath)
        )
    }

    private static func files(_ path: [Route]) -> [String] {
        path.compactMap { route in
            switch route {
            case let .file(file): return file
            case let .folder(folder): return folder
            default: return nil
            }
        }
    }

    /// The file showing in Notes, if one is open.
    public var openNote: String? {
        if case let .file(path)? = notesPath.last { return path }
        return nil
    }

    /// Opens a file in Notes. Picked from the browser or the sidebar it replaces what was open; reached
    /// by a link inside a note it goes on top, so closing it returns to the note the link was in.
    public func openNote(_ path: String, fromLink: Bool, model: AppModel) {
        var place = ShellPlace(notesFiles: Self.files(notesPath))
        place.openNote(path, fromLink: fromLink)
        let routes = place.notesFiles.map { Route.file($0) }
        if routes != notesPath { notesPath = routes }
        show(.notes, model: model)
    }

    /// Shows a folder in the notes browser. With one pane the browser has to come forward, so whatever
    /// note was open is closed; with two the note stays beside it.
    public func showFolder(_ path: String, model: AppModel, split: Bool) {
        model.setNotesFolder(path)
        if !split, !notesPath.isEmpty { notesPath.removeAll() }
        show(.notes, model: model)
    }

    /// Takes a request made through `model.route` and turns it into a place. On iPhone a route is a
    /// request, taken once and cleared, or asking for the same place again would do nothing. The model
    /// has already noted the section, view, scope or folder the route names.
    ///
    /// - A task view or an area shows Tasks.
    /// - A folder or file asked for from Tasks or Notes (a link in a task, "New note", "Notes in
    ///   Personal") shows in Notes: a folder becomes the folder being browsed, a file is opened on top.
    /// - From Search and Agents, files and folders open in place, so Back returns to the list.
    /// - A task's own file opens the task.
    public func take(_ route: Route, model: AppModel, split: Bool) {
        defer { model.route = nil }
        switch route {
        case .today, .upcoming, .ready, .list, .calendar, .board, .week, .area:
            show(.tasks, model: model)
        case .search:
            show(.search, model: model)
        case let .folder(path):
            switch destination {
            case .tasks, .notes: showFolder(path, model: model, split: split)
            case .search: open(route, in: \.searchPath, replacing: false)
            case .agents: open(route, in: \.agentsPath, replacing: false)
            }
        case let .file(path):
            if let task = model.tasks.first(where: { $0.path == path }) {
                model.selectedTaskID = task.id
                return
            }
            switch destination {
            case .tasks, .notes:
                openNote(path, fromLink: true, model: model)
            case .search:
                // Beside the results, a new pick replaces the last one; pushed over them, it goes on top.
                open(route, in: \.searchPath, replacing: split)
                if split { model.selectedTaskID = nil }
            case .agents:
                open(route, in: \.agentsPath, replacing: false)
            }
        case .insights, .activity, .importer, .settings:
            break
        }
    }

    private func open(_ route: Route, in keyPath: ReferenceWritableKeyPath<ShellState, [Route]>, replacing: Bool) {
        if replacing {
            if self[keyPath: keyPath] != [route] { self[keyPath: keyPath] = [route] }
        } else if self[keyPath: keyPath].last != route {
            self[keyPath: keyPath].append(route)
        }
    }

    /// A file was renamed here: every stack that had it open keeps it open under its new path. Without
    /// this the note would be closed by `prune` the moment its old path stopped existing.
    public func renamed(_ old: String, to new: String) {
        for keyPath in [\ShellState.notesPath, \.searchPath, \.agentsPath] where self[keyPath: keyPath].contains(.file(old)) {
            self[keyPath: keyPath] = self[keyPath: keyPath].map { $0 == .file(old) ? .file(new) : $0 }
        }
    }

    /// Closes files that are gone: deleted here, or renamed or removed on another device.
    public func prune(model: AppModel) {
        guard let vault = model.vault else { return }
        func keep(_ route: Route) -> Bool {
            if case let .file(path) = route { return vault.exists(path) }
            return true
        }
        for keyPath in [\ShellState.notesPath, \.searchPath, \.agentsPath] where !self[keyPath: keyPath].allSatisfy(keep) {
            self[keyPath: keyPath].removeAll { !keep($0) }
        }
    }
}
