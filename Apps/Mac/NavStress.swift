#if DEBUG
import AppKit
import PerchKit
import PerchUI
import SwiftUI
import WebKit

/// The navigation stress test. In the real main window, on a test notebook, it moves between places, opens
/// task panels and closes them every way a person does: the X, Esc, Cmd+W, with the sidebar toggled or the
/// place changed while a panel is open. It records each time the main window closed, or a panel stayed open,
/// writes the tally as JSON and quits.
///
///     open -n -g -W -a Perch.app --args -perchNavStress <test notebook> <result.json> [-perchNavStressSteps 120] [-perchNavStressSeed 46]
///
/// The notebook is opened without sync, and a test run never reads the Keychain or saves settings, so use
/// a copy of a notebook: closing a panel saves any change it holds.
@MainActor
enum NavStress {
    struct Tally: Codable {
        var runs = 0
        var windowClosed = 0
        var panelStayedOpen = 0
    }

    struct Failure: Codable {
        var step: Int
        var place: String
        var method: String
        var problem: String
    }

    struct Report: Codable {
        var steps: Int
        var notes: Int
        var openTasks: Int
        var tallies: [String: Tally]
        var failures: [Failure]
        /// The windows there were when the run began, and why it stopped early if it did.
        var log: [String] = []
    }

    /// The ways a person closes a task panel.
    enum Method: String, CaseIterable {
        case xButton = "x"
        case escape = "esc"
        case commandW = "cmd-w"
        case sidebarThenEscape = "sidebar+esc"
        case moveThenEscape = "move+esc"
    }

    static func start(shell: MacShell, result: URL) {
        Task { @MainActor in await run(shell: shell, result: result) }
    }

    private static func run(shell: MacShell, result: URL) async {
        let arguments = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        }
        let steps = value("-perchNavStressSteps").flatMap(Int.init) ?? 120
        var random = SplitMix(seed: value("-perchNavStressSeed").flatMap(UInt64.init) ?? 46)
        let model = shell.model

        // The notebook loads and the window appears.
        var log: [String] = []
        // Its own window, made off screen, so the run never shows where the person is working.
        makeWindow(shell: shell)
        if let width = value("-perchNavStressWidth").flatMap(Double.init), let window {
            window.setFrame(NSRect(x: -30_000, y: -30_000, width: width, height: window.frame.height), display: true)
        }
        for _ in 0..<40 where model.tasks.isEmpty { await pause(0.25) }
        await pause(1)

        log += NSApp.windows.map { "window \(type(of: $0)) \(Int($0.frame.width))x\(Int($0.frame.height)) \($0.identifier?.rawValue ?? "-") visible=\($0.isVisible) main=\($0.canBecomeMain) key=\($0.isKeyWindow)" }
        log.append("shell.mainWindow=\(shell.mainWindow != nil) active=\(NSApp.isActive)")
        let notes = model.vault.map { noteFiles(in: $0.root) } ?? []
        // `-perchNavStressScroll`: can the task panel be scrolled with the pointer over a task's details?
        if arguments.contains("-perchNavStressScroll"), let window {
            log += await scrollProbe(model: model, window: window)
            let report = Report(steps: 0, notes: 0, openTasks: model.tasks.filter(\.isOpen).count, tallies: [:], failures: [], log: log)
            try? JSONEncoder().encode(report).write(to: result)
            exit(0)
        }

        // `-perchNavStressNotes`: the note editing test instead of the panel test.
        if arguments.contains("-perchNavStressNotes"), let window, let root = model.vault?.root {
            let report = await NoteStress.run(shell: shell, window: window, notes: notes, root: root,
                                              keys: { key($0, code: $1, flags: $2, in: window) })
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? encoder.encode(report).write(to: result)
            exit(0)
        }

