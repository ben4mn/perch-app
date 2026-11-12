import XCTest
@testable import PerchKit

/// The awkward places for a formatting command: the cases random testing turned up, written down one by one.
/// `«` and `»` stand around the selection, `¦` is the caret.
final class FormattingEdgeTests: XCTestCase {
    private let red = "#D94F3D"

    private func parse(_ marked: String) -> (text: String, selection: NSRange) {
        var text = ""
        var start: Int?, end: Int?
        for character in marked {
            switch character {
            case "«": start = text.utf16.count
            case "»": end = text.utf16.count
            case "¦":
                start = text.utf16.count
                end = start
            default: text.append(character)
            }
        }
        return (text, NSRange(location: start ?? 0, length: (end ?? start ?? 0) - (start ?? 0)))
    }

    private func show(_ text: String, _ selection: NSRange) -> String {
        let source = text as NSString
        if selection.length == 0 { return source.replacingCharacters(in: selection, with: "¦") }
        let closed = source.replacingCharacters(in: NSRange(location: NSMaxRange(selection), length: 0), with: "»") as NSString
        return closed.replacingCharacters(in: NSRange(location: selection.location, length: 0), with: "«")
    }

    private func run(_ marked: String, _ command: (String, NSRange) -> TextEdit?) -> String {
        let note = parse(marked)
        guard let edit = command(note.text, note.selection) else { return "nil" }
        return show(edit.applied(to: note.text), edit.selection)
    }

    private func toggle(_ format: InlineFormat, _ marked: String, value: String = "") -> String {
        run(marked) { MarkdownFormatting.toggle(format, value: value, in: $0, selection: $1) }
    }

    private func color(_ marked: String, _ value: String? = "#D94F3D") -> String {
        run(marked) { MarkdownFormatting.set(.textColor, value: value, in: $0, selection: $1) }
    }

    // MARK: Marks that Markdown will read

    func testMarksArePulledInPastPunctuationSoTheyStillCount() {
        // `foo**(bar)**baz` is not bold in Markdown: the marks must hug a word.
        XCTAssertEqual(toggle(.bold, "foo«(bar)»baz"), "foo(**«bar»**)baz")
        XCTAssertEqual(toggle(.italic, "a,«b;»c"), "a,*«b»*;c")
        XCTAssertEqual(toggle(.strikethrough, "foo«(bar)»baz"), "foo(~~«bar»~~)baz")
        XCTAssertEqual(toggle(.highlight, "foo«(bar)»baz"), "foo(==«bar»==)baz")
        // With a space or punctuation outside, the punctuation can stay inside.
        XCTAssertEqual(toggle(.bold, "foo «(bar)» baz"), "foo **«(bar)»** baz")
        XCTAssertEqual(toggle(.bold, "«\"quoted\"»"), "**«\"quoted\"»**")
        // Tags don't have that rule.
        XCTAssertEqual(toggle(.underline, "foo«(bar)»baz"), "foo<u>«(bar)»</u>baz")
        XCTAssertEqual(color("foo«(bar)»baz"), "foo<span style=\"color: #D94F3D\">«(bar)»</span>baz")
    }

    func testWhatWasWrittenComesOffWithTheSameCommand() {
        for format in [InlineFormat.bold, .italic, .strikethrough, .highlight] {
            for marked in ["foo«(bar)»baz", "a,«b;»c", "see «what?»", "«it's» fine", "50«%» off", "x «— y —» z", "mid«wor»d"] {
                let note = parse(marked)
                guard let on = MarkdownFormatting.toggle(format, in: note.text, selection: note.selection) else { continue }
                let formatted = on.applied(to: note.text)
                XCTAssertTrue(MarkdownFormatting.formats(in: formatted, selection: on.selection).isOn(format), "\(format) \(marked) → \(formatted)")
                XCTAssertEqual(MarkdownFormatting.toggle(format, in: formatted, selection: on.selection)?.applied(to: formatted), note.text, "\(format) \(marked) → \(formatted)")
            }
        }
    }

    func testNothingIsWrittenThatWouldNotReadBack() {
        // Bold ending right against a lone asterisk would make `***`, which reads as something else.
        XCTAssertEqual(toggle(.bold, "«with 2 *» 3"), "nil")
        // A color around half of `^2^` would put a tag, with its space, inside the superscript and break it.
        XCTAssertEqual(color("H~2~O «x^2»^ end"), "nil")
        XCTAssertEqual(color("H~2~O x«^2^» end"), "H~2~O x<span style=\"color: #D94F3D\">«^2^»</span> end")
    }

