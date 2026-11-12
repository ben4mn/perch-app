import AppKit
import PerchKit
import PerchUI
import SwiftUI

/// Keeps Perch up to date from its GitHub releases. It looks when Perch opens and every few hours after; with
/// Install updates automatically on (the default), it downloads a new version in the background and moves to
/// it once nobody has used Perch for a minute, or when Perch is quit, reopening in the background. The new
/// copy is put in place only at that moment, so the running app never mixes its code with the new copy's
/// files. With it off, it offers the update instead. See AutoUpdate.
@MainActor
final class UpdateCenter: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate(Date)
        case available(UpdateChecker.Update)
        /// GitHub won't show the Perch repository to this account. The link installs Perch's GitHub App on it.
        case noAccess(URL?)
        case installing
        /// Downloaded, and waiting for a quiet moment to restart onto it.
        case ready(UpdateChecker.Update)
        case failed(String)
    }

    static let checkOnLaunchKey = "updatesCheckOnLaunch"
    static let installAutomaticallyKey = "updatesInstallAutomatically"
    static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "" }

    @Published private(set) var status = Status.idle
    /// An update found by the check at launch, offered once.
    @Published var offer: UpdateChecker.Update?

    private let github: GitHubSession
    /// Nil when this build has no update source (Config/Perch.xcconfig): then nothing is ever checked.
    private let checker: UpdateChecker?
    /// "owner/name" of the repository whose releases update Perch.
    var repository: String? { checker?.repository }
    var isEnabled: Bool { checker != nil }
    private var installsAutomatically: Bool { UserDefaults.standard.object(forKey: Self.installAutomaticallyKey) as? Bool ?? true }
    private var lastCheck: Date?
    /// A downloaded update waiting for its moment, and since when Perch has been behind other apps.
    private var waiting: (update: UpdateChecker.Update, zip: URL)?
    private var inactiveSince: Date?
    private var watcher: Task<Void, Never>?

    init(github: GitHubSession, repository: String?) {
        self.github = github
        checker = repository.map { UpdateChecker(repository: $0) }
    }

    /// The check at launch: quiet unless it finds something, and only if it's turned on. It also starts the
    /// look every few hours, and the wait for a quiet moment to restart onto a downloaded update.
    func checkAtLaunch() {
        guard isEnabled else { return }
        watch()
        guard UserDefaults.standard.object(forKey: Self.checkOnLaunchKey) as? Bool ?? true else { return }
        Task { await check(announce: true) }
    }

    private func watch() {
        guard watcher == nil else { return }
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.inactiveSince = Date() }
        }
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.inactiveSince = nil }
        }
        if !NSApp.isActive { inactiveSince = Date() }
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                await self?.tick()
            }
        }
    }

    private func tick() async {
        if let waiting {
            if AutoUpdate.canRestart(isActive: NSApp.isActive, inactiveSince: inactiveSince, now: Date()) { restart(onto: waiting) }
        } else if installsAutomatically, AutoUpdate.dueForCheck(lastCheck: lastCheck, now: Date()) {
            await check(announce: false)
        }
    }

    func check(announce: Bool) async {
        guard let checker, status != .checking, status != .installing else { return }
        if case .ready = status { return }
        lastCheck = Date()
        status = .checking
        do {
            let token = try await github.accessToken()
            switch try await checker.check(current: Self.currentVersion, token: token) {
            case .upToDate:
                status = .upToDate(Date())
            case .noAccess:
                status = .noAccess(try? await github.reach().installURL)
            case let .available(update):
                if installsAutomatically {
                    await prepare(update)
                } else {
                    status = .available(update)
                    if announce { offer = update }
                }
            }
        } catch {
            status = .failed(Self.describe(error))
        }
    }

    func install(_ update: UpdateChecker.Update) async {
        guard let checker else { return }
        offer = nil
        status = .installing
        do {
            let token = try await github.accessToken()
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("perch-update", isDirectory: true)
            let zip = try await checker.download(update, token: token, into: folder)
            try UpdateInstaller.install(zip: zip, replacing: Bundle.main.bundleURL, bundleID: Bundle.main.bundleIdentifier ?? "", version: update.version)
            try? FileManager.default.removeItem(at: zip)
            relaunch()
        } catch {
            status = .failed(Self.describe(error))
        }
    }

    /// Downloads an update to put in place at the next quiet moment.
    private func prepare(_ update: UpdateChecker.Update) async {
        guard let checker else { return }
        do {
            let token = try await github.accessToken()
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("perch-update", isDirectory: true)
            let zip = try await checker.download(update, token: token, into: folder)
            waiting = (update, zip)
            status = .ready(update)
        } catch {
            status = .failed(Self.describe(error))
        }
    }

    /// Puts the downloaded copy in place and reopens it, in the background unless asked from Settings.
    func restartNow() {
        guard let waiting else { return }
        restart(onto: waiting, inBackground: false)
    }

    private func restart(onto ready: (update: UpdateChecker.Update, zip: URL), inBackground: Bool = true) {
        waiting = nil
        do {
            try UpdateInstaller.install(zip: ready.zip, replacing: Bundle.main.bundleURL, bundleID: Bundle.main.bundleIdentifier ?? "", version: ready.update.version)
            try? FileManager.default.removeItem(at: ready.zip)
            relaunch(inBackground: inBackground)
        } catch {
            status = .failed(Self.describe(error))
        }
    }

    /// When Perch quits with an update downloaded: put it in place, so the next launch is the new version.
    func installOnQuit() {
        guard let ready = waiting else { return }
        waiting = nil
        try? UpdateInstaller.install(zip: ready.zip, replacing: Bundle.main.bundleURL, bundleID: Bundle.main.bundleIdentifier ?? "", version: ready.update.version)
    }

    /// Opens the newly installed copy a moment after this one quits.
    private func relaunch(inBackground: Bool = false) {
        let opener = Process()
        opener.executableURL = URL(fileURLWithPath: "/bin/sh")
        opener.arguments = ["-c", inBackground ? "sleep 1; /usr/bin/open -g \"$PERCH_APP\"" : "sleep 1; /usr/bin/open \"$PERCH_APP\""]
        opener.environment = ["PERCH_APP": Bundle.main.bundleURL.path]
        try? opener.run()
        NSApp.terminate(nil)
    }

    private static func describe(_ error: Error) -> String {
        if error as? SyncError == .authentication { return "GitHub turned down Perch's sign-in. Sign out, then sign in again." }
        return error.localizedDescription
    }

    /// The changelog built into this copy of Perch.
    static var changelog: [Changelog.Release] {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Changelog.parse(text)
    }
}

