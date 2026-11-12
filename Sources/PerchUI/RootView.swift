import PerchKit
import SwiftUI

/// A folder in the notes tree.
struct FolderNode: Identifiable, Hashable {
    var id: String { path }
    var name: String
    var path: String
    var folders: [FolderNode]
    var files: [VaultFile]

    /// - Parameter kinds: only these kinds of file are listed, and only the folders that hold some.
    static func tree(from files: [VaultFile], kinds: Set<VaultFileKind> = FolderListing.browsableKinds) -> FolderNode {
        final class Builder {
            var name: String, path: String
            var folders: [String: Builder] = [:]
            var files: [VaultFile] = []
            init(name: String, path: String) { self.name = name; self.path = path }
            func build() -> FolderNode {
                FolderNode(
                    name: name, path: path,
                    folders: folders.values.map { $0.build() }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                    files: files.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                )
            }
        }
        let root = Builder(name: "", path: "")
        for file in files where kinds.contains(file.kind) {
            var node = root
            let parts = file.path.split(separator: "/").map(String.init).dropLast()
            var current = ""
            for part in parts {
                current = current.isEmpty ? part : current + "/" + part
                if node.folders[part] == nil { node.folders[part] = Builder(name: part, path: current) }
                node = node.folders[part]!
            }
            node.files.append(file)
        }
        return root.build()
    }
}

/// One row showing in the sidebar's notes tree: a folder or a file, at its depth.
struct SidebarEntry: Identifiable, Hashable {
    enum Kind: Hashable {
        case folder(isExpanded: Bool)
        case file(VaultFileKind)
    }

    var route: Route
    var title: String
    var depth: Int
    var kind: Kind
    var id: Route { route }

    /// The folder's path when this row is a folder.
    var folderPath: String? {
        if case .folder = kind, case let .folder(path) = route { return path }
        return nil
    }
}

extension FolderNode {
    /// The rows that show under this folder, top to bottom, given which folders are open. Only what is
    /// showing is listed, so a notebook with a thousand files costs a handful of rows until a folder is opened.
    func visibleEntries(expanded: Set<String>, depth: Int = 0) -> [SidebarEntry] {
        var entries: [SidebarEntry] = []
        collect(into: &entries, expanded: expanded, depth: depth)
        return entries
    }

    private func collect(into entries: inout [SidebarEntry], expanded: Set<String>, depth: Int) {
        for folder in folders {
            let isOpen = expanded.contains(folder.path)
            entries.append(SidebarEntry(route: .folder(folder.path), title: folder.name, depth: depth, kind: .folder(isExpanded: isOpen)))
            if isOpen { folder.collect(into: &entries, expanded: expanded, depth: depth + 1) }
        }
        for file in files {
            entries.append(SidebarEntry(route: .file(file.path), title: file.title, depth: depth, kind: .file(file.kind)))
        }
    }
}

/// The sidebar's keyboard rules, kept apart from the view so they can be tested.
enum SidebarKeys {
    /// The folders that must be open for a route to show in the tree: every folder above a file or folder.
    static func ancestors(of route: Route?) -> [String] {
        let path: String
        switch route {
        case let .file(file): path = file
        case let .folder(folder): path = folder
        default: return []
        }
        var parts = path.split(separator: "/").map(String.init)
        guard parts.count > 1 else { return [] }
        parts.removeLast()
        var result: [String] = []
        var current = ""
        for part in parts {
            current = current.isEmpty ? part : current + "/" + part
            result.append(current)
        }
        return result
    }

    /// The row `offset` places from the selected one, stopping at either end. With nothing selected
    /// (or the selection not in the list), Down picks the first row and Up the last.
    static func step(from selected: Route?, by offset: Int, in rows: [Route]) -> Route? {
        guard !rows.isEmpty else { return nil }
        guard let selected, let index = rows.firstIndex(of: selected) else { return offset >= 0 ? rows.first : rows.last }
        return rows[min(max(index + offset, 0), rows.count - 1)]
    }

    /// The folder a row sits in, for the Left arrow. Nil at the top level.
    static func parent(of route: Route?) -> Route? {
        ancestors(of: route).last.map { Route.folder($0) }
    }

