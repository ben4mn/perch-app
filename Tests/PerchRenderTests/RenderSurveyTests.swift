import XCTest
@testable import PerchKit

/// Draws every note in a notebook through the real reader page and lists the ones that look wrong: a table
/// left as text, an error box, or Markdown's own marks left showing. Opt-in, for finding problems in a
/// real notebook; it reads only the copy you name and writes only the report:
///
///     PERCH_RENDER_SURVEY=/path/to/notebook-copy PERCH_RENDER_SURVEY_OUT=/tmp/survey.json \
///       swift test --filter RenderSurveyTests
@MainActor
final class RenderSurveyTests: XCTestCase {
    struct Finding: Codable {
        var path: String
        var kind: String
        var sample: String
    }

    func testSurveyANotebook() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let folder = environment["PERCH_RENDER_SURVEY"] else { throw XCTSkip("Set PERCH_RENDER_SURVEY to a notebook copy.") }
        let root = URL(fileURLWithPath: folder)
        let out = URL(fileURLWithPath: environment["PERCH_RENDER_SURVEY_OUT"] ?? NSTemporaryDirectory() + "perch-render-survey.json")
        let page = RenderPage(width: 760, height: 800, vaultRoot: root)
        defer { page.close() }

        var findings: [Finding] = []
        var drawn = 0
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        let prefix = root.standardizedFileURL.path + "/"
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "md", let markdown = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let path = url.standardizedFileURL.path.replacingOccurrences(of: prefix, with: "")
            try await page.render(markdown, ["basePath": path])
            drawn += 1
            let found = try await page.js(Self.inspect) as? [[String: String]] ?? []
            findings += found.map { Finding(path: path, kind: $0["kind"] ?? "?", sample: $0["sample"] ?? "") }
            page.clearMessages()
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(findings).write(to: out)
        print("RENDER SURVEY: \(drawn) notes drawn, \(findings.count) findings, report at \(out.path)")
    }

    /// Looks over the drawn page, outside code, for what a reader shouldn't see.
    private static let inspect = """
    const root = document.getElementById('root');
    const findings = [];
    const add = (kind, text) => { if (findings.length < 12) findings.push({ kind, sample: String(text).trim().slice(0, 160) }); };
    for (const error of root.querySelectorAll('.render-error')) add('error box', error.textContent);
    // Text outside code, maths and diagrams.
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        return node.parentElement.closest('pre, code, .math, .diagram, .render-error, script, style')
          ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT;
      }
    });
    const blocks = new Map();
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      const block = node.parentElement.closest('p, li, td, th, h1, h2, h3, h4, h5, h6, blockquote, dd, dt') || node.parentElement;
      blocks.set(block, (blocks.get(block) || '') + node.textContent);
    }
    for (const [block, text] of blocks) {
      if (/(^|\\n)\\s*\\|?\\s*:?-{3,}:?\\s*\\|/.test(text) || /\\|\\s*:?-{3,}:?\\s*\\|/.test(text)) add('table left as text', text);
      else if ((text.match(/\\|/g) || []).length >= 4 && block.tagName === 'P' && /\\n/.test(block.innerText)) add('pipes in a paragraph', text);
      if (/\\*\\*[^*\\s][^*]*\\*\\*/.test(text)) add('bold marks showing', text);
      if (/(^|[^\\\\])\\[\\[[^\\]]+\\]\\]/.test(text)) add('wiki link left as text', text);
      if (/\\]\\((https?:|\\.|\\/)[^)\\s]*\\)/.test(text)) add('link syntax showing', text);
      if (/^\\s*#{1,6}\\s+\\S/.test(text) && block.tagName === 'P') add('heading marks showing', text);
      if (/==[^=\\s][^=]*==/.test(text)) add('highlight marks showing', text);
      if (/\\[![a-z]+\\]/i.test(text)) add('callout left as text', text);
      if (/\\[\\^[^\\]]+\\]/.test(text)) add('footnote left as text', text);
      if (/(^|\\n)\\s*[-*+] \\[[ xX]\\]/.test(text)) add('task box left as text', text);
      if (/~~[^~\\s][^~]*~~/.test(text)) add('strike marks showing', text);
      if (/\\$\\$/.test(text)) add('maths marks showing', text);
      if (/<\\/?(details|summary|div|span|br|sup|sub|kbd|mark|u)\\b[^>]*>/i.test(text)) add('HTML tag showing', text);
      if (/(^|\\s)\\*[^*\\s][^*]*\\*(?=[A-Za-z])/.test(text) || /(^|\\s)_[^_\\s][^_]*_(?=[A-Za-z])/.test(text)) add('italic marks showing', text);
    }
    return findings;
    """
}
