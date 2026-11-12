import XCTest
@testable import PerchKit

/// A note with a selection drawn in it: `«` and `»` around selected text, or `¦` for the caret.
private struct Marked: Equatable, CustomStringConvertible {
    var text: String
    var selection: NSRange

    init(_ marked: String) {
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
        self.text = text
        selection = NSRange(location: start ?? 0, length: (end ?? start ?? 0) - (start ?? 0))
    }

    init(text: String, selection: NSRange) {
        self.text = text
        self.selection = selection
    }

    func applying(_ edit: TextEdit?) -> Marked? {
        edit.map { Marked(text: $0.applied(to: text), selection: $0.selection) }
    }

    var description: String {
        let source = text as NSString
        guard NSMaxRange(selection) <= source.length else { return text + " (selection out of range)" }
        if selection.length == 0 { return source.replacingCharacters(in: selection, with: "¦") }
        return source.replacingCharacters(in: NSRange(location: NSMaxRange(selection), length: 0), with: "»")
            .inserting("«", at: selection.location)
    }
}

private extension String {
    func inserting(_ piece: String, at location: Int) -> String {
        (self as NSString).replacingCharacters(in: NSRange(location: location, length: 0), with: piece)
    }
}

final class MarkdownFormattingTests: XCTestCase {
    private let red = "#D94F3D", blue = "#3B82D9", green = "#3F9B5B"

    private func toggle(_ format: InlineFormat, _ marked: String, value: String = "", file: StaticString = #filePath, line: UInt = #line) -> String {
        let note = Marked(marked)
        guard let result = note.applying(MarkdownFormatting.toggle(format, value: value, in: note.text, selection: note.selection)) else { return "nil" }
        return result.description
    }

    private func set(_ format: InlineFormat, _ value: String?, _ marked: String) -> String {
        let note = Marked(marked)
        guard let result = note.applying(MarkdownFormatting.set(format, value: value, in: note.text, selection: note.selection)) else { return "nil" }
        return result.description
    }

    private func run(_ marked: String, _ command: (String, NSRange) -> TextEdit?) -> String {
        let note = Marked(marked)
        guard let result = note.applying(command(note.text, note.selection)) else { return "nil" }
        return result.description
    }

    // MARK: What gets written

    func testEachFormatWritesTheAgreedMarkup() {
        XCTAssertEqual(toggle(.bold, "a «word» b"), "a **«word»** b")
        XCTAssertEqual(toggle(.italic, "a «word» b"), "a *«word»* b")
        XCTAssertEqual(toggle(.strikethrough, "a «word» b"), "a ~~«word»~~ b")
        XCTAssertEqual(toggle(.underline, "a «word» b"), "a <u>«word»</u> b")
        XCTAssertEqual(toggle(.highlight, "a «word» b"), "a ==«word»== b")
        XCTAssertEqual(toggle(.subscript, "H«2»O"), "H~«2»~O")
        XCTAssertEqual(toggle(.superscript, "x«2»"), "x^«2»^")
        XCTAssertEqual(set(.textColor, red, "a «word» b"), "a <span style=\"color: #D94F3D\">«word»</span> b")
        XCTAssertEqual(set(.highlight, blue, "a «word» b"), "a <mark style=\"background-color: #3B82D9\">«word»</mark> b")
        XCTAssertEqual(set(.textSize, "1.15em", "a «word» b"), "a <span style=\"font-size: 1.15em\">«word»</span> b")
        for size in FormatPalette.sizes {
            XCTAssertEqual(set(.textSize, size, "«x»"), "<span style=\"font-size: \(size)\">«x»</span>")
        }
        XCTAssertEqual(FormatPalette.colors.map(\.hex), ["#D94F3D", "#E8843C", "#C99A1B", "#3F9B5B", "#1F9E96", "#3B82D9", "#6B5BD2", "#A855C7", "#D4588F", "#7A7F87"])
        XCTAssertEqual(FormatPalette.sizes, ["0.85em", "1.15em", "1.3em", "1.6em"])
    }

    func testTogglingAgainTakesTheMarkupOff() {
        for format in InlineFormat.allCases {
            let value = format == .textColor ? red : (format == .textSize ? "1.3em" : "")
            let on = toggle(format, "one «two» three", value: value)
            XCTAssertNotEqual(on, "nil", "\(format)")
            XCTAssertEqual(toggle(format, on, value: value), "one «two» three", "\(format)")
        }
    }

    func testWithNothingSelectedItFormatsTheWordUnderTheCaret() {
        XCTAssertEqual(toggle(.bold, "a wo¦rd b"), "a **wo¦rd** b")
        XCTAssertEqual(toggle(.bold, "a ¦word b"), "a **¦word** b")
        XCTAssertEqual(toggle(.bold, "a word¦ b"), "a **word¦** b")
        XCTAssertEqual(toggle(.bold, "a **wo¦rd** b"), "a wo¦rd b")
        XCTAssertEqual(toggle(.underline, "caf¦é au lait"), "<u>caf¦é</u> au lait")
        XCTAssertEqual(set(.textColor, red, "a wo¦rd b"), "a <span style=\"color: #D94F3D\">wo¦rd</span> b")
        // Only the word loses it when it sits inside a longer bold stretch.
        XCTAssertEqual(toggle(.bold, "**one t¦wo three**"), "**one** t¦wo **three**")
    }