    func testSubscriptAndSuperscriptGoOnEachWord() {
        XCTAssertEqual(toggle(.subscript, "«one two»"), "~«one~ ~two»~")
        XCTAssertEqual(toggle(.superscript, "x«2»"), "x^«2»^")
        XCTAssertEqual(toggle(.subscript, "~«one~ ~two»~"), "«one two»")
    }

    // MARK: Empty pairs

    func testTheCaretInsideARealMarkIsNotAnEmptyPair() {
        // The caret between the two asterisks that open bold text: italic must not eat them.
        XCTAssertEqual(toggle(.italic, "*¦*bold** text"), "nil")
        // Here the caret is at the end of the italic words, so the italic comes off; the bold is untouched.
        XCTAssertEqual(toggle(.italic, "***both**¦* text"), "**both**¦ text")
        XCTAssertEqual(toggle(.subscript, "~¦~struck~~ text"), "nil")
        // Inside code, `**` is two asterisks.
        XCTAssertEqual(toggle(.italic, "`a = *¦*b`"), "*`a = **b`¦*")
        XCTAssertEqual(toggle(.bold, "```\n**¦**\n```"), "nil")
        XCTAssertEqual(toggle(.bold, "---\ntitle: **¦**\n---\n"), "nil")
        // A real empty pair still comes away, among words or alone on a line.
        XCTAssertEqual(toggle(.bold, "word **¦** word"), "word ¦ word")
        XCTAssertEqual(toggle(.bold, "**¦**"), "¦")
        XCTAssertEqual(toggle(.highlight, "- ==¦=="), "- ¦")
        XCTAssertEqual(color("a <span style=\"color: #D94F3D\">¦</span> b", nil), "a ¦ b")
    }

    func testAnEmptyStrikethroughIsNotTypedWhereItWouldOpenACodeBlock() {
        // `~~~~` at the start of a line is a code fence: everything under it would turn into code.
        XCTAssertEqual(toggle(.strikethrough, "¦"), "nil")
        XCTAssertEqual(toggle(.strikethrough, "- ¦"), "nil")
        XCTAssertEqual(toggle(.strikethrough, "> ¦\"quoted\""), "nil")
        XCTAssertEqual(toggle(.strikethrough, "word ¦"), "word ~~¦~~")
        // And not straight after a bare address, which would take the marks into itself.
        XCTAssertEqual(toggle(.bold, "see https://example.com/a¦"), "nil")
        XCTAssertEqual(toggle(.bold, "see https://example.com/a ¦"), "see https://example.com/a **¦**")
    }

    // MARK: Places with no Markdown in them

    func testIndentedCodeIsLeftAlone() {
        let note = "Paragraph.\n\n    let x = «value»\n"
        XCTAssertEqual(toggle(.bold, note), "nil")
        XCTAssertEqual(color(note), "nil")
        XCTAssertEqual(run(note) { MarkdownFormatting.setHeading(2, in: $0, selection: $1) }, "nil")
        XCTAssertEqual(run(note) { MarkdownFormatting.toggleQuote(in: $0, selection: $1) }, "nil")
        // Four spaces under a list item is a paragraph of that item, not code.
        XCTAssertEqual(toggle(.bold, "- item\n\n    more «words»\n"), "- item\n\n    more **«words»**\n")
        // And straight under a paragraph it is just the paragraph going on.
        XCTAssertEqual(toggle(.bold, "Paragraph\n    more «words»\n"), "Paragraph\n    more **«words»**\n")
    }

    func testRawHTMLBlocksAreLeftAlone() {
        XCTAssertEqual(toggle(.bold, "<table><tr><td>«cell»</td></tr></table>\n"), "nil")
        XCTAssertEqual(color("<details>\n<summary>Title</summary>\nsome «words»\n</details>\n\nafter"), "nil")
        XCTAssertEqual(color("<div align=\"center\">\nno blank «lines»\n</div>"), "nil")
        XCTAssertEqual(color("<pre>\n\nkept «as is»\n</pre>"), "nil")
        // After the blank line, Markdown starts again.
        XCTAssertEqual(color("<details>\n<summary>Title</summary>\n\nsome «words»\n\n</details>"), "<details>\n<summary>Title</summary>\n\nsome <span style=\"color: #D94F3D\">«words»</span>\n\n</details>")
        // The block Perch writes for alignment has those blank lines, so its words can be formatted.
        XCTAssertEqual(toggle(.bold, "<div align=\"center\">\n\n«middle»\n\n</div>"), "<div align=\"center\">\n\n**«middle»**\n\n</div>")
        // A line that merely starts with one of Perch's own tags is ordinary text.
        XCTAssertEqual(toggle(.bold, "<u>under</u> «word»"), "<u>under</u> **«word»**")
    }

