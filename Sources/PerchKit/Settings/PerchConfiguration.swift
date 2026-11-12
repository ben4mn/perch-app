import Foundation

/// What a build of Perch was set up with: the values that differ between the maintainer's own build and a
/// build made from the public source. `Config/Perch.xcconfig` sets public-safe defaults and
/// `Config/Private.xcconfig`, when it is there, overrides them; each app's Info.plist carries the result.
/// Nothing in the Swift package names a person, an account or a server. An empty value turns its feature off.
public struct PerchConfiguration: Equatable, Sendable {
    /// The Info.plist keys, one per value.
    public enum Key {
        public static let gitHubClientID = "PerchGitHubClientID"
        public static let updateRepository = "PerchUpdateRepository"
        public static let keychainService = "PerchKeychainService"
        public static let standardAreas = "PerchStandardAreas"
        public static let preferredNotebook = "PerchPreferredNotebook"
        public static let ownerID = "PerchOwnerID"
        public static let otherOwners = "PerchOtherOwners"
        public static let agentMarks = "PerchAgentMarks"
        public static let defaultRepositoryOwner = "PerchDefaultRepositoryOwner"
    }

    /// The client ID of the GitHub App Perch signs in through. Empty: this build has no GitHub sign-in.
    public var gitHubClientID: String
    /// "owner/name" of the GitHub repository whose releases update the Mac app. Empty: no update checks.
    public var updateRepository: String
    /// The Keychain service Perch's secrets are kept under.
    public var keychainService: String
    /// The areas a notebook starts with, in this order, when their top-level folders exist.
    public var standardAreas: [String]
    /// The repository name preferred when choosing a notebook from GitHub. Empty: the first one offered.
    public var preferredNotebook: String
    /// The `owner` of the tasks of the person using Perch, and the author of what they write in a task's log.
    public var ownerID: String
    /// Owners offered for a task besides the person using Perch and the owners already in the notebook.
    public var otherOwners: [String]
    /// The agents drawn with a mark of their own, by lower-cased name; any other agent shows its initial.
    public var agentMarks: [String: AgentHistory.Mark]
    /// The GitHub account the iPhone offers first for the notebook repository. Empty: the user types it.
    public var defaultRepositoryOwner: String

    public init(
        gitHubClientID: String = "",
        updateRepository: String = "",
        keychainService: String = "perch",
        standardAreas: [String] = ["Personal"],
        preferredNotebook: String = "",
        ownerID: String = "me",
        otherOwners: [String] = ["pair", "claude"],
        agentMarks: [String: AgentHistory.Mark] = ["claude": .claude],
        defaultRepositoryOwner: String = ""
    ) {
        self.gitHubClientID = gitHubClientID
        self.updateRepository = updateRepository
        self.keychainService = keychainService
        self.standardAreas = standardAreas
        self.preferredNotebook = preferredNotebook
        self.ownerID = ownerID
        self.otherOwners = otherOwners
        self.agentMarks = agentMarks
        self.defaultRepositoryOwner = defaultRepositoryOwner
    }

