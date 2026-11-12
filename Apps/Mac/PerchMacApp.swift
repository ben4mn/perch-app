import PerchKit
import PerchUI
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    #if DEBUG
    /// A snapshot run draws offscreen and must never show in the Dock or the app switcher, so it gives
    /// up being a regular app before launch finishes, not a moment after.
    func applicationWillFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.arguments.contains("-perchSnapshotDir") { NSApp.setActivationPolicy(.prohibited) }
    }
    #endif

    /// The notch keeps working after the main window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// A task ticked in the last half second is written before the app goes.
    var flush: () -> Void = {}
    func applicationWillTerminate(_ notification: Notification) { flush() }

    /// Clicking the Dock icon brings the main window back, or opens one when it has been closed. Perch does
    /// this itself every time: AppKit counts the notch as a visible window, and when AppKit acts as well,
    /// SwiftUI opens a second window beside Perch's.
    var reopen: () -> Void = {}
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        reopen()
        return MainWindowReopen.letsAppKitHandleReopen(hasVisibleWindows: hasVisibleWindows)
    }
}

@main
struct PerchMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var shell = MacShell()
    /// Tabs: "Tabs and split view (experimental)". Off, the Tabs menu isn't there at all.
    @AppStorage(WorkspaceStore.settingKey) private var tabsOn = false

    var body: some Scene {
        WindowGroup("Perch", id: "main") {
            // Snapshots draw offscreen, and the stress test makes its own window: see NavStress.
            if !ProcessInfo.processInfo.arguments.contains("-perchSnapshotDir"), !ProcessInfo.processInfo.arguments.contains("-perchNavStress") {
                MacRootView(shell: shell)
                    .perchThemed(ThemeStore.shared)
                    .frame(minWidth: 860, minHeight: 540)
                    .background(WindowOpenerCapture(shell: shell))
                    .onAppear {
                        delegate.reopen = { shell.services.openMainWindow() }
                        delegate.flush = {
                            shell.model.flushCompletions()
                            shell.updates.installOnQuit()
                        }
                    }
            }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            // File, Close: an open task panel closes first, so a reflex Cmd+W doesn't close the window.
            CommandGroup(replacing: .saveItem) {
                Button("Close") { shell.closeFrontmost() }.keyboardShortcut("w")
            }
            CommandGroup(after: .appInfo) {
                // Only a build with an update source can look for updates.
                if FirstRun.showsUpdateChecks(shell.configuration) {
                    Button("Check for Updates…") {
                        SettingsRouter.shared.pane = .updates
                        shell.model.route = .settings
                        shell.services.openMainWindow()
                        Task { await shell.updates.check(announce: false) }
                    }
                }
            }
            CommandGroup(replacing: .newItem) {
                // In Notes the new note goes in the folder being browsed, like the sidebar's own New button.
                Button("New Note") { _ = shell.model.createNote(in: shell.model.section == .notes ? shell.model.notesFolder : "") }.keyboardShortcut("n")
                Button("New Task") {
                    shell.services.openMainWindow()
                    shell.model.newTask(fromFolder: shell.model.section == .notes ? shell.model.notesFolder : "")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Open Notebook…") { shell.chooseVault() }.keyboardShortcut("o")
            }
            CommandMenu("Go") {
                // ⌘1 and ⌘2 are the two sections; each comes back where it was left.
                Button("Tasks") { shell.model.show(.tasks) }.keyboardShortcut("1")
                Button("Notes") { shell.model.show(.notes) }.keyboardShortcut("2")
                Divider()
                // The task views keep their numbers, with Option. Not Control: ⌃1 to ⌃4 switch desktops in macOS.
                Button("Today") { shell.model.show(view: .today) }.keyboardShortcut("1", modifiers: [.command, .option])
                Button("Upcoming") { shell.model.show(view: .upcoming) }.keyboardShortcut("2", modifiers: [.command, .option])
                Button("List") { shell.model.show(view: .list) }.keyboardShortcut("3", modifiers: [.command, .option])
                Button("Calendar") { shell.model.show(view: .calendar) }.keyboardShortcut("4", modifiers: [.command, .option])
                Button("Ready to Tick") { shell.model.show(view: .ready) }.keyboardShortcut("5", modifiers: [.command, .option])
                Button("Board") { shell.model.show(view: .board) }.keyboardShortcut("6", modifiers: [.command, .option])
                Divider()
                // Steps through All and each area, in the order of the bar.
                Button("Next Area") { stepScope(1) }.keyboardShortcut("]", modifiers: [.command, .option])
                Button("Previous Area") { stepScope(-1) }.keyboardShortcut("[", modifiers: [.command, .option])
                Divider()
                Button("Search") { shell.model.route = .search }.keyboardShortcut("f", modifiers: [.command, .option])
                Divider()
                Button("Sync Now") { Task { await shell.model.syncNow() } }.keyboardShortcut("s", modifiers: [.command, .shift])
            }
            if tabsOn { WorkspaceCommands(store: shell.workspace) }
            // Bold, color, lists, headings and the rest, for the note being edited.
            FormatCommands()
            // ⌃⌘, not ⌘ alone: a note's own ⌘+ and ⌘− change the reading text size. And not ⌥⌘: with
            // Accessibility Zoom's shortcuts turned on, macOS takes ⌥⌘+ and ⌥⌘− before any app sees them.
            CommandGroup(after: .toolbar) {
                Button("Larger Interface") { DisplaySettings.stepSavedInterfaceSize(1) }.keyboardShortcut("=", modifiers: [.command, .control])
                Button("Smaller Interface") { DisplaySettings.stepSavedInterfaceSize(-1) }.keyboardShortcut("-", modifiers: [.command, .control])
                Button("Default Interface Size") { DisplaySettings.stepSavedInterfaceSize(0) }.keyboardShortcut("0", modifiers: [.command, .control])
                Divider()
            }
        }
        Settings {
            MacSettingsView(shell: shell).frame(minWidth: 700, idealWidth: 740, minHeight: 520, idealHeight: 620).perchThemed(ThemeStore.shared, paintsBackground: false)
        }
        .windowResizability(.contentMinSize)
    }
}