    func testQuoteMarksNeverGoInsideCode() {
        let fenced = "before\n```\nlet «x» = 1\n```\nafter"
        XCTAssertEqual(run(fenced) { MarkdownFormatting.toggleQuote(in: $0, selection: $1) }, "nil")
        XCTAssertEqual(run(fenced) { MarkdownFormatting.setCallout("note", in: $0, selection: $1) }, "nil")
        XCTAssertEqual(run("---\ntitle: «x»\n---\n") { MarkdownFormatting.toggleQuote(in: $0, selection: $1) }, "nil")
        // A whole block, fences and all, can be quoted.
        XCTAssertEqual(run("«```\ncode\n```»") { MarkdownFormatting.toggleQuote(in: $0, selection: $1) }, "«> ```\n> code\n> ```»")
    }

    func testLinkAddressesAreNeverTouched() {
        XCTAssertEqual(color("[a [b] c](https://exa«mple.com/x_y») end"), "nil")
        XCTAssertEqual(color("[[sic]](https://exa«mple.com/x_y) end»"), "[[sic]]«(https://example.com/x_y) <span style=\"color: #D94F3D\">end»</span>")
        XCTAssertEqual(toggle(.bold, "![alt](pa«th/to.png) end»"), "**«![alt](path/to.png) end»**")
    }

    // MARK: Selections in awkward places

    func testSelectionsThatStartOrEndInsideATagOrAMark() {
        XCTAssertEqual(color("one <sp«an style=\"color: #3B82D9\">two</span> thr»ee"), "one <span style=\"color: #D94F3D\">«two thr»</span>ee")
        XCTAssertEqual(color("one <span style=\"color: #3B82D9\">two</sp«an> thr»ee"), "one <span style=\"color: #3B82D9\">two</span>« <span style=\"color: #D94F3D\">thr»</span>ee")
        XCTAssertEqual(toggle(.underline, "*«*bold*»* rest"), "«**<u>bold</u>**» rest")
        XCTAssertEqual(color("**bo«ld*»* rest"), "**bo<span style=\"color: #D94F3D\">«ld</span>**» rest")
    }

    func testSelectionsAcrossCellsItemsAndHeadings() {
        XCTAssertEqual(color("| on«e | tw»o |\n| --- | --- |"), "| on<span style=\"color: #D94F3D\">«e</span> | <span style=\"color: #D94F3D\">tw»</span>o |\n| --- | --- |")
        XCTAssertEqual(toggle(.bold, "- [ ] fi«rst\n  1. sec»ond"), "- [ ] fi**«rst**\n  1. **sec»**ond")
        XCTAssertEqual(color("# Hea«ding\n\nPara»graph"), "# Hea<span style=\"color: #D94F3D\">«ding</span>\n\n<span style=\"color: #D94F3D\">Para»</span>graph")
        XCTAssertEqual(toggle(.bold, "> [!note] Ti«tle\n> bo»dy"), "> [!note] Ti**«tle**\n> **bo»**dy")
    }

    func testTheCaretAtTheEdgesOfWordsAndTheNote() {
        XCTAssertEqual(color("¦word next"), "<span style=\"color: #D94F3D\">¦word</span> next")
        XCTAssertEqual(color("word¦ next"), "<span style=\"color: #D94F3D\">word¦</span> next")
        XCTAssertEqual(color("word ¦next"), "word <span style=\"color: #D94F3D\">¦next</span>")
        XCTAssertEqual(color("word next¦"), "word <span style=\"color: #D94F3D\">next¦</span>")
        XCTAssertEqual(color("¦"), "<span style=\"color: #D94F3D\">¦</span>")
        XCTAssertEqual(color("line\n¦"), "line\n<span style=\"color: #D94F3D\">¦</span>")
        // Between two spaces there is no word: a pair to type into.
        XCTAssertEqual(color("a ¦ b"), "a <span style=\"color: #D94F3D\">¦</span> b")
    }

