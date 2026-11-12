import PerchKit
import XCTest

/// The fenced blocks of a note, read the plain way: for notes whose fences all start at the left margin.
struct Fence {
    var tag: String
    var content: String
    var line: Int

    static func all(in markdown: String) -> [Fence] {
        var result: [Fence] = []
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var index = 0
        while index < lines.count {
            let line = lines[index]
            guard let marker = ["````", "```", "~~~"].first(where: { line.hasPrefix($0) }) else { index += 1; continue }
            let info = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            var body: [String] = []
            var cursor = index + 1
            while cursor < lines.count, lines[cursor].trimmingCharacters(in: .whitespaces) != marker { body.append(lines[cursor]); cursor += 1 }
            result.append(Fence(tag: info.split(separator: " ").first.map(String.init) ?? "", content: body.map { $0 + "\n" }.joined(), line: index))
            index = cursor + 1
        }
        return result
    }
}

extension ThemePalette {
    /// What the app sends the page for this theme.
    var appearance: [String: Any] {
        ["variables": cssVariables.filter { $0.key.hasPrefix("--") }, "colorScheme": isDark ? "dark" : "light"]
    }
}

@MainActor
final class RenderFixtureTests: XCTestCase {
    private var page: RenderPage!

    override func setUp() async throws {
        page = RenderPage(width: 760, vaultRoot: Checkout.fixtures)
        try await page.ready()
    }

    override func tearDown() async throws {
        page.close()
        page = nil
    }

    private static let handWritten = [
        "code-languages.md", "code-edge.md", "tables.md", "lists.md", "inline.md", "callouts.md", "math.md", "mermaid.md",
        "abc.md", "wikilinks.md", "html.md", "images.md", "xss.md", "formatting.md", "wide-content.md", "crlf.md",
        "crlf-frontmatter.md", "frontmatter-simple.md", "frontmatter-lists.md", "frontmatter-rich.md", "frontmatter-not.md",
        "frontmatter-empty.md", "frontmatter-unclosed.md", "bench-small.md", "bench-typical.md", "bench-5-mermaid.md",
    ]
    /// Blocks that are meant to fail, by note: one bad formula, one bad diagram, and the hostile note's diagram.
    private static let expectedErrors = ["math.md": 1, "mermaid.md": 1]

    // MARK: Every fixture

    func testEveryFixtureDrawsCompletelyWithOnlyTheExpectedErrors() async throws {
        for name in Self.handWritten {
            try await page.render(try Checkout.fixture(name))
            let errors = try await page.count(".render-error")
            let errorText = try await page.string("[...document.querySelectorAll('.render-error')].map(e => e.textContent).join(' | ')")
            XCTAssertEqual(errors, Self.expectedErrors[name] ?? 0, "\(name): \(errorText)")
            let unfinishedMath = try await page.count(".math[data-math=\"pending\"]")
            XCTAssertEqual(unfinishedMath, 0, "\(name): formulas left untypeset")
            let unfinishedDiagrams = try await page.count(".diagram[data-state=\"pending\"]")
            XCTAssertEqual(unfinishedDiagrams, 0, "\(name): diagrams left undrawn")
            let text = try await page.int("document.getElementById('root').innerText.trim().length")
            XCTAssertGreaterThan(text, 10, "\(name): nothing on the page")
            XCTAssertFalse(page.messages(ofType: "rendered").isEmpty, name)
            XCTAssertFalse(page.messages(ofType: "settled").isEmpty, name)
            page.clearMessages()
        }
    }

    func testNothingIsWiderThanThePageAtPhoneWidths() async throws {
        for wrap in [false, true] {
            for width in [380, 669, 951] {
                try await page.resize(width: CGFloat(width))
                for name in Self.handWritten {
                    try await page.render(try Checkout.fixture(name), ["appearance": [
                        "style": ["--perch-code-white-space": wrap ? "pre-wrap" : "", "--perch-code-overflow-wrap": wrap ? "anywhere" : ""],
                    ]])
                    let overflow = try await page.string("""
                    (() => {
                      const page = document.documentElement;
                      if (page.scrollWidth <= page.clientWidth && document.body.scrollWidth <= page.clientWidth) return "";
                      const wide = [...document.querySelectorAll("#root *")].filter((el) => el.getBoundingClientRect().right > page.clientWidth + 0.5 && !el.closest("pre, .table-wrap, .math-display, .math-inline, .diagram, .math-block"));
                      return `scrollWidth ${page.scrollWidth} > ${page.clientWidth}: ` + wide.slice(0, 4).map((el) => el.tagName + "." + el.className + " " + Math.round(el.getBoundingClientRect().right)).join(", ");
                    })()
                    """)
                    XCTAssertEqual(overflow, "", "\(name) at \(width)pt, wrap \(wrap)")
                }
            }
        }
    }