extension PerchMacApp {
    /// Moves the task scope one place along All, Work, Personal…, stopping at the ends.
    @MainActor
    private func stepScope(_ offset: Int) {
        let scopes: [String?] = [nil] + shell.model.visibleAreas.map { Optional($0) }
        let index = scopes.firstIndex(of: shell.model.taskScope) ?? 0
        shell.model.setScope(scopes[min(max(index + offset, 0), scopes.count - 1)])
    }
}

/// Saves SwiftUI's window opener and the main window itself, so the Dock and the notch bring back that one
/// window, or open a new one once it has gone, and never a second beside it.
private struct WindowOpenerCapture: View {
    @ObservedObject var shell: MacShell
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        WindowReader { [weak shell] window in shell?.mainWindow = window }
            .onAppear {
                shell.services.openMainWindow = { [weak shell] in
                    // Right after launch the main window can exist before it has reported itself; find it by
                    // the identifier SwiftUI gives the "main" window group, so a Dock click can't open a second.
                    let window = shell?.mainWindow ?? NSApp.windows.first {
                        ($0.identifier?.rawValue.hasPrefix("main") ?? false) && ($0.isVisible || $0.isMiniaturized)
                    }
                    NSApp.activate(ignoringOtherApps: true)
                    switch MainWindowReopen.action(window: window.map { .init(isVisible: $0.isVisible, isMiniaturized: $0.isMiniaturized) }) {
                    case .bringForward:
                        window?.makeKeyAndOrderFront(nil)
                    case .restore:
                        window?.deminiaturize(nil)
                        window?.makeKeyAndOrderFront(nil)
                    case .openNew:
                        openWindow(id: "main")
                    }
                }
            }
    }
}

