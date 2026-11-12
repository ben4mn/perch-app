#if DEBUG
import PerchKit
import PerchUI
import SwiftUI
import WebKit

/// Debug-only checks. The app draws itself offscreen, writes PNGs and page reports, then quits.
/// `Perch -perchSnapshotDir <folder> -perchSnapshotVault <test notebook> -perchSnapshotScript <route;route>`
/// never touches the screen, never syncs, and never changes saved settings.
///
/// For pictures meant to be looked at rather than checked (the frames of `scripts/site-media.sh`):
/// `-perchSnapshotComposite` draws each note page and whiteboard into the window's PNG, where the web
/// view's own drawing never reaches; `-perchSnapshotFlatSidebar` draws the main window's sidebar as a
/// plain column, since the system's glass sidebar draws nothing off screen; and a `wait:<seconds>` step
/// sets how long the steps after it wait before their picture (3 seconds until then, 6 for a whiteboard).
@MainActor
enum SnapshotRunner {
    private static var window: NSWindow?
    private static var shell: MacShell?
    /// Set by a duo: step: the iPhone shell's state, and whether its content has two panes.
    private static var duoShell: ShellState?
    private static var duoSplits = false

    static func start(shell: MacShell) {
        self.shell = shell
        NSApp.setActivationPolicy(.prohibited)
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-perchSnapshotDir"), arguments.indices.contains(index + 1) else { exit(2) }
        let directory = URL(fileURLWithPath: arguments[index + 1])
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = arguments.firstIndex(of: "-perchSnapshotScript").map { arguments[$0 + 1] } ?? "today"

        // Start every run on System with no changes, whatever theme is saved, so snapshots are repeatable.
        // Set for this run only; a theme key passed as a launch argument (-themeID nord) still wins.
        var volatile = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        let plain = [ThemeStore.Keys.selected: "system", ThemeStore.Keys.appearance: "auto", ThemeStore.Keys.accent: "", ThemeStore.Keys.overrides: "{}", ThemeStore.Keys.imported: "[]"]
        for (key, value) in plain where volatile[key] == nil { volatile[key] = value }
        UserDefaults.standard.setVolatileDomain(volatile, forName: UserDefaults.argumentDomain)
        ThemeStore.shared.reload()
        // Light or dark is set on the app, not the window, so a theme can pin the window and hand it back.
        NSApp.appearance = NSAppearance(named: arguments.contains("-perchSnapshotLight") ? .aqua : .darkAqua)

        let hosting = NSHostingView(rootView: mainWindow(shell, width: 1240, height: 800))
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 1240, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        // Kept out of Mission Control and the window cycle: it sits far off screen while it draws.
        window.collectionBehavior = [.transient, .ignoresCycle]
        window.orderBack(nil)
        self.window = window

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            var stepWait: Double?
            for (index, step) in script.split(separator: ";").map(String.init).enumerated() {
                if step.hasPrefix("wait:") {
                    // wait:<seconds> for the steps after it; it draws nothing itself.
                    stepWait = Double(step.dropFirst(5)).map { max($0, 0.05) }
                    continue
                }
                if step.hasPrefix("relaystatus:") {
                    // relaystatus:off|connecting|connected|refused|unreachable|failed sets what Settings, Agents shows.
                    let statuses: [String: RelayStatus] = ["off": .off, "connecting": .connecting, "connected": .connected(agentsHere: 2),
                                                           "refused": .refused, "unreachable": .unreachable, "failed": .failed("HTTP 500")]
                    shell.model.debugShowRelayStatus(statuses[String(step.dropFirst(12))] ?? .off)
                } else if step == "standinproposals" {
                    // Proposals with every detail, for the Ready to tick view or a task's page (detail:ready).
                    NotchSnapshots.standInProposals(shell.model)
                } else if step.hasPrefix("detail:"), let task = step == "detail:ready" ? shell.model.readyToTick.first : shell.model.task(id: String(step.dropFirst(7))) {
                    window.contentView = NSHostingView(rootView: TaskDetailHost(model: shell.model, task: task).perchThemed(ThemeStore.shared).frame(width: 460, height: 860).background(Color(nsColor: .windowBackgroundColor)))
                    window.setContentSize(NSSize(width: 460, height: 860))
                } else if step.hasPrefix("notch"), let shot = NotchSnapshots.shot(step, services: shell.services) {
                    // The notch on a stand-in desktop, in any state or moment of its opening: notchclosed, notchpeek,
                    // notchframe:0.35, notchmode:week, notchlive:reminder, notchdrag:focus, notchcomplete:0.4.
                    // notchscreen:<width>[:nonotch][:dark] picks the desktop first. See NotchSnapshots for the full list.
                    window.contentView = NSHostingView(rootView: shot.view)
                    window.setContentSize(shot.size)
                } else if step == "sidebar" || step.hasPrefix("sidebar:") {
                    // sidebar draws the sidebar for the section in front; sidebar:tasks or sidebar:notes picks one.
                    // Steps after it (section:, scope:, a view or a folder) redraw the same sidebar.
                    if let section = AppSection(rawValue: String(step.dropFirst(8))) { shell.model.show(section) }
                    window.contentView = NSHostingView(rootView: NavigationStack { SidebarView(model: shell.model) }.perchThemed(ThemeStore.shared).frame(width: 320, height: 800).background(Color(nsColor: .windowBackgroundColor)))
                    window.setContentSize(NSSize(width: 320, height: 800))
                } else if step == "areaeditor" || step.hasPrefix("areaeditor:") {
                    // areaeditor[:<width>x<height>] draws the "Edit areas" sheet on its own.
                    let size = step.dropFirst(11).split(separator: "x").compactMap { Double($0) }.map { CGFloat($0) }
                    let width = size.first ?? 400, height = size.count > 1 ? size[1] : 560
                    window.contentView = NSHostingView(rootView: AreaEditor(model: shell.model).perchPresented()
                        .environment(\.horizontalSizeClass, width < 700 ? .compact : .regular)
                        .perchThemed(ThemeStore.shared).frame(width: width, height: height))
                    window.setContentSize(NSSize(width: width, height: height))
                } else if step.hasPrefix("duo:") {
                    // duo:<width>x<height>[:expanded|rail|drawer] draws the iPhone's wide-screen shell (sidebar or rail,
                    // panes) at that size, for checking a folding phone's inner screen: duo:951x669, duo:669x951:drawer.
                    // Steps that follow keep drawing in it. tab:agents and tab:search pick those destinations;
                    // file: opens a note in its pane; task:<id> shows a task in the detail pane.
                    let pieces = step.dropFirst(4).split(separator: ":").map(String.init)
                    let size = (pieces.first ?? "").split(separator: "x").compactMap { Double($0) }.map { CGFloat($0) }
                    let width = size.first ?? 951, height = size.count > 1 ? size[1] : 669
                    let state = ShellState(destination: ShellDestination(shell.model.section))
                    let mode = pieces.count > 1 ? pieces[1] : "expanded"
                    state.drawerOpen = mode == "drawer"
                    duoShell = state
                    // With set:experimentalTabs=true before it, the shell draws the workspace's tabs and panes.
                    let tabs = WorkspaceStore.isEnabled ? shell.workspace : nil
                    tabs?.attach(shell: state)
                    duoSplits = ShellLayout(width: Double(width), height: Double(height), preference: mode == "expanded" ? .expanded : .rail, scale: Double(PerchDisplay.current.scale)).splitsContent
                    shell.model.route = nil
                    window.contentView = NSHostingView(rootView: DuoSnapshotView(model: shell.model, shell: state, workspace: tabs, preference: mode == "expanded" ? .expanded : .rail, size: CGSize(width: width, height: height))
                        .modifier(RootOverlays(model: shell.model))
                        .environment(\.horizontalSizeClass, .compact)
                        .perchThemed(ThemeStore.shared)
                        .frame(width: width, height: height))
                    window.setContentSize(NSSize(width: width, height: height))
                } else if step.hasPrefix("tab:"), let state = duoShell, let destination = ShellDestination(rawValue: String(step.dropFirst(4))) {
                    state.show(destination, model: shell.model)
                } else if step.hasPrefix("size:") {
                    // size:<width>x<height> draws the main pane alone at that size, for checking narrow and short
                    // layouts such as a phone's: size:466x678, size:678x466. Widths under 700 get a compact size
                    // class, as a phone has, and wide ones may put sub-sections in a column, as the iPhone does.
                    // Route steps that follow keep drawing at this size.
                    let size = step.dropFirst(5).split(separator: "x").compactMap { Double($0) }.map { CGFloat($0) }
                    let width = size.first ?? 466, height = size.count > 1 ? size[1] : 678
                    let pane = DetailRouter(model: shell.model, settings: AnyView(EmptyView()))
                        .modifier(RootOverlays(model: shell.model))
                        .environment(\.horizontalSizeClass, width < 700 ? .compact : .regular)
                        .environment(\.perchSubsectionRail, true)
                        .perchThemed(ThemeStore.shared)
                        .frame(width: width, height: height)
                    window.contentView = NSHostingView(rootView: pane)
                    window.setContentSize(NSSize(width: width, height: height))
                } else if step.hasPrefix("format:") {
                    // format:bar|palette|highlightPalette|keyboard|keyboardStyle|keyboardColor[:<width>x<height>] draws
                    // the note editor's format controls on their own, with a made-up selection: the Mac's bar,
                    // its color popover, and the iPhone's keyboard bar and its two strips. format:keyboard:380x110
                    // is a closed folding phone, format:keyboard:669x110 an open one.
                    let pieces = step.dropFirst(7).split(separator: ":").map(String.init)
                    let piece = FormatGallery.Piece(rawValue: pieces.first ?? "") ?? .bar
                    let size = (pieces.count > 1 ? pieces[1] : "").split(separator: "x").compactMap { Double($0) }.map { CGFloat($0) }
                    let isPalette = piece == .palette || piece == .highlightPalette
                    let width = size.first ?? (isPalette ? 216 : (piece == .bar ? 900 : 380))
                    let height = size.count > 1 ? size[1] : (isPalette ? 250 : 110)
                    window.contentView = NSHostingView(rootView: FormatGallery(piece).perchThemed(ThemeStore.shared).frame(width: width, height: height))
                    window.setContentSize(NSSize(width: width, height: height))
                } else if step.hasPrefix("onboarding:") {
                    // onboarding:signin|code|choose|empty|cloning|failed draws the first-run screens with stand-in GitHub replies.
                    window.contentView = NSHostingView(rootView: OnboardingSnapshots.view(String(step.dropFirst(11)))
                        .perchThemed(ThemeStore.shared).frame(width: 1240, height: 800).background(Color(nsColor: .windowBackgroundColor)))
                    window.setContentSize(NSSize(width: 1240, height: 800))
                } else if step == "motion" {
                    // The completion check, its burst held part-way, and the "done for today" moment, since
                    // a still picture can't show them moving.
                    window.contentView = NSHostingView(rootView: MotionGallery().perchThemed(ThemeStore.shared).frame(width: 720, height: 560))
                    window.setContentSize(NSSize(width: 720, height: 560))
                } else if step == "themesettings" || step.hasPrefix("themesettings:") {
                    // themesettings:<width>x<height> checks other sizes, e.g. themesettings:340x1560 for an iPhone's width.
                    let size = step.dropFirst(14).split(separator: "x").compactMap { Double($0) }.map { CGFloat($0) }
                    let width = size.first ?? 980, height = size.count > 1 ? size[1] : 1560
                    window.contentView = NSHostingView(rootView: NavigationStack { ThemeSettingsView().toolbar(.hidden) }.perchThemed(ThemeStore.shared).frame(width: width, height: height))
                    window.setContentSize(NSSize(width: width, height: height))
                } else if step.hasPrefix("settingspane:") {
                    // settingspane:display|reading|editing[:<width>x<height>] draws one settings screen alone, as the
                    // iPhone pushes it: settingspane:reading:380x900 for a phone's width. Any other name
                    // (appearance, notebook, agents, notch, sync) draws that pane of the Mac's Settings.
                    let pieces = step.dropFirst(13).split(separator: ":").map(String.init)
                    let size = (pieces.count > 1 ? pieces[1] : "").split(separator: "x").compactMap { Double($0) }.map { CGFloat($0) }
                    let width = size.first ?? 560, height = size.count > 1 ? size[1] : 1100
                    let pane = SettingsPane(rawValue: pieces.first ?? "") ?? .display
                    window.contentView = NSHostingView(rootView: NavigationStack { MacSettingsPane(shell: shell, pane: pane).toolbar(.hidden) }
                        .environment(\.horizontalSizeClass, width < 700 ? .compact : .regular)
                        .perchThemed(ThemeStore.shared).frame(width: width, height: height))
                    window.setContentSize(NSSize(width: width, height: height))
                } else if step == "settingswindow" || step.hasPrefix("settingswindow:") {
                    // settingswindow[:<pane>] draws the Mac's Settings window as it opens: the groups on the left, one pane on the right.
                    SettingsRouter.shared.pane = SettingsPane(rawValue: String(step.dropFirst(15))) ?? .appearance
                    window.contentView = NSHostingView(rootView: MacSettingsView(shell: shell).perchThemed(ThemeStore.shared).frame(width: 740, height: 620))
                    window.setContentSize(NSSize(width: 740, height: 620))
                } else {
                    NotchSnapshots.settingChanged(by: step)
                    apply(step, model: shell.model)
                    // Inside the iPhone's shell a route is a request, taken and cleared, as on the iPhone.
                    if let state = duoShell, let route = shell.model.route {
                        if shell.workspace.isActive { shell.workspace.take(route) } else { state.take(route, model: shell.model, split: duoSplits) }
                    }
                }
                let wait = step.contains("whiteboard") ? max(stepWait ?? 6, 6) : stepWait ?? 3
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                let name = String(format: "%02d", index)
                if composites {
                    await saveCompositePNG(directory.appendingPathComponent("\(name).png"))
                } else {
                    savePNG(directory.appendingPathComponent("\(name).png"))
                }
                saveEditorReport(directory.appendingPathComponent("\(name)-editor.json"))
                await saveWebReport(directory: directory, name: name)
            }
            exit(0)
        }
    }

    private static func apply(_ step: String, model: AppModel) {
        let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
        // Steps that name something need it after the colon; a bare "area" or "file" is skipped.
        // "area:<name>" is the old per-area screen: it now scopes Tasks to that area and shows its List.
        if ["area", "file", "whiteboard", "task", "completing"].contains(parts[0]), parts.count < 2 { return }
        switch parts[0] {
        case "today": model.route = .today
        case "upcoming": model.route = .upcoming
        case "week": model.route = .week
        case "list": model.route = .list
        case "calendar":
            // calendar:month or calendar:week picks the mode first.
            // Set for this run only, so snapshots never change the app's saved settings.
            if parts.count > 1 {
                var volatile = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
                volatile["calendarMode"] = parts[1]
                UserDefaults.standard.setVolatileDomain(volatile, forName: UserDefaults.argumentDomain)
            }
            model.route = .calendar
        case "folderlayout", "foldersort", "folderdates":
            // folderlayout:grid|list, foldersort:name|modified|created|kind and folderdates:edited.week
            // (a date filter, see FolderListing.DateFilter), for this run only.
            // Follow with a folder: step; a folder already on screen picks it up when reopened.
            if parts.count > 1 {
                var volatile = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
                let key = ["folderlayout": "folderLayout", "foldersort": "folderSort", "folderdates": "folderDateFilter"][parts[0]]!
                volatile[key] = parts[1]
                UserDefaults.standard.setVolatileDomain(volatile, forName: UserDefaults.argumentDomain)
            }
        case "theme":
            // theme:<id> shows a theme (theme:system goes back). Set for this run only, like calendar above,
            // so snapshots never change the app's saved theme.
            var volatile = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            volatile[ThemeStore.Keys.selected] = parts.count > 1 ? parts[1] : "system"
            UserDefaults.standard.setVolatileDomain(volatile, forName: UserDefaults.argumentDomain)
            ThemeStore.shared.reload()
        case "themecolor":
            // themecolor:<key>=<hex> changes one colour of the theme set by theme:<id>, e.g. themecolor:textMuted=#4A4C60.
            // Also for this run only.
            let pair = (parts.count > 1 ? parts[1] : "").split(separator: "=").map(String.init)
            var volatile = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            if pair.count == 2, let id = volatile[ThemeStore.Keys.selected] as? String,
               let json = try? JSONEncoder().encode([id: [pair[0]: pair[1]]]) {
                volatile[ThemeStore.Keys.overrides] = String(data: json, encoding: .utf8)
                UserDefaults.standard.setVolatileDomain(volatile, forName: UserDefaults.argumentDomain)
                ThemeStore.shared.reload()
            }
        case "set":
            // set:key=value changes a view setting for this run only, e.g. set:calendarTray=overdue,
            // set:displayInterfaceSize=extraLarge, set:displayDensity=compact or set:editorHighlightLine=true.
            // true and false are stored as booleans, so on/off settings read them; everything else stays text.
            let pair = (parts.count > 1 ? parts[1] : "").split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { return }
            var volatile = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            if pair[1] == "true" || pair[1] == "false" { volatile[pair[0]] = pair[1] == "true" } else { volatile[pair[0]] = pair[1] }
            UserDefaults.standard.setVolatileDomain(volatile, forName: UserDefaults.argumentDomain)
            // Tabs: a setting changed this way reaches no view that is already on screen, so the main
            // window is drawn afresh and reads it. Put set:experimentalTabs=true before a duo: step.
            if pair[0] == WorkspaceStore.settingKey, duoShell == nil, let shell, let window {
                window.contentView = NSHostingView(rootView: mainWindow(shell, width: 1240, height: 800))
                window.setContentSize(NSSize(width: 1240, height: 800))
            }
        case "notemode":
            // notemode:read, notemode:edit or notemode:split, before the file: step it should apply to.
            // Set for this run only, like calendar: above.
            if parts.count > 1, let mode = NoteMode(rawValue: parts[1]) {
                var volatile = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
                volatile[ReadingSettings.Key.openIn] = mode == .read ? "read" : "edit"
                volatile[ReadingSettings.Key.editWithPreview] = mode == .split
                UserDefaults.standard.setVolatileDomain(volatile, forName: UserDefaults.argumentDomain)
            }
        case "reading":
            // reading:<key>=<value>, for example reading:readingFont=charter, reading:readingTextSize=3,
            // reading:readingParagraphSpacing=relaxed or reading:editorLineWidth=narrow. Numbers and true/false keep their type.
            if parts.count > 1, let equals = parts[1].firstIndex(of: "=") {
                let key = String(parts[1][..<equals]), value = String(parts[1][parts[1].index(after: equals)...])
                var volatile = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
                if let number = Int(value) { volatile[key] = number }
                else if let number = Double(value) { volatile[key] = number }
                else if value == "true" || value == "false" { volatile[key] = value == "true" }
                else { volatile[key] = value }
                UserDefaults.standard.setVolatileDomain(volatile, forName: UserDefaults.argumentDomain)
            }
        case "narrow":
            // narrow:<width>:<note path> draws one note alone at that width, as the iPhone cover screen would.
            let pieces = (parts.count > 1 ? parts[1] : "").split(separator: ":", maxSplits: 1).map(String.init)
            if pieces.count == 2, let width = Double(pieces[0]) {
                window?.contentView = NSHostingView(rootView: NavigationStack { FileScreen(model: model, path: pieces[1]) }
                    .perchThemed(ThemeStore.shared).frame(width: width, height: 800))
                window?.setContentSize(NSSize(width: width, height: 800))
            }
        case "section":
            // section:tasks or section:notes switches section, back where that section was left.
            if parts.count > 1, let section = AppSection(rawValue: parts[1]) { model.show(section) }
        case "scope":
            // scope:<area> scopes every task view to one area ("scope:work" finds "✈️ Work"); a bare scope: is All.
            model.setScope(named: parts.count > 1 ? parts[1] : "")
        case "view":
            // view:today|upcoming|list|calendar|ready changes the task view and keeps the scope.
            if parts.count > 1, let view = TaskViewKind(rawValue: parts[1]) { model.show(view: view) }
        case "areas":
            // areas:Consulting,Other adds areas by name for this run only, as "Edit areas" would. Nothing is saved or written.
            model.transientAreas = (parts.count > 1 ? parts[1] : "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        case "hideareas", "areaorder":
            // hideareas:Personal hides areas from the bars and areaorder:Studio,Home puts areas in that order,
            // for this run only, as Edit areas would. A snapshot run's model saves nothing about areas.
            let names = (parts.count > 1 ? parts[1] : "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts[0] == "hideareas" { model.areaPreferences.hidden = names } else { model.areaPreferences.order = names }
        case "noteskind":
            // noteskind:all|notes|boards|whiteboards filters the Notes section.
            if parts.count > 1, let kind = NotesKind(rawValue: parts[1]) { model.setNotesKind(kind) }
        case "folder": model.route = .folder(parts.count > 1 ? parts[1] : "")
        case "ready": model.route = .ready
        case "insights": model.route = .insights
        case "activity": model.route = .activity
        case "importer": model.route = .importer
        case "settings": model.route = .settings
        case "search":
            model.searchQuery = parts.count > 1 ? parts[1] : ""
            model.route = .search
        case "area": model.route = .area(parts[1])
        case "file", "whiteboard": model.route = .file(parts[1])
        case "task": model.selectedTaskID = parts[1]
        case "completing":
            // completing:<taskid> draws a task as just ticked, mid-completion. Nothing is written.
            if parts.count > 1 { model.debugShowCompleting(parts[1]) }
        case "closetask": model.selectedTaskID = nil
        case "webscroll":
            // webscroll:<0…1> scrolls the note on screen to that fraction of its length, to look further down it.
            if parts.count > 1, let fraction = Double(parts[1]) {
                for host in WebHost.debugHosts.allObjects where host.debugPage == "render" && host.webView.window != nil {
                    host.call("scrollTo", arguments: ["fraction": fraction])
                }
            }
        case "webunload", "webrestore":
            // webunload lets the note on screen's page go, as half a minute off screen would; webrestore
            // brings it back, as coming on screen again would. The note should look the same afterwards.
            for host in WebHost.debugHosts.allObjects where host.debugPage == "render" && host.webView.window != nil {
                if parts[0] == "webunload" { host.debugUnload() } else { host.debugRestore() }
            }
        case "tabs":
            // Builds a workspace without clicking, after set:experimentalTabs=true. An <item> is a place:
            // today, list, calendar, folder:<path>, file:<path>, search.
            //   tabs:open:<item>   a new tab            tabs:go:<item>       the tab in front goes there
            //   tabs:split:<item>  in the other pane    tabs:down            panes one above the other
            //   tabs:select:<n>    the pane's nth tab   tabs:focus:left|right
            //   tabs:fill:<n>      n notes as tabs      tabs:close           closes the tab in front
            //   tabs:unsplit       one pane again       tabs:fraction:<0.25-0.75>
            //   tabs:validate      checks tabs against the notebook's files, as a sync would
            //   tabs:save:<name>   saves the layout     tabs:show:<name>     brings a saved one back
            guard let store = shell?.workspace, parts.count > 1 else { return }
            let pieces = parts[1].split(separator: ":", maxSplits: 1).map(String.init)
            let argument = pieces.count > 1 ? pieces[1] : ""
            let item = WorkspaceItem(token: argument)
            switch pieces[0] {
            case "open": if let item { store.open(item, in: .newTab) }
            case "go": if let item { store.open(item) }
            case "split": if let item { store.open(item, in: .otherPane) } else { store.split(.horizontal) }
            case "down": store.split(.vertical)
            case "select":
                let tabs = store.workspace.focusedPane.tabs
                if let number = Int(argument), tabs.indices.contains(number - 1) { store.select(tabs[number - 1].id) }
            case "focus": store.focus(pane: ["right", "bottom", "1"].contains(argument) ? 1 : 0)
            case "fill":
                for file in model.files.filter({ $0.kind == .note }).prefix(Int(argument) ?? 0) { store.open(.file(file.path), in: .newTab) }
            case "close": store.closeFocusedTab()
            case "unsplit": store.closeSplit()
            case "fraction": store.setFraction(Double(argument) ?? 0.5)
            case "validate": store.debugValidate()
            case "window":
                // tabs:window:<width>x<height> draws the whole Mac window at that size, for a small one.
                let size = argument.split(separator: "x").compactMap { Double($0) }.map { CGFloat($0) }
                if size.count == 2, let shell, let window {
                    window.contentView = NSHostingView(rootView: mainWindow(shell, width: size[0], height: size[1]))
                    window.setContentSize(NSSize(width: size[0], height: size[1]))
                }
            case "save": store.saveWorkspace(as: argument)
            case "show": store.showWorkspace(argument)
            default: break
            }
        case "wbforce":
            // Exercises the real save path, on a test vault only.
            for host in WebHost.debugHosts.allObjects where host.debugPage == "whiteboard" { host.call("flush", arguments: ["force": true]) }
        default: break
        }
    }

    private static var composites: Bool { ProcessInfo.processInfo.arguments.contains("-perchSnapshotComposite") }

    /// The main window's content, as the app draws it, or with `-perchSnapshotFlatSidebar` its sidebar
    /// drawn as a plain column beside the same main pane.
    private static func mainWindow(_ shell: MacShell, width: CGFloat, height: CGFloat) -> AnyView {
        let flat = ProcessInfo.processInfo.arguments.contains("-perchSnapshotFlatSidebar")
        let root = flat ? AnyView(FlatSidebarWindow(shell: shell)) : AnyView(MacRootView(shell: shell))
        return AnyView(root.perchThemed(ThemeStore.shared).frame(width: width, height: height).background(Color(nsColor: .windowBackgroundColor)))
    }

    /// The window's picture with every web view on it drawn in, at the window's own scale. Each page is
    /// settled first (code coloured, formulas typeset, diagrams and pictures drawn), and only the part of
    /// it that shows is drawn.
    private static func saveCompositePNG(_ url: URL) async {
        guard let window, let view = window.contentView else { return }
        let hosts = WebHost.debugHosts.allObjects.filter { $0.webView.window === window && isShowing($0.webView, in: view) }
        for host in hosts where host.debugPage == "render" { await host.settle() }
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let base = bitmap.cgImage else { return }
        let scale = CGFloat(bitmap.pixelsWide) / max(view.bounds.width, 1)
        guard let context = CGContext(data: nil, width: bitmap.pixelsWide, height: bitmap.pixelsHigh, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.draw(base, in: CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        context.scaleBy(x: scale, y: scale)
        for host in hosts {
            // The whole page as the page reports take it, drawn where the web view is and cut to what shows.
            // It is taken again until two in a row agree, so a page still settling after a scroll is never
            // caught half-way.
            var picture: CGImage?
            var previous: Data?
            for _ in 0..<5 {
                guard let image = try? await host.webView.takeSnapshot(configuration: nil),
                      let taken = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { break }
                picture = taken
                let pixels = taken.dataProvider?.data as Data?
                if let pixels, pixels == previous { break }
                previous = pixels
                try? await Task.sleep(nanoseconds: 60_000_000)
            }
            guard let picture else { continue }
            // Window coordinates have their origin at the bottom left, as the context does.
            let frame = host.webView.convert(host.webView.bounds, to: nil)
            context.saveGState()
            context.clip(to: host.webView.convert(host.webView.visibleRect, to: nil))
            context.draw(picture, in: frame)
            context.restoreGState()
        }
        guard let image = context.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// A web view that really shows: not hidden or faded out anywhere up its chain (a note's reader sits
    /// under the editor at no opacity while editing), and on top at some point of it, so a page parked
    /// behind something else is never drawn over it.
    private static func isShowing(_ webView: WKWebView, in root: NSView) -> Bool {
        var current: NSView? = webView
        while let view = current {
            if view.isHidden || view.alphaValue < 0.01 || (view.layer?.opacity ?? 1) < 0.01 { return false }
            current = view.superview
        }
        let visible = webView.visibleRect
        guard visible.width > 1, visible.height > 1 else { return false }
        let samples = [(0.5, 0.5), (0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)].map {
            CGPoint(x: visible.minX + visible.width * $0.0, y: visible.minY + visible.height * $0.1)
        }
        return samples.contains { point in
            guard let hit = root.hitTest(webView.convert(point, to: nil)) else { return false }
            return hit === webView || hit.isDescendant(of: webView)
        }
    }

    /// Where the note editor on screen is scrolled, beside the page reports, to check the two stay level.
    private static func saveEditorReport(_ url: URL) {
        guard let root = window?.contentView, let report = EditorDebug.report(in: root) else { return }
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) { try? data.write(to: url) }
    }

    private static func savePNG(_ url: URL) {
        guard let view = window?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func saveWebReport(directory: URL, name: String) async {
        var index = 0
        for host in WebHost.debugHosts.allObjects where host.webView.window != nil {
            // The report and the picture show the finished page: code coloured, formulas typeset, diagrams drawn.
            if host.debugPage == "render" { await host.settle() }
            let script = """
            JSON.stringify({
              page: location.href,
              textLength: document.body.innerText.length,
              headings: document.querySelectorAll('h1,h2,h3').length,
              mermaid: [...document.querySelectorAll('.diagram[data-kind="mermaid"][data-state="done"]')].filter(d => d.shadowRoot?.querySelector('svg')).length,
              abc: document.querySelectorAll('.diagram[data-kind="abc"][data-state="done"] svg').length,
              math: document.querySelectorAll('.katex').length,
              mathErrors: document.querySelectorAll('.math[data-math="error"]').length,
              pending: document.querySelectorAll('.math[data-math="pending"], .diagram[data-state="pending"]').length,
              codeBlocks: document.querySelectorAll('.code-block').length,
              codeColoured: document.querySelectorAll('.code-block[data-highlighted]').length,
              codeTagged: document.querySelectorAll('.code-block[data-lang]').length,
              tables: document.querySelectorAll('#root table').length,
              tasks: document.querySelectorAll('li.task-list-item').length,
              overflowX: Math.max(0, document.documentElement.scrollWidth - document.documentElement.clientWidth),
              timing: window.Perch?.timing ?? null,
              errors: document.querySelectorAll('.render-error').length,
              errorText: [...document.querySelectorAll('.render-error')].map(e => e.textContent.slice(0, 180)),
              wikilinks: document.querySelectorAll('a.wikilink').length,
              missing: document.querySelectorAll('a.wikilink.missing').length,
              mentions: document.querySelectorAll('a.mention').length,
              callouts: document.querySelectorAll('.callout').length,
              images: document.images.length,
              brokenImages: [...document.images].filter(i => i.complete && i.naturalWidth === 0).length,
              excalidraw: document.querySelectorAll('.excalidraw canvas').length,
              scrollTop: Math.round(document.scrollingElement.scrollTop),
              padTop: getComputedStyle(document.getElementById('root') || document.body).paddingTop,
              sample: document.body.innerText.slice(0, 160)
            })
            """
            var report = (try? await host.webView.evaluateJavaScript(script)) as? String ?? "{\"error\":\"no report\"}"
            // How long the page took to load: from making the web view to its "ready".
            if report.hasPrefix("{"), let ready = host.readyAt {
                // And how long the note took to open: from its view taking the page to its text being on screen.
                let open = host.firstTextAt.map { Int($0.timeIntervalSince(host.takenAt) * 1000) } ?? -1
                // And how many reader pages are alive: the one showing, one kept ready, and none left over from
                // notes that have been closed.
                let readers = WebHost.debugHosts.allObjects.filter { $0.debugPage == "render" }.count
                report = "{\"pageLoadMs\":\(Int(ready.timeIntervalSince(host.createdAt) * 1000)),\"openToTextMs\":\(open),\"liveReaders\":\(readers)," + report.dropFirst()
            }
            let file = directory.appendingPathComponent("\(name)-web\(index).json")
            try? report.write(to: file, atomically: true, encoding: .utf8)
            if let image = try? await host.webView.takeSnapshot(configuration: nil),
               let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("\(name)-web\(index).png"))
            }
            index += 1
        }
    }
}

/// The main window with its sidebar as a plain column, for `-perchSnapshotFlatSidebar`: the same sidebar,
/// main pane and task panel as `MacRootView`, without the system's split view, whose glass sidebar draws
/// nothing in an off-screen window.
private struct FlatSidebarWindow: View {
    @ObservedObject var shell: MacShell
    @AppStorage(WorkspaceStore.settingKey) private var tabsOn = false
    @Environment(\.perchTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            NavigationStack { SidebarView(model: shell.model) }
                .frame(width: 250)
            Rectangle().fill(theme.border).frame(width: 1)
            TaskPanelColumn(model: shell.model) {
                if tabsOn {
                    WorkspaceDetail(store: shell.workspace, model: shell.model, settings: AnyView(MacSettingsView(shell: shell)))
                } else {
                    DetailRouter(model: shell.model, settings: AnyView(MacSettingsView(shell: shell)))
                }
            }
        }
        .background(theme.background)
        .modifier(RootOverlays(model: shell.model))
        .environment(\.perchWorkspace, tabsOn ? shell.workspace : nil)
    }
}

/// The iPhone's wide-screen shell, drawn on the Mac for a snapshot. The Agents screen is the iPhone
/// app's own, so the activity list stands in for it.
private struct DuoSnapshotView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var shell: ShellState
    var workspace: WorkspaceStore?
    @State var preference: SidebarPreference
    let size: CGSize
    @Environment(\.perchTheme) private var theme

    var body: some View {
        let layout = ShellLayout(width: Double(size.width), height: Double(size.height), preference: preference, scale: Double(theme.display.scale))
        let _ = (shell.layout = layout)
        WideShellView(
            model: model, shell: shell, layout: layout, preference: $preference,
            agents: AnyView(EmptyState(symbol: "person.2", title: "Agents", message: "The iPhone app draws its Agents screen here.")),
            workspace: workspace, openSettings: {}
        )
    }
}
#endif
