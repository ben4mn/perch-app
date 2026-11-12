import PerchKit
import XCTest

/// Hostile notes, the inline-style allowlist, and colours that have to stay readable on every theme.
@MainActor
final class RenderSafetyTests: XCTestCase {
    private var page: RenderPage!

    override func setUp() async throws {
        page = RenderPage(width: 760, vaultRoot: Checkout.fixtures)
        try await page.ready()
    }

    override func tearDown() async throws {
        page.close()
        page = nil
    }

    func testAHostileNoteRunsNothing() async throws {
        try await page.render(try Checkout.fixture("xss.md"))
        // Give error handlers, timers and loads every chance to fire, then poke at what's left.
        _ = try await page.js("""
        for (const element of document.querySelectorAll("#root *")) {
          for (const type of ["click", "mouseover", "error", "load", "toggle", "focus"]) {
            try { element.dispatchEvent(new Event(type, { bubbles: false })); } catch {}
          }
        }
        return true;
        """)
        try await Task.sleep(nanoseconds: 400_000_000)
        let ran = try await page.string("typeof window.__xss")
        XCTAssertEqual(ran, "undefined", "script from the note ran")
        let forbidden = try await page.count("#root script, #root iframe, #root object, #root embed, #root form, #root style, #root link, #root meta, #root base, #root input:not([type=checkbox]), #root button:not(.code-copy), #root textarea, #root select")
        XCTAssertEqual(forbidden, 0)
        let handlers = try await page.string("[...document.querySelectorAll('#root *')].flatMap((el) => [...el.attributes].filter((a) => /^on/i.test(a.name)).map((a) => el.tagName + ' ' + a.name)).join(', ')")
        XCTAssertEqual(handlers, "", "inline event handlers survived")
        let links = try await page.string("[...document.querySelectorAll('#root [href], #root [src], #root [action], #root [xlink\\\\:href]')].map((el) => el.getAttribute('href') ?? el.getAttribute('src') ?? '').filter((v) => /^\\s*(javascript|vbscript|data:text\\/html)/i.test(v)).join(', ')")
        XCTAssertEqual(links, "", "script URLs survived")
        let shown = try await page.string("getComputedStyle(document.getElementById('root')).display + ',' + getComputedStyle(document.body).backgroundColor")
        XCTAssertEqual(shown, "block,rgba(0, 0, 0, 0)", "a <style> in the note changed the page")
        let last = try await page.string("document.getElementById('root').lastElementChild.textContent")
        XCTAssertEqual(last, "Survived.")
        // Inline styles: only the harmless declarations are left.
        let styles = try await page.string("JSON.stringify([...document.querySelectorAll('#root [style]')].filter((el) => !el.closest('.math, .diagram')).map((el) => el.getAttribute('style')))")
        let found = try JSONSerialization.jsonObject(with: Data(styles.utf8)) as! [String]
        let allowed = try NSRegularExpression(pattern: #"^(?:(?:color|background-color|font-size|text-align|font-weight|font-style|text-decoration): [#\w(), .%-]+;?\s*)+$"#)
        for style in found {
            XCTAssertNotNil(allowed.firstMatch(in: style, range: NSRange(style.startIndex..., in: style)), "style survived: \(style)")
            for banned in ["url", "position", "expression", "var(", "important", "behavior", "binding", "import", "inset", "z-index", "display", "width"] {
                XCTAssertFalse(style.lowercased().contains(banned), "\(banned) in \(style)")
            }
        }
        let overlay = try await page.string("(() => { const el = document.getElementById('overlay'); const style = getComputedStyle(el); return [style.position, el.getBoundingClientRect().height < 60].join(','); })()")
        XCTAssertEqual(overlay, "static,true", "a note can't cover the page")
        let huge = try await page.string("parseFloat(getComputedStyle([...document.querySelectorAll('#root span')].find((el) => el.textContent === 'huge')).fontSize) < 40")
        XCTAssertEqual(huge, "true")
        // Nothing was fetched from outside the app.
        let outside = page.requestedURLs.filter { !$0.hasPrefix("perch-app://") && !$0.hasPrefix("perch-vault://") }
        XCTAssertEqual(outside, [])
        // Markup that imitates the page's own controls gets none of their powers.
        page.clearMessages()
        _ = try await page.js("document.querySelector('[data-conflict]')?.querySelector('button')?.click(); return true;")
        XCTAssertTrue(page.messages(ofType: "resolveConflict").isEmpty)
        let fakeLightbox = try await page.count("body > .perch-lightbox")
        XCTAssertEqual(fakeLightbox, 0)
    }

    func testHostileNoteStaysHarmlessThroughEditsAndAppearanceChanges() async throws {
        let markdown = try Checkout.fixture("xss.md")
        try await page.render(markdown)
        try await page.render(markdown.replacingOccurrences(of: "Survived.", with: "Survived again."))
        try await page.call("setAppearance", ThemePresets.perchDark.appearance)
        try await page.render("<img src=x onerror=\"window.__xss=1\">\n\n" + markdown, ["compact": true])
        try await Task.sleep(nanoseconds: 300_000_000)
        let ran = try await page.string("typeof window.__xss")
        XCTAssertEqual(ran, "undefined")
        let handlers = try await page.count("#root [onerror], #root [onclick], #root [onload], #root script")
        XCTAssertEqual(handlers, 0)
    }

    func testAppearanceValuesAreChecked() async throws {
        try await page.render("# Title\n\ntext")
        try await page.call("setAppearance", [
            "variables": ["--perch-bg": "url(https://example.com/x.png)", "--perch-text": "red; } body { display: none", "--other": "#fff", "--perch-accent": "#112233"],
            "fontBody": "x; background: url(//example.com)", "attributes": ["properties": "<script>", "onload": "x"],
        ])
        let applied = try await page.string("[document.documentElement.style.getPropertyValue('--perch-bg'), document.documentElement.style.getPropertyValue('--perch-text'), document.documentElement.style.getPropertyValue('--other'), document.documentElement.style.getPropertyValue('--perch-accent'), document.documentElement.style.getPropertyValue('--perch-font-body'), document.documentElement.dataset.properties ?? '', document.documentElement.getAttribute('onload') ?? ''].join('|')")
        XCTAssertEqual(applied, "|||#112233|||")
    }

    func testInlineStyleAllowlist() async throws {
        let cases: [(String, String)] = [
            ("color: #D94F3D", "color: #d94f3d"),
            ("color:#abc;font-size:1.3em", "color: #abc; font-size: 1.3em"),
            ("background-color: rgb(1, 2, 3)", "background-color: rgb(1, 2, 3)"),
            ("color: hsl(210, 80%, 45%)", "color: hsl(210, 80%, 45%)"),
            ("color: RebeccaPurple", "color: rebeccapurple"),
            ("font-size: 0.85em", "font-size: 0.85em"),
            ("font-size: 2em", "font-size: 2em"),
            ("font-size: 2.01em", ""),
            ("font-size: 0.69em", ""),
            ("font-size: 900em", ""),
            ("font-size: 20px", ""),
            ("font-size: 1e9em", ""),
            ("font-size: calc(100em)", ""),
            ("text-align: center", "text-align: center"),
            ("text-align: justify", ""),
            ("font-weight: bold; font-style: italic; text-decoration: underline", "font-weight: bold; font-style: italic; text-decoration: underline"),
            ("text-decoration: underline line-through", "text-decoration: underline line-through"),
            ("text-decoration: underline url(x)", ""),
            ("background: url(javascript:alert(1))", ""),
            ("background-color: url(x)", ""),
            ("background-image: url('https://example.com/t.png')", ""),
            ("position: fixed; inset: 0; z-index: 9; display: block; width: 100vw", ""),
            ("color: red; behavior: url(x.htc)", "color: red"),
            ("color: expression(alert(1))", ""),
            ("color: var(--x, url(https://example.com))", ""),
            ("color: var(--perch-accent)", ""),
            ("color: red !important", ""),
            ("color: red; @import url(x.css)", "color: red"),
            ("color: r\\65 d", ""),
            ("color: red /* x */", ""),
            ("color: red; color: transparent", "color: red"),
            ("color: currentcolor", ""),
            ("color: #12345", ""),
            ("COLOR: RED; Font-Size: 1.15EM", "color: red; font-size: 1.15em"),
            ("color: red;;; ;font-size:1.6em;", "color: red; font-size: 1.6em"),
            ("color: red}; body{display:none", ""),
            ("-webkit-text-fill-color: red; filter: blur(9px); opacity: 0; transform: scale(99); content: 'x'", ""),
            ("font: 900em x; margin: -999px; float: right; line-height: 99", ""),
            ("", ""),
            // Tricks with how CSS is written.
            ("co/**/lor: red", ""),
            ("color/**/: red", ""),
            ("\\63olor: red", ""),
            ("c\\6f lor: red", ""),
            ("color: red; unicode-bidi: bidi-override; direction: rtl", "color: red"),
            ("color: red; font-family: 'a;color:blue'; background-color: #fff url(https://example.com/s.png)", "color: red"),
            ("color: red; font-family: \"a;font-size:1.3em;b\"", "color: red; font-size: 1.3em"),
            ("color: rgb(calc(1), 2, 3)", ""),
            ("color: rgb(1 2 3 / 0)", "color: rgb(1 2 3 / 0)"),
            ("color: rgb(from red r g b)", ""),
            ("color: color-mix(in srgb, red, blue)", ""),
            ("color: light-dark(red, url(x))", ""),
            ("color: image-set('https://example.com/i.png' 1x)", ""),
            ("background-color: -webkit-image-set(url(https://example.com/j.png) 1x)", ""),
            ("background-color: element(#root)", ""),
            ("font-size: 999em; font-size: 1e2em; font-size: +1.5em; font-size: 1.5EM", "font-size: 1.5em"),
            ("font-size: 1.5em; font-size: 999em", "font-size: 1.5em"),
            ("font-size: -1.5em", ""),
            ("font-size: 1.5 em", ""),
            ("font-size: 1.5em 2em", ""),
            ("font-size: 150%", ""),
            ("font-size: xx-large", ""),
            ("font-size: 1.5rem", ""),
            ("font-size: 0x1em", ""),
            ("font-size: 1.5em\u{0}", ""),
            ("COLOR: RED; -webkit-text-fill-color: transparent; -webkit-mask: url(https://example.com/m.png)", "color: red"),
            ("position: fixed; top: 0; left: 0; inset: 0; z-index: 2147483647; color: red", "color: red"),
            ("color: red; color: url(https://example.com/dup)", "color: red"),
            ("color: red; color: blue", "color: blue"),
            ("color: red\n;background-image: url(https://example.com/nl.png)", "color: red"),
            ("color: red; --perch-bg: red; --x: url(https://example.com)", "color: red"),
            ("color: red; text-align: center; text-align: -webkit-center", "color: red; text-align: center"),
            ("font-weight: 1000; font-weight: 950", ""),
            ("text-decoration: underline wavy red 99em", ""),
            ("color : red ; background-color\t:\t#00ff00", "color: red; background-color: #00ff00"),
            ("color:red;color:RED;COLOR:Red", "color: red"),
            ("color: red; cOlOr: transparent; color: inherit; color: initial; color: unset", "color: red"),
            ("color: #ff00ff00", "color: #ff00ff00"),
            ("width: 5000px; height: 5000px; margin-left: -5000px; display: none; visibility: hidden; opacity: 0", ""),
            ("animation: x 1s infinite; transition: all 1s; cursor: url(x), auto; pointer-events: none", ""),
            ("content: url(x); counter-reset: a; quotes: '<' '>'", ""),
            (String(repeating: "color: red; ", count: 400), ""),
            ("color: " + String(repeating: "a", count: 300), ""),
        ]
        for (input, expected) in cases {
            let clean = try await page.js("return window.Perch.color.cleanStyle(style);", ["style": input]) as? String
            XCTAssertEqual(clean, expected, "cleanStyle(\(input))")
        }
    }

    func testFormattingFromTheEditorRendersEverywhere() async throws {
        try await page.render(try Checkout.fixture("formatting.md"), ["appearance": ThemePresets.perchLight.appearance])
        let inked = try await page.count("#root [data-ink]")
        XCTAssertEqual(inked, 31)
        let tinted = try await page.count("#root mark[data-tint]")
        XCTAssertEqual(tinted, 18)
        let inside = try await page.string("[...document.querySelectorAll('#root span[data-ink]')].find((el) => el.querySelector('strong')).innerHTML")
        for piece in ["<strong>bold</strong>", "<em>italic</em>", "<code>code</code>", "class=\"wikilink\""] { XCTAssertTrue(inside.contains(piece), "Markdown inside a coloured span: \(inside)") }
        let places = try await page.string("['h3', 'li', 'li.task-list-item', 'blockquote', '.callout-title', '.callout-body', 'td', 'div[align]'].map((s) => document.querySelectorAll(`#root ${s} [data-ink], #root ${s} [data-tint], #root ${s} u`).length > 0).join(',')")
        XCTAssertEqual(places, "true,true,true,true,true,true,true,false")
        let sizes = try await page.string("[...document.querySelectorAll('#root span')].filter((el) => el.style.fontSize).map((el) => el.style.fontSize).join(',')")
        XCTAssertEqual(sizes, "0.85em,1.15em,1.3em,1.6em,1.3em,1.3em")
        let rejected = try await page.string("[...document.querySelectorAll('h2')].find((h) => h.textContent === 'Rejected styles').nextElementSibling.innerHTML")
        XCTAssertFalse(rejected.contains("style="), rejected)
        let underline = try await page.string("getComputedStyle(document.querySelector('#root u')).textDecorationLine")
        XCTAssertEqual(underline, "underline")
        let aligned = try await page.string("[...document.querySelectorAll('#root div[align]')].map((el) => getComputedStyle(el.querySelector('p')).textAlign + ':' + el.querySelectorAll('strong, a.wikilink, li').length).join(',')")
        XCTAssertEqual(aligned, "center:2,right:1,center:4,right:3")
        // The author's colour is kept beside the drawn one, and is what the note says.
        let kept = try await page.string("document.querySelector('#root [data-ink]').dataset.ink")
        XCTAssertEqual(kept, "rgb(217, 79, 61)")
    }

    private func hue(_ hex: String) -> Double? {
        guard let color = ThemeRGB(hex: hex) else { return nil }
        let high = max(color.red, color.green, color.blue), low = min(color.red, color.green, color.blue), spread = high - low
        guard spread > 0.02 else { return nil }
        let raw: Double
        if high == color.red { raw = ((color.green - color.blue) / spread).truncatingRemainder(dividingBy: 6) }
        else if high == color.green { raw = (color.blue - color.red) / spread + 2 }
        else { raw = (color.red - color.green) / spread + 4 }
        return (raw * 60 + 360).truncatingRemainder(dividingBy: 360)
    }

    func testAuthorColoursAreReadableOnEveryBuiltInTheme() async throws {
        let palette = try await page.js("return Object.values(window.Perch.color.PALETTE);") as! [String]
        XCTAssertEqual(palette, ["#D94F3D", "#E8843C", "#C99A1B", "#3F9B5B", "#1F9E96", "#3B82D9", "#6B5BD2", "#A855C7", "#D4588F", "#7A7F87"])
        let hard = ["#FFFFFF", "#000000", "#FFF36B", "#1B1F4B", "#808080", "#00FF00", "#FF00FF", "#663399"]
        var adjusted = 0, untouched = 0
        for theme in ThemePresets.all {
            let grounds = [theme.background, theme.surface, theme.codeBackground]
            for colour in palette + hard {
                let text = try await page.js("return window.Perch.color.readableTextColor(colour, grounds);", ["colour": colour, "grounds": grounds]) as! String
                for ground in grounds {
                    XCTAssertGreaterThanOrEqual(ThemeContrast.ratio(text, ground) ?? 0, 4.5, "\(colour) as text on \(theme.id) \(ground) became \(text)")
                }
                let already = grounds.allSatisfy { (ThemeContrast.ratio(colour, $0) ?? 0) >= 4.5 }
                if already { XCTAssertEqual(text.uppercased(), colour.uppercased(), "a colour that already reads is left alone (\(theme.id))"); untouched += 1 } else { adjusted += 1 }
                if let before = hue(colour), let after = hue(text) {
                    let turn = min(abs(before - after), 360 - abs(before - after))
                    XCTAssertLessThan(turn, 8, "\(colour) on \(theme.id) became \(text): the hue moved")
                }
            }
        }
        XCTAssertGreaterThan(adjusted, 20, "some colours need help on some themes")
        XCTAssertGreaterThan(untouched, 20, "and many need none")
    }

    func testColoursOnThePageFollowTheThemeWithoutRenderingAgain() async throws {
        let markdown = try Checkout.fixture("formatting.md")
        try await page.render(markdown, ["appearance": ThemePresets.perchLight.appearance])
        _ = try await page.js("window.__span = document.querySelector('#root [data-ink]'); return true;")
        page.clearMessages()
        for theme in ThemePresets.all {
            try await page.call("setAppearance", theme.appearance)
            let drawn = try await page.string("""
            JSON.stringify({
              same: window.__span === document.querySelector('#root [data-ink]'),
              ink: [...document.querySelectorAll('#root [data-ink]')].filter((el) => !el.closest('[data-tint]')).map((el) => { const m = getComputedStyle(el).color.match(/\\d+/g).map(Number); return '#' + m.slice(0, 3).map((n) => n.toString(16).padStart(2, '0')).join(''); }),
            })
            """)
            let result = try JSONSerialization.jsonObject(with: Data(drawn.utf8)) as! [String: Any]
            XCTAssertEqual(result["same"] as? Bool, true)
            for ink in result["ink"] as! [String] {
                // 4.5 is met before the colour is rounded to whole 0–255 steps, as in the editor; rounding can cost a hundredth.
                XCTAssertGreaterThanOrEqual(ThemeContrast.ratio(ink, theme.background) ?? 0, 4.45, "\(ink) on \(theme.id)")
            }
        }
        XCTAssertTrue(page.messages(ofType: "rendered").isEmpty, "changing theme never renders the note again")
        let source = try await page.string("document.querySelector('#root [data-ink]').dataset.ink")
        XCTAssertEqual(source, "rgb(217, 79, 61)", "the author's colour is never lost")
    }

    func testSyntaxColoursAreReadableOnEveryBuiltInTheme() async throws {
        try await page.render("```swift\n// comment\nlet x: Int = 1 + \"two\".count\nfunc f() -> String { nil }\n```\n\n```diff\n-old\n+new\n```\n")
        for theme in ThemePresets.all {
            try await page.call("setAppearance", theme.appearance)
            let colours = try await page.string("""
            JSON.stringify(Object.fromEntries(["hljs-keyword", "hljs-string", "hljs-number", "hljs-title", "hljs-type", "hljs-comment", "hljs-addition", "hljs-deletion"].map((name) => {
              const probe = document.createElement("span");
              probe.className = name;
              document.querySelector(".code-block pre code").append(probe);
              const m = getComputedStyle(probe).color.match(/\\d+/g).map(Number);
              probe.remove();
              return [name, "#" + m.slice(0, 3).map((n) => n.toString(16).padStart(2, "0")).join("")];
            }).concat([["plain", (() => { const m = getComputedStyle(document.querySelector(".code-block pre code")).color.match(/\\d+/g).map(Number); return "#" + m.slice(0, 3).map((n) => n.toString(16).padStart(2, "0")).join(""); })()]])))
            """)
            let found = try JSONSerialization.jsonObject(with: Data(colours.utf8)) as! [String: String]
            XCTAssertEqual(found.count, 9)
            for (name, colour) in found {
                let needed = name == "hljs-comment" ? 3.0 : 4.5
                XCTAssertGreaterThanOrEqual(ThemeContrast.ratio(colour, theme.codeBackground) ?? 0, needed, "\(name) \(colour) on \(theme.id)'s code background \(theme.codeBackground)")
            }
        }
    }
}
