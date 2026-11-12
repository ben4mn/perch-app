import PerchKit
import SwiftUI

// The iPhone app on a wide screen: an unfolded folding phone, a phone on its side, an iPad window.
//
// A sidebar on the leading edge takes the place of the tab bar and of the chip bars above the content.
// It is the Mac's sidebar (the same rows, from `SidebarRows`) sized for a finger, and it folds down to
// a rail of icons. Beside it the content splits in two where there is room: a list and what is picked
// in it. Every decision about what goes where is `ShellLayout` and `ShellPresentation` in PerchKit;
// the place itself is `ShellState` and `AppModel`, shared with the tab bar layout, so changing between
// the two keeps it.

/// The wide layout. The app supplies what only it has: the Agents screen, its Settings, and anything
/// it wants in the Tasks toolbar.
public struct WideShellView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var shell: ShellState
    let layout: ShellLayout
    @Binding var preference: SidebarPreference
    let agents: AnyView
    let tasksAccessory: AnyView?
    let openSettings: () -> Void
    /// Tabs: the workspace, when "Tabs and split view" is on. Nil draws the content as before.
    var workspace: WorkspaceStore?
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var direction

    public init(
        model: AppModel, shell: ShellState, layout: ShellLayout, preference: Binding<SidebarPreference>,
        agents: AnyView, tasksAccessory: AnyView? = nil, workspace: WorkspaceStore? = nil, openSettings: @escaping () -> Void
    ) {
        self.workspace = workspace
        self.model = model
        self.shell = shell
        self.layout = layout
        _preference = preference
        self.agents = agents
        self.tasksAccessory = tasksAccessory
        self.openSettings = openSettings
    }

    /// The drawer only exists where the sidebar can't stay open beside the content.
    private var showsDrawer: Bool { shell.drawerOpen && !layout.canPinSidebar }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                navigation
                Rectangle().fill(theme.hairline).frame(width: 1).ignoresSafeArea()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(showsDrawer)
            }
            if showsDrawer {
                // Anywhere outside the drawer closes it.
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture { setSidebar(.rail) }
                    .accessibilityLabel("Close sidebar")
                    .accessibilityAddTraits(.isButton)
                    // Esc on a hardware keyboard closes the drawer too.
                    .background {
                        Button("Close sidebar") { setSidebar(.rail) }
                            .keyboardShortcut(.cancelAction)
                            .opacity(0)
                            .accessibilityHidden(true)
                    }
                    .transition(.opacity)
                sidebar
                    .frame(width: layout.sidebarWidth)
                    .frame(maxHeight: .infinity)
                    .background(theme.sidebar.ignoresSafeArea())
                    .overlay(alignment: .trailing) { Rectangle().fill(theme.border).frame(width: 1).ignoresSafeArea() }
                    .shadow(color: .black.opacity(0.22), radius: 18, x: 6)
                    .simultaneousGesture(swipe)
                    .transition(.perchSlide(from: .leading, reduceMotion: reduceMotion))
                    .zIndex(1)
            }
        }
        .background(theme.background.ignoresSafeArea())
        // The shell's sidebar is the column of sub-sections; the sections don't draw their own.
        .environment(\.perchSubsectionRail, false)
        .environment(\.perchWorkspace, workspace)
        .onChange(of: layout.canPinSidebar) { _, canPin in
            if canPin, shell.drawerOpen { shell.drawerOpen = false }
        }
    }

    // MARK: Navigation

    /// The rail or the pinned sidebar. One container whose width changes, so the content beside it
    /// slides over as the sidebar opens and closes.
    private var navigation: some View {
        let pinned = layout.navigation == .sidebar
        return ZStack(alignment: .topLeading) {
            if pinned {
                sidebar.frame(width: layout.sidebarWidth).transition(.opacity)
            } else {
                ShellRail(model: model, shell: shell, isExpanded: showsDrawer, toggle: toggleSidebar, openSettings: openSettings)
                    .frame(width: layout.railWidth)
                    .transition(.opacity)
            }
        }
        .frame(width: pinned ? layout.sidebarWidth : layout.railWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .clipped()
        .background(theme.sidebar.ignoresSafeArea())
        .simultaneousGesture(swipe)
    }

    private var sidebar: some View {
        ShellSidebar(
            // Tabs: a tab shows a folder or a note, not both, so picking a folder leaves the note.
            model: model, shell: shell, offersBoard: layout.offersBoard, splitsContent: workspace == nil && layout.splitsContent,
            collapse: toggleSidebar, openSettings: openSettings,
            dismissDrawer: { if showsDrawer { setSidebar(.rail) } }
        )
    }

    /// A swipe away from the leading edge opens the sidebar; a swipe toward it closes it.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                let flip: Double = direction == .rightToLeft ? -1 : 1
                guard let wanted = ShellLayout.swipe(
                    translation: value.translation.width * flip, predicted: value.predictedEndTranslation.width * flip,
                    vertical: value.translation.height
                ) else { return }
                setSidebar(wanted)
            }
    }

    private func toggleSidebar() {
        let isOpen = layout.canPinSidebar ? preference == .expanded : shell.drawerOpen
        setSidebar(isOpen ? .rail : .expanded)
    }

    /// Opens or closes the sidebar. Where it can stay open beside the content the choice is saved;
    /// where it is a drawer it is only for now.
    private func setSidebar(_ wanted: SidebarPreference) {
        withMotion(Motion.smooth, reduceMotion: reduceMotion) {
            if layout.canPinSidebar {
                if preference != wanted { preference = wanted }
            } else {
                shell.drawerOpen = wanted == .expanded
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let workspace {
            PhoneWorkspaceContent(store: workspace, model: model, shell: shell, layout: layout, agents: agents, tasksAccessory: tasksAccessory)
        } else {
            plainContent
        }
    }

    private var plainContent: some View {
        ZStack {
            Group {
                switch shell.destination {
                case .tasks: WideTasksView(model: model, shell: shell, layout: layout, accessory: tasksAccessory)
                case .notes: WideNotesView(model: model, shell: shell, layout: layout)
                case .agents: agents
                case .search: WideSearchView(model: model, shell: shell, layout: layout)
                }
            }
            .id(shell.destination)
            .transition(.perchSwap(reduceMotion: reduceMotion))
        }
        .motion(Motion.smooth, value: shell.destination)
    }
}

// MARK: - The rail

/// The sidebar folded down: the four destinations as icons with their names, and Settings.
private struct ShellRail: View {
    @ObservedObject var model: AppModel
    @ObservedObject var shell: ShellState
    var isExpanded: Bool
    var toggle: () -> Void
    var openSettings: () -> Void
    @Environment(\.perchTheme) private var theme

    var body: some View {
        VStack(spacing: 4) {
            SidebarToggle(isExpanded: isExpanded, action: toggle)
                .padding(.bottom, 6)
            ForEach(ShellDestination.allCases) { destination in
                RailButton(title: destination.title, symbol: destination.symbol, isSelected: shell.destination == destination) {
                    if destination == .search { shell.showSearch(model: model) } else { shell.show(destination, model: model) }
                }
            }
            Spacer(minLength: 0)
            RailSync(model: model)
            RailButton(title: "Settings", symbol: "gearshape", isSelected: false, action: openSettings)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Navigation")
    }
}

private struct RailButton: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    var action: () -> Void
    @State private var hovering = false
    @Environment(\.perchTheme) private var theme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.perchFixed(size: 19, weight: .medium))
                    .symbolVariant(isSelected ? .fill : .none)
                    .frame(height: Metrics.scaled(24))
                Text(title).font(.perchSmall).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: max(Metrics.scaled(52), 48))
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isSelected ? theme.accentSoft : (hovering ? theme.wash : Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PerchPressStyle())
        .onHover { hovering = $0 }
        #if os(iOS)
        .hoverEffect(.highlight)
        #endif
        .motion(Motion.quick, value: isSelected)
        .motion(Motion.quick, value: hovering)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Sync as a single icon, for the rail: its state, and a tap to sync now.
