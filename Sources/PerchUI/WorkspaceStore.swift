import Combine
import PerchKit
import SwiftUI

// EXPERIMENTAL: tabs and split view. See Workspace.swift in PerchKit for the model and for how to
// remove the feature.
//
// The app has one place it is "at": `AppModel.route` on the Mac, `ShellState` and the model on the
// iPhone. Every screen, the sidebar and every shortcut read and change that place, and none of them
// knows about tabs. So the workspace doesn't replace it. It mirrors it:
//
// - the focused pane's front tab IS the app's place. Go somewhere by any of the usual means and that
//   tab goes there; bring another tab or pane to the front and the app's place becomes that tab's;
// - every other tab is only remembered, and a pane without the focus is drawn from its tab's own
//   place, not the app's.
//
// A pane takes the focus on mouse-down (or touch-down), before whatever was clicked acts, so an
// action always lands in the pane it was made in.

@MainActor
public final class WorkspaceStore: ObservableObject {
    /// The setting: "Tabs and split view (experimental)". Off by default.
    public static let settingKey = "experimentalTabs"
    static let layoutKey = "workspaceLayout"
    static let savedKey = "workspaceSaved"

    public static var isEnabled: Bool { UserDefaults.standard.bool(forKey: settingKey) }

    /// What a name is being asked for.
    public enum Prompt: Identifiable, Equatable {
        case saveAs
        case rename(String)
        public var id: String {
            switch self {
            case .saveAs: return "save"
            case let .rename(name): return "rename:" + name
            }
        }
    }

    @Published public private(set) var workspace: Workspace
    @Published public private(set) var saved: SavedWorkspaces
    /// True while a workspace is on screen: the setting is on and, on the iPhone, the layout is wide.
    @Published public private(set) var isActive = false
    /// The tab being dragged, from the moment its drag begins.
    @Published var draggingTab: String?
    @Published var prompt: Prompt?

    public let model: AppModel
    private let defaults: UserDefaults?
    /// The iPhone's shell, when this workspace mirrors it instead of `model.route`.
    private weak var shell: ShellState?
    private var cancellables: Set<AnyCancellable> = []
    private var isApplying = false
    /// The saved workspace is checked against the notebook once, after its first load.
    private var needsRestoreCheck = true

    /// - Parameter defaults: where the workspace and the saved layouts are kept. Nil (snapshot and
    ///   debug runs, tests) starts fresh and saves nothing.
    public init(model: AppModel, defaults: UserDefaults?) {
        self.model = model
        self.defaults = defaults
        workspace = Workspace.decoded(defaults?.data(forKey: Self.layoutKey)) ?? Workspace(.home(for: model.section))
        saved = SavedWorkspaces.decoded(defaults?.data(forKey: Self.savedKey))
        // The Mac: the route is the place. The value arrives before the model has finished with it,
        // which is fine: only the value is read.
        model.$route.sink { [weak self] route in self?.routeChanged(route) }.store(in: &cancellables)
        // A notebook that is already open is the one to check the saved tabs against.
        filesChanged(model.files)
        model.$files.dropFirst().sink { [weak self] files in self?.filesChanged(files) }.store(in: &cancellables)
        model.$lastRename.sink { [weak self] rename in
            guard let rename else { return }
            self?.change(applies: false) { $0.renamed(from: rename.from, to: rename.to) }
        }.store(in: &cancellables)
    }

    /// Mirrors the iPhone's shell instead of `model.route`, which on the iPhone is only a request.
    public func attach(shell: ShellState) {
        self.shell = shell
        // Read a turn later, once whatever changed has finished changing.
        Publishers.Merge3(
            shell.$destination.map { _ in () }, shell.$notesPath.map { _ in () }, model.$nav.map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in self?.shellChanged() }
        .store(in: &cancellables)
    }

    // MARK: On and off screen

    /// A workspace has come on screen: the setting was turned on, or a folding phone was opened.
    /// The focused tab follows to wherever the app is; every other tab is as it was left.
    public func activate() {
        guard !isActive else { return }
        isActive = true
        if let item = appItem { change(applies: false) { $0.adopt(item) } }
    }