/// Reports the window it is drawn in. A window that closes is let go by the weak reference that holds it,
/// or reads as not visible until then, so only arriving in a window is reported.
private struct WindowReader: NSViewRepresentable {
    let arrived: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { Probe(arrived: arrived) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Probe: NSView {
        let arrived: (NSWindow) -> Void

        init(arrived: @escaping (NSWindow) -> Void) {
            self.arrived = arrived
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { arrived(window) }
        }
    }
}

/// Owns app-wide objects that outlive any one window.
@MainActor
final class MacShell: ObservableObject {
    let model: AppModel
    let services: NotchServices
    /// Tabs: the tabs and panes of the main window, used only while the experimental setting is on.
    let workspace: WorkspaceStore
    private(set) var notch: NotchController?
    @Published var vaultPath: String?
    @Published var syncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(syncEnabled, forKey: "syncEnabled")
            if let vaultPath { open(path: vaultPath, repository: notebookRepository) }
        }
    }
    /// What this build was set up with (Config/Perch.xcconfig): the GitHub App, the update source, the
    /// Keychain service. A build without a GitHub App never asks anyone to sign in.
    let configuration = PerchConfiguration.main
    /// The GitHub sign-in. A build with a GitHub App needs one before it opens a notebook.
    let github: GitHubSession
    /// Every secret (the GitHub account and the Relay token) in one Keychain item, read at most once a launch
    /// and only when something needs it: see `KeychainSecrets`. Nil in a test run, which keeps them in memory.
    private let keychain: KeychainSecrets?
    /// Who is signed in, from preferences, so drawing the window never reads the Keychain.
    @Published private(set) var profile: GitHubProfile?
    /// A sign-in is saved, but the Keychain didn't let Perch read it this launch. That isn't signed out.
    @Published private(set) var signInUnreadable = false
    var isSignedIn: Bool { profile != nil || signInUnreadable }
    /// "owner/name" when the open notebook was cloned from GitHub through Perch; its sync signs in as the account.
    /// Nil for a Git repository set up some other way, which syncs with that folder's own Git login.
    @Published private(set) var notebookRepository: String?
    /// False for a plain folder, which opens without sync.
    @Published private(set) var notebookIsGit = true
    /// Shows the notebook chooser over the open notebook.
    @Published var showingChooser = false
    /// The main window, while there is one. The Dock and the notch bring this window back rather than open another.
    weak var mainWindow: NSWindow?
    /// Perch's own updates, from its GitHub releases.
    let updates: UpdateCenter
    let isSnapshot: Bool
    /// A snapshot or the navigation stress test: a test notebook, and never the Keychain, the Relay, the
    /// notch, update checks or saved settings.
    let isTestRun: Bool
    var needsAccount: Bool { FirstRun.needsAccount(configuration, isSignedIn: isSignedIn, isTestRun: isTestRun) }

    private static let vaultRepositoryKey = "vaultGitHubRepository"
    private static let profileKey = "githubProfile"

    init() {
        #if DEBUG
        // The earliest point the app's own code runs: see `AppDelegate.applicationWillFinishLaunching`.
        if ProcessInfo.processInfo.arguments.contains("-perchSnapshotDir") { NSApplication.shared.setActivationPolicy(.prohibited) }
        #endif
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Perch")
        // A snapshot run starts on Tasks › All › Today every time, and saves nothing about where it went.
        #if DEBUG
        let isSnapshot = ProcessInfo.processInfo.arguments.contains("-perchSnapshotDir")
        let isTestRun = isSnapshot || ProcessInfo.processInfo.arguments.contains("-perchNavStress")
        #else
        let isSnapshot = false
        let isTestRun = false
        #endif
        self.isSnapshot = isSnapshot
        self.isTestRun = isTestRun
        model = AppModel(supportDirectory: support, navigationDefaults: isTestRun ? nil : .standard)
        services = NotchServices(model: model)
        // A snapshot run starts with one tab and saves nothing about the tabs it opens.
        workspace = WorkspaceStore(model: model, defaults: isSnapshot ? nil : .standard)
        syncEnabled = UserDefaults.standard.object(forKey: "syncEnabled") as? Bool ?? true
        // Test runs never read the Keychain, so a test run can't ask for it or change it.
        let keychain = isTestRun ? nil : KeychainSecrets(keychain: SystemKeychain(), notes: UserDefaultsSecretNotes(), service: configuration.keychainService)
        self.keychain = keychain
        github = GitHubSession(signIn: GitHubDeviceSignIn(clientID: configuration.gitHubClientID), store: keychain ?? MemorySecretStore())
        // Without a GitHub App nobody can sign in, so nothing about an account is looked up.
        if let keychain, configuration.signsInWithGitHub {
            let signedIn = Self.savedProfile(keychain)
            profile = signedIn.profile
            signInUnreadable = signedIn.unreadable
        }
        updates = UpdateCenter(github: github, repository: configuration.checksForUpdates ? configuration.updateRepository : nil)
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-perchSnapshotDir") {
            // Snapshots only read. They never sync and never change which notebook the app opens next,
            // so a snapshot run can't touch the real notebook's Git history or saved settings.
            // `-perchSnapshotVault <folder>` picks a test notebook; without it, the saved one is drawn.
            let named = arguments.firstIndex(of: "-perchSnapshotVault").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
            if let path = named ?? UserDefaults.standard.string(forKey: "vaultPath"), FileManager.default.fileExists(atPath: path) {
                vaultPath = path
                notebookIsGit = FileManager.default.fileExists(atPath: URL(fileURLWithPath: path).appendingPathComponent(".git").path)
                model.open(root: URL(fileURLWithPath: path), engine: nil)
            }
            DispatchQueue.main.async { SnapshotRunner.start(shell: self) }
            return
        }
        // `-perchNavStress <test notebook> <result.json>`: the real window on a copy of a notebook, driven
        // by NavStress. It never syncs and never saves which notebook to open next.
        if let index = arguments.firstIndex(of: "-perchNavStress"), arguments.indices.contains(index + 2) {
            let path = arguments[index + 1]
            vaultPath = path
            notebookIsGit = FileManager.default.fileExists(atPath: URL(fileURLWithPath: path).appendingPathComponent(".git").path)
            model.open(root: URL(fileURLWithPath: path), engine: nil)
            let result = URL(fileURLWithPath: arguments[index + 2])
            DispatchQueue.main.async { NavStress.start(shell: self, result: result) }
            return
        }
        #endif
        // In a build with a GitHub App the saved notebook opens only once someone is signed in. A sign-in the
        // Keychain wouldn't hand over still counts: the notes are on this Mac, and sync says what is wrong.
        if !needsAccount { openSavedNotebook() }
        // A few seconds after launch, once the notebook is up, look for a newer Perch (needs the account).
        if FirstRun.checksForUpdatesAtLaunch(configuration, hasAccount: profile != nil) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [updates] in updates.checkAtLaunch() }
        }
        // SwiftUI's App can create this before AppKit is ready, so start the notch next turn.
        DispatchQueue.main.async { [self] in notch = NotchController(services: services) }
    }

    /// File, Close (Cmd+W). See `MainWindowClose`.
    func closeFrontmost() {
        #if DEBUG
        DebugProbes.closeCommands += 1
        #endif
        // Perch is the app in front whenever its menu takes Cmd+W; the last fallback is for the stress test,
        // which drives the window from behind.
        let window = NSApp.keyWindow ?? NSApp.mainWindow ?? mainWindow
        let inMain = window != nil && window === mainWindow
        #if DEBUG
        func name(_ w: NSWindow?) -> String { w.map { "\($0.identifier?.rawValue ?? "-")#\($0.windowNumber)" } ?? "nil" }
        DebugProbes.lastClose = "panel \(model.selectedTaskID != nil), key \(name(NSApp.keyWindow)), NSApp.main \(name(NSApp.mainWindow)), shell.main \(name(mainWindow)), chose \(name(window))"
        #endif
        switch MainWindowClose.commandW(panelOpen: model.selectedTaskID != nil, inMainWindow: inMain) {
        case .closePanel: model.selectedTaskID = nil
        case .closeWindow, .notOurs: window?.performClose(nil)
        }
    }

    /// Open Notebook… and Settings' "Open a different notebook…": the chooser, over the main window.
    func chooseVault() {
        guard !needsAccount else { return services.openMainWindow() }
        if vaultPath == nil { return services.openMainWindow() }
        showingChooser = true
        services.openMainWindow()
    }

    private func openSavedNotebook() {
        guard let path = UserDefaults.standard.string(forKey: "vaultPath"), FileManager.default.fileExists(atPath: path) else { return }
        open(path: path, repository: UserDefaults.standard.string(forKey: Self.vaultRepositoryKey))
    }

    /// Opens a notebook folder. A repository name means Perch cloned it from GitHub, and its sync signs in as the account.
    func open(path: String, repository: String? = nil) {
        UserDefaults.standard.set(path, forKey: "vaultPath")
        UserDefaults.standard.set(repository, forKey: Self.vaultRepositoryKey)
        vaultPath = path
        notebookRepository = repository
        let url = URL(fileURLWithPath: path)
        let isGit = FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
        notebookIsGit = isGit
        var engine: (any SyncEngine)?
        if isGit && syncEnabled {
            if repository != nil {
                let github = github
                engine = GitCLISync(root: url, token: { try await github.accessToken() })
            } else {
                engine = GitCLISync(root: url)
            }
        }
        model.open(root: url, engine: engine)
        connectRelay()
    }

    func signedIn(with token: GitHubDeviceSignIn.Token) async throws {
        let account = try await github.signedIn(with: token)
        setProfile(GitHubProfile(account))
        openSavedNotebook()
        if FirstRun.checksForUpdatesAtLaunch(configuration, hasAccount: true) { updates.checkAtLaunch() }
    }

    /// Forgets the account and stops syncing. The notebook's files stay where they are.
    func signOut() {
        let github = github
        Task { await github.signOut() }
        setProfile(nil)
        showingChooser = false
        model.close()
    }

    private func setProfile(_ profile: GitHubProfile?) {
        self.profile = profile
        signInUnreadable = false
        guard !isTestRun else { return }
        Self.saveProfile(profile)
    }

    /// Who is signed in. Since this version it is kept in preferences, as a copy of the saved account's
    /// public parts. Without that copy (the first launch of this version) it is learned once from the
    /// Keychain, in the read the first sync needs anyway. When the notes say no account is saved, the
    /// Keychain isn't touched.
    private static func savedProfile(_ keychain: KeychainSecrets) -> (profile: GitHubProfile?, unreadable: Bool) {
        if keychain.isSaved(GitHubSession.storeKey) == false {
            saveProfile(nil)
            return (nil, false)
        }
        if let data = UserDefaults.standard.data(forKey: profileKey), let profile = try? JSONDecoder().decode(GitHubProfile.self, from: data) {
            return (profile, false)
        }
        do {
            let profile = try GitHubSession.storedAccount(in: keychain).map(GitHubProfile.init)
            saveProfile(profile)
            return (profile, false)
        } catch {
            return (nil, true)
        }
    }

    private static func saveProfile(_ profile: GitHubProfile?) {
        if let profile, let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: profileKey)
        } else {
            UserDefaults.standard.removeObject(forKey: profileKey)
        }
    }

    /// Clones a repository Perch can reach, or opens the clone of it already in that folder.
    func openFromGitHub(_ fullName: String, in parent: URL) async throws {
        switch GitHubNotebook.placement(for: fullName, in: parent) {
        case let .open(folder):
            open(path: folder.path, repository: fullName)
        case let .clone(folder):
            let token = try await github.accessToken()
            let author = profile.map { (name: $0.commitName, email: $0.commitEmail) }
            try await GitCLISync.clone(GitHubNotebook.remoteURL(for: fullName), to: folder, token: token, author: author)
            open(path: folder.path, repository: fullName)
        }
        showingChooser = false
    }

    /// Asks for a notebook folder on this Mac and opens it. A build with a GitHub App asks for a Git
    /// repository, as it always has; one without opens any folder, and syncs it only if it is a Git
    /// repository (see `FirstRun.opening`). Returns why not, when the folder can't be used.
    func chooseLocalRepository() -> String? {
        let anyFolder = FirstRun.sources(configuration).contains(.anyFolder)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = anyFolder
        panel.prompt = "Open Notebook"
        panel.message = anyFolder
            ? "Choose a folder of notes. If it is a Git repository, Perch syncs it with the Git login it already uses."
            : "Choose a Git repository of notes. Perch syncs it with the Git login it already uses."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let isGit = FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
        guard FirstRun.opening(configuration, isGitRepository: isGit) != .refused else {
            return "\(url.lastPathComponent) isn't a Git repository. Choose a folder that is a Git clone, or clone one from GitHub above."
        }
        open(path: url.path)
        showingChooser = false
        return nil
    }

    @Published var relayURL = UserDefaults.standard.string(forKey: "relayURL") ?? ""
    /// Whether an app token is saved, from the notes kept beside the Keychain, so Settings can say so without
    /// reading it.
    @Published private(set) var hasRelayToken = false
    private var relayConnect: Task<Void, Never>?

    /// The token lives in the Keychain with the GitHub account, the address in preferences. `asked` is true
    /// for Connect in Settings: the user asked for it, so a refusal earlier in this launch may be asked again.
    func connectRelay(token newToken: String? = nil, asked: Bool = false) {
        // A test run never reads or changes the real address and token.
        guard !isTestRun, let keychain else { return }
        UserDefaults.standard.set(relayURL, forKey: "relayURL")
        let key = KeychainSecrets.relayTokenKey
        let url = URL(string: relayURL).flatMap { $0.scheme == nil ? nil : $0 }
        let trimmed = newToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pasted: String? = trimmed.isEmpty ? nil : trimmed
        // Only when it has to: with no address there is nothing to connect to, and a token the notes say
        // isn't saved isn't looked for.
        let wanted = url != nil && (pasted != nil || keychain.isSaved(key) != false)
        hasRelayToken = pasted != nil || keychain.isSaved(key) == true
        relayConnect?.cancel()
        guard wanted || pasted != nil else {
            model.connectRelay(nil)
            return
        }
        relayConnect = Task { [weak self] in
            // Off the main thread: the first read of a launch can wait for the user to answer the Keychain.
            let token = await Task.detached { () -> String? in
                if asked { keychain.allowAskingAgain() }
                if let pasted { keychain.save(Data(pasted.utf8), for: key) }
                guard wanted else { return nil }
                return keychain.load(key).flatMap { String(data: $0, encoding: .utf8) }
            }.value
            guard let self, !Task.isCancelled else { return }
            hasRelayToken = token != nil || keychain.isSaved(key) == true
            guard let url, let token else { return model.connectRelay(nil) }
            model.connectRelay(RelayClient(baseURL: url, token: token))
        }
    }
}

