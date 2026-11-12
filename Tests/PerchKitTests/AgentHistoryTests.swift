import XCTest
@testable import PerchKit

/// The notch's Agents card, when nobody is working: what each agent did last.
final class AgentHistoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_330_000)

    private func commit(_ author: String, _ email: String, _ subject: String, minutesAgo: Double) -> AgentHistory.Commit {
        .init(author: author, email: email, date: now.addingTimeInterval(-minutesAgo * 60), subject: subject)
    }

    private func event(_ agent: String, _ kind: String, _ text: String, path: String? = nil, minutesAgo: Double) -> AgentHistory.Event {
        .init(agent: agent, kind: kind, text: text, path: path, date: now.addingTimeInterval(-minutesAgo * 60))
    }

    func testOnlyAgentsCommitsCountNotTheOwners() {
        let deeds = AgentHistory.latest(commits: [
            commit("Alex Doe", "42+alexdoe@users.noreply.github.com", "Update Groceries.md", minutesAgo: 1),
            commit("claude", "claude@perch.local", "Add task: Book the dentist", minutesAgo: 5),
        ], events: [])
        XCTAssertEqual(deeds.map(\.agent), ["claude"])
    }

    func testEachAgentShowsTheLatestThingItDidNewestFirst() {
        let deeds = AgentHistory.latest(commits: [
            commit("claude", "claude@perch.local", "Add task: Book the dentist", minutesAgo: 30),
            commit("claude", "claude@perch.local", "Complete task: Renew passport", minutesAgo: 10),
            commit("wren", "wren@perch.local", "Add to Trip ideas.md", minutesAgo: 120),
        ], events: [
            event("dot", "status", "Ready to help with your notes and tasks through Perch.", minutesAgo: 2),
        ])
        XCTAssertEqual(deeds.map(\.agent), ["dot", "claude", "wren"])
        XCTAssertEqual(deeds.map(\.text), ["Ready to help with your notes and tasks through Perch.", "Completed “Renew passport”", "Added to Trip ideas"])
        XCTAssertEqual(deeds[1].date, now.addingTimeInterval(-600))
    }

    func testTheRelaysLiveNewsWinsWhenItIsNewerThanTheLastCommit() {
        let deeds = AgentHistory.latest(commits: [
            commit("claude", "claude@perch.local", "Add task: Book the dentist", minutesAgo: 30),
        ], events: [
            event("claude", "claim", "Writing the weekly summary", path: "Claude/Weekly.md", minutesAgo: 1),
        ])
        XCTAssertEqual(deeds.map(\.text), ["Working on Weekly"])
    }

    func testCommitSubjectsReadAsShortSentences() {
        let cases = [
            ("Add task: Book the dentist", "Added “Book the dentist”"),
            ("Update task: Book the dentist", "Updated “Book the dentist”"),
            ("Complete task: Book the dentist", "Completed “Book the dentist”"),
            ("Propose done: Book the dentist", "Thinks “Book the dentist” is done"),
            ("Create Ideas.md", "Created Ideas"),
            ("Update Ideas.md", "Edited Ideas"),
            ("Add to Ideas.md", "Added to Ideas"),
            ("Add card to Home.kanban.md", "Added a card to Home"),
            ("Summarised the week", "Summarised the week"),
        ]
        for (subject, text) in cases { XCTAssertEqual(AgentHistory.describe(subject: subject), text, subject) }
    }

    func testRelayEventsReadAsShortSentences() {
        XCTAssertEqual(AgentHistory.describe(event("dot", "message", "Your trip is booked", minutesAgo: 0)), "Left you a message: Your trip is booked")
        XCTAssertEqual(AgentHistory.describe(event("dot", "claim", "Editing", path: "Personal/Trip.md", minutesAgo: 0)), "Working on Trip")
        XCTAssertEqual(AgentHistory.describe(event("dot", "release", "Finished", path: "Personal/Trip.md", minutesAgo: 0)), "Finished Trip")
        XCTAssertEqual(AgentHistory.describe(event("dot", "write", "Edited", path: "Personal/Trip.md", minutesAgo: 0)), "Edited Trip")
        XCTAssertEqual(AgentHistory.describe(event("dot", "task", "Added “Pack”", minutesAgo: 0)), "Added “Pack”")
    }

    func testAtMostFourAgents() {
        let commits = (1...6).map { commit("agent\($0)", "agent\($0)@perch.local", "Update Note.md", minutesAgo: Double($0)) }
        XCTAssertEqual(AgentHistory.latest(commits: commits, events: []).map(\.agent), ["agent1", "agent2", "agent3", "agent4"])
    }

    func testOnlyClaudeHasItsOwnMarkInThePublicBuild() {
        let marks = PerchConfiguration.neutral.agentMarks
        XCTAssertEqual(AgentHistory.mark(for: "Claude", marks: marks), .claude)
        XCTAssertEqual(AgentHistory.mark(for: "claude-code", marks: marks), .claude)
        XCTAssertEqual(AgentHistory.mark(for: "dot", marks: marks), .initial("D"))
        XCTAssertEqual(AgentHistory.mark(for: "robot", marks: marks), .initial("R"))
        XCTAssertEqual(AgentHistory.displayName(for: "claude-code", marks: marks), "Claude")
        XCTAssertEqual(AgentHistory.displayName(for: "dot", marks: marks), "dot")
    }

    func testABuildGivesItsOwnAgentsTheirMarks() {
        // As a build's PERCH_AGENT_MARKS gives them: a name, then the mark it is drawn with.
        let marks = PerchConfiguration(info: [PerchConfiguration.Key.agentMarks: "claude=claude, pip=dot, Robin=house"]).agentMarks
        XCTAssertEqual(AgentHistory.mark(for: "pip", marks: marks), .dot)
        XCTAssertEqual(AgentHistory.mark(for: "claude-work", marks: marks), .claude)
        XCTAssertEqual(AgentHistory.mark(for: "robin", marks: marks), .house)
        XCTAssertEqual(AgentHistory.mark(for: "robinson", marks: marks), .initial("R"), "a longer name is someone else")
        XCTAssertEqual(AgentHistory.mark(for: "codex", marks: marks), .initial("C"))
        XCTAssertEqual(AgentHistory.displayName(for: "pip", marks: marks), "Pip")
        XCTAssertEqual(AgentHistory.displayName(for: "robin", marks: marks), "Robin")
        XCTAssertEqual(AgentHistory.displayName(for: "claude-work", marks: marks), "Claude")
        XCTAssertEqual(AgentHistory.displayName(for: "codex", marks: marks), "codex")
    }
}
