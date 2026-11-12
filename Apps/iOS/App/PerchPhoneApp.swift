import ActivityKit
import BackgroundTasks
import PerchKit
import PerchUI
import Security
import SwiftUI
import UserNotifications
import WidgetKit

enum Keychain {
    /// The build's Keychain service (Config/Perch.xcconfig), with the suffix the iPhone has always used.
    private static let service = PerchConfiguration.main.keychainService + ".github"

    static func save(_ token: String, account: String = "github") {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(token.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load(account: String = "github") -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String = "github") {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
    }
}

@MainActor
final class PhoneShell: ObservableObject {
    /// Matches BGTaskSchedulerPermittedIdentifiers in the Info.plist (project.yml).
    static let backgroundTaskID = (Bundle.main.bundleIdentifier ?? "perch") + ".sync"

    let model: AppModel
    let focus: PhoneFocus
    /// Which destination is in front and what is open in it. Shared by the tab bar and the wide layout.
    let navigation: ShellState
    /// Tabs: the tabs and panes of the wide layout, used only while the experimental setting is on.
    let workspace: WorkspaceStore
    @Published var isConfigured = false
    /// The repository's owner, as last entered, or the build's default (`PERCH_DEFAULT_REPOSITORY_OWNER`).
    @Published var owner = UserDefaults.standard.string(forKey: "githubOwner") ?? PerchConfiguration.main.defaultRepositoryOwner
    @Published var repository = UserDefaults.standard.string(forKey: "githubRepository") ?? ""
    @Published var branch = UserDefaults.standard.string(forKey: "githubBranch") ?? "main"

    private var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private var support: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0] }
    var vaultURL: URL { documents.appendingPathComponent("Notebook", isDirectory: true) }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // The section, the area in scope and where each section was left are remembered on this device.
        #if DEBUG
        // A launch that names where to open reads what was saved but doesn't save where it went.
        model = AppModel(supportDirectory: support, navigationDefaults: .standard, savesNavigation: !PhoneLaunch.overridesNavigation)
        PhoneLaunch.apply(to: model)
        #else
        model = AppModel(supportDirectory: support, navigationDefaults: .standard)
        #endif
        focus = PhoneFocus(log: model.focusLog)
        navigation = ShellState(destination: ShellDestination(model.section))
        #if DEBUG
        // A launch that names where to open, or which tabs, saves nothing about its tabs either.
        workspace = WorkspaceStore(model: model, defaults: PhoneLaunch.overridesNavigation ? nil : .standard)
        #else
        workspace = WorkspaceStore(model: model, defaults: .standard)
        #endif
        workspace.attach(shell: navigation)
        #if DEBUG
        PhoneLaunch.apply(to: navigation)
        // Simulator checks: open a sample notebook without GitHub.
        if ProcessInfo.processInfo.arguments.contains("-perchLocalVault") {
            model.open(root: vaultURL, engine: nil)
            isConfigured = true
            return
        }
        #endif
        if let token = Keychain.load(), !repository.isEmpty {
            connect(token: token)
        }
    }

    func connect(token: String) {
        Keychain.save(token)
        UserDefaults.standard.set(owner, forKey: "githubOwner")
        UserDefaults.standard.set(repository, forKey: "githubRepository")
        UserDefaults.standard.set(branch, forKey: "githubBranch")
        try? FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let engine = GitHubAPISync(
            configuration: .init(owner: owner, repository: repository, branch: branch),
            token: token,
            root: vaultURL,
            stateURL: support.appendingPathComponent("sync-\(owner)-\(repository)-\(branch).json")
        )
        model.open(root: vaultURL, engine: engine)
        isConfigured = true
        connectRelay()
    }

    @Published var relayURL = UserDefaults.standard.string(forKey: "relayURL") ?? ""

    func connectRelay(token newToken: String? = nil) {
        UserDefaults.standard.set(relayURL, forKey: "relayURL")
        if let newToken, !newToken.isEmpty { Keychain.save(newToken, account: "relay") }
        guard let url = URL(string: relayURL), url.scheme == "https" || url.host == "localhost", let token = Keychain.load(account: "relay") else {
            model.connectRelay(nil)
            return
        }
        model.connectRelay(RelayClient(baseURL: url, token: token))
    }

    func disconnect() {
        model.close()
        Keychain.delete()
        isConfigured = false
    }

    /// Adds anything captured through the share sheet as tasks.
    func collectShared() {
        guard let inbox = SharedStore.inboxURL,
              let items = try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil) else { return }
        for item in items {
            if let text = try? String(contentsOf: item, encoding: .utf8) {
                let lines = text.components(separatedBy: "\n")
                if let task = model.quickAdd(lines[0]), lines.count > 1 {
                    var updated = task
                    updated.details = lines.dropFirst().joined(separator: "\n")
                    model.update(updated)
                }
            }
            try? FileManager.default.removeItem(at: item)
        }
    }

    /// Keeps widgets and scheduled reminders in step with the tasks.
    func publishToSystem() {
        let today = model.today
        let list = model.todayTasks
        let snapshot = WidgetSnapshot(
            date: Date(),
            total: list.count,
            overdue: list.filter { $0.isOverdue(today: today) }.count,
            tasks: list.prefix(8).map { .init(id: $0.id, title: $0.title, priority: $0.priority, isOverdue: $0.isOverdue(today: today), area: $0.area) }
        )
        if let url = SharedStore.snapshotURL, let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
        }
        scheduleReminders()
    }

    private func scheduleReminders() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let now = Date()
        var pending: [(key: String, title: String, date: Date)] = []
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        for task in model.tasks where task.isOpen {
            let due = task.due.flatMap { day in task.time.flatMap { formatter.date(from: "\(day)T\($0)") } }
            if task.remind.isEmpty, let due, due > now { pending.append((task.id, task.title, due)) }
            for entry in task.remind {
                var date: Date?
                if entry.hasPrefix("-"), entry.hasSuffix("m"), let minutes = Int(entry.dropFirst().dropLast()) {
                    date = due?.addingTimeInterval(TimeInterval(-minutes * 60))
                } else {
                    date = formatter.date(from: String(entry.prefix(16)))
                }
                if let date, date > now { pending.append(("\(task.id)|\(entry)", task.title, date)) }
            }
        }
        // iOS holds at most 64 pending notifications, so keep the soonest.
        for item in pending.sorted(by: { $0.date < $1.date }).prefix(60) {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.sound = .default
            content.categoryIdentifier = "TASK"
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            let request = UNNotificationRequest(identifier: item.key, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            center.add(request)
        }
    }

    func scheduleBackgroundSync() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// The iPhone's focus timer, shown on the Lock Screen and in the Dynamic Island.