private struct RailSync: View {
    @ObservedObject var model: AppModel
    @Environment(\.perchTheme) private var theme

    var body: some View {
        Button { Task { await model.syncNow() } } label: {
            Group {
                switch model.syncPhase {
                case .off: Image(systemName: "icloud.slash")
                case .idle: Image(systemName: "checkmark.icloud")
                case .syncing: ProgressView().controlSize(.small)
                case .failed: Image(systemName: "exclamationmark.icloud").foregroundStyle(theme.danger)
                }
            }
            .font(.perchFixed(size: 16))
            .foregroundStyle(theme.textMuted)
            .frame(maxWidth: .infinity, minHeight: Metrics.minTap)
            .contentShape(Rectangle())
        }
        .buttonStyle(PerchPressStyle())
        .disabled(model.syncEngine == nil)
        .motion(Motion.smooth, value: model.syncPhase)
        .accessibilityLabel(spoken)
        .accessibilityHint(model.syncEngine == nil ? "" : "Syncs now")
    }

    private var spoken: String {
        switch model.syncPhase {
        case .off: return "Sync is off"
        case let .idle(date): return date.map { "Synced \($0.formatted(date: .omitted, time: .shortened))" } ?? "Ready to sync"
        case .syncing: return "Syncing"
        case let .failed(message): return "Sync failed: \(message)"
        }
    }
}