struct MacRootView: View {
    @ObservedObject var shell: MacShell
    @ObservedObject private var model: AppModel
    @ObservedObject private var updates: UpdateCenter
    @AppStorage(WorkspaceStore.settingKey) private var tabsOn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.perchTheme) private var theme

    init(shell: MacShell) {
        self.shell = shell
        model = shell.model
        updates = shell.updates
    }

    var body: some View {
        if shell.needsAccount {
            SignInView(shell: shell)
        } else if shell.vaultPath == nil {
            NotebookChooserView(shell: shell)
        } else {
            NavigationSplitView {
                SidebarView(model: model).navigationSplitViewColumnWidth(min: 210, ideal: 250)
            } detail: {
                // The task panel is Perch's own column, not SwiftUI's inspector: see TaskPanelColumn.
                TaskPanelColumn(model: model) {
                    detail
                }
            }
            .modifier(ThemedWindowChrome(background: theme.background))
            .modifier(RootOverlays(model: model))
            .alert(
                updates.offer.map { "Perch \($0.version.description) is available" } ?? "",
                isPresented: Binding(get: { updates.offer != nil }, set: { if !$0 { updates.offer = nil } }),
                presenting: updates.offer
            ) { update in
                Button("Install and Restart") { Task { await updates.install(update) } }
                Button("What's New") {
                    SettingsRouter.shared.pane = .updates
                    model.route = .settings
                }
                Button("Later", role: .cancel) {}
            } message: { update in
                Text(update.notes.isEmpty ? "A newer Perch is on GitHub." : String(update.notes.prefix(500)))
            }
            .sheet(isPresented: $shell.showingChooser) {
                NotebookChooserView(shell: shell, onCancel: { shell.showingChooser = false })
                    .frame(width: 660, height: 680)
            }
            .environment(\.perchWorkspace, tabsOn ? shell.workspace : nil)
        }
    }

    /// The main pane: one place, or with "Tabs and split view" on, the workspace's tabs and panes.
    @ViewBuilder
    private var detail: some View {
        if tabsOn {
            WorkspaceDetail(store: shell.workspace, model: model, settings: AnyView(MacSettingsView(shell: shell)))
        } else {
            DetailRouter(model: model, settings: AnyView(MacSettingsView(shell: shell)))
        }
    }
}