    func testWithNoWordItTypesAnEmptyPairAndTakesItBackIfAskedTwice() {
        XCTAssertEqual(toggle(.bold, "a ¦ b"), "a **¦** b")
        XCTAssertEqual(toggle(.bold, "a **¦** b"), "a ¦ b")
        XCTAssertEqual(toggle(.italic, "¦"), "*¦*")
        XCTAssertEqual(toggle(.italic, "*¦*"), "¦")
        XCTAssertEqual(toggle(.underline, "¦"), "<u>¦</u>")
        XCTAssertEqual(toggle(.underline, "<u>¦</u>"), "¦")
        XCTAssertEqual(set(.textColor, red, "end ¦"), "end <span style=\"color: #D94F3D\">¦</span>")
        // Picking another color with the caret in an empty span swaps the color.
        XCTAssertEqual(set(.textColor, blue, "end <span style=\"color: #D94F3D\">¦</span>"), "end <span style=\"color: #3B82D9\">¦</span>")
        XCTAssertEqual(set(.textColor, nil, "end <span style=\"color: #D94F3D\">¦</span>"), "end ¦")
        // Italic inside an empty bold pair isn't mistaken for the bold pair.
        XCTAssertEqual(toggle(.italic, "a **¦** b"), "a ***¦*** b")
        XCTAssertEqual(toggle(.italic, "a ***¦*** b"), "a **¦** b")
    }

    // MARK: Color never nests

    func testANewColorReplacesTheOldOne() {
        XCTAssertEqual(set(.textColor, blue, "<span style=\"color: #D94F3D\">«word»</span>"), "<span style=\"color: #3B82D9\">«word»</span>")
        XCTAssertEqual(set(.textColor, blue, "«<span style=\"color: #D94F3D\">word</span>»"), "<span style=\"color: #3B82D9\">«word»</span>")
        XCTAssertEqual(
            set(.textColor, blue, "<span style=\"color: #D94F3D\">one «two» three</span>"),
            "<span style=\"color: #D94F3D\">one </span><span style=\"color: #3B82D9\">«two»</span><span style=\"color: #D94F3D\"> three</span>"
                .replacingOccurrences(of: "one </span>", with: "one</span> ").replacingOccurrences(of: "<span style=\"color: #D94F3D\"> three", with: " <span style=\"color: #D94F3D\">three")
        )
        XCTAssertEqual(set(.highlight, blue, "==«word»=="), "<mark style=\"background-color: #3B82D9\">«word»</mark>")
        XCTAssertEqual(set(.highlight, "", "<mark style=\"background-color: #3B82D9\">«word»</mark>"), "==«word»==")
        XCTAssertEqual(set(.textSize, "1.6em", "<span style=\"font-size: 1.15em\">«word»</span>"), "<span style=\"font-size: 1.6em\">«word»</span>")
        // A size span and a color span are different things: one doesn't replace the other.
        XCTAssertEqual(
            set(.textColor, red, "<span style=\"font-size: 1.15em\">«word»</span>"),
            "<span style=\"font-size: 1.15em\"><span style=\"color: #D94F3D\">«word»</span></span>"
        )
    }

    func testAColorAcrossSeveralSpansLeavesOneCleanSpan() {
        let text = "«a <span style=\"color: #D94F3D\">b</span> c <span style=\"color: #3F9B5B\">d</span> e»"
        XCTAssertEqual(set(.textColor, blue, text), "<span style=\"color: #3B82D9\">«a b c d e»</span>")
        // The same color on text beside a span joins it.
        XCTAssertEqual(set(.textColor, red, "<span style=\"color: #D94F3D\">ab</span>«cd»"), "<span style=\"color: #D94F3D\">ab«cd»</span>")
        // Nested spans from somewhere else are flattened by the next edit that touches them.
        let nested = "<span style=\"color: #D94F3D\">a <span style=\"color: #3F9B5B\">b</span> «c»</span>"
        XCTAssertEqual(
            set(.textColor, blue, nested),
            "<span style=\"color: #D94F3D\">a</span> <span style=\"color: #3F9B5B\">b</span> <span style=\"color: #3B82D9\">«c»</span>"
        )
    }

    func testRemovingAColorUnwraps() {
        XCTAssertEqual(set(.textColor, nil, "a <span style=\"color: #D94F3D\">«word»</span> b"), "a «word» b")
        XCTAssertEqual(set(.textColor, nil, "a <span style=\"color: #D94F3D\">wo¦rd</span> b"), "a wo¦rd b")
        XCTAssertEqual(set(.textColor, nil, "<span style=\"color: #D94F3D\">one «two» three</span>"), "<span style=\"color: #D94F3D\">one</span> «two» <span style=\"color: #D94F3D\">three</span>")
        XCTAssertEqual(set(.highlight, nil, "<mark style=\"background-color: #3B82D9\">«word»</mark>"), "«word»")
        XCTAssertEqual(set(.textSize, nil, "<span style=\"font-size: 1.3em\">«word»</span>"), "«word»")
        XCTAssertEqual(set(.textColor, nil, "plain «word»"), "nil")
    }

