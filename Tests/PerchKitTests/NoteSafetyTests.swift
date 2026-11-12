import XCTest
@testable import PerchKit
@testable import PerchUI

#if canImport(AppKit)
import AppKit
#endif

/// Checks that the editor's helpers change only what they say they change, and that opening a note,
/// in the reader or the editor, never writes to its file.
final class NoteEditingSafetyTests: XCTestCase {
    private func caret(_ location: Int) -> NSRange { NSRange(location: location, length: 0) }
    private func length(_ text: String) -> Int { (text as NSString).length }

    // MARK: Task boxes

    func testTickingATaskChangesOneCharacter() throws {
        let text = "# List\n- [ ] one\n- [x] two [ ] not a box\n  1. [X] three\n> - [ ] quoted\nplain [ ] text\n- [ ]"
        var edit = try XCTUnwrap(MarkdownEditing.setTaskBox(in: text, line: 1))
        XCTAssertEqual(edit.range.length, 1)
        XCTAssertEqual(edit.applied(to: text), text.replacingOccurrences(of: "- [ ] one", with: "- [x] one"))

        // The box at the start of the item is the one that changes, not a later `[ ]` on the same line.
        edit = try XCTUnwrap(MarkdownEditing.setTaskBox(in: text, line: 2))
        XCTAssertEqual(edit.applied(to: text), text.replacingOccurrences(of: "- [x] two", with: "- [ ] two"))

        edit = try XCTUnwrap(MarkdownEditing.setTaskBox(in: text, line: 3))
        XCTAssertEqual(edit.applied(to: text), text.replacingOccurrences(of: "[X] three", with: "[ ] three"))
        edit = try XCTUnwrap(MarkdownEditing.setTaskBox(in: text, line: 4))
        XCTAssertEqual(edit.applied(to: text), text.replacingOccurrences(of: "> - [ ] quoted", with: "> - [x] quoted"))
        edit = try XCTUnwrap(MarkdownEditing.setTaskBox(in: text, line: 6))
        XCTAssertEqual(edit.applied(to: text), String(text.dropLast(3)) + "[x]")

        // Not tasks, or not there at all.
        XCTAssertNil(MarkdownEditing.setTaskBox(in: text, line: 0))
        XCTAssertNil(MarkdownEditing.setTaskBox(in: text, line: 5))
        XCTAssertNil(MarkdownEditing.setTaskBox(in: text, line: 7))
        XCTAssertNil(MarkdownEditing.setTaskBox(in: text, line: -1))
        XCTAssertNil(MarkdownEditing.setTaskBox(in: "", line: 0))
        // Asking for the state it already has changes nothing.
        XCTAssertNil(MarkdownEditing.setTaskBox(in: text, line: 1, checked: false))
        XCTAssertNil(MarkdownEditing.setTaskBox(in: text, line: 2, checked: true))
        XCTAssertNotNil(MarkdownEditing.setTaskBox(in: text, line: 1, checked: true))
    }

    func testTickingKeepsWindowsLineEndingsAndEmoji() throws {
        let text = "---\r\ntitle: 👩‍👩‍👧 café\r\n---\r\n- [ ] 🎉 first\r\n- [ ] second\r\n"
        let edit = try XCTUnwrap(MarkdownEditing.setTaskBox(in: text, line: 4))
        let result = edit.applied(to: text)
        XCTAssertEqual(result, "---\r\ntitle: 👩‍👩‍👧 café\r\n---\r\n- [ ] 🎉 first\r\n- [x] second\r\n")
        XCTAssertEqual(Array(result.utf16).count, Array(text.utf16).count)
        // An old Mac file, with bare carriage returns, counts lines the way the reader does.
        let old = "a\r- [ ] b\r- [ ] c"
        XCTAssertEqual(try XCTUnwrap(MarkdownEditing.setTaskBox(in: old, line: 2)).applied(to: old), "a\r- [ ] b\r- [x] c")
    }

    // MARK: Return and numbering

