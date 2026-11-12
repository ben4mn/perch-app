import PerchKit
import XCTest

/// Harder questions asked of the page in review: markup built to break out of it, notes replaced while
/// work is still under way, long random runs of edits, files that fail to load, and a page nobody is looking at.
@MainActor
final class RenderReviewTests: XCTestCase {
    private var page: RenderPage!
    /// A second page that only ever draws a note from nothing, to compare with.
    private var reference: RenderPage?

    override func setUp() async throws {
        page = RenderPage(width: 760, vaultRoot: Checkout.fixtures)
        try await page.ready()
    }

    override func tearDown() async throws {
        page.close()
        page = nil
        reference?.close()
        reference = nil
    }

    /// The page as text that two renders of the same note must agree on. Shadow trees (drawn diagrams) are
    /// read too; ids Mermaid numbers its drawings with are left out, since they count up over a page's life.
    private func snapshot(_ page: RenderPage) async throws -> String {
        try await page.string("""
        (() => {
          const read = (node) => {
            let html = '';
            for (const child of node.childNodes) {
              if (child.nodeType === Node.TEXT_NODE) { html += child.textContent; continue; }
              if (child.nodeType !== Node.ELEMENT_NODE) continue;
              const attributes = [...child.attributes].filter((a) => a.name !== 'style' || !child.closest('.diagram')).map((a) => ` ${a.name}="${a.value}"`).sort().join('');
              html += `<${child.localName}${attributes}>` + (child.shadowRoot ? '#shadow:' + read(child.shadowRoot) : '') + read(child) + `</${child.localName}>`;
            }
            return html;
          };
          return read(document.getElementById('root')).replace(/mermaid-\\d+/g, 'mermaid-N').replace(/abcjs-[\\w-]*\\d+/g, 'abcjs-N');
        })()
        """)
    }

    private func lineNumbers(_ page: RenderPage) async throws -> String {
        try await page.string("[...document.querySelectorAll('#root [data-line]')].map((el) => el.dataset.line).join(',')")
    }

    private func fresh(_ markdown: String, basePath: String = "note.md") async throws -> (page: String, lines: String) {
        if let reference { try await reference.startOver() } else { reference = RenderPage(width: 760, vaultRoot: Checkout.fixtures) }
        let other = reference!
        try await other.render(markdown, ["basePath": basePath])
        return (try await snapshot(other), try await lineNumbers(other))
    }

    // MARK: The harness itself

    func testAsManyPagesAsTheTestsLikeCanBeMade() async throws {
        // The 64th offscreen window with a web view in it never loads; the harness reuses them to stay under that.
        for round in 0..<150 {
            let extra = RenderPage(width: 400)
            try await extra.ready()
            try await extra.render("round \(round)")
            let text = try await extra.string("document.getElementById('root').textContent")
            XCTAssertEqual(text.trimmingCharacters(in: .whitespacesAndNewlines), "round \(round)")
            extra.close()
        }
        XCTAssertLessThan(RenderPage.webViewsMade, 30)
    }

    // MARK: Security

    func testThePageAllowsNoEvalAndNothingFromOutside() async throws {
        let policy = try await page.string("document.querySelector('meta[http-equiv]').content")
        XCTAssertFalse(policy.contains("unsafe-eval"), policy)
        XCTAssertTrue(policy.contains("script-src perch-app:;"), policy)
        for part in ["object-src 'none'", "base-uri 'none'", "form-action 'none'"] { XCTAssertTrue(policy.contains(part), part) }
        XCTAssertFalse(policy.contains("script-src perch-app: 'unsafe-inline'"))
        let tried = try await page.string("""
        (() => {
          const out = [];
          try { out.push('eval ' + eval('1 + 1')); } catch { out.push('eval blocked'); }
          try { out.push('Function ' + new Function('return 2')()); } catch { out.push('Function blocked'); }
          const script = document.createElement('script'); script.textContent = 'window.__inline = 1'; document.body.append(script); script.remove();
          out.push('inline ' + typeof window.__inline);
          return out.join(', ');
        })()
        """)
        XCTAssertEqual(tried, "eval blocked, Function blocked, inline undefined")
        // Every kind of diagram and every library still works under that policy.
        _ = try await page.js("window.__csp = []; document.addEventListener('securitypolicyviolation', (e) => window.__csp.push(e.violatedDirective + ' ' + e.blockedURI)); return true;")
        for name in ["mermaid.md", "math.md", "abc.md", "code-languages.md"] {
            try await page.render(try Checkout.fixture(name))
        }
        let blocked = try await page.string("JSON.stringify(window.__csp)")
        XCTAssertEqual(blocked, "[]", "the page's own libraries tripped its policy")
    }