    func testSizeSteps() {
        func step(_ delta: Int, _ marked: String) -> String { run(marked) { MarkdownFormatting.stepSize(delta, in: $0, selection: $1) } }
        XCTAssertEqual(step(1, "«x»"), "<span style=\"font-size: 1.15em\">«x»</span>")
        XCTAssertEqual(step(1, "<span style=\"font-size: 1.15em\">«x»</span>"), "<span style=\"font-size: 1.3em\">«x»</span>")
        XCTAssertEqual(step(1, "<span style=\"font-size: 1.3em\">«x»</span>"), "<span style=\"font-size: 1.6em\">«x»</span>")
        XCTAssertEqual(step(1, "<span style=\"font-size: 1.6em\">«x»</span>"), "nil")
        XCTAssertEqual(step(-1, "<span style=\"font-size: 1.15em\">«x»</span>"), "«x»")
        XCTAssertEqual(step(-1, "«x»"), "<span style=\"font-size: 0.85em\">«x»</span>")
        XCTAssertEqual(step(-1, "<span style=\"font-size: 0.85em\">«x»</span>"), "nil")
        XCTAssertEqual(step(1, "<span style=\"font-size: 0.85em\">«x»</span>"), "«x»")
    }

    // MARK: Overlaps

    func testSelectionsThatPartlyOverlapFormatting() {
        XCTAssertEqual(toggle(.bold, "**ab**«cd»"), "**ab«cd»**")
        XCTAssertEqual(toggle(.bold, "**a«b**cd»"), "**a«bcd»**")
        XCTAssertEqual(toggle(.bold, "«ab **cd** ef»"), "**«ab cd ef»**")
        XCTAssertEqual(toggle(.bold, "**a«b»c**"), "**a**«b»**c**")
        XCTAssertEqual(toggle(.underline, "<u>ab</u> «cd <u>ef»</u>"), "<u>ab</u> <u>«cd ef»</u>")
        XCTAssertEqual(toggle(.underline, "<u>a«b</u> c»d"), "<u>a«b c»</u>d")
        // Underline that starts inside bold and ends outside it is cut at the bold's edge, so tags never cross.
        XCTAssertEqual(toggle(.underline, "**bo«ld** and» more"), "**bo<u>«ld</u>** <u>and»</u> more")
        XCTAssertEqual(toggle(.underline, "[li«nk](https://example.com) and» more"), "[li<u>«nk</u>](https://example.com) <u>and»</u> more")
        // A selection that cuts into a mark, a link target or code takes the whole thing.
        XCTAssertEqual(toggle(.underline, "a `co«de` b» c"), "a <u>«`code` b»</u> c")
        XCTAssertEqual(toggle(.underline, "see [[No«te]] now»"), "see <u>«[[Note]] now»</u>")
        XCTAssertEqual(toggle(.bold, "«<u>word</u>»"), "«<u>**word**</u>»")
        XCTAssertEqual(set(.textColor, red, "«**bold**»"), "«**<span style=\"color: #D94F3D\">bold</span>**»")
    }

    func testBoldAndItalicTogether() {
        XCTAssertEqual(toggle(.italic, "**«word»**"), "***«word»***")
        XCTAssertEqual(toggle(.italic, "***«word»***"), "**«word»**")
        XCTAssertEqual(toggle(.bold, "***«word»***"), "*«word»*")
        XCTAssertEqual(toggle(.bold, "*«word»*"), "***«word»***")
        XCTAssertEqual(toggle(.italic, "__«word»__"), "__*«word»*__")
        XCTAssertEqual(toggle(.bold, "__«word»__"), "«word»")
        XCTAssertEqual(toggle(.italic, "_«word»_"), "«word»")
        XCTAssertEqual(toggle(.bold, "snake_case «name» here_too"), "snake_case **«name»** here_too")
    }

    // MARK: Blocks

    func testOneSpanPerLineAndBlockMarksStayOutside() {
        let text = "# Tit«le\n\n- one\n- [ ] two\n  1. three\n> quoted\n> [!note] Heads up\n\nplain» text"
        XCTAssertEqual(
            set(.textColor, red, text),
            """
            # Tit<span style="color: #D94F3D">«le</span>

            - <span style="color: #D94F3D">one</span>
            - [ ] <span style="color: #D94F3D">two</span>
              1. <span style="color: #D94F3D">three</span>
            > <span style="color: #D94F3D">quoted</span>
            > [!note] <span style="color: #D94F3D">Heads up</span>

            <span style="color: #D94F3D">plain»</span> text
            """
        )
        XCTAssertEqual(toggle(.bold, "- «one\n- two»"), "- **«one**\n- **two»**")
        XCTAssertEqual(toggle(.bold, "- **«one**\n- **two»**"), "- «one\n- two»")
        // A selection that ends at the start of the next line doesn't touch that line.
        XCTAssertEqual(toggle(.underline, "«one\n»two"), "<u>«one</u>\n»two")
    }