        let places: [(String, Route)] = [("Today", .today), ("Upcoming", .upcoming), ("List", .list), ("Board", .board),
                                         ("Calendar", .calendar), ("Ready", .ready), ("Notes", .folder(""))]
        var tallies: [String: Tally] = [:]
        var failures: [Failure] = []
        var commandWPaths: [String] = []
        // What Cmd+W is in the menu bar: exactly one item should carry it.
        var commandW: [String] = []
        for top in NSApp.mainMenu?.items ?? [] {
            for item in top.submenu?.items ?? [] where item.keyEquivalent == "w" && item.keyEquivalentModifierMask == .command {
                commandW.append(top.title + " > " + item.title)
            }
        }
        log.append("Cmd+W items: \(commandW)")

        for step in 0..<steps {
            let open = model.tasks.filter(\.isOpen)
            guard !open.isEmpty, let window = mainWindow(shell) else {
                log.append("stopped at step \(step): open tasks \(open.count), main window found \(mainWindow(shell) != nil)")
                break
            }

            // Somewhere to be: a task view, the notes, or a note itself.
            let place: (name: String, route: Route)
            if !notes.isEmpty, random.next() % 3 == 0 {
                let note = notes[Int(random.next() % UInt64(notes.count))]
                place = ("note", .file(note))
            } else {
                place = places[Int(random.next() % UInt64(places.count))]
            }
            DebugProbes.mark("step \(step): go to \(place.name)")
            model.route = place.route
            await pause(0.25)

            // A task's panel, as clicking a task opens it.
            DebugProbes.mark("open panel")
            model.selectedTaskID = open[Int(random.next() % UInt64(open.count))].id
            await pause(0.8)

            let method = Method.allCases[Int(random.next() % UInt64(Method.allCases.count))]
            // The panel must still be open, or there's nothing to close: a panel that closed by itself is a
            // finding of its own, and Cmd+W with no panel rightly closes the window.
            // Open means on screen: the panel's X is drawn inside the window.
            if let task = model.selectedTaskID, !panelVisible(in: window, task: task) {
                // Still sliding in? A window parked off every screen may get few animation frames.
                await pause(1.0)
            }
            if let task = model.selectedTaskID, !panelVisible(in: window, task: task) {
                let frame = model.selectedTaskID.flatMap { DebugProbes.taskPanelClose[$0] }.map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "none"
                failures.append(.init(step: step, place: place.name, method: method.rawValue, problem: "the panel is selected but not on screen: X at \(frame), window content \(Int(window.contentView?.bounds.width ?? 0)) wide"))
            }
            guard model.selectedTaskID != nil else {
                failures.append(.init(step: step, place: place.name, method: method.rawValue, problem: "the panel closed by itself"))
                DebugProbes.mark("HID ITSELF")
                continue
            }
            DebugProbes.mark("close by \(method.rawValue)")
            switch method {
            case .xButton:
                guard let point = closeButton(in: window, task: model.selectedTaskID) else {
                    failures.append(.init(step: step, place: place.name, method: method.rawValue, problem: "no Close button found"))
                    model.selectedTaskID = nil
                    continue
                }
                click(at: point, in: window)
            case .escape:
                key("\u{1b}", code: 53, in: window)
            case .commandW:
                let before = DebugProbes.closeCommands
                let responder = window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
                key("w", code: 13, flags: .command, in: window)
                let runsNow = DebugProbes.closeCommands - before
                await pause(0.45)
                let runsLater = DebugProbes.closeCommands - before
                commandWPaths.append("taken by \(lastKeyTaker), Close ran \(runsNow) then \(runsLater) times, window closed \(mainWindow(shell)?.isVisible != true), saw: \(DebugProbes.lastClose)")
            case .sidebarThenEscape:
                NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
                await pause(0.35)
                NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
                await pause(0.35)
                key("\u{1b}", code: 53, in: window)
            case .moveThenEscape:
                model.route = places[Int(random.next() % UInt64(places.count))].1
                await pause(0.35)
                key("\u{1b}", code: 53, in: window)
            }
            await pause(0.45)

            var tally = tallies[method.rawValue, default: Tally()]
            tally.runs += 1
            if mainWindow(shell)?.isVisible != true {
                tally.windowClosed += 1
                failures.append(.init(step: step, place: place.name, method: method.rawValue, problem: "the main window closed"))
                reopen(shell)
                await pause(0.9)
            } else if model.selectedTaskID != nil {
                tally.panelStayedOpen += 1
                failures.append(.init(step: step, place: place.name, method: method.rawValue, problem: "the panel stayed open"))
                model.selectedTaskID = nil
                await pause(0.3)
            }
            tallies[method.rawValue] = tally
        }