    /// The next row whose name starts with what was typed, looking after the selected row first and
    /// wrapping round. A leading emoji or symbol in a name is skipped, so "p" finds "🏠 Personal".
    static func match(_ typed: String, in rows: [(route: Route, title: String)], after selected: Route?) -> Route? {
        let needle = typed.lowercased()
        guard !needle.isEmpty, !rows.isEmpty else { return nil }
        let start = selected.flatMap { route in rows.firstIndex { $0.route == route } } ?? -1
        // While a word is being typed the selected row may keep matching; a single letter moves on.
        let offsets = needle.count > 1 ? Array(0..<rows.count) : Array(1...rows.count)
        for offset in offsets {
            let row = rows[((start < 0 ? 0 : start) + offset) % rows.count]
            let name = row.title.lowercased().drop { !$0.isLetter && !$0.isNumber }
            if name.hasPrefix(needle) { return row.route }
        }
        return nil
    }
}

/// One row of the sidebar: an icon, a name and an optional count. Drawn by Perch rather than the system,
/// so its selection and hover colors come from the theme and stay readable on every one.
struct SidebarRow: View {
    let title: String
    let symbol: String
    var count = 0
    /// A small red dot before the count: something here is overdue.
    var alert = false
    var depth = 0
    var isSelected = false
    /// Draws the keyboard focus ring: this row is selected and the sidebar has the keyboard.
    var showsFocus = false
    /// Nil for a row with nothing to open; otherwise whether the folder is open.
    var isExpanded: Bool?
    /// Space before the icon for rows with no chevron.
    var inset: CGFloat = SidebarRow.chevronWidth
    var select: () -> Void
    var toggle: (() -> Void)?
    @Environment(\.perchTheme) private var theme
    @State private var hovering = false

    // A pointer's sizes on the Mac; a finger's on iPhone, where every row is a 44-point target.
    #if os(iOS)
    static let chevronWidth: CGFloat = 26
    static var rowHeight: CGFloat { max(Metrics.minTap, Metrics.row(40)) }
    private static let iconSize: CGFloat = 15.5
    private static let iconWidth: CGFloat = 22
    private static let chevronSize: CGFloat = 10.5
    private static let indent: CGFloat = 16
    #else
    static let chevronWidth: CGFloat = 14
    static var rowHeight: CGFloat { Metrics.row(26) }
    private static let iconSize: CGFloat = 12.5
    private static let iconWidth: CGFloat = 18
    private static let chevronSize: CGFloat = 8.5
    private static let indent: CGFloat = 14
    #endif

