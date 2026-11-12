import XCTest
@testable import PerchKit

final class MarkdownEditingTests: XCTestCase {
    private func caret(_ location: Int) -> NSRange { NSRange(location: location, length: 0) }
    private func end(_ text: String) -> NSRange { caret((text as NSString).length) }

    // MARK: Return

    func testReturnContinuesBulletsNumbersAndTasks() throws {
        var text = "- one"
        var edit = try XCTUnwrap(MarkdownEditing.newline(in: text, selection: end(text)))
        XCTAssertEqual(edit.applied(to: text), "- one\n- ")
        XCTAssertEqual(edit.selection, caret(8))

        text = "  3. three"
        edit = try XCTUnwrap(MarkdownEditing.newline(in: text, selection: end(text)))
        XCTAssertEqual(edit.applied(to: text), "  3. three\n  4. ")

        text = "* [x] done"
        edit = try XCTUnwrap(MarkdownEditing.newline(in: text, selection: end(text)))
        XCTAssertEqual(edit.applied(to: text), "* [x] done\n* [ ] ")

        text = "> quoted"
        edit = try XCTUnwrap(MarkdownEditing.newline(in: text, selection: end(text)))
        XCTAssertEqual(edit.applied(to: text), "> quoted\n> ")
    }

    func testReturnSplitsAnItemAtTheCaret() throws {
        let text = "- one two"
        let edit = try XCTUnwrap(MarkdownEditing.newline(in: text, selection: caret(5)))
        XCTAssertEqual(edit.applied(to: text), "- one\n-  two")
    }

    func testReturnOnEmptyItemEndsTheListOrStepsOut() throws {
        var text = "- one\n- "
        var edit = try XCTUnwrap(MarkdownEditing.newline(in: text, selection: end(text)))
        XCTAssertEqual(edit.applied(to: text), "- one\n")
        XCTAssertEqual(edit.selection, caret(6))

        text = "- one\n    - "
        edit = try XCTUnwrap(MarkdownEditing.newline(in: text, selection: end(text)))
        XCTAssertEqual(edit.applied(to: text), "- one\n- ")

        text = "- [ ] "
        edit = try XCTUnwrap(MarkdownEditing.newline(in: text, selection: end(text)))
        XCTAssertEqual(edit.applied(to: text), "")

        text = "> "
        edit = try XCTUnwrap(MarkdownEditing.newline(in: text, selection: end(text)))
        XCTAssertEqual(edit.applied(to: text), "")
    }

    func testReturnElsewhereIsOrdinary() {
        XCTAssertNil(MarkdownEditing.newline(in: "plain text", selection: caret(5)))
        XCTAssertNil(MarkdownEditing.newline(in: "- item", selection: caret(1)), "inside the marker")
        XCTAssertNil(MarkdownEditing.newline(in: "- item", selection: NSRange(location: 2, length: 2)), "with a selection")
        XCTAssertNil(MarkdownEditing.newline(in: "---", selection: caret(3)), "a rule is not a list")
        XCTAssertNil(MarkdownEditing.newline(in: "**bold** start", selection: caret(14)))
    }

    func testReturnCountsEmojiAsUTF16() throws {
        let text = "- ✈️ 👍 trip"
        let edit = try XCTUnwrap(MarkdownEditing.newline(in: text, selection: end(text)))
        XCTAssertEqual(edit.applied(to: text), text + "\n- ")
        XCTAssertEqual(edit.selection.location, (text as NSString).length + 3)
    }

    // MARK: Tab

    func testTabIndentsListItemsOnly() throws {
        let text = "- one\n- two"
        let edit = try XCTUnwrap(MarkdownEditing.indent(in: text, selection: end(text), outdent: false))
        XCTAssertEqual(edit.applied(to: text), "- one\n    - two")
        XCTAssertEqual(edit.selection, caret(15))
        XCTAssertNil(MarkdownEditing.indent(in: "plain", selection: caret(2), outdent: false))
    }

    func testShiftTabOutdents() throws {
        var text = "- one\n    - two"
        var edit = try XCTUnwrap(MarkdownEditing.indent(in: text, selection: end(text), outdent: true))
        XCTAssertEqual(edit.applied(to: text), "- one\n- two")
        text = "\t- tabbed"
        edit = try XCTUnwrap(MarkdownEditing.indent(in: text, selection: caret(3), outdent: true))
        XCTAssertEqual(edit.applied(to: text), "- tabbed")
        XCTAssertNil(MarkdownEditing.indent(in: "- flat", selection: caret(3), outdent: true))
    }