    func testReturnRenumbersTheItemsBelow() throws {
        let text = "1. one\n2. two\n   nested text\n   - child\n3. three\n\n4. after a gap\n"
        let edit = try XCTUnwrap(MarkdownEditing.newline(in: text, selection: caret(6)))
        XCTAssertEqual(edit.applied(to: text), "1. one\n2. \n3. two\n   nested text\n   - child\n4. three\n\n4. after a gap\n")
        XCTAssertEqual(edit.selection, caret(10))

        // Numbers that don't follow on are someone's choice: leave them.
        let lazy = "1. one\n1. two\n1. three"
        XCTAssertEqual(try XCTUnwrap(MarkdownEditing.newline(in: lazy, selection: caret(6))).applied(to: lazy), "1. one\n2. \n1. two\n1. three")
        // A different list style below is another list.
        let mixed = "1. one\n2) two"
        XCTAssertEqual(try XCTUnwrap(MarkdownEditing.newline(in: mixed, selection: caret(6))).applied(to: mixed), "1. one\n2. \n2) two")
        // 9 becoming 10 grows the text by a character.
        let nine = "8. a\n9. b\n10. c"
        XCTAssertEqual(try XCTUnwrap(MarkdownEditing.newline(in: nine, selection: caret(4))).applied(to: nine), "8. a\n9. \n10. b\n11. c")
        // Windows line endings below are kept as they are.
        let windows = "1. one\r\n2. two\r\n3. three\r\n"
        XCTAssertEqual(try XCTUnwrap(MarkdownEditing.newline(in: windows, selection: caret(6))).applied(to: windows), "1. one\n2. \r\n3. two\r\n4. three\r\n")
    }

    // MARK: Selections never point past the end

    func testEverySelectionAnEditReturnsIsInsideTheNewText() {
        let samples = [
            "### a", "# Title 🎉", "- [ ] 👩‍👩‍👧 family\n- two\n\n3. three", "plain café text", "> quote\n> more", "\tTabbed\n    spaced\n",
            "a\r\nb\r\n- c\r\n", "", "**bold** and *it*", "e\u{301}a\u{308}\n- x",
        ]
        for text in samples {
            let size = length(text)
            for location in 0...size {
                for extent in [0, 1, 2, size] where location + extent <= size {
                    let selection = NSRange(location: location, length: extent)
                    var edits: [TextEdit] = [
                        MarkdownEditing.cycleHeading(in: text, selection: selection),
                        MarkdownEditing.toggleWrap(in: text, selection: selection, left: "**", right: "**"),
                        MarkdownEditing.toggleWrap(in: text, selection: selection, left: "*", right: "*"),
                        MarkdownEditing.toggleWrap(in: text, selection: selection, left: "`", right: "`"),
                        MarkdownEditing.link(in: text, selection: selection),
                        MarkdownEditing.wikiLink(in: text, selection: selection),
                        MarkdownEditing.toggleList(in: text, selection: selection, kind: .bullet),
                        MarkdownEditing.toggleList(in: text, selection: selection, kind: .numbered),
                        MarkdownEditing.toggleList(in: text, selection: selection, kind: .task),
                    ]
                    edits += [
                        MarkdownEditing.newline(in: text, selection: selection),
                        MarkdownEditing.indent(in: text, selection: selection, outdent: false),
                        MarkdownEditing.indent(in: text, selection: selection, outdent: true),
                        MarkdownEditing.wrapSelection(typing: "*", in: text, selection: selection),
                    ].compactMap { $0 }
                    for edit in edits {
                        XCTAssertLessThanOrEqual(NSMaxRange(edit.range), size, "range in \(text.debugDescription) at \(selection)")
                        let result = edit.applied(to: text)
                        XCTAssertLessThanOrEqual(NSMaxRange(edit.selection), length(result), "selection in \(text.debugDescription) at \(selection)")
                        XCTAssertGreaterThanOrEqual(edit.selection.location, 0)
                    }
                }
            }
        }
    }

    func testHelpersLeaveTheRestOfTheNoteAlone() {
        // Whatever a helper does, the text outside the range it names is untouched, byte for byte.
        let text = "intro 🎉\r\n- [ ] one\r\n- two é\r\n\r\n```\r\n- in code\r\n```\r\ntail\r\n"
        let source = text as NSString
        let selection = NSRange(location: source.range(of: "- [ ] one").location, length: 16)
        let edits = [
            MarkdownEditing.indent(in: text, selection: selection, outdent: false),
            MarkdownEditing.indent(in: text, selection: selection, outdent: true),
            MarkdownEditing.toggleList(in: text, selection: selection, kind: .numbered),
            MarkdownEditing.toggleWrap(in: text, selection: selection, left: "**", right: "**"),
        ].compactMap { $0 }
        XCTAssertEqual(edits.count, 3)
        for edit in edits {
            let result = edit.applied(to: text) as NSString
            XCTAssertEqual(result.substring(to: edit.range.location), source.substring(to: edit.range.location))
            XCTAssertEqual(
                result.substring(from: edit.range.location + length(edit.replacement)), source.substring(from: NSMaxRange(edit.range))
            )
        }
        // Tab over two Windows-ended lines indents both and keeps their endings.
        let indented = MarkdownEditing.indent(in: text, selection: selection, outdent: false)?.applied(to: text)
        XCTAssertEqual(indented, "intro 🎉\r\n    - [ ] one\r\n    - two é\r\n\r\n```\r\n- in code\r\n```\r\ntail\r\n")
    }

    // MARK: The tokenizer on a long note