@MainActor
final class PhoneFocus: ObservableObject {
    @Published private(set) var endDate: Date?
    @Published private(set) var startDate: Date?
    private var activity: Activity<FocusAttributes>?
    private let log: FocusLog

    init(log: FocusLog) { self.log = log }

    var isRunning: Bool { startDate != nil }

    func start(minutes: Int?, taskTitle: String) {
        stop()
        // Nothing starts a session, or a Live Activity, while the timer is hidden in Settings.
        guard FocusAvailability.isAvailable() else { return }
        let start = Date()
        startDate = start
        endDate = minutes.map { start.addingTimeInterval(TimeInterval($0 * 60)) }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = FocusAttributes.ContentState(endDate: endDate, startDate: start, isPaused: false, pausedDisplay: nil)
        activity = try? Activity.request(attributes: FocusAttributes(taskTitle: taskTitle), content: .init(state: state, staleDate: endDate))
    }

    func addFive() {
        guard let start = startDate, let end = endDate else { return }
        endDate = end.addingTimeInterval(300)
        let state = FocusAttributes.ContentState(endDate: endDate, startDate: start, isPaused: false, pausedDisplay: nil)
        Task { await activity?.update(.init(state: state, staleDate: endDate)) }
    }

    func stop() {
        if let start = startDate {
            let ending = min(endDate ?? Date(), Date())
            log.add(FocusSession(start: start, seconds: Int(ending.timeIntervalSince(start))))
        }
        startDate = nil
        endDate = nil
        let current = activity
        activity = nil
        Task { await current?.end(nil, dismissalPolicy: .immediate) }
    }
}

@main
struct PerchPhoneApp: App {
    @StateObject private var shell = PhoneShell()
    /// Tabs: "Tabs and split view (experimental)". Off, the Tabs shortcuts aren't there at all.
    @AppStorage(WorkspaceStore.settingKey) private var tabsOn = false
    @Environment(\.scenePhase) private var phase

    init() {
        #if DEBUG
        PhoneLaunch.applyOverrides()
        #endif
        BGTaskScheduler.shared.register(forTaskWithIdentifier: PhoneShell.backgroundTaskID, using: nil) { task in
            Task { @MainActor in
                guard let shell = PhoneShell.current else {
                    task.setTaskCompleted(success: false)
                    return
                }
                await shell.model.syncNow()
                shell.publishToSystem()
                shell.scheduleBackgroundSync()
                task.setTaskCompleted(success: true)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if shell.isConfigured {
                    PhoneRootView(shell: shell)
                } else {
                    SetupView(shell: shell)
                }
            }
            .perchThemed(ThemeStore.shared)
            .onAppear {
                PhoneShell.current = shell
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-perchLocalVault") { return }
                #endif
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            }
        }
        .commands {
            PhoneCommands(shell: shell)
            if tabsOn { WorkspaceCommands(store: shell.workspace) }
        }
        .onChange(of: phase) { _, newPhase in
            switch newPhase {
            case .active:
                shell.collectShared()
                Task { await shell.model.syncNow() }
            case .background:
                // A task ticked a moment ago is written before the app can be suspended.
                shell.model.flushCompletions()
                shell.publishToSystem()
                shell.scheduleBackgroundSync()
            default: break
            }
        }
    }
}

extension PhoneShell {
    static weak var current: PhoneShell?
}