        log += Dictionary(grouping: commandWPaths, by: { $0 }).map { "\($0.value.count)x \($0.key)" }.sorted()
        // `-perchNavStressHold <seconds> <file>`: show the List with no panel, write the window's number to the
        // file and wait, so a picture can be taken of the real window (title bar and all) where it is parked.
        if let seconds = value("-perchNavStressHold").flatMap(Double.init), let file = arguments.firstIndex(of: "-perchNavStressHold").flatMap({ arguments.indices.contains($0 + 2) ? arguments[$0 + 2] : nil }) {
            model.selectedTaskID = nil
            model.route = .list
            // `-perchNavStressHoldPanel` holds with the first open task's panel showing.
            if arguments.contains("-perchNavStressHoldPanel") { model.selectedTaskID = model.tasks.first(where: \.isOpen)?.id }
            await pause(1.5)
            if let window = mainWindow(shell) {
                try? String(window.windowNumber).write(toFile: file, atomically: true, encoding: .utf8)
                await pause(seconds)
            }
        }

        // The control: with no panel open, Cmd+W still closes the window, as on any Mac.
        model.selectedTaskID = nil
        await pause(0.5)
        if let window = mainWindow(shell) {
            key("w", code: 13, flags: .command, in: window)
            await pause(0.6)
            log.append("control, Cmd+W with no panel closed the window: \(mainWindow(shell)?.isVisible != true)")
        }

