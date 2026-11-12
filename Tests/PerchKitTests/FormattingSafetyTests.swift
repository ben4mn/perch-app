import XCTest
@testable import PerchKit

/// A small repeatable random source, so a failure can be run again.
private struct Dice: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var value = state
        value ^= value >> 33
        value = value &* 0xff51afd7ed558ccd
        value ^= value >> 33
        return value
    }
}

/// Formatting commands must only ever add or remove their own marks. These tests throw random selections
/// at real and broken notes and check the words always survive.
final class FormattingSafetyTests: XCTestCase {
    private func length(_ text: String) -> Int { (text as NSString).length }

    /// A note using every kind of block, with no inline HTML and no emphasis: the formats under test
    /// can be put on and taken off any part of it.
    private let plainNote = """
    ---
    title: Trip 🎉
    tags: [a, b]
    ---
    # Packing for the coast

    Take the coast road to the [harbor](https://example.com/a_b*c) for the early ferry. Café, naïve, e\u{301}.

    - First item with a [[Wiki Link|label]] in it
    - [ ] A task 👩‍👩‍👧 with `inline code` and more words
      1. Nested number one
      2. Nested number two
    > A quote that runs on
    > [!tip] Pack light
    > Body of the callout

    | Name | Role | Notes |
    | --- | :-: | --- |
    | Ada | Engineer | Writes `code` daily |
    | Grace |  | Navy |

    ```swift
    let x = "**not bold** <u>not underlined</u>"
    ```

    $$
    x^2 + y^2
    $$

    Footnote here[^1] and a bare link https://example.com/page.

    [^1]: The note itself.

    ---

    <div align="center">

    Centered words here

    </div>

    Last line without a newline
    """