    var body: some View {
        HStack(spacing: 0) {
            if let isExpanded, let toggle {
                Button(action: toggle) {
                    Image(systemName: "chevron.right")
                        .font(.perchFixed(size: Self.chevronSize, weight: .bold))
                        .foregroundStyle(theme.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: Self.chevronWidth, height: Self.rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: inset, height: 1)
            }
            Button(action: select) {
                HStack(spacing: 7) {
                    Image(systemName: symbol)
                        .font(.perchFixed(size: Self.iconSize, weight: .medium))
                        .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
                        .frame(width: Self.iconWidth)
                    Text(title).font(.perchBody).foregroundStyle(theme.text).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    if alert { Circle().fill(theme.danger).frame(width: 6, height: 6).transition(.opacity) }
                    if count > 0 {
                        Text("\(count)")
                            .font(.perchCaption.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(isSelected ? theme.accent : theme.textMuted)
                            .contentTransition(.numericText())
                            .transition(.opacity)
                    }
                }
                .frame(minHeight: Self.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, CGFloat(depth) * Self.indent + 6)
        .padding(.trailing, 8)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(isSelected ? theme.accentSoft : (hovering ? theme.wash : Color.clear)))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(showsFocus ? theme.accent : Color.clear, lineWidth: 1.5))
        .onHover { hovering = $0 }
        #if os(iOS)
        .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 6, style: .continuous))
        .hoverEffect(.highlight)
        #endif
        .motion(Motion.quick, value: hovering)
        .motion(Motion.quick, value: isSelected)
        .motion(Motion.smooth, value: count)
        .help(title)
        // One element for VoiceOver: its name and count, whether it is the selected one, and for a
        // folder whether it is open, with opening and closing as an action of its own.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((count > 0 ? "\(title), \(count)" : title) + (alert ? ", some overdue" : ""))
        .accessibilityValue(isExpanded.map { $0 ? "Expanded" : "Collapsed" } ?? "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, select)
        .accessibilityActions {
            if let isExpanded, let toggle { Button(isExpanded ? "Collapse" : "Expand", action: toggle) }
        }
    }
}

func fileIcon(_ kind: VaultFileKind) -> String {
    switch kind {
    case .board: return "rectangle.split.3x1"
    case .whiteboard: return "scribble"
    case .notebook: return "curlybraces.square"
    case .task: return "checkmark.circle"
    default: return "doc.text"
    }
}

/// The "New" choices for a folder. Only kinds that will show where they were asked for are offered,
/// so a browser that lists boards alone doesn't offer a note that would then seem to vanish.
@ViewBuilder @MainActor
func newItemButtons(model: AppModel, folder: String, kinds: Set<VaultFileKind> = FolderListing.browsableKinds) -> some View {
    // A task goes in the folder's area (Personal/… adds to Personal), through quick add.
    Button { model.newTask(fromFolder: folder) } label: { Label("New task", systemImage: "checkmark.circle") }
    Divider()
    if kinds.contains(.note) { Button { _ = model.createNote(in: folder) } label: { Label("New note", systemImage: "doc.text") } }
    if kinds.contains(.board) { Button { _ = model.createNote(in: folder, kind: .board) } label: { Label("New board", systemImage: "rectangle.split.3x1") } }
    if kinds.contains(.whiteboard) { Button { _ = model.createNote(in: folder, kind: .whiteboard) } label: { Label("New whiteboard", systemImage: "scribble") } }
}

public struct SidebarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The notes tree, rebuilt only when the list of files changes, not on every change to the model.
    @State private var tree = FolderNode(name: "", path: "", folders: [], files: [])
    /// The folders open in the tree, by path.
    @State private var expanded: Set<String> = []
    @FocusState private var hasKeyboard: Bool
    /// Letters typed to jump to a row, and when the last one arrived.
    @State private var typed = ""
    @State private var typedAt = Date.distantPast
    /// The row the arrow keys are on in Tasks, where a view and an area are both selected at once.
    /// Nil means the current view's row.
    @State private var cursor: Route?
    @State private var editingAreas = false

    public init(model: AppModel) {
        self.model = model
        _expanded = State(initialValue: Set(SidebarKeys.ancestors(of: model.route)))
    }

    /// The route of the view Tasks is showing, for its row in the sidebar.
    private var viewRow: Route? {
        model.isShowingTasks ? SidebarPlaces.route(for: model.taskView) : nil
    }

    /// The row the keyboard is on.
    private var keyboardRow: Route? {
        model.section == .tasks ? (cursor ?? viewRow) : model.route
    }

    private func isSelected(_ route: Route) -> Bool {
        if model.section == .tasks, case let .area(name) = route { return (model.taskScope ?? "") == name }
        if model.section == .tasks { return viewRow == route }
        return model.route == route
    }

