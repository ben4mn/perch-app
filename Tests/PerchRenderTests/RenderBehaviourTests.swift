import PerchKit
import XCTest

/// How the page behaves over time: what it loads, what it redraws after an edit, and what it tells Swift.
@MainActor
final class RenderBehaviourTests: XCTestCase {
    private var page: RenderPage!

    override func setUp() async throws {
        page = RenderPage(width: 760, vaultRoot: Checkout.fixtures)
        try await page.ready()
    }

    override func tearDown() async throws {
        page.close()
        page = nil
    }

    private func chunkNames() -> [String] {
        page.requestedURLs.filter { $0.contains("/chunks/") }.map { URL(string: $0)!.lastPathComponent }
    }

    func testHeavyLibrariesAreOnlyFetchedWhenANoteNeedsThem() async throws {
        let startup = Set(chunkNames())
        XCTAssertLessThanOrEqual(startup.count, 3, "the page starts from a handful of small files: \(startup)")
        let startupBytes = try (["render.js", "render.css"] + startup.map { "chunks/" + $0 }).reduce(0) { sum, name in
            sum + (try FileManager.default.attributesOfItem(atPath: Checkout.web.appendingPathComponent(name).path)[.size] as! Int)
        }
        XCTAssertLessThan(startupBytes, 450_000, "what every note pays for before its first word shows")

        try await page.render(try Checkout.fixture("bench-small.md"))
        XCTAssertEqual(Set(chunkNames()), startup, "plain text needs nothing more")
        XCTAssertFalse(page.requestedURLs.contains { $0.hasSuffix("render-katex.css") })

        try await page.render("```swift\nlet x = 1\n```\n")
        let afterSwift = Set(chunkNames()).subtracting(startup)
        XCTAssertTrue(afterSwift.contains { $0.hasPrefix("swift-") }, "\(afterSwift)")
        XCTAssertFalse(afterSwift.contains { $0.hasPrefix("python-") || $0.hasPrefix("katex-") || $0.hasPrefix("mermaid") || $0.hasPrefix("abcjs-") }, "\(afterSwift)")
        XCTAssertLessThanOrEqual(afterSwift.count, 3, "one language costs the highlighter and that language: \(afterSwift)")

        try await page.render("Inline $x^2$.")
        XCTAssertTrue(chunkNames().contains { $0.hasPrefix("katex-") })
        XCTAssertTrue(page.requestedURLs.contains { $0.hasSuffix("render-katex.css") })
        XCTAssertFalse(chunkNames().contains { $0.hasPrefix("mermaid") || $0.hasPrefix("abcjs-") })

        try await page.render("```mermaid\npie title T\n  \"a\" : 1\n```\n")
        XCTAssertTrue(chunkNames().contains { $0.hasPrefix("mermaid") })
        XCTAssertTrue(chunkNames().contains { $0.hasPrefix("pieDiagram") }, "only the kind of diagram that was drawn")
        XCTAssertFalse(chunkNames().contains { $0.hasPrefix("ganttDiagram") || $0.hasPrefix("abcjs-") })

        try await page.render("```abc\nX:1\nK:C\nCDEF|\n```\n")
        XCTAssertTrue(chunkNames().contains { $0.hasPrefix("abcjs-") })
    }