    func testEmojiAndCombiningCharactersStayWhole() {
        // The middle of an emoji is not somewhere a text view puts the caret, but nothing must break if it is.
        let family = "👩‍👩‍👧"
        for offset in 0...family.utf16.count {
            let text = "a \(family) b"
            for edit in [
                MarkdownFormatting.set(.textColor, value: red, in: text, selection: NSRange(location: 2 + offset, length: 0)),
                MarkdownFormatting.toggle(.bold, in: text, selection: NSRange(location: 2 + offset, length: 0)),
                MarkdownFormatting.set(.textColor, value: red, in: text, selection: NSRange(location: 2, length: offset)),
            ].compactMap({ $0 }) {
                let result = edit.applied(to: text)
                XCTAssertTrue(result.contains(family), "offset \(offset): \(result.debugDescription)")
                XCTAssertEqual(String(decoding: Array(result.utf16), as: UTF16.self), result)
            }
        }
        XCTAssertEqual(color("«e\u{301}»cole"), "<span style=\"color: #D94F3D\">«e\u{301}»</span>cole")
        XCTAssertEqual(toggle(.bold, "caf«é 🎉» x"), "caf**«é 🎉»** x")
    }

    func testClearFormattingKeepsLinksCodeAndOtherPeoplesTags() {
        let clear: (String, NSRange) -> TextEdit? = { MarkdownFormatting.clearFormatting(in: $0, selection: $1) }
        XCTAssertEqual(
            run("«**bold** [*link*](https://e.com/a_b) `**code**` <u>u</u> ==h== <span style=\"color: #D94F3D\">c</span> [[Wiki *x*]] <kbd>K</kbd> https://e.com/*x*»", clear),
            "«bold [link](https://e.com/a_b) `**code**` u h c [[Wiki *x*]] <kbd>K</kbd> https://e.com/*x*»"
        )
        XCTAssertEqual(run("```\n«**code**»\n```", clear), "nil")
        XCTAssertEqual(run("«plain words»", clear), "nil")
    }

    // MARK: Deleting part of a tag

    func testBackspaceOnATagTakesTheWholePair() {
        func delete(_ marked: String) -> String {
            run(marked) { MarkdownFormatting.deletingTag(in: $0, range: $1) }
        }
        // Backspace at the start of colored text: the caret is after the `>`.
        XCTAssertEqual(delete("a <span style=\"color: #D94F3D\"«>»red</span> b"), "a ¦red b")
        XCTAssertEqual(delete("a <span style=\"color: #D94F3D\">red«<»/span> b"), "a red¦ b")
        XCTAssertEqual(delete("a <span style=\"col«o»r: #D94F3D\">red</span> b"), "a ¦red b")
        XCTAssertEqual(delete("- [ ] <u>under</u«>» x"), "- [ ] under¦ x")
        XCTAssertEqual(delete("<mark style=\"background-color: #3B82D9\">m</mar«k»> <span style=\"font-size: 1.3em\">big</span>"), "m¦ <span style=\"font-size: 1.3em\">big</span>")
        // The innermost pair only.
        XCTAssertEqual(delete("<u><span style=\"color: #D94F3D\"«>»x</span></u>"), "<u>¦x</u>")
        // Everything else is ordinary text, and the key does what it always does.
        for plain in [
            "a <span style=\"color: #D94F3D\">r«e»d</span> b", "**«b»old**", "*«*»bold**", "<kbd«>»K</kbd>", "line<br«>»", "<u>never close«d»",
            "<span style=\"color: red; font-weight: bold\"«>»theirs</span>", "`<u«>»x</u>`", "```\n<u«>»x</u>\n```", "<details«>»\n<u>x</u«>»\n</details>",
            "<u>one\ntwo</u«>»",
        ] {
            XCTAssertEqual(delete(plain), "nil", plain)
        }
        // More than one character selected is the user's own edit.
        XCTAssertEqual(delete("a <u«>r»ed</u>"), "nil")
    }

    // MARK: Colors people can read