    public var body: some View {
        let section = model.section
        let places = section == .tasks ? SidebarPlaces.views(model) : []
        let areas = section == .tasks ? SidebarPlaces.areas(model) : []
        let entries = section == .notes ? tree.visibleEntries(expanded: expanded) : []
        let allNotes = SidebarPlaces.allNotes
        // Every row of this section in the order it shows, for the arrow keys and for typing a name.
        let order: [(route: Route, title: String)] = section == .tasks
            ? places.map { ($0.route, $0.title) } + areas.map { ($0.route, $0.title) }
            : [(allNotes.route, allNotes.title)] + entries.map { ($0.route, $0.title) }

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    SidebarRows(
                        model: model, section: section, entries: entries, isSelected: isSelected,
                        focused: hasKeyboard ? keyboardRow : nil,
                        select: select, toggle: toggle, editAreas: { editingAreas = true }
                    )
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .scrollContentBackground(.hidden)
            // The sidebar takes the keyboard like a list does: arrows move, Return and Space open.
            .focusable(true, interactions: .edit)
            .focused($hasKeyboard)
            .focusEffectDisabled()
            .onKeyPress(.upArrow) { step(-1, in: order, proxy: proxy) }
            .onKeyPress(.downArrow) { step(1, in: order, proxy: proxy) }
            .onKeyPress(.rightArrow) { openSelected(entries, order: order, proxy: proxy) }
            .onKeyPress(.leftArrow) { closeSelected(entries, proxy: proxy) }
            .onKeyPress(.return) { toggleSelected(entries) }
            .onKeyPress(.space) { toggleSelected(entries) }
            .onKeyPress(characters: .alphanumerics) { press in
                guard press.modifiers.isSubset(of: [.shift]) else { return .ignored }
                let now = Date()
                typed = now.timeIntervalSince(typedAt) < 1 ? typed + press.characters : press.characters
                typedAt = now
                guard let match = SidebarKeys.match(typed, in: order, after: keyboardRow) else { return .handled }
                go(to: match, proxy: proxy)
                return .handled
            }
            .onChange(of: model.route) { _, route in
                // A view chosen somewhere else (a shortcut, the main pane) takes the keyboard's place with it.
                if let cursor, case .area = cursor {} else { cursor = nil }
                // Opening something deeper, from a link or the main pane, opens its folders here and brings it into view.
                let needed = SidebarKeys.ancestors(of: route).filter { !expanded.contains($0) }
                if !needed.isEmpty { withMotion(Motion.smooth, reduceMotion: reduceMotion) { expanded.formUnion(needed) } }
                if let route { DispatchQueue.main.async { withMotion(Motion.smooth, reduceMotion: reduceMotion) { proxy.scrollTo(route) } } }
            }
            .onChange(of: model.section) { _, _ in cursor = nil }
            .onAppear {
                if let route = model.route, !SidebarKeys.ancestors(of: route).isEmpty {
                    DispatchQueue.main.async { proxy.scrollTo(route, anchor: .center) }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            // Tasks or Notes: the sidebar shows one section at a time.
            SectionSwitcher(model: model)
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 2)
                .background(theme.sidebar)
        }
        .onChange(of: model.files, initial: true) { _, files in tree = FolderNode.tree(from: files) }
        .background(theme.sidebar.ignoresSafeArea())
        .motion(Motion.smooth, value: model.offersReadyView)
        .motion(Motion.smooth, value: section)
        .motion(Motion.smooth, value: model.visibleAreas)
        .areaEditor(isPresented: $editingAreas, model: model)
        .searchable(text: $model.searchQuery, placement: .sidebar, prompt: "Search")
        .onChange(of: model.searchQuery) { _, query in
            if !jsTrim(query).isEmpty { model.route = .search }
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    newItemButtons(model: model, folder: model.section == .notes ? model.notesFolder : "")
                } label: { Image(systemName: "square.and.pencil") }
                .help("New note, board or whiteboard")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Rectangle().fill(theme.hairline).frame(height: 1)
                HStack(spacing: 2) {
                    SyncStatusView(model: model)
                    Menu {
                        Button("Activity") { model.route = .activity }
                        Button("Insights") { model.route = .insights }
                        Button("Import from Todoist") { model.route = .importer }
                        Divider()
                        Button("Edit Areas…") { editingAreas = true }
                        Button("Settings") { model.route = .settings }
                    } label: { Image(systemName: "ellipsis.circle").foregroundStyle(theme.textSecondary) }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .padding(.trailing, 12)
                    .help("Activity, Insights, Import, Areas and Settings")
                    .accessibilityLabel("More")
                }
            }
            .background(theme.sidebar)
        }
    }

    // MARK: Selecting and moving

    /// A click on a row: show it, and give the sidebar the keyboard so the arrow keys carry on from there.
    private func select(_ route: Route) {
        activate(route)
        hasKeyboard = true
    }

    /// Shows a row. In Tasks an area row sets the scope and leaves the view alone; every other row is a place.
    private func activate(_ route: Route) {
        if model.section == .tasks, case let .area(name) = route {
            model.setScope(name.isEmpty ? nil : name)
            cursor = route
        } else {
            model.route = route
            cursor = model.section == .tasks ? route : nil
        }
    }

    private func toggle(_ folder: String) {
        withMotion(Motion.smooth, reduceMotion: reduceMotion) {
            if expanded.contains(folder) { expanded.remove(folder) } else { expanded.insert(folder) }
        }
    }

    private func go(to route: Route, proxy: ScrollViewProxy) {
        guard route != keyboardRow else { return }
        activate(route)
        proxy.scrollTo(route)
    }

    private func step(_ offset: Int, in order: [(route: Route, title: String)], proxy: ScrollViewProxy) -> KeyPress.Result {
        if let next = SidebarKeys.step(from: keyboardRow, by: offset, in: order.map(\.route)) { go(to: next, proxy: proxy) }
        return .handled
    }

    private func selectedEntry(_ entries: [SidebarEntry]) -> SidebarEntry? {
        guard let route = model.route else { return nil }
        return entries.first { $0.route == route }
    }

    /// Return and Space open or close the selected folder. Other rows are already showing, being selected.
    private func toggleSelected(_ entries: [SidebarEntry]) -> KeyPress.Result {
        guard let path = selectedEntry(entries)?.folderPath else { return .ignored }
        toggle(path)
        return .handled
    }

    /// Right opens a closed folder, and steps into an open one.
    private func openSelected(_ entries: [SidebarEntry], order: [(route: Route, title: String)], proxy: ScrollViewProxy) -> KeyPress.Result {
        guard let entry = selectedEntry(entries), let path = entry.folderPath else { return .ignored }
        if expanded.contains(path) { return step(1, in: order, proxy: proxy) }
        toggle(path)
        return .handled
    }

    /// Left closes an open folder; on anything else it moves up to the folder it sits in.
    private func closeSelected(_ entries: [SidebarEntry], proxy: ScrollViewProxy) -> KeyPress.Result {
        guard let entry = selectedEntry(entries) else { return .ignored }
        if let path = entry.folderPath, expanded.contains(path) {
            toggle(path)
        } else if let parent = SidebarKeys.parent(of: entry.route) {
            go(to: parent, proxy: proxy)
        }
        return .handled
    }
}