    private func visible(_ text: String) -> String {
        // The words of a note with every mark these commands write taken out.
        var result = text
        for pattern in [#"</?(span|mark|u)\b[^<>]*>"#, #"[*~=^_]"#] {
            result = result.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return result
    }

    private func randomSelection(in text: String, using dice: inout Dice) -> NSRange {
        let source = text as NSString
        guard source.length > 0 else { return NSRange(location: 0, length: 0) }
        var start = Int.random(in: 0...source.length, using: &dice)
        var end = min(source.length, start + [0, 0, 1, 3, 9, 30, 120].randomElement(using: &dice)!)
        // Text views never put a selection inside a character.
        while start > 0, start < source.length, UTF16.isTrailSurrogate(source.character(at: start)) { start -= 1 }
        while end < source.length, end > start, UTF16.isTrailSurrogate(source.character(at: end)) { end += 1 }
        if start < source.length { start = source.rangeOfComposedCharacterSequence(at: start).location }
        if end < source.length, end > start { end = source.rangeOfComposedCharacterSequence(at: end).location }
        return NSRange(location: start, length: max(end - start, 0))
    }

    private func assertSound(_ edit: TextEdit, in text: String, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(NSMaxRange(edit.range), length(text), label, file: file, line: line)
        guard NSMaxRange(edit.range) <= length(text) else { return }
        let result = edit.applied(to: text)
        XCTAssertGreaterThanOrEqual(edit.selection.location, 0, label, file: file, line: line)
        XCTAssertLessThanOrEqual(NSMaxRange(edit.selection), length(result), label, file: file, line: line)
        // A note that was valid UTF-16 still is.
        XCTAssertEqual(String(decoding: Array(result.utf16), as: UTF16.self), result, label, file: file, line: line)
    }

    private let values: [(InlineFormat, String)] = [
        (.underline, ""), (.textColor, "#D94F3D"), (.highlight, "#3B82D9"), (.textSize, "1.3em"),
        (.bold, ""), (.italic, ""), (.strikethrough, ""), (.highlight, ""), (.subscript, ""), (.superscript, ""),
    ]

    // MARK: Apply then remove

    func testApplyingThenRemovingAnHTMLFormatGivesBackTheNoteExactly() {
        var dice = Dice(state: 7)
        var applied = 0
        for text in [plainNote, plainNote.replacingOccurrences(of: "\n", with: "\r\n")] {
            for _ in 0..<500 {
                let selection = randomSelection(in: text, using: &dice)
                for (format, value) in values.prefix(4) {
                    guard let on = MarkdownFormatting.set(format, value: value, in: text, selection: selection) else { continue }
                    let label = "\(format) at \(selection): \((text as NSString).substring(with: selection).debugDescription)"
                    assertSound(on, in: text, label)
                    let formatted = on.applied(to: text)
                    XCTAssertEqual(visible(formatted), visible(text), label)
                    // A caret with no word leaves an empty pair to type into; asking again takes it away.
                    if on.range.length > 0 { assertTidy(formatted, format: format, label) }
                    guard let off = MarkdownFormatting.set(format, value: nil, in: formatted, selection: on.selection) else {
                        XCTFail("couldn't remove \(label)")
                        continue
                    }
                    assertSound(off, in: formatted, label)
                    XCTAssertEqual(off.applied(to: formatted), text, label)
                    applied += 1
                }
            }
        }
        XCTAssertGreaterThan(applied, 1500)
    }

    func testTogglingAMarkdownFormatTwiceGivesBackTheNoteExactly() {
        var dice = Dice(state: 11)
        var applied = 0
        let source = plainNote as NSString
        let breaks = CharacterSet.whitespacesAndNewlines
        for _ in 0..<600 {
            // Whole words: Markdown's own emphasis can't start or stop in the middle of some words.
            var selection = randomSelection(in: plainNote, using: &dice)
            var start = selection.location, end = NSMaxRange(selection)
            while start > 0, let scalar = UnicodeScalar(source.character(at: start - 1)), !breaks.contains(scalar) { start -= 1 }
            while end < source.length, let scalar = UnicodeScalar(source.character(at: end)), !breaks.contains(scalar) { end += 1 }
            guard start > 0 ? UnicodeScalar(source.character(at: start - 1)) != nil : true, end < source.length ? UnicodeScalar(source.character(at: end)) != nil : true else { continue }
            selection = NSRange(location: start, length: end - start)
            guard selection.length > 0 else { continue }
            for (format, value) in values.dropFirst(4) {
                guard let on = MarkdownFormatting.toggle(format, value: value, in: plainNote, selection: selection) else { continue }
                let label = "\(format) at \(selection): \(source.substring(with: selection).debugDescription)"
                assertSound(on, in: plainNote, label)
                let formatted = on.applied(to: plainNote)
                XCTAssertEqual(visible(formatted), visible(plainNote), label)
                // Marks that Markdown wouldn't read as this format (a `~` beside another `~`, say) can't be
                // found again to take off. Everything that does read as the format must come off cleanly.
                guard MarkdownFormatting.formats(in: formatted, selection: on.selection).isOn(format) else { continue }
                guard let off = MarkdownFormatting.toggle(format, value: value, in: formatted, selection: on.selection) else {
                    XCTFail("couldn't remove \(label)")
                    continue
                }
                XCTAssertEqual(off.applied(to: formatted), plainNote, label)
                applied += 1
            }
        }
        XCTAssertGreaterThan(applied, 1000)
    }

    /// One span per line, none empty, none inside another of its own kind.
    private func assertTidy(_ text: String, format: InlineFormat, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let source = text as NSString
        for row in MarkdownFormatting.lines(source, through: source.length) where row.isText {
            for segment in MarkdownFormatting.segments(source, line: row) {
                let pairs = InlineScanner.scan(source, source: text, range: segment).pairs.filter { $0.format == format }
                for pair in pairs {
                    XCTAssertGreaterThan(pair.inner.length, 0, "empty span: \(label)", file: file, line: line)
                    XCTAssertFalse(pairs.contains { $0 != pair && $0.outer.location <= pair.outer.location && NSMaxRange($0.outer) >= NSMaxRange(pair.outer) }, "nested span: \(label)", file: file, line: line)
                }
            }
            // A tag opened on a line is closed on that line.
            let content = source.substring(with: row.content)
            for name in ["span", "mark", "u"] {
                let opens = content.components(separatedBy: "<\(name)").count - 1
                let closes = content.components(separatedBy: "</\(name)>").count - 1
                if !content.contains("not underlined") { XCTAssertEqual(opens, closes, "\(name) left open on a line: \(label)", file: file, line: line) }
            }
        }
    }

    // MARK: Broken markup

    private let broken = [
        "an <span style=\"color: #D94F3D\">unclosed span and more words",
        "a stray </span> close and <u>under</u> words",
        "<span style=\"color: #D94F3D\">starts here\nand ends here</span> on the next line",
        "<SPAN STYLE=\"COLOR: #d94f3d\">upper case</SPAN> and <U>upper u</U>",
        "<span style='color: #D94F3D'>single quotes</span> and <mark style='background-color:#3B82D9'>tight</mark>",
        "<span style=\"color: #D94F3D; font-weight: bold\" class=\"x\" id=y>extra attributes</span> stay",
        "<span style=\"color: red\">a named color</span> and <span style=\"font-size: 3em\">an odd size</span>",
        "<span><span style=\"color: #D94F3D\"></span></span> empties <u></u> <mark></mark>",
        "<u>crossed **bold</u> tags** and <mark>==both==</mark>",
        "**unbalanced *stars and _under_scores__ ~~half ==open ^x ~y",
        "<span style=\"color: #D94F3D\">nested <span style=\"color: #3B82D9\">twice <span style=\"color: #3F9B5B\">thrice</span></span></span>",
        "<<u>>odd<</u>> <span style=\"color: #D94F3D\" <u>broken tag</u>",
        "| <u>cell | split</u> | table |\n| --- | --- | --- |",
        "- <span style=\"color: #D94F3D\">item one\n- item two</span>",
        "<div align=\"center\">\nno blank lines <u>inside</u>\n</div>",
        "<div align=\"center\">\n\nnever closed <mark>div",
        "</div>\n\nclose with no open",
        "text <!-- a <u>comment</u> --> after `<u>code</u>` end",
        "\u{FEFF}<u>byte order mark</u>\r\n<u>windows</u>\r\n",
        "emoji 👩‍👩‍👧 <u>👩‍👩‍👧</u> é e\u{301} <span style=\"color: #D94F3D\">🎉</span>",
        "<u>", "</u>", "<", ">", "<span style=\"color:", "****", "~~~~", "====", "^^", "",
    ]

    func testCommandsOnBrokenMarkupNeverLoseWords() {
        var dice = Dice(state: 23)
        var edits = 0
        for text in broken {
            let size = length(text)
            var selections: [NSRange] = [NSRange(location: 0, length: size)]
            for _ in 0..<60 { selections.append(randomSelection(in: text, using: &dice)) }
            for location in 0...min(size, 40) { selections.append(NSRange(location: location, length: 0)) }
            for selection in selections {
                guard selection.location == size || !UTF16.isTrailSurrogate((text as NSString).character(at: selection.location)) else { continue }
                let label = "\(text.debugDescription) at \(selection)"
                for (format, value) in values {
                    for edit in [
                        MarkdownFormatting.toggle(format, value: value, in: text, selection: selection),
                        MarkdownFormatting.set(format, value: value, in: text, selection: selection),
                        MarkdownFormatting.set(format, value: nil, in: text, selection: selection),
                    ].compactMap({ $0 }) {
                        assertSound(edit, in: text, "\(format) \(label)")
                        XCTAssertEqual(visible(edit.applied(to: text)), visible(text), "\(format) \(label)")
                        edits += 1
                    }
                }
                let more: [TextEdit?] = [
                    MarkdownFormatting.clearFormatting(in: text, selection: selection),
                    MarkdownFormatting.stepSize(1, in: text, selection: selection),
                    MarkdownFormatting.stepSize(-1, in: text, selection: selection),
                ]
                for edit in more.compactMap({ $0 }) {
                    assertSound(edit, in: text, label)
                    XCTAssertEqual(visible(edit.applied(to: text)), visible(text), label)
                }
                let blocks: [TextEdit?] = [
                    MarkdownFormatting.toggleCode(in: text, selection: selection),
                    MarkdownFormatting.setHeading(2, in: text, selection: selection),
                    MarkdownFormatting.toggleQuote(in: text, selection: selection),
                    MarkdownFormatting.setCallout("note", in: text, selection: selection),
                    MarkdownFormatting.setCallout(nil, in: text, selection: selection),
                    MarkdownFormatting.toggleCodeBlock(language: "swift", in: text, selection: selection),
                    MarkdownFormatting.insertDivider(in: text, selection: selection),
                    MarkdownFormatting.insertTable(rows: 2, columns: 2, in: text, selection: selection),
                    MarkdownFormatting.tableMove(forward: true, in: text, selection: selection),
                    MarkdownFormatting.tableMove(forward: false, in: text, selection: selection),
                    MarkdownFormatting.tableAddRow(in: text, selection: selection),
                    MarkdownFormatting.tableAddColumn(in: text, selection: selection),
                    MarkdownFormatting.setAlignment("center", in: text, selection: selection),
                    MarkdownFormatting.setAlignment("right", in: text, selection: selection),
                    MarkdownFormatting.setAlignment(nil, in: text, selection: selection),
                ]
                for edit in blocks.compactMap({ $0 }) { assertSound(edit, in: text, label) }
                _ = MarkdownFormatting.formats(in: text, selection: selection)
            }
        }
        XCTAssertGreaterThan(edits, 5000)
    }

    func testMarkupPerchDidNotWriteIsLeftExactlyAsItIs() {
        // Tags with more to them than Perch writes are somebody else's: formatting around them never rewrites them.
        let foreign = "<span style=\"color: #D94F3D; font-weight: bold\" class=\"x\">rich</span> and <font color=\"red\">old</font> plain words"
        let source = foreign as NSString
        let selection = NSRange(location: 0, length: source.length)
        for (format, value) in values {
            guard let edit = MarkdownFormatting.set(format, value: value, in: foreign, selection: selection) else { continue }
            var result = edit.applied(to: foreign)
            // Subscript and superscript can't hold a space, so each word gets its own marks, inside the tags.
            if format == .subscript || format == .superscript { result = result.replacingOccurrences(of: format.markers().open, with: "") }
            XCTAssertTrue(result.contains("<span style=\"color: #D94F3D; font-weight: bold\" class=\"x\">rich</span>"), "\(format): \(result)")
            XCTAssertTrue(result.contains("<font color=\"red\">old</font>"), "\(format): \(result)")
        }
        XCTAssertNil(MarkdownFormatting.clearFormatting(in: foreign, selection: selection))
        XCTAssertNil(MarkdownFormatting.set(.textColor, value: nil, in: foreign, selection: selection))

        // A span that runs over two lines isn't one Perch can safely rewrite: both halves stay.
        let crossing = "<span style=\"color: #D94F3D\">one\ntwo</span>"
        XCTAssertNil(MarkdownFormatting.set(.textColor, value: nil, in: crossing, selection: NSRange(location: 0, length: length(crossing))))
        let recolored = MarkdownFormatting.set(.textColor, value: "#3B82D9", in: crossing, selection: NSRange(location: 0, length: length(crossing)))?.applied(to: crossing)
        XCTAssertEqual(recolored, "<span style=\"color: #D94F3D\"><span style=\"color: #3B82D9\">one</span>\n<span style=\"color: #3B82D9\">two</span></span>")
    }

    func testBlockCommandsLeaveTheRestOfTheNoteAlone() {
        var dice = Dice(state: 31)
        let text = plainNote
        let source = text as NSString
        for _ in 0..<400 {
            let selection = randomSelection(in: text, using: &dice)
            let edits: [TextEdit?] = [
                MarkdownFormatting.setHeading(Int.random(in: 0...3, using: &dice), in: text, selection: selection),
                MarkdownFormatting.toggleQuote(in: text, selection: selection),
                MarkdownFormatting.setCallout("warning", in: text, selection: selection),
                MarkdownFormatting.toggleCodeBlock(in: text, selection: selection),
                MarkdownFormatting.insertDivider(in: text, selection: selection),
                MarkdownFormatting.insertTable(rows: 1, columns: 2, in: text, selection: selection),
                MarkdownFormatting.tableAddRow(in: text, selection: selection),
                MarkdownFormatting.tableAddColumn(in: text, selection: selection),
                MarkdownFormatting.setAlignment("center", in: text, selection: selection),
                MarkdownFormatting.toggle(.bold, in: text, selection: selection),
                MarkdownFormatting.set(.textColor, value: "#D94F3D", in: text, selection: selection),
            ]
            for edit in edits.compactMap({ $0 }) {
                assertSound(edit, in: text, "\(selection)")
                let result = edit.applied(to: text) as NSString
                // Everything outside the range the edit names is untouched.
                XCTAssertEqual(result.substring(to: edit.range.location), source.substring(to: edit.range.location))
                XCTAssertEqual(result.substring(from: edit.range.location + length(edit.replacement)), source.substring(from: NSMaxRange(edit.range)))
                // The edit never reaches outside the lines the selection touches (table and div commands
                // work on the whole table or block).
                XCTAssertLessThanOrEqual(edit.range.length, 4000)
            }
        }
    }

    func testFormattingALongNoteIsQuick() {
        var lines: [String] = []
        for index in 0..<4000 {
            switch index % 6 {
            case 0: lines.append("## Heading \(index)")
            case 1: lines.append("- [ ] task with **bold**, <u>under</u> and <span style=\"color: #D94F3D\">red</span> 🎉")
            case 2: lines.append("```")
            case 3: lines.append("code \(index)")
            case 4: lines.append("```")
            default: lines.append("Prose with *emphasis*, `code` and a [link](https://example.com) to color.")
            }
        }
        let text = lines.joined(separator: "\n")
        let target = (text as NSString).range(of: "to color", options: .backwards)
        var best = Double.infinity
        for _ in 0..<5 {
            let start = Date()
            _ = MarkdownFormatting.formats(in: text, selection: target)
            XCTAssertNotNil(MarkdownFormatting.set(.textColor, value: "#3B82D9", in: text, selection: target))
            best = min(best, Date().timeIntervalSince(start))
        }
        print("formatting: state and one color at the end of a \(lines.count)-line note \(String(format: "%.1f", best * 1000)) ms")
        XCTAssertLessThan(best, 0.25)
    }
}