    func testALongNoteStylesQuickly() {
        var lines: [String] = ["---", "title: Long", "tags: [a, b]", "---"]
        for index in 0..<5000 {
            switch index % 10 {
            case 0: lines.append("## Heading \(index) with `code`")
            case 1: lines.append("- [ ] a task with **bold**, *italic* and [[A Link|label]] 🎉")
            case 2: lines.append("> quoted text with a [link](https://example.com/\(index)) and ==marks==")
            case 3: lines.append("```swift")
            case 4: lines.append("let value\(index) = \"**not bold**\"")
            case 5: lines.append("```")
            case 6: lines.append("| cell | **bold** | `code` |")
            case 7: lines.append("")
            default: lines.append("Plain prose with ~~strike~~, _emphasis_, a footnote[^\(index)] and https://example.com/page.")
            }
        }
        let text = lines.joined(separator: "\n")
        let source = text as NSString

        var best = Double.infinity
        var whole = MarkdownHighlighter.highlight(text)
        for _ in 0..<5 {
            let start = Date()
            whole = MarkdownHighlighter.highlight(text)
            best = min(best, Date().timeIntervalSince(start))
        }
        XCTAssertEqual(whole.lines.count, lines.count)
        print("highlight: \(lines.count) lines, \(source.length) UTF-16 units, whole note \(String(format: "%.1f", best * 1000)) ms")
        // Generous, so a busy machine doesn't fail the test; the real figure is printed above.
        XCTAssertLessThan(best, 0.25)

        // One keystroke restyles one line, given the state the line above ended in.
        let middle = whole.lines[2500]
        var single = Double.infinity
        for _ in 0..<20 {
            let start = Date()
            _ = MarkdownHighlighter.highlight(source, range: middle.range, startState: middle.before)
            single = min(single, Date().timeIntervalSince(start))
        }
        print("highlight: one line of that note \(String(format: "%.3f", single * 1000)) ms")
        XCTAssertLessThan(single, 0.01)
    }

    func testStylingAnyLineAloneMatchesStylingTheWholeNote() {
        // The editor restyles one paragraph at a time; that must agree with doing everything at once.
        let text = "---\ntitle: x\n---\n# H 🎉\n\n```js\nconst a = '*x*'\n```\n\r\n- [x] done **b**\r\n$$\nx^2\n$$\n> [!note] T\n> body `c`\n~~~\n- [ ] no\n~~~\nend\n# <span style=\"color: #D94F3D\">red 🎉</span> <u>u</u>\n- <mark style='background-color:#abc'>m</mark> H~2~O x^2^ <span style=\"font-size: 1.3em\">big\nunclosed </span> `<u>code</u>` <!-- <u>c</u> -->"
        let whole = MarkdownHighlighter.highlight(text)
        for line in whole.lines {
            let part = MarkdownHighlighter.highlight(text as NSString, range: line.range, startState: line.before)
            XCTAssertEqual(part.endState, line.after)
            XCTAssertEqual(part.spans, whole.spans.filter { NSIntersectionRange($0.range, line.range).length > 0 || ($0.range.length == 0 && NSLocationInRange($0.range.location, line.range)) })
        }
        // Spans never reach past the text or split a surrogate pair.
        let source = text as NSString
        for span in whole.spans {
            XCTAssertLessThanOrEqual(NSMaxRange(span.range), source.length)
            if span.range.length > 0 {
                XCTAssertFalse(UTF16.isTrailSurrogate(source.character(at: span.range.location)), "\(span)")
                XCTAssertFalse(UTF16.isLeadSurrogate(source.character(at: NSMaxRange(span.range) - 1)), "\(span)")
            }
        }
    }
}

