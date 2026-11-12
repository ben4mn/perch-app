import XCTest
@testable import PerchKit

/// Typing in a note: the preview keeps up while you type, and a long note doesn't make each keystroke wait.
/// Measured by the Mac's note stress test, which found the preview frozen until typing paused (2 to 4 s)
/// and every keystroke in a 490 KB transcript holding the app for 120 to 290 ms.
final class NoteEditingSpeedTests: XCTestCase {
    // MARK: The same text

    func testTheSameTextIsTheSame() {
        XCTAssertTrue(TextIdentity.same("Plain note", "Plain note"))
        XCTAssertFalse(TextIdentity.same("Plain note", "Plain note."))
        XCTAssertFalse(TextIdentity.same("abc", "abd"))
        XCTAssertTrue(TextIdentity.same("", ""))
    }

    func testAChangeOnlyInHowALetterIsWrittenIsStillAChange() {
        // "é" as one character and as e plus an accent: Swift's == calls them equal, but the file's bytes
        // differ, so saving it is right.
        XCTAssertFalse(TextIdentity.same("caf\u{E9}", "cafe\u{301}"))
    }

    func testTextFromTheEditorComparesQuickly() {
        // A long transcript, mostly English with the odd curly quote and emoji, as the editor hands it over.
        let line = "Speaker 2: \u{201C}We tried that in Q3\u{201D} and it worked \u{1F44D} for the team, so let's keep it.\n"
        let long = String(repeating: line, count: 6_000)
        let fromEditor = TextIdentity.native(NSMutableString(string: long) as String)
        let typed = fromEditor + "x"
        measure {
            for _ in 0..<20 {
                XCTAssertFalse(TextIdentity.same(fromEditor, typed))
                XCTAssertTrue(TextIdentity.same(fromEditor, long))
            }
        }
    }

    // MARK: Finding lines

    /// A long transcript held the way the editor holds its text.
    private var transcript: NSMutableString {
        let line = "Speaker 2: \u{201C}We tried that in Q3\u{201D} and it worked \u{1F44D} for the team.\n"
        return NSMutableString(string: String(repeating: line, count: 6_000))
    }

    func testLinesAreCountedTheSameInBlocks() {
        // Lines that end exactly on a block's edge, an empty note, and a location past the end.
        let text = NSMutableString(string: String(repeating: "a", count: 4095) + "\n" + "b\n\nc")
        XCTAssertEqual(MarkdownEditing.lineNumber(of: 4095, in: text), 0)
        XCTAssertEqual(MarkdownEditing.lineNumber(of: 4096, in: text), 1)
        XCTAssertEqual(MarkdownEditing.lineNumber(of: text.length + 50, in: text), 3)
        XCTAssertEqual(MarkdownEditing.location(ofLine: 1, in: text), 4096)
        XCTAssertEqual(MarkdownEditing.location(ofLine: 3, in: text), 4099)
        XCTAssertEqual(MarkdownEditing.lineNumber(of: 10, in: NSString()), 0)
    }

    func testFindingALineNearTheEndOfALongNoteIsQuick() {
        let text = transcript
        XCTAssertEqual(MarkdownEditing.lineNumber(of: text.length, in: text), 6_000)
        let start = Date()
        for _ in 0..<30 {
            _ = MarkdownEditing.lineNumber(of: text.length - 10, in: text)
            _ = MarkdownEditing.location(ofLine: 5_990, in: text)
        }
        // Thirty of each, as a few seconds of scrolling and typing ask for: well under a frame each.
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.15)
    }

    // MARK: Pacing the preview

    /// Someone types at a steady pace; the reader takes `cost` to draw each render.
    private func simulate(every gap: Double, for duration: Double, cost: Double) -> (renders: Int, longestStale: Double, last: Double) {
        var pacer = RenderPacer()
        var time = 0.0
        var due: Double?
        var renders = 0
        var shownAt: [Double] = []
        var typedAt: [Double] = []
        while time <= duration + 2 {
            if time <= duration, typedAt.last.map({ time - $0 >= gap - 1e-9 }) ?? true {
                typedAt.append(time)
                if due == nil, let wait = pacer.changed(at: time) { due = time + wait }
            }
            if let fire = due, time >= fire - 1e-9 {
                due = nil
                renders += 1
                pacer.sent(at: time)
                pacer.drawn(cost: cost)
                shownAt.append(time + cost)
            }
            time += 0.001
        }
        // How long any keystroke waited for a render sent after it to be drawn.
        var longest = 0.0
        for typed in typedAt {
            if let shown = shownAt.first(where: { $0 >= typed + cost - 1e-9 && $0 - cost >= typed - 1e-9 }) {
                longest = max(longest, shown - typed)
            }
        }
        return (renders, longest, shownAt.last ?? 0)
    }

    func testThePreviewKeepsUpWhileSomeoneTypes() {
        // Twelve characters a second for three seconds, in an ordinary note.
        let run = simulate(every: 0.083, for: 3, cost: 0.02)
        XCTAssertGreaterThanOrEqual(run.renders, 18, "it draws as they type, not once they stop")
        XCTAssertLessThan(run.longestStale, 0.25, "no keystroke waits more than a quarter of a second to show")
    }

    func testTheLastKeystrokeAlwaysShows() {
        let run = simulate(every: 0.083, for: 1, cost: 0.02)
        XCTAssertLessThan(run.last, 1 + 0.25)
    }

    func testASlowNoteDrawsLessOftenRatherThanFallingBehind() {
        // A huge note whose reader takes 0.4 s a render: it draws about every 0.6 s, not after every key.
        let run = simulate(every: 0.083, for: 3, cost: 0.4)
        XCTAssertLessThanOrEqual(run.renders, 7)
        XCTAssertGreaterThanOrEqual(run.renders, 4)
    }

    func testOneKeyAfterAPauseShowsAlmostAtOnce() {
        var pacer = RenderPacer()
        pacer.sent(at: 0)
        pacer.drawn(cost: 0.02)
        XCTAssertEqual(pacer.changed(at: 5) ?? 1, RenderPacer.soonest, accuracy: 0.001)
    }

    func testARenderCalledOffLetsTheNextChangeAskAgain() {
        // The reader went away before the waiting render was sent: later typing must still be drawn.
        var pacer = RenderPacer()
        XCTAssertNotNil(pacer.changed(at: 0))
        pacer.cancelled()
        XCTAssertNotNil(pacer.changed(at: 0.02))
    }

    func testAChangeWhileARenderIsWaitingJoinsIt() {
        var pacer = RenderPacer()
        XCTAssertNotNil(pacer.changed(at: 0))
        XCTAssertNil(pacer.changed(at: 0.01), "the waiting render will send the newest text")
        pacer.sent(at: 0.04)
        XCTAssertNotNil(pacer.changed(at: 0.05))
    }
}
