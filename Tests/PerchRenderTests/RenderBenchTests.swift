import AppKit
import PerchKit
import XCTest

/// Timings for the reader page. Skipped unless `PERCH_RENDER_BENCH=1`; `scripts/render-bench.sh` runs it.
@MainActor
final class RenderBenchTests: XCTestCase {
    private func ms(_ interval: TimeInterval) -> String { String(format: "%.0f", interval * 1000) }

    func testTimings() async throws {
        guard ProcessInfo.processInfo.environment["PERCH_RENDER_BENCH"] == "1" else { throw XCTSkip("Set PERCH_RENDER_BENCH=1 to measure.") }
        let notes = ["bench-small.md", "bench-typical.md", "stress-200-code-blocks.md", "stress-5000-lines.md", "bench-5-mermaid.md"]
        var rows = ["note | load→ready | cold: text shown | cold: all drawn | warm edit: text shown | warm edit: all drawn | same text again"]
        // One throwaway page first, so the first row doesn't pay for starting WebKit's processes.
        let first = RenderPage(newWebView: true)
        try await first.ready()
        first.close()
        for name in notes {
            let markdown = try Checkout.fixture(name)
            var cells: [[TimeInterval]] = []
            for _ in 0..<3 {
                // A web view of its own, so "load→ready" is what opening a note without a spare page costs.
                // With the notebook's pictures to hand: ones that can't be found cost a second layout.
                let page = RenderPage(vaultRoot: Checkout.fixtures, newWebView: true)
                try await page.ready()
                let load = page.readyAfter ?? 0
                let cold = try await timeRender(page, markdown)
                // Let the first render's layout finish, as a frame would, so the edit is timed on its own.
                _ = try await page.int("document.documentElement.scrollHeight")
                // An edit as the split preview sees it: one more word in a paragraph near the middle.
                let lines = markdown.components(separatedBy: "\n")
                var edited = lines
                let target = (lines.count / 2..<lines.count).first { !lines[$0].isEmpty && lines[$0].first!.isLetter } ?? lines.count - 1
                edited[target] += " edited"
                let warm = try await timeRender(page, edited.joined(separator: "\n"))
                let again = try await timeRender(page, edited.joined(separator: "\n"))
                cells.append([load, cold.shown, cold.settled, warm.shown, warm.settled, again.settled])
                page.close()
            }
            let median = (0..<6).map { column in cells.map { $0[column] }.sorted()[1] }
            rows.append(name + " | " + median.map(ms).joined(separator: " | "))
        }
        print("\nRENDER BENCH (ms, median of 3)\n" + rows.joined(separator: "\n") + "\n")
    }

    /// Time until the page says the text is up, and until everything in it is drawn.
    private func timeRender(_ page: RenderPage, _ markdown: String) async throws -> (shown: TimeInterval, settled: TimeInterval) {
        page.clearMessages()
        let start = Date()
        var shown: TimeInterval = 0
        let watch = Task { @MainActor in
            try await page.wait("rendered") { !page.messages(ofType: "rendered").isEmpty }
            shown = Date().timeIntervalSince(start)
        }
        try await page.call("render", ["markdown": markdown, "basePath": "note.md"])
        try await page.settle()
        let settled = Date().timeIntervalSince(start)
        if ProcessInfo.processInfo.environment["PERCH_RENDER_BENCH_DETAIL"] == "1" {
            print("  detail:", (try? await page.string("JSON.stringify(window.Perch.timing ?? null)")) ?? "")
        }
        try await watch.value
        return (min(shown, settled), settled)
    }
}

/// Pictures of fixtures as the page draws them. Skipped unless `PERCH_RENDER_STILLS=<folder>`.
/// `PERCH_WEB_ROOT` picks which build of the page to draw with, for before-and-after pairs.
@MainActor
final class RenderStillTests: XCTestCase {
    func testStills() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let folder = environment["PERCH_RENDER_STILLS"] else { throw XCTSkip("Set PERCH_RENDER_STILLS to a folder.") }
        let names = (environment["PERCH_RENDER_STILL_NOTES"] ?? "formatting.md").split(separator: ",").map(String.init)
        let width = CGFloat(Double(environment["PERCH_RENDER_STILL_WIDTH"] ?? "") ?? 760)
        let themes = (environment["PERCH_RENDER_STILL_THEMES"] ?? "perch-light,perch-dark").split(separator: ",").map(String.init)
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        for theme in themes {
            guard let palette = ([ThemePresets.perchLight, ThemePresets.perchDark] + ThemePresets.all).first(where: { $0.id == theme }) else { continue }
            for name in names {
                let markdown = try Checkout.fixture(name)
                // Tall enough for the whole note, so one picture shows all of it.
                let probe = RenderPage(width: width, height: 800, vaultRoot: Checkout.fixtures)
                try await probe.render(markdown, ["appearance": palette.appearance])
                let height = min(CGFloat(try await probe.int("document.documentElement.scrollHeight")), 6000)
                probe.close()
                let page = RenderPage(width: width, height: height, vaultRoot: Checkout.fixtures)
                try await page.render(markdown, ["appearance": palette.appearance])
                try await Task.sleep(nanoseconds: 500_000_000)
                let image = try await page.webView.takeSnapshot(configuration: nil)
                if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
                    try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name.replacingOccurrences(of: ".md", with: ""))-\(theme)-\(Int(width)).png"))
                }
                page.close()
            }
        }
    }
}