/// Settings as a list of groups on the left and the chosen group on the right. The same view fills the
/// Settings window and the main window's Settings place.
struct MacSettingsView: View {
    @ObservedObject var shell: MacShell
    @ObservedObject private var router = SettingsRouter.shared
    @Environment(\.perchTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsPane.allCases) { pane in SettingsPaneButton(pane: pane, selection: $router.pane) }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(width: Metrics.scaled(176))
            .background(theme.sidebar)
            .overlay(alignment: .trailing) { Rectangle().fill(theme.border).frame(width: 1) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Settings groups")
            // Up and Down move between the groups once the list has the keyboard (Tab reaches it).
            .focusable()
            .focusEffectDisabled()
            .onMoveCommand { direction in
                let all = SettingsPane.allCases
                guard let index = all.firstIndex(of: router.pane) else { return }
                switch direction {
                case .up: router.pane = all[max(index - 1, 0)]
                case .down: router.pane = all[min(index + 1, all.count - 1)]
                default: break
                }
            }
            MacSettingsPane(shell: shell, pane: router.pane)
                .id(router.pane)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.background)
        .navigationTitle("Settings")
    }
}

private struct SettingsPaneButton: View {
    let pane: SettingsPane
    @Binding var selection: SettingsPane
    @Environment(\.perchTheme) private var theme