    /// The workspace has left the screen. The app is already at the focused tab's place, so the
    /// layout without tabs carries on from there.
    public func deactivate() {
        guard isActive else { return }
        isActive = false
        shell?.workspaceTaskPane = nil
        draggingTab = nil
    }

    // MARK: The mirror

    /// Where the app is, as a workspace item.
    private var appItem: WorkspaceItem? {
        if let shell {
            return WorkspaceItem(destination: shell.destination, taskView: model.taskView, notesFolder: model.notesFolder, openNote: shell.openNote)
        }
        return model.route.flatMap(WorkspaceItem.init)
    }

    /// Makes one change to the workspace, saves it, and (unless the change came from the app's own
    /// place) moves the app to the focused tab when that is now a different tab or place.
    private func change(applies: Bool = true, _ body: (inout Workspace) -> Void) {
        var next = workspace
        body(&next)
        guard next != workspace else { return }
        let before = workspace
        workspace = next
        save()
        if applies, next.focusedTab.id != before.focusedTab.id || next.focusedItem != before.focusedItem { applyFocused() }
    }

    private func applyFocused() {
        guard isActive else { return }
        apply(workspace.focusedItem)
    }

    /// Moves the app to a place.
    private func apply(_ item: WorkspaceItem) {
        isApplying = true
        defer { isApplying = false }
        guard let shell else {
            if model.route != item.route { model.route = item.route }
            return
        }
        let place = item.shellPlace
        if let view = place.taskView, model.taskView != view { model.show(view: view) }
        if let folder = place.notesFolder, model.notesFolder != folder || model.section != .notes { model.setNotesFolder(folder) }
        let files = place.notesFile.map { [Route.file($0)] } ?? []
        if place.destination == .notes, shell.notesPath != files { shell.notesPath = files }
        shell.show(place.destination, model: model)
    }

    /// The Mac: the route changed. Unless this store changed it, the focused tab goes there, or with
    /// ⌘ held a new tab does, and with ⌥⌘ the other pane.
    private func routeChanged(_ route: Route?) {
        guard shell == nil, isActive, !isApplying, let route, let item = WorkspaceItem(route) else { return }
        let target = Self.clickTarget()
        if target == .current, item == workspace.focusedItem, !workspace.focusedTab.isMissing { return }
        change(applies: false) { workspace in
            if !workspace.open(item, in: target) {
                workspace.open(item)
                tooManyTabs()
            }
        }
    }

    /// The iPhone: the shell or the model's place changed. The focused tab follows.
    private func shellChanged() {
        guard shell != nil, isActive, !isApplying, let item = appItem else { return }
        if item == workspace.focusedItem, !workspace.focusedTab.isMissing { return }
        change(applies: false) { $0.open(item) }
    }

    /// The iPhone: a request made through `model.route` (a link in a note, a search result, "Notes in
    /// Personal") while the workspace is on screen. It opens in the focused tab.
    public func take(_ route: Route) {
        defer { model.route = nil }
        if case let .file(path) = route, let task = model.tasks.first(where: { $0.path == path }) {
            model.selectedTaskID = task.id
            return
        }
        guard !isApplying, let item = WorkspaceItem(route) else { return }
        // Insights, Import and Settings are sheets on the iPhone, not places.
        if case let .page(page) = item, page != .agents { return }
        open(item)
    }

    /// ⌘-click opens in a new tab and ⌥⌘-click in the other pane, wherever the click was: the sidebar,
    /// a folder, a link in a note, a search result. A keyboard shortcut that holds ⌘ is not a click.
    private static func clickTarget() -> WorkspaceTarget {
        #if os(macOS)
        let flags = NSEvent.modifierFlags
        guard flags.contains(.command), let type = NSApp.currentEvent?.type, type != .keyDown, type != .keyUp else { return .current }
        return flags.contains(.option) ? .otherPane : .newTab
        #else
        return .current
        #endif
    }

    private func tooManyTabs() {
        model.banner = "That is the most tabs Perch keeps open (\(Workspace.maxTabs)). Close one to open another."
    }

    // MARK: Files