#if DEBUG
/// Launch arguments for opening any screen on the simulator without tapping. Debug builds only.
///
///     -perchSection <tasks|notes>                -perchScope <area name>
///     -perchView <today|upcoming|list|calendar|board|ready>
///     -perchCalendarMode <month|week>            -perchFolder <path>
///     -perchNotesKind <all|notes|boards|whiteboards>
///     -perchExtraAreas "Consulting,Other"        -perchTab <agents|search>
///     -perchSettings <root|areas|theme|display|reading|editing>    -perchTheme <id>
///     -perchOpen <file path>                     -perchTask <task id>
///     -perchSearch <text>                        -perchSidebar <expanded|rail|drawer>
///     -perchForceLayoutSize <width>x<height>     -perchNotesBrowser <shown|hidden>
///     -perchNoteMode <read|edit|split>
///     -perchTabs "today|file:Personal/Chess Project.md"    -perchSplit <item>
///
/// `-perchTabs` turns on the experimental tabs and split view for the launch and opens those places as
/// tabs, `|` between them; `-perchSplit` puts one more in a second pane. A place is `today`, `list`,
/// `calendar`, `folder:<path>`, `file:<path>` or `search`. `-experimentalTabs YES` alone turns the
/// setting on for the launch with one tab.
///
/// `-perchForceLayoutSize 951x669` lays the app out as if it had that much room and scales the result
/// to fit the screen, so the layouts of a screen the simulator can't show (a folding phone's inner
/// screen) can still be looked at. `-perchView board` shows the Board, which needs a wide layout.
/// `-perchForceLayoutAfter <seconds>` starts the run at the real size and switches to the forced one
/// after that long; `-perchForceLayoutUntil <seconds>` does the opposite. Either stands in for opening
/// or closing a folding phone part-way through, to check that the place is kept.
/// `-perchForceLayoutColumn 86` pretends the system keeps that much of the forced width for a column of
/// its own, as it does on the cover screen: the layout is told the whole size and draws in the rest.
/// `-perchPretendScene 678x951` only tells the layout the screen is that big; the app draws unscaled in
/// the room it really has, so the rail can be tried at full size on the cover screen held sideways.
/// `-perchLayoutReadout` prints the measured screen, the room inside the safe area and the arrangement
/// chosen along the bottom edge.
///
/// All of it applies to that launch only. The theme and calendar mode go in the launch-argument domain,
/// which is never saved, the same way the Mac snapshot runner does it; a launch that names a section,
/// scope, view or folder doesn't save where it ends up; and the extra areas are never written anywhere.
/// `-perchScope work` finds "✈️ Work": case and a leading emoji are ignored.
@MainActor
enum PhoneLaunch {
    static func value(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.firstIndex(of: name).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    }

    static func applyOverrides() {
        var volatile = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        if let theme = value("-perchTheme") { volatile[ThemeStore.Keys.selected] = theme }
        if let mode = value("-perchCalendarMode"), ["month", "week"].contains(mode) { volatile["calendarMode"] = mode }
        if let sidebar = value("-perchSidebar") { volatile[SidebarPreference.storageKey] = sidebar == "expanded" ? "expanded" : "rail" }
        if let browser = value("-perchNotesBrowser") { volatile["shellNotesBrowserHidden"] = browser == "hidden" }
        if value("-perchTabs") != nil || value("-perchSplit") != nil { volatile[WorkspaceStore.settingKey] = true }
        if let mode = value("-perchNoteMode").flatMap(NoteMode.init(rawValue:)) {
            volatile[ReadingSettings.Key.openIn] = mode == .read ? "read" : "edit"
            volatile[ReadingSettings.Key.editWithPreview] = mode == .split
        }
        UserDefaults.standard.setVolatileDomain(volatile, forName: UserDefaults.argumentDomain)
        ThemeStore.shared.reload()
    }

    /// True when the launch says where to open, so nothing about where it goes is saved.
    static var overridesNavigation: Bool {
        ["-perchSection", "-perchScope", "-perchView", "-perchFolder", "-perchNotesKind", "-perchExtraAreas", "-perchTab", "-perchOpen", "-perchSearch", "-perchTabs", "-perchSplit", "-experimentalTabs"]
            .contains { value($0) != nil }
    }

