import XCTest
@testable import PerchKit

/// A small repeatable random source, so a failure can be run again from its seed.
private struct Seeded: RandomNumberGenerator {
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

/// A made-up note, with the pieces of it no formatting command may ever change.
private struct RandomNote {
    var text = ""
    /// Code, addresses, link targets, image paths, frontmatter and raw HTML, in the order they appear.
    var protected: [String] = []
    /// True when the note was made with formatting already in it.
    var rich = false
}

/// Builds notes out of every kind of block and inline piece Perch knows, well-formed and otherwise.
private struct NoteMaker {
    var dice: Seeded
    var note = RandomNote()
    var eol = "\n"
    /// Whether to put existing formatting (and broken formatting) in.
    var rich: Bool

    init(seed: UInt64, rich: Bool) {
        dice = Seeded(state: seed)
        self.rich = rich
        note.rich = rich
        if Int.random(in: 0..<4, using: &dice) == 0 { eol = "\r\n" }
    }

    private static let words = [
        "coast", "road", "ferry", "café", "naïve", "e\u{301}cole", "👩‍👩‍👧", "🎉", "日本語", "x", "it's", "(aside)", "end.", "\"quoted\"",
        "A&B", "50%", "well-known", "a,b;c", "snake", "über", "🇨🇦", "1️⃣", "what?", "yes!", "[sic]", "#tag", "@name", "$5", "one/two",
        "non\u{A0}breaking", "thin\u{2009}space", "…", "—",
    ]
    /// Characters that Markdown reads as marks when they pair up. Only notes that already have formatting get them.
    private static let lonely = ["2 * 3", "a_b", "~approx", "a=b", "x^2", "5 < 6", "a > b", "* star", "tilde ~ here", "= equals", "under_score_d"]
    private static let colors = ["#D94F3D", "#3B82D9", "#3F9B5B", "#A855C7"]

    private mutating func roll(_ upper: Int) -> Int { Int.random(in: 0..<upper, using: &dice) }
    private mutating func pick(_ list: [String]) -> String { list[roll(list.count)] }

    private mutating func words(_ range: ClosedRange<Int> = 1...4) -> String {
        (0..<Int.random(in: range, using: &dice)).map { _ in pick(Self.words) }.joined(separator: " ")
    }

    private mutating func keep(_ piece: String) -> String {
        note.protected.append(piece)
        return piece
    }

    /// The words of one line: plain words with code, links and (in a rich note) formatting among them.
    mutating func inline(_ pieces: ClosedRange<Int> = 1...5, table: Bool = false) -> String {
        var parts: [String] = []
        for _ in 0..<Int.random(in: pieces, using: &dice) {
            switch roll(rich ? 30 : 13) {
            case 0...5: parts.append(words())
            case 6: parts.append(keep("`let a = **b** <u>c</u> ~d~`"))
            case 7: parts.append("[" + words(1...2) + "](" + keep("https://example.com/a_b*c?q=1~2&r==3^4") + ")")
            case 8: parts.append(keep("https://example.org/path_with_under*star"))
            case 9: parts.append(keep(table ? "[[Note Name]]" : "[[Note_Name*|shown ~label~]]"))
            case 10: parts.append(keep("![alt *text*](images/pic_one*two.png)"))
            case 11: parts.append(words() + keep("[^1]"))
            case 12: parts.append(words(3...8))
            case 13: parts.append("**" + words(1...2) + "**")
            case 14: parts.append("*" + words(1...2) + "*")
            case 15: parts.append("~~" + words(1...2) + "~~")
            case 16: parts.append("==" + words(1...2) + "==")
            case 17: parts.append("<u>" + words(1...2) + "</u>")
            case 18: parts.append("<span style=\"color: \(pick(Self.colors))\">" + words(1...3) + "</span>")
            case 19: parts.append("<mark style=\"background-color: \(pick(Self.colors))\">" + words(1...2) + "</mark>")
            case 20: parts.append("<span style=\"font-size: \(pick(FormatPalette.sizes))\">" + words(1...2) + "</span>")
            case 21: parts.append("H~2~O and x^2^")
            case 22: parts.append(keep("<font color=\"red\">") + words(1...2) + keep("</font>"))
            case 23: parts.append(keep("<span style=\"color: red; font-weight: bold\" class=\"x\">") + words(1...2) + "</span>")
            case 24: parts.append(words(1...2) + keep("<br>") + words(1...2))
            case 25: parts.append(keep("<!-- a <u>comment</u> **here** -->"))
            case 26: parts.append(pick(Self.lonely))
            case 27: parts.append(pick(["</span>", "<u>", "**", "<mark>", "</u>", "==", "~~", "<span style=\"color:"]) + " " + words(1...2))
            case 28: parts.append("***" + words(1...2) + "*** __" + words(1...1) + "__ _" + words(1...1) + "_")
            default: parts.append("<u>**" + words(1...2) + "**</u> <span style=\"color: #D94F3D\"><u>" + words(1...2) + "</u></span>")
            }
        }
        return parts.joined(separator: " ")
    }