    func testTablesAreFormattedCellByCell() {
        let text = "| «Name | Role |\n| --- | :-: |\n| Ada | Eng»ineer |"
        XCTAssertEqual(
            toggle(.bold, text),
            "| **«Name** | **Role** |\n| --- | :-: |\n| **Ada** | **Eng»**ineer |"
        )
        XCTAssertEqual(set(.textColor, red, "| a | b¦c |"), "| a | <span style=\"color: #D94F3D\">b¦c</span> |")
    }

    func testCodeFrontmatterAndBlockSyntaxAreNeverFormatted() {
        XCTAssertEqual(toggle(.bold, "```\n«code»\n```"), "nil")
        XCTAssertEqual(toggle(.bold, "```\nco¦de\n```"), "nil")
        XCTAssertEqual(toggle(.bold, "---\ntitle: «x»\n---\nbody"), "nil")
        XCTAssertEqual(toggle(.bold, "$$\n«x»\n$$"), "nil")
        XCTAssertEqual(toggle(.underline, "«---»"), "nil")
        XCTAssertEqual(toggle(.underline, "«<div align=\"center\">»"), "nil")
        XCTAssertEqual(toggle(.underline, "«one\n```\ncode\n```\ntwo»"), "<u>«one</u>\n```\ncode\n```\n<u>two»</u>")
        // The caret in the middle of a tag does nothing rather than splitting it.
        XCTAssertEqual(toggle(.bold, "<sp¦an style=\"color: #D94F3D\">x</span>"), "nil")
        XCTAssertEqual(toggle(.underline, "a `co¦de` b"), "a <u>`co¦de`</u> b".replacingOccurrences(of: "co¦de`</u>", with: "code`¦</u>"))
    }

    func testEmojiAndWindowsLineEndings() {
        XCTAssertEqual(toggle(.underline, "👩‍👩‍👧 «family 🎉» day"), "👩‍👩‍👧 <u>«family 🎉»</u> day")
        XCTAssertEqual(set(.textColor, red, "«🎉»"), "<span style=\"color: #D94F3D\">«🎉»</span>")
        XCTAssertEqual(toggle(.bold, "- «one 🎉\r\n- two»\r\n"), "- **«one 🎉**\r\n- **two»**\r\n")
        XCTAssertEqual(toggle(.bold, "- **«one 🎉**\r\n- **two»**\r\n"), "- «one 🎉\r\n- two»\r\n")
        let text = "a\r\n«b»\r\nc"
        let note = Marked(text)
        let edit = MarkdownFormatting.toggle(.underline, in: note.text, selection: note.selection)
        XCTAssertEqual(edit?.applied(to: note.text), "a\r\n<u>b</u>\r\nc")
    }

    func testClearFormattingKeepsLinksAndCode() {
        let text = "«**bold** *it* ~~gone~~ <u>under</u> ==hi== <mark style=\"background-color: #3B82D9\">blue</mark> "
            + "<span style=\"color: #D94F3D\">red <span style=\"font-size: 1.3em\">big</span></span> H~2~O x^2^ [link](https://e.com) `code` [[Note]]»"
        XCTAssertEqual(
            run(text) { MarkdownFormatting.clearFormatting(in: $0, selection: $1) },
            "«bold it gone under hi blue red big H2O x2 [link](https://e.com) `code` [[Note]]»"
        )
        XCTAssertEqual(run("**one «two» three**") { MarkdownFormatting.clearFormatting(in: $0, selection: $1) }, "**one** «two» **three**")
        XCTAssertEqual(run("plain «text»") { MarkdownFormatting.clearFormatting(in: $0, selection: $1) }, "nil")
        XCTAssertEqual(
            run("- **«one**\n- <u>two»</u>") { MarkdownFormatting.clearFormatting(in: $0, selection: $1) },
            "- «one\n- two»"
        )
    }

    func testInlineCode() {
        func code(_ marked: String) -> String { run(marked) { MarkdownFormatting.toggleCode(in: $0, selection: $1) } }
        XCTAssertEqual(code("a «word» b"), "a `«word»` b")
        XCTAssertEqual(code("a `«word»` b"), "a «word» b")
        XCTAssertEqual(code("a wo¦rd b"), "a `wo¦rd` b")
        XCTAssertEqual(code("a `wo¦rd` b"), "a wo¦rd b")
        XCTAssertEqual(code("```\nco¦de\n```"), "nil")
    }

    // MARK: State