/// The button that opens the sidebar from the rail and folds it back.
private struct SidebarToggle: View {
    var isExpanded: Bool
    var action: () -> Void
    @Environment(\.perchTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.leading")
                .font(.perchFixed(size: 17, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .frame(width: Metrics.minTap, height: Metrics.minTap)
                .contentShape(Rectangle())
        }
        .buttonStyle(PerchPressStyle())
        #if os(iOS)
        .hoverEffect(.highlight)
        #endif
        .help(isExpanded ? "Hide the sidebar" : "Show the sidebar")
        .accessibilityLabel(isExpanded ? "Hide sidebar" : "Show sidebar")
    }
}

// MARK: - The sidebar

/// The whole sidebar: Tasks | Notes at the top; the views and areas, or the folder tree; then Agents
/// and Search; then sync and Settings.
private struct ShellSidebar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var shell: ShellState
    var offersBoard: Bool
    var splitsContent: Bool
    var collapse: () -> Void
    var openSettings: () -> Void
    /// Called after picking somewhere to go, so a drawer gets out of the way.
    var dismissDrawer: () -> Void
    @State private var tree = FolderNode(name: "", path: "", folders: [], files: [])
    @State private var expanded: Set<String> = []
    @State private var editingAreas = false
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct TreeKey: Equatable {
        var files: [VaultFile]
        var kind: NotesKind
    }