    func testTabMovesEverySelectedLine() throws {
        let text = "a\n- b\n\nc\nd"
        let selection = NSRange(location: 0, length: 8)
        let edit = try XCTUnwrap(MarkdownEditing.indent(in: text, selection: selection, outdent: false))
        XCTAssertEqual(edit.applied(to: text), "    a\n    - b\n\n    c\nd")
        let back = try XCTUnwrap(MarkdownEditing.indent(in: edit.applied(to: text), selection: edit.selection, outdent: true))
        XCTAssertEqual(back.applied(to: edit.applied(to: text)), text)
    }

    // MARK: Wrapping

    func testBoldWrapsAndUnwraps() {
        let text = "make this bold"
        let wrap = MarkdownEditing.toggleWrap(in: text, selection: NSRange(location: 5, length: 4), left: "**", right: "**")
        XCTAssertEqual(wrap.applied(to: text), "make **this** bold")
        XCTAssertEqual(wrap.selection, NSRange(location: 7, length: 4))
        let bolded = wrap.applied(to: text)
        let unwrap = MarkdownEditing.toggleWrap(in: bolded, selection: wrap.selection, left: "**", right: "**")
        XCTAssertEqual(unwrap.applied(to: bolded), text)
        XCTAssertEqual(unwrap.selection, NSRange(location: 5, length: 4))
        let outer = MarkdownEditing.toggleWrap(in: bolded, selection: NSRange(location: 5, length: 8), left: "**", right: "**")
        XCTAssertEqual(outer.applied(to: bolded), text)
    }

    func testItalicInsideBoldDoesNotEatTheBold() {
        let text = "**bold**"
        let edit = MarkdownEditing.toggleWrap(in: text, selection: NSRange(location: 2, length: 4), left: "*", right: "*")
        XCTAssertEqual(edit.applied(to: text), "***bold***")
        let both = edit.applied(to: text)
        let off = MarkdownEditing.toggleWrap(in: both, selection: edit.selection, left: "*", right: "*")
        XCTAssertEqual(off.applied(to: both), text)
    }

    func testWrapWithNothingSelectedPutsCaretInside() {
        let edit = MarkdownEditing.toggleWrap(in: "", selection: caret(0), left: "`", right: "`")
        XCTAssertEqual(edit.applied(to: ""), "``")
        XCTAssertEqual(edit.selection, caret(1))
    }

    func testTypingAMarkOverASelectionWrapsIt() throws {
        let text = "a word here"
        let selection = NSRange(location: 2, length: 4)
        let star = try XCTUnwrap(MarkdownEditing.wrapSelection(typing: "*", in: text, selection: selection))
        XCTAssertEqual(star.applied(to: text), "a *word* here")
        let twice = try XCTUnwrap(MarkdownEditing.wrapSelection(typing: "*", in: star.applied(to: text), selection: star.selection))
        XCTAssertEqual(twice.applied(to: star.applied(to: text)), "a **word** here")
        let bracket = try XCTUnwrap(MarkdownEditing.wrapSelection(typing: "[", in: text, selection: selection))
        XCTAssertEqual(bracket.applied(to: text), "a [word] here")
        XCTAssertNil(MarkdownEditing.wrapSelection(typing: "x", in: text, selection: selection))
        XCTAssertNil(MarkdownEditing.wrapSelection(typing: "*", in: text, selection: caret(2)))
    }

    func testLinks() {
        let text = "see docs"
        let label = MarkdownEditing.link(in: text, selection: NSRange(location: 4, length: 4))
        XCTAssertEqual(label.applied(to: text), "see [docs](url)")
        XCTAssertEqual((label.applied(to: text) as NSString).substring(with: label.selection), "url")
        let address = "https://example.com"
        let target = MarkdownEditing.link(in: address, selection: NSRange(location: 0, length: 19))
        XCTAssertEqual(target.applied(to: address), "[](https://example.com)")
        XCTAssertEqual(target.selection, caret(1))
        let wiki = MarkdownEditing.wikiLink(in: text, selection: NSRange(location: 4, length: 4))
        XCTAssertEqual(wiki.applied(to: text), "see [[docs]]")
        XCTAssertEqual(MarkdownEditing.wikiLink(in: "", selection: caret(0)).replacement, "[[")
    }