struct SyncStatusView: View {
    @ObservedObject var model: AppModel
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            Group {
                switch model.syncPhase {
                case .off:
                    Image(systemName: "icloud.slash")
                    Text("Sync is off")
                case let .idle(date):
                    Image(systemName: "checkmark.icloud")
                    Text(date.map { "Synced \($0.formatted(date: .omitted, time: .shortened))" } ?? "Ready")
                case .syncing:
                    ProgressView().controlSize(.mini)
                    Text("Syncing…")
                case let .failed(message):
                    Image(systemName: "exclamationmark.icloud").foregroundStyle(theme.danger)
                    Text(message).lineLimit(2).help(message)
                }
            }
            .transition(.perchSwap(reduceMotion: reduceMotion))
            Spacer()
            Button { Task { await model.syncNow() } } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                .buttonStyle(.borderless)
                .disabled(model.syncEngine == nil)
                .help("Sync now")
                .accessibilityLabel("Sync now")
        }
        .font(.perchCaption)
        .foregroundStyle(theme.textSecondary)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .motion(Motion.smooth, value: model.syncPhase)
    }
}

/// When a file isn't something Perch shows.
struct UnsupportedFileView: View {
    @ObservedObject var model: AppModel
    let path: String

    var body: some View {
        let folder = (path as NSString).deletingLastPathComponent
        EmptyState(
            symbol: "doc.questionmark", title: "Perch doesn't open this kind of file",
            message: "“\((path as NSString).lastPathComponent)” isn't a note, board or whiteboard. It is safe in your notebook, and other apps can still open it.",
            actionTitle: "Show its folder", action: { model.route = .folder(folder) }
        )
        .perchScreenBackground()
    }
}