/// Opens notes the way the app does and checks nothing on disk changes.
@MainActor
final class NoteOpenSafetyTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("perch-open-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func openModel(_ folder: URL) async -> AppModel {
        let model = AppModel(supportDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("perch-support-\(UUID().uuidString)"))
        model.open(root: folder, engine: nil)
        await model.reload(force: true)
        addTeardownBlock { await model.close() }
        return model
    }

    /// Every file under a folder with its bytes and modified date, `.git` aside.
    private func snapshot(_ folder: URL) throws -> [String: (data: Data, modified: Date?)] {
        var result: [String: (Data, Date?)] = [:]
        let base = folder.resolvingSymlinksInPath().path
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey])
        while let url = walker?.nextObject() as? URL {
            let path = String(url.resolvingSymlinksInPath().path.dropFirst(base.count + 1))
            if path == ".git" || path.hasPrefix(".git/") { continue }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values.isRegularFile == true else { continue }
            result[path] = (try Data(contentsOf: url), values.contentModificationDate)
        }
        return result
    }

    /// Opens every note as the reader and then as the editor would, without typing anything.
    /// Returns how many notes were opened and any whose text didn't survive the trip through the editor.
    private func openEverything(in model: AppModel, appearance: EditorAppearance = EditorAppearance()) async throws -> (opened: Int, mangled: [String]) {
        var sessions: [NoteSession] = []
        var mangled: [String] = []
        let styler = MarkdownStyler(appearance: appearance, palette: ThemePresets.perchDark)
        let notes = model.files.filter { $0.kind == .note || $0.kind == .task }
        for file in notes {
            // The reader: load the text, and take the passes the app makes while a note is open.
            let session = NoteSession(path: file.path, model: model)
            sessions.append(session)
            session.refreshFromDisk()
            session.saveNow()
            guard session.isReadable else { continue }

            // The editor: the text goes into text storage, is styled, and is read back out.
            let storage = NSTextStorage(string: session.text)
            styler.restyleAll(storage)
            styler.restyle(storage, edited: NSRange(location: 0, length: min(1, storage.length)))
            // Moving the caret shows and hides formatting tags: styling only, never characters.
            let source = storage.string as NSString
            for location in [0, source.length / 2, source.length] {
                styler.reveal(styler.revealRange(for: NSRange(location: location, length: 0), in: source), in: storage)
            }
            styler.reveal(nil, in: storage)
            if Array(storage.string.utf16) != Array(session.text.utf16) { mangled.append(file.path) }
            // What the editor hands back is what the session compares against before saving.
            session.text = storage.string
            session.saveNow()
        }
        // Longer than the save delay, so a save that was wrongly scheduled would have run by now.
        try await Task.sleep(nanoseconds: 900_000_000)
        await model.reload(force: true)
        sessions.forEach { $0.saveNow() }
        return (notes.count, mangled)
    }

    /// Notes chosen to catch anything that tidies text on the way through: line endings, byte order
    /// marks, odd Unicode, unfinished blocks, and a file that isn't text at all.
    private func writeTrickyNotes() throws -> Int {
        let tricky: [String: Data] = [
            "plain.md": Data("# Title\n\nBody\n".utf8),
            "no-newline.md": Data("no trailing newline".utf8),
            "many-newlines.md": Data("text\n\n\n\n".utf8),
            "windows.md": Data("---\r\ntitle: Win\r\n---\r\n- [ ] one\r\n- [x] two\r\n".utf8),
            "old-mac.md": Data("one\rtwo\rthree".utf8),
            "mixed.md": Data("a\r\nb\nc\rd\n".utf8),
            "bom.md": Data([0xEF, 0xBB, 0xBF]) + Data("# With a byte order mark\n".utf8),
            "decomposed.md": Data("cafe\u{301} and nai\u{308}ve, composed: café\n".utf8),
            "emoji.md": Data("👩‍👩‍👧 🎉 **bold 🎉** `code 🎉`\n".utf8),
            "trailing-space.md": Data("line with two spaces  \n\ttabbed\t\n   \n".utf8),
            "frontmatter-only.md": Data("---\ntags: [a]\n---".utf8),
            "open-fence.md": Data("```\nnever closed\n- [ ] not a task".utf8),
            "conflict.md": Data(":::conflict{variant=a}\nmine\n:::\n:::conflict{variant=d}\ntheirs\n:::\n".utf8),
            "empty.md": Data(),
            "spaces.md": Data("   \n\n".utf8),
            "nul.md": Data("before\u{0}after\n".utf8),
            "separators.md": Data("line\u{2028}separator\u{2029}paragraph\u{85}next\n".utf8),
            "not-utf8.md": Data([0x63, 0x61, 0x66, 0xE9, 0x0A]),
            "Tasks/Task tabc1234.md": Data("---\nperch: task\nid: tabc1234\ntitle: A task\n---\nDetails\n".utf8),
            // Notes that already hold formatting, tidy and otherwise. Opening one must never "fix" it.
            "formatted.md": Data("# <span style=\"color: #D94F3D\">Red</span>\n\n<u>under</u> <mark style=\"background-color: #3B82D9\">blue</mark> <span style=\"font-size: 1.3em\">big</span> ==hi== H~2~O x^2^\n\n<div align=\"center\">\n\nmiddle\n\n</div>\n".utf8),
            "formatted-windows.md": Data("- <span style=\"color: #3F9B5B\">green 🎉</span>\r\n- [ ] <u>task</u>\r\n".utf8),
            "unclosed-span.md": Data("an <span style=\"color: #D94F3D\">unclosed span\n\nnext paragraph <u>also open".utf8),
            "crossing-span.md": Data("<span style=\"color: #D94F3D\">starts here\nand ends</span> on the next line\n\n<u>crossed **bold</u> tags**\n".utf8),
            "upper-case-tags.md": Data("<SPAN STYLE=\"COLOR: #d94f3d\">shouting</SPAN> <U>too</U> <MARK>and this</MARK>\n".utf8),
            "single-quotes.md": Data("<span style='color:#D94F3D'>tight</span> <mark style='background-color: #abc'>short hex</mark>\n".utf8),
            "extra-attributes.md": Data("<span style=\"color: #D94F3D; font-weight: bold\" class=\"x\" id=y data-a>rich</span> <font color=\"red\">old</font> <span style=\"color: red\">named</span>\n".utf8),
            "empty-and-nested.md": Data("<span></span><u></u><mark></mark> <span style=\"color: #D94F3D\"><span style=\"color: #3B82D9\">nested</span></span> <<u>>odd<</u>> <span style=\"color:\n".utf8),
            "open-div.md": Data("<div align=\"center\">\n\nnever closed\n\n</DIV\n".utf8),
        ]
        for (path, data) in tricky {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        return tricky.count
    }

    /// Opens every tricky note and fails if any byte or modified date under the folder is different afterwards.
    private func assertOpeningChangesNothing(appearance: EditorAppearance = EditorAppearance(), _ label: String = "defaults") async throws {
        let count = try writeTrickyNotes()
        let before = try snapshot(root)
        let model = await openModel(root)
        let result = try await openEverything(in: model, appearance: appearance)
        let after = try snapshot(root)

        XCTAssertGreaterThanOrEqual(result.opened, count - 1, label)
        XCTAssertEqual(result.mangled, [], label)
        XCTAssertEqual(Set(before.keys), Set(after.keys), label)
        for (path, old) in before {
            XCTAssertEqual(after[path]?.data, old.data, "\(path) changed on disk (\(label))")
            XCTAssertEqual(after[path]?.modified, old.modified, "\(path) was rewritten (\(label))")
        }
    }

    func testOpeningNotesNeverWritesThem() async throws {
        try await assertOpeningChangesNothing()
    }

    /// The same pass with Display, Reading and Editing settings away from their defaults. Settings live
    /// in UserDefaults and only change how a note is drawn, so no combination may write a note.
    /// The values go in the launch-argument domain, which is never saved, and are taken out again after.
    func testOpeningNotesNeverWritesThemWhateverTheSettings() async throws {
        let combinations: [(label: String, values: [String: Any], appearance: EditorAppearance)] = [
            (
                "large, relaxed, every typing aid on",
                [
                    DisplaySettings.Key.interfaceSize: "extraLarge", DisplaySettings.Key.density: "roomy",
                    ReadingSettings.Key.font: "charter", ReadingSettings.Key.textSize: 3, ReadingSettings.Key.justify: true,
                    ReadingSettings.Key.paragraphSpacing: "relaxed", ReadingSettings.Key.headingFont: "serif",
                    ReadingSettings.Key.codeWrap: "wrap", ReadingSettings.Key.properties: "expanded",
                    ReadingSettings.Key.imageWidth: "full", ReadingSettings.Key.showOutline: true,
                    EditingSettings.Key.font: "reader", EditingSettings.Key.textSize: 4, EditingSettings.Key.lineSpacing: "relaxed",
                    EditingSettings.Key.lineWidth: "full", EditingSettings.Key.marks: "full", EditingSettings.Key.highlightLine: true,
                    EditingSettings.Key.indent: "tab", EditingSettings.Key.spellCheck: true, EditingSettings.Key.autocorrect: true,
                    EditingSettings.Key.smartPunctuation: true, EditingSettings.Key.openIn: "edit",
                ],
                EditorAppearance(font: .charter, size: 20, spacing: 0.6, characters: nil, fullStrengthMarks: true, highlightsCurrentLine: true)
            ),
            (
                "small, compact, every typing aid off",
                [
                    DisplaySettings.Key.interfaceSize: "small", DisplaySettings.Key.density: "compact",
                    DisplaySettings.Key.taskPreview: false, DisplaySettings.Key.taskChips: false,
                    ReadingSettings.Key.font: "mono", ReadingSettings.Key.textSize: -3, ReadingSettings.Key.lineWidth: "narrow",
                    ReadingSettings.Key.paragraphSpacing: "tight", ReadingSettings.Key.properties: "hidden",
                    ReadingSettings.Key.hyphenate: true, ReadingSettings.Key.underlineLinks: false, ReadingSettings.Key.codeTextSize: "same",
                    EditingSettings.Key.font: "system", EditingSettings.Key.textSize: -2, EditingSettings.Key.lineSpacing: "compact",
                    EditingSettings.Key.lineWidth: "narrow", EditingSettings.Key.indent: "2", EditingSettings.Key.continueLists: false,
                    EditingSettings.Key.tabIndents: false, EditingSettings.Key.wrapSelection: false, EditingSettings.Key.autocorrect: false,
                    EditingSettings.Key.editWithPreview: false, EditingSettings.Key.syncPreviewScroll: false,
                    EditingSettings.Key.hideTags: false, EditingSettings.Key.formattingBar: false, EditingSettings.Key.recentColors: "#D94F3D,nonsense",
                ],
                EditorAppearance(font: .system, size: 11, spacing: 0.22, characters: 56, fullStrengthMarks: false, highlightsCurrentLine: false, hidesTags: false)
            ),
            (
                "values no version of Perch wrote",
                [
                    DisplaySettings.Key.interfaceSize: "enormous", DisplaySettings.Key.density: 7,
                    ReadingSettings.Key.properties: "", ReadingSettings.Key.textSize: 999,
                    EditingSettings.Key.indent: "8", EditingSettings.Key.lineWidth: "wide", EditingSettings.Key.marks: "bold",
                ],
                EditorAppearance(font: .mono, size: 24, spacing: 0.4, characters: 100, fullStrengthMarks: true, highlightsCurrentLine: true)
            ),
        ]
        let saved = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(saved, forName: UserDefaults.argumentDomain) }
        for combination in combinations {
            UserDefaults.standard.setVolatileDomain(saved.merging(combination.values) { _, new in new }, forName: UserDefaults.argumentDomain)
            XCTAssertEqual(UserDefaults.standard.object(forKey: DisplaySettings.Key.interfaceSize) as? String, combination.values[DisplaySettings.Key.interfaceSize] as? String)
            try? FileManager.default.removeItem(at: root)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try await assertOpeningChangesNothing(appearance: combination.appearance, combination.label)
        }
    }

    func testStylingInTheEditorIsQuickAndNeverChangesCharacters() {
        var lines: [String] = []
        for index in 0..<5000 {
            switch index % 8 {
            case 0: lines.append("## Heading \(index)")
            case 1: lines.append("- [ ] task with **bold** and [[Link]] 🎉")
            case 2: lines.append("```")
            case 3: lines.append("code \(index)")
            case 4: lines.append("```")
            default: lines.append("Prose with *emphasis*, `code` and a [link](https://example.com).")
            }
        }
        let text = lines.joined(separator: "\n")
        let storage = NSTextStorage(string: text)
        let styler = MarkdownStyler(appearance: EditorAppearance(), palette: ThemePresets.perchLight)

        var start = Date()
        styler.restyleAll(storage)
        let whole = Date().timeIntervalSince(start)
        XCTAssertEqual(storage.string, text)

        // A keystroke in the middle: only that paragraph is styled again.
        let middle = (text as NSString).range(of: "Heading 2504")
        var best = Double.infinity
        for _ in 0..<20 {
            storage.replaceCharacters(in: NSRange(location: middle.location, length: 0), with: "x")
            start = Date()
            styler.restyle(storage, edited: NSRange(location: middle.location, length: 1))
            best = min(best, Date().timeIntervalSince(start))
            storage.replaceCharacters(in: NSRange(location: middle.location, length: 1), with: "")
            styler.restyle(storage, edited: NSRange(location: middle.location, length: 0))
        }
        XCTAssertEqual(storage.string, text)
        print("styler: whole 5,000-line note \(String(format: "%.1f", whole * 1000)) ms, one keystroke \(String(format: "%.2f", best * 1000)) ms")
        XCTAssertLessThan(best, 0.02)

        // Opening a fence above restyles what is below it, and closing it puts everything back.
        let before = NSAttributedString(attributedString: storage)
        let top = (text as NSString).range(of: "Prose").location
        storage.replaceCharacters(in: NSRange(location: top, length: 0), with: "~~~\n")
        styler.restyle(storage, edited: NSRange(location: top, length: 4))
        let below = (storage.string as NSString).range(of: "Heading 4000")
        XCTAssertNotNil(storage.attribute(.perchCodeBlock, at: below.location, effectiveRange: nil), "text under a new fence is code")
        storage.replaceCharacters(in: NSRange(location: top, length: 4), with: "")
        styler.restyle(storage, edited: NSRange(location: top, length: 0))
        XCTAssertEqual(storage.string, text)
        XCTAssertTrue(storage.isEqual(to: before), "no styling is left over once the fence is gone")
    }

    func testOnlyFormattingTagsHideAndOtherHTMLStaysInSight() throws {
        let text = "press <kbd>K</kbd> and<br>break <u>under</u> Array<String> x <u></u>\n\n<details>\n<summary>More</summary>\n\n<img src=\"a.png\" width=\"300\">\n\n<div align=\"center\">\n\nmiddle\n\n</div>\n"
        let source = text as NSString
        let storage = NSTextStorage(string: text)
        let styler = MarkdownStyler(appearance: EditorAppearance(), palette: ThemePresets.perchLight)
        styler.restyleAll(storage)
        func size(_ needle: String) throws -> CGFloat {
            try XCTUnwrap(storage.attribute(.font, at: source.range(of: needle).location, effectiveRange: nil) as? PlatformFont).pointSize
        }
        // A tag the editor draws the effect of hides. Anything else would take content out of sight with it.
        XCTAssertLessThan(try size("<u>under"), 1)
        XCTAssertLessThan(try size("</u> Array"), 1)
        for shown in ["<kbd>", "</kbd>", "<br>", "<String>", "<u></u>", "<details>", "<summary>", "</summary>", "<img", "<div", "</div>"] {
            XCTAssertGreaterThan(try size(shown), 6, shown)
        }
        XCTAssertEqual(storage.string, text)
    }

    func testTextOnAColoredHighlightIsReadAgainstTheHighlight() throws {
        let text = "<mark style=\"background-color: #D94F3D\">plain and <span style=\"color: #D94F3D\">red on red</span></mark> <span style=\"color: #3B82D9\"><mark style=\"background-color: #3B82D9\">blue on blue</mark></span> ==yellow and <span style=\"color: #C99A1B\">amber</span>==\n"
        let source = text as NSString
        for palette in ThemePresets.all {
            let storage = NSTextStorage(string: text)
            let styler = MarkdownStyler(appearance: EditorAppearance(hidesTags: false), palette: palette)
            styler.restyleAll(storage)
            let page = try XCTUnwrap(ThemeRGB(hex: palette.background))
            let yellow = FormatPalette.plainWash(try XCTUnwrap(ThemeRGB(hex: palette.warning)), on: page)
            for (needle, highlight) in [("plain and", "#D94F3D"), ("red on red", "#D94F3D"), ("blue on blue", "#3B82D9"), ("yellow and", ""), ("amber", "")] {
                let color = try XCTUnwrap(storage.attribute(.foregroundColor, at: source.range(of: needle).location, effectiveRange: nil) as? PlatformColor)
                let shown = try XCTUnwrap(color.themeRGB)
                let behind = highlight.isEmpty ? yellow : FormatPalette.wash(try XCTUnwrap(ThemeRGB(hex: highlight)), on: page, dark: palette.isDark)
                XCTAssertGreaterThanOrEqual(ThemeContrast.ratio(shown, behind), 4.4, "\(needle) in \(palette.name)")
            }
            XCTAssertEqual(storage.string, text)
        }
    }

    func testFormattingIsShownAndTagsHideWithoutChangingCharacters() throws {
        let text = "plain <span style=\"color: #000000\">black</span> and <u>under</u>\nsecond <mark style=\"background-color: #3B82D9\">blue</mark> <span style=\"font-size: 1.6em\">big</span>\n"
        let source = text as NSString
        func font(_ storage: NSTextStorage, _ needle: String) -> PlatformFont? {
            storage.attribute(.font, at: source.range(of: needle).location, effectiveRange: nil) as? PlatformFont
        }
        for palette in [ThemePresets.perchDark, ThemePresets.perchLight] {
            let storage = NSTextStorage(string: text)
            let styler = MarkdownStyler(appearance: EditorAppearance(), palette: palette)
            styler.restyleAll(storage)
            XCTAssertEqual(storage.string, text)

            // Colored text can be read on this theme, whatever was picked.
            let color = try XCTUnwrap(storage.attribute(.foregroundColor, at: source.range(of: "black").location, effectiveRange: nil) as? PlatformColor)
            let rgb = try XCTUnwrap(color.usingColorSpace(.sRGB))
            let shown = ThemeRGB(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent))
            XCTAssertGreaterThanOrEqual(ThemeContrast.ratio(shown, try XCTUnwrap(ThemeRGB(hex: palette.background))), 4.4, palette.name)
            XCTAssertNotNil(storage.attribute(.underlineStyle, at: source.range(of: "under").location, effectiveRange: nil))
            XCTAssertNotNil(storage.attribute(.backgroundColor, at: source.range(of: "blue").location, effectiveRange: nil))
            let base = try XCTUnwrap(font(storage, "plain")).pointSize
            XCTAssertEqual(try XCTUnwrap(font(storage, "big")).pointSize, base * 1.6, accuracy: 0.6)

            // Tags are in the text but drawn too small to see, until the caret is on their line.
            XCTAssertLessThan(try XCTUnwrap(font(storage, "<span")).pointSize, 1)
            XCTAssertLessThan(try XCTUnwrap(font(storage, "<mark")).pointSize, 1)
            styler.reveal(styler.revealRange(for: NSRange(location: 3, length: 0), in: source), in: storage)
            XCTAssertGreaterThan(try XCTUnwrap(font(storage, "<span")).pointSize, 6)
            XCTAssertLessThan(try XCTUnwrap(font(storage, "<mark")).pointSize, 1, "the other line stays hidden")
            styler.reveal(styler.revealRange(for: NSRange(location: source.range(of: "second").location, length: 0), in: source), in: storage)
            XCTAssertLessThan(try XCTUnwrap(font(storage, "<span")).pointSize, 1)
            XCTAssertGreaterThan(try XCTUnwrap(font(storage, "<mark")).pointSize, 6)
            XCTAssertEqual(storage.string, text)

            // With the setting off, every tag is shown, small.
            let open = MarkdownStyler(appearance: EditorAppearance(hidesTags: false), palette: palette)
            open.restyleAll(storage)
            XCTAssertGreaterThan(try XCTUnwrap(font(storage, "<span")).pointSize, 6)
            XCTAssertLessThan(try XCTUnwrap(font(storage, "<span")).pointSize, base)
            XCTAssertNil(open.revealRange(for: NSRange(location: 0, length: 0), in: source))
        }
    }

    func testAFileThatIsNotTextIsNeverReplaced() async throws {
        let bytes = Data([0x63, 0x61, 0x66, 0xE9, 0x0A])
        try bytes.write(to: root.appendingPathComponent("latin1.md"))
        let model = await openModel(root)
        let session = NoteSession(path: "latin1.md", model: model)
        XCTAssertFalse(session.isReadable)
        // Even if something changes the text in memory, the file keeps its own bytes.
        session.text = "typed over it"
        session.saveNow()
        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("latin1.md")), bytes)
    }

    func testEditsSaveAndOutsideChangesAreKept() async throws {
        let url = root.appendingPathComponent("note.md")
        try Data("one\r\ntwo\r\n".utf8).write(to: url)
        let model = await openModel(root)
        let session = NoteSession(path: "note.md", model: model)

        // An edit is saved exactly as typed.
        session.text = "one\r\ntwo\r\nthree"
        session.saveNow()
        XCTAssertEqual(try Data(contentsOf: url), Data("one\r\ntwo\r\nthree".utf8))

        // With nothing unsaved, a change from outside is taken in and not written back.
        try Data("from an agent\n".utf8).write(to: url)
        session.refreshFromDisk()
        XCTAssertEqual(session.text, "from an agent\n")
        session.saveNow()
        XCTAssertEqual(try Data(contentsOf: url), Data("from an agent\n".utf8))

        // With unsaved typing, a change from outside is kept beside it, never overwritten.
        session.text = "from an agent\nand me\n"
        try Data("from an agent\nand the agent again\n".utf8).write(to: url)
        session.refreshFromDisk()
        XCTAssertEqual(session.text, "from an agent\nand me\n")
        session.saveNow()
        let saved = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(ConflictBlocks.contains(saved))
        XCTAssertTrue(saved.contains("and the agent again"))
        XCTAssertTrue(saved.contains("and me"))

        // A note that was deleted isn't brought back by a late save.
        session.text = saved + "more"
        session.discard()
        try FileManager.default.removeItem(at: url)
        session.saveNow()
        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    /// The same check over a copy of a real notebook. Set PERCH_VAULT_COPY to a folder that is a Git
    /// working copy you can afford to lose; the test fails if `git status` shows anything afterwards.
    func testOpeningEveryNoteInARealNotebookCopyChangesNothing() async throws {
        guard let path = ProcessInfo.processInfo.environment["PERCH_VAULT_COPY"], !path.isEmpty else {
            throw XCTSkip("Set PERCH_VAULT_COPY to a copy of a notebook to run this.")
        }
        let folder = URL(fileURLWithPath: path)
        // A notebook that syncs with GitHub is the real one; a copy has no remote, or a local one.
        let syncsWithGitHub = GitCLISync.origin(of: folder).flatMap(GitHubNotebook.fullName(fromRemote:)) != nil
        XCTAssertFalse(syncsWithGitHub || path.hasSuffix("Perch-Test/vault"), "Use a copy, not the notebook itself.")
        let before = try snapshot(folder)
        let model = await openModel(folder)
        let result = try await openEverything(in: model)
        let after = try snapshot(folder)

        print("opened \(result.opened) notes in \(path); \(before.count) files checked")
        XCTAssertGreaterThan(result.opened, 0)
        XCTAssertEqual(result.mangled, [], "text changed going through the editor's text storage")
        XCTAssertEqual(Set(before.keys), Set(after.keys))
        var changed: [String] = []
        for (file, old) in before where after[file]?.data != old.data || after[file]?.modified != old.modified { changed.append(file) }
        XCTAssertEqual(changed, [])

        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["-C", path, "status", "--porcelain"]
        let pipe = Pipe()
        git.standardOutput = pipe
        try git.run()
        git.waitUntilExit()
        let status = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(status, "", "git status should be clean")
    }
}