    mutating func block() -> [String] {
        switch roll(17) {
        case 0, 1, 2:
            return (0..<Int.random(in: 1...3, using: &dice)).map { _ in inline() }
        case 3:
            return [String(repeating: "#", count: Int.random(in: 1...4, using: &dice)) + " " + inline(1...3)]
        case 4, 5:
            var lines: [String] = []
            for index in 0..<Int.random(in: 1...4, using: &dice) {
                let indent = String(repeating: "  ", count: roll(3))
                let marker = ["- ", "* ", "\(index + 1). ", "- [ ] ", "- [x] ", "+ "][roll(6)]
                lines.append(indent + marker + (roll(8) == 0 ? "" : inline(1...3)))
            }
            return lines
        case 6:
            return (0..<Int.random(in: 1...3, using: &dice)).map { _ in "> " + inline(1...3) }
        case 7:
            return ["> [!" + pick(["note", "tip", "warning"]) + "] " + words(1...2), "> " + inline(1...3), ">", "> - " + inline(1...2)]
        case 8:
            let columns = Int.random(in: 1...3, using: &dice)
            var lines = ["| " + (0..<columns).map { _ in words(1...2) }.joined(separator: " | ") + " |"]
            lines.append(keep("|" + String(repeating: " --- |", count: columns)))
            for _ in 0..<Int.random(in: 1...3, using: &dice) {
                var cells: [String] = []
                for _ in 0..<columns { cells.append(roll(5) == 0 ? "" : inline(1...2, table: true)) }
                lines.append("| " + cells.joined(separator: " | ") + (roll(6) == 0 ? "" : " |"))
            }
            return lines
        case 9:
            let fence = pick(["```", "~~~", "````"])
            return [fence + pick(["", "swift", "js"]), keep("let x = \"**not bold** <u>no</u>\""), "", keep("  indented *code* ==here=="), fence]
        case 10:
            // Indented code: after a blank line, and not under a list.
            return ["Lead paragraph " + words(1...2) + ".", "", keep("    indented **code** <u>line</u>"), keep("\tsecond ~line~ of it")]
        case 11:
            return ["$$", keep("x^2 + y_1 * z ~ w"), "$$"]
        case 12:
            return pick(["center", "right"]) == "center"
                ? ["<div align=\"center\">", "", inline(1...3), "", "</div>"]
                : ["<div align=\"right\">", "", inline(1...2), inline(1...2), "", "</div>"]
        case 13:
            return [keep("<details>"), keep("<summary>Raw *summary* text</summary>"), keep("inside a **raw** block <b>x</b>"), keep("</details>")]
        case 14:
            return [keep("<table><tr><td>cell *one*</td><td>==two==</td></tr></table>")]
        case 15:
            return ["[^1]: " + inline(1...2)]
        default:
            return [pick(["---", "***", "<!-- a whole-line comment -->"])]
        }
    }

    mutating func make() -> RandomNote {
        var lines: [String] = []
        if roll(4) == 0 {
            lines += ["---", "title: A *starred* title <u>x</u>", "tags: [a_b, c~d]", "---"].map { keep($0) }
        }
        for _ in 0..<Int.random(in: 1...7, using: &dice) {
            if !lines.isEmpty { lines.append("") }
            lines += block()
        }
        if roll(3) == 0 { lines.append("") }
        note.text = lines.joined(separator: eol)
        return note
    }
}

/// Text integrity for the formatting commands, checked on thousands of made-up notes and selections.
/// What is asserted here is the contract with the user's files: a command changes its own marks and
/// nothing else.
final class FormattingFuzzTests: XCTestCase {
    private func length(_ text: String) -> Int { (text as NSString).length }