public struct DetailRouter: View {
    @ObservedObject var model: AppModel
    let settings: AnyView
    /// Tabs: the place to draw, for a workspace pane. Nil draws `model.route`, as without tabs.
    var explicit: Route?
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: AppModel, settings: AnyView, route: Route? = nil) {
        self.model = model
        self.settings = settings
        explicit = route
    }

    public var body: some View {
        let route = explicit ?? model.route ?? .today
        let pane = Self.pane(route)
        ZStack {
            // Each place fades and rises in over the one before it, so a switch reads as a move, not a cut.
            // A section is one place: its bars stay put while the view or folder under them changes.
            screen(route)
                .id(pane)
                .transition(.perchSwap(reduceMotion: reduceMotion))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
        .motion(Motion.smooth, value: pane)
    }

    /// What counts as one place in the main pane: all of Tasks, all of the folder browser, or a single screen.
    static func pane(_ route: Route) -> String {
        switch route {
        case .today, .upcoming, .ready, .list, .calendar, .board, .area: return "tasks"
        case .week: return "tasks-week"
        case .folder: return "notes"
        case let .file(path): return "file:" + path
        default: return String(describing: route)
        }
    }

    @ViewBuilder
    private func screen(_ route: Route) -> some View {
        switch route {
        case .today, .upcoming, .ready, .list, .calendar, .board, .area:
            TasksSectionView(model: model, view: explicit.flatMap { WorkspaceItem($0)?.taskView })
        // Week is the calendar's week mode now. The route stays for anything that still asks for it.
        case .week: TasksSectionView(model: model, calendarStartMode: "week", view: explicit == nil ? nil : .calendar)
        case let .folder(path): NotesSectionView(model: model, path: path)
        case let .file(path): fileView(path)
        case .search: SearchScreen(model: model)
        case .insights: InsightsScreen(model: model)
        case .activity: ActivityScreen(model: model)
        case .importer: ImportScreen(model: model)
        case .settings: settings
        }
    }

    @ViewBuilder
    private func fileView(_ path: String) -> some View {
        switch VaultFile.classify(path) {
        case .board: BoardView(model: model, path: path)
        case .whiteboard: WhiteboardScreen(model: model, path: path)
        case .note, .task: NoteView(model: model, path: path)
        default: UnsupportedFileView(model: model, path: path)
        }
    }
}

/// App-wide sheets and messages shared by the Mac and iPhone layouts.
public struct RootOverlays: ViewModifier {
    @ObservedObject var model: AppModel
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var renameText = ""

    public init(model: AppModel) { self.model = model }

    public func body(content: Content) -> some View {
        content
            .sheet(item: Binding(
                get: { model.needsNextDate },
                set: { model.needsNextDate = $0 }
            )) { NextDateSheet(model: model, task: $0) }
            .alert(
                "Delete this task?",
                isPresented: Binding(get: { model.pendingDelete != nil }, set: { if !$0 { model.pendingDelete = nil } })
            ) {
                Button("Delete", role: .destructive) {
                    if let task = model.pendingDelete { model.delete(task) }
                    model.pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { model.pendingDelete = nil }
            } message: {
                Text("Its file is removed. It stays recoverable in Git history once synced.")
            }
            .alert(
                "Delete \(model.pendingFileDelete.map { VaultFile(path: $0).title } ?? "this file")?",
                isPresented: Binding(get: { model.pendingFileDelete != nil }, set: { if !$0 { model.pendingFileDelete = nil } })
            ) {
                Button("Delete", role: .destructive) {
                    // The model moves the main pane off the file, to the folder it was in.
                    if let path = model.pendingFileDelete { model.deleteFile(path) }
                    model.pendingFileDelete = nil
                }
                Button("Cancel", role: .cancel) { model.pendingFileDelete = nil }
            } message: {
                Text("Its file is removed. It stays recoverable in Git history once synced.")
            }
            .onChange(of: model.pendingFileRename) { _, path in
                if let path { renameText = VaultFile(path: path).title }
            }
            .alert(
                "Rename \(model.pendingFileRename.map { VaultFile(path: $0).title } ?? "this file")",
                isPresented: Binding(get: { model.pendingFileRename != nil }, set: { if !$0 { model.pendingFileRename = nil } })
            ) {
                TextField("Title", text: $renameText)
                Button("Rename") {
                    if let path = model.pendingFileRename { model.rename(path, to: renameText) }
                    model.pendingFileRename = nil
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) { model.pendingFileRename = nil }
            } message: {
                Text("Links to it update automatically.")
            }
            .overlay(alignment: .bottom) {
                if let banner = model.banner {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle.fill").foregroundStyle(theme.info)
                        Text(banner).font(.perchBody).foregroundStyle(theme.text).fixedSize(horizontal: false, vertical: true)
                        Button { model.banner = nil } label: {
                            Image(systemName: "xmark").font(.perchCaption.weight(.bold)).foregroundStyle(theme.textSecondary)
                                .frame(width: Metrics.minTap, height: Metrics.minTap).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss")
                    }
                    .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
                    .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
                    .padding()
                    .transition(.perchBanner(from: .bottom, reduceMotion: reduceMotion))
                }
            }
            .motion(Motion.smooth, value: model.banner)
    }
}

// MARK: Pieces the iPhone app assembles into its own tabs.

public struct FileScreen: View {
    @ObservedObject var model: AppModel
    let path: String

