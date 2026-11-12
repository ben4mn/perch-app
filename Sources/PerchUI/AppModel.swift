import Combine
import Foundation
import PerchKit
import SwiftUI

/// A file that was given a new name: where it was and where it is now.
public struct FileRename: Equatable, Sendable {
    public var from: String
    public var to: String
    /// Goes up with every rename, so renaming a file back again still counts as a change.
    public var serial: Int
}

public enum Route: Hashable, Sendable {
    case today, upcoming, week, ready
    /// Every open task in one list, and tasks on a month or week calendar.
    case list, calendar
    /// Open tasks in columns by when they are due. Wide screens only; a narrow one draws Upcoming.
    case board
    case area(String)
    case file(String)
    /// A folder's contents. The empty path is the notebook's top level.
    case folder(String)
    case search, insights, activity, importer, settings
}

public enum SyncPhase: Equatable {
    case off
    case idle(Date?)
    case syncing
    case failed(String)
}

@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var vault: Vault?
    @Published public private(set) var files: [VaultFile] = []
    @Published public private(set) var tasks: [PerchTask] = []
    @Published public private(set) var links = LinkIndex(entries: [])
    @Published public private(set) var boardCards: [BoardCardReference] = []
    @Published public private(set) var syncPhase: SyncPhase = .off
    /// What the main pane shows on the Mac. On iPhone it is a request the tabs take and clear.
    /// Setting it also records the place in `nav`, so each section remembers where it was.
    @Published public var route: Route? = .today {
        didSet { routeChanged() }
    }
    /// The section in front, the task view and area in scope, and where Notes was left.
    @Published public private(set) var nav = NavigationState() {
        didSet { if nav != oldValue, savesNavigation { navigationDefaults.map(nav.save(to:)) } }
    }
    /// The user's own changes to the list of areas: added names, the order, and which are hidden.
    @Published public var areaPreferences = AreaPreferences() {
        didSet {
            guard areaPreferences != oldValue else { return }
            if savesNavigation { navigationDefaults.map(areaPreferences.save(to:)) }
            resolveScope()
        }
    }
    /// Areas added for this run only, by a debug launch argument or a snapshot step. Never saved.
    @Published public var transientAreas: [String] = []
    @Published public var searchQuery = ""
    @Published public var selectedTaskID: String?
    @Published public var pendingDelete: PerchTask?
    /// A file waiting for a yes before it is deleted. `RootOverlays` asks.
    @Published public var pendingFileDelete: String?
    /// A file whose new name is being asked for, from the sidebar or a folder. `RootOverlays` asks.
    @Published public var pendingFileRename: String?
    /// Tasks ticked a moment ago, still showing their completion before they leave the list.
    @Published public private(set) var completing: Set<String> = []
    private var pendingCompletions: [String: PendingCompletion] = [:]
    @Published public var banner: String?
    @Published public var needsNextDate: PerchTask?
    /// The last file renamed here. The iPhone keeps its own stacks of open files and moves them to the
    /// new path; the Mac's one open file is `route`, which `rename` moves itself.
    @Published public private(set) var lastRename: FileRename?
    /// Goes up when a new task is asked for by a shortcut. The quick add field on screen takes the keyboard.
    @Published public private(set) var newTaskRequests = 0
    /// Who's working in the notebook right now. The Relay fills this in.
    @Published public var agents: [AgentPresence] = []
    /// What each agent did last, newest first: from the notebook's history and the Relay's recent events.
    @Published public var agentHistory: [AgentHistory.Deed] = []
    private var relayEvents: [AgentHistory.Event] = []

    public private(set) var texts: [String: String] = [:]
    public var syncEngine: (any SyncEngine)?
    public let focusLog: FocusLog
    /// What this build was set up with: the standard areas, the owner, and the other owners on offer.
    public let configuration: PerchConfiguration
    /// The owner of the tasks of the person using Perch, and the author of what they write in a task's log.
    public var author: String

    private var cache: [String: (modified: Date?, text: String?)] = [:]
    private var signature = ""
    /// The files as last scanned, before Git's dates are put on them. `files` is these, dated.
    private var scannedFiles: [VaultFile] = []
    /// When each file was created and last edited, from the notebook's Git history (see FileHistory).
    private var fileDates: [String: FileDates] = [:]
    /// The commit `fileDates` was read at, so an unchanged history isn't read again.
    private var fileDatesHead: String?
    /// Files saved here but not committed yet: their own save time is newer than the history.
    private var uncommittedFiles: Set<String> = []
    private var isRefreshingDates = false
    /// When the Relay was last asked for the history (the iPhone only).
    private var lastHistoryCheck = Date.distantPast
    private var loops: [Task<Void, Never>] = []
    private var pendingSync: Task<Void, Never>?
    private var isReloading = false
    /// Counts this app's own changes to files and to `tasks`. See `reload`.
    private var localChanges = 0
    /// A full reload has been asked for and hasn't been applied yet.
    private var forcePending = false
    private let navigationDefaults: UserDefaults?
    private let savesNavigation: Bool
    private var isNormalizingRoute = false
    /// The saved Notes place is checked against the notebook once, after its first load.
    private var needsPlaceCheck = true
    private var pendingScopeName: String?

    /// - Parameters:
    ///   - navigationDefaults: Where the section, scope, last places and the area list are remembered.
    ///     Nil (the default, and what tests and snapshot runs use) starts fresh and saves nothing.
    ///   - savesNavigation: False reads what was saved but never writes, for a launch with debug overrides.
    ///   - configuration: The build's values. The app's own by default; tests pass their own.
    public init(supportDirectory: URL, navigationDefaults: UserDefaults? = nil, savesNavigation: Bool = true,
                configuration: PerchConfiguration = .main) {
        self.configuration = configuration
        author = configuration.ownerID
        focusLog = FocusLog(url: supportDirectory.appendingPathComponent("focus.json"))
        self.navigationDefaults = navigationDefaults
        self.savesNavigation = savesNavigation
        if let navigationDefaults {
            nav = NavigationState.load(from: navigationDefaults)
            areaPreferences = AreaPreferences.load(from: navigationDefaults)
            route = Self.route(for: nav.place(in: nav.section))
        }
    }

    public var today: String { DayMath.string(from: Date()) }

    /// Every area, in the user's order: the standard areas when their folders exist, any other area
    /// that already has tasks, and the ones the user added by name. Hidden areas are included, so quick
    /// add's `#Area` and "move to area" still know them; `visibleAreas` is what the bars show.
    public var areas: [String] {
        guard !files.isEmpty else { return [] }
        let topLevel = topLevelFolders
        let discovered = AreaList.discovered(topLevelFolders: topLevel, taskAreas: tasks.map(\.area), standard: configuration.standardAreas)
        return AreaList.all(discovered: discovered, preferences: areaPreferences, transient: transientAreas)
    }

    /// The notebook's top-level folders. A file at the top level is not one.
    private var topLevelFolders: Set<String> {
        Set(files.compactMap { file in
            let parts = file.path.split(separator: "/")
            return parts.count > 1 ? String(parts[0]) : nil
        })
    }

    /// The areas shown as sub-sections of Tasks.
    public var visibleAreas: [String] { AreaList.visible(areas, preferences: areaPreferences) }

    // MARK: Sections and scope

    public var section: AppSection { nav.section }
    public var taskView: TaskViewKind { nav.taskView }
    /// The area every task view is showing. Nil is all of them.
    public var taskScope: String? { nav.taskScope }
    public var notesFolder: String { nav.notesFolder }
    public var notesKind: NotesKind { nav.notesKind }

    /// The tasks in scope: every view reads these, so a scope applies to all of them alike.
    public var scopedTasks: [PerchTask] { TaskScope.filter(tasks, area: nav.taskScope) }
    public var scopedBoardCards: [BoardCardReference] { boardCards.filter { TaskScope.contains(path: $0.path, area: nav.taskScope) } }
    public var scopedReadyToTick: [PerchTask] { scopedTasks.filter(\.isReadyToTick) }
    /// Whether the Ready to tick view is offered: something in scope is waiting, or it is the view showing.
    public var offersReadyView: Bool { nav.taskView == .ready || scopedTasks.contains(where: \.isReadyToTick) }

    /// True while the main pane shows one of the task views.
    public var isShowingTasks: Bool {
        switch route {
        case .today, .upcoming, .week, .ready, .list, .calendar, .board, .area: return true
        default: return false
        }
    }

    static func route(for place: NavigationState.Place) -> Route {
        switch place {
        case let .tasks(view):
            switch view {
            case .today: return .today
            case .upcoming: return .upcoming
            case .list: return .list
            case .calendar: return .calendar
            case .board: return .board
            case .ready: return .ready
            }
        case let .area(name): return .area(name)
        case let .folder(path): return .folder(path)
        case let .file(path): return .file(path)
        }
    }

    private func routeChanged() {
        guard !isNormalizingRoute, let route else { return }
        switch route {
        case .today: nav.visit(.tasks(.today))
        case .upcoming: nav.visit(.tasks(.upcoming))
        case .list: nav.visit(.tasks(.list))
        case .ready: nav.visit(.tasks(.ready))
        case .board: nav.visit(.tasks(.board))
        case .calendar, .week: nav.visit(.tasks(.calendar))
        case let .area(name):
            // An area is a scope now. Anything that still asks for the old per-area screen gets that
            // area's List, which shows the same tree of tasks.
            nav.visit(.area(name))
            resolveScope()
            isNormalizingRoute = true
            self.route = .list
            isNormalizingRoute = false
        case let .folder(path): nav.visit(.folder(path))
        case let .file(path):
            // Task files open in the task views' own detail, and aren't a place in Notes.
            if VaultFile.classify(path) != .task { nav.visit(.file(path)) }
        case .search, .insights, .activity, .importer, .settings: break
        }
    }

    /// Brings a section to the front without asking the main pane for anything: the iPhone's tabs.
    public func selectSection(_ section: AppSection) {
        if nav.section != section { nav.section = section }
    }

    /// Switches to a section, back where it was left.
    public func show(_ section: AppSection) {
        route = Self.route(for: nav.place(in: section))
    }

    public func show(view: TaskViewKind) {
        route = Self.route(for: .tasks(view))
    }

    /// Puts the keyboard in the quick add field of the task view showing. The Calendar, the Board and
    /// Ready to tick have no such field, so they give way to Today, which does.
    public func requestNewTask() {
        if ![.today, .upcoming, .list].contains(nav.taskView) {
            show(view: .today)
        } else if !isShowingTasks {
            show(view: nav.taskView)
        }
        // A beat later, so a view that has only just been asked for is there to hear it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.newTaskRequests += 1 }
    }

    /// The area a folder belongs to: its top folder, when that is an area.
    public static func area(forFolder folder: String, areas: [String]) -> String? {
        guard let top = folder.split(separator: "/").first.map(String.init), !top.isEmpty else { return nil }
        return areas.first { $0 == top }
    }

    /// "New task" in the New menu: Tasks, in the folder's area when it has one, with the keyboard in quick
    /// add. From a folder outside every area the area in view stays as it was.
    public func newTask(fromFolder folder: String) {
        if let area = Self.area(forFolder: folder, areas: areas) { setScope(area) }
        requestNewTask()
    }

    /// Scopes every task view to one area, or to all of them with nil.
    public func setScope(_ area: String?) {
        applyScope(area)
        if !isShowingTasks { show(view: nav.taskView) }
    }

    /// Every change of scope ends up here. Once the notebook has loaded, a name that isn't one of the
    /// areas on offer is All, so nothing can scope the views to an area that can't be seen or left.
    private func applyScope(_ area: String?) {
        let scope = files.isEmpty ? area : TaskScope.resolved(area, in: visibleAreas)
        if nav.taskScope != scope { nav.taskScope = scope }
    }

    /// Scopes Tasks to the area with this name, ignoring case and a leading emoji: "work" finds
    /// "✈️ Work". Before the notebook has loaded the name is kept and applied once it has.
    /// For launch arguments and snapshot steps, which can't easily type an emoji.
    public func setScope(named name: String) {
        guard !name.isEmpty else { return setScope(nil) }
        guard !files.isEmpty else {
            pendingScopeName = name
            return
        }
        if let area = visibleAreas.first(where: { AreaList.isSame($0, name) }) { setScope(area) }
    }

    /// Jumps to an area's tasks, in whichever view Tasks was left in.
    public func showTasks(area: String?) {
        applyScope(area)
        show(view: nav.taskView)
    }

    /// Changes the folder the notes browser shows, without asking the main pane for it: the iPhone's Notes tab.
    public func setNotesFolder(_ path: String) {
        nav.visit(.folder(path))
    }

    public func setNotesKind(_ kind: NotesKind) {
        if nav.notesKind != kind { nav.notesKind = kind }
    }

    /// The folder that goes with an area, when the area is also a top-level folder with something to browse.
    public func notesFolder(forArea area: String?) -> String? {
        guard let area else { return nil }
        let prefix = area + "/"
        return files.contains { $0.path.hasPrefix(prefix) && FolderListing.browsableKinds.contains($0.kind) } ? area : nil
    }

    /// The area that goes with a folder: the area named like its top-level folder, if there is one.
    public func area(forFolder path: String) -> String? {
        guard let top = path.split(separator: "/").first.map(String.init) else { return nil }
        return visibleAreas.contains(top) ? top : nil
    }

    /// Adds an area by name and returns what it resolved to. Nothing is written to the notebook:
    /// the area's `Tasks` folder appears with its first task.
    @discardableResult
    public func addArea(_ name: String) -> String? {
        var preferences = areaPreferences
        guard let area = AreaList.add(name, to: &preferences, existing: areas, topLevelFolders: Array(topLevelFolders)) else { return nil }
        areaPreferences = preferences
        return area
    }

    /// An area can be taken off the list while it is only a name: no tasks, and not one of the standard ones.
    public func canRemoveArea(_ area: String) -> Bool {
        areaPreferences.extra.contains(area) && !tasks.contains { $0.area == area }
    }

    /// A scope whose area is no longer on offer falls back to All.
    private func resolveScope() {
        guard !files.isEmpty, nav.taskScope != nil else { return }
        let resolved = TaskScope.resolved(nav.taskScope, in: visibleAreas)
        if resolved != nav.taskScope { nav.taskScope = resolved }
    }

    /// After the first load, a remembered folder or file that is gone gives way to the nearest folder that exists.
    private func checkRememberedPlace() {
        if let name = pendingScopeName, !files.isEmpty {
            pendingScopeName = nil
            if let area = visibleAreas.first(where: { AreaList.isSame($0, name) }), nav.taskScope != area { nav.taskScope = area }
        }
        resolveScope()
        guard needsPlaceCheck, !files.isEmpty else { return }
        needsPlaceCheck = false
        let folder = NotesSubsections.existing(nav.notesFolder, files: files)
        if folder != nav.notesFolder {
            nav.notesFolder = folder
            if case .folder = route { route = .folder(folder) }
        }
        if let file = nav.notesFile, !files.contains(where: { $0.path == file }) {
            nav.notesFile = nil
            if route == .file(file) { route = .folder(NotesSubsections.existing((file as NSString).deletingLastPathComponent, files: files)) }
        }
    }

    // MARK: Opening

    public func open(root: URL, engine: (any SyncEngine)?) {
        defer { Task { await refreshAgentHistory() } }
        // Ticks still waiting belong to the notebook that is closing. Write them there, before `vault`
        // changes, or they would be written into the new one (or lost).
        flushCompletions()
        loops.forEach { $0.cancel() }
        if let vault, vault.root.standardizedFileURL != root.standardizedFileURL {
            // Nothing from the old notebook may be shown, ticked or saved against the new one.
            files = []
            scannedFiles = []
            fileDates = [:]
            fileDatesHead = nil
            uncommittedFiles = []
            lastHistoryCheck = .distantPast
            texts = [:]
            tasks = []
            links = LinkIndex(entries: [])
            boardCards = []
            selectedTaskID = nil
            needsNextDate = nil
            pendingDelete = nil
            pendingFileDelete = nil
            pendingFileRename = nil
        }
        vault = Vault(root: root)
        needsPlaceCheck = true
        localChanges += 1
        syncEngine = engine
        syncPhase = engine == nil ? .off : .idle(nil)
        cache = [:]
        signature = ""
        Task { await reload(force: true) }
        loops = [
            Task { [weak self] in
                // Picks up changes from other apps and agents, like the Claude routine.
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await self?.reload()
                }
            },
        ]
        if engine != nil {
            loops.append(Task { [weak self] in
                await self?.syncNow()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    await self?.syncNow()
                }
            })
        }
    }

    private var relayLoop: Task<Void, Never>?

    /// Polls the Relay for agent presence. Pass nil to stop.
    /// Whether the Relay is answering, for Settings.
    @Published public private(set) var relayStatus: RelayStatus = .off

    public func connectRelay(_ client: RelayClient?) {
        relayLoop?.cancel()
        agents = []
        guard let client else {
            relayStatus = .off
            return
        }
        relayStatus = .connecting
        relayLoop = Task { [weak self] in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            while !Task.isCancelled {
                let answer: (agents: [RelayClient.Agent], events: [RelayClient.Event])?
                do {
                    answer = try await client.presence()
                } catch {
                    // A newer Connect cancelled this loop: its own status stands.
                    if Task.isCancelled { return }
                    self?.relayStatus = RelayStatus(error: error)
                    if self?.relayStatus == .refused { self?.agents = [] }
                    answer = nil
                }
                if let presence = answer, !Task.isCancelled {
                    self?.relayStatus = .connected(agentsHere: presence.agents.filter(\.isActive).count)
                    self?.agents = presence.agents.map {
                        AgentPresence(name: $0.name, status: $0.status, isActive: $0.isActive, path: $0.path, updated: formatter.date(from: $0.updated) ?? Date(), link: $0.sessionLink)
                    }
                    self?.relayEvents = presence.events.compactMap { event in
                        formatter.date(from: event.at).map { AgentHistory.Event(agent: event.agent, kind: event.kind, text: event.text, path: event.path, date: $0) }
                    }
                    await self?.refreshAgentHistory()
                    #if os(iOS)
                    // No Git here: the Relay's copy of the history gives each file its real dates.
                    // Checked about once a minute; an unchanged history costs one small request.
                    if let self, Date().timeIntervalSince(self.lastHistoryCheck) > 55 {
                        self.lastHistoryCheck = Date()
                        if let answer = try? await client.history(etag: self.fileDatesHead), !Task.isCancelled {
                            self.useFileHistory(answer.log, head: answer.etag)
                        }
                    }
                    #endif
                }
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    public func close() {
        flushCompletions()
        loops.forEach { $0.cancel() }
        loops = []
    }

    // MARK: Loading

    /// Reads the notebook from disk off the main thread, then swaps the result in.
    ///
    /// The scan takes a moment, and the app can change a task while it runs (a drag to another day,
    /// a tick, a quick add). A scan that started before that change may have read the old file, and
    /// applying it would put the old task back on screen until the next pass. So every local change
    /// bumps `localChanges`, and a scan result is thrown away if the count moved while it was running.
    /// The next pass, at most three seconds later, reads the file as it now is.
    ///
    /// A forced reload is never lost that way: it stays pending, is retried straight away a few times,
    /// and after that the regular three-second pass carries it out. A forced reload asked for while a
    /// scan is already running is picked up by that running call instead of being dropped.
    public func reload(force: Bool = false) async {
        if force { forcePending = true }
        // A reader page is kept loaded for the next note to open. Costs nothing once one is waiting.
        WebHost.prewarmReader()
        guard vault != nil, !isReloading else { return }
        isReloading = true
        defer { isReloading = false }
        var passes = 0
        repeat {
            guard let vault else { return }
            passes += 1
            let forced = forcePending
            forcePending = false
            let startedAt = localChanges
            let previous = cache
            let previousSignature = signature
            let result: LoadResult? = await Task.detached(priority: .utility) {
                AppModel.load(vault: vault, cache: previous, previousSignature: forced ? nil : previousSignature)
            }.value
            guard startedAt == localChanges else {
                if forced { forcePending = true }
                continue
            }
            guard let result else { continue }
            cache = result.cache
            signature = result.signature
            scannedFiles = result.files
            files = FileHistory.apply(fileDates, uncommitted: uncommittedFiles, to: result.files)
            Task { await refreshFileDates() }
            texts = result.texts
            tasks = result.tasks
            links = result.links
            boardCards = result.boardCards
            checkRememberedPlace()
        } while forcePending && passes < 4
    }

    private struct LoadResult: Sendable {
        var cache: [String: (modified: Date?, text: String?)]
        var signature: String
        var files: [VaultFile]
        var texts: [String: String]
        var tasks: [PerchTask]
        var links: LinkIndex
        var boardCards: [BoardCardReference]
    }

    private nonisolated static func load(
        vault: Vault,
        cache: [String: (modified: Date?, text: String?)],
        previousSignature: String?
    ) -> LoadResult? {
        guard let files = try? vault.scan() else { return nil }
        var hasher = Hasher()
        for file in files {
            hasher.combine(file.path)
            hasher.combine(file.modified)
        }
        let signature = String(hasher.finalize())
        if signature == previousSignature { return nil }

        var newCache: [String: (modified: Date?, text: String?)] = [:]
        var texts: [String: String] = [:]
        var tasks: [PerchTask] = []
        var cards: [BoardCardReference] = []
        var entries: [(file: VaultFile, text: String?)] = []
        for file in files {
            var text: String?
            if file.kind == .note || file.kind == .task || file.kind == .board {
                if let cached = cache[file.path], cached.modified == file.modified {
                    text = cached.text
                } else {
                    text = try? vault.read(file.path)
                }
            }
            newCache[file.path] = (file.modified, text)
            entries.append((file, text))
            guard let text else { continue }
            texts[file.path] = text
            if file.kind == .task, let task = try? TaskCodec.decode(path: file.path, text: text) { tasks.append(task) }
            if file.kind == .board {
                for list in KanbanCodec.parse(text).board.lists {
                    for card in list.cards where !card.isCompleted && card.dueDate != nil {
                        cards.append(.init(path: file.path, board: file.title, list: list.name, card: card))
                    }
                }
            }
        }
        return LoadResult(
            cache: newCache, signature: signature, files: files, texts: texts, tasks: tasks,
            links: LinkIndex(entries: entries), boardCards: cards
        )
    }

    // MARK: Sync

    public func scheduleSync() {
        guard syncEngine != nil else { return }
        pendingSync?.cancel()
        pendingSync = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    /// Reads each file's real dates from the notebook's Git history (the Mac), and puts them on `files`.
    /// The iPhone has no Git: it gets the same history from the Relay instead (see `connectRelay`).
    public func refreshFileDates() async {
        #if os(macOS)
        guard let vault, !isRefreshingDates else { return }
        isRefreshingDates = true
        defer { isRefreshingDates = false }
        let git = (syncEngine as? GitCLISync) ?? GitCLISync(root: vault.root)
        guard let snapshot = await git.fileHistory(knownHead: fileDatesHead), self.vault?.root == vault.root else { return }
        if let dates = snapshot.dates {
            fileDates = dates
            fileDatesHead = snapshot.head
        } else if snapshot.uncommitted == uncommittedFiles {
            return
        }
        uncommittedFiles = snapshot.uncommitted
        applyFileDates()
        #endif
    }

    /// Takes a Git history read elsewhere (the Relay's, on the iPhone), keyed by the commit it was read at.
    func useFileHistory(_ log: String, head: String) {
        guard head != fileDatesHead else { return }
        fileDates = FileHistory.parse(log)
        fileDatesHead = head
        applyFileDates()
    }

    private func applyFileDates() {
        let dated = FileHistory.apply(fileDates, uncommitted: uncommittedFiles, to: scannedFiles)
        if dated != files { files = dated }
    }

    /// Recomputes what each agent did last. Agents' writes arrive as commits under their own names.
    public func refreshAgentHistory() async {
        var commits: [AgentHistory.Commit] = []
        #if os(macOS)
        // The history is read even with sync turned off: it is only `git log` on the notebook.
        if let git = (syncEngine as? GitCLISync) ?? vault.map({ GitCLISync(root: $0.root) }) {
            let parser = ISO8601DateFormatter()
            commits = await git.log(limit: 200).compactMap { entry in
                parser.date(from: entry.date).map { AgentHistory.Commit(author: entry.author, email: entry.email, date: $0, subject: entry.subject) }
            }
        }
        #endif
        let history = AgentHistory.latest(commits: commits, events: relayEvents)
        if history != agentHistory { agentHistory = history }
    }

    public func syncNow() async {
        defer { Task { await refreshAgentHistory(); await refreshFileDates() } }
        guard let syncEngine, syncPhase != .syncing else { return }
        syncPhase = .syncing
        do {
            let result = try await syncEngine.sync()
            syncPhase = .idle(Date())
            if result.pulled > 0 || !result.conflicts.isEmpty { await reload(force: true) }
            if !result.conflicts.isEmpty {
                banner = "\(result.conflicts.count) file(s) changed on two devices. Both versions were kept for you to choose."
            }
        } catch {
            syncPhase = .failed(error.localizedDescription)
        }
    }

    // MARK: Files

    public func text(of path: String) -> String { texts[path] ?? (try? vault?.read(path)) ?? "" }

    public func save(_ text: String, to path: String) {
        guard let vault else { return }
        do {
            try vault.write(text, to: path)
            localChanges += 1
            texts[path] = text
            scheduleSync()
        } catch {
            banner = "Couldn't save \(VaultFile(path: path).name): \(error.localizedDescription)"
        }
    }

    public func createNote(in folder: String, kind: VaultFileKind = .note) -> String? {
        guard let vault else { return nil }
        let (base, suffix, content): (String, String, String) = {
            switch kind {
            case .board: return ("New Board", ".kanban.md", "## To Do\n\n## Doing\n\n## Done")
            case .whiteboard: return ("New Whiteboard", ".excalidraw", #"{"type":"excalidraw","version":2,"source":"perch","elements":[],"appState":{},"files":{}}"#)
            default: return ("New Note", ".md", "")
            }
        }()
        var counter = 1
        var path: String
        repeat {
            let name = counter == 1 ? base + suffix : "\(base) \(counter)\(suffix)"
            path = folder.isEmpty ? name : "\(folder)/\(name)"
            counter += 1
        } while vault.exists(path)
        save(content, to: path)
        Task { await reload(force: true) }
        route = .file(path)
        return path
    }

    /// Renames a note and updates every `[[link]]` that pointed at its old title.
    public func rename(_ path: String, to newTitle: String) {
        guard let vault else { return }
        let file = VaultFile(path: path)
        let cleanTitle = jsTrim(newTitle)
        guard !cleanTitle.isEmpty, cleanTitle != file.title, !cleanTitle.contains("/") else { return }
        let suffix = String(file.name.dropFirst(file.title.count))
        let newPath = file.folder.isEmpty ? cleanTitle + suffix : "\(file.folder)/\(cleanTitle)\(suffix)"
        guard !vault.exists(newPath) else {
            banner = "A file named \(cleanTitle) already exists here."
            return
        }
        do {
            NoteSession.saveAll(at: path)
            try vault.move(path, to: newPath)
            NoteSession.retire(at: path)
            NoteResume.shared.renamed(from: path, to: newPath)
            localChanges += 1
            for source in links.backlinks(to: path) where source != path {
                guard let text = texts[source] else { continue }
                var updated = WikiLinks.rewrite(text, from: file.title, to: cleanTitle)
                let oldStem = String(path.dropLast(suffix.count))
                let newStem = String(newPath.dropLast(suffix.count))
                updated = WikiLinks.rewrite(updated, from: oldStem, to: newStem)
                if updated != text { try vault.write(updated, to: source) }
            }
            if route == .file(path) { route = .file(newPath) }
            if nav.notesFile == path { nav.notesFile = newPath }
            lastRename = FileRename(from: path, to: newPath, serial: (lastRename?.serial ?? 0) + 1)
            Task { await reload(force: true) }
            scheduleSync()
        } catch {
            banner = "Couldn't rename: \(error.localizedDescription)"
        }
    }

    public func deleteFile(_ path: String) {
        guard let vault else { return }
        do {
            try vault.delete(path)
            localChanges += 1
            // A deleted note gives way to the folder it was in, so the section doesn't change under you.
            if nav.notesFile == path { nav.notesFile = nil }
            if route == .file(path) {
                // A task's own page gives way to the task view that was showing, in the same scope.
                route = VaultFile.classify(path) == .task
                    ? Self.route(for: .tasks(nav.taskView))
                    : .folder(NotesSubsections.existing((path as NSString).deletingLastPathComponent, files: files.filter { $0.path != path }))
            }
            Task { await reload(force: true) }
            scheduleSync()
        } catch {
            banner = "Couldn't delete: \(error.localizedDescription)"
        }
    }

    // MARK: Tasks

    private var store: TaskStore? { vault.map(TaskStore.init) }

    public func task(id: String?) -> PerchTask? {
        guard let id else { return nil }
        return tasks.first { $0.id == id }
    }

    public func subtasks(of task: PerchTask) -> [PerchTask] {
        tasks.filter { $0.parent == task.id }.sorted(by: Self.ordered)
    }

    public nonisolated static func ordered(_ a: PerchTask, _ b: PerchTask) -> Bool {
        if a.priority != b.priority { return a.priority < b.priority }
        switch (a.due, b.due) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    /// Top-level tasks, plus subtasks whose parent isn't in the list, so nothing can vanish: a subtask
    /// whose parent is in another area, is finished, or doesn't match a filter stands on its own.
    public func roots(_ list: [PerchTask]) -> [PerchTask] {
        let ids = Set(list.map(\.id))
        return list.filter { $0.parent == nil || !ids.contains($0.parent!) }
    }

    public var todayTasks: [PerchTask] {
        tasks.filter { $0.isDueTodayOrEarlier(today: today) }.sorted(by: Self.ordered)
    }

    public var readyToTick: [PerchTask] { tasks.filter(\.isReadyToTick) }

    #if DEBUG
    /// For the snapshot runner only: changes the tasks in memory for a picture. Nothing is saved.
    public func debugChangeTasks(_ change: (inout [PerchTask]) -> Void) { change(&tasks) }
    /// For the snapshot runner only: shows a Relay status without connecting to anything.
    public func debugShowRelayStatus(_ status: RelayStatus) { relayStatus = status }
    #endif

    public func update(_ task: PerchTask) {
        guard let store else { return }
        do {
            localChanges += 1
            if let index = tasks.firstIndex(where: { $0.id == task.id }) { tasks[index] = task }
            try store.save(task)
            scheduleSync()
        } catch {
            banner = "Couldn't save the task: \(error.localizedDescription)"
        }
    }

    public func move(_ task: PerchTask, toArea area: String) {
        guard let vault, task.area != area else { return }
        var updated = task
        let name = (task.path as NSString).lastPathComponent
        updated.path = "\(area)/Tasks/\(name)"
        do {
            try vault.move(task.path, to: updated.path)
            localChanges += 1
            update(updated)
            Task { await reload(force: true) }
        } catch {
            banner = "Couldn't move the task: \(error.localizedDescription)"
        }
    }

    public func complete(_ task: PerchTask, manualNextDue: String? = nil) {
        guard let store else { return }
        // This is the completion. A tick still waiting for the same task must not complete it a second
        // time, which would move a repeating task on by two periods.
        dropPendingCompletion(task.id)
        if manualNextDue == nil, store.needsManualNextDate(task) {
            needsNextDate = task
            return
        }
        do {
            let updated = try store.complete(task, by: author, manualNextDue: manualNextDue)
            localChanges += 1
            if let index = tasks.firstIndex(where: { $0.id == task.id }) { tasks[index] = updated }
            scheduleSync()
        } catch {
            banner = "Couldn't complete the task: \(error.localizedDescription)"
        }
    }

    // MARK: Completing with a moment to see it

    /// What a task looked like when it was ticked, to tell whether someone else completed it meanwhile.
    private struct PendingCompletion {
        var timer: Task<Void, Never>
        var due: String?
        var activityCount: Int
    }

    /// Ticks a task but writes the completion after `delay`, so the row can show its check first.
    ///
    /// The wait lives here, not in the row, so it survives the row scrolling away or its screen closing.
    /// The task is read fresh when the time comes, so an edit made meanwhile is kept, and
    /// `cancelCompleting` undoes the tick. `flushCompletions` writes anything still waiting at once.
    ///
    /// However it ends, a tick completes its task at most once: `complete`, `reopen` and `delete` all
    /// drop a waiting tick for the same task, and a repeating task that something else moved on while
    /// the tick waited (another device, an agent) is left where it is.
    public func beginCompleting(_ task: PerchTask, after delay: Double) {
        guard let store, !completing.contains(task.id), let current = self.task(id: task.id), current.isOpen else { return }
        if store.needsManualNextDate(current) {
            needsNextDate = current
            return
        }
        let id = task.id
        completing.insert(id)
        let timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(delay, 0) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.finishCompleting(id)
        }
        pendingCompletions[id] = PendingCompletion(timer: timer, due: current.due, activityCount: current.activity.count)
    }

    /// Takes back a tick that hasn't been written yet.
    public func cancelCompleting(_ id: String) { dropPendingCompletion(id) }

    /// Writes every waiting completion now. Called when the app goes to the background, quits, or closes the notebook.
    public func flushCompletions() {
        for id in pendingCompletions.keys.sorted() { finishCompleting(id) }
    }

    #if DEBUG
    /// Draws a task as just ticked without ever writing it, for checking the look in a snapshot.
    public func debugShowCompleting(_ id: String) { completing.insert(id) }
    #endif

    private func dropPendingCompletion(_ id: String) {
        pendingCompletions.removeValue(forKey: id)?.timer.cancel()
        if completing.contains(id) { completing.remove(id) }
    }

    private func finishCompleting(_ id: String) {
        guard let pending = pendingCompletions[id] else { return }
        dropPendingCompletion(id)
        guard let fresh = task(id: id), fresh.isOpen else { return }
        // A repeating task stays open when completed, so "still open" doesn't prove nobody completed it.
        // If its date moved and a completion was logged since the tick, that was the completion.
        if fresh.recurrence != nil, fresh.due != pending.due,
           fresh.activity.dropFirst(pending.activityCount).contains(where: { $0.text.hasPrefix("Completed; next due") }) {
            return
        }
        complete(fresh)
    }

    public func reopen(_ task: PerchTask) {
        guard let store else { return }
        dropPendingCompletion(task.id)
        try? store.reopen(task)
        localChanges += 1
        Task { await reload(force: true) }
        scheduleSync()
    }

    public func delete(_ task: PerchTask) {
        dropPendingCompletion(task.id)
        for child in subtasks(of: task) {
            var orphan = child
            orphan.parent = nil
            update(orphan)
        }
        deleteFile(task.path)
        localChanges += 1
        tasks.removeAll { $0.id == task.id }
        if selectedTaskID == task.id { selectedTaskID = nil }
    }

    /// Moves tasks to a day, or clears their date when `day` is nil, and returns the ids that changed.
    ///
    /// Every way of rescheduling ends up here: drags, drops, the Move to menu, the date sheet. Each task
    /// is read fresh from the model, so several moves in a row build on each other, and only `due` changes.
    /// Ids that aren't an open task, and tasks already on that day, are skipped without touching their files.
    @discardableResult
    public func move(taskIDs: [String], to day: String?) -> [String] {
        var moved: [String] = []
        for id in taskIDs {
            guard let task = task(id: id), let updated = TaskCalendar.rescheduled(task, to: day) else { continue }
            update(updated)
            moved.append(id)
        }
        return moved
    }

    public func reschedule(_ list: [PerchTask], to date: String) {
        move(taskIDs: list.map(\.id), to: date)
    }

    /// `defaultDue` is the day to use when the text itself doesn't name one, for adding from a calendar day.
    @discardableResult
    public func quickAdd(_ text: String, defaultArea: String? = nil, defaultDue: String? = nil, parent: PerchTask? = nil) -> PerchTask? {
        guard let store else { return nil }
        let parsed = QuickAdd.parse(text, areas: areas)
        guard !parsed.title.isEmpty else { return nil }
        let area = parent?.area ?? parsed.area ?? defaultArea ?? visibleAreas.first ?? areas.first ?? "Personal"
        do {
            let task = try store.create(title: parsed.title, area: area, configure: { task in
                task.due = parsed.due ?? defaultDue
                task.time = parsed.time
                task.recurrence = parsed.recurrence
                task.labels = parsed.labels
                task.priority = parsed.priority ?? 4
                task.owner = parsed.owner ?? self.author
                task.parent = parent?.id
            })
            localChanges += 1
            tasks.append(task)
            texts[task.path] = TaskCodec.encode(task)
            scheduleSync()
            Task { await reload(force: true) }
            return task
        } catch {
            banner = "Couldn't add the task: \(error.localizedDescription)"
            return nil
        }
    }

    public func addActivity(to task: PerchTask, text: String) {
        var updated = task
        updated.activity.append(.init(date: today, author: author, text: text))
        update(updated)
    }

    public func acceptProposal(_ task: PerchTask) { complete(task) }

    public func rejectProposal(_ task: PerchTask) {
        var updated = task
        updated.activity.append(.init(date: today, author: author, text: "Not done yet: declined \(task.proposedDoneBy ?? "the agent")'s proposal."))
        updated.clearProposal()
        update(updated)
    }

    // MARK: Search

    public struct SearchHit: Identifiable, Hashable {
        public var path: String
        public var title: String
        public var snippet: String
        public var kind: VaultFileKind
        public var id: String { path }
    }

    public func search(_ query: String, limit: Int = 100) -> [SearchHit] {
        let needle = jsTrim(query)
        guard !needle.isEmpty else { return [] }
        var titleHits: [SearchHit] = []
        var bodyHits: [SearchHit] = []
        for file in files where file.kind != .attachment && file.kind != .other {
            let text = texts[file.path] ?? ""
            let task = file.kind == .task ? tasks.first { $0.path == file.path } : nil
            let title = task?.title ?? file.title
            if title.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                titleHits.append(.init(path: file.path, title: title, snippet: file.folder, kind: file.kind))
            } else if let range = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) {
                let start = text.index(range.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
                let end = text.index(range.upperBound, offsetBy: 80, limitedBy: text.endIndex) ?? text.endIndex
                let snippet = text[start..<end].replacingOccurrences(of: "\n", with: " ")
                bodyHits.append(.init(path: file.path, title: title, snippet: snippet, kind: file.kind))
            }
        }
        return Array((titleHits + bodyHits).prefix(limit))
    }
}

public struct BoardCardReference: Identifiable, Hashable, Sendable {
    public var path: String
    public var board: String
    public var list: String
    public var card: KanbanCard
    public var id: String { path + "#" + card.title + list }
}

public struct AgentPresence: Identifiable, Equatable, Sendable {
    public var name: String
    public var status: String
    public var isActive: Bool
    public var path: String?
    public var updated: Date
    /// Opens the session the agent is working in, when Perch knows it.
    public var link: URL?
    public var id: String { name }

    public init(name: String, status: String, isActive: Bool, path: String? = nil, updated: Date = Date(), link: URL? = nil) {
        self.name = name
        self.status = status
        self.isActive = isActive
        self.path = path
        self.updated = updated
        self.link = link
    }
}