    /// A fifth of the notes on an ordinary run, which takes about half a minute. `PERCH_FUZZ=full swift test
    /// --filter FormattingFuzzTests` runs them all; any other number multiplies the full count.
    private static func rounds(_ full: UInt64) -> UInt64 {
        switch ProcessInfo.processInfo.environment["PERCH_FUZZ"] {
        case "full": return full
        case let value?: return full * (UInt64(value) ?? 1)
        case nil: return full / 5
        }
    }

    private static let formats: [(InlineFormat, String)] = [
        (.underline, ""), (.textColor, "#D94F3D"), (.highlight, "#3B82D9"), (.textSize, "1.3em"),
        (.bold, ""), (.italic, ""), (.strikethrough, ""), (.highlight, ""), (.subscript, ""), (.superscript, ""),
    ]

    /// A selection anywhere in the note. Half the time at least one end is beside a mark, a tag, a pipe
    /// or a line end, where the hard cases are.
    private func selection(in text: String, using dice: inout Seeded) -> NSRange {
        let source = text as NSString
        guard source.length > 0 else { return NSRange(location: 0, length: 0) }
        func near() -> Int {
            let start = Int.random(in: 0..<source.length, using: &dice)
            for offset in 0..<60 where start + offset < source.length {
                let character = source.character(at: start + offset)
                if [0x3C, 0x3E, 0x2A, 0x7E, 0x3D, 0x5E, 0x7C, 0x0A, 0x60, 0x5B, 0x5D, 0x28, 0x29].contains(Int(character)) {
                    return min(max(start + offset + Int.random(in: -2...3, using: &dice), 0), source.length)
                }
            }
            return start
        }
        func whole(_ index: Int) -> Int {
            index < source.length ? source.rangeOfComposedCharacterSequence(at: index).location : index
        }
        var start = whole(Bool.random(using: &dice) ? near() : Int.random(in: 0...source.length, using: &dice))
        var end: Int
        switch Int.random(in: 0..<6, using: &dice) {
        case 0, 1: end = start
        case 2: end = whole(near())
        default: end = whole(min(source.length, start + [1, 2, 4, 9, 25, 80, 300].randomElement(using: &dice)!))
        }
        if end < start { swap(&start, &end) }
        return NSRange(location: start, length: end - start)
    }

    /// (d) The edit and the selection it hands back are real ranges that never split a character.
    private func assertSound(_ edit: TextEdit, in text: String, _ label: @autoclosure () -> String, file: StaticString = #filePath, line: UInt = #line) -> String? {
        guard edit.range.location >= 0, NSMaxRange(edit.range) <= length(text) else {
            XCTFail("edit range \(edit.range) outside the note: \(label())", file: file, line: line)
            return nil
        }
        let result = edit.applied(to: text)
        let source = result as NSString
        guard edit.selection.location >= 0, edit.selection.length >= 0, NSMaxRange(edit.selection) <= source.length else {
            XCTFail("selection \(edit.selection) outside the new note: \(label())", file: file, line: line)
            return nil
        }
        for index in [edit.selection.location, NSMaxRange(edit.selection)] where index < source.length && index > 0 {
            if UTF16.isTrailSurrogate(source.character(at: index)), UTF16.isLeadSurrogate(source.character(at: index - 1)) {
                XCTFail("selection splits a character: \(label())", file: file, line: line)
            }
        }
        if String(decoding: Array(result.utf16), as: UTF16.self) != result {
            XCTFail("broken UTF-16: \(label())", file: file, line: line)
        }
        return result
    }

    /// The tags and marks a format writes, as a pattern.
    private func marks(of format: InlineFormat) -> String {
        switch format {
        case .bold, .italic: return #"[*_]"#
        case .strikethrough, .subscript: return #"~"#
        case .superscript: return #"\^"#
        case .underline: return #"</?u>"#
        case .highlight: return #"</?mark\b[^<>\n]*>|="#
        case .textColor, .textSize: return #"</?span\b[^<>\n]*>"#
        }
    }

    private func strip(_ text: String, _ pattern: String) -> String {
        text.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
    }