    func testWideContentScrollsInsideItsOwnBox() async throws {
        try await page.resize(width: 380)
        try await page.render(try Checkout.fixture("wide-content.md"))
        let boxes = try await page.string("""
        JSON.stringify({
          code: [...document.querySelectorAll(".code-block pre")].some((el) => el.scrollWidth > el.clientWidth + 20 && getComputedStyle(el).overflowX === "auto"),
          table: [...document.querySelectorAll(".table-wrap")].some((el) => el.scrollWidth > el.clientWidth + 20),
          math: [...document.querySelectorAll(".math-block, .math-display")].some((el) => el.scrollWidth > el.clientWidth + 20),
        })
        """)
        XCTAssertEqual(boxes, #"{"code":true,"table":true,"math":true}"#)
        // With wrapping on, code no longer needs to scroll.
        try await page.call("setAppearance", ["style": ["--perch-code-white-space": "pre-wrap", "--perch-code-overflow-wrap": "anywhere"]])
        let wrapped = try await page.int("Math.max(...[...document.querySelectorAll('.code-block pre')].map((el) => el.scrollWidth - el.clientWidth))")
        XCTAssertLessThanOrEqual(wrapped, 1)
    }

    // MARK: Code

    func testCodeBlocksKeepTheirTextExactlyAndAreColouredByLanguage() async throws {
        let markdown = try Checkout.fixture("code-languages.md")
        let fences = Fence.all(in: markdown)
        XCTAssertGreaterThanOrEqual(Set(fences.map { $0.tag.lowercased() }).count, 30)
        try await page.render(markdown)
        let json = try await page.string("""
        JSON.stringify([...document.querySelectorAll(".code-block")].map((block) => ({
          text: block.querySelector("pre code").textContent,
          label: block.querySelector(".code-lang").textContent,
          tokens: block.querySelectorAll("pre code span[class^='hljs-']").length,
          plain: block.classList.contains("plain"),
          line: Number(block.dataset.line),
        })))
        """)
        let blocks = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [[String: Any]]
        XCTAssertEqual(blocks.count, fences.count)
        let uncoloured: Set<String> = ["plaintext", "text", "brainfog", ""]
        for (fence, block) in zip(fences, blocks) {
            XCTAssertEqual(block["text"] as? String, fence.content, "text of the \(fence.tag) block")
            XCTAssertEqual(block["label"] as? String, fence.tag, "the label is the tag as written")
            XCTAssertEqual(block["line"] as? Int, fence.line, "source line of the \(fence.tag) block")
            XCTAssertEqual(block["plain"] as? Bool, fence.tag.isEmpty)
            let tokens = block["tokens"] as? Int ?? 0
            if uncoloured.contains(fence.tag) { XCTAssertEqual(tokens, 0, "\(fence.tag) stays plain text") }
            else { XCTAssertGreaterThan(tokens, 0, "\(fence.tag) should be coloured") }
        }
    }

    func testLanguageTagsAndTheirAliases() async throws {
        let expected = [
            "sh": "bash", "zsh": "bash", "shell": "shell", "console": "shell", "js": "javascript", "jsx": "javascript", "mjs": "javascript",
            "ts": "typescript", "tsx": "typescript", "py": "python", "yml": "yaml", "objc": "objectivec", "c++": "cpp", "cs": "csharp",
            "c#": "csharp", "kt": "kotlin", "rs": "rust", "md": "markdown", "html": "xml", "dockerfile": "dockerfile", "docker": "dockerfile",
            "toml": "ini", "golang": "go", "rb": "ruby", "jsonc": "json", "Swift": "swift", "PYTHON": "python", "ps1": "powershell",
        ]
        for (tag, language) in expected {
            try await page.render("```\(tag)\nx = 1\n```\n")
            let resolved = try await page.string("document.querySelector('.code-block').dataset.highlighted === '1' ? 'coloured' : 'plain'")
            XCTAssertEqual(resolved, "coloured", "\(tag) should be read as \(language)")
        }
        for tag in ["text", "txt", "plain", "plaintext", "nosuchlanguage", "42"] {
            try await page.render("```\(tag)\nfunction x() { return 1 }\n```\n")
            let spans = try await page.count(".code-block pre code span")
            XCTAssertEqual(spans, 0, "\(tag) stays plain")
            let label = try await page.string("document.querySelector('.code-lang').textContent")
            XCTAssertEqual(label, tag)
        }
        // No tag: never guessed at.
        try await page.render("```\nfunction x() { return 1 }\n```\n")
        let guessed = try await page.count(".code-block pre code span")
        XCTAssertEqual(guessed, 0)
    }

    func testCodeEdgeCases() async throws {
        let markdown = try Checkout.fixture("code-edge.md")
        try await page.render(markdown)
        func text(_ selector: String, _ index: Int = 0) async throws -> String {
            try await page.js("return document.querySelectorAll(selector)[index]?.textContent ?? '<missing>';", ["selector": selector, "index": index]) as? String ?? ""
        }
        let all = try await page.string("JSON.stringify([...document.querySelectorAll('.code-block pre code')].map((c) => c.textContent))")
        let blocks = try JSONSerialization.jsonObject(with: Data(all.utf8)) as! [String]
        XCTAssertTrue(blocks[0].hasPrefix("let veryLongLine = [\"item-000\""))
        XCTAssertTrue(blocks[0].contains("\"item-059\"]\n// short\n"))
        XCTAssertEqual(blocks[1], "func main() {\n\tif true {\n\t\tfmt.Println(\"tabs\")\n\t}\n}\n", "tabs are kept as tabs")
        XCTAssertEqual(blocks[2], "def spaces():\n    if True:\n        return \"four spaces\"\n")
        XCTAssertEqual(blocks[3], "build:\n\tswift build\n")
        // Inside a list, a nested list, a quote and a callout: the block's own indentation is gone, its text is whole.
        let value1 = try await text("li > .code-block pre code")
        XCTAssertEqual(value1, "const inList = 1;\n")
        let value2 = try await text("li li .code-block pre code")
        XCTAssertEqual(value2, "{ \"nested\": true }\n")
        let value3 = try await text("blockquote .code-block pre code")
        XCTAssertEqual(value3, "in_quote = True\n")
        let value4 = try await text(".callout .code-block pre code")
        XCTAssertEqual(value4, "echo \"in callout\"\n")
        XCTAssertTrue(blocks.contains("Here is how to write a block:\n\n```js\nconst inner = \"fence\";\n```\n"), "a fence inside a longer fence is text")
        XCTAssertTrue(blocks.contains("tilde fence with ``` inside\n"))
        XCTAssertTrue(blocks.contains("indented line one\n    indented deeper\n<b>not bold</b>\n"), "an indented block keeps its inner indentation")
        XCTAssertTrue(blocks.contains("<script>window.__codeRan = 1</script>\n<img src=x onerror=\"window.__codeRan = 2\">\n<b>bold?</b> &amp; &lt; &#x41;\n"))
        XCTAssertTrue(blocks.contains("$not math$ and $$not display$$\n| not | a | table |\n| --- | --- | --- |\n[[not a wiki link]] and [[also|not]]\n- [ ] not a task\n> [!note] not a callout\n==not marked== ~sub~ ^sup^ :smile: https://example.com\n\\$ \\\\ trailing spaces follow:   \n\tleading tab\n"))
        XCTAssertTrue(blocks.contains("\nleading and trailing blank lines are kept\n\n"))
        XCTAssertTrue(blocks.contains(""), "an empty block is still a block")
        let ran = try await page.string("typeof window.__codeRan")
        XCTAssertEqual(ran, "undefined", "markup inside code never runs")
        let inner = try await page.count(".code-block pre code :not(span)")
        XCTAssertEqual(inner, 0, "nothing inside a code block but the highlighter's spans")
        // Inline code.
        let inline = try await page.string("JSON.stringify([...document.querySelectorAll('#root :not(pre) > code')].map((c) => c.textContent))")
        let spans = try JSONSerialization.jsonObject(with: Data(inline.utf8)) as! [String]
        for wanted in ["`backticks`", "`` double ``", "<script>alert(1)</script>", "$x^2$", "a | b", "[[not a link]]", "inline code", "second_one()", "render(markdown, { compact: true })"] {
            XCTAssertTrue(spans.contains(wanted), "inline code \(wanted) in \(spans)")
        }
        let stray = try await page.count("#root .math, #root a.wikilink, #root table table")
        XCTAssertEqual(stray, 0, "nothing in this note is a formula or a wiki link")
    }

    func testCopyGivesTheBlocksExactText() async throws {
        try await page.render("```js\nconst a = 1;\n\tconst b = \"<two>\";   \n```\n\n<button class=\"code-copy\">fake</button>\n\n<div class=\"code-block\"><div class=\"code-head\"><span class=\"code-copy\">fake</span></div><pre>stolen</pre></div>\n")
        page.clearMessages()
        _ = try await page.js("document.querySelector('.code-block .code-copy').click(); return true;")
        try await page.wait("copy") { !self.page.messages(ofType: "copy").isEmpty }
        XCTAssertEqual(page.messages(ofType: "copy").first?["text"] as? String, "const a = 1;\n\tconst b = \"<two>\";   ")
        page.clearMessages()
        // Markup in the note that imitates a block's Copy control does nothing.
        _ = try await page.js("for (const fake of document.querySelectorAll('span.code-copy')) fake.click(); return true;")
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(page.messages(ofType: "copy").isEmpty)
    }

    func testDiffLinesAreMarked() async throws {
        try await page.render("```diff\n-old\n+new\n same\n```\n")
        let added = try await page.string("document.querySelector('.hljs-addition')?.textContent ?? ''")
        let removed = try await page.string("document.querySelector('.hljs-deletion')?.textContent ?? ''")
        XCTAssertEqual(added, "+new")
        XCTAssertEqual(removed, "-old")
        let tinted = try await page.string("getComputedStyle(document.querySelector('.hljs-addition')).backgroundColor")
        XCTAssertNotEqual(tinted, "rgba(0, 0, 0, 0)")
    }

    // MARK: Other Markdown

    func testTables() async throws {
        try await page.render(try Checkout.fixture("tables.md"))
        let tables = try await page.count("#root table")
        XCTAssertEqual(tables, 6)
        let wrapped = try await page.count("#root .table-wrap > table")
        XCTAssertEqual(wrapped, 6, "every table sits in a box that scrolls")
        let alignment = try await page.string("[...document.querySelectorAll('table')[0].querySelectorAll('tbody tr:first-child td')].map((td) => getComputedStyle(td).textAlign).join(',')")
        XCTAssertEqual(alignment, "left,center,right")
        let cells = try await page.string("JSON.stringify([...document.querySelectorAll('table')[1].querySelectorAll('tbody td')].map((td) => td.textContent))")
        XCTAssertTrue(cells.contains("\"a | b\""), cells)
        let codeCells = try await page.string("[...document.querySelectorAll('table')[1].querySelectorAll('td code')].map((c) => c.textContent).join(';')")
        XCTAssertEqual(codeCells, "let x = 1;a | b")
        let inList = try await page.count("li table")
        let inQuote = try await page.count("blockquote table")
        XCTAssertEqual([inList, inQuote], [1, 1])
        let currency = try await page.string("document.querySelectorAll('table')[1].querySelector('tbody tr:nth-child(5)').textContent")
        XCTAssertTrue(currency.contains("costs $5 and $10"), currency)
        let notTables = try await page.string("document.getElementById('root').innerText")
        XCTAssertTrue(notTables.contains("| just | one | line |"))
    }

    func testListsAndTasks() async throws {
        let markdown = try Checkout.fixture("lists.md")
        try await page.render(markdown)
        let depth = try await page.count("ul ul ul ul ul")
        XCTAssertEqual(depth, 1, "five levels of bullets")
        let mixed = try await page.count("ol ol ul ol")
        XCTAssertEqual(mixed, 1)
        let start = try await page.string("document.querySelector('ol[start]')?.getAttribute('start') ?? ''")
        XCTAssertEqual(start, "7")
        let lines = markdown.components(separatedBy: "\n")
        let taskLines = lines.indices.filter { lines[$0].range(of: #"^[\s>]*(?:[-*+]|\d+\.) \[[ xX]\] "#, options: .regularExpression) != nil }
        let boxes = try await page.string("JSON.stringify([...document.querySelectorAll('li.task-list-item')].map((li) => [Number(li.dataset.line), li.querySelector('input[type=checkbox]').checked, li.querySelector('input[type=checkbox]').disabled]))")
        let found = try JSONSerialization.jsonObject(with: Data(boxes.utf8)) as! [[Any]]
        XCTAssertEqual(found.map { $0[0] as! Int }, taskLines, "each box knows the line it was written on")
        XCTAssertEqual(found.filter { $0[1] as! Bool }.count, lines.filter { $0.range(of: #"\[[xX]\] "#, options: .regularExpression) != nil }.count)
        XCTAssertTrue(found.allSatisfy { !($0[2] as! Bool) }, "boxes can be ticked")
        let text = try await page.string("document.getElementById('root').innerText")
        XCTAssertTrue(text.contains("[] not a task (no space)"))
        XCTAssertTrue(text.contains("[ ]not a task either"))
        // Ticking one tells Swift which line, and nothing else.
        page.clearMessages()
        _ = try await page.js("document.querySelectorAll('li.task-list-item input')[3].click(); return true;")
        try await page.wait("toggleTask") { !self.page.messages(ofType: "toggleTask").isEmpty }
        let message = page.messages(ofType: "toggleTask")[0]
        XCTAssertEqual(message["line"] as? Int, taskLines[3])
        XCTAssertEqual(message["checked"] as? Bool, true)
    }

    func testInlineFormatting() async throws {
        try await page.render(try Checkout.fixture("inline.md"))
        let headings = try await page.string("[...document.querySelectorAll('h1,h2,h3,h4,h5,h6')].map((h) => h.tagName).join('')")
        XCTAssertTrue(headings.hasPrefix("H1H2H3H4H5H6H1H2"), headings)
        let first = try await page.string("document.querySelector('h1').innerHTML")
        for piece in ["<em>emphasis</em>", "<strong>strong</strong>", "<code>code</code>", "href=\"https://example.com\""] { XCTAssertTrue(first.contains(piece), first) }
        let second = try await page.count("h2 s, h2 mark, h2 a.wikilink")
        XCTAssertEqual(second, 3)
        let emphasis = try await page.string("document.querySelectorAll('h2')[2].nextElementSibling.innerHTML")
        for piece in ["<em>italic</em>", "<strong>bold</strong>", "<s>strike</s>", "<mark>highlight</mark>", "H<sub>2</sub>O", "x<sup>2</sup>", "snake_case_word", "2<em>3</em>4"] { XCTAssertTrue(emphasis.contains(piece), "\(piece) in \(emphasis)") }
        let breaks = try await page.string("[...document.querySelectorAll('h2')].find((h) => h.textContent === 'Line breaks').nextElementSibling.innerHTML")
        XCTAssertTrue(breaks.contains("<br>"), "a single newline is a line break, as NotesHub shows it")
        let links = try await page.string("JSON.stringify([...document.querySelectorAll('#root a[href]')].map((a) => a.getAttribute('href')))")
        for wanted in ["https://example.com/auto", "https://example.com/bare", "http://www.example.com", "mailto:mail@example.com", "https://example.com/reference"] { XCTAssertTrue(links.contains("\"\(wanted)\""), "\(wanted) in \(links)") }
        let fileNames = try await page.string("[...document.querySelectorAll('#root p')].find((p) => p.textContent.startsWith('File names')).querySelectorAll('a').length")
        XCTAssertEqual(fileNames, "0", "README.md and friends are not web addresses")
        let relative = try await page.string("document.querySelector('a[data-note]').dataset.note")
        XCTAssertEqual(relative, "Other Note.md")
        let footnotes = try await page.count(".footnotes li")
        XCTAssertEqual(footnotes, 3)
        let references = try await page.count(".footnote-ref")
        XCTAssertEqual(references, 4)
        let emoji = try await page.string("[...document.querySelectorAll('h2')].find((h) => h.textContent === 'Emoji').nextElementSibling.textContent")
        XCTAssertTrue(emoji.contains("😄") && emoji.contains("👍") && emoji.contains("🎉") && emoji.contains(":not_an_emoji:"), emoji)
        let escapes = try await page.string("[...document.querySelectorAll('h2')].find((h) => h.textContent === 'Escapes and entities').nextElementSibling.textContent")
        XCTAssertEqual(escapes, "*not italic* # not heading © & <tag> 1 < 2 > 0")
        let rules = try await page.count("#root > hr")
        XCTAssertEqual(rules, 3)
        let quotes = try await page.count("blockquote blockquote blockquote")
        XCTAssertEqual(quotes, 1)
        // A footnote's link moves the page to the footnote without leaving it.
        _ = try await page.js("document.querySelector('.footnote-ref a').click(); return true;")
        let scrolled = try await page.int("Math.round(document.scrollingElement.scrollTop)")
        XCTAssertGreaterThan(scrolled, 0)
        let location = try await page.string("location.href")
        XCTAssertEqual(location, "perch-app://app/render.html")
    }

    func testCallouts() async throws {
        try await page.render(try Checkout.fixture("callouts.md"))
        let callouts = try await page.count(".callout")
        XCTAssertEqual(callouts, 23)
        let plain = try await page.count("#root > blockquote")
        XCTAssertEqual(plain, 2, "a quote that isn't a callout stays a quote")
        let titles = try await page.string("JSON.stringify([...document.querySelectorAll('.callout > .callout-title')].map((t) => t.textContent))")
        for wanted in ["Note", "A custom title", "Folded shut", "Folded open", "Title only", "Unknown type", "Nested callout"] { XCTAssertTrue(titles.contains("\"\(wanted)\""), "\(wanted) in \(titles)") }
        let folded = try await page.string("[...document.querySelectorAll('details.callout')].map((d) => d.open).join(',')")
        XCTAssertEqual(folded, "false,true")
        let formatted = try await page.string("[...document.querySelectorAll('.callout-title')].find((t) => t.textContent.startsWith('Title with')).innerHTML")
        for piece in ["<em>emphasis</em>", "<code>code</code>", "class=\"wikilink\""] { XCTAssertTrue(formatted.contains(piece), formatted) }
        let bodies = try await page.string("JSON.stringify([...document.querySelectorAll('.callout')].slice(0, 2).map((c) => c.querySelector('.callout-body').textContent.trim()))")
        XCTAssertEqual(bodies, #"["A note with the default title.","Tip body with bold and code."]"#)
        let nested = try await page.count(".callout .callout, .callout ul, .callout table")
        XCTAssertEqual(nested, 3)
        let leak = try await page.string("document.getElementById('root').innerText")
        XCTAssertFalse(leak.contains("[!"), "no callout marker is left showing")
    }

    func testMath() async throws {
        try await page.render(try Checkout.fixture("math.md"))
        let typeset = try await page.count(".math[data-math=\"done\"] .katex")
        XCTAssertEqual(typeset, 13)
        let display = try await page.count(".math-block .katex-display")
        XCTAssertEqual(display, 4)
        let inlineError = try await page.count(".math-inline[data-math=\"error\"]")
        XCTAssertEqual(inlineError, 1)
        let badSource = try await page.string("document.querySelector('.math-inline[data-math=\"error\"]').textContent")
        XCTAssertEqual(badSource, "\\frac{1}{", "a formula that can't be typeset still shows what was written")
        let blockError = try await page.string("document.querySelector('.math-block .render-error').textContent + '|' + document.querySelector('.math-block pre.source').textContent")
        XCTAssertTrue(blockError.hasPrefix("This formula couldn't be typeset:"), blockError)
        XCTAssertTrue(blockError.hasSuffix("|\\begin{nothing} x \\end{nothing}"), blockError)
        let currency = try await page.string("[...document.querySelectorAll('h2')].find((h) => h.textContent === 'Currency').nextElementSibling.innerHTML")
        XCTAssertFalse(currency.contains("math"), "prices are not formulas: \(currency)")
        XCTAssertTrue(currency.contains("It costs $5 and $10 at the door. Between $20 and $30. Price: $1,200.50. A $ alone. Paid 5$ twice, 10$ total."))
        XCTAssertTrue(currency.contains("Escaped $5 and $6. US$ and A$ prefixes. $HOME and $PATH are variables. Win $100 or $200!"))
        let inBlocks = try await page.count("li .katex, blockquote .katex, td .katex")
        XCTAssertGreaterThanOrEqual(inBlocks, 5)
        let literal = try await page.string("[...document.querySelectorAll('code')].map((c) => c.textContent).join('|')")
        XCTAssertTrue(literal.contains("$inline code$") && literal.contains("$fenced$ $$stays$$"), literal)
        let stylesheet = page.requestedURLs.filter { $0.hasSuffix("render-katex.css") }.count
        XCTAssertEqual(stylesheet, 1)
    }

    func testMermaidDiagramsAndTheirErrors() async throws {
        try await page.render(try Checkout.fixture("mermaid.md"))
        let drawn = try await page.int("[...document.querySelectorAll('.diagram[data-kind=\"mermaid\"][data-state=\"done\"]')].filter((d) => d.shadowRoot?.querySelector('svg')).length")
        XCTAssertEqual(drawn, 6)
        let failed = try await page.string("[...document.querySelectorAll('.diagram[data-state=\"error\"]')].map((d) => d.querySelector('.render-error').textContent.split('\\n')[0] + '|' + d.querySelector('pre.source').textContent).join('')")
        XCTAssertEqual(failed, "Mermaid couldn't draw this diagram.|flowchart LR\n  A -->\n  ((( not a diagram\n", "a diagram that can't be drawn says so and shows its source")
        let leftovers = try await page.count("body > :not(#root):not(script)")
        XCTAssertEqual(leftovers, 0, "Mermaid's scratch elements are cleared away")
        let after = try await page.string("document.getElementById('root').lastElementChild.textContent")
        XCTAssertEqual(after, "After the diagrams.")
        // Fits the column.
        let widest = try await page.int("Math.max(...[...document.querySelectorAll('.diagram')].map((d) => Math.ceil(d.shadowRoot?.querySelector('svg')?.getBoundingClientRect().width ?? 0))) <= document.getElementById('root').clientWidth ? 1 : 0")
        XCTAssertEqual(widest, 1)
        // A small diagram stays its own size instead of being blown up to the column's width, and its labels sit where Mermaid put them.
        let natural = try await page.string("JSON.stringify([...document.querySelectorAll('.diagram[data-state=\"done\"]')].map((d) => d.shadowRoot.querySelector('svg')).map((svg) => [/max-width/.test(svg.getAttribute('style') ?? ''), Math.round(svg.getBoundingClientRect().width) <= Math.ceil(svg.viewBox.baseVal.width) + 1]))")
        XCTAssertEqual(natural, "[[true,true],[true,true],[true,true],[true,true],[true,true],[true,true]]")
        let anchored = try await page.int("document.querySelectorAll('.diagram')[1].shadowRoot.querySelectorAll('text[style*=\"text-anchor\"], text[text-anchor]').length")
        XCTAssertGreaterThan(anchored, 0, "the diagram's own inline styles are intact")
        // Tap to enlarge.
        _ = try await page.js("document.querySelector('.diagram[data-state=\"done\"]').click(); return true;")
        let enlarged = try await page.count("body > .perch-lightbox .sheet svg")
        XCTAssertEqual(enlarged, 1)
        _ = try await page.js("document.querySelector('body > .perch-lightbox').click(); return true;")
        let closed = try await page.count("body > .perch-lightbox")
        XCTAssertEqual(closed, 0)
    }

    func testDiagramsFollowTheThemeWithoutRenderingAgain() async throws {
        try await page.render(try Checkout.fixture("bench-5-mermaid.md"), ["appearance": ThemePresets.perchLight.appearance])
        _ = try await page.js("window.__first = document.querySelector('.diagram'); window.__firstHeading = document.querySelector('h1'); return true;")
        let lightFill = try await page.string("document.querySelector('.diagram').shadowRoot.innerHTML.includes('\(ThemePresets.perchLight.text)')")
        XCTAssertEqual(lightFill, "true")
        page.clearMessages()
        try await page.call("setAppearance", ThemePresets.perchDark.appearance)
        try await page.settle()
        XCTAssertTrue(page.messages(ofType: "rendered").isEmpty, "a new theme is not a new render")
        let same = try await page.string("window.__first === document.querySelector('.diagram') && window.__firstHeading === document.querySelector('h1') && window.__first.dataset.state === 'done'")
        XCTAssertEqual(same, "true")
        let darkFill = try await page.string("document.querySelector('.diagram').shadowRoot.innerHTML.includes('\(ThemePresets.perchDark.text)')")
        XCTAssertEqual(darkFill, "true", "the diagram is redrawn in the dark theme's colours")
    }

    func testMusic() async throws {
        try await page.render(try Checkout.fixture("abc.md"))
        let drawn = try await page.count(".diagram[data-kind=\"abc\"][data-state=\"done\"] svg")
        XCTAssertGreaterThanOrEqual(drawn, 2)
        let after = try await page.string("document.getElementById('root').lastElementChild.textContent")
        XCTAssertEqual(after, "After the music.")
    }

    func testWikiLinks() async throws {
        try await page.render(try Checkout.fixture("wikilinks.md"), ["resolved": ["Wiki Target": true, "Wiki Target#Section Two": true, "Folder/Deep Note": true, "No Such Note": false, "A": true, "B": true]])
        let links = try await page.string("JSON.stringify([...document.querySelectorAll('a.wikilink')].map((a) => [a.dataset.wiki, a.textContent, a.classList.contains('missing')]))")
        let found = try JSONSerialization.jsonObject(with: Data(links.utf8)) as! [[Any]]
        func has(_ target: String, _ label: String, missing: Bool = false) -> Bool { found.contains { $0[0] as? String == target && $0[1] as? String == label && $0[2] as? Bool == missing } }
        XCTAssertTrue(has("Wiki Target", "Wiki Target"))
        XCTAssertTrue(has("Wiki Target", "shown text"))
        XCTAssertTrue(has("Wiki Target#Section Two", "Wiki Target#Section Two"))
        XCTAssertTrue(has("Wiki Target#Section Two", "the section"))
        XCTAssertTrue(has("Folder/Deep Note", "Folder/Deep Note"))
        XCTAssertTrue(has("No Such Note", "No Such Note", missing: true))
        XCTAssertTrue(has("No Such Note", "gone", missing: true))
        XCTAssertTrue(has("Wiki Target", "aliased in a cell"), "an alias in a table cell, written with an escaped bar: \(links)")
        XCTAssertTrue(has("A", "A") && has("B", "B"))
        XCTAssertEqual(found.count, 16, links)
        let places = try await page.count("li a.wikilink, blockquote a.wikilink, td a.wikilink, h2 a.wikilink")
        XCTAssertEqual(places, 6)
        let literal = try await page.string("document.getElementById('root').innerText")
        for text in ["[[code]]", "[[ ]]", "[[]]", "[single]", "[[unclosed", "[[escaped]]", "[[in a fence]]"] { XCTAssertTrue(literal.contains(text), text) }
        page.clearMessages()
        _ = try await page.js("document.querySelectorAll('a.wikilink')[1].click(); return true;")
        try await page.wait("openWiki") { !self.page.messages(ofType: "openWiki").isEmpty }
        XCTAssertEqual(page.messages(ofType: "openWiki")[0]["target"] as? String, "Wiki Target")
    }

    func testRawHTMLBlocks() async throws {
        try await page.render(try Checkout.fixture("html.md"))
        let details = try await page.count("#root > details")
        XCTAssertEqual(details, 2)
        let inside = try await page.string("document.querySelector('#root > details').innerHTML")
        for piece in ["<summary>Click to open</summary>", "<strong>inside</strong>", "<ul"] { XCTAssertTrue(inside.contains(piece), "Markdown between the tags of a raw block belongs to it: \(inside)") }
        let centered = try await page.string("getComputedStyle(document.querySelector('div[align=center] p')).textAlign + ',' + document.querySelector('div[align=center] p em').textContent")
        XCTAssertEqual(centered, "center,Markdown")
        let right = try await page.string("getComputedStyle(document.querySelector('p[align=right]')).textAlign")
        XCTAssertEqual(right, "right")
        let inline = try await page.count("#root kbd, #root abbr[title], #root sub, #root sup, #root u, #root p br")
        XCTAssertEqual(inline, 7)
        let table = try await page.count("#root .table-wrap > table td")
        XCTAssertEqual(table, 2)
        let text = try await page.string("document.getElementById('root').innerText")
        XCTAssertFalse(text.contains("a comment that must not show"))
        XCTAssertTrue(text.contains("Paragraph after."))
        let sized = try await page.string("document.querySelector('img[alt=\"sized image\"]').getAttribute('width')")
        XCTAssertEqual(sized, "40")
    }

    func testImages() async throws {
        try await page.render(try Checkout.fixture("images.md"))
        // Pictures below the first screen load when they come near it; bring them all in.
        _ = try await page.js("for (const image of document.images) image.loading = 'eager'; return true;")
        try await page.wait("the pictures to load") { self.imagesSettled }
        let sources = try await page.string("JSON.stringify([...document.querySelectorAll('#root img')].map((i) => i.getAttribute('src')))")
        XCTAssertTrue(sources.contains("\"perch-vault://vault/pixel.png\""), sources)
        XCTAssertTrue(sources.contains("\"perch-vault://vault/.attachments/shape.svg\""), sources)
        XCTAssertTrue(sources.contains("\"perch-vault://vault/.attachments/two%20words.png\""), sources)
        let broken = try await page.int("[...document.images].filter((i) => i.complete && i.naturalWidth === 0).length")
        XCTAssertEqual(broken, 0, "no broken-image icons")
        let missing = try await page.string("document.querySelector('.image-missing')?.textContent ?? ''")
        XCTAssertEqual(missing, "Missing image: this file is not there")
        let caption = try await page.string("document.querySelector('figure figcaption')?.textContent ?? ''")
        XCTAssertEqual(caption, "A caption under the picture")
        let wide = try await page.int("Math.round(document.querySelector('img[alt=\"a wide picture\"]').getBoundingClientRect().width) <= document.getElementById('root').clientWidth ? 1 : 0")
        XCTAssertEqual(wide, 1, "a big picture is fitted to the column")
        _ = try await page.js("document.querySelector('img[alt=\"a small square\"]').click(); return true;")
        let enlarged = try await page.count("body > .perch-lightbox img")
        XCTAssertEqual(enlarged, 1)
    }

    private var imagesSettled: Bool {
        var done = false
        var answered = false
        page.webView.evaluateJavaScript("[...document.images].every((i) => i.complete) && document.querySelectorAll('.image-missing').length === 1") { value, _ in
            done = (value as? Bool) ?? false
            answered = true
        }
        let until = Date().addingTimeInterval(0.3)
        while !answered, Date() < until { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005)) }
        return done
    }

    func testFrontmatter() async throws {
        func properties() async throws -> String {
            try await page.string("JSON.stringify([...document.querySelectorAll('.properties dt')].map((dt) => [dt.textContent, [...dt.nextElementSibling.querySelectorAll('.chip')].map((c) => c.textContent).join(',') || dt.nextElementSibling.textContent]))")
        }
        try await page.render(try Checkout.fixture("frontmatter-simple.md"))
        let value5 = try await properties()
        XCTAssertEqual(value5, #"[["title","Simple"],["status","draft"],["tags","trips,autumn"]]"#)
        XCTAssertEqual(page.messages(ofType: "rendered").last?["toc"] as? [[String: AnyHashable]], [["level": 1, "text": "After simple frontmatter", "line": 5]], "lines are counted from the top of the file")
        try await page.render(try Checkout.fixture("frontmatter-lists.md"))
        let value6 = try await properties()
        XCTAssertEqual(value6, #"[["title","Quoted: with colon"],["aliases","First alias,Second alias"],["tags","unindented,dashes"],["created","2026-01-05T10:00:00Z"],["empty","–"],["url","https://example.com/a?b=c"]]"#)
        try await page.render(try Checkout.fixture("frontmatter-rich.md"))
        let raw = try await page.string("document.querySelector('.properties pre')?.textContent ?? ''")
        XCTAssertTrue(raw.contains("multiline: |\n  line one"), "frontmatter too rich to list is shown as written: \(raw)")
        for name in ["frontmatter-not.md", "frontmatter-empty.md", "frontmatter-unclosed.md"] {
            try await page.render(try Checkout.fixture(name))
            let boxes = try await page.count(".properties")
            XCTAssertEqual(boxes, 0, name)
            let headings = try await page.count("h1, h2")
            XCTAssertGreaterThanOrEqual(headings, 1, name)
        }
        let unclosed = try await page.string("document.getElementById('root').innerText")
        XCTAssertTrue(unclosed.contains("Body stays visible."))
        // In a compact render (task details) there is no properties box at all.
        try await page.render(try Checkout.fixture("frontmatter-simple.md"), ["compact": true])
        let compact = try await page.count(".properties")
        XCTAssertEqual(compact, 0)
    }

    func testWindowsLineEndings() async throws {
        let markdown = try Checkout.fixture("crlf.md")
        XCTAssertTrue(markdown.contains("\r\n"))
        try await page.render(markdown)
        let html = try await page.string("document.getElementById('root').innerHTML")
        XCTAssertFalse(html.contains("\r"), "no carriage returns reach the page")
        let code = try await page.string("document.querySelector('.code-block pre code').textContent")
        XCTAssertEqual(code, "const a = 1;\nconst b = 2;\n")
        let counts = try await page.string("['li.task-list-item', 'table', '.callout', '.katex-display', 'p br'].map((s) => document.querySelectorAll(s).length).join(',')")
        XCTAssertEqual(counts, "2,1,1,1,1")
        let lines = try await page.string("[...document.querySelectorAll('li.task-list-item')].map((li) => li.dataset.line).join(',')")
        XCTAssertEqual(lines, "5,6")
        try await page.render(try Checkout.fixture("crlf-frontmatter.md"))
        page.clearMessages()
        _ = try await page.js("document.querySelector('li.task-list-item input').click(); return true;")
        try await page.wait("toggleTask") { !self.page.messages(ofType: "toggleTask").isEmpty }
        XCTAssertEqual(page.messages(ofType: "toggleTask")[0]["line"] as? Int, 6)
        let chips = try await page.count(".properties .chip")
        XCTAssertEqual(chips, 2)
    }

    // MARK: Stress

    func testStressNotes() async throws {
        for (name, blocks) in [("stress-200-code-blocks.md", 200), ("stress-5000-lines.md", 100)] {
            let markdown = try Checkout.fixture(name)
            let start = Date()
            try await page.render(markdown)
            let took = Date().timeIntervalSince(start)
            XCTAssertLessThan(took, 20, "\(name) took \(took)s")
            let errors = try await page.count(".render-error")
            XCTAssertEqual(errors, 0, name)
            let code = try await page.count(".code-block")
            XCTAssertGreaterThanOrEqual(code, blocks, name)
            let uncoloured = try await page.count(".code-block[data-lang]:not([data-highlighted])")
            XCTAssertEqual(uncoloured, 0, "\(name): every tagged block is coloured")
            let pending = try await page.count(".math[data-math=\"pending\"], .diagram[data-state=\"pending\"]")
            XCTAssertEqual(pending, 0, name)
            let fences = Fence.all(in: markdown).filter { $0.tag != "mermaid" && $0.tag != "abc" }
            let texts = try await page.string("JSON.stringify([...document.querySelectorAll('.code-block pre code')].map((c) => c.textContent))")
            XCTAssertEqual(try JSONSerialization.jsonObject(with: Data(texts.utf8)) as? [String], fences.map(\.content), "\(name): code text")
        }
    }
}