    var body: some View {
        let selected = selection == pane
        Button { selection = pane } label: {
            Label { Text(pane.title) } icon: { Image(systemName: pane.symbol).frame(width: Metrics.scaled(22)) }
                .font(.perchBody)
                .foregroundStyle(selected ? theme.accent : theme.text)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: Metrics.row(28), alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? theme.accentSoft : Color.clear))
        .motion(Motion.quick, value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One group of settings. Display, Reading and Editing are shared with the iPhone; the rest are the Mac's own.
struct MacSettingsPane: View {
    @ObservedObject var shell: MacShell
    let pane: SettingsPane
    /// Read so this is drawn again when the interface size or density changes.
    @Environment(\.perchDisplay) private var display

    var body: some View {
        let _ = display
        switch pane {
        case .display: DisplaySettingsView()
        case .reading: ReadingSettingsView()
        case .editing: EditingSettingsView()
        default:
            Form {
                switch pane {
                case .appearance:
                    Section("Theme") { ThemeSettingsSection() }
                case .notebook:
                    // A build without a GitHub App has no account to show.
                    if FirstRun.showsAccountSettings(shell.configuration) {
                        Section("GitHub account") {
                            LabeledContent("Signed in as") {
                                Text(shell.profile.map { "@\($0.login)" } ?? (shell.signInUnreadable ? "Saved, but the Keychain didn't let Perch read it" : "Not signed in"))
                            }
                            Button("Sign Out", role: .destructive) { shell.signOut() }.disabled(!shell.isSignedIn)
                            Text("Signing out stops sync. Your notes stay in the notebook folder and on GitHub.")
                                .font(.perchStyle(.caption)).foregroundStyle(.secondary)
                        }
                    }
                    Section("Notebook") {
                        LabeledContent("Folder") { Text(shell.vaultPath ?? "None").textSelection(.enabled).lineLimit(2) }
                        LabeledContent("Syncs with") {
                            Text(shell.notebookRepository.map { "github.com/\($0), as your GitHub account" }
                                ?? (shell.notebookIsGit ? "This folder's own Git remote and login" : "Nothing. This folder isn't a Git repository, so Perch only saves to it."))
                                .lineLimit(2)
                        }
                        Button("Open a different notebook…") { shell.chooseVault() }
                    }
                    Section("Areas") { AreaEditor(model: shell.model, embedded: true) }
                case .agents:
                    Section("Agents") { RelaySettings(shell: shell, model: shell.model) }
                case .notch:
                    Section("Notch") { NotchSettings(shell: shell) }
                case .updates:
                    UpdatesSettings(updates: shell.updates)
                case .experimental:
                    ExperimentalSettings()
                default:
                    Section("Sync") {
                        Toggle("Sync with Git", isOn: $shell.syncEnabled)
                        Text("Perch commits changes, pulls, and pushes about once a minute. A notebook cloned from GitHub in Perch syncs as your GitHub account; any other Git repository uses its own remote and Git login.")
                            .font(.perchStyle(.caption)).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .perchScreenBackground()
            // The Mac doesn't scale a form's own labels, so they are given the interface size here,
            // as the Display, Reading and Editing panes do.
            .environment(\.font, display.metrics.size == .standard ? nil : Font.perchStyle(.body))
        }
    }
}

struct NotchSettings: View {
    @ObservedObject var shell: MacShell
    /// Read so this is drawn again when the interface size or density changes.
    @Environment(\.perchDisplay) private var display
    @AppStorage("notchEnabled") private var enabled = true
    @AppStorage("notchAmbient") private var ambient = true
    @AppStorage("notchScreens") private var screens = "builtin"
    @AppStorage("notepadFolder") private var notepadFolder = "Personal/Daily"
    @AppStorage("notchMotion") private var motion = NotchMotionLevel.full.rawValue
    @AppStorage("notchBreathe") private var breathes = true
    @AppStorage(FocusAvailability.hiddenKey) private var focusHidden = FocusAvailability.hiddenByDefault
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        let _ = display
        Toggle("Show the notch", isOn: $enabled)
        Toggle("Show today's counts beside the notch", isOn: $ambient)
        if ambient {
            LabeledContent("Apps with long menus") {
                if MenuBarClearance.canMeasureMenus {
                    Label("Counts step aside automatically", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                } else {
                    Button("Allow Perch to see menu widths…") { MenuBarClearance.requestMenuAccess() }
                }
            }
            Text("Counts hide whenever menus or menu bar icons reach the notch. Without Accessibility access, Perch can't measure other apps' menus, so it shows counts only in Finder.")
                .font(.perchStyle(.caption)).foregroundStyle(.secondary)
        }
        Toggle("Hide the focus timer", isOn: $focusHidden)
        Text(focusHidden
            ? "The Focus card, the start buttons on tasks, the timer beside the notch and focus time in Insights are hidden. Turn this off to use them."
            : "Turning this on hides the Focus card, the start buttons on tasks, the timer beside the notch and focus time in Insights. A session under way ends and is logged.")
            .font(.perchStyle(.caption)).foregroundStyle(.secondary)
        Picker("Show on", selection: $screens) {
            Text("Screens with a notch").tag("builtin")
            Text("Every screen").tag("all")
        }
        Picker("Notch animations", selection: $motion) {
            ForEach(NotchMotionLevel.allCases) { level in Text(level.title).tag(level.rawValue) }
        }
        Text(motionNote).font(.perchStyle(.caption)).foregroundStyle(.secondary)
        if ambient, motion == NotchMotionLevel.full.rawValue {
            Toggle("Glow gently while something is overdue", isOn: $breathes)
        }
        Toggle("Open Perch at login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, wanted in
                do {
                    if wanted { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    shell.model.banner = "Couldn't change the login setting: \(error.localizedDescription)"
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
        TextField("Notepad folder", text: $notepadFolder)
    }

    private var motionNote: String {
        switch NotchMotionLevel(stored: motion) {
        case .full: "The notch springs open, cards arrive one after another, and finishing things gets a small flourish. Reduce Motion in System Settings still turns all of it into fades."
        case .subtle: "The same movements with no bounce, no stagger and no flourishes."
        case .off: "The notch changes at once, with no animation."
        }
    }
}

struct RelaySettings: View {
    @ObservedObject var shell: MacShell
    /// Watched so the status line changes the moment the Relay answers.
    @ObservedObject var model: AppModel
    /// Read so this is drawn again when the interface size or density changes.
    @Environment(\.perchDisplay) private var display
    @State private var token = ""

    var body: some View {
        let _ = display
        RelayStatusLine(model: model)
        TextField("Relay address", text: $shell.relayURL, prompt: Text("https://relay.example.com"))
        SecureField("App token", text: $token, prompt: Text(shell.hasRelayToken ? "Saved" : "From perch-relay add-agent"))
        Button(model.relayStatus.isConnected ? "Reconnect" : "Connect") {
            let pasted = token.trimmingCharacters(in: .whitespacesAndNewlines)
            shell.connectRelay(token: pasted.isEmpty ? nil : pasted, asked: true)
            token = ""
        }
        .disabled(model.relayStatus == .connecting)
        Text("Shows which agents are working in your notebook, in the notch and the app. Perch only reads from the Relay.")
            .font(.perchStyle(.caption)).foregroundStyle(.secondary)
    }
}

/// The window behind everything, and the toolbar band across the top, take the theme's background, so no
/// system grey shows around the floating sidebar or above the list. macOS 15 and later; macOS 14 keeps the
/// system's look.
private struct ThemedWindowChrome: ViewModifier {
    let background: Color

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .containerBackground(background, for: .window)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            content
        }
    }
}