    /// Puts the model where the launch arguments say, before anything is drawn.
    static func apply(to model: AppModel) {
        if let names = value("-perchExtraAreas") {
            model.transientAreas = names.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        if let view = value("-perchView").flatMap(TaskViewKind.init(rawValue:)) { model.show(view: view) }
        if let scope = value("-perchScope") { model.setScope(named: scope) }
        if let kind = value("-perchNotesKind").flatMap(NotesKind.init(rawValue:)) { model.setNotesKind(kind) }
        if let folder = value("-perchFolder") { model.setNotesFolder(folder) }
        // The old Boards tab is Notes showing boards.
        if value("-perchTab") == "boards" { model.setNotesKind(.boards) }
        if ["notes", "boards"].contains(value("-perchTab") ?? "") { model.selectSection(.notes) }
        if let section = value("-perchSection").flatMap(AppSection.init(rawValue:)) { model.selectSection(section) }
        if let query = value("-perchSearch") { model.searchQuery = query }
    }

    /// Puts the shell where the launch arguments say.
    static func apply(to navigation: ShellState) {
        switch value("-perchTab") {
        case "agents": navigation.destination = .agents
        case "search": navigation.destination = .search
        default: break
        }
        if value("-perchSidebar") == "drawer" { navigation.drawerOpen = true }
    }

    /// The size named by `-perchForceLayoutSize 951x669`.
    static let forcedSize: CGSize? = {
        guard let parts = value("-perchForceLayoutSize")?.lowercased().split(separator: "x").compactMap({ Double($0) }),
              parts.count == 2, parts[0] >= 200, parts[1] >= 200 else { return nil }
        return CGSize(width: parts[0], height: parts[1])
    }()

    /// The width `-perchForceLayoutColumn 86` takes off the forced size for a column the system keeps,
    /// as it does on the cover screen. The layout is told the whole size and given the rest to draw in.
    static let forcedColumn: CGFloat = max(CGFloat(value("-perchForceLayoutColumn").flatMap(Double.init) ?? 0), 0)

    /// The size named by `-perchPretendScene 678x951`: the layout is told the screen is that big while
    /// the app keeps drawing, unscaled, in the room it really has. On the cover screen held sideways
    /// (594 points beside the system's column) it gives the rail at full size, system column and all.
    static let pretendScene: CGSize? = {
        guard let parts = value("-perchPretendScene")?.lowercased().split(separator: "x").compactMap({ Double($0) }), parts.count == 2 else { return nil }
        return CGSize(width: parts[0], height: parts[1])
    }()

    static let showsReadout = ProcessInfo.processInfo.arguments.contains("-perchLayoutReadout")

    /// "root", "areas", "theme", "display", "reading" or "editing" from `-perchSettings`: Settings itself, or one of its screens.
    static var settings: String? { value("-perchSettings") }
    /// The screens `-perchSettings` can push on top of Settings.
    static let settingsScreens = ["areas", "theme", "display", "reading", "editing"]
    static var settingsShown = false
}
#endif

struct SetupView: View {
    @ObservedObject var shell: PhoneShell
    @State private var code: GitHubDeviceSignIn.Code?
    @State private var waiting: Task<Void, Never>?
    @State private var message: String?
    @State private var copied = false
    @State private var showManual = false
    @State private var manualToken = ""
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var signIn: GitHubDeviceSignIn { GitHubDeviceSignIn(clientID: configuration.gitHubClientID) }
    private let configuration = PerchConfiguration.main
    /// A build with no GitHub App (the public build) can't sign in, so it connects with a token alone.
    private var signsIn: Bool { configuration.signsInWithGitHub }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image("PerchMark").resizable().scaledToFit().frame(width: 110, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .padding(.top, 30)
                    VStack(spacing: 6) {
                        Text("Welcome to Perch").font(.title.bold())
                        Text("Your notes and tasks, synced with GitHub.").foregroundStyle(theme.textSecondary)
                    }
                    if signsIn {
                        if let code {
                            codeCard(code)
                        } else {
                            Button(action: begin) {
                                Label("Sign in with GitHub", systemImage: "person.badge.key.fill")
                                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .padding(.horizontal, 24)
                        }
                    }
                    if let message {
                        Text(message).font(.callout).foregroundStyle(theme.danger).multilineTextAlignment(.center).padding(.horizontal)
                    }
                    if signsIn {
                        DisclosureGroup("Use a personal access token instead", isExpanded: $showManual) { tokenForm }
                            .font(.callout)
                            .padding(.horizontal, 24)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Connect to the GitHub repository that holds your notes with a fine-grained token that can read and write its contents.")
                                .font(.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                            tokenForm
                        }
                        .padding(.horizontal, 24)
                    }
                }
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .motion(Motion.smooth, value: code?.userCode)
            .perchScreenBackground()
        }
        .onDisappear { waiting?.cancel() }
    }

    private var tokenForm: some View {
        VStack(spacing: 10) {
            TextField("Owner", text: $shell.owner).textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("Repository", text: $shell.repository).textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("Fine-grained token", text: $manualToken).textInputAutocapitalization(.never)
            Button("Connect") { shell.connect(token: jsTrim(manualToken)) }
                .disabled(jsTrim(manualToken).isEmpty || shell.repository.isEmpty || shell.owner.isEmpty)
        }
        .textFieldStyle(.roundedBorder)
        .padding(.top, 8)
    }