    var body: some View {
        let section = model.section
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                SectionSwitcher(model: model, selection: .some(shell.destination.section)) { section in
                    shell.show(ShellDestination(section), model: model)
                }
                SidebarToggle(isExpanded: true, action: collapse)
            }
            .padding(.leading, 10)
            .padding(.trailing, 2)
            .padding(.top, 6)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        if section == .notes { kindRow }
                        SidebarRows(
                            model: model, section: section,
                            entries: section == .notes ? tree.visibleEntries(expanded: expanded) : [],
                            offersBoard: offersBoard, isSelected: isSelected, focused: nil,
                            select: select, toggle: toggle, editAreas: { editingAreas = true }
                        )
                    }
                    .padding(8)
                }
                .scrollContentBackground(.hidden)
                .onChange(of: shell.notesPath) { _, path in reveal(path.last, proxy) }
                .onChange(of: model.notesFolder) { _, folder in reveal(.folder(folder), proxy) }
            }
            Rectangle().fill(theme.hairline).frame(height: 1)
            VStack(spacing: 1) {
                SidebarRow(
                    title: ShellDestination.agents.title, symbol: ShellDestination.agents.symbol,
                    count: model.agents.filter(\.isActive).count, isSelected: shell.destination == .agents, inset: 6
                ) {
                    shell.show(.agents, model: model)
                    dismissDrawer()
                }
                SidebarRow(title: ShellDestination.search.title, symbol: ShellDestination.search.symbol, isSelected: shell.destination == .search, inset: 6) {
                    shell.showSearch(model: model)
                    dismissDrawer()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            Rectangle().fill(theme.hairline).frame(height: 1)
            HStack(spacing: 0) {
                SyncStatusView(model: model)
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.perchFixed(size: 16, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: Metrics.minTap, height: Metrics.minTap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PerchPressStyle())
                #if os(iOS)
                .hoverEffect(.highlight)
                #endif
                .help("Settings")
                .accessibilityLabel("Settings")
            }
            .padding(.trailing, 4)
        }
        .onChange(of: TreeKey(files: model.files, kind: model.notesKind), initial: true) { _, key in
            tree = FolderNode.tree(from: key.files, kinds: key.kind.kinds)
        }
        .onAppear { expanded.formUnion(needed(for: shell.notesPath.last) + needed(for: .folder(model.notesFolder))) }
        .motion(Motion.smooth, value: section)
        .motion(Motion.smooth, value: model.offersReadyView)
        .motion(Motion.smooth, value: model.visibleAreas)
        .areaEditor(isPresented: $editingAreas, model: model)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sidebar")
    }

    /// Which kinds of file the tree and the browser list: everything, or notes, boards or whiteboards alone.
    private var kindRow: some View {
        Menu {
            Picker("Show", selection: Binding(get: { model.notesKind }, set: { model.setNotesKind($0) })) {
                ForEach(NotesKind.allCases) { kind in Label(kind.title, systemImage: kind.symbol).tag(kind) }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "line.3.horizontal.decrease").font(.perchFixed(size: 14, weight: .medium)).frame(width: 22)
                Text("Show").font(.perchBody)
                Spacer(minLength: 4)
                Text(model.notesKind.title).font(.perchCaption.weight(.medium))
                Image(systemName: "chevron.up.chevron.down").font(.perchFixed(size: 9, weight: .bold))
            }
            .foregroundStyle(model.notesKind == .all ? theme.textSecondary : theme.accent)
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .frame(minHeight: SidebarRow.rowHeight)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Show: \(model.notesKind.title)")
        .accessibilityHint("Chooses which kinds of file are listed")
    }

    /// In Tasks one view and one area are marked at once; in Notes the folder being browsed and the note open.
    private func isSelected(_ route: Route) -> Bool {
        switch route {
        case let .area(name): return (model.taskScope ?? "") == name
        case let .folder(path): return shell.destination == .notes && model.notesFolder == path && (splitsContent || shell.notesPath.isEmpty)
        case .file: return shell.destination == .notes && shell.notesPath.last == route
        default: return shell.destination == .tasks && route == SidebarPlaces.route(for: model.taskView.effective(wide: offersBoard))
        }
    }

    private func select(_ route: Route) {
        switch route {
        case let .area(name):
            // An area is a scope: it changes what every view shows and leaves the sidebar open for a view.
            model.setScope(name.isEmpty ? nil : name)
            shell.show(.tasks, model: model)
        case let .folder(path):
            withMotion(Motion.smooth, reduceMotion: reduceMotion) {
                shell.showFolder(path, model: model, split: splitsContent)
                if !path.isEmpty { expanded.insert(path) }
            }
        case let .file(path):
            shell.openNote(path, fromLink: false, model: model)
            dismissDrawer()
        default:
            model.route = route
            dismissDrawer()
        }
    }

    private func toggle(_ folder: String) {
        withMotion(Motion.smooth, reduceMotion: reduceMotion) {
            if expanded.contains(folder) { expanded.remove(folder) } else { expanded.insert(folder) }
        }
    }

    private func needed(for route: Route?) -> [String] {
        var folders = SidebarKeys.ancestors(of: route)
        if case let .folder(path)? = route, !path.isEmpty { folders.append(path) }
        return folders
    }

    /// Opens the folders above whatever was just opened elsewhere, and scrolls it into view.
    private func reveal(_ route: Route?, _ proxy: ScrollViewProxy) {
        guard let route else { return }
        let missing = SidebarKeys.ancestors(of: route).filter { !expanded.contains($0) }
        if !missing.isEmpty { withMotion(Motion.smooth, reduceMotion: reduceMotion) { expanded.formUnion(missing) } }
        DispatchQueue.main.async { withMotion(Motion.smooth, reduceMotion: reduceMotion) { proxy.scrollTo(route) } }
    }
}

// MARK: - Panes