    private func filesChanged(_ files: [VaultFile]) {
        guard !files.isEmpty else { return }
        let paths = Set(files.map(\.path))
        let dropsMissing = needsRestoreCheck
        needsRestoreCheck = false
        change {
            $0.validate(fileExists: { paths.contains($0) }, folder: { NotesSubsections.existing($0, files: files) })
            if dropsMissing { $0.dropMissing(home: .home(for: model.section)) }
        }
    }

    private func save() {
        guard let defaults else { return }
        defaults.set(workspace.encoded(), forKey: Self.layoutKey)
    }

    // MARK: What the strip, the menus and the shortcuts do

    private var home: WorkspaceItem { .home(for: model.section) }

    public func open(_ item: WorkspaceItem, in target: WorkspaceTarget = .current) {
        var opened = true
        change { opened = $0.open(item, in: target) }
        if !opened { tooManyTabs() }
    }

    public func newTab() {
        var opened = true
        change { opened = $0.newTab(home) }
        if !opened { tooManyTabs() }
    }

    public func close(_ id: String) { change { $0.close(id, home: home) } }
    public func closeFocusedTab() { close(workspace.focusedTab.id) }
    public func closeOthers(keeping id: String) { change { $0.closeOthers(keeping: id) } }
    public func reopenClosedTab() { change { $0.reopenClosed() } }
    public func select(_ id: String) { change { $0.select(id) } }
    public func selectAdjacent(_ offset: Int) { change { $0.selectAdjacent(offset) } }
    public func goBack() { change { $0.goBack() } }
    public func goForward() { change { $0.goForward() } }
    public func setFraction(_ fraction: Double) { change { $0.setFraction(fraction) } }
    public func closeSplit() { change { $0.closeSplit() } }
    public func swapPanes() { change { $0.swapPanes() } }

    public func duplicate(_ id: String) {
        var opened = true
        change { opened = $0.duplicate(id) }
        if !opened { tooManyTabs() }
    }

    /// Gives a pane the focus, and says so to VoiceOver.
    public func focus(pane: Int) {
        guard workspace.focus != min(max(pane, 0), workspace.panes.count - 1) else { return }
        change { $0.focus(pane: pane) }
        let name = Self.paneName(workspace.focus, axis: workspace.axis)
        AccessibilityNotification.Announcement("\(name) pane, \(workspace.focusedTab.title)").post()
    }

    public func focusOtherPane() {
        guard workspace.isSplit else { return }
        focus(pane: 1 - workspace.focus)
    }

    /// Splits, with the tab in front shown again in the new pane.
    public func split(_ axis: SplitAxis, showing item: WorkspaceItem? = nil) {
        var opened = true
        change { opened = $0.split(axis, showing: item) }
        if !opened { tooManyTabs() }
    }

    public func move(_ id: String, toPane pane: Int, at index: Int? = nil, axis: SplitAxis? = nil) {
        change { $0.move(id, toPane: pane, at: index, axis: axis) }
    }

    /// Sends the tab in front to the other pane, making the split if there isn't one.
    public func moveFocusedTabAcross() {
        let tab = workspace.focusedTab.id
        move(tab, toPane: workspace.isSplit ? 1 - workspace.focus : 1)
    }

    static func paneName(_ index: Int, axis: SplitAxis) -> String {
        switch (axis, index) {
        case (.horizontal, 0): return "Left"
        case (.horizontal, _): return "Right"
        case (.vertical, 0): return "Top"
        case (.vertical, _): return "Bottom"
        }
    }

    // MARK: Saved workspaces

    public func saveWorkspace(as name: String) {
        var next = saved
        if next.save(workspace, as: name) {
            setSaved(next)
        } else if SavedWorkspaces.cleaned(name) != nil {
            model.banner = "Perch keeps \(SavedWorkspaces.limit) saved workspaces. Delete one to save another."
        }
    }

    public func renameWorkspace(_ name: String, to new: String) {
        var next = saved
        if next.rename(name, to: new) {
            setSaved(next)
        } else {
            model.banner = "That name can't be used: it is empty, too long, or another workspace has it."
        }
    }

    public func deleteWorkspace(_ name: String) {
        var next = saved
        next.delete(name)
        setSaved(next)
    }