    // MARK: Line prefixes

    func testHeadingCycles() {
        var text = "Title"
        var selection = caret(5)
        for expected in ["# Title", "## Title", "### Title", "Title"] {
            let edit = MarkdownEditing.cycleHeading(in: text, selection: selection)
            text = edit.applied(to: text)
            selection = edit.selection
            XCTAssertEqual(text, expected)
            XCTAssertEqual(selection.location, (text as NSString).length)
        }
    }

    func testListToggles() {
        let text = "one\ntwo"
        let all = NSRange(location: 0, length: 7)
        let bullets = MarkdownEditing.toggleList(in: text, selection: all, kind: .bullet)
        XCTAssertEqual(bullets.applied(to: text), "- one\n- two")
        let tasks = MarkdownEditing.toggleList(in: bullets.applied(to: text), selection: bullets.selection, kind: .task)
        XCTAssertEqual(tasks.applied(to: bullets.applied(to: text)), "- [ ] one\n- [ ] two")
        let plain = MarkdownEditing.toggleList(in: "- [ ] one\n- [ ] two", selection: NSRange(location: 0, length: 19), kind: .task)
        XCTAssertEqual(plain.applied(to: "- [ ] one\n- [ ] two"), text)
        let numbered = MarkdownEditing.toggleList(in: text, selection: all, kind: .numbered)
        XCTAssertEqual(numbered.applied(to: text), "1. one\n2. two")
        let single = MarkdownEditing.toggleList(in: "  item", selection: caret(4), kind: .task)
        XCTAssertEqual(single.applied(to: "  item"), "  - [ ] item")
        XCTAssertEqual(single.selection, caret(10))
    }

    func testLineLookups() {
        let text = "a\nbb\n\nccc" as NSString
        XCTAssertEqual(MarkdownEditing.lineNumber(of: 0, in: text), 0)
        XCTAssertEqual(MarkdownEditing.lineNumber(of: 3, in: text), 1)
        XCTAssertEqual(MarkdownEditing.lineNumber(of: 99, in: text), 3)
        XCTAssertEqual(MarkdownEditing.location(ofLine: 3, in: text), 6)
        XCTAssertEqual(MarkdownEditing.location(ofLine: 9, in: text), text.length)
    }
}

final class MarkdownHighlighterTests: XCTestCase {
    private func kinds(_ text: String, at needle: String) -> [MarkdownSpanKind] {
        let range = (text as NSString).range(of: needle)
        XCTAssertNotEqual(range.location, NSNotFound, "\(needle) not in text")
        return MarkdownHighlighter.highlight(text).spans
            .filter { NSIntersectionRange($0.range, range).length == range.length }
            .map(\.kind)
    }

    func testHeadingsAndInlineStyles() {
        let text = "## A *fine* title\n\nSome **bold**, _soft_, ~~gone~~, ==lit== and `code` text."
        XCTAssertTrue(kinds(text, at: "A *fine* title").contains(.heading(level: 2)))
        XCTAssertTrue(kinds(text, at: "fine").contains(.emphasis))
        XCTAssertEqual(kinds(text, at: "##"), [.heading(level: 2), .marker])
        XCTAssertEqual(kinds(text, at: "bold"), [.strong])
        XCTAssertEqual(kinds(text, at: "soft"), [.emphasis])
        XCTAssertEqual(kinds(text, at: "gone"), [.strikethrough])
        XCTAssertEqual(kinds(text, at: "lit"), [.highlight])
        XCTAssertEqual(kinds(text, at: "code"), [.inlineCode])
        XCTAssertEqual(kinds(text, at: "text."), [])
    }

    func testMarksInsideCodeAndLinksAreLeftAlone() {
        let text = "Use `a **b** c` and [[Some_Note_Name]] and [x_y](http://a.b/c_d_e) and snake_case_word."
        XCTAssertEqual(kinds(text, at: "b"), [.inlineCode])
        XCTAssertEqual(kinds(text, at: "Some_Note_Name"), [.wikiLink])
        XCTAssertEqual(kinds(text, at: "x_y"), [.linkText])
        XCTAssertEqual(kinds(text, at: "http://a.b/c_d_e"), [.linkURL])
        XCTAssertEqual(kinds(text, at: "snake_case_word"), [])
        XCTAssertEqual(kinds("5 * 3 * 2 and 2*3", at: "3"), [])
        XCTAssertEqual(kinds("see https://example.com/a_b now", at: "https://example.com/a_b"), [.linkText])
    }