/// The line between two panes. Drag it to give one side more room.
private struct PaneDivider: View {
    /// The trailing pane's width now, and the content's.
    let width: Double
    let content: Double
    @Binding var fraction: Double
    /// Set while dragging; the pane follows it without the saved fraction changing on every point.
    @Binding var dragWidth: Double?
    @State private var hovering = false
    @Environment(\.perchTheme) private var theme
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        Rectangle().fill(theme.hairline).frame(width: 1)
            .overlay {
                Capsule().fill(dragWidth != nil || hovering ? theme.accent : theme.textMuted.opacity(0.45))
                    .frame(width: 4, height: 34)
            }
            .overlay {
                // A finger-wide handle around a hair-thin line.
                Color.clear.frame(width: 22).contentShape(Rectangle())
                    .onHover { hovering = $0 }
                    .gesture(
                        DragGesture(minimumDistance: 2, coordinateSpace: .global)
                            .onChanged { value in
                                // Dragging toward the leading edge widens the trailing pane.
                                let moved = value.translation.width * (direction == .rightToLeft ? 1 : -1)
                                let start = dragStart ?? width
                                dragStart = start
                                dragWidth = PaneLayout.trailingWidth(content: content, fraction: PaneLayout.fraction(trailingWidth: start + moved, content: content))
                            }
                            .onEnded { _ in
                                if let dragWidth { fraction = PaneLayout.fraction(trailingWidth: dragWidth, content: content) }
                                dragWidth = nil
                                dragStart = nil
                            }
                    )
            }
            .motion(Motion.quick, value: hovering)
            .ignoresSafeArea(edges: .vertical)
            .zIndex(2)
            .accessibilityElement()
            .accessibilityLabel("Pane divider")
            .accessibilityValue("\(Int((width / max(content, 1)) * 100)) percent for the detail")
            .accessibilityAdjustableAction { change in
                let step = change == .increment ? 0.04 : -0.04
                fraction = PaneLayout.fraction(trailingWidth: (fraction + step) * content, content: content)
            }
    }

    @State private var dragStart: Double?
}

/// The key the pane's share of the width is saved under.
enum PaneStorage {
    static let detailFraction = "shellDetailFraction"
    static let notesBrowserHidden = "shellNotesBrowserHidden"
}

// MARK: - Tasks

/// Tasks on a wide screen: the view on the left; on the right the selected task, or beside Today what
/// is coming next. The calendar and the board keep the whole width until a task is picked.
struct WideTasksView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var shell: ShellState
    let layout: ShellLayout
    var accessory: AnyView?
    /// Tabs: the view a workspace pane shows, and whether this pane is the one that shows the
    /// selected task. Left alone, both are as without tabs.
    var view: TaskViewKind?
    var showsDetail = true
    @AppStorage(PaneStorage.detailFraction) private var fraction = PaneLayout.defaultFraction
    @State private var dragWidth: Double?
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var place: ShellPlace {
        var place = shell.place(model: model)
        if let view { place.taskView = view }
        if !showsDetail { place.selectedTask = nil }
        return place
    }

    var body: some View {
        let presentation = ShellPresentation(place: place, layout: layout)
        let trailing = presentation.tasksTrailing
        let width = dragWidth ?? PaneLayout.trailingWidth(content: layout.contentWidth, fraction: fraction)
        HStack(spacing: 0) {
            NavigationStack {
                TasksSectionView(model: model, showsBars: layout.showsContentBars, offersBoard: layout.offersBoard, view: view)
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        if let accessory { ToolbarItem(placement: .topBarTrailing) { accessory } }
                    }
                    #endif
            }
            .frame(maxWidth: .infinity)
            if trailing != .none {
                PaneDivider(width: width, content: layout.contentWidth, fraction: $fraction, dragWidth: $dragWidth)
                pane(trailing)
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .background(theme.background)
                    .transition(.perchSlide(from: .trailing, reduceMotion: reduceMotion))
            }
        }
        .motion(Motion.smooth, value: trailing != .none)
        .perchScreenBackground()
    }

    private func pane(_ trailing: ShellPresentation.TasksTrailing) -> some View {
        ZStack {
            Group {
                if trailing == .detail, let task = model.task(id: model.selectedTaskID) {
                    TaskDetailHost(model: model, task: task).id(task.id)
                } else if trailing == .dashboard {
                    TodayCompanion(model: model).id("dashboard")
                } else {
                    EmptyState(
                        symbol: "checklist", title: "No task selected",
                        message: "Choose a task to see its details, subtasks and activity here."
                    )
                    .id("placeholder")
                }
            }
            .transition(.perchSwap(reduceMotion: reduceMotion))
        }
        .motion(Motion.smooth, value: model.selectedTaskID)
        .motion(Motion.smooth, value: trailing)
    }
}

