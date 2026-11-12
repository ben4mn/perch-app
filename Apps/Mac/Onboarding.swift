import AppKit
import PerchKit
import PerchUI
import SwiftUI

// The Mac's first run. In a build with a GitHub App: sign in with GitHub, then choose a notebook, either a
// repository cloned from GitHub or a Git repository already on this Mac. In a build without one (the public
// build, see Config/Perch.xcconfig): choose a folder on this Mac, no sign-in. `FirstRun` decides which.
// Each screen is a plain view of its state (drawn by snapshots with stand-in replies) inside a small view
// that does the work.

/// Signs in with a short code, as the iPhone does: Perch shows the code, you enter it on GitHub.
struct SignInView: View {
    @ObservedObject var shell: MacShell
    @State private var code: GitHubDeviceSignIn.Code?
    @State private var waiting: Task<Void, Never>?
    @State private var message: String?
    @State private var copied = false

    var body: some View {
        SignInScreen(
            code: code, message: message, copied: copied, configured: shell.configuration.signsInWithGitHub,
            begin: begin,
            copyAndOpen: {
                guard let code else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code.userCode, forType: .string)
                NSWorkspace.shared.open(code.verificationURL)
                copied = true
            },
            cancel: {
                waiting?.cancel()
                code = nil
            }
        )
        .onDisappear { waiting?.cancel() }
    }

    private func begin() {
        message = nil
        copied = false
        waiting?.cancel()
        waiting = Task { @MainActor in
            do {
                let signIn = GitHubDeviceSignIn(clientID: shell.configuration.gitHubClientID)
                let code = try await signIn.start()
                self.code = code
                let token = try await signIn.waitForApproval(code)
                try await shell.signedIn(with: token)
            } catch is CancellationError {
            } catch {
                message = error.localizedDescription
                code = nil
            }
        }
    }
}

struct SignInScreen: View {
    let code: GitHubDeviceSignIn.Code?
    let message: String?
    let copied: Bool
    let configured: Bool
    let begin: () -> Void
    let copyAndOpen: () -> Void
    let cancel: () -> Void
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 18) {
            Image("PerchMark").resizable().scaledToFit().frame(width: 104, height: 104)
            VStack(spacing: 6) {
                Text("Welcome to Perch").font(.perchStyle(.title).bold()).foregroundStyle(theme.text)
                Text("Sign in with GitHub to use Perch. Your notes and tasks stay in your own GitHub repository.")
                    .multilineTextAlignment(.center).foregroundStyle(theme.textSecondary).frame(maxWidth: 420)
            }
            if let code {
                codeCard(code)
            } else {
                Button(action: begin) {
                    Label("Sign in with GitHub", systemImage: "person.badge.key.fill").padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!configured)
                .keyboardShortcut(.defaultAction)
            }
            if !configured {
                Text("This build has no GitHub App set up (PerchGitHubClientID is empty).")
                    .font(.perchStyle(.callout)).foregroundStyle(theme.danger)
            }
            if let message {
                Text(message).font(.perchStyle(.callout)).foregroundStyle(theme.danger)
                    .multilineTextAlignment(.center).frame(maxWidth: 420)
            }
            Text("Perch signs in through its own GitHub App, so it only sees the repositories you install it on.")
                .font(.perchStyle(.caption)).foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.center).frame(maxWidth: 380)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
        .motion(Motion.smooth, value: code?.userCode)
        .riseIn()
    }

    private func codeCard(_ code: GitHubDeviceSignIn.Code) -> some View {
        VStack(spacing: 12) {
            Text("Enter this code on GitHub").font(.perchStyle(.subheadline)).foregroundStyle(theme.textSecondary)
            Text(code.userCode)
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .tracking(4)
                .foregroundStyle(theme.text)
                .textSelection(.enabled)
            Button(action: copyAndOpen) {
                Label(copied ? "Code copied, GitHub is open" : "Copy Code and Open GitHub",
                      systemImage: copied ? "checkmark" : "arrow.up.forward.app")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for you to approve on GitHub…").font(.perchStyle(.footnote)).foregroundStyle(theme.textSecondary)
            }
            Button("Cancel", action: cancel).buttonStyle(.link).font(.perchStyle(.footnote))
        }
        .padding(22)
        .frame(width: 380)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
        .transition(.perchSwap(reduceMotion: reduceMotion))
    }
}

/// What the GitHub half of the chooser knows about the repositories Perch can reach.
enum RepositoryList: Equatable {
    case loading
    case failed(String)
    case loaded(GitHubDeviceSignIn.Reach)
}

/// Picks the notebook: a repository from GitHub, cloned here, or a Git repository already on this Mac.
/// Fills the window on first run; a sheet with Cancel when you switch notebooks.
struct NotebookChooserView: View {
    @ObservedObject var shell: MacShell
    var onCancel: (() -> Void)?
    @State private var list = RepositoryList.loading
    @State private var selected: String?
    @State private var parent = GitHubNotebook.defaultParent
    @State private var placement: GitHubNotebook.Placement?
    @State private var busy: String?
    @State private var message: String?

