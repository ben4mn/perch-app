import XCTest
@testable import PerchKit

final class KanbanTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        let root = try XCTUnwrap(Bundle.module.resourceURL).appendingPathComponent("Fixtures")
        return try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
    }

    func testNotesHubFixtureRoundTripsExactly() throws {
        let text = try fixture("Home Renovation.kanban.md")
        let parsed = KanbanCodec.parse(text)
        XCTAssertTrue(parsed.droppedLines.isEmpty)
        XCTAssertEqual(KanbanCodec.serialize(parsed.board), text)
    }

    func testCardMetadataMatchesNotesHub() {
        let parsed = KanbanCodec.parse("## To Do\n- Call plumber ~1h #Kitchen @alex 2026-11-03  \n  Ask about:\n  - [ ] price\n  - [x] timing\n\n## Done\n- [x] Sand floor #Living 2023-06-22  \n- [ ] Paint shed  ")
        let card = parsed.board.lists[0].cards[0]
        XCTAssertEqual(card.title, "Call plumber")
        XCTAssertEqual(card.estimateValue, 1)
        XCTAssertEqual(card.estimateUnit, "h")
        XCTAssertEqual(card.tags, ["Kitchen"])
        XCTAssertEqual(card.mentions, ["alex"])
        XCTAssertEqual(card.dueDate, "2026-11-03")
        XCTAssertEqual(card.taskCounts.total, 2)
        XCTAssertEqual(card.taskCounts.completed, 1)
        XCTAssertTrue(parsed.board.lists[1].cards[0].isCompleted)
    }

    func testJavaScriptDateRollover() {
        XCTAssertEqual(KanbanCodec.parseSerializedDate("2023-02-30"), "2023-3-02".replacingOccurrences(of: "-3-", with: "-03-"))
        XCTAssertEqual(KanbanCodec.parseSerializedDate("2023-00-15"), "2022-12-15")
    }

    func testReportsLinesNotesHubDrops() {
        let parsed = KanbanCodec.parse("stray\n# H1\n## List\n* star\n- Card  ")
        XCTAssertEqual(parsed.droppedLines.map(\.text), ["stray", "# H1", "* star"])
    }

    func testCRLFKeepsCarriageReturnBehavior() {
        XCTAssertEqual(splitLines("a\r\nb"), ["a\r", "b"])
    }
}

final class FrontmatterTests: XCTestCase {
    func testSplitIsLossless() {
        for text in ["no frontmatter\n", "---\na: 1\n---\nbody", "---\r\na: 1\r\n---\r\nbody\r\n", "---\nnever closed", "", "---\n---\n", "🎉\n---\nx: y\n---\n"] {
            XCTAssertEqual(MarkdownDocument(text: text).text, text)
        }
    }

    func testFieldsPreserveUnknownKeys() {
        var document = MarkdownDocument(text: "---\ncustom: keep me\n# a comment\naliases: [Sam, \"Sam S\"]\n---\nBody\n")
        XCTAssertEqual(document.fields.list("aliases"), ["Sam", "Sam S"])
        var fields = document.fields
        fields["status"] = "open"
        document.fields = fields
        XCTAssertTrue(document.rawFrontmatter.contains("custom: keep me"))
        XCTAssertTrue(document.rawFrontmatter.contains("# a comment"))
        XCTAssertEqual(document.fields["status"], "open")
        XCTAssertEqual(document.body, "Body\n")
    }

    func testBlockLists() {
        let document = MarkdownDocument(text: "---\naliases:\n  - One\n  - Two\nnext: x\n---\n")
        XCTAssertEqual(document.fields.list("aliases"), ["One", "Two"])
        XCTAssertEqual(document.fields["next"], "x")
    }

    func testQuotingRoundTrips() {
        var fields = FrontmatterFields()
        let tricky = "Answer Clay's: \"moved\" invite #1 (10:00)"
        fields["title"] = tricky
        XCTAssertEqual(FrontmatterFields(raw: fields.raw)["title"], tricky)
    }
}

final class WhiteboardTests: XCTestCase {
    func testDecodesNotesHubFixture() throws {
        let root = try XCTUnwrap(Bundle.module.resourceURL).appendingPathComponent("Fixtures")
        let svg = try String(contentsOf: root.appendingPathComponent("Brainstorming.excalidraw.svg"), encoding: .utf8)
        let scene = try WhiteboardCodec.sceneJSON(fromSVG: svg)
        XCTAssertGreaterThan(WhiteboardCodec.elementCount(sceneJSON: scene), 0)
    }

