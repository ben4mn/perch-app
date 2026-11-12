@testable import PerchKit
import XCTest

/// The mentions search (names of other notes found in a note's text) and where a clicked link may make a note.
final class LinkSearchTests: XCTestCase {
    private struct Random {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(bound))
        }
    }

    private let vocabulary = ["plan", "Plan", "PLAN", "garden", "Garden shed", "shed", "ha ha", "ha", "naïve", "Zürich", "C++", "my_note", "re-do",
                              "2026", "Q3 plan", "plan Q3", "the", "of", "İstanbul", "straße", "note-taking", "(draft)", "a.b", "日本語", "émigré"]
    private let glue = [" ", " ", " ", "\n", ", ", ". ", "-", "_", "", " `", "` ", "\n```\n", " [[", "]] ", "|", "\n\n", "’s ", " (", ") "]

    private func index() -> LinkIndex {
        let titles = ["Plan", "Garden shed", "shed", "ha ha", "naïve", "Zürich", "C++ notes", "my_note", "re-do", "Q3 plan", "plan Q3", "Garden",
                      "İstanbul", "Straße", "note-taking", "(draft) plan", "a.b", "日本語", "Émigré", "Plan 2026", "2026"]
        return LinkIndex(entries: titles.enumerated().map { (VaultFile(path: "f\($0.offset % 3)/\($0.element).md"), nil) })
    }

    func testTheQuickSearchAnswersExactlyWhatSearchingForEveryNameDoes() {
        let links = index()
        var random = Random(state: 7)
        for round in 0..<400 {
            var text = round % 5 == 0 ? "---\naliases: [Plan, shed]\n---\n" : ""
            for _ in 0..<(5 + random.next(60)) { text += vocabulary[random.next(vocabulary.count)] + glue[random.next(glue.count)] }
            let quick = links.mentions(in: text, excluding: round % 4 == 0 ? "f0/Plan.md" : nil)
            let reference = links.mentionsBySearchingForEveryName(in: text, excluding: round % 4 == 0 ? "f0/Plan.md" : nil)
            XCTAssertEqual(quick, reference, "round \(round): \(text.debugDescription)")
            if quick != reference { return }
        }
    }

    func testALongNoteInABigNotebookIsSearchedQuickly() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Fixtures/Rendering/stress-5000-lines.md"), encoding: .utf8)
        let words = Array(Set(text.split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 5 })).sorted()
        var entries: [(file: VaultFile, text: String?)] = (0..<3000).map { (VaultFile(path: "notes/Project Zebra \($0).md"), nil) }
        entries += words.prefix(40).map { (VaultFile(path: "words/\($0).md"), nil) }
        let links = LinkIndex(entries: entries)
        let start = Date()
        let found = links.mentions(in: text, excluding: "x.md")
        let took = Date().timeIntervalSince(start)
        XCTAssertGreaterThan(found.count, 1000, "the note is full of these words")
        // Searching for every name took 20 seconds here. Generous, for a busy machine and a debug build.
        XCTAssertLessThan(took, 3, "5,000 lines against 3,040 titles")
        print(String(format: "mentions: 5,000 lines, 3,040 titles, %d found in %.0f ms", found.count, took * 1000))
        // A cancelled search stops and says nothing.
        XCTAssertEqual(links.mentions(in: text, excluding: "x.md", isCancelled: { true }), [])
    }

    func testAClickedLinkCanOnlyMakeANoteInsideTheNotebook() {
        XCTAssertEqual(WikiLinks.pathForNewNote(target: "New idea", besideNoteIn: "Daily"), "Daily/New idea.md")
        XCTAssertEqual(WikiLinks.pathForNewNote(target: "New idea", besideNoteIn: ""), "New idea.md")
        XCTAssertEqual(WikiLinks.pathForNewNote(target: "Sub/New idea.md", besideNoteIn: "Daily"), "Daily/Sub/New idea.md")
        XCTAssertEqual(WikiLinks.pathForNewNote(target: "Plan#Next steps", besideNoteIn: "Daily"), "Daily/Plan.md")
        for hostile in ["../Projects/Plan", "..", "../../../tmp/made-by-a-click", "/etc/passwd", "a/../../b", "./x", "a//b", ".git/config", "a/.hidden",
                        "", "   ", "#heading", "a\\..\\b", "line\nbreak", "nul\u{0}l", " lead/ trail ", String(repeating: "x", count: 300)] {
            XCTAssertNil(WikiLinks.pathForNewNote(target: hostile, besideNoteIn: "Daily"), hostile.debugDescription)
        }
    }
}