    private func codeCard(_ code: GitHubDeviceSignIn.Code) -> some View {
        VStack(spacing: 14) {
            Text("Enter this code on GitHub").font(.subheadline).foregroundStyle(.secondary)
            Text(code.userCode)
                .font(.system(size: 38, weight: .bold, design: .monospaced))
                .tracking(4)
                .textSelection(.enabled)
            Button {
                UIPasteboard.general.string = code.userCode
                copied = true
                UIApplication.shared.open(code.verificationURL)
            } label: {
                Label(copied ? "Code copied, opening GitHub" : "Copy code and open GitHub", systemImage: copied ? "checkmark" : "arrow.up.forward.app")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            HStack(spacing: 8) {
                ProgressView()
                Text("Waiting for you to approve on GitHub…").font(.footnote).foregroundStyle(.secondary)
            }
            Button("Cancel") {
                waiting?.cancel()
                self.code = nil
            }
            .font(.footnote)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
        .transition(.perchSwap(reduceMotion: reduceMotion))
        .padding(.horizontal, 20)
    }

    private func begin() {
        message = nil
        copied = false
        waiting?.cancel()
        waiting = Task {
            do {
                let code = try await signIn.start()
                await MainActor.run { self.code = code }
                let token = try await signIn.waitForApproval(code)
                let repositories = try await signIn.repositories(token: token.accessToken)
                await MainActor.run {
                    // Prefer the build's notebook; otherwise the first repository the app can reach.
                    let pick = GitHubNotebook.preferred(in: repositories, name: configuration.preferredNotebook)
                    guard let pick else {
                        message = "Signed in, but Perch isn't installed on any repository yet. Install the Perch GitHub App on the repository that holds your notes, then try again."
                        self.code = nil
                        return
                    }
                    let parts = pick.split(separator: "/").map(String.init)
                    shell.owner = parts[0]
                    shell.repository = parts[1]
                    shell.branch = "main"
                    shell.connect(token: token.accessToken)
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    message = error.localizedDescription
                    code = nil
                }
            }
        }
    }
}

/// The keyboard shortcuts, for when the phone has a keyboard attached. They mirror the Mac's, and
/// holding ⌘ lists them wherever the system shows its shortcut overlay.
struct PhoneCommands: Commands {
    let shell: PhoneShell
    private var model: AppModel { shell.model }
    private var navigation: ShellState { shell.navigation }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            // In Notes a new note, in the folder being browsed; anywhere else a new task.
            Button("New Note or Task") {
                if navigation.destination == .notes {
                    _ = model.createNote(in: model.notesFolder)
                } else {
                    model.requestNewTask()
                }
            }
            .keyboardShortcut("n")
        }
        CommandMenu("Go") {
            Button("Tasks") { navigation.show(.tasks, model: model) }.keyboardShortcut("1")
            Button("Notes") { navigation.show(.notes, model: model) }.keyboardShortcut("2")
            Button("Agents") { navigation.show(.agents, model: model) }.keyboardShortcut("3")
            // ⌥⌘F as on the Mac. Plain ⌘F is left alone: in a note being edited it would otherwise
            // take the keyboard away to another screen.
            Button("Search") { navigation.showSearch(model: model) }.keyboardShortcut("f", modifiers: [.command, .option])
            Divider()
            // The task views keep the Mac's numbers. The Board follows them; on a narrow screen it shows Upcoming.
            Button("Today") { model.show(view: .today) }.keyboardShortcut("1", modifiers: [.command, .option])
            Button("Upcoming") { model.show(view: .upcoming) }.keyboardShortcut("2", modifiers: [.command, .option])
            Button("List") { model.show(view: .list) }.keyboardShortcut("3", modifiers: [.command, .option])
            Button("Calendar") { model.show(view: .calendar) }.keyboardShortcut("4", modifiers: [.command, .option])
            Button("Ready to Tick") { model.show(view: .ready) }.keyboardShortcut("5", modifiers: [.command, .option])
            Button("Board") { model.show(view: .board) }.keyboardShortcut("6", modifiers: [.command, .option])
            Divider()
            Button("Next Area") { stepScope(1) }.keyboardShortcut("]", modifiers: [.command, .option])
            Button("Previous Area") { stepScope(-1) }.keyboardShortcut("[", modifiers: [.command, .option])
            Divider()
            Button("Show or Hide Sidebar") { shell.toggleSidebar() }.keyboardShortcut("s", modifiers: [.command, .control])
            Button("Sync Now") { Task { await model.syncNow() } }.keyboardShortcut("s", modifiers: [.command, .shift])
        }
    }

    /// Moves the task scope one place along All, Work, Personal…, stopping at the ends.
    private func stepScope(_ offset: Int) {
        let scopes: [String?] = [nil] + model.visibleAreas.map { Optional($0) }
        let index = scopes.firstIndex(of: model.taskScope) ?? 0
        model.setScope(scopes[min(max(index + offset, 0), scopes.count - 1)])
    }
}

extension PhoneShell {
    /// Opens or folds the sidebar, as its own button does: the saved choice where the sidebar can stay
    /// open beside the content, the drawer where it can't. Does nothing on a phone-sized screen.
    func toggleSidebar() {
        guard let layout = navigation.layout, layout.isWide else { return }
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        withMotion(Motion.smooth, reduceMotion: reduceMotion) {
            if layout.canPinSidebar {
                let saved = UserDefaults.standard.string(forKey: SidebarPreference.storageKey).flatMap(SidebarPreference.init) ?? .expanded
                UserDefaults.standard.set(saved.toggled.rawValue, forKey: SidebarPreference.storageKey)
            } else {
                navigation.drawerOpen.toggle()
            }
        }
    }
}

/// The app once a notebook is open. It measures the room it has and draws one of two arrangements:
/// tabs with chip bars on a phone-sized screen, or the sidebar and panes on a wide one. Both read the
/// same model and the same `ShellState`, so going from one to the other (opening or closing a folding
/// phone, turning it) changes the arrangement and keeps the place.
struct PhoneRootView: View {
    @ObservedObject var shell: PhoneShell
    @ObservedObject private var model: AppModel
    @ObservedObject private var navigation: ShellState
    /// Tabs: the workspace, watched so a change of pane or tab redraws the sheet below.
    @ObservedObject private var workspace: WorkspaceStore
    @AppStorage(WorkspaceStore.settingKey) private var tabsOn = false
    /// The room the app was given, inside the safe area. Measured, never assumed from the device.
    @State private var available = CGSize(width: 390, height: 760)
    /// The whole screen, under the system's bars and the keyboard too. Whether this is a big screen is
    /// judged from it, so a column the system keeps for itself, or the keyboard, can't turn the
    /// sidebar back into tabs.
    @State private var scene = CGSize(width: 390, height: 844)
    @State private var showingSettings = false
    @AppStorage(SidebarPreference.storageKey) private var sidebar = SidebarPreference.expanded
    @AppStorage(FocusAvailability.hiddenKey) private var focusHidden = FocusAvailability.hiddenByDefault
    @Environment(\.perchTheme) private var theme

    init(shell: PhoneShell) {
        self.shell = shell
        model = shell.model
        navigation = shell.navigation
        workspace = shell.workspace
    }