    func testFormatsAtTheCaretAndAcrossASelection() {
        func formats(_ marked: String) -> ActiveFormats {
            let note = Marked(marked)
            return MarkdownFormatting.formats(in: note.text, selection: note.selection)
        }
        var active = formats("**bo¦ld** plain")
        XCTAssertTrue(active.bold)
        XCTAssertFalse(active.italic)
        XCTAssertFalse(formats("**bold** pl¦ain").bold)
        XCTAssertTrue(formats("**bold¦** plain").bold)
        active = formats("## <span style=\"color: #d94f3d\"><u>Ti¦tle</u></span>")
        XCTAssertEqual(active.headingLevel, 2)
        XCTAssertEqual(active.textColor, red)
        XCTAssertTrue(active.underline)
        active = formats("- [ ] ==ta¦sk== <mark style=\"background-color: #3B82D9\">x</mark>")
        XCTAssertEqual(active.list, .task)
        XCTAssertEqual(active.highlight, "")
        XCTAssertEqual(formats("1. <mark style=\"background-color: #3B82D9\">¦x</mark>").highlight, blue)
        XCTAssertEqual(formats("1. x¦").list, .numbered)
        XCTAssertEqual(formats("* x¦").list, .bullet)
        XCTAssertEqual(formats("<span style=\"font-size: 1.3em\">bi¦g</span>").textSize, "1.3em")
        XCTAssertTrue(formats("see [the l¦ink](https://e.com)").link)
        XCTAssertTrue(formats("see `co¦de`").code)
        XCTAssertTrue(formats("```\nco¦de\n```").inCodeBlock)
        XCTAssertTrue(formats("| a | b¦ |").inTable)
        active = formats("> [!warning] Careful\n> bo¦dy")
        XCTAssertTrue(active.quote)
        XCTAssertEqual(active.callout, "warning")
        XCTAssertNil(formats("> just a quo¦te").callout)
        XCTAssertEqual(formats("<div align=\"center\">\n\ncente¦red\n\n</div>\n\nafter").alignment, "center")
        XCTAssertNil(formats("<div align=\"center\">\n\ncentered\n\n</div>\n\naf¦ter").alignment)

        // A selection has a format only when all of it does.
        XCTAssertTrue(formats("**«one two»**").bold)
        XCTAssertFalse(formats("«**one** two»").bold)
        XCTAssertTrue(formats("- **«one**\n- **two»**").bold)
        XCTAssertEqual(formats("<span style=\"color: #D94F3D\">«one»</span>").textColor, red)
        XCTAssertNil(formats("«<span style=\"color: #D94F3D\">one</span> <span style=\"color: #3B82D9\">two</span>»").textColor)
        XCTAssertEqual(formats("").headingLevel, 0)
        XCTAssertEqual(formats("a\n¦"), ActiveFormats())
    }

    // MARK: Block commands

    func testHeadings() {
        func heading(_ level: Int, _ marked: String) -> String { run(marked) { MarkdownFormatting.setHeading(level, in: $0, selection: $1) } }
        XCTAssertEqual(heading(1, "Tit¦le"), "# Tit¦le")
        XCTAssertEqual(heading(2, "# Tit¦le"), "## Tit¦le")
        XCTAssertEqual(heading(2, "## Tit¦le"), "Tit¦le")
        XCTAssertEqual(heading(0, "### Tit¦le"), "Tit¦le")
        XCTAssertEqual(heading(0, "Tit¦le"), "nil")
        XCTAssertEqual(heading(3, "- [ ] ta¦sk"), "### ta¦sk")
        XCTAssertEqual(heading(1, "> quo¦ted"), "> # quo¦ted")
        XCTAssertEqual(heading(2, "«one\n\ntwo»"), "«## one\n\n## two»")
        XCTAssertEqual(heading(1, "¦"), "# ¦")
        XCTAssertEqual(heading(1, "```\nco¦de\n```"), "nil")
        XCTAssertEqual(heading(1, "a\r\nb¦\r\nc"), "a\r\n# b¦\r\nc")
    }

    func testQuotesAndCallouts() {
        func quote(_ marked: String) -> String { run(marked) { MarkdownFormatting.toggleQuote(in: $0, selection: $1) } }
        XCTAssertEqual(quote("li¦ne"), "> li¦ne")
        XCTAssertEqual(quote("> li¦ne"), "li¦ne")
        XCTAssertEqual(quote("«one\n\ntwo»"), "«> one\n>\n> two»")
        XCTAssertEqual(quote("«> one\n>\n> two»"), "«one\n\ntwo»")
        XCTAssertEqual(quote("> > dee¦p"), "> dee¦p")

        func callout(_ type: String?, _ marked: String) -> String { run(marked) { MarkdownFormatting.setCallout(type, in: $0, selection: $1) } }
        XCTAssertEqual(callout("tip", "¦"), "> [!tip] Title\n> ¦")
        XCTAssertEqual(callout("warning", "Mind the g¦ap"), "> [!warning]\n> Mind the g¦ap")
        XCTAssertEqual(callout("note", "«one\ntwo»"), "> [!note]\n«> one\n> two»")
        XCTAssertEqual(callout("danger", "> [!note] Title\n> bo¦dy"), "> [!danger] Title\n> bo¦dy")
        XCTAssertEqual(callout("note", "> [!note] Title\n> bo¦dy"), "nil")
        XCTAssertEqual(callout(nil, "> [!note] Title\n> bo¦dy"), "> Title\n> bo¦dy")
        XCTAssertEqual(callout("tip", "> plain quo¦te"), "> [!tip]\n> plain quo¦te")
        XCTAssertEqual(callout(nil, "plain¦"), "nil")
    }