// MARK: - Notes

/// The notes browser with files pushed over it: the Notes tab of a phone-sized screen, and of a wide
/// one that has no room for a second pane.
public struct NotesStackView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var shell: ShellState
    var showsBars: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: AppModel, shell: ShellState, showsBars: Bool = true) {
        self.model = model
        self.shell = shell
        self.showsBars = showsBars
    }

    public var body: some View {
        NavigationStack(path: $shell.notesPath) {
            NotesSectionView(model: model, path: model.notesFolder, showsBars: showsBars, open: open)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .navigationDestination(for: Route.self) { destination in
                    if case let .file(file) = destination { FileScreen(model: model, path: file) }
                }
        }
    }

    /// Choosing a folder changes what the browser shows; a file is pushed on top, so Back returns to
    /// the folder it was opened from.
    private func open(_ destination: Route) {
        switch destination {
        case let .folder(folder): withMotion(Motion.smooth, reduceMotion: reduceMotion) { model.setNotesFolder(folder) }
        case let .file(file): shell.openNote(file, fromLink: false, model: model)
        default: break
        }
    }
}

/// Notes on a wide screen: the folder browser and the open note side by side. The browser folds away
/// so the note can have the whole width, which is also when editing gets its preview beside it.
struct WideNotesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var shell: ShellState
    let layout: ShellLayout
    @AppStorage(PaneStorage.notesBrowserHidden) private var browserHidden = false
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if layout.splitsContent {
            split
        } else {
            NotesStackView(model: model, shell: shell, showsBars: layout.showsContentBars)
        }
    }

    private var split: some View {
        let note = shell.openNote
        let showsBrowser = note == nil || !browserHidden
        return HStack(spacing: 0) {
            if showsBrowser {
                NavigationStack {
                    NotesSectionView(model: model, path: model.notesFolder, showsBars: layout.showsContentBars, open: open)
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                }
                .environment(\.perchSelectedPath, note)
                .frame(width: PaneLayout.listWidth(content: layout.contentWidth, scale: Double(theme.display.scale)))
                .transition(.perchSlide(from: .leading, reduceMotion: reduceMotion))
                Rectangle().fill(theme.hairline).frame(width: 1).ignoresSafeArea()
            }
            ZStack {
                if let note {
                    NavigationStack {
                        FileScreen(model: model, path: note)
                            .toolbar { ToolbarItemGroup(placement: .navigation) { noteButtons } }
                    }
                    .id(note)
                    .transition(.perchSwap(reduceMotion: reduceMotion))
                } else {
                    EmptyState(
                        symbol: "doc.text", title: "No note open",
                        message: "Choose a note, board or whiteboard from the list to read it here."
                    )
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .motion(Motion.smooth, value: note)
        }
        .motion(Motion.smooth, value: showsBrowser)
        .perchScreenBackground()
    }

    /// Beside the note's own buttons: fold the browser away, and close the note (or go back to the
    /// note a link was followed from).
    @ViewBuilder
    private var noteButtons: some View {
        Button {
            withMotion(Motion.smooth, reduceMotion: reduceMotion) { browserHidden.toggle() }
        } label: { Image(systemName: browserHidden ? "sidebar.squares.leading" : "arrow.up.left.and.arrow.down.right") }
            .help(browserHidden ? "Show the folder list" : "Read at full width")
            .accessibilityLabel(browserHidden ? "Show folder list" : "Hide folder list")
        let goesBack = shell.notesPath.count > 1
        Button {
            withMotion(Motion.smooth, reduceMotion: reduceMotion) { _ = shell.notesPath.popLast() }
        } label: { Image(systemName: goesBack ? "chevron.backward" : "xmark") }
            .help(goesBack ? "Back to the previous note" : "Close this note")
            .accessibilityLabel(goesBack ? "Back to previous note" : "Close note")
    }

    private func open(_ destination: Route) {
        withMotion(Motion.smooth, reduceMotion: reduceMotion) {
            switch destination {
            case let .folder(folder): model.setNotesFolder(folder)
            case let .file(file): shell.openNote(file, fromLink: false, model: model)
            default: break
            }
        }
    }
}

// MARK: - Search

/// The destination a file or folder opened from Search or Agents is drawn with.
struct PlaceScreen: View {
    @ObservedObject var model: AppModel
    let route: Route
    var open: (Route) -> Void

    var body: some View {
        switch route {
        case let .file(file): FileScreen(model: model, path: file)
        case let .folder(folder): FolderHost(model: model, path: folder, open: open)
        default: EmptyView()
        }
    }
}

/// Search with results pushed over the list: a phone-sized screen, and a wide one with a single pane.
public struct SearchStackView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var shell: ShellState
    @State private var searching = false

    public init(model: AppModel, shell: ShellState) {
        self.model = model
        self.shell = shell
    }

    public var body: some View {
        NavigationStack(path: $shell.searchPath) {
            SearchScreen(model: model)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $model.searchQuery, isPresented: $searching, placement: .navigationBarDrawer(displayMode: .always), prompt: "Notes, tasks, boards")
                #else
                .searchable(text: $model.searchQuery, isPresented: $searching, prompt: "Notes, tasks, boards")
                #endif
                .navigationDestination(for: Route.self) { destination in
                    PlaceScreen(model: model, route: destination) { shell.searchPath.append($0) }
                }
        }
        // Asked for by ⌥⌘F: the keyboard goes to the field.
        .task(id: shell.searchRequests) { if shell.takeSearchFocus() { searching = true } }
    }
}