    /// Reads the values from an Info.plist dictionary. A key that is missing, empty, or still holds an
    /// unexpanded `$(SETTING)` counts as not set. Lists are comma-separated; agent marks are a list of
    /// `name=mark` (`claude=claude, robin=house`), where a mark is one of `AgentHistory.Mark`'s kinds.
    public init(info: [String: Any]) {
        func text(_ key: String) -> String {
            let value = ((info[key] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return value.hasPrefix("$(") ? "" : value
        }
        func list(_ key: String) -> [String]? {
            guard info[key] != nil else { return nil }
            return text(key).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        let defaults = PerchConfiguration()
        let repository = text(Key.updateRepository)
        let repositoryParts = repository.split(separator: "/", omittingEmptySubsequences: false)
        let validRepository = repositoryParts.count == 2 && repositoryParts.allSatisfy { !$0.isEmpty && !$0.contains(" ") }
        let service = text(Key.keychainService)
        let bundleID = text("CFBundleIdentifier")
        let areas = list(Key.standardAreas) ?? []
        let owner = text(Key.ownerID)
        var marks = defaults.agentMarks
        if let pairs = list(Key.agentMarks) {
            marks = [:]
            for pair in pairs {
                let parts = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2, !parts[0].isEmpty, let mark = AgentHistory.Mark(kind: parts[1]) else { continue }
                marks[parts[0].lowercased()] = mark
            }
        }
        self.init(
            gitHubClientID: text(Key.gitHubClientID),
            updateRepository: validRepository ? repository : "",
            keychainService: !service.isEmpty ? service : (!bundleID.isEmpty ? bundleID : defaults.keychainService),
            standardAreas: areas.isEmpty ? defaults.standardAreas : areas,
            preferredNotebook: text(Key.preferredNotebook),
            ownerID: owner.isEmpty ? defaults.ownerID : owner,
            otherOwners: list(Key.otherOwners) ?? defaults.otherOwners,
            agentMarks: marks,
            defaultRepositoryOwner: text(Key.defaultRepositoryOwner)
        )
    }

    /// A build made from the public source with nothing configured.
    public static let neutral = PerchConfiguration(info: [:])

    /// This app's own values, from its Info.plist. In a test run that is the test runner's, so neutral.
    public static let main = PerchConfiguration(info: Bundle.main.infoDictionary ?? [:])

    /// Signing in with GitHub needs the GitHub App's client ID.
    public var signsInWithGitHub: Bool { !gitHubClientID.isEmpty }

    /// Updates are the releases of `updateRepository`, read with the GitHub sign-in, so both must be set.
    public var checksForUpdates: Bool { !updateRepository.isEmpty && signsInWithGitHub }
}

/// What the Mac offers before a notebook is open, and which settings can work, given the build.
public enum FirstRun {
    /// Ways to open a notebook.
    public enum Source: Equatable, Sendable {
        /// A repository the GitHub sign-in can reach, cloned to this Mac.
        case gitHub
        /// A Git repository already on this Mac, synced with that folder's own Git login.
        case gitFolder
        /// Any folder on this Mac: a Git repository syncs as `gitFolder` does, any other folder opens without sync.
        case anyFolder
    }

    /// What happens when a folder on this Mac is chosen as the notebook.
    public enum Opening: Equatable, Sendable {
        case withSync
        case withoutSync
        case refused
    }

    /// The sign-in screen comes first only when this build can sign in and nobody has. Test runs never ask.
    public static func needsAccount(_ configuration: PerchConfiguration, isSignedIn: Bool, isTestRun: Bool) -> Bool {
        configuration.signsInWithGitHub && !isSignedIn && !isTestRun
    }

    /// The choices on the notebook chooser.
    public static func sources(_ configuration: PerchConfiguration) -> [Source] {
        configuration.signsInWithGitHub ? [.gitHub, .gitFolder] : [.anyFolder]
    }

    /// A Git repository always opens with sync. A plain folder opens without it in a build with no GitHub
    /// sign-in; a build with sign-in keeps asking for a Git repository, as it always has.
    public static func opening(_ configuration: PerchConfiguration, isGitRepository: Bool) -> Opening {
        if isGitRepository { return .withSync }
        return sources(configuration).contains(.anyFolder) ? .withoutSync : .refused
    }

    /// The look for a newer Perch a few seconds after launch needs the update source and a saved account.
    public static func checksForUpdatesAtLaunch(_ configuration: PerchConfiguration, hasAccount: Bool) -> Bool {
        configuration.checksForUpdates && hasAccount
    }

    /// Settings shows the GitHub account only when this build can sign in.
    public static func showsAccountSettings(_ configuration: PerchConfiguration) -> Bool { configuration.signsInWithGitHub }

    /// Settings offers update checks only when this build has an update source.
    public static func showsUpdateChecks(_ configuration: PerchConfiguration) -> Bool { configuration.checksForUpdates }
}
