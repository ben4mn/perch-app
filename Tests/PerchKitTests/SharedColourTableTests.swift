import PerchKit
import XCTest

/// The editor and the reader must draw a picked colour the same way. Both are held to one table,
/// `Tests/Fixtures/Rendering/legible-colours.json`: this test holds the editor's rule (`FormatPalette`)
/// to it, and `RenderReviewTests` holds the reader's JavaScript to it.
///
/// After changing the rule on purpose, write the table again with
/// `PERCH_WRITE_COLOUR_TABLE=1 swift test --filter SharedColourTableTests`, rebuild the reader to match,
/// and run the rendering tests.
final class SharedColourTableTests: XCTestCase {
    private static let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Rendering/legible-colours.json")

    private func colours() -> [String] {
        var colours = FormatPalette.colors.map(\.hex) + ["#FFFFFF", "#000000", "#FFF36B", "#1B1F4B", "#808080", "#00FF00", "#FF00FF", "#663399", "#FF0000", "#0000FF", "#C81E1E", "#177BCF"]
        var seed: UInt64 = 20261109
        for _ in 0..<28 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            colours.append(String(format: "#%06X", Int((seed >> 33) & 0xFFFFFF)))
        }
        return colours
    }

    /// Text colours: [picked colour, page colour, colour drawn].
    private func textRows() -> [[String]] {
        var grounds = ThemePresets.all.map { $0.background.uppercased() } + ["#FFFFFF", "#000000", "#767676", "#777777", "#757575", "#F5F5DC", "#102030"]
        var seen = Set<String>()
        grounds = grounds.filter { seen.insert($0).inserted }
        return grounds.flatMap { ground in
            colours().map { [$0, ground, FormatPalette.legible(ThemeRGB(hex: $0)!, on: ThemeRGB(hex: ground)!).hex] }
        }
    }

    /// Highlights: [highlight colour, page colour, "dark" or "light", text colour, "picked" or "theme", the wash drawn, the text drawn on it].
    /// A picked text colour is first made readable on the page, then on the wash, as the editor does.
    private func highlightRows() -> [[String]] {
        var rows: [[String]] = []
        for theme in ThemePresets.all {
            let page = ThemeRGB(hex: theme.background)!
            for highlight in colours().prefix(18) {
                let wash = FormatPalette.wash(ThemeRGB(hex: highlight)!, on: page, dark: theme.isDark).hex
                let behind = ThemeRGB(hex: wash)!
                rows.append([highlight, theme.background.uppercased(), theme.isDark ? "dark" : "light", theme.text.uppercased(), "theme", wash,
                             FormatPalette.legible(ThemeRGB(hex: theme.text)!, on: behind).hex])
                for ink in [highlight, "#D94F3D", "#3B82D9", "#FFFFFF", "#000000"] {
                    let onPage = FormatPalette.legible(ThemeRGB(hex: ink)!, on: page)
                    rows.append([highlight, theme.background.uppercased(), theme.isDark ? "dark" : "light", ink, "picked", wash, FormatPalette.legible(onPage, on: behind).hex])
                }
            }
        }
        return rows
    }

    func testTheEditorsColourRuleMatchesTheTableTheReaderIsHeldTo() throws {
        let text = textRows(), highlights = highlightRows()
        if ProcessInfo.processInfo.environment["PERCH_WRITE_COLOUR_TABLE"] == "1" {
            let lines = { (rows: [[String]]) in rows.map { "  [" + $0.map { "\"\($0)\"" }.joined(separator: ", ") + "]" }.joined(separator: ",\n") }
            let json = """
            {
            "about": "What the editor (FormatPalette in Swift) and the reader (Perch.color in JavaScript) must both draw. text: a picked text colour, the page colour, the colour drawn. highlights: highlight colour, page colour, dark or light theme, text colour, whether that text colour was picked or is the theme's own, the wash drawn behind, the text colour drawn on it. Written by SharedColourTableTests with PERCH_WRITE_COLOUR_TABLE=1.",
            "rows": [
            \(lines(text))
            ],
            "highlights": [
            \(lines(highlights))
            ]
            }

            """
            try json.write(to: Self.file, atomically: true, encoding: .utf8)
        }
        let table = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.file)) as! [String: Any]
        XCTAssertEqual(table["rows"] as? [[String]], text, "FormatPalette.legible no longer answers what the table says; the reader would draw another colour")
        XCTAssertEqual(table["highlights"] as? [[String]], highlights, "FormatPalette.wash or legible on a highlight changed")
        XCTAssertGreaterThan(text.count, 1000)
        XCTAssertGreaterThan(highlights.count, 1000)
    }
}