    /// (a) Only this format's own marks were added or taken away.
    private func assertOnlyMarksChanged(_ old: String, _ new: String, format: InlineFormat?, _ label: @autoclosure () -> String, file: StaticString = #filePath, line: UInt = #line) {
        let pattern = format.map { marks(of: $0) } ?? #"</?(span|mark|u)\b[^<>\n]*>|[*_~=^]"#
        if strip(old, pattern) != strip(new, pattern) {
            XCTFail("words changed: \(label())\n\(new.debugDescription)", file: file, line: line)
        }
    }

    /// (c) Code, addresses, link targets, frontmatter and raw HTML are all still there, whole and in order.
    private func assertProtected(_ note: RandomNote, in new: String, _ label: @autoclosure () -> String, file: StaticString = #filePath, line: UInt = #line) {
        var rest = new[...]
        for piece in note.protected {
            guard let found = rest.range(of: piece) else {
                XCTFail("changed \(piece.debugDescription): \(label())\n\(new.debugDescription)", file: file, line: line)
                return
            }
            rest = rest[found.upperBound...]
        }
    }

    private static let contract = try! NSRegularExpression(pattern: [
        #"<u>"#, #"</u>"#, #"</span>"#, #"</mark>"#,
        ##"<span style="color: #[0-9A-F]{6}">"##,
        ##"<mark style="background-color: #[0-9A-F]{6}">"##,
        #"<span style="font-size: (0\.85|1\.15|1\.3|1\.6)em">"#,
    ].map { "^(?:" + $0 + ")$" }.joined(separator: "|"))
    private static let anyTag = try! NSRegularExpression(pattern: #"</?[A-Za-z][^<>\n]*>"#)

    private func tags(_ text: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        let source = text as NSString
        for match in Self.anyTag.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            counts[source.substring(with: match.range), default: 0] += 1
        }
        return counts
    }

    /// (f) Every tag that wasn't in the note before is one of the agreed ones, written exactly.
    private func assertContract(_ old: String, _ new: String, _ label: @autoclosure () -> String, file: StaticString = #filePath, line: UInt = #line) {
        let before = tags(old)
        for (tag, count) in tags(new) where count > before[tag, default: 0] {
            if Self.contract.firstMatch(in: tag, range: NSRange(location: 0, length: length(tag))) == nil {
                XCTFail("wrote \(tag.debugDescription): \(label())", file: file, line: line)
            }
        }
    }

    /// The spans of one format in a note, as the commands see them.
    private func pairs(of format: InlineFormat, in text: String) -> [InlinePair] {
        let source = text as NSString
        var found: [InlinePair] = []
        for row in MarkdownFormatting.lines(source, through: source.length) where row.isText {
            for segment in MarkdownFormatting.segments(source, line: row) {
                found += InlineScanner.scan(source, source: text, range: segment).pairs.filter { $0.format == format }
            }
        }
        return found
    }

    private func assertNoNesting(_ text: String, format: InlineFormat, _ label: @autoclosure () -> String, file: StaticString = #filePath, line: UInt = #line) {
        let all = pairs(of: format, in: text)
        for pair in all {
            if all.contains(where: { $0 != pair && $0.outer.location <= pair.outer.location && NSMaxRange($0.outer) >= NSMaxRange(pair.outer) }) {
                XCTFail("nested \(format): \(label())\n\(text.debugDescription)", file: file, line: line)
                return
            }
        }
    }

    private func describe(_ note: RandomNote, _ selection: NSRange, seed: UInt64) -> String {
        "seed \(seed) at \(selection) \((note.text as NSString).substring(with: selection).debugDescription) in \(note.text.debugDescription)"
    }

    // MARK: Inline commands