    func testMarkupBuiltToBreakOutDoesNothing() async throws {
        _ = try await page.js("window.__csp = []; document.addEventListener('securitypolicyviolation', (e) => window.__csp.push(e.violatedDirective + ' ' + e.blockedURI)); return true;")
        let markdown = try Checkout.fixture("xss-more.md")
        try await page.render(markdown, ["appearance": ThemePresets.perchLight.appearance])
        _ = try await page.js("""
        for (const host of [document, ...[...document.querySelectorAll('.diagram')].map((d) => d.shadowRoot).filter(Boolean)]) {
          for (const element of host.querySelectorAll('*')) {
            for (const type of ['click', 'mouseover', 'error', 'load', 'toggle', 'focus', 'start']) { try { element.dispatchEvent(new Event(type, { bubbles: false })); } catch {} }
          }
        }
        return true;
        """)
        try await Task.sleep(nanoseconds: 500_000_000)
        // Those events don't bubble, so the page's click listener never heard them and WebKit followed the links
        // itself. RenderPage turned every one away; the app's web view does too, and opens outside only what
        // `ExternalLink` allows. That must be no more than the page's own listener passes out (a web page or an
        // email address). Before RenderPage turned them away, the tel: link offered to place a call on every run.
        let tried = page.refusedNavigations
        XCTAssertTrue(tried.contains(URL(string: "tel:+15550100")!), "the tel: link was never followed, so nothing here tests it: \(tried)")
        let passedOut = try await page.js("""
        return [...document.querySelectorAll('#root a[href]')].filter((a) => /^https?:|^mailto:/i.test(a.getAttribute('href'))).map((a) => a.href);
        """) as? [String] ?? []
        for url in tried where ExternalLink.opens(url) {
            XCTAssertTrue(passedOut.contains(url.absoluteString), "the app would hand \(url.absoluteString) to the system, which the page itself never passes out")
        }
        let ran = try await page.string("typeof window.__xss")
        XCTAssertEqual(ran, "undefined", "script from the note ran")
        let scripts = try await page.string("JSON.stringify(window.__csp.filter((v) => /script/.test(v)))")
        XCTAssertEqual(scripts, "[]", "script reached the page and only the policy stopped it")
        let last = try await page.string("document.getElementById('root').lastElementChild.textContent")
        XCTAssertEqual(last, "Survived too.")

        // Addresses: nothing left that points at the app's own files, the notebook's files, the disk or a script.
        let addresses = try await page.string("""
        JSON.stringify([document.getElementById('root'), ...[...document.querySelectorAll('.diagram')].map((d) => d.shadowRoot).filter(Boolean)].flatMap((host) => [...host.querySelectorAll('[href], [src], [srcset], [action], [formaction], [data], [poster], [background]')])
          .flatMap((el) => ['href', 'src', 'srcset', 'action', 'formaction', 'data', 'poster', 'background', 'xlink:href'].map((name) => el.getAttribute(name)).filter(Boolean))
          .filter((value) => !/^(https:\\/\\/example\\.com|#$|tel:|x$)/.test(value) && !/^perch-vault:\\/\\/vault\\/[\\w.%-]+$/.test(value)))
        """)
        XCTAssertEqual(addresses, "[]", "an address survived that the page should never hold")
        let forbidden = try await page.count("#root script, #root iframe, #root object, #root embed, #root form, #root style:not(.abc-paper style), #root link, #root meta, #root base, #root template > *, #root noscript, #root foreignObject, #root annotation-xml, #root input:not([type=checkbox i]), #root [formaction], #root [srcdoc]")
        let which = try await page.string("[...document.querySelectorAll('#root script, #root iframe, #root object, #root embed, #root form, #root style:not(.abc-paper style), #root link, #root meta, #root base, #root template > *, #root noscript, #root foreignObject, #root annotation-xml, #root input:not([type=checkbox i]), #root [formaction], #root [srcdoc]')].map((el) => el.outerHTML.slice(0, 200)).join(' | ')")
        XCTAssertEqual(forbidden, 0, which)
        let handlers = try await page.string("[document, ...[...document.querySelectorAll('.diagram')].map((d) => d.shadowRoot).filter(Boolean)].flatMap((host) => [...host.querySelectorAll('*')]).flatMap((el) => [...el.attributes].filter((a) => /^on/i.test(a.name)).map((a) => el.tagName + ' ' + a.name)).join(', ')")
        XCTAssertEqual(handlers, "", "inline event handlers survived")

        // Nothing a note writes can sit over the page, in the page or from inside a diagram.
        let placed = try await page.string("[...document.querySelectorAll('#root *')].filter((el) => ['fixed', 'sticky'].includes(getComputedStyle(el).position) || (getComputedStyle(el).position === 'absolute' && !el.closest('.code-block, .task-list-item, .diagram, .katex'))).map((el) => el.tagName + '#' + el.id).join(', ')")
        XCTAssertEqual(placed, "")
        let hosts = try await page.string("[...document.querySelectorAll('.diagram')].map((el) => getComputedStyle(el).position + ' ' + (el.getBoundingClientRect().height < 2000)).filter((v) => v !== 'static true').join(', ')")
        XCTAssertEqual(hosts, "", "a diagram's own stylesheet moved or stretched its frame")
        let wide = try await page.int("document.documentElement.scrollWidth - document.documentElement.clientWidth")
        XCTAssertEqual(wide, 0)

        // Inline styles: the allowlist again, on the page this time. Formulas and music keep their own.
        let styles = try await page.string("JSON.stringify([...document.querySelectorAll('#root [style]')].filter((el) => !el.closest('.katex, .abc-paper, .abc-audio')).map((el) => el.getAttribute('style')))")
        for style in try JSONSerialization.jsonObject(with: Data(styles.utf8)) as! [String] {
            XCTAssertNotNil(style.range(of: #"^(?:(?:color|background-color|font-size): [#\w(), .%-]+;?\s*)+$"#, options: .regularExpression), "style survived: \(style)")
        }
        // Attributes the page uses for its own bookkeeping, forged: read strictly, so they can carry nothing.
        let forged = try await page.string("['forged-ink', 'forged-tint'].map((id) => document.getElementById(id).getAttribute('style') ?? 'none').join(',')")
        XCTAssertEqual(forged, "none,none")
        // A note can't hide text by dressing its markup as a formula: the colour is still made readable.
        let dressed = try await page.string("(() => { const el = document.getElementById('fake-math'); const m = getComputedStyle(el).color.match(/[\\d.]+/g).map(Number); return [m.length === 3 || m[3] === 1, el.style.color !== ''].join(','); })()")
        XCTAssertEqual(dressed, "true,true")
        // Language labels are text.
        let labels = try await page.string("[...document.querySelectorAll('.code-lang')].filter((el) => el.children.length).length")
        XCTAssertEqual(labels, "0")

        // Clicks on forgeries: the page's own controls don't answer to copies of them, and no link takes the page anywhere.
        page.clearMessages()
        _ = try await page.js("""
        for (const anchor of document.querySelectorAll('#root a')) anchor.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
        document.querySelector('#fake-code .code-copy')?.click();
        document.querySelector('.conflict button')?.click();
        document.querySelector('#loose-box')?.click();
        document.getElementById('fake-lightbox')?.click();
        return true;
        """)
        try await Task.sleep(nanoseconds: 300_000_000)
        // Not even a move within the page: RenderPage, like the app, turned away the click on `href="#"` above.
        let here = try await page.string("location.href")
        XCTAssertEqual(here, "perch-app://app/render.html", "a link took the page away")
        XCTAssertTrue(page.messages(ofType: "copy").isEmpty, "a forged Copy button copied")
        XCTAssertTrue(page.messages(ofType: "resolveConflict").isEmpty)
        let loose = page.messages(ofType: "toggleTask").filter { ($0["line"] as? Int) != (markdown.components(separatedBy: "\n").firstIndex { $0.contains("forged-task") }) }
        XCTAssertTrue(loose.isEmpty, "a box outside a task list changed a task: \(loose)")
        for message in page.messages(ofType: "openExternal") {
            let url = message["url"] as? String ?? ""
            XCTAssertTrue(url.hasPrefix("https://") || url.hasPrefix("http://") || url.hasPrefix("mailto:"), url)
        }
        // What Swift is asked to open is checked there too; here, that every message is the shape Swift expects.
        for message in page.messages {
            switch message["type"] as? String {
            case "openNote": XCTAssertNotNil(message["path"] as? String)
            case "openWiki": XCTAssertNotNil(message["target"] as? String)
            case "saveMention": XCTAssertNotNil(message["path"] as? String); XCTAssertNotNil(message["text"] as? String)
            case "toggleTask": XCTAssertNotNil(message["line"] as? Int); XCTAssertNotNil(message["checked"] as? Bool)
            default: break
            }
        }
        let outside = page.requestedURLs.filter { !$0.hasPrefix("perch-app://app/") && !$0.hasPrefix("perch-vault://vault/") }
        XCTAssertEqual(outside, [])
        XCTAssertFalse(page.requestedURLs.contains { $0.contains("whiteboard") || $0.contains("passwd") })
    }

    func testTheReaderDrawsPickedColoursExactlyAsTheEditorDoes() async throws {
        // The table was written by the editor's own rule (FormatPalette.legible). Both sides are held to it.
        let data = try Data(contentsOf: Checkout.fixtures.appendingPathComponent("legible-colours.json"))
        let table = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let rows = table["rows"] as! [[String]], highlights = table["highlights"] as! [[String]]
        // Highlights: the wash behind, and the text on it, for the theme's own text and for picked colours.
        let washed = try await page.js("""
        return rows.map(([highlight, ground, scheme, text, kind]) => {
          const c = window.Perch.color, dark = scheme === 'dark';
          const behind = c.wash(highlight, ground, dark);
          const shown = kind === 'picked' ? c.textOnWash(text, null, ground, behind) : (c.textOnWash(null, text, ground, behind) || text);
          return [behind.toUpperCase(), shown.toUpperCase()];
        });
        """, ["rows": highlights]) as! [[String]]
        XCTAssertGreaterThan(highlights.count, 1000)
        for (row, answer) in zip(highlights, washed) {
            XCTAssertEqual(answer, [row[5], row[6]], "\(row[3]) (\(row[4])) on a \(row[0]) highlight over \(row[1])")
            if !["#000000", "#FFFFFF"].contains(answer[1]) { XCTAssertGreaterThanOrEqual(ThemeContrast.ratio(answer[1], answer[0]) ?? 0, 4.4, "\(row)") }
        }
        XCTAssertGreaterThan(rows.count, 1000)
        let answers = try await page.js("return rows.map(([colour, ground]) => window.Perch.color.legible(colour, ground).toUpperCase());", ["rows": rows]) as! [String]
        var changed = 0
        for (row, answer) in zip(rows, answers) {
            XCTAssertEqual(answer, row[2], "\(row[0]) on \(row[1])")
            if answer != row[0] { changed += 1 }
            // Readable, give or take the rounding to whole colour steps, unless it ran out of room at black or white.
            if !["#000000", "#FFFFFF"].contains(answer) { XCTAssertGreaterThanOrEqual(ThemeContrast.ratio(answer, row[1]) ?? 0, 4.4, "\(row[0]) on \(row[1]) became \(answer)") }
        }
        XCTAssertGreaterThan(changed, 300)
        XCTAssertLessThan(changed, rows.count - 300)
        // And the page uses that rule against the theme's page colour.
        for theme in [ThemePresets.perchLight, ThemePresets.perchDark] {
            try await page.render("<span style=\"color: #E8843C\">orange</span> <span style=\"color: #1B1F4B\">navy</span>", ["appearance": theme.appearance])
            let drawn = try await page.string("[...document.querySelectorAll('#root [data-ink]')].map((el) => { const m = getComputedStyle(el).color.match(/\\d+/g).map(Number); return '#' + m.slice(0, 3).map((n) => n.toString(16).padStart(2, '0')).join('').toUpperCase(); }).join(',')")
            let expected = ["#E8843C", "#1B1F4B"].map { colour in rows.first { $0[0] == colour && $0[1] == theme.background.uppercased() }![2] }.joined(separator: ",")
            XCTAssertEqual(drawn, expected, theme.id)
        }
    }

    func testFormattingTheEditorWritesIsDrawnAsTheEditorShowsIt() async throws {
        // White and pale yellow text on a light page, and black on a dark one, are moved until they can be read.
        for theme in [ThemePresets.perchLight, ThemePresets.perchDark] + ThemePresets.all.filter({ ["paper", "nord", "solarized-light"].contains($0.id) }) {
            try await page.render("<span style=\"color: #FFFFFF\">white</span> <span style=\"color: #FFF36B\">yellow</span> <span style=\"color: #000000\">black</span>\n\n<mark style=\"background-color: #D94F3D\">plain on red, <span style=\"color: #D94F3D\">red on red</span>, <span style=\"color: #FFFFFF\">white on red</span></mark> <mark style=\"background-color: #1B1F4B\">on navy</mark> <mark style=\"background-color: #FFF36B\">on yellow <span style=\"color: #C99A1B\">amber</span></mark>\n", ["appearance": theme.appearance])
            let seen = try await page.string("""
            JSON.stringify((() => {
              const hex = (value) => { const m = value.match(/[\\d.]+/g).map(Number); return '#' + m.slice(0, 3).map((n) => Math.round(n).toString(16).padStart(2, '0')).join(''); };
              const page = hex(getComputedStyle(document.documentElement).getPropertyValue('--perch-bg').trim().replace(/^#(..)(..)(..)$/, (_, r, g, b) => `rgb(${parseInt(r, 16)}, ${parseInt(g, 16)}, ${parseInt(b, 16)})`));
              const out = { page, text: [], washed: [] };
              for (const el of document.querySelectorAll('#root p:first-of-type > [data-ink]')) out.text.push(hex(getComputedStyle(el).color));
              for (const mark of document.querySelectorAll('#root mark')) {
                const behind = window.Perch.color.wash(mark.dataset.tint, page, document.documentElement.dataset.scheme === 'dark');
                out.washed.push([behind, hex(getComputedStyle(mark).color)]);
                for (const inner of mark.querySelectorAll('[data-ink]')) out.washed.push([behind, hex(getComputedStyle(inner).color)]);
              }
              return out;
            })())
            """)
            let result = try JSONSerialization.jsonObject(with: Data(seen.utf8)) as! [String: Any]
            XCTAssertEqual((result["page"] as? String)?.uppercased(), theme.background.uppercased())
            for colour in result["text"] as! [String] {
                XCTAssertGreaterThanOrEqual(ThemeContrast.ratio(colour, theme.background) ?? 0, 4.4, "\(colour) as text on \(theme.id)")
            }
            let pairs = result["washed"] as! [[String]]
            XCTAssertEqual(pairs.count, 6)
            for pair in pairs {
                XCTAssertGreaterThanOrEqual(ThemeContrast.ratio(pair[1], pair[0]) ?? 0, 4.4, "\(pair[1]) on a highlight that shows as \(pair[0]) in \(theme.id)")
            }
        }

        // A callout whose title is coloured, in part or whole, is still one callout with its title in the title.
        let titles = [
            ("> [!tip] <span style=\"color: #A855C7\">Purple title</span>\n> body", "Purple title", "body"),
            ("> [!tip] Plain <span style=\"color: #A855C7\">purple</span> end\n> body", "Plain purple end", "body"),
            ("> [!tip] <mark style=\"background-color: #D4588F\">Marked</mark> and <u>under</u>\n> body\n> more", "Marked and under", "body\nmore"),
            ("> <span style=\"color: #A855C7\">[!tip] Whole line coloured</span>\n> body", "Whole line coloured", "body"),
            ("> <u>[!warning]</u>\n> body", "Warning", "body"),
            ("> [!tip]- <span style=\"font-size: 1.3em\"><span style=\"color: #D94F3D\">Folded big red</span></span>\n> body", "Folded big red", "body"),
            ("> [!tip] <span style=\"color: #A855C7\">Only a title</span>", "Only a title", ""),
        ]
        for (markdown, title, body) in titles {
            try await page.render(markdown)
            let drawn = try await page.string("JSON.stringify([document.querySelectorAll('#root > .callout').length, document.querySelectorAll('#root > *').length, document.querySelector('.callout-title')?.textContent.trim() ?? '', document.querySelector('.callout-body')?.textContent.trim() ?? '', document.getElementById('root').textContent.includes('[!')])")
            let expected = try String(data: JSONSerialization.data(withJSONObject: [1, 1, title, body, false] as [Any]), encoding: .utf8)!
            XCTAssertEqual(drawn, expected, markdown)
        }

        // An aligned block aligns everything in it, and list markers and task boxes stay beside their text.
        let aligned = "<div align=\"center\">\n\n# Heading\n\nPara\n\n- item one\n\n1. first\n\n- [ ] task\n\n> quote\n\n| a | b |\n| --- | --- |\n| 1 | 2 |\n\n</div>\n\n<div align=\"right\">\n\n## Right\n\nPara\n\n- item\n\n- [ ] task\n\n> quote\n\n| a | b |\n| --- | --- |\n| 1 | 2 |\n\n</div>\n\nAfter.\n"
        for width in [760, 380] {
            try await page.resize(width: CGFloat(width))
            try await page.render(aligned)
            let measured = try await page.string("""
            JSON.stringify([...document.querySelectorAll('#root > div[align]')].map((block) => {
              const inner = block.getBoundingClientRect();
              const textOf = (el) => { const range = document.createRange(); range.selectNodeContents(el); return range.getBoundingClientRect(); };
              const places = {};
              for (const el of block.querySelectorAll('h1, h2, p, li, .table-wrap')) {
                const text = el.matches('.table-wrap') ? el.getBoundingClientRect() : textOf(el);
                const name = el.matches('.task-list-item') ? 'task' : el.closest('blockquote') ? 'quote' : el.localName === 'div' ? 'table' : el.localName;
                places[name] = [Math.round(text.left - inner.left), Math.round(inner.right - text.right)];
              }
              const box = block.querySelector('.task-list-item input').getBoundingClientRect(), task = textOf(block.querySelector('.task-list-item'));
              const item = block.querySelector('ul > li:not(.task-list-item)');
              const lines = Math.round(item.getBoundingClientRect().height / parseFloat(getComputedStyle(item).lineHeight));
              return { align: block.getAttribute('align'), places, boxGap: Math.round(task.right - box.left), marker: getComputedStyle(item, '::before').content, lines };
            }))
            """)
            let blocks = try JSONSerialization.jsonObject(with: Data(measured.utf8)) as! [[String: Any]]
            XCTAssertEqual(blocks.count, 2)
            for block in blocks {
                let places = block["places"] as! [String: [Int]]
                XCTAssertEqual(Set(places.keys), ["h1", "p", "li", "task", "quote", "table"].reduce(into: Set<String>()) { $0.insert($1 == "h1" && block["align"] as? String == "right" ? "h2" : $1) }, "\(places)")
                for (name, gaps) in places {
                    if block["align"] as? String == "center" {
                        // Quotes have a bar and padding on the left, and markers sit left of their text: near enough is centred.
                        XCTAssertLessThan(abs(gaps[0] - gaps[1]), name == "quote" || name == "li" || name == "task" ? 40 : 3, "\(name) in a centred block at \(width): \(gaps)")
                    } else {
                        XCTAssertLessThan(gaps[1], 4, "\(name) in a right-aligned block at \(width): \(gaps)")
                        XCTAssertGreaterThan(gaps[0], 60, "\(name) in a right-aligned block at \(width): \(gaps)")
                    }
                }
                XCTAssertTrue((block["marker"] as? String ?? "").contains("•"), "a list's marker is written beside its text")
                XCTAssertEqual(block["lines"] as? Int, 1, "marker and text share a line")
                XCTAssertLessThan(block["boxGap"] as! Int, 90, "the task's box is beside its text, not out at the far margin")
            }
        }
    }

    // MARK: Notes replaced mid-flight, and long runs

    func testANoteReplacedWhileItsLibrariesLoadLeavesNothingBehind() async throws {
        let first = try Checkout.fixture("bench-5-mermaid.md") + "\n\n" + (try Checkout.fixture("math.md")) + "\n\n" + (try Checkout.fixture("abc.md"))
        let second = try Checkout.fixture("bench-typical.md")
        // No waiting between them: the first note's libraries are still on their way when the second arrives.
        try await page.call("render", ["markdown": first, "basePath": "a.md"])
        try await page.call("render", ["markdown": second, "basePath": "b.md"])
        try await page.call("render", ["markdown": first, "basePath": "a.md"])
        try await page.call("render", ["markdown": second, "basePath": "b.md"])
        try await page.settle()
        try await Task.sleep(nanoseconds: 300_000_000)
        try await page.settle()
        let now = try await snapshot(page)
        let clean = try await fresh(second, basePath: "b.md").page
        XCTAssertEqual(now, clean, "the page shows the second note and only the second note")
        let strays = try await page.string("[document.querySelectorAll('#root .diagram[data-kind=abc]').length, document.querySelectorAll('body > :not(#root):not(script)').length, document.querySelectorAll('[id^=dmermaid], body > [id^=mermaid]').length].join(',')")
        XCTAssertEqual(strays, "0,0,0", "something of the first note, or of a library's scratch work, is still on the page")
        XCTAssertEqual(page.messages(ofType: "rendered").count, 4, "one answer for each render asked for")
        let pending = try await page.count(".math[data-math=pending], .diagram[data-state=pending]")
        XCTAssertEqual(pending, 0)
    }

    func testThreeHundredNotesInOnePageLeaveNoPile() async throws {
        let names = ["bench-typical.md", "lists.md", "tables.md", "callouts.md", "math.md", "mermaid.md", "code-edge.md", "inline.md", "formatting.md", "abc.md", "images.md", "html.md"]
        let notes = try names.map { try Checkout.fixture($0) }
        func counts() async throws -> [Int] {
            let text = try await page.string("JSON.stringify([document.getElementsByTagName('*').length, document.head.childElementCount, document.body.childElementCount, document.styleSheets.length, document.querySelectorAll('#root > *').length])")
            return try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [Int]
        }
        // Once around first, so every library and stylesheet the notes need is already in.
        for (index, note) in notes.enumerated() { try await page.render(note, ["basePath": "warm-\(index).md"]) }
        try await page.render("# Small\n\ntext", ["basePath": "small.md"])
        let before = try await counts()
        page.clearMessages()
        for round in 0..<300 {
            // Each note is a different note to the page (its own path), some with a paragraph of their own.
            let markdown = notes[round % notes.count] + "\n\nRound \(round).\n"
            try await page.call("render", ["markdown": markdown, "basePath": "note-\(round).md"])
            // Most are replaced before their drawing is done, as when someone flicks through a list.
            if round % 7 == 0 { try await page.settle() }
        }
        try await page.render("# Small\n\ntext", ["basePath": "small.md"])
        let after = try await counts()
        XCTAssertEqual(after, before, "elements, head children, body children, stylesheets, blocks: back to where a small note started")
        XCTAssertEqual(page.messages(ofType: "rendered").count, 301)
        let idle = try await page.string("await window.Perch.settle()")
        XCTAssertEqual(idle, "true")
        // The page still answers a click once, not once per note it has shown.
        try await page.render("- [ ] one box\n", ["basePath": "box.md"])
        page.clearMessages()
        _ = try await page.js("document.querySelector('li.task-list-item input').click(); return true;")
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(page.messages(ofType: "toggleTask").count, 1)
    }

    func testAnyRunOfEditsEndsOnThePageAFreshRenderGives() async throws {
        struct Random {
            var state: UInt64
            mutating func next(_ bound: Int) -> Int {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return Int((state >> 33) % UInt64(max(bound, 1)))
            }
        }
        // Lines that change what other blocks mean: fences opening and closing, link and footnote
        // definitions, raw HTML left open, list and quote markers, blank lines.
        let extras = ["```", "```js", "~~~", "", "", "[ref]: https://example.com/changed", "[^1]: A footnote that changed.", "Text with a [link][ref] and a note[^1].",
                      "<details>", "</details>", "<div align=\"center\">", "</div>", "- item", "  - nested", "> quote", "> [!note] Title", "| a | b |", "| --- | --- |",
                      "$$", "$x^2$ inline", "# Heading", "---", "1. one", "    indented code", "- [ ] task", "Same line.", "Same line.", "<span style=\"color: #D94F3D\">red</span>",
                      "```mermaid", "flowchart LR", "  A --> B", "[[Wiki Target]]", ":::conflict{variant=a}", ":::", "==mark== and `code`", "![pic](pixel.png)"]
        let steps = Int(ProcessInfo.processInfo.environment["PERCH_RENDER_EDIT_STEPS"] ?? "") ?? 45
        for (number, name) in ["inline.md", "lists.md", "code-edge.md", "tables.md", "callouts.md", "html.md", "math.md", "formatting.md"].enumerated() {
            var random = Random(state: UInt64(1000 + number))
            var lines = try Checkout.fixture(name).components(separatedBy: "\n")
            try await page.render(lines.joined(separator: "\n"), ["basePath": name])
            var history: [String] = []
            for step in 0..<steps {
                let at = random.next(lines.count)
                switch random.next(6) {
                case 0, 1:
                    let line = extras[random.next(extras.count)]
                    lines.insert(line, at: at)
                    history.append("insert \(line.debugDescription) at \(at)")
                case 2:
                    if lines.count > 3 { history.append("delete \(at): \(lines[at].debugDescription)"); lines.remove(at: at) }
                case 3:
                    let line = extras[random.next(extras.count)]
                    history.append("replace \(at) with \(line.debugDescription)")
                    lines[at] = line
                case 4:
                    // A block moved: a few lines cut from one place and put in another.
                    let length = min(1 + random.next(6), lines.count - at)
                    let cut = Array(lines[at..<(at + length)])
                    lines.removeSubrange(at..<(at + length))
                    let to = random.next(lines.count)
                    lines.insert(contentsOf: cut, at: to)
                    history.append("move \(length) lines from \(at) to \(to)")
                default:
                    lines[at] += " x"
                    history.append("type at the end of \(at)")
                }
                let markdown = lines.joined(separator: "\n")
                page.clearMessages()
                // Most steps don't wait for drawing to finish, as typing doesn't.
                try await page.call("render", ["markdown": markdown, "basePath": name])
                XCTAssertEqual(page.messages(ofType: "rendered").count, 1, "one answer per render")
                guard step % 3 == 2 || step == steps - 1 else { continue }
                try await page.settle()
                let reached = try await snapshot(page)
                let (clean, cleanNumbering) = try await fresh(markdown, basePath: name)
                if reached != clean {
                    let differs = zip(reached, clean).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? min(reached.count, clean.count)
                    let around = { (text: String) in String(text.dropFirst(max(0, differs - 120)).prefix(300)) }
                    XCTFail("\(name) step \(step): the page reached by edits is not the page a fresh render gives.\nLast edits: \(history.suffix(4))\nReached: …\(around(reached))\nFresh:   …\(around(clean))")
                    return
                }
                // The lines blocks say they came from are right too: they decide which task a click ticks.
                let numbering = try await lineNumbers(page)
                XCTAssertEqual(numbering, cleanNumbering, "\(name) step \(step): source lines")
            }
        }
    }

    func testScrollPositionIsKeptThroughEditsAndBackgroundDrawing() async throws {
        let markdown = try Checkout.fixture("stress-200-code-blocks.md")
        try await page.render(markdown)
        try await page.call("scrollTo", ["fraction": 0.5])
        let lines = markdown.components(separatedBy: "\n")
        let anchor = try await page.string("(() => { const el = [...document.querySelectorAll('#root > h2, #root > p')].find((e) => e.getBoundingClientRect().top >= 0); window.__anchor = el; return String(Math.round(el.getBoundingClientRect().top)); })()")
        // An edit near the top that adds a paragraph (the page gets taller above the reader), then one below.
        var edited = lines
        edited[2] += " edited"
        try await page.call("render", ["markdown": edited.joined(separator: "\n"), "basePath": "note.md"])
        try await page.settle()
        let afterEdit = try await page.string("String(Math.round(window.__anchor.getBoundingClientRect().top)) + ',' + window.__anchor.isConnected")
        XCTAssertEqual(afterEdit, anchor + ",true", "typing a word far above doesn't move what is being read")
        edited[lines.count - 3] += " edited"
        try await page.call("render", ["markdown": edited.joined(separator: "\n"), "basePath": "note.md"])
        try await page.settle()
        let afterSecond = try await page.string("String(Math.round(window.__anchor.getBoundingClientRect().top))")
        XCTAssertEqual(afterSecond, anchor)
    }

    func testPicturesFarDownThePageAreLoadedBeforeAPDFIsMade() async throws {
        // Pictures below what is showing wait until the reader gets near them. A PDF takes in the whole
        // page, and used to come out with empty spaces where those pictures were.
        let filler = (0..<120).map { "Paragraph \($0) of filler, long enough to push the pictures far down the page." }.joined(separator: "\n\n")
        let markdown = filler + "\n\n![big](wide.png)\n\n![small](pixel.png)\n\n![gone](missing.png)\n\nEnd.\n"
        try await page.call("render", ["markdown": markdown, "basePath": "note.md"])
        try await page.settle()
        let loaded = try await page.string("[...document.querySelectorAll('#root img')].map((img) => img.complete && img.naturalWidth > 0).join(',') + '|' + document.querySelectorAll('.image-missing').length")
        XCTAssertEqual(loaded, "true,true|1", "every picture that exists is in, and the one that doesn't says so")
        let data = try await page.webView.pdf()
        XCTAssertGreaterThan(data.count, 2000)
    }

    func testAWideDiagramOnAPhoneStaysReadableAndScrollsSideways() async throws {
        try await page.resize(width: 380)
        let wide = "```mermaid\nflowchart LR\n  " + (1...14).map { "N\($0)[Step number \($0)]" }.joined(separator: " --> ") + "\n```\n\n```mermaid\nflowchart LR\n  A --> B\n```\n"
        try await page.render(wide)
        let measured = try await page.string("""
        JSON.stringify([...document.querySelectorAll('.diagram')].map((el) => { const svg = el.shadowRoot.querySelector('svg'); const natural = svg.viewBox.baseVal.width; const shown = svg.getBoundingClientRect().width;
          return [Math.round(100 * shown / natural), el.scrollWidth > el.clientWidth + 1, Math.round(el.getBoundingClientRect().right) <= innerWidth, Math.abs((svg.getBoundingClientRect().left - el.getBoundingClientRect().left) - (el.getBoundingClientRect().right - svg.getBoundingClientRect().right)) < 2]; }))
        """)
        // The long one keeps 60% of its size and scrolls inside its frame; the small one is whole, at full size, centred.
        XCTAssertEqual(measured, "[[60,true,true,false],[100,false,true,true]]")
        let overflow = try await page.int("document.documentElement.scrollWidth - document.documentElement.clientWidth")
        XCTAssertEqual(overflow, 0, "the page itself never scrolls sideways")
    }

    // MARK: Files that fail to load

    func testALibraryThatCannotBeLoadedLeavesThePlainBlock() async throws {
        page.failRequests(containing: ["/chunks/", "render-katex.css"])
        let markdown = "# Title\n\n```swift\nlet x = 1\n```\n\nInline $x^2$.\n\n$$\ny = mx + b\n$$\n\n```mermaid\nflowchart LR\n  A --> B\n```\n\n```abc\nX:1\nK:C\nCDEF|\n```\n\nEnd.\n"
        try await page.render(markdown)
        let shown = try await page.string("""
        JSON.stringify({
          code: document.querySelector('.code-block pre code').textContent,
          coloured: document.querySelectorAll('.code-block[data-highlighted]').length,
          math: [...document.querySelectorAll('.math')].map((el) => el.textContent.trim()),
          diagrams: [...document.querySelectorAll('.diagram')].map((el) => el.dataset.state + ':' + (el.querySelector('pre.source')?.textContent.includes(el.dataset.kind === 'abc' ? 'CDEF' : 'A --> B') ?? false)),
          end: document.getElementById('root').lastElementChild.textContent,
        })
        """)
        XCTAssertEqual(shown, #"{"code":"let x = 1\n","coloured":0,"math":["x^2","y = mx + b"],"diagrams":["error:true","error:true"],"end":"End."}"#, "everything is readable as written")
        XCTAssertEqual(page.messages(ofType: "settled").count, 1, "the page still says when it has done all it can")
        // A browser never asks twice for a script that failed, so the page can't recover by itself; the next
        // page to load does (the app loads a new one for each note it opens).
        page.failRequests(containing: [])
        try await page.startOver()
        try await page.render(markdown + "\nAgain.\n")
        let recovered = try await page.string("[document.querySelectorAll('.code-block[data-highlighted]').length, document.querySelectorAll('.math .katex').length, [...document.querySelectorAll('.diagram')].filter((el) => el.dataset.state === 'done').length].join(',')")
        XCTAssertEqual(recovered, "1,2,2")
    }

    // MARK: A page nobody is looking at

    func testBackgroundDrawingWaitsWhileThePageIsHiddenAndWorksInShortSlices() async throws {
        // The test window counts as hidden or shown depending on the machine; say which, both ways.
        _ = try await page.js("window.__hidden = true; Object.defineProperty(document, 'hidden', { configurable: true, get: () => window.__hidden }); return true;")
        let markdown = try Checkout.fixture("stress-200-code-blocks.md")
        try await page.call("render", ["markdown": markdown, "basePath": "note.md"])
        try await Task.sleep(nanoseconds: 400_000_000)
        let text = try await page.count(".code-block")
        XCTAssertEqual(text, 200, "the text is there at once, seen or not")
        let waiting = try await page.count(".code-block[data-highlighted]")
        XCTAssertEqual(waiting, 0, "no colouring while nobody is looking")
        XCTAssertTrue(page.messages(ofType: "settled").isEmpty)
        // Shown again: the work picks up, a slice at a time.
        _ = try await page.js("window.__hidden = false; document.dispatchEvent(new Event('visibilitychange')); return true;")
        try await page.wait("the page to finish once shown") { !self.page.messages(ofType: "settled").isEmpty }
        let done = try await page.count(".code-block[data-highlighted]")
        XCTAssertGreaterThan(done, 150)
        let timing = page.messages(ofType: "settled").last?["timing"] as? [String: Any]
        let slices = timing?["slices"] as? Int ?? 0, longest = timing?["longestSlice"] as? Double ?? 999
        XCTAssertGreaterThan(slices, 3, "200 blocks are not coloured in one go: \(String(describing: timing))")
        // A slice aims for 8 ms and ends after the block that crosses it. Loose, for a machine busy with other tests.
        XCTAssertLessThan(longest, 60, "one slice held the page for \(longest) ms")
        // Hidden again, with a PDF asked for: settle() finishes the work regardless.
        _ = try await page.js("window.__hidden = true; return true;")
        try await page.call("render", ["markdown": markdown.replacingOccurrences(of: "let", with: "var"), "basePath": "other.md"])
        try await page.settle()
        let forPDF = try await page.count(".code-block[data-highlighted]")
        XCTAssertGreaterThan(forPDF, 150, "a PDF waits for everything, hidden or not")
    }
}