/// Search on a wide screen: the field and the results on the left, the picked result on the right.
struct WideSearchView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var shell: ShellState
    let layout: ShellLayout
    @FocusState private var fieldFocused: Bool
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if layout.splitsContent {
            split
        } else {
            SearchStackView(model: model, shell: shell)
        }
    }

    private var split: some View {
        let presentation = ShellPresentation(place: shell.place(model: model), layout: layout)
        let task = presentation.searchShowsTask ? model.task(id: model.selectedTaskID) : nil
        let shown = task == nil ? shell.searchPath.last : nil
        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                FilterField(text: $model.searchQuery, prompt: "Notes, tasks, boards")
                    .focused($fieldFocused)
                    .padding(.horizontal, Metrics.screenPadding)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
                    .accessibilityLabel("Search")
                SearchScreen(model: model)
            }
            .environment(\.perchSelectedPath, task?.path ?? Self.path(shown))
            .frame(width: PaneLayout.listWidth(content: layout.contentWidth, scale: Double(theme.display.scale)))
            Rectangle().fill(theme.hairline).frame(width: 1).ignoresSafeArea()
            ZStack {
                Group {
                    if let task {
                        TaskDetailHost(model: model, task: task).id("task:" + task.id)
                    } else if let shown {
                        NavigationStack {
                            PlaceScreen(model: model, route: shown) { shell.searchPath.append($0) }
                                .toolbar {
                                    ToolbarItem(placement: .navigation) {
                                        Button {
                                            withMotion(Motion.smooth, reduceMotion: reduceMotion) { _ = shell.searchPath.popLast() }
                                        } label: { Image(systemName: shell.searchPath.count > 1 ? "chevron.backward" : "xmark") }
                                            .accessibilityLabel(shell.searchPath.count > 1 ? "Back" : "Close preview")
                                    }
                                }
                        }
                        .id(shown)
                    } else {
                        EmptyState(
                            symbol: "doc.text.magnifyingglass", title: "Nothing picked",
                            message: "Choose a result to read it here without losing your place in the list."
                        )
                        .id("placeholder")
                    }
                }
                .transition(.perchSwap(reduceMotion: reduceMotion))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .motion(Motion.smooth, value: shown)
            .motion(Motion.smooth, value: task?.id)
        }
        .perchScreenBackground()
        // Asked for by ⌥⌘F or picked in the sidebar: the field takes the keyboard. Not on a plain redraw.
        .task(id: shell.searchRequests) { if shell.takeSearchFocus() { fieldFocused = true } }
    }

    private static func path(_ route: Route?) -> String? {
        if case let .file(path)? = route { return path }
        return nil
    }
}
