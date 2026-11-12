import XCTest
@testable import PerchKit

/// Ready to tick: an agent thinks one of your tasks is finished. What it says, and how to get back to it.
final class ProposalTests: XCTestCase {
    private func task(reason: String?, at: String? = nil, from: String? = nil, during: String? = nil, by agent: String = "claude") -> PerchTask {
        var task = PerchTask(id: "t1", path: "✈️ Acme/Tasks/t1.md", title: "Accept Robin Ash's intro 1:1")
        task.proposedDoneBy = agent
        task.proposedDoneReason = reason
        task.proposedDoneAt = at
        task.proposedDoneFrom = from
        task.proposedDoneWhile = during
        return task
    }

    func testAMootProposalSaysTheTaskIsNoLongerNeeded() {
        let summary = Proposal(task(reason: "Moot: Robin Ash's intro 1:1 was on Thu 29 Oct, which has passed."))
        XCTAssertEqual(summary.kind, .noLongerNeeded)
        XCTAssertEqual(summary.headline, "Thinks this is no longer needed")
        XCTAssertEqual(summary.reason, "Robin Ash's intro 1:1 was on Thu 29 Oct, which has passed.")
    }

    func testAnOrdinaryProposalSaysItsDone() {
        let summary = Proposal(task(reason: "Sent the deck to Mohit on Monday."))
        XCTAssertEqual(summary.kind, .done)
        XCTAssertEqual(summary.headline, "Thinks this is done")
        XCTAssertEqual(summary.reason, "Sent the deck to Mohit on Monday.")
        XCTAssertEqual(Proposal(task(reason: nil)).reason, nil)
    }

    func testItSaysWhoWhenAndWhatTheAgentWasDoing() {
        let summary = Proposal(task(reason: "Moot: passed.", at: "2026-11-10T12:14:05-06:00", during: "Reviewing open tasks to close out stale ones"))
        XCTAssertEqual(summary.agent, "Claude")
        XCTAssertEqual(summary.date, ISO8601DateFormatter().date(from: "2026-11-10T18:14:05Z"))
        XCTAssertEqual(summary.during, "Reviewing open tasks to close out stale ones")
        XCTAssertNil(Proposal(task(reason: nil, at: "yesterday")).date)
    }

    func testOnlySessionLinksFromClaudeAndCodexOpen() {
        let opens = [
            "claude://code/continue?session=local_c1d34085-969d-433d-b5ba-b29a48d714b6",
            "codex://threads/01a1c668-6820-7fa1-8958-10407b1b6b5a",
        ]
        for link in opens { XCTAssertEqual(Proposal(task(reason: nil, from: link)).link?.absoluteString, link, link) }
        // A task file is plain text anyone can edit, so nothing else is ever opened from one.
        let refused = [
            "https://example.com/phish", "file:///etc/passwd", "claude://code/new?q=delete%20everything",
            "claude://code/continue?session=last", "codex://threads/../settings", "javascript:alert(1)",
            // Claude's app has no such link, so Perch doesn't offer one.
            "claude://resume?session=dfad42d0-e731-4254-a07c-43a9106bc5d7",
        ]
        for link in refused { XCTAssertNil(Proposal(task(reason: nil, from: link)).link, link) }
    }

    func testTheWordingSaysWhoThinksWhatAndWhatEachButtonDoes() {
        let moot = Proposal(task(reason: "Moot: passed."))
        XCTAssertEqual(moot.sentence, "Claude thinks this is no longer needed")
        XCTAssertEqual(moot.acceptTitle, "Close task")
        XCTAssertEqual(moot.declineTitle, "Keep open")
        // An agent the build gives no mark of its own goes by its own name.
        let done = Proposal(task(reason: "Sent it.", by: "robin"))
        XCTAssertEqual(done.sentence, "robin thinks this is done")
        XCTAssertEqual(done.acceptTitle, "Mark done")
    }

    func testTheLinkSaysWhichAppItOpens() {
        XCTAssertEqual(Proposal(task(reason: nil, from: "claude://code/continue?session=local_abc")).linkTitle, "Open the Claude session")
        XCTAssertEqual(Proposal(task(reason: nil, from: "codex://threads/01a1c668-6820-7fa1-8958-10407b1b6b5a")).linkTitle, "Open the Codex thread")
        XCTAssertNil(Proposal(task(reason: nil)).linkTitle)
    }

    func testAnAgentInTheRelayCarriesTheSameCheckedLink() throws {
        let json = Data("""
        {"agents": [
          {"name": "claude", "status": "Here", "isActive": true, "updated": "2026-11-10T18:14:05.000Z", "link": "claude://code/continue?session=local_abc"},
          {"name": "dot", "status": "Here", "isActive": true, "updated": "2026-11-10T18:14:05.000Z", "link": "https://example.com"},
          {"name": "wren", "status": "Here", "isActive": false, "updated": "2026-11-10T18:14:05.000Z"}
        ]}
        """.utf8)
        let agents = try JSONDecoder().decode(RelayClient.Snapshot.self, from: json).agents
        XCTAssertEqual(agents.map(\.sessionLink?.absoluteString), ["claude://code/continue?session=local_abc", nil, nil])
        XCTAssertEqual(SessionLink.title(for: agents[0].sessionLink!), "Open the Claude session")
    }

    func testTheNewFieldsRoundTripThroughTheTaskFile() throws {
        var original = task(reason: "Moot: passed.", at: "2026-11-10T12:14:05-06:00",
                            from: "claude://code/continue?session=local_abc", during: "Reviewing open tasks")
        original.status = .open
        let text = TaskCodec.encode(original)
        XCTAssertTrue(text.contains("proposed_done_at: 2026-11-10T12:14:05-06:00\n") || text.contains("proposed_done_at: \"2026-11-10T12:14:05-06:00\"\n"), text)
        let decoded = try TaskCodec.decode(path: original.path, text: text)
        XCTAssertEqual(decoded.proposedDoneAt, "2026-11-10T12:14:05-06:00")
        XCTAssertEqual(decoded.proposedDoneFrom, "claude://code/continue?session=local_abc")
        XCTAssertEqual(decoded.proposedDoneWhile, "Reviewing open tasks")
    }
}
