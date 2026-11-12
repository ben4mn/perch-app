#if DEBUG
import AppKit
import PerchKit
import PerchUI

/// The note editing test, run by NavStress with `-perchNavStressNotes`. For small, medium and large notes it
/// times what a person waits for: the note's preview after opening it, the editor after Cmd+E, the preview
/// catching up while they type at a steady pace (and how long each keystroke holds the app), the preview
/// after it is turned back on, and the reader after Done.
@MainActor
enum NoteStress {
    struct Typing: Codable {
        var keystrokes = 0
        /// From a keystroke until the preview shows it, in seconds.
        var medianWait = 0.0
        var slowestWait = 0.0
        /// Keystrokes the preview never showed before typing stopped and it settled.
        var neverShown = 0
        var renders = 0
        /// How long a keystroke held the main thread, in milliseconds: over 16 drops a frame.
        var slowestKeystrokeMs = 0.0
        var keystrokesOver16ms = 0
    }

    struct Note: Codable {
        var path: String
        var bytes: Int
        var openToPreview: Double?
        var editToEditor: Double?
        var typing: Typing?
        var previewOnToPreview: Double?
        var doneToReader: Double?
        var problems: [String] = []
    }

    struct Report: Codable {
        var notes: [Note]
    }

    static func run(shell: MacShell, window: NSWindow, notes: [String], root: URL,
                    keys: (String, UInt16, NSEvent.ModifierFlags) -> Void) async -> Report {
        // Notes open in the reader, and editing shows the preview beside the editor, for this run only.
        var volatile = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        volatile[ReadingSettings.Key.openIn] = "read"
        volatile[ReadingSettings.Key.editWithPreview] = true
        UserDefaults.standard.setVolatileDomain(volatile, forName: UserDefaults.argumentDomain)

        let model = shell.model
        var results: [Note] = []
        for path in pick(notes, root: root) {
            var note = Note(path: path, bytes: size(of: path, in: root))
            // Open it, and wait for the reader.
            model.selectedTaskID = nil
            var started = Date()
            model.route = .file(path)
            note.openToPreview = await rendered(after: started)
            if note.openToPreview == nil { note.problems.append("the preview never drew after opening") }
            await pause(0.6)

            // Edit (Cmd+E): the editor, with the preview beside it.
            started = Date()
            keys("e", 14, .command)
            var editor: NSTextView?
            for _ in 0..<150 {
                editor = window.contentView.flatMap(EditorDebug.editor)
                if editor != nil { break }
                await pause(0.02)
            }
            if let editor {
                note.editToEditor = Date().timeIntervalSince(started)
                await pause(0.6)
                note.typing = await type(into: editor, window: window)
            } else {
                note.problems.append("no editor after Cmd+E")
            }

            // The preview off and on again.
            DebugProbes.togglePreview?()
            await pause(0.6)
            started = Date()
            DebugProbes.togglePreview?()
            note.previewOnToPreview = await rendered(after: started)
            await pause(0.6)

            // Done (Cmd+E): back to the reader.
            started = Date()
            keys("e", 14, .command)
            note.doneToReader = await rendered(after: started)
            await pause(0.8)
            results.append(note)
        }
        return Report(notes: results)
    }

    /// Types a line at the end of the note at about 12 characters a second, as key presses, then measures
    /// how long each one waited for the preview.
    private static func type(into editor: NSTextView, window: NSWindow) async -> Typing {
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        let line = Array(" stress typing to see the preview keep up")
        let rendersBefore = DebugProbes.renderSent.count
        var strokes: [(at: Date, length: Int, ms: Double)] = []
        for character in ["\n"] + line.map(String.init) {
            let code: UInt16 = character == "\n" ? 36 : 0
            let at = Date()
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                windowNumber: window.windowNumber, context: nil, characters: character == "\n" ? "\r" : character,
                                                charactersIgnoringModifiers: character == "\n" ? "\r" : character, isARepeat: false, keyCode: code) {
                    window.sendEvent(event)
                }
            }
            strokes.append((at, (editor.string as NSString).length, Date().timeIntervalSince(at) * 1000))
            await pause(0.083)
        }
        await pause(1.5)

        var typing = Typing()
        typing.keystrokes = strokes.count
        typing.renders = DebugProbes.renderSent.count - rendersBefore
        typing.slowestKeystrokeMs = strokes.map(\.ms).max() ?? 0
        typing.keystrokesOver16ms = strokes.filter { $0.ms > 16 }.count
        let sent = DebugProbes.renderSent
        let drawn = DebugProbes.rendered
        var waits: [Double] = []
        for stroke in strokes {
            // The first render sent after the keystroke with at least its text, and the reader's answer to it.
            guard let render = sent.first(where: { $0.at >= stroke.at && $0.length >= stroke.length }),
                  let shown = drawn.first(where: { $0 >= render.at }) else {
                typing.neverShown += 1
                continue
            }
            waits.append(shown.timeIntervalSince(stroke.at))
        }
        waits.sort()
        typing.medianWait = waits.isEmpty ? 0 : waits[waits.count / 2]
        typing.slowestWait = waits.last ?? 0
        return typing
    }

    /// Seconds until the reader answers "rendered" after a moment, or nil after three seconds.
    private static func rendered(after start: Date) async -> Double? {
        for _ in 0..<300 {
            if let first = DebugProbes.rendered.first(where: { $0 > start }) { return first.timeIntervalSince(start) }
            await pause(0.01)
        }
        return nil
    }

    /// Three small notes, three medium and three large, so the times cover the range.
    private static func pick(_ notes: [String], root: URL) -> [String] {
        // `-perchNavStressNote <part of a path>` picks that note alone, for profiling.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-perchNavStressNote"), arguments.indices.contains(index + 1) {
            return notes.filter { $0.contains(arguments[index + 1]) }.prefix(1).map { $0 }
        }
        let sized = notes.map { ($0, size(of: $0, in: root)) }.filter { $0.1 > 200 }
        let small = sized.filter { $0.1 < 3_000 }.prefix(3)
        let medium = sized.filter { $0.1 >= 6_000 && $0.1 < 25_000 }.prefix(3)
        let large = sized.sorted { $0.1 > $1.1 }.prefix(3)
        return (small + medium + large).map(\.0)
    }

    private static func size(of path: String, in root: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(path).path)[.size] as? Int) ?? 0
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
#endif