    func testCodeBlocksDividersAndTables() {
        func block(_ language: String, _ marked: String) -> String { run(marked) { MarkdownFormatting.toggleCodeBlock(language: language, in: $0, selection: $1) } }
        XCTAssertEqual(block("swift", "let x¦ = 1"), "```swift\nlet x¦ = 1\n```")
        XCTAssertEqual(block("", "«a\nb»\nc"), "```\n«a\nb»\n```\nc")
        XCTAssertEqual(block("", "¦"), "```\n¦\n```")
        XCTAssertEqual(block("", "```swift\nlet x¦ = 1\n```\nafter"), "let x¦ = 1\nafter")
        XCTAssertEqual(block("", "```\n¦\n```"), "¦")
        XCTAssertEqual(block("", "a\n```\nnever clo¦sed"), "a\nnever clo¦sed")

        func divider(_ marked: String) -> String { run(marked) { MarkdownFormatting.insertDivider(in: $0, selection: $1) } }
        XCTAssertEqual(divider("¦"), "---\n¦")
        XCTAssertEqual(divider("text¦"), "text\n\n---\n¦")
        XCTAssertEqual(divider("text\n¦"), "text\n\n---\n¦")
        XCTAssertEqual(divider("text\n\n¦\nmore"), "text\n\n---\n¦\nmore")
        XCTAssertEqual(divider("te¦xt\nmore"), "text\n\n---\n¦\nmore")

        func table(_ rows: Int, _ columns: Int, _ marked: String) -> String { run(marked) { MarkdownFormatting.insertTable(rows: rows, columns: columns, in: $0, selection: $1) } }
        XCTAssertEqual(table(2, 3, "¦"), "| «Column 1» | Column 2 | Column 3 |\n| --- | --- | --- |\n|  |  |  |\n|  |  |  |\n")
        XCTAssertEqual(table(1, 2, "intro¦"), "intro\n\n| «Column 1» | Column 2 |\n| --- | --- |\n|  |  |\n")
        XCTAssertEqual(table(1, 1, "a\r\n¦"), "a\r\n\r\n| «Column 1» |\r\n| --- |\r\n|  |\r\n")
    }

    func testMovingAroundATable() {
        func tab(_ marked: String, back: Bool = false) -> String { run(marked) { MarkdownFormatting.tableMove(forward: !back, in: $0, selection: $1) } }
        let table = "| Name | Role |\n| --- | --- |\n| Ada |  |"
        XCTAssertEqual(tab("| Na¦me | Role |\n| --- | --- |\n| Ada |  |"), "| Name | «Role» |\n| --- | --- |\n| Ada |  |")
        XCTAssertEqual(tab("| Name | Ro¦le |\n| --- | --- |\n| Ada |  |"), "| Name | Role |\n| --- | --- |\n| «Ada» |  |")
        XCTAssertEqual(tab("| Name | Role |\n| --- | --- |\n| Ad¦a |  |"), "| Name | Role |\n| --- | --- |\n| Ada | ¦ |")
        XCTAssertEqual(tab("| Name | Role |\n| --- | --- |\n| Ada | ¦ |"), table + "\n| ¦ |  |")
        XCTAssertEqual(tab("| Name | Role |\n| --- | --- |\n| Ada | ¦ |", back: true), "| Name | Role |\n| --- | --- |\n| «Ada» |  |")
        XCTAssertEqual(tab("| Name | Role |\n| --- | --- |\n| Ad¦a |  |", back: true), "| Name | «Role» |\n| --- | --- |\n| Ada |  |")
        XCTAssertEqual(tab("not a ta¦ble"), "nil")

        func row(_ marked: String) -> String { run(marked) { MarkdownFormatting.tableAddRow(in: $0, selection: $1) } }
        XCTAssertEqual(row("| Na¦me | Role |\n| --- | --- |\n| Ada |  |"), "| Name | Role |\n| --- | --- |\n| ¦ |  |\n| Ada |  |")
        XCTAssertEqual(row("| Name | Role |\n| --- | --- |\n| Ad¦a |  |\nafter"), "| Name | Role |\n| --- | --- |\n| Ada |  |\n| ¦ |  |\nafter")

        func column(_ marked: String) -> String { run(marked) { MarkdownFormatting.tableAddColumn(in: $0, selection: $1) } }
        XCTAssertEqual(column("| Na¦me | Role |\n| --- | --- |\n| Ada |  |"), "| Name | ¦ | Role |\n| --- | --- | --- |\n| Ada |  |  |")
        XCTAssertEqual(column("| Name | Role |\n| --- | --- |\n| Ada | x¦ |"), "| Name | Role |¦  |\n| --- | --- | --- |\n| Ada | x |  |".replacingOccurrences(of: "Role |¦  |", with: "Role | ¦ |"))
        XCTAssertEqual(column("plain¦"), "nil")
    }

    // MARK: Tidy Table

    /// Lines a table's columns up so its pipes fall in line in the editor's fixed-width font.
    func testTidyTableLinesTheColumnsUp() {
        func tidy(_ marked: String) -> String { run(marked) { MarkdownFormatting.tidyTable(in: $0, selection: $1) } }
        XCTAssertEqual(
            tidy("| Name | Qty |\n|---|---|\n| Te¦nt | 1 |\n| Lantern | 12 |"),
            "| Name    | Qty |\n| ------- | --- |\n| Te¦nt    | 1   |\n| Lantern | 12  |"
        )
        // The caret stays where it was in its cell, wherever the cell moves to.
        XCTAssertEqual(
            tidy("| Name | Qty |\n|---|---|\n| Tent | 1 |\n| Lan¦tern | 12 |"),
            "| Name    | Qty |\n| ------- | --- |\n| Tent    | 1   |\n| Lan¦tern | 12  |"
        )
    }