    /// Replaces what is open with a saved layout. Files that have since gone are left out.
    public func showWorkspace(_ name: String) {
        guard var layout = saved.layout(named: name) else { return }
        let files = model.files
        if !files.isEmpty {
            let paths = Set(files.map(\.path))
            layout.validate(fileExists: { paths.contains($0) }, folder: { NotesSubsections.existing($0, files: files) })
            layout.dropMissing(home: home)
        }
        change { $0 = layout }
    }

    private func setSaved(_ next: SavedWorkspaces) {
        saved = next
        defaults?.set(next.encoded(), forKey: Self.savedKey)
    }

    // MARK: Debug

    #if DEBUG
    /// Checks the tabs against the notebook now, as a change to its files would.
    public func debugValidate() { filesChanged(model.files) }

    /// Sets up a workspace without interaction, for snapshots and simulator runs: tabs in the first
    /// pane, and optionally one item in a second. The app goes to the focused tab even if no
    /// workspace is on screen yet, so a folded phone starts on it.
    public func debugPreset(tabs: [WorkspaceItem], split: WorkspaceItem?) {
        var workspace = Workspace(tabs.first ?? workspace.focusedItem)
        for item in tabs.dropFirst() { workspace.newTab(item) }
        if let split { workspace.open(split, in: .otherPane) }
        self.workspace = workspace
        apply(workspace.focusedItem)
    }
    #endif
}

// MARK: - Routes

extension WorkspaceItem {
    /// The workspace item for a route. An area is a scope, not a place, and has none.
    init?(_ route: Route) {
        switch route {
        case .today: self = .tasks(.today)
        case .upcoming: self = .tasks(.upcoming)
        case .ready: self = .tasks(.ready)
        case .list: self = .tasks(.list)
        case .calendar, .week: self = .tasks(.calendar)
        case .board: self = .tasks(.board)
        case .area: return nil
        case let .file(path): self = .file(path)
        case let .folder(path): self = .folder(path)
        case .search: self = .search
        case .insights: self = .page(.insights)
        case .activity: self = .page(.activity)
        case .importer: self = .page(.importer)
        case .settings: self = .page(.settings)
        }
    }

    var route: Route {
        switch self {
        case let .tasks(view):
            switch view {
            case .today: return .today
            case .upcoming: return .upcoming
            case .list: return .list
            case .calendar: return .calendar
            case .board: return .board
            case .ready: return .ready
            }
        case let .folder(path): return .folder(path)
        case let .file(path): return .file(path)
        case .search: return .search
        case .page(.insights): return .insights
        case .page(.activity), .page(.agents): return .activity
        case .page(.importer): return .importer
        case .page(.settings): return .settings
        }
    }

    /// The task view this is, when it is one.
    var taskView: TaskViewKind? {
        if case let .tasks(view) = self { return view }
        return nil
    }
}

// MARK: - Unsaved notes

/// Which notes have typing that isn't on disk yet, for the dot on a tab. `NoteSession` keeps it.
@MainActor
final class NoteDirt: ObservableObject {
    static let shared = NoteDirt()
    @Published private(set) var paths: Set<String> = []

    func mark(_ path: String, unsaved: Bool) {
        if unsaved {
            if !paths.contains(path) { paths.insert(path) }
        } else if paths.contains(path) {
            paths.remove(path)
        }
    }
}

// MARK: - Environment

private struct WorkspaceKey: EnvironmentKey {
    static let defaultValue: WorkspaceStore? = nil
}

private struct PaneOwnsToolbarKey: EnvironmentKey {
    static let defaultValue = true
}

public extension EnvironmentValues {
    /// The workspace, where tabs and split view are on. Nil everywhere else, which is how the rest of
    /// the app knows to offer nothing about tabs.
    var perchWorkspace: WorkspaceStore? {
        get { self[WorkspaceKey.self] }
        set { self[WorkspaceKey.self] = newValue }
    }

    /// False inside a Mac workspace pane that doesn't have the focus. The Mac has one toolbar for the
    /// window; a note's buttons go there only for the pane in front.
    var perchPaneOwnsToolbar: Bool {
        get { self[PaneOwnsToolbarKey.self] }
        set { self[PaneOwnsToolbarKey.self] = newValue }
    }
}