    public init(model: AppModel, path: String) {
        self.model = model
        self.path = path
    }

    public var body: some View {
        switch VaultFile.classify(path) {
        case .board: BoardView(model: model, path: path).id(path)
        case .whiteboard: WhiteboardScreen(model: model, path: path).id(path)
        case .note, .task: NoteView(model: model, path: path).id(path)
        default: UnsupportedFileView(model: model, path: path)
        }
    }
}

public struct SearchHost: View {
    @ObservedObject var model: AppModel
    public init(model: AppModel) { self.model = model }
    public var body: some View { SearchScreen(model: model) }
}

public struct ImportHost: View {
    @ObservedObject var model: AppModel
    public init(model: AppModel) { self.model = model }
    public var body: some View { ImportScreen(model: model) }
}

public struct InsightsHost: View {
    @ObservedObject var model: AppModel
    public init(model: AppModel) { self.model = model }
    public var body: some View { InsightsScreen(model: model) }
}

/// Recent comments and changes on tasks, newest first, for the iPhone's Agents tab.
public struct ActivityRowsHost: View {
    @ObservedObject var model: AppModel
    @Environment(\.perchTheme) private var theme
    public init(model: AppModel) { self.model = model }

    public var body: some View {
        let items = model.tasks
            .flatMap { task in task.activity.map { (task: task, item: $0) } }
            .sorted { $0.item.date > $1.item.date }
            .prefix(40)
        if items.isEmpty {
            EmptyState(
                symbol: "bubble.left.and.text.bubble.right", title: "No activity yet",
                message: "When you or an agent comments on a task or proposes it as done, the note shows up here."
            )
            .frame(minHeight: 240)
        }
        ForEach(Array(items.enumerated()), id: \.offset) { _, entry in
            Button { model.selectedTaskID = entry.task.id } label: {
                ActivityLine(author: entry.item.author, me: model.author, date: relativeDay(entry.item.date, today: model.today), title: entry.task.title, text: entry.item.text)
            }
            .buttonStyle(PerchPressStyle())
        }
    }
}

/// One entry in an activity list: who, when, on what, and what they said.
struct ActivityLine: View {
    var author: String
    var me: String
    var date: String
    var title: String?
    var text: String
    @Environment(\.perchTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(name: author, me: me, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(author).font(.perchHeading).foregroundStyle(theme.text)
                    Text(date).font(.perchCaption).foregroundStyle(theme.textMuted)
                }
                if let title { Text(title).font(.perchBody).foregroundStyle(theme.text).lineLimit(1) }
                Text(TaskText.plain(text).split(whereSeparator: \.isNewline).joined(separator: " ")).font(.perchCaption).foregroundStyle(theme.textSecondary).lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, Metrics.rowPadding)
        .contentShape(Rectangle())
        .hoverHighlight()
    }
}