    func testTextOnAColoredHighlightIsReadableOnEveryTheme() {
        let colors = FormatPalette.colors.map(\.hex) + ["#000000", "#FFFFFF", "#FFFF00", "#123456", "#FEDCBA", "#808080"]
        for palette in ThemePresets.all {
            guard let page = ThemeRGB(hex: palette.background), let ink = ThemeRGB(hex: palette.text) else { return XCTFail("bad colors in \(palette.name)") }
            for highlight in colors {
                let behind = FormatPalette.wash(ThemeRGB(hex: highlight)!, on: page, dark: palette.isDark)
                // The highlight can be told from the page.
                if FormatPalette.colors.contains(where: { $0.hex == highlight }) {
                    XCTAssertGreaterThan(ThemeContrast.ratio(behind, page), 1.05, "\(highlight) highlight can't be seen on \(palette.name)")
                }
                // The theme's own text, and every color of text, once moved for the highlight under it.
                for text in [ink] + colors.map({ ThemeRGB(hex: $0)! }) {
                    let shown = FormatPalette.legible(text, on: behind)
                    XCTAssertGreaterThanOrEqual(ThemeContrast.ratio(shown, behind), 4.5 - 0.001, "\(text.hex) on a \(highlight) highlight in \(palette.name)")
                }
            }
            // The plain yellow highlight is the theme's warning color washed over the page. On a few dark
            // themes the theme's own text is too close to it, so it too is moved until it reads.
            if let warning = ThemeRGB(hex: palette.warning) {
                let mark = FormatPalette.plainWash(warning, on: page)
                for text in [ink] + colors.map({ ThemeRGB(hex: $0)! }) {
                    XCTAssertGreaterThanOrEqual(ThemeContrast.ratio(FormatPalette.legible(text, on: mark), mark), 4.5 - 0.001, "\(text.hex) on ==highlight== in \(palette.name)")
                }
            }
        }
    }

    func testEveryColorIsReadableAsTextOnEveryTheme() {
        var dice = SystemRandomNumberGenerator()
        var colors = FormatPalette.colors.map(\.hex) + ["#000000", "#FFFFFF", "#FFFF00", "#00FF00", "#0000FF", "#FF00FF", "#808080", "#7F7F7F"]
        for _ in 0..<200 { colors.append(ThemeRGB(red: .random(in: 0...1, using: &dice), green: .random(in: 0...1, using: &dice), blue: .random(in: 0...1, using: &dice)).hex) }
        for palette in ThemePresets.all {
            // On the page, on raised surfaces (the settings preview), and on a code block's background.
            for backdrop in [palette.background, palette.surface, palette.codeBackground] {
                guard let behind = ThemeRGB(hex: backdrop) else { return XCTFail("bad color in \(palette.name)") }
                for hex in colors {
                    let shown = FormatPalette.legible(ThemeRGB(hex: hex)!, on: behind)
                    XCTAssertGreaterThanOrEqual(ThemeContrast.ratio(shown, behind), 4.5 - 0.001, "\(hex) on \(backdrop) in \(palette.name)")
                }
            }
        }
    }

    // MARK: Long notes

    func testTheFormatBarKeepsUpInAFiveThousandLineNote() {
        var lines: [String] = []
        for index in 0..<5000 {
            switch index % 8 {
            case 0: lines.append("## Heading \(index)")
            case 1: lines.append("- [ ] task with **bold**, <u>under</u> and <span style=\"color: #D94F3D\">red</span> 🎉")
            case 2: lines.append("```")
            case 3: lines.append("code \(index)")
            case 4: lines.append("```")
            case 5: lines.append("> a quote with ==highlight== and a [link](https://example.com)")
            case 6: lines.append("")
            default: lines.append("Prose with *emphasis*, `code` and <mark style=\"background-color: #3B82D9\">blue</mark> words to color.")
            }
        }
        var text = lines.joined(separator: "\n")
        let length = (text as NSString).length
        // Moving the caret about: what the bar asks on every move.
        _ = MarkdownFormatting.formats(in: text, selection: NSRange(location: 0, length: 0))
        var start = Date()
        let moves = 300
        for move in 0..<moves {
            _ = MarkdownFormatting.formats(in: text, selection: NSRange(location: (move * 7919) % length, length: 0))
        }
        let perMove = Date().timeIntervalSince(start) / Double(moves)
        // Typing: the note is different every time, so its lines are read again.
        start = Date()
        let keys = 20
        for _ in 0..<keys {
            text += "x"
            _ = MarkdownFormatting.formats(in: text, selection: NSRange(location: (text as NSString).length, length: 0))
        }
        let perKey = Date().timeIntervalSince(start) / Double(keys)
        print(String(format: "formatting: in a 5000-line note the bar's state takes %.2f ms per caret move and %.1f ms per key", perMove * 1000, perKey * 1000))
        XCTAssertLessThan(perMove, 0.004)
        XCTAssertLessThan(perKey, 0.05)
    }
}