/// Settings, Updates: the version, whether there's a newer one, and what changed in each release.
struct UpdatesSettings: View {
    @ObservedObject var updates: UpdateCenter
    @AppStorage(UpdateCenter.checkOnLaunchKey) private var checkOnLaunch = true
    @AppStorage(UpdateCenter.installAutomaticallyKey) private var installAutomatically = true

    var body: some View {
        if updates.isEnabled { checks } else {
            // A build with no update source shows its version and changelog, and offers nothing to check.
            Section("Version") {
                LabeledContent("Version") { version }
                Text("This copy of Perch was built from source and doesn't check for updates. To update it, build a newer copy.")
                    .font(.perchStyle(.caption)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        changelog
    }

    private var version: some View {
        Text(UpdateCenter.build.isEmpty ? UpdateCenter.currentVersion : "\(UpdateCenter.currentVersion) (\(UpdateCenter.build))")
            .textSelection(.enabled)
    }

    @ViewBuilder private var checks: some View {
        Section("Updates") {
            LabeledContent("Version") { version }
            status
            HStack {
                Button("Check Now") { Task { await updates.check(announce: false) } }
                    .disabled(updates.status == .checking || updates.status == .installing)
                if case let .available(update) = updates.status {
                    Button("Install \(update.version.description) and Restart") { Task { await updates.install(update) } }
                        .buttonStyle(.borderedProminent)
                }
                if case .ready = updates.status {
                    Button("Restart Now") { updates.restartNow() }.buttonStyle(.borderedProminent)
                }
            }
            Toggle("Check for updates when Perch opens", isOn: $checkOnLaunch)
            Toggle("Install updates automatically", isOn: $installAutomatically)
            Text("Perch looks every few hours, downloads a new version in the background, and moves to it when you haven't used it for a minute or when you quit it.")
                .font(.perchStyle(.caption)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        if case let .available(update) = updates.status, !update.notes.isEmpty {
            Section("New in \(update.version.description)") {
                ForEach(Array(lines(update.notes).enumerated()), id: \.offset) { _, line in Text(LocalizedStringKey(line)) }
            }
        }
    }

    private var changelog: some View {
        Section("Changelog") {
            ForEach(UpdateCenter.changelog) { release in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(release.version).font(.perchStyle(.headline))
                        if let date = release.date { Text(date).font(.perchStyle(.caption)).foregroundStyle(.secondary) }
                        if release.version == UpdateCenter.currentVersion {
                            Text("This version").font(.perchStyle(.caption)).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(Array(release.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•").foregroundStyle(.secondary)
                            Text(LocalizedStringKey(item)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch updates.status {
        case .idle:
            Text("Perch checks GitHub for a newer release.").foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Checking…") }
        case let .upToDate(date):
            Text("Perch is up to date. Checked \(date.formatted(date: .omitted, time: .shortened)).").foregroundStyle(.secondary)
        case let .available(update):
            Text("Perch \(update.version.description) is available.").bold()
        case let .noAccess(link):
            VStack(alignment: .leading, spacing: 4) {
                let repository = updates.repository ?? "Perch"
                Text("Perch can't see its own releases yet. Install Perch's GitHub App on the \(repository) repository, then check again.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let link { Link("Add \(repository) on GitHub", destination: link) }
            }
        case .installing:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Downloading and installing. Perch reopens when it's done.") }
        case let .ready(update):
            Text("Perch \(update.version.description) is downloaded. It moves to it by itself when you aren't using Perch, or when you quit.")
                .fixedSize(horizontal: false, vertical: true)
        case let .failed(message):
            Text(message).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func lines(_ notes: String) -> [String] {
        notes.components(separatedBy: .newlines).map { $0.hasPrefix("- ") ? "• " + $0.dropFirst(2) : $0 }.filter { !$0.isEmpty }
    }
}