    func testTextIsShownBeforeCodeIsColoured() async throws {
        let markdown = try Checkout.fixture("bench-typical.md")
        // Not settled: look at the page the moment render returns.
        try await page.call("render", ["markdown": markdown, "basePath": "note.md"])
        let first = try await page.string("JSON.stringify({ blocks: document.querySelectorAll('.code-block').length, text: document.querySelector('.code-block pre code').textContent.length > 10, headings: document.querySelectorAll('h2').length })")
        XCTAssertEqual(first, #"{"blocks":10,"text":true,"headings":10}"#, "everything readable is there at once")
        XCTAssertEqual(page.messages(ofType: "rendered").count, 1)
        let before = try await page.string("JSON.stringify([...document.querySelectorAll('.code-block, .math-block, .diagram, .table-wrap, #root > p')].map((el) => Math.round(el.getBoundingClientRect().height)))")
        try await page.settle()
        let coloured = try await page.count(".code-block[data-highlighted]")
        XCTAssertEqual(coloured, 9)
        try await page.wait("settled") { !self.page.messages(ofType: "settled").isEmpty }
        // Colouring code changes no sizes, so nothing on the page moves.
        let after = try await page.string("JSON.stringify([...document.querySelectorAll('.code-block, .math-block, .diagram, .table-wrap, #root > p')].map((el) => Math.round(el.getBoundingClientRect().height)))")
        let was = try JSONSerialization.jsonObject(with: Data(before.utf8)) as! [Int], now = try JSONSerialization.jsonObject(with: Data(after.utf8)) as! [Int]
        let codeHeights = try await page.string("JSON.stringify([...document.querySelectorAll('.code-block')].map((el) => Math.round(el.getBoundingClientRect().height)))")
        XCTAssertEqual(was.count, now.count)
        XCTAssertFalse(codeHeights.isEmpty)
        let moved = zip(was, now).filter { abs($0 - $1) > 1 }.count
        XCTAssertLessThanOrEqual(moved, 3, "only the formulas may change height when they are typeset: \(before) → \(after)")
    }

    func testAnEditOnlyRebuildsTheBlockThatChanged() async throws {
        let markdown = try Checkout.fixture("bench-typical.md")
        try await page.render(markdown)
        _ = try await page.js("""
        window.__kept = { code: [...document.querySelectorAll('.code-block')], math: document.querySelector('.math-block'), table: document.querySelector('table'), heading: document.querySelectorAll('h2')[9] };
        return true;
        """)
        let lines = markdown.components(separatedBy: "\n")
        let target = lines.firstIndex { $0.hasPrefix("## Section 2") }! + 2
        var edited = lines
        edited[target] += " One more sentence."
        page.clearMessages()
        try await page.call("render", ["markdown": edited.joined(separator: "\n"), "basePath": "note.md"])
        let timing = page.messages(ofType: "rendered").last?["timing"] as? [String: Any]
        XCTAssertEqual(timing?["built"] as? Int, 1, "one paragraph changed, one piece rebuilt: \(String(describing: timing))")
        XCTAssertEqual((timing?["reused"] as? Int ?? 0) + 1, timing?["pieces"] as? Int)
        let kept = try await page.string("""
        JSON.stringify({
          code: window.__kept.code.every((el, i) => el === document.querySelectorAll('.code-block')[i] && (el.dataset.highlighted === '1' || !el.dataset.lang)),
          math: window.__kept.math === document.querySelector('.math-block') && !!window.__kept.math.querySelector('.katex'),
          table: window.__kept.table === document.querySelector('table'),
          text: document.getElementById('root').innerText.includes('One more sentence.'),
          busy: document.querySelectorAll('.math[data-math="pending"]').length,
        })
        """)
        XCTAssertEqual(kept, #"{"code":true,"math":true,"table":true,"text":true,"busy":0}"#, "coloured code and typeset formulas are kept as they are")
        XCTAssertEqual(page.messages(ofType: "settled").count, 1, "nothing was left to draw")

        // Lines added above: blocks below keep their nodes and learn their new line numbers.
        let headingLine = lines.firstIndex { $0.hasPrefix("## Section 10") }!
        var longer = lines
        longer.insert(contentsOf: ["", "A new paragraph.", "", "- [ ] and a task"], at: target + 1)
        try await page.call("render", ["markdown": longer.joined(separator: "\n"), "basePath": "note.md"])
        let moved = try await page.string("[window.__kept.heading === document.querySelectorAll('h2')[9], document.querySelectorAll('h2')[9].dataset.line].join(',')")
        // The note's first four lines are frontmatter; the page counts from the body and adds them back.
        XCTAssertEqual(moved, "true,\(headingLine + 4 - 4)")
        let toc = page.messages(ofType: "rendered").last?["toc"] as? [[String: Any]]
        XCTAssertEqual(toc?.first { $0["text"] as? String == "Section 10" }?["line"] as? Int, headingLine + 4)
        page.clearMessages()
        _ = try await page.js("document.querySelector('li.task-list-item input').click(); return true;")
        try await page.wait("toggleTask") { !self.page.messages(ofType: "toggleTask").isEmpty }
        XCTAssertEqual(page.messages(ofType: "toggleTask")[0]["line"] as? Int, target + 4, "a box in a block that moved still reports its true line")

        // Removing everything, then putting it back.
        try await page.render("")
        let empty = try await page.int("document.getElementById('root').childNodes.length")
        XCTAssertEqual(empty, 0)
        try await page.render(markdown)
        let back = try await page.count(".code-block[data-highlighted]")
        XCTAssertEqual(back, 9)
    }

    func testReorderedAndRepeatedBlocksEndUpInTheRightOrder() async throws {
        let blocks = ["# One", "Para A", "```js\nlet a = 1;\n```", "Para B", "- x\n- y", "Para A", "> quote", "Para C"]
        try await page.render(blocks.joined(separator: "\n\n"))
        var order = blocks
        for step in 0..<12 {
            // A deterministic shuffle, with a duplicate added or removed now and then.
            order = Array(order[(step % order.count)...] + order[..<(step % order.count)])
            if step % 3 == 0 { order.insert("Para A", at: order.count / 2) }
            if step % 4 == 1, order.count > 3 { order.remove(at: 1) }
            let markdown = order.joined(separator: "\n\n")
            try await page.render(markdown)
            let incremental = try await page.string("document.getElementById('root').innerHTML")
            let fresh = RenderPage(width: 760)
            try await fresh.render(markdown)
            let clean = try await fresh.string("document.getElementById('root').innerHTML")
            fresh.close()
            XCTAssertEqual(incremental, clean, "after step \(step) the page should be what a fresh render gives")
        }
    }

    func testEveryFixtureGivesTheSamePageWhenReachedByEdits() async throws {
        // Render a different note first, then the fixture: the result must match a page that only ever saw the fixture.
        for name in ["lists.md", "tables.md", "callouts.md", "code-edge.md", "html.md", "inline.md", "formatting.md"] {
            let markdown = try Checkout.fixture(name)
            try await page.render(try Checkout.fixture("bench-typical.md"))
            let half = markdown.components(separatedBy: "\n")
            try await page.render(half[..<(half.count / 2)].joined(separator: "\n"))
            try await page.render(markdown)
            let incremental = try await page.string("document.getElementById('root').innerHTML")
            let fresh = RenderPage(width: 760, vaultRoot: Checkout.fixtures)
            try await fresh.render(markdown)
            let clean = try await fresh.string("document.getElementById('root').innerHTML")
            fresh.close()
            XCTAssertEqual(incremental, clean, name)
        }
    }

    func testAMissingPictureStaysMissingThroughEditsElsewhere() async throws {
        // A picture that is a block of its own (raw HTML, or a captioned one, which becomes a figure) is a
        // node the page keeps for its block. An edit elsewhere keeps the block, and must keep its note too.
        let markdown = "# Title\n\n<img src=\"gone-1.png\">\n\n![second](gone-2.png \"A caption\")\n\nInline ![third](gone-3.png) too.\n\nText."
        try await page.render(markdown)
        var noted = 0
        for _ in 0..<300 {
            noted = try await page.count(".image-missing")
            if noted == 3 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(noted, 3, "each picture that isn't there says so")
        try await page.render(markdown + " More text.")
        let shown = try await page.string("[document.querySelectorAll('.image-missing').length, document.querySelectorAll('#root img').length].join(',')")
        XCTAssertEqual(shown, "3,0", "notes for missing pictures, then pictures left on the page: none comes back as a broken picture")
    }

    func testAppearanceChangesNeverRenderAgain() async throws {
        try await page.render(try Checkout.fixture("bench-typical.md"), ["appearance": ThemePresets.perchLight.appearance])
        _ = try await page.js("window.__nodes = [...document.getElementById('root').children]; return true;")
        page.clearMessages()
        try await page.call("setAppearance", ["fontSize": 19, "lineHeight": 1.8, "measure": "80ch", "justify": true, "fontBody": "Charter, serif",
                                               "style": ["--perch-code-white-space": "pre-wrap", "--perch-paragraph-gap": "1.4em", "--perch-code-size": "1em"],
                                               "attributes": ["properties": "expanded", "images": "full"]])
        try await page.call("setAppearance", ThemePresets.all.last!.appearance)
        try await page.settle()
        XCTAssertTrue(page.messages(ofType: "rendered").isEmpty)
        let same = try await page.string("window.__nodes.length === document.getElementById('root').children.length && window.__nodes.every((node, i) => node === document.getElementById('root').children[i])")
        XCTAssertEqual(same, "true")
        let applied = try await page.string("[getComputedStyle(document.documentElement).fontSize, getComputedStyle(document.querySelector('pre code')).whiteSpace, document.documentElement.dataset.scheme, document.querySelector('.properties').open].join(',')")
        XCTAssertEqual(applied, "19px,pre-wrap,\(ThemePresets.all.last!.isDark ? "dark" : "light"),true")
    }

    func testTheOutlineCanJumpToALine() async throws {
        let markdown = try Checkout.fixture("bench-typical.md")
        try await page.render(markdown)
        let line = markdown.components(separatedBy: "\n").firstIndex { $0.hasPrefix("## Section 8") }!
        // Called the way the app calls it: with a dictionary.
        try await page.call("scrollToLine", ["line": line])
        let top = try await page.int("Math.round([...document.querySelectorAll('h2')].find((h) => h.textContent === 'Section 8').getBoundingClientRect().top)")
        XCTAssertLessThan(abs(top), 4, "the heading is at the top of the page")
        try await page.call("scrollToSourceLine", ["line": 0])
        let back = try await page.int("Math.round(document.scrollingElement.scrollTop)")
        XCTAssertEqual(back, 0)
    }

    /// The editor beside the preview starts its text 60 points down (format bar and inset). Given that as the
    /// page's top padding, the first block starts level with the editor's first line, and a line the editor
    /// scrolls to sits at the same height on the page, so both sides stay level as they scroll.
    func testALineSyncedFromTheEditorSitsLevelWithIt() async throws {
        let markdown = try Checkout.fixture("bench-typical.md")
        try await page.render(markdown)
        try await page.call("setAppearance", ["style": ["--perch-pad-top": "60px"]])
        // The first thing on the page (here the note's properties) starts where the editor's line 1 does.
        let first = try await page.int("Math.round(document.getElementById('root').firstElementChild.getBoundingClientRect().top)")
        XCTAssertEqual(first, 60, "the page starts level with the editor's first line")
        let line = markdown.components(separatedBy: "\n").firstIndex { $0.hasPrefix("## Section 8") }!
        try await page.call("scrollToSourceLine", ["line": line])
        let top = try await page.int("Math.round([...document.querySelectorAll('h2')].find((h) => h.textContent === 'Section 8').getBoundingClientRect().top)")
        XCTAssertLessThan(abs(top - 60), 2, "the synced line sits 60 down, level with the editor's top line")
        // The page reports the same line back, so scrolling the preview moves the editor to match.
        let reported = try await page.js("return window.Perch.lineAtTop ? window.Perch.lineAtTop() : null;")
        if let reported = reported as? Double { XCTAssertEqual(reported, Double(line), accuracy: 0.5) }
        // Back in the reader alone, the page's own spacing returns.
        try await page.call("setAppearance", ["style": ["--perch-pad-top": ""]])
        let padding = try await page.string("getComputedStyle(document.getElementById('root')).paddingTop")
        XCTAssertNotEqual(padding, "60px")
    }

    func testTimingsAreReported() async throws {
        XCTAssertNotNil((page.messages(ofType: "ready").first?["boot"] as? [String: Any])?["ready"] as? Double)
        try await page.render(try Checkout.fixture("bench-typical.md"))
        try await page.wait("settled") { !self.page.messages(ofType: "settled").isEmpty }
        let rendered = page.messages(ofType: "rendered").last?["timing"] as? [String: Any]
        for key in ["parse", "build", "text", "pieces", "reused", "built"] { XCTAssertNotNil(rendered?[key], key) }
        let settled = page.messages(ofType: "settled").last?["timing"] as? [String: Any]
        for key in ["highlight", "math", "mermaid", "abc", "load", "settled"] { XCTAssertNotNil(settled?[key], key) }
        XCTAssertNotNil((settled?["load"] as? [String: Any])?["highlighter"])
    }

    func testCompactRenderReportsItsHeightAsContentArrives() async throws {
        try await page.resize(width: 420)
        page.clearMessages()
        try await page.call("render", ["markdown": "Details\n\n```mermaid\nflowchart TD\n  A --> B --> C\n```\n\n- [ ] a box\n", "basePath": "tasks/t.md", "compact": true])
        let first = page.messages(ofType: "rendered").last?["height"] as? Double ?? 0
        XCTAssertGreaterThan(first, 100, "room for the diagram is held from the start")
        try await page.settle()
        try await page.wait("a height once the diagram is drawn") { (self.page.messages(ofType: "height").last?["height"] as? Double ?? 0) > 0 || !self.page.messages(ofType: "settled").isEmpty }
        let final = try await page.int("document.documentElement.scrollHeight")
        let reported = (page.messages(ofType: "height").last?["height"] ?? page.messages(ofType: "settled").last?["height"]) as? Double ?? 0
        XCTAssertEqual(Int(reported), final, "Swift is told the page's final height")
        let heights = page.messages(ofType: "height").compactMap { $0["height"] as? Double }
        XCTAssertEqual(heights.count, Set(heights).count, "the same height is never reported twice in a row: \(heights)")
        XCTAssertLessThanOrEqual(heights.count, 3)
    }
}
