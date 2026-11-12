import XCTest

/// Bold, strike-through and highlight whose closing marks come right after punctuation and right before a
/// word, as in `**IBM, Salesforce:**Emphasize`. CommonMark doesn't count that closing `**` (GitHub shows the
/// marks), but the meaning is plain, and notes written by AI tools do it often: a survey of a real notebook
/// found it 22 times in 12 notes, and a redlined contract full of `~~Customer.~~Supplier`. Underscores keep the
/// strict rule, so `snake_case_names` stay as they are.
@MainActor
final class RenderEmphasisTests: XCTestCase {
    private var page: RenderPage!

    override func setUp() async throws {
        page = RenderPage()
    }

    override func tearDown() async throws {
        page.close()
    }

    private func draw(_ markdown: String) async throws {
        try await page.render(markdown)
    }

    private func texts(_ selector: String) async throws -> [String] {
        try await page.js("return [...document.querySelectorAll('#root ' + selector)].map(e => e.textContent);", ["selector": selector]) as? [String] ?? []
    }

    private func pageText() async throws -> String {
        try await page.string("document.getElementById('root').textContent")
    }

    func testBoldEndingInPunctuationRightBeforeAWord() async throws {
        try await draw("**IBM, Salesforce, McKinsey:**Emphasize skills-based architectures")
        let v1 = try await texts("strong")
        XCTAssertEqual(v1, ["IBM, Salesforce, McKinsey:"])
        let v2 = try await pageText()
        XCTAssertFalse(v2.contains("**"))

        try await draw("The grid is clear that **tools are \u{201C}Not Managed\u{201D}**even though they run.")
        let v3 = try await texts("strong")
        XCTAssertEqual(v3, ["tools are \u{201C}Not Managed\u{201D}"])
    }

    func testBoldStartingAfterAWordRightBeforePunctuation() async throws {
        try await draw("See**\u{201C}the brief\u{201D}** for more.")
        let v4 = try await texts("strong")
        XCTAssertEqual(v4, ["\u{201C}the brief\u{201D}"])
    }

    func testStrikeAndHighlightTheSameWay() async throws {
        try await draw("Changes. ~~The vendor may update this.~~Acme may update this.")
        let v5 = try await texts("s")
        XCTAssertEqual(v5, ["The vendor may update this."])
        try await draw("A ==note to self.==Then the rest.")
        let v6 = try await texts("mark")
        XCTAssertEqual(v6, ["note to self."])
    }

    func testInsideATableCell() async throws {
        try await draw("| Area | Claim |\n|---|---|\n| **Agentic AI** | **IBM, Salesforce:**Emphasize skills |\n")
        let v7 = try await texts("td strong")
        XCTAssertEqual(v7, ["Agentic AI", "IBM, Salesforce:"])
    }

    func testTheUsualRulesStillHold() async throws {
        try await draw("Two times three: 2 * 3 * 4, and snake_case_name, and ** not bold ** here.")
        let v8 = try await texts("em")
        let v9 = try await texts("strong")
        XCTAssertEqual(v8.count + v9.count, 0)
        let v10 = try await pageText()
        XCTAssertTrue(v10.contains("snake_case_name"))

        try await draw("**bold** and *italic* and a**b**c and ~~gone~~ and ==lit==")
        let v11 = try await texts("strong")
        XCTAssertEqual(v11, ["bold", "b"])
        let v12 = try await texts("em")
        XCTAssertEqual(v12, ["italic"])
        let v13 = try await texts("s")
        XCTAssertEqual(v13, ["gone"])
        let v14 = try await texts("mark")
        XCTAssertEqual(v14, ["lit"])

        try await draw("Code keeps its marks: `**Label:**Text`")
        let v15 = try await texts("code")
        XCTAssertEqual(v15, ["**Label:**Text"])
        let v16 = try await texts("strong")
        XCTAssertEqual(v16.count, 0)
    }
}
