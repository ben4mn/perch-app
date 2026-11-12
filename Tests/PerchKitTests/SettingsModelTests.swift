import XCTest
@testable import PerchKit

/// The sums and mappings behind Settings: interface size and density, the reader's style, and the
/// typing helpers that can be turned off.
final class SettingsModelTests: XCTestCase {
    private func caret(_ location: Int) -> NSRange { NSRange(location: location, length: 0) }
    private func end(_ text: String) -> NSRange { caret((text as NSString).length) }

    // MARK: Interface size and density

    func testDefaultsChangeNothing() {
        let metrics = DisplayMetrics.standard
        for value in [1.5, 7, 10, 11.5, 13.5, 18, 22, 43, 72.25] {
            XCTAssertEqual(metrics.font(value), value)
            XCTAssertEqual(metrics.length(value), value)
            XCTAssertEqual(metrics.gap(value), value)
            XCTAssertEqual(metrics.rowPadding(value), value)
            XCTAssertEqual(metrics.rowHeight(value), value)
        }
        XCTAssertEqual(InterfaceSize.standard.scale, 1)
        XCTAssertEqual(InterfaceSize.standard.rawValue, "default")
        XCTAssertEqual(InterfaceDensity.comfortable.rowFactor, 1)
        XCTAssertEqual(InterfaceDensity.comfortable.gapFactor, 1)
    }

    func testInterfaceSizeScalesFontsInOrder() {
        let sizes = InterfaceSize.allCases.map { DisplayMetrics(size: $0).font(13.5) }
        XCTAssertEqual(sizes, sizes.sorted())
        XCTAssertEqual(Set(sizes).count, sizes.count)
        XCTAssertEqual(DisplayMetrics(size: .small).font(13.5), 12)
        XCTAssertEqual(DisplayMetrics(size: .large).font(13.5), 15)
        XCTAssertEqual(DisplayMetrics(size: .extraLarge).font(13.5), 17)
        // Rounded to half a point, and never too small to read.
        XCTAssertEqual(DisplayMetrics(size: .extraLarge).font(11).truncatingRemainder(dividingBy: 0.5), 0)
        XCTAssertEqual(DisplayMetrics(size: .small).font(8), 8)
    }

    func testGapsGrowMoreSlowlyThanText() {
        let extraLarge = DisplayMetrics(size: .extraLarge)
        XCTAssertEqual(extraLarge.length(20), 25)
        XCTAssertEqual(extraLarge.gap(20), 23)
        XCTAssertLessThan(extraLarge.gap(12) / 12, extraLarge.font(12) / 12)
    }

    func testDensityChangesRowsAndLeavesFontsAlone() {
        let compact = DisplayMetrics(density: .compact), roomy = DisplayMetrics(density: .roomy)
        XCTAssertEqual(compact.font(13.5), 13.5)
        XCTAssertEqual(roomy.length(18), 18)
        XCTAssertEqual(compact.rowPadding(10), 5.5)
        XCTAssertEqual(roomy.rowPadding(10), 15)
        XCTAssertEqual(compact.rowPadding(7), 4)
        XCTAssertEqual(roomy.rowPadding(7), 10.5)
        XCTAssertLessThan(compact.gap(12), 12)
        XCTAssertGreaterThan(roomy.gap(12), 12)
        XCTAssertLessThan(compact.rowHeight(18), 18)
        XCTAssertGreaterThan(roomy.rowHeight(18), 18)
        // Rows never touch, however small and tight.
        XCTAssertEqual(DisplayMetrics(size: .small, density: .compact).rowPadding(1), 2)
    }

    func testSizeAndDensityCombine() {
        let metrics = DisplayMetrics(size: .extraLarge, density: .roomy)
        XCTAssertEqual(metrics.rowPadding(10), 19)
        XCTAssertGreaterThan(metrics.rowHeight(18), DisplayMetrics(size: .extraLarge).rowHeight(18))
        XCTAssertFalse(metrics.isStandard)
    }

    func testSteppingStopsAtTheEnds() {
        XCTAssertEqual(InterfaceSize.standard.stepped(by: 1), .large)
        XCTAssertEqual(InterfaceSize.standard.stepped(by: -1), .small)
        XCTAssertEqual(InterfaceSize.small.stepped(by: -1), .small)
        XCTAssertEqual(InterfaceSize.extraLarge.stepped(by: 1), .extraLarge)
        XCTAssertEqual(InterfaceSize.small.stepped(by: 5), .extraLarge)
    }