    func testPlainExcalidraw() throws {
        let text = #"{"type":"excalidraw","version":2,"elements":[{"id":"a"}]}"#
        let scene = try WhiteboardCodec.sceneJSON(fromFileNamed: "x.excalidraw", text: text)
        XCTAssertEqual(WhiteboardCodec.elementCount(sceneJSON: scene), 1)
    }

    func testMissingPayloadIsAnError() {
        XCTAssertThrowsError(try WhiteboardCodec.sceneJSON(fromSVG: "<svg></svg>"))
    }
}

final class TaskTests: XCTestCase {
    func testTaskRoundTrip() throws {
        var task = PerchTask(id: "tabc2345", path: "✈️ Acme/Tasks/x.md", title: "Answer: \"moved\" invite")
        task.owner = "alex"
        task.due = "2026-11-14"
        task.time = "09:00"
        task.priority = 2
        task.labels = ["admin", "pair up"]
        task.parent = "tparent2"
        task.recurrence = "every monday"
        task.remind = ["2026-11-14T09:00"]
        task.details = "**From:** Someone\n\n- [ ] item\n\n## Other heading\n\nText [[Link]]"
        task.activity = [
            .init(date: "2026-11-09", author: "triage", text: "First line\nsecond line"),
            .init(date: "2026-11-10", author: "alex", text: "Done with: colons"),
        ]
        let text = TaskCodec.encode(task)
        let decoded = try TaskCodec.decode(path: task.path, text: text)
        XCTAssertEqual(decoded.title, task.title)
        XCTAssertEqual(decoded.details, task.details)
        XCTAssertEqual(decoded.activity, task.activity)
        XCTAssertEqual(decoded.labels, task.labels)
        XCTAssertEqual(decoded.area, "✈️ Acme")
        XCTAssertEqual(TaskCodec.encode(decoded), text)
    }

    func testUnknownFrontmatterSurvives() throws {
        let text = "---\nid: t1\nstatus: open\nmy_field: hello\n---\nBody\n"
        let task = try TaskCodec.decode(path: "A/Tasks/a.md", text: text)
        XCTAssertTrue(TaskCodec.encode(task).contains("my_field: hello"))
    }

    func testPlainNoteInTasksFolderIsNotATask() {
        XCTAssertThrowsError(try TaskCodec.decode(path: "A/Tasks/a.md", text: "# Just a note\n"))
    }

    func testFileNameIsSafe() {
        let name = TaskCodec.fileName(title: "Answer Clay's moved: 'Berkeley + data' invite (now Fri 13 Nov, 10:00-10:30 CST, with someone extremely long here)", id: "t1234567")
        XCTAssertFalse(name.contains(":"))
        XCTAssertTrue(name.hasSuffix(" t1234567.md"))
        XCTAssertLessThanOrEqual(name.count, 95)
        XCTAssertEqual(TaskCodec.fileName(title: "???", id: "t1"), "Task t1.md")
    }

    func testCompleteAndRepeat() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TaskStore(vault: Vault(root: root))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = DayMath.date(from: "2026-11-09", calendar: calendar)!

        let once = try store.create(title: "One", area: "Personal", today: today)
        let done = try store.complete(once, today: today, calendar: calendar)
        XCTAssertEqual(done.status, .done)
        XCTAssertEqual(done.completed, "2026-11-09")

        let repeating = try store.create(title: "Water", area: "Personal", configure: {
            $0.due = "2026-10-05"
            $0.recurrence = "every monday"
        }, today: today)
        let next = try store.complete(repeating, today: today, calendar: calendar)
        XCTAssertEqual(next.status, .open)
        XCTAssertEqual(next.due, "2026-11-16")
        XCTAssertEqual(store.loadAll().count, 2)
    }
}