    private var sources: [FirstRun.Source] { FirstRun.sources(shell.configuration) }

    var body: some View {
        NotebookChooserScreen(
            sources: sources,
            login: shell.profile?.login ?? "",
            list: list, selected: $selected, placement: placement, busy: busy, message: message,
            refresh: { Task { await load() } },
            changeFolder: changeFolder,
            openRepository: openRepository,
            chooseLocal: {
                message = nil
                if let problem = shell.chooseLocalRepository() { message = problem }
            },
            signOut: { shell.signOut() },
            cancel: onCancel
        )
        // Only a build that signs in with GitHub has repositories to look up.
        .task { if sources.contains(.gitHub) { await load() } }
        .onChange(of: selected) { _, _ in updatePlacement() }
        .onChange(of: parent) { _, _ in updatePlacement() }
    }

    private func load() async {
        list = .loading
        do {
            let reach = try await shell.github.reach()
            list = .loaded(reach)
            if selected == nil || !reach.repositories.contains(selected!) {
                // Prefer the build's notebook; otherwise the first repository Perch can reach, as the iPhone does.
                selected = GitHubNotebook.preferred(in: reach.repositories, name: shell.configuration.preferredNotebook)
            }
            updatePlacement()
        } catch {
            list = .failed(Self.describe(error))
        }
    }

    /// On the Mac a refused token is fixed by signing in again, not in Settings as on the iPhone.
    static func describe(_ error: Error) -> String {
        if error as? SyncError == .authentication { return "GitHub turned down Perch's sign-in. Sign out, then sign in again." }
        return error.localizedDescription
    }

    private func updatePlacement() {
        placement = selected.map { GitHubNotebook.placement(for: $0, in: parent) }
    }

    private func changeFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose where Perch puts the clone. It goes in a new folder named after the repository."
        if FileManager.default.fileExists(atPath: parent.path) { panel.directoryURL = parent }
        if panel.runModal() == .OK, let url = panel.url { parent = url }
    }

    private func openRepository() {
        guard let selected, busy == nil else { return }
        message = nil
        if case .clone = placement { busy = "Cloning \(selected)…" } else { busy = "Opening \(selected)…" }
        Task { @MainActor in
            do {
                try await shell.openFromGitHub(selected, in: parent)
            } catch {
                message = Self.describe(error)
            }
            busy = nil
            updatePlacement()
        }
    }
}

struct NotebookChooserScreen: View {
    /// What this build offers: GitHub and a Git repository here, or (with no GitHub App) any folder here.
    let sources: [FirstRun.Source]
    let login: String
    let list: RepositoryList
    @Binding var selected: String?
    let placement: GitHubNotebook.Placement?
    let busy: String?
    let message: String?
    let refresh: () -> Void
    let changeFolder: () -> Void
    let openRepository: () -> Void
    let chooseLocal: () -> Void
    let signOut: () -> Void
    let cancel: (() -> Void)?
    @Environment(\.perchTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if signsIn { gitHubCard }
                localCard
                if let message {
                    Text(message).font(.perchStyle(.callout)).foregroundStyle(theme.danger).fixedSize(horizontal: false, vertical: true)
                }
                if let cancel {
                    HStack {
                        Spacer()
                        Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background.ignoresSafeArea())
        .disabled(busy != nil)
        .riseIn()
    }

    private var signsIn: Bool { sources.contains(.gitHub) }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image("PerchMark").resizable().scaledToFit().frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(signsIn ? "Choose a notebook" : "Welcome to Perch").font(.perchStyle(.title2).bold()).foregroundStyle(theme.text)
                Text(signsIn ? (login.isEmpty ? "Signed in to GitHub" : "Signed in to GitHub as @\(login)")
                             : "Perch keeps your notes and tasks as Markdown files in a folder on this Mac.")
                    .font(.perchStyle(.callout)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if signsIn { Button("Sign Out", action: signOut).buttonStyle(.link) }
        }
    }