    /// The size to lay out for: the room measured, or in a debug run the size named on the command line.
    private var size: CGSize {
        #if DEBUG
        if forcing, let forced = PhoneLaunch.forcedSize {
            return CGSize(width: max(forced.width - PhoneLaunch.forcedColumn, 200), height: forced.height)
        }
        #endif
        return available
    }

    /// The whole screen's size, to go with `size`.
    private var sceneSize: CGSize {
        #if DEBUG
        if forcing, let forced = PhoneLaunch.forcedSize { return forced }
        if let pretend = PhoneLaunch.pretendScene { return pretend }
        #endif
        return scene
    }

    #if DEBUG
    /// Whether the size named on the command line is in force. It can start or stop part-way through
    /// a run, to stand in for the phone being opened or closed.
    @State private var forcing = PhoneLaunch.value("-perchForceLayoutAfter") == nil
    #endif

    var body: some View {
        let size = size
        let sceneSize = sceneSize
        let layout = ShellLayout(
            width: size.width, height: size.height, sceneWidth: sceneSize.width, sceneHeight: sceneSize.height,
            allowsWide: theme.display.allowsWideLayouts, preference: sidebar, scale: Double(theme.display.scale)
        )
        let _ = (navigation.layout = layout)
        ZStack {
            // Fills exactly the safe area, so its size is the room the content has.
            Color.clear
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { available = proxy.size }
                            .onChange(of: proxy.size) { _, new in available = new }
                    }
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { scene = proxy.size }
                            .onChange(of: proxy.size) { _, new in scene = new }
                    }
                    .ignoresSafeArea()
                }
            arrangement(layout)
        }
        #if DEBUG
        .overlay(alignment: .bottom) {
            // -perchLayoutReadout: what was measured and what was chosen, for checking a real screen.
            if PhoneLaunch.showsReadout {
                Text("scene \(Int(sceneSize.width))x\(Int(sceneSize.height))  room \(Int(size.width))x\(Int(size.height))  \(String(describing: layout.navigation))  content \(Int(layout.contentWidth))\(layout.splitsContent ? " split" : "")")
                    .font(.caption2.monospaced()).padding(4).background(.black.opacity(0.75)).foregroundStyle(.white)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        #endif
        .modifier(RootOverlays(model: model))
        .sheet(item: Binding(
            // A sheet where there is no pane for the task. When a pane appears (the phone is unfolded)
            // the sheet closes and the pane shows the same task; the other way round, the sheet opens.
            get: { navigation.presentation(model: model)?.taskDetail == .sheet ? model.task(id: model.selectedTaskID) : nil },
            set: { task in
                // Closed by the user: forget the task. Closed because a pane took over: keep it.
                if task == nil, navigation.presentation(model: model)?.taskDetail == .pane { return }
                model.selectedTaskID = task?.id
            }
        )) { task in
            TaskDetailHost(model: model, task: task)
                .presentationDetents([.large])
                .presentationBackground(theme.background)
        }
        .sheet(isPresented: $showingSettings) { PhoneSettings(shell: shell) }
        .onChange(of: model.tasks) { shell.publishToSystem() }
        .onChange(of: model.route) { _, route in
            guard let route else { return }
            // Tabs: while the workspace is on screen a request opens in the focused tab.
            if workspace.isActive { workspace.take(route) } else { navigation.take(route, model: model, split: layout.splitsContent) }
        }
        // A file deleted here or on another device isn't left open.
        .onChange(of: model.files) { navigation.prune(model: model) }
        // A note renamed while it is open stays open, in whichever stack or pane it was showing.
        .onChange(of: model.lastRename) { _, rename in
            if let rename { navigation.renamed(rename.from, to: rename.to) }
        }
        // The drawer belongs to the rail. Back on tabs it is forgotten, so it doesn't spring open
        // the next time the phone is unfolded.
        .onChange(of: layout.isWide) { _, wide in
            if !wide, navigation.drawerOpen { navigation.drawerOpen = false }
        }
        .onChange(of: focusHidden, initial: true) { _, hidden in
            // Hiding the timer ends a session that is running, through the same path as Stop.
            if hidden, shell.focus.isRunning { shell.focus.stop() }
        }
        .onAppear {
            // Whatever the model started on has been turned into the first destination already.
            model.route = nil
            #if DEBUG
            if PhoneLaunch.settings != nil, !PhoneLaunch.settingsShown {
                PhoneLaunch.settingsShown = true
                showingSettings = true
            }
            if let after = PhoneLaunch.value("-perchForceLayoutAfter").flatMap(Double.init) {
                DispatchQueue.main.asyncAfter(deadline: .now() + after) { forcing = true }
            }
            if let until = PhoneLaunch.value("-perchForceLayoutUntil").flatMap(Double.init) {
                DispatchQueue.main.asyncAfter(deadline: .now() + until) { forcing = false }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                let tabs = (PhoneLaunch.value("-perchTabs") ?? "").split(separator: "|").compactMap { WorkspaceItem(token: String($0)) }
                let split = PhoneLaunch.value("-perchSplit").flatMap(WorkspaceItem.init(token:))
                if !tabs.isEmpty || split != nil { workspace.debugPreset(tabs: tabs, split: split) }
                if let path = PhoneLaunch.value("-perchOpen") { model.route = .file(path) }
                if let task = PhoneLaunch.value("-perchTask") { model.selectedTaskID = task }
            }
            #endif
        }
        .onOpenURL { url in
            // The widget's link: today's tasks, in every area.
            if url.host == "today" { model.showTasks(area: nil); model.show(view: .today) }
            if url.host == "task" { model.selectedTaskID = url.lastPathComponent }
        }
    }

    @ViewBuilder
    private func arrangement(_ layout: ShellLayout) -> some View {
        #if DEBUG
        if forcing, let forced = PhoneLaunch.forcedSize {
            // A debug run drawing another screen's layout: laid out at that size, then scaled to fit.
            let forced = size
            let scale = min(available.width / forced.width, available.height / forced.height, 1)
            // An overlay, so the larger layout doesn't change the room being measured. The pretend
            // screen has no system bars of its own, so nothing inside it makes room for this screen's.
            Color.clear.overlay {
                screen(layout)
                    .frame(width: forced.width, height: forced.height)
                    .scaleEffect(scale)
                    .ignoresSafeArea()
            }
        } else {
            screen(layout)
        }
        #else
        screen(layout)
        #endif
    }

    @ViewBuilder
    private func screen(_ layout: ShellLayout) -> some View {
        if layout.isWide {
            WideShellView(
                model: model, shell: navigation, layout: layout, preference: $sidebar,
                agents: AnyView(PhoneAgentsTab(model: model, shell: shell, navigation: navigation)),
                tasksAccessory: focusHidden ? nil : AnyView(PhoneFocusButton(focus: shell.focus, model: model)),
                workspace: tabsOn ? workspace : nil,
                openSettings: { showingSettings = true }
            )
        } else {
            tabs
        }
    }

    /// Choosing Tasks or Notes also tells the model, which remembers the section for the next launch.
    private var selectedTab: Binding<ShellDestination> {
        Binding(get: { navigation.destination }, set: { navigation.show($0, model: model) })
    }

    /// The phone-sized arrangement. The tabs carry the same names and icons as the sidebar's entries.
    private var tabs: some View {
        TabView(selection: selectedTab) {
            PhoneTasksTab(model: model, shell: shell, showsFocus: !focusHidden, openSettings: { showingSettings = true })
                .tabItem { tabLabel(.tasks) }.tag(ShellDestination.tasks)
            NotesStackView(model: model, shell: navigation)
                .tabItem { tabLabel(.notes) }.tag(ShellDestination.notes)
            PhoneAgentsTab(model: model, shell: shell, navigation: navigation)
                .tabItem { tabLabel(.agents) }.tag(ShellDestination.agents)
            SearchStackView(model: model, shell: navigation)
                .tabItem { tabLabel(.search) }.tag(ShellDestination.search)
        }
    }

    private func tabLabel(_ destination: ShellDestination) -> some View {
        Label(destination.title, systemImage: destination.symbol)
    }
}