final class DateTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    // Monday
    private var today: Date { DayMath.date(from: "2026-11-09", calendar: calendar)! }

    private func parse(_ text: String) -> QuickAdd {
        QuickAdd.parse(text, areas: ["✈️ Acme", "Personal"], today: today, calendar: calendar)
    }

    func testQuickAdd() {
        let result = parse("Call the vet tomorrow at 5pm #Personal !p2 @claude #home")
        XCTAssertEqual(result.title, "Call the vet")
        XCTAssertEqual(result.due, "2026-11-10")
        XCTAssertEqual(result.time, "17:00")
        XCTAssertEqual(result.area, "Personal")
        XCTAssertEqual(result.priority, 2)
        XCTAssertEqual(result.owner, "claude")
        XCTAssertEqual(result.labels, ["home"])
    }

    func testEmojiAreaMatches() {
        XCTAssertEqual(parse("Do it #acme").area, "✈️ Acme")
    }

    func testPhrases() {
        XCTAssertEqual(parse("x today").due, "2026-11-09")
        XCTAssertEqual(parse("x friday").due, "2026-11-13")
        XCTAssertEqual(parse("x monday").due, "2026-11-16")
        XCTAssertEqual(parse("x in 3 days").due, "2026-11-12")
        XCTAssertEqual(parse("x next week").due, "2026-11-16")
        XCTAssertEqual(parse("x jan 5").due, "2027-01-05")
        XCTAssertEqual(parse("x dec 25").due, "2026-12-25")
        XCTAssertEqual(parse("x 2026-12-01").due, "2026-12-01")
        XCTAssertEqual(parse("x 9am").time, "09:00")
        XCTAssertEqual(parse("x 9am").due, "2026-11-09")
    }

    func testPlainWordsStayInTitle() {
        XCTAssertEqual(parse("Monitor the marathon").title, "Monitor the marathon")
        XCTAssertNil(parse("Monitor the marathon").due)
    }

    func testRecurrence() {
        XCTAssertEqual(parse("Water every monday").recurrence, "every monday")
        XCTAssertEqual(parse("Water every monday").due, "2026-11-09")
        XCTAssertEqual(parse("Water every monday").title, "Water")
        XCTAssertEqual(Recurrence.next(rule: "every day", after: "2026-11-09", calendar: calendar), "2026-11-10")
        XCTAssertEqual(Recurrence.next(rule: "every 2 weeks", after: "2026-11-09", calendar: calendar), "2026-11-23")
        XCTAssertEqual(Recurrence.next(rule: "every other day", after: "2026-11-09", calendar: calendar), "2026-11-11")
        XCTAssertEqual(Recurrence.next(rule: "every month", after: "2026-01-31", calendar: calendar), "2026-02-28")
        XCTAssertEqual(Recurrence.next(rule: "every weekday", after: "2026-11-13", calendar: calendar), "2026-11-16")
        XCTAssertEqual(Recurrence.next(rule: "every mon, wed", after: "2026-11-09", calendar: calendar), "2026-11-11")
        XCTAssertNil(Recurrence.next(rule: "every 3rd friday", after: "2026-11-09", calendar: calendar))
    }
}

final class LinkTests: XCTestCase {
    private func index() -> LinkIndex {
        LinkIndex(entries: [
            (VaultFile(path: "Work/People/Pat-Quill.md"), "---\naliases: [Pat Quill, Patricia Quill]\n---\nHi\n"),
            (VaultFile(path: "Work/Plan.md"), "See [[Pat-Quill]] and [[Missing]] and `[[code]]`\n"),
            (VaultFile(path: "A/README.md"), "x"),
            (VaultFile(path: "B/README.md"), "x"),
            (VaultFile(path: "Personal/Cooking/Soup.md"), "[[Personal/Cooking]]"),
        ])
    }

    func testParseSkipsCode() {
        let links = WikiLinks.parse("[[One]] `[[two]]`\n```\n[[three]]\n```\n[[Four|Label]]")
        XCTAssertEqual(links.map(\.target), ["One", "Four"])
        XCTAssertEqual(links[1].label, "Label")
    }

    func testResolve() {
        let index = index()
        XCTAssertEqual(index.resolve("pat-quill"), .note("Work/People/Pat-Quill.md"))
        XCTAssertEqual(index.resolve("Patricia Quill"), .note("Work/People/Pat-Quill.md"))
        XCTAssertEqual(index.resolve("Personal/Cooking"), .folder("Personal/Cooking"))
        XCTAssertEqual(index.resolve("Missing"), .missing)
        XCTAssertEqual(index.resolve("README"), .ambiguous(["A/README.md", "B/README.md"]))
        XCTAssertEqual(index.resolve("README", from: "A/x.md"), .note("A/README.md"))
        XCTAssertEqual(index.resolve("A/README"), .note("A/README.md"))
    }