    private var gitHubCard: some View {
        card(symbol: "arrow.down.circle", title: "Clone from GitHub",
             detail: "Perch copies the repository to this Mac and keeps it in sync, signed in as you.") {
            switch list {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking up the repositories Perch can reach…").foregroundStyle(theme.textSecondary)
                }
            case let .failed(problem):
                VStack(alignment: .leading, spacing: 8) {
                    Text(problem).foregroundStyle(theme.danger).fixedSize(horizontal: false, vertical: true)
                    Button("Try Again", action: refresh)
                }
            case let .loaded(reach) where reach.repositories.isEmpty:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Perch can't reach any repositories yet. Install its GitHub App on the repository that holds your notes, then refresh.")
                        .foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        if let url = reach.installURL { Link("Add Repositories on GitHub", destination: url) }
                        Button("Refresh", action: refresh)
                    }
                }
            case let .loaded(reach):
                repositoryList(reach)
            }
        }
    }

    private func repositoryList(_ reach: GitHubDeviceSignIn.Reach) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                ForEach(reach.repositories, id: \.self) { name in
                    repositoryRow(name)
                    if name != reach.repositories.last { Divider().overlay(theme.border) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.background))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
            if let placement {
                HStack(spacing: 6) {
                    Image(systemName: "folder").foregroundStyle(theme.textMuted)
                    Text(placementText(placement)).font(.perchStyle(.callout)).foregroundStyle(theme.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    if case .clone = placement { Button("Change…", action: changeFolder) }
                }
            }
            HStack(spacing: 12) {
                // While a clone runs, its progress takes the place of the links.
                if let busy {
                    ProgressView().controlSize(.small)
                    Text(busy).font(.perchStyle(.callout)).foregroundStyle(theme.textSecondary).lineLimit(1).truncationMode(.middle)
                } else {
                    if let url = reach.installURL {
                        Link("Add or remove repositories", destination: url).font(.perchStyle(.callout)).fixedSize()
                    }
                    Button("Refresh", action: refresh).buttonStyle(.link).font(.perchStyle(.callout)).fixedSize()
                }
                Spacer(minLength: 12)
                Button(primaryTitle, action: openRepository)
                    .buttonStyle(.borderedProminent)
                    .disabled(selected == nil || busy != nil)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var primaryTitle: String {
        if case .open = placement { return "Open Notebook" }
        return "Clone and Open"
    }

    private func repositoryRow(_ name: String) -> some View {
        let parts = name.split(separator: "/", maxSplits: 1).map(String.init)
        let isSelected = selected == name
        return Button { selected = name } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? theme.accent : theme.textMuted)
                Text(parts.count == 2 ? parts[0] + " / " : "").foregroundStyle(theme.textSecondary)
                    + Text(parts.last ?? name).bold().foregroundStyle(theme.text)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var localCard: some View {
        if sources.contains(.anyFolder) {
            card(symbol: "folder", title: "Open a notebook folder",
                 detail: "Pick a folder of notes, or a new empty folder to start one. If the folder is a Git repository, Perch commits and syncs it with the Git login that folder already uses. Any other folder works too, without sync.") {
                Button("Choose Folder…", action: chooseLocal)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            card(symbol: "internaldrive", title: "Use a Git repo on this Mac",
                 detail: "Pick a folder that is already a Git clone, such as one NotesHub uses. Perch syncs it with the Git login that folder already uses.") {
                Button("Choose Folder…", action: chooseLocal)
            }
        }
    }

    private func card<Content: View>(symbol: String, title: String, detail: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(theme.accent).frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.perchStyle(.headline)).foregroundStyle(theme.text)
                    Text(detail).font(.perchStyle(.callout)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            content().padding(.leading, 38)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
    }

    private func placementText(_ placement: GitHubNotebook.Placement) -> String {
        switch placement {
        case let .clone(url): return "Clones into \(Self.tilde(url))"
        case let .open(url): return "Opens the clone already at \(Self.tilde(url))"
        }
    }

    static func tilde(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}

#if DEBUG
/// The first-run screens for snapshots, with stand-in GitHub replies: onboarding:signin|code|choose|empty|cloning|failed,
/// and onboarding:local, the first run of a build with no GitHub App (FirstRun.sources), which offers a folder.
enum OnboardingSnapshots {
    @MainActor
    static func view(_ name: String) -> AnyView {
        let code = GitHubDeviceSignIn.Code(userCode: "WDJB-MJHT", verificationURL: URL(string: "https://github.com/login/device")!,
                                           deviceCode: "", interval: 5, expiresAt: Date().addingTimeInterval(900))
        let reach = GitHubDeviceSignIn.Reach(repositories: ["someone/notes", "someone/perch"], appSlug: "perch")
        let target = GitHubNotebook.defaultParent.appendingPathComponent("notes")
        func chooser(_ list: RepositoryList, busy: String? = nil, message: String? = nil,
                     sources: [FirstRun.Source] = [.gitHub, .gitFolder]) -> AnyView {
            AnyView(NotebookChooserScreen(
                sources: sources,
                login: "someone", list: list, selected: .constant("someone/notes"), placement: .clone(target), busy: busy, message: message,
                refresh: {}, changeFolder: {}, openRepository: {}, chooseLocal: {}, signOut: {}, cancel: nil))
        }
        switch name {
        case "code": return AnyView(SignInScreen(code: code, message: nil, copied: false, configured: true, begin: {}, copyAndOpen: {}, cancel: {}))
        case "choose": return chooser(.loaded(reach))
        case "empty": return chooser(.loaded(.init(repositories: [], appSlug: "perch")))
        case "cloning": return chooser(.loaded(reach), busy: "Cloning someone/notes…")
        case "failed": return chooser(.failed(NotebookChooserView.describe(SyncError.authentication)))
        case "local": return chooser(.loading, sources: FirstRun.sources(.neutral))
        default: return AnyView(SignInScreen(code: nil, message: nil, copied: false, configured: true, begin: {}, copyAndOpen: {}, cancel: {}))
        }
    }
}
#endif