    func testListsTasksAndQuotes() {
        let text = "- plain\n  1. numbered\n- [ ] open\n- [x] done item\n> [!note] Heads up\n> quoted **text**"
        XCTAssertEqual(kinds(text, at: "1."), [.listMarker])
        XCTAssertEqual(kinds(text, at: "[ ]"), [.taskBox(checked: false)])
        XCTAssertEqual(kinds(text, at: "[x]"), [.taskBox(checked: true)])
        XCTAssertEqual(kinds(text, at: "done item"), [.taskDone])
        XCTAssertEqual(kinds(text, at: "[!note]"), [.blockquote, .calloutTag])
        XCTAssertEqual(kinds(text, at: "text"), [.blockquote, .strong])
        let lines = MarkdownHighlighter.highlight(text).lines
        XCTAssertEqual(lines.map(\.prefixLength), [2, 5, 6, 6, 2, 2])
    }

    func testFencesCarryStateAcrossLines() {
        let text = "before\n```swift\nlet **x** = 1\n```\nafter **bold**\n~~~\n- [ ] not a task\n~~~"
        XCTAssertEqual(kinds(text, at: "```swift"), [.codeBlock, .codeFence])
        XCTAssertEqual(kinds(text, at: "x"), [.codeBlock])
        XCTAssertEqual(kinds(text, at: "bold"), [.strong])
        XCTAssertEqual(kinds(text, at: "[ ]"), [.codeBlock])
        let result = MarkdownHighlighter.highlight(text)
        XCTAssertEqual(result.lines.map(\.after), [.normal, .fence("```"), .fence("```"), .normal, .normal, .fence("~~~"), .fence("~~~"), .normal])
        XCTAssertEqual(result.endState, .normal)
        XCTAssertEqual(MarkdownHighlighter.highlight("```\nopen").endState, .fence("```"))
    }

    func testStylingOneLineMatchesStylingEverything() {
        let text = "---\ntitle: x\n---\n# Head\n```\ncode *a*\n```\n- [x] done\n$$\nx^2\n$$\nend *it*\n"
        let whole = MarkdownHighlighter.highlight(text)
        var pieces: [MarkdownSpan] = []
        var state = MarkdownHighlighter.initialState
        for line in whole.lines {
            XCTAssertEqual(line.before, state)
            let part = MarkdownHighlighter.highlight(text as NSString, range: line.range, startState: state)
            XCTAssertEqual(part.lines.count, 1)
            pieces += part.spans
            state = part.endState
        }
        XCTAssertEqual(pieces, whole.spans)
        XCTAssertEqual(state, whole.endState)
    }

    func testFrontmatterNeedsAnEnd() {
        let closed = "---\ntags: [a]\n---\nBody"
        XCTAssertEqual(kinds(closed, at: "tags:"), [.frontmatter, .frontmatterKey])
        XCTAssertEqual(kinds(closed, at: "Body"), [])
        let open = "---\nJust a rule above"
        XCTAssertEqual(kinds(open, at: "---"), [.rule])
        XCTAssertEqual(kinds(open, at: "Just"), [])
        XCTAssertEqual(kinds("text\n\n---\n", at: "---"), [.rule])
    }

    func testBlockStateRoundTripsThroughItsCode() {
        for state in [MarkdownBlockState.normal, .frontmatter, .fence("````"), .fence("~~~"), .math] {
            XCTAssertEqual(MarkdownBlockState(code: state.code), state)
        }
    }

    func testTablesMathRulesAndOddInput() {
        XCTAssertEqual(kinds("| a | **b** |", at: "b"), [.table, .strong])
        XCTAssertEqual(kinds("$$\nx\n$$", at: "x"), [.codeBlock])
        XCTAssertEqual(kinds("* * *", at: "* * *"), [.rule])
        XCTAssertEqual(MarkdownHighlighter.highlight("").spans, [])
        XCTAssertEqual(MarkdownHighlighter.highlight("\n\n").lines.count, 2)
        // Unbalanced marks never crash or loop.
        _ = MarkdownHighlighter.highlight("**a *b `c [[d [e](f ~~g ==h $$ ``` ___")
        let long = String(repeating: "- item with **bold** and `code` and [[Link]]\n", count: 4000)
        measure { _ = MarkdownHighlighter.highlight(long) }
    }
}