    func testInlineCommandsChangeOnlyTheirOwnMarks() {
        var edits = 0
        for seed in 1...Self.rounds(700) as ClosedRange<UInt64> {
            var maker = NoteMaker(seed: seed, rich: seed % 2 == 0)
            let note = maker.make()
            var dice = Seeded(state: seed &* 977)
            for _ in 0..<14 {
                let selection = selection(in: note.text, using: &dice)
                let label = { self.describe(note, selection, seed: seed) }
                for (format, value) in Self.formats {
                    let commands: [(String, TextEdit?)] = [
                        ("toggle", MarkdownFormatting.toggle(format, value: value, in: note.text, selection: selection)),
                        ("set", MarkdownFormatting.set(format, value: value, in: note.text, selection: selection)),
                        ("remove", MarkdownFormatting.set(format, value: nil, in: note.text, selection: selection)),
                    ]
                    for (name, edit) in commands {
                        guard let edit, let result = assertSound(edit, in: note.text, "\(name) \(format) \(label())") else { continue }
                        XCTAssertNotEqual(result, note.text, "an edit that changes nothing: \(name) \(format) \(label())")
                        assertOnlyMarksChanged(note.text, result, format: format, "\(name) \(format) \(label())")
                        assertProtected(note, in: result, "\(name) \(format) \(label())")
                        assertContract(note.text, result, "\(name) \(format) \(label())")
                        edits += 1
                    }
                }
                let others: [(String, TextEdit?)] = [
                    ("clear", MarkdownFormatting.clearFormatting(in: note.text, selection: selection)),
                    ("larger", MarkdownFormatting.stepSize(1, in: note.text, selection: selection)),
                    ("smaller", MarkdownFormatting.stepSize(-1, in: note.text, selection: selection)),
                ]
                for (name, edit) in others {
                    guard let edit, let result = assertSound(edit, in: note.text, "\(name) \(label())") else { continue }
                    assertOnlyMarksChanged(note.text, result, format: nil, "\(name) \(label())")
                    assertProtected(note, in: result, "\(name) \(label())")
                    assertContract(note.text, result, "\(name) \(label())")
                }
                if let edit = MarkdownFormatting.toggleCode(in: note.text, selection: selection), let result = assertSound(edit, in: note.text, "code \(label())") {
                    XCTAssertEqual(strip(result, "`"), strip(note.text, "`"), "code \(label())")
                }
                _ = MarkdownFormatting.formats(in: note.text, selection: selection)
            }
        }
        XCTAssertGreaterThan(edits, 8_000)
    }

    /// (b) In a note with no formatting of its own, putting a format on and taking it off again gives
    /// back the note, byte for byte. Whatever a command writes, the same command can find again.
    func testEveryFormatComesOffAgainExactly() {
        var applied = 0, refused = 0
        for seed in 1...Self.rounds(600) as ClosedRange<UInt64> {
            var maker = NoteMaker(seed: seed &+ 5000, rich: false)
            let note = maker.make()
            var dice = Seeded(state: seed &* 31)
            for _ in 0..<14 {
                let selection = selection(in: note.text, using: &dice)
                let label = { self.describe(note, selection, seed: seed) }
                for (format, value) in Self.formats {
                    guard let on = MarkdownFormatting.toggle(format, value: value, in: note.text, selection: selection) else {
                        refused += 1
                        continue
                    }
                    guard let formatted = assertSound(on, in: note.text, "\(format) \(label())") else { continue }
                    // What was written reads as the format, so the bar lights up and the next press takes it off.
                    if on.range.length > 0 || selection.length > 0 {
                        XCTAssertTrue(MarkdownFormatting.formats(in: formatted, selection: on.selection).isOn(format), "wrote \(format) that doesn't read as \(format): \(label())\n\(formatted.debugDescription)")
                    }
                    guard let off = MarkdownFormatting.toggle(format, value: value, in: formatted, selection: on.selection) else {
                        XCTFail("couldn't take \(format) off: \(label())\n\(formatted.debugDescription)")
                        continue
                    }
                    XCTAssertEqual(off.applied(to: formatted), note.text, "\(format) \(label())")
                    if format == .textColor || format == .highlight && !value.isEmpty || format == .textSize || format == .underline {
                        let removed = MarkdownFormatting.set(format, value: nil, in: formatted, selection: on.selection)
                        XCTAssertEqual(removed?.applied(to: formatted), note.text, "set nil \(format) \(label())")
                    }
                    applied += 1
                }
            }
        }
        XCTAssertGreaterThan(applied, 6_000)
        print("formatting fuzz: \(applied) formats put on and taken off again, \(refused) requests with nothing to format")
    }