    func testTidyTableKeepsAndFollowsEachColumnsAlignment() {
        func tidy(_ marked: String) -> String { run(marked) { MarkdownFormatting.tidyTable(in: $0, selection: $1) } }
        XCTAssertEqual(
            tidy("| L¦ | C | R |\n|:--|:-:|--:|\n| a | bb | ccc |\n| longer | x | 1 |"),
            "| L¦      |  C  |   R |\n| :----- | :-: | --: |\n| a      | bb  | ccc |\n| longer |  x  |   1 |"
        )
    }

    func testTidyTablePadsShortRowsAndKeepsExtraCells() {
        func tidy(_ marked: String) -> String { run(marked) { MarkdownFormatting.tidyTable(in: $0, selection: $1) } }
        // A row short of cells gets empty ones; cells past the header's are kept, never dropped.
        XCTAssertEqual(
            tidy("| a¦ | b |\n|---|---|\n| 1 |\n| 1 | 2 | 3 |"),
            "| a¦   | b   |\n| --- | --- |\n| 1   |     |\n| 1   | 2   | 3   |"
        )
    }

    func testTidyTableCountsWideCharactersAsTwoColumns() {
        func tidy(_ marked: String) -> String { run(marked) { MarkdownFormatting.tidyTable(in: $0, selection: $1) } }
        XCTAssertEqual(
            tidy("| Emoji¦ | x |\n|---|---|\n| \u{1F44D} | \u{6F22}\u{5B57} |"),
            "| Emoji¦ | x    |\n| ----- | ---- |\n| \u{1F44D}    | \u{6F22}\u{5B57} |"
        )
    }

    func testTidyTableKeepsPipesInCodeAndEscapedPipesInTheirCell() {
        func tidy(_ marked: String) -> String { run(marked) { MarkdownFormatting.tidyTable(in: $0, selection: $1) } }
        XCTAssertEqual(
            tidy("| a¦ | b |\n|---|---|\n| `x|y` | c\\|d |"),
            "| a¦     | b    |\n| ----- | ---- |\n| `x|y` | c\\|d |"
        )
    }

    func testTidyTableKeepsAListsIndentAndTheLineEndings() {
        func tidy(_ marked: String) -> String { run(marked) { MarkdownFormatting.tidyTable(in: $0, selection: $1) } }
        XCTAssertEqual(
            tidy("- item\n\n  | a¦ | bb |\n  |---|---|\n  | 1 | 2 |\nafter"),
            "- item\n\n  | a¦   | bb  |\n  | --- | --- |\n  | 1   | 2   |\nafter"
        )
        XCTAssertEqual(
            tidy("| a¦ | b |\r\n|---|---|\r\n| 1 | 2 |"),
            "| a¦   | b   |\r\n| --- | --- |\r\n| 1   | 2   |"
        )
    }

    func testTidyTableDoesNothingOutsideATableOrWhenItIsTidy() {
        func tidy(_ marked: String) -> String { run(marked) { MarkdownFormatting.tidyTable(in: $0, selection: $1) } }
        XCTAssertEqual(tidy("plain¦ text"), "nil")
        XCTAssertEqual(tidy("| a¦   | b   |\n| --- | --- |\n| 1   | 2   |"), "nil")
    }

    func testAlignment() {
        func align(_ alignment: String?, _ marked: String) -> String { run(marked) { MarkdownFormatting.setAlignment(alignment, in: $0, selection: $1) } }
        XCTAssertEqual(align("center", "Tit¦le"), "<div align=\"center\">\n\nTit¦le\n\n</div>")
        XCTAssertEqual(align("right", "«one\ntwo»\nthree"), "<div align=\"right\">\n\n«one\ntwo»\n\n</div>\n\nthree")
        XCTAssertEqual(align("right", "<div align=\"center\">\n\nTit¦le\n\n</div>"), "<div align=\"right\">\n\nTit¦le\n\n</div>")
        XCTAssertEqual(align("center", "<div align=\"center\">\n\nTit¦le\n\n</div>"), "Tit¦le")
        XCTAssertEqual(align(nil, "<div align=\"center\">\n\nTit¦le\n\n</div>\nafter"), "Tit¦le\nafter")
        XCTAssertEqual(align("left", "a\n<DIV ALIGN='right'>\nTit¦le\n</div>\nb"), "a\nTit¦le\nb")
        XCTAssertEqual(align(nil, "Tit¦le"), "nil")
        XCTAssertEqual(align("center", "a\r\nb¦\r\n"), "a\r\n<div align=\"center\">\r\n\r\nb¦\r\n\r\n</div>\r\n")
        // Wrapping and unwrapping comes back to the same text.
        for text in ["Tit¦le", "a\n\n«b\nc»\n\nd", "«x»\n"] {
            let note = Marked(text)
            let wrapped = note.applying(MarkdownFormatting.setAlignment("center", in: note.text, selection: note.selection))!
            let back = wrapped.applying(MarkdownFormatting.setAlignment(nil, in: wrapped.text, selection: wrapped.selection))!
            XCTAssertEqual(back.description, text)
        }
    }