    func testBacklinks() {
        XCTAssertEqual(index().backlinks(to: "Work/People/Pat-Quill.md"), ["Work/Plan.md"])
    }

    func testMentionsPreferLongestAndRespectWords() {
        let text = "From Patricia Quill about [[Plan]], Pat-Quillish no. README here."
        let mentions = index().mentions(in: text)
        XCTAssertEqual(mentions.map { String(text[$0.range]) }, ["Patricia Quill"])
    }

    func testRewriteKeepsLabel() {
        XCTAssertEqual(WikiLinks.rewrite("a [[Old|L]] b [[old]] `[[Old]]`", from: "Old", to: "New"), "a [[New|L]] b [[New]] `[[Old]]`")
    }
}

/// Compares against NotesHub's own code when `PERCH_COMPARE_DIR` points at its output.
final class RealBoardComparison: XCTestCase {
    func testMatchesReferenceOutput() throws {
        guard let vaultPath = ProcessInfo.processInfo.environment["PERCH_VAULT"],
              let compare = ProcessInfo.processInfo.environment["PERCH_COMPARE_DIR"] else {
            throw XCTSkip("Needs a local vault copy")
        }
        let vault = Vault(root: URL(fileURLWithPath: vaultPath))
        for file in try vault.scan() where file.kind == .board {
            let expected = try String(contentsOf: URL(fileURLWithPath: compare).appendingPathComponent(file.name), encoding: .utf8)
            XCTAssertEqual(KanbanCodec.serialize(KanbanCodec.parse(try vault.read(file.path)).board), expected, file.path)
        }
    }
}

final class VaultScanTests: XCTestCase {
    func testScanSeesFilesAfterIgnoredOnes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = Vault(root: root)
        for path in [".DS_Store", "A/.gitkeep", "A/one.md", "B/.DS_Store", "B/two.md", "Z/.attachments/abc.png", "Z/three.kanban.md", ".git/config"] {
            try vault.write("x", to: path)
        }
        let files = try vault.scan()
        XCTAssertEqual(files.map(\.path), ["A/one.md", "B/two.md", "Z/.attachments/abc.png", "Z/three.kanban.md"])
        XCTAssertEqual(files.map(\.kind), [.note, .note, .attachment, .board])
    }
}

final class HTMLPasteTests: XCTestCase {
    func testCommonStructure() {
        let html = "<h2>Plan</h2><p>Use <strong>bold</strong> and <a href=\"https://x.test\">a link</a></p><ul><li>One</li><li>Two</li></ul><script>bad()</script>"
        let markdown = HTMLToMarkdown.convert(html)
        XCTAssertTrue(markdown.contains("## Plan"))
        XCTAssertTrue(markdown.contains("**bold**"))
        XCTAssertTrue(markdown.contains("[a link](https://x.test)"))
        XCTAssertTrue(markdown.contains("- One"))
        XCTAssertFalse(markdown.contains("bad()"))
    }
}

final class InsightsTests: XCTestCase {
    func testStreakAndOverdue() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = DayMath.date(from: "2026-11-09", calendar: calendar)!
        var a = PerchTask(id: "a", path: "P/Tasks/a.md", title: "A")
        a.status = .done
        a.completed = "2026-11-08"
        var b = PerchTask(id: "b", path: "P/Tasks/b.md", title: "B")
        b.status = .done
        b.completed = "2026-11-07"
        var c = PerchTask(id: "c", path: "P/Tasks/c.md", title: "C")
        c.due = "2026-11-01"
        let insights = Insights.compute(tasks: [a, b, c], focus: [FocusSession(start: today, seconds: 1800)], today: today, calendar: calendar)
        XCTAssertEqual(insights.streakDays, 2)
        XCTAssertEqual(insights.overdue, 1)
        XCTAssertEqual(insights.oldestOverdue?.id, "c")
        XCTAssertEqual(insights.completedThisWeek, 2)
        XCTAssertEqual(insights.focusMinutesThisWeek, 30)
    }
}