    /// (e) A second, third and fifth color over the same words replaces the first: nothing nests, nothing
    /// is left empty, and the note doesn't grow.
    func testRepeatedColorsNeverPileUp() {
        let colors = ["#D94F3D", "#3B82D9", "#3F9B5B", "#A855C7", "#1F9E96"]
        var rounds = 0
        for seed in 1...Self.rounds(500) as ClosedRange<UInt64> {
            var maker = NoteMaker(seed: seed &+ 9000, rich: seed % 2 == 0)
            let note = maker.make()
            var dice = Seeded(state: seed &* 131)
            for _ in 0..<8 {
                let start = selection(in: note.text, using: &dice)
                for format in [InlineFormat.textColor, .highlight] {
                    var text = note.text
                    var selection = start
                    var sizes: [Int] = []
                    let emptyBefore = pairs(of: format, in: text).filter { $0.inner.length == 0 }.count
                    for (round, color) in colors.enumerated() {
                        guard let edit = MarkdownFormatting.set(format, value: color, in: text, selection: selection) else { break }
                        let label = "\(format) round \(round) \(describe(note, start, seed: seed))"
                        guard let result = assertSound(edit, in: text, label) else { break }
                        assertOnlyMarksChanged(text, result, format: format, label)
                        assertProtected(note, in: result, label)
                        assertContract(text, result, label)
                        assertNoNesting(result, format: format, label)
                        if start.length > 0 {
                            XCTAssertLessThanOrEqual(pairs(of: format, in: result).filter { $0.inner.length == 0 }.count, emptyBefore, "empty span: \(label)")
                        }
                        // The same color again has nothing left to do.
                        if start.length > 0, let again = MarkdownFormatting.set(format, value: color, in: result, selection: edit.selection) {
                            XCTAssertEqual(again.applied(to: result), result, "same color twice: \(label)")
                        }
                        text = result
                        selection = edit.selection
                        sizes.append(length(text))
                        rounds += 1
                    }
                    // Where there was no color to merge with or split, every round is the same length as the first.
                    if !note.rich, let first = sizes.first { XCTAssertTrue(sizes.allSatisfy { $0 == first }, "grew: \(sizes) \(describe(note, start, seed: seed))") }
                }
            }
        }
        XCTAssertGreaterThan(rounds, 2_000)
    }

    // MARK: Block commands

    func testBlockCommandsKeepEveryWordAndStayOutOfCode() {
        var edits = 0
        for seed in 1...Self.rounds(500) as ClosedRange<UInt64> {
            var maker = NoteMaker(seed: seed &+ 20_000, rich: seed % 2 == 0)
            let note = maker.make()
            var dice = Seeded(state: seed &* 613)
            let source = note.text as NSString
            for _ in 0..<12 {
                let selection = selection(in: note.text, using: &dice)
                let label = { self.describe(note, selection, seed: seed) }
                let commands: [(String, TextEdit?)] = [
                    ("heading", MarkdownFormatting.setHeading(Int.random(in: 0...3, using: &dice), in: note.text, selection: selection)),
                    ("quote", MarkdownFormatting.toggleQuote(in: note.text, selection: selection)),
                    ("callout", MarkdownFormatting.setCallout("warning", in: note.text, selection: selection)),
                    ("no callout", MarkdownFormatting.setCallout(nil, in: note.text, selection: selection)),
                    ("divider", MarkdownFormatting.insertDivider(in: note.text, selection: selection)),
                    ("table", MarkdownFormatting.insertTable(rows: 2, columns: 2, in: note.text, selection: selection)),
                    ("row", MarkdownFormatting.tableAddRow(in: note.text, selection: selection)),
                    ("column", MarkdownFormatting.tableAddColumn(in: note.text, selection: selection)),
                    ("tidy table", MarkdownFormatting.tidyTable(in: note.text, selection: selection)),
                    ("next cell", MarkdownFormatting.tableMove(forward: true, in: note.text, selection: selection)),
                    ("last cell", MarkdownFormatting.tableMove(forward: false, in: note.text, selection: selection)),
                    ("center", MarkdownFormatting.setAlignment("center", in: note.text, selection: selection)),
                    ("right", MarkdownFormatting.setAlignment("right", in: note.text, selection: selection)),
                    ("left", MarkdownFormatting.setAlignment(nil, in: note.text, selection: selection)),
                    ("code block", MarkdownFormatting.toggleCodeBlock(language: "swift", in: note.text, selection: selection)),
                ]
                for (name, edit) in commands {
                    guard let edit, let result = assertSound(edit, in: note.text, "\(name) \(label())") else { continue }
                    let new = result as NSString
                    // Everything outside the range the edit names is untouched.
                    XCTAssertEqual(new.substring(to: edit.range.location), source.substring(to: edit.range.location), "\(name) \(label())")
                    XCTAssertEqual(new.substring(from: edit.range.location + length(edit.replacement)), source.substring(from: NSMaxRange(edit.range)), "\(name) \(label())")
                    // The table's rule row grows with a new column; nothing else protected ever changes.
                    if name != "column", name != "tidy table" { assertProtected(note, in: result, "\(name) \(label())") }
                    // Tidying only moves spaces, resizes rule rows and adds empty cells to short rows: line by line,
                    // with spaces and dashes taken out, each row is what it was plus at most some closing pipes.
                    if name == "tidy table" {
                        let squeeze = { (line: Substring) in line.filter { $0 != " " && $0 != "-" } }
                        let before = source.substring(with: edit.range).split(separator: "\n", omittingEmptySubsequences: false)
                        let after = edit.replacement.split(separator: "\n", omittingEmptySubsequences: false)
                        XCTAssertEqual(before.count, after.count, "tidy table kept its rows: \(label())")
                        for (old, new) in zip(before, after) {
                            let was = squeeze(old), now = squeeze(new)
                            XCTAssertTrue(now.hasPrefix(was) && now.dropFirst(was.count).allSatisfy { $0 == "|" },
                                          "tidy table only padded \(old.debugDescription) to \(new.debugDescription): \(label())")
                        }
                    }
                    // No word is lost: every run of letters in the note is still there, in order.
                    var rest = result[...]
                    // (Taking a callout or an alignment away takes its own tag with it.)
                    let own: Set<String> = ["div", "align", "center", "right", "note", "tip", "warning", "swift"]
                    for word in note.text.components(separatedBy: CharacterSet.alphanumerics.inverted) where word.count > 2 && !own.contains(word) {
                        guard let found = rest.range(of: word) else {
                            XCTFail("lost \(word.debugDescription): \(name) \(label())\n\(result.debugDescription)")
                            break
                        }
                        rest = rest[found.upperBound...]
                    }
                    // Line endings stay the note's own.
                    if note.text.contains("\r\n") {
                        XCTAssertFalse(result.replacingOccurrences(of: "\r\n", with: "").contains("\n"), "bare line feed in a Windows note: \(name) \(label())")
                    } else {
                        XCTAssertFalse(result.contains("\r"), "\(name) \(label())")
                    }
                    edits += 1
                }
            }
        }
        XCTAssertGreaterThan(edits, 3_000)
    }