/// The Tasks tab: the areas pinned under the navigation bar, the view switcher under them, then the view.
struct PhoneTasksTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var shell: PhoneShell
    var showsFocus: Bool
    var openSettings: () -> Void

    var body: some View {
        NavigationStack {
            TasksSectionView(model: model)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if showsFocus {
                        ToolbarItem(placement: .topBarLeading) { PhoneFocusButton(focus: shell.focus, model: model) }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: openSettings) { Image(systemName: "gearshape") }
                            .accessibilityLabel("Settings")
                    }
                }
        }
    }
}

struct PhoneSettings: View {
    @ObservedObject var shell: PhoneShell
    @State private var relayToken = ""
    @State private var path: [String]
    @AppStorage(FocusAvailability.hiddenKey) private var focusHidden = FocusAvailability.hiddenByDefault
    @Environment(\.dismiss) private var dismiss
    @Environment(\.perchTheme) private var theme

    init(shell: PhoneShell) {
        self.shell = shell
        #if DEBUG
        _path = State(initialValue: PhoneLaunch.settings.map { PhoneLaunch.settingsScreens.contains($0) ? [$0] : [] } ?? [])
        #else
        _path = State(initialValue: [])
        #endif
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section("Appearance") {
                    NavigationLink(value: "theme") {
                        LabeledContent("Theme", value: ThemeStore.shared.selectedID == ThemePresets.systemID ? "System" : theme.name)
                    }
                    NavigationLink(value: "display") {
                        LabeledContent("Display", value: theme.display.metrics.size.title)
                    }
                    NavigationLink("Reading", value: "reading")
                    NavigationLink("Editing", value: "editing")
                }
                .listRowBackground(theme.surface)
                Section("Tasks") {
                    NavigationLink("Areas", value: "areas")
                }
                .listRowBackground(theme.surface)
                Section {
                    Toggle("Hide the focus timer", isOn: $focusHidden)
                } header: {
                    Text("Features")
                } footer: {
                    Text("Takes the focus timer out of the toolbar and leaves focus time out of Insights. Turn this off to bring them back.")
                }
                .listRowBackground(theme.surface)
                ExperimentalSettings()
                    .listRowBackground(theme.surface)
                Section("Repository") {
                    LabeledContent("Repository", value: "\(shell.owner)/\(shell.repository)")
                    LabeledContent("Branch", value: shell.branch)
                    SyncStatusLine(model: shell.model)
                    Button("Sync now") { Task { await shell.model.syncNow() } }
                }
                .listRowBackground(theme.surface)
                Section {
                    RelayStatusLine(model: shell.model)
                    TextField("Relay address", text: $shell.relayURL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("App token", text: $relayToken)
                    Button(shell.model.relayStatus.isConnected ? "Reconnect" : "Connect") {
                        shell.connectRelay(token: relayToken.trimmingCharacters(in: .whitespacesAndNewlines))
                        relayToken = ""
                    }
                } header: {
                    Text("Agents")
                } footer: {
                    Text("Shows which agents are working in your notebook. Perch only reads from the Relay.")
                }
                .listRowBackground(theme.surface)
                Section("More") {
                    NavigationLink("Insights", value: "insights")
                    NavigationLink("Import from Todoist", value: "import")
                }
                .listRowBackground(theme.surface)
                Section {
                    Button("Disconnect GitHub", role: .destructive) {
                        shell.disconnect()
                        dismiss()
                    }
                } footer: {
                    Text("This removes the token. Your notes stay on GitHub and in this app.")
                }
                .listRowBackground(theme.surface)
            }
            .perchScreenBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(for: String.self) { screen in
                switch screen {
                case "areas":
                    ScrollView { AreaEditor(model: shell.model, embedded: true).padding(16) }
                        .perchScreenBackground()
                        .navigationTitle("Areas")
                        .navigationBarTitleDisplayMode(.inline)
                case "theme": ThemeSettingsView()
                case "display": DisplaySettingsView()
                case "reading": ReadingSettingsView()
                case "editing": EditingSettingsView()
                case "insights": InsightsHost(model: shell.model)
                case "import": ImportHost(model: shell.model)
                default: EmptyView()
                }
            }
        }
        .presentationBackground(theme.background)
    }
}