    func testIPhoneTextSizeFollowsTheSystemOrNot() {
        let standard = DisplayMetrics.standard
        // Matching the iPhone with the default interface size is exactly the iPhone's size.
        for system in 0..<DisplayMetrics.textSizeCount {
            XCTAssertEqual(standard.textSizeIndex(system: system, matchSystem: true), system)
            XCTAssertEqual(standard.textSizeIndex(system: system, matchSystem: false), DisplayMetrics.defaultTextSizeIndex)
        }
        let large = DisplayMetrics(size: .large), small = DisplayMetrics(size: .small), extraLarge = DisplayMetrics(size: .extraLarge)
        XCTAssertEqual(large.textSizeIndex(system: 5, matchSystem: true), 6)
        XCTAssertEqual(large.textSizeIndex(system: 5, matchSystem: false), 4)
        XCTAssertEqual(small.textSizeIndex(system: 3, matchSystem: true), 1)
        XCTAssertEqual(extraLarge.textSizeIndex(system: 3, matchSystem: true), 5)
        // The ends hold.
        XCTAssertEqual(small.textSizeIndex(system: 0, matchSystem: true), 0)
        XCTAssertEqual(extraLarge.textSizeIndex(system: 11, matchSystem: true), 11)
    }

    func testWideLayoutsCanBeTurnedOff() {
        XCTAssertEqual(AdaptiveLayout.effectiveWidth(669, allowsWide: true), 669)
        XCTAssertEqual(AdaptiveLayout.effectiveWidth(466, allowsWide: false), 466)
        let narrowed = AdaptiveLayout.effectiveWidth(951, allowsWide: false)
        XCTAssertLessThan(narrowed, AdaptiveLayout.wideWidth)
        // The Duo's inner screen, both ways up, then keeps the phone layouts.
        XCTAssertEqual(AdaptiveLayout.month(width: narrowed, height: 669, compactWidthClass: false), .stacked)
        XCTAssertEqual(AdaptiveLayout.week(width: narrowed, compactWidthClass: false), .stacked)
        XCTAssertFalse(AdaptiveLayout.folderGrid(width: narrowed, prefersList: true))
        XCTAssertEqual(AdaptiveLayout.month(width: AdaptiveLayout.effectiveWidth(951, allowsWide: true), height: 669, compactWidthClass: false), .grid)
    }

    // MARK: Reader style

    func testDefaultReaderStyleClearsEverything() {
        let style = ReaderStyle.standard
        XCTAssertFalse(style.cssVariables.isEmpty)
        XCTAssertTrue(style.cssVariables.values.allSatisfy(\.isEmpty), "the defaults leave the stylesheet in charge")
        XCTAssertTrue(style.attributes.values.allSatisfy(\.isEmpty))
        XCTAssertFalse(style.hyphenates)
    }

    func testReaderStyleMapsEachSettingToItsVariable() {
        let style = ReaderStyle(
            paragraphSpacing: .relaxed, headingFont: .serif, codeWrap: .wrap, codeTextSize: .same, properties: .expanded,
            hyphenate: true, justify: false, underlineLinks: false, imageWidth: .full
        )
        let css = style.cssVariables
        XCTAssertEqual(css["--perch-paragraph-gap"], "1.4em")
        XCTAssertEqual(css["--perch-font-heading"]?.hasPrefix("ui-serif"), true)
        XCTAssertEqual(css["--perch-code-white-space"], "pre-wrap")
        XCTAssertEqual(css["--perch-code-overflow-wrap"], "anywhere")
        XCTAssertEqual(css["--perch-code-size"], "1em")
        XCTAssertEqual(css["--perch-hyphens"], "auto")
        XCTAssertEqual(css["--perch-text-align"], "")
        XCTAssertEqual(css["--perch-link-decoration"], "none")
        XCTAssertEqual(style.attributes, ["properties": "expanded", "images": "full"])
        XCTAssertEqual(ReaderStyle(paragraphSpacing: .tight).cssVariables["--perch-paragraph-gap"], ".55em")
        XCTAssertEqual(ReaderStyle(headingFont: .rounded).cssVariables["--perch-font-heading"]?.hasPrefix("ui-rounded"), true)
        XCTAssertEqual(ReaderStyle(properties: .hidden).attributes["properties"], "hidden")
        XCTAssertEqual(ReaderStyle(properties: .collapsed).attributes["properties"], "collapsed")
    }