        let report = Report(steps: steps, notes: notes.count, openTasks: model.tasks.filter(\.isOpen).count,
                            tallies: tallies, failures: failures, log: log + DebugProbes.timeline)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(report).write(to: result)
        exit(0)
    }

    // MARK: Helpers

    private static var window: NSWindow?

    /// Perch's main view in a window of the test's own, far off every screen, with SwiftUI's toolbar and title
    /// carried into it. SwiftUI's own window group makes its first window only when the app comes to the
    /// front, which a run in the background never does. Clicks and keys are sent to it directly.
    private static func makeWindow(shell: MacShell) {
        let controller = NSHostingController(rootView: MacRootView(shell: shell).perchThemed(ThemeStore.shared).frame(minWidth: 860, minHeight: 540))
        controller.sceneBridgingOptions = [.toolbars, .title]
        let made = NSWindow(contentViewController: controller)
        made.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        made.identifier = NSUserInterfaceItemIdentifier("main-NavStress")
        made.isReleasedWhenClosed = false
        made.isRestorable = false
        made.setFrame(NSRect(x: -30_000, y: -30_000, width: 1367, height: 760), display: true)
        made.orderFront(nil)
        window = made
        shell.mainWindow = made
    }

    /// Brings the test's window back after something closed it, still off screen.
    private static func reopen(_ shell: MacShell) {
        guard let window else { return }
        park(window)
        window.orderFront(nil)
        shell.mainWindow = window
    }

    private static func park(_ window: NSWindow) {
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// The test's window, while it is open.
    private static func mainWindow(_ shell: MacShell) -> NSWindow? {
        window.flatMap { $0.isVisible ? $0 : nil }
    }

    /// Notes to open: Markdown files outside Tasks folders and hidden folders.
    private static func noteFiles(in root: URL) -> [String] {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        var paths: [String] = []
        let prefix = root.standardizedFileURL.path + "/"
        for case let url as URL in walker where url.pathExtension == "md" {
            let path = url.standardizedFileURL.path.replacingOccurrences(of: prefix, with: "")
            if !path.split(separator: "/").contains("Tasks") { paths.append(path) }
            if paths.count >= 400 { break }
        }
        return paths.sorted()
    }

    /// The centre of the task panel's Close button, in window coordinates: the right-most "Close" button.
    /// Opens the open task with the longest details, then scrolls down with the pointer over them, as a mouse
    /// wheel or trackpad does, and says whether the panel moved.
    private static func scrollProbe(model: AppModel, window: NSWindow) async -> [String] {
        guard let task = model.tasks.filter(\.isOpen).max(by: { $0.details.count < $1.details.count }) else { return ["no task"] }
        model.route = .list
        model.selectedTaskID = task.id
        await pause(2.5)
        func webViews(_ view: NSView) -> [WKWebView] { (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap(webViews) }
        guard let details = window.contentView.map(webViews)?.first(where: { $0.enclosingScrollView != nil }),
              let panel = details.enclosingScrollView else { return ["no details view in a scroll view"] }
        let before = panel.contentView.bounds.origin.y
        let room = (panel.documentView?.frame.height ?? 0) - panel.contentView.bounds.height
        for _ in 0..<8 {
            if let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -40, wheel2: 0, wheel3: 0),
               let event = NSEvent(cgEvent: cg) {
                details.scrollWheel(with: event)
            }
            await pause(0.05)
        }
        await pause(0.6)
        let after = panel.contentView.bounds.origin.y
        return ["scroll: details \(task.details.count) characters, room to scroll \(Int(room)) pt, panel moved \(Int(after - before)) pt"]
    }

    /// Whether the panel is on screen: its X is drawn, inside the window.
    private static func panelVisible(in window: NSWindow, task: String) -> Bool {
        guard let frame = DebugProbes.taskPanelClose[task], frame.width > 0, let content = window.contentView else { return false }
        return content.bounds.insetBy(dx: -1, dy: -1).contains(NSPoint(x: frame.midX, y: frame.midY))
    }

    /// The centre of the task panel's X, in window coordinates. The button reports its own frame in debug
    /// builds (SwiftUI builds its accessibility tree only for a real assistive app, so it can't be searched).
    private static func closeButton(in window: NSWindow, task: String?) -> NSPoint? {
        guard let task, let frame = DebugProbes.taskPanelClose[task], frame.width > 0, let content = window.contentView else { return nil }
        return NSPoint(x: frame.midX, y: content.bounds.height - frame.midY)
    }

    // Clicks and keys go straight to the window, as AppKit hands them to the window in front. That doesn't
    // need Perch to be the app in front, which macOS 26 won't let a test make it.

    private static func click(at point: NSPoint, in window: NSWindow) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                                              pressure: type == .leftMouseDown ? 1 : 0) {
                window.sendEvent(event)
            }
        }
    }

    /// A key press in AppKit's order: the window's key equivalents (SwiftUI's keyboard shortcuts, such as
    /// the panel's X on Esc), then the menu bar's (Cmd+W is File, Close), then the window itself.
    /// Who took the last key press: "window" (a view in it), "menu", or "none".
    static var lastKeyTaker = ""

    static func key(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags = [], in window: NSWindow) {
        func event(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                             windowNumber: window.windowNumber, context: nil, characters: characters,
                             charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
        }
        guard let down = event(.keyDown), let up = event(.keyUp) else { return }
        if window.performKeyEquivalent(with: down) {
            lastKeyTaker = "window"
        } else if NSApp.mainMenu?.performKeyEquivalent(with: down) == true {
            lastKeyTaker = "menu"
        } else {
            lastKeyTaker = "none"
            window.sendEvent(down)
        }
        window.sendEvent(up)
    }

    /// A small seeded random source, so a run can be repeated exactly.
    struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}
#endif