    // MARK: What the editor shows

    func testTheHighlighterReadsInlineFormatting() {
        func kinds(_ text: String, at needle: String) -> [MarkdownSpanKind] {
            let range = (text as NSString).range(of: needle)
            return MarkdownHighlighter.highlight(text).spans.filter { NSLocationInRange(range.location, $0.range) }.map(\.kind)
        }
        let text = "a <span style=\"color: #d94f3d\">red <u>under</u></span> <mark style=\"background-color: #3B82D9\">blue</mark> <span style=\"font-size: 1.3em\">big</span> H~two~O x^nine^ <mark>plain</mark>"
        XCTAssertEqual(kinds(text, at: "red"), [.textColor("#D94F3D")])
        XCTAssertEqual(kinds(text, at: "under"), [.textColor("#D94F3D"), .underline])
        XCTAssertEqual(kinds(text, at: "blue"), [.highlightColor("#3B82D9")])
        XCTAssertEqual(kinds(text, at: "big"), [.textSize(1.3)])
        XCTAssertEqual(kinds(text, at: "two"), [.subscript])
        XCTAssertEqual(kinds(text, at: "nine"), [.superscript])
        XCTAssertEqual(kinds(text, at: "plain"), [.highlight])
        XCTAssertEqual(kinds(text, at: "<span"), [.formatTag])
        // A tag inside a colored span is still a tag: it is dimmed after the color goes on.
        XCTAssertEqual(kinds(text, at: "<u>").last, .formatTag)
        XCTAssertEqual(kinds(text, at: "</mark>"), [.formatTag])
        // Tags the editor draws nothing for are never the hiding kind: hiding them would hide content.
        for other in ["line<br>break", "press <kbd>K</kbd> now", "<details>", "<summary>Title</summary>", "<img src=\"a.png\" width=\"300\">", "empty <u></u> pair", "Array<String> and Set<Int>"] {
            let spans = MarkdownHighlighter.highlight(other as NSString, range: NSRange(location: 0, length: (other as NSString).length)).spans
            XCTAssertFalse(spans.contains { $0.kind == .formatTag }, other)
        }

        // Forgiving about how a tag is written, since other apps write them too.
        XCTAssertEqual(kinds("<SPAN STYLE='COLOR:#abc; font-weight: bold'>x y</SPAN>", at: "x y"), [.textColor("#AABBCC"), .strong])
        XCTAssertEqual(kinds("<b>bold</b> <em>it</em> <del>gone</del>", at: "bold"), [.strong])
        // Nothing is colored without both ends on the line, and nothing inside code or a comment.
        XCTAssertEqual(kinds("an <span style=\"color: #D94F3D\">unclosed one", at: "unclosed"), [])
        XCTAssertEqual(kinds("an <span style=\"color: #D94F3D\">unclosed one", at: "<span"), [.htmlTag])
        XCTAssertEqual(kinds("`<u>code</u>` here", at: "code"), [.inlineCode])
        XCTAssertEqual(kinds("```\n<u>code</u>\n```", at: "code"), [.codeBlock])
        XCTAssertEqual(kinds("<!-- <u>note</u> -->", at: "note"), [.comment])
        XCTAssertEqual(kinds("a < b and c > d ~ e ^ f", at: "b"), [])
        XCTAssertEqual(kinds("see <https://example.com> now", at: "example"), [.linkText])
    }

    // MARK: Colors people can read

    func testPaletteColorsAreReadableOnEveryBuiltInTheme() {
        for palette in ThemePresets.all {
            guard let background = ThemeRGB(hex: palette.background) else { return XCTFail("bad background") }
            for swatch in FormatPalette.colors + [.init(name: "Black", hex: "#000000"), .init(name: "White", hex: "#FFFFFF"), .init(name: "Yellow", hex: "#FFFF00")] {
                let color = ThemeRGB(hex: swatch.hex)!
                let shown = FormatPalette.legible(color, on: background)
                XCTAssertGreaterThanOrEqual(ThemeContrast.ratio(shown, background), 4.5 - 0.001, "\(swatch.name) on \(palette.name)")
                if ThemeContrast.ratio(color, background) >= 4.5 { XCTAssertEqual(shown, color, "a readable color is left alone") }
                // Only the lightness moves.
                let before = FormatPalette.hsl(color), after = FormatPalette.hsl(shown)
                if before.saturation > 0.05, after.lightness > 0.03, after.lightness < 0.97 {
                    XCTAssertEqual(before.hue, after.hue, accuracy: 0.02, "\(swatch.name) on \(palette.name)")
                }
            }
        }
        XCTAssertEqual(FormatPalette.normalizedHex("#abc"), "#AABBCC")
        XCTAssertEqual(FormatPalette.normalizedHex("d94f3d"), "#D94F3D")
        XCTAssertNil(FormatPalette.normalizedHex("red"))
        XCTAssertNil(FormatPalette.normalizedHex("#12345"))
    }
}