struct PhoneFocusButton: View {
    @ObservedObject var focus: PhoneFocus
    @ObservedObject var model: AppModel

    var body: some View {
        if focus.isRunning {
            Menu {
                if focus.endDate != nil { Button("Add 5 minutes") { focus.addFive() } }
                Button("Stop", role: .destructive) { focus.stop() }
            } label: {
                if let end = focus.endDate {
                    Text(timerInterval: Date()...max(end, Date()), countsDown: true).monospacedDigit().font(.callout)
                } else if let start = focus.startDate {
                    Text(start, style: .timer).monospacedDigit().font(.callout)
                }
            }
            .accessibilityLabel("Focus timer")
        } else {
            Menu {
                let title = model.todayTasks.first?.title ?? "Focus"
                ForEach([25, 45, 60], id: \.self) { minutes in
                    Button("\(minutes) minutes") { focus.start(minutes: minutes, taskTitle: title) }
                }
                Button("Count up") { focus.start(minutes: nil, taskTitle: title) }
            } label: { Image(systemName: "timer") }
            .accessibilityLabel("Start a focus timer")
        }
    }
}

struct PhoneAgentsTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var shell: PhoneShell
    /// What is opened from the activity list is kept here, so it survives a change of layout.
    @ObservedObject var navigation: ShellState
    @Environment(\.perchTheme) private var theme

    var body: some View {
        NavigationStack(path: $navigation.agentsPath) {
            ScrollView {
                // Two columns when there is room, as on an unfolded or sideways phone.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        hereNow.frame(minWidth: 280, maxWidth: 340)
                        activity.frame(minWidth: 320)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        hereNow
                        activity
                    }
                }
                .padding(16)
            }
            .perchScreenBackground()
            .refreshable { await model.syncNow() }
            .navigationTitle("Agents")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { destination in
                switch destination {
                case let .file(file): FileScreen(model: model, path: file)
                case let .folder(folder): FolderHost(model: model, path: folder, open: { navigation.agentsPath.append($0) })
                default: EmptyView()
                }
            }
        }
        // A link in a task opened from the activity list opens here, in place, so Back returns to the
        // list: `ShellState.take` adds it to this stack.
    }

    private var hereNow: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Here now")
            if model.agents.isEmpty {
                EmptyState(
                    symbol: "person.2", title: "No agents connected",
                    message: "Agents working in your notebook show up here with what they are doing. Add a Relay address in Settings to see them."
                )
                .frame(minHeight: 220)
            }
            ForEach(model.agents) { agent in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(agent.isActive ? theme.success : theme.textMuted).frame(width: 9, height: 9).padding(.top, 6)
                        .accessibilityLabel(agent.isActive ? "Active" : "Idle")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agent.name).font(.body.weight(.semibold)).foregroundStyle(theme.text)
                        Text(agent.status).font(.callout).foregroundStyle(theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .motion(Motion.smooth, value: model.agents.map(\.id))
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 4) {
            heading("Recent activity")
            ActivityRowsHost(model: model)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heading(_ text: String) -> some View {
        Text(text.uppercased()).font(.caption2.weight(.semibold)).kerning(0.5).foregroundStyle(theme.textMuted)
            .accessibilityAddTraits(.isHeader)
    }
}

struct SyncStatusLine: View {
    @ObservedObject var model: AppModel
    @Environment(\.perchTheme) private var theme

    var body: some View {
        LabeledContent("Sync") {
            switch model.syncPhase {
            case .off: Text("Off")
            case let .idle(date): Text(date.map { $0.formatted(date: .omitted, time: .shortened) } ?? "Ready")
            case .syncing: ProgressView()
            case let .failed(message): Text(message).foregroundStyle(theme.danger)
            }
        }
        .motion(Motion.smooth, value: model.syncPhase)
    }
}