    func testAlignmentWritesTheAgreedBlockAndComesOffExactly() {
        var applied = 0
        for seed in 1...Self.rounds(300) as ClosedRange<UInt64> {
            var maker = NoteMaker(seed: seed &+ 30_000, rich: false)
            let note = maker.make()
            guard !note.text.contains("<div") else { continue }
            var dice = Seeded(state: seed &* 211)
            for _ in 0..<8 {
                let selection = selection(in: note.text, using: &dice)
                for alignment in ["center", "right"] {
                    guard let on = MarkdownFormatting.setAlignment(alignment, in: note.text, selection: selection),
                          let aligned = assertSound(on, in: note.text, describe(note, selection, seed: seed)) else { continue }
                    let eol = note.text.contains("\r\n") ? "\r\n" : "\n"
                    XCTAssertTrue(on.replacement.hasPrefix("<div align=\"\(alignment)\">\(eol)\(eol)"), describe(note, selection, seed: seed))
                    XCTAssertTrue(on.replacement.hasSuffix("\(eol)\(eol)</div>") || on.replacement.hasSuffix("\(eol)\(eol)</div>\(eol)"), describe(note, selection, seed: seed))
                    guard let off = MarkdownFormatting.setAlignment(nil, in: aligned, selection: on.selection) else {
                        XCTFail("couldn't take alignment off: \(describe(note, selection, seed: seed))")
                        continue
                    }
                    let back = off.applied(to: aligned)
                    // The blank line left under `</div>` (so the next paragraph still reads as Markdown) may stay.
                    XCTAssertTrue(back == note.text || back.replacingOccurrences(of: eol + eol + eol, with: eol + eol) == note.text
                        || back.replacingOccurrences(of: eol + eol, with: eol) == note.text.replacingOccurrences(of: eol + eol, with: eol),
                        "alignment round trip: \(describe(note, selection, seed: seed))\n\(back.debugDescription)")
                    applied += 1
                }
            }
        }
        XCTAssertGreaterThan(applied, 300)
    }
}