    func testEveryStyleSendsTheSameKeysSoAChangeCanBeUndone() {
        let changed = ReaderStyle(paragraphSpacing: .tight, headingFont: .rounded, codeWrap: .wrap, properties: .hidden, underlineLinks: false, imageWidth: .full)
        XCTAssertEqual(Set(changed.cssVariables.keys), Set(ReaderStyle.standard.cssVariables.keys))
        XCTAssertEqual(Set(changed.attributes.keys), Set(ReaderStyle.standard.attributes.keys))
    }

    func testJustifiedTextIsAlwaysHyphenated() {
        let justified = ReaderStyle(hyphenate: false, justify: true)
        XCTAssertTrue(justified.hyphenates)
        XCTAssertEqual(justified.cssVariables["--perch-text-align"], "justify")
        XCTAssertEqual(justified.cssVariables["--perch-hyphens"], "auto")
    }

    func testReaderValuesAreSafeForThePage() {
        // The page refuses anything with these in it; make sure nothing Perch sends would be refused.
        for style in [ReaderStyle.standard, ReaderStyle(paragraphSpacing: .relaxed, headingFont: .serif, codeWrap: .wrap, codeTextSize: .same, hyphenate: true, justify: true, underlineLinks: false)] {
            for (name, value) in style.cssVariables {
                XCTAssertTrue(name.hasPrefix("--perch-"))
                XCTAssertNil(value.range(of: #"url\(|[;{}<>]"#, options: .regularExpression), "\(name): \(value)")
            }
        }
    }

    // MARK: Typing helpers

    func testStandardOptionsMatchTheOldBehaviour() throws {
        let options = MarkdownEditing.Options.standard
        XCTAssertEqual(options.indent.unit, MarkdownEditing.indentUnit)
        for (typed, text, selection) in [("\n", "- one", end("- one")), ("\t", "- one", end("- one")), ("*", "word", NSRange(location: 0, length: 4))] {
            let viaTyping = MarkdownEditing.edit(forTyping: typed, in: text, selection: selection, options: options)
            let direct: TextEdit? = switch typed {
            case "\n": MarkdownEditing.newline(in: text, selection: selection)
            case "\t": MarkdownEditing.indent(in: text, selection: selection, outdent: false)
            default: MarkdownEditing.wrapSelection(typing: typed, in: text, selection: selection)
            }
            XCTAssertNotNil(viaTyping)
            XCTAssertEqual(viaTyping, direct)
        }
        XCTAssertEqual(MarkdownEditing.edit(forTyping: "\n", in: "- one", selection: end("- one"))?.applied(to: "- one"), "- one\n- ")
    }

    func testOrdinaryTypingIsLeftAlone() {
        XCTAssertNil(MarkdownEditing.edit(forTyping: "a", in: "word", selection: caret(2)))
        XCTAssertNil(MarkdownEditing.edit(forTyping: "a", in: "word", selection: NSRange(location: 0, length: 4)))
        XCTAssertNil(MarkdownEditing.edit(forTyping: "\n", in: "plain", selection: end("plain")))
        XCTAssertNil(MarkdownEditing.edit(forTyping: "\t", in: "plain", selection: end("plain")))
        XCTAssertNil(MarkdownEditing.edit(forTyping: "*", in: "word", selection: caret(2)))
    }

    func testContinuingListsCanBeTurnedOff() {
        let off = MarkdownEditing.Options(continuesLists: false)
        for text in ["- one", "3. three", "- [ ] task", "> quoted", "- "] {
            XCTAssertNil(MarkdownEditing.edit(forTyping: "\n", in: text, selection: end(text), options: off), text)
        }
        // The other helpers stay on.
        XCTAssertNotNil(MarkdownEditing.edit(forTyping: "\t", in: "- one", selection: end("- one"), options: off))
        XCTAssertNotNil(MarkdownEditing.edit(forTyping: "*", in: "word", selection: NSRange(location: 0, length: 4), options: off))
    }

    func testTabIndentCanBeTurnedOff() {
        let off = MarkdownEditing.Options(tabIndentsLists: false)
        XCTAssertNil(MarkdownEditing.edit(forTyping: "\t", in: "- one", selection: end("- one"), options: off))
        XCTAssertNil(MarkdownEditing.edit(forTyping: "\t", in: "- one\n- two", selection: NSRange(location: 0, length: 11), options: off))
        XCTAssertNotNil(MarkdownEditing.edit(forTyping: "\n", in: "- one", selection: end("- one"), options: off))
        // The indent command itself (the keyboard bar, Shift-Tab) still works.
        XCTAssertNotNil(MarkdownEditing.indent(in: "- one", selection: end("- one"), outdent: false, options: off))
    }

    func testWrappingTheSelectionCanBeTurnedOff() {
        let off = MarkdownEditing.Options(wrapsSelection: false)
        for mark in ["*", "_", "`", "[", "(", "~", "\""] {
            XCTAssertNil(MarkdownEditing.edit(forTyping: mark, in: "word", selection: NSRange(location: 0, length: 4), options: off), mark)
            XCTAssertNotNil(MarkdownEditing.edit(forTyping: mark, in: "word", selection: NSRange(location: 0, length: 4)), mark)
        }
    }

    func testIndentSizes() throws {
        let text = "- one"
        for (style, expected) in [(MarkdownEditing.IndentStyle.twoSpaces, "  - one"), (.fourSpaces, "    - one"), (.tab, "\t- one")] {
            let options = MarkdownEditing.Options(indent: style)
            let edit = try XCTUnwrap(MarkdownEditing.edit(forTyping: "\t", in: text, selection: end(text), options: options))
            XCTAssertEqual(edit.applied(to: text), expected)
            // The caret stays after the same character.
            XCTAssertEqual(edit.selection, caret((expected as NSString).length))
            // And one outdent takes exactly that back.
            let back = try XCTUnwrap(MarkdownEditing.indent(in: expected, selection: end(expected), outdent: true, options: options))
            XCTAssertEqual(back.applied(to: expected), text)
        }
        XCTAssertEqual(MarkdownEditing.IndentStyle(rawValue: "2"), .twoSpaces)
        XCTAssertEqual(MarkdownEditing.IndentStyle(rawValue: "4"), .fourSpaces)
        XCTAssertEqual(MarkdownEditing.IndentStyle(rawValue: "tab"), .tab)
    }

    func testOutdentTakesOneLevelOfTheChosenSize() throws {
        let two = MarkdownEditing.Options(indent: .twoSpaces)
        var text = "    - deep"
        var edit = try XCTUnwrap(MarkdownEditing.indent(in: text, selection: end(text), outdent: true, options: two))
        XCTAssertEqual(edit.applied(to: text), "  - deep")
        // With tabs chosen, a line indented with spaces by someone else still comes out a level.
        let tab = MarkdownEditing.Options(indent: .tab)
        edit = try XCTUnwrap(MarkdownEditing.indent(in: text, selection: end(text), outdent: true, options: tab))
        XCTAssertEqual(edit.applied(to: text), "- deep")
        text = "\t\t- deep"
        edit = try XCTUnwrap(MarkdownEditing.indent(in: text, selection: end(text), outdent: true, options: two))
        XCTAssertEqual(edit.applied(to: text), "\t- deep")
    }

    func testIndentingSeveralLinesUsesTheChosenSize() throws {
        let text = "- one\n- two"
        let edit = try XCTUnwrap(MarkdownEditing.indent(in: text, selection: NSRange(location: 0, length: 11), outdent: false, options: .init(indent: .twoSpaces)))
        XCTAssertEqual(edit.applied(to: text), "  - one\n  - two")
    }

    func testReturnOnAnEmptyNestedItemStepsOutByTheChosenSize() throws {
        let text = "- one\n  - "
        let edit = try XCTUnwrap(MarkdownEditing.newline(in: text, selection: end(text), options: .init(indent: .twoSpaces)))
        XCTAssertEqual(edit.applied(to: text), "- one\n- ")
    }

    func testNothingTheHelpersDoAddsSmartPunctuation() throws {
        // Curly quotes and long dashes break Markdown; the helpers only ever add what was typed or plain marks.
        let wrapped = try XCTUnwrap(MarkdownEditing.edit(forTyping: "\"", in: "word", selection: NSRange(location: 0, length: 4)))
        XCTAssertEqual(wrapped.applied(to: "word"), "\"word\"")
    }
}
