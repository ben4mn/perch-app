#if DEBUG
import AppKit
import PerchKit
import PerchUI
import SwiftUI
import UniformTypeIdentifiers

/// Draws the notch for the debug snapshot runner, on a stand-in desktop, in any state and at any
/// moment of its opening. Nothing here shows a window, starts a clock, plays a sound or saves a setting.
///
///     notchscreen:<width>[:nonotch][:dark]   the desktop the following steps are drawn on (default 1470, notched, light)
///     notchclosed | notchclosed:bare         at rest, with or without today's counts
///     notchpeek                              swollen under the pointer
///     notchframe:<-0.1...1.1>                the opening held at that progress; beyond the ends is a spring's overshoot
///     notchmode:workspace|week|insights|clips
///     notchmode:clips:<text|links|images|files>  Clips with stand-in clips, filtered to one kind
///     notchmode:clips:hover|prompt|empty|off     the first card under the pointer, a prompt at the foot,
///                                                nothing kept yet, Clips turned off
///     notchlive:focus|noroom|paused|reminder|agent|focusdone|event
///     notchdrag:<card>[:<points>]            a card held mid-reorder
///     notchcomplete:<0...1>                  the first task mid-completion, its burst at that progress
///     notchfocus:running|paused              the open panel with a session under way
///     notchopen:prompt                       the open panel with a prompt across its foot
///     notchready[:busy]                      the Agents card with the notebook's Ready to tick, each proposal
///                                            given a time, a session and a status (busy: with agents here too)
///     notch:Today|Focus|Notepad|Clips        the old names, kept working
///
/// Moments of a movement, for frames of a clip, each on the curve the app animates it with (`Motion`):
///
///     notchpeek:<0...1>                      the swell under the pointer held part-way
///     notchmove:open:<seconds>               the pointer resting on the notch: the swell, then the panel opening
///                                            (after `NotchHover.openDelay`) with its content arriving item by item
///     notchmove:close:<seconds>              the panel going back, the counts returning
///     notchmove:prompt|promptaway:<seconds>[:reminder|agent|event|focusdone]
///                                            a prompt dropping out of the closed notch, or going back in
///     notchmove:live|liveaway:<seconds>[:<elapsed>]  the focus timer widening the closed notch, or leaving it,
///                                            <elapsed> seconds into a 25-minute session
///     notchtick:<seconds>[:<done>]           the open panel, its first task's tick held that long after the click
///                                            (negative: the pointer is still arriving); <done> tasks before it are
///                                            already ticked, in memory only
///
/// `notchscreen:<width>:tall` draws every step at the open panel's size, so closed and open frames share one
/// picture size, and `notchscreen:<width>:still` holds every open panel fully arrived, with nothing repeating.
/// `-perchSnapshotAgents <file.json>` gives the agents shown here instead of the built-in stand-ins:
/// `{"here": [{"name": "claude", "status": "…", "path": "…"}], "history": [{"agent": "claude", "text": "…", "minutesAgo": 40}]}`,
/// and `-perchSnapshotClips <file.json>` the words of the stand-in clips (see `standInClips`).
///
/// The focus timer is hidden unless `set:focusHidden=false` comes first, as in the app. The steps that
/// are about the timer (notchlive:focus|noroom|paused|focusdone, notchfocus:*, notchdrag:focus) show it
/// for that one step, for this run only.
@MainActor
enum NotchSnapshots {

    /// The notebook's own proposals, with the details the Relay now records, for a picture only. With none
    /// waiting, two open tasks stand in, one of each kind. Nothing is saved.
    static func standInProposals(_ model: AppModel) {
        model.debugChangeTasks { tasks in
            // With none waiting, two open tasks stand in, one of each kind.
            if !tasks.contains(where: \.isReadyToTick) {
                let reasons = ["Moot: The meeting was on Thu 29 Oct, which has passed.", "Sent the deck on Monday; it is in the thread."]
                for (index, reason) in zip(tasks.indices.filter { tasks[$0].isOpen }.prefix(2), reasons) {
                    tasks[index].proposedDoneBy = "claude"
                    tasks[index].proposedDoneReason = reason
                }
            }
            // A proposal that already says when, from where and while doing what keeps its own words.
            for index in tasks.indices where tasks[index].isReadyToTick && tasks[index].proposedDoneAt == nil {
                tasks[index].proposedDoneAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-1200))
                tasks[index].proposedDoneFrom = tasks[index].proposedDoneFrom ?? "claude://code/continue?session=local_snapshot"
                tasks[index].proposedDoneWhile = tasks[index].proposedDoneWhile ?? "Reviewing open tasks to close out stale ones"
            }
        }
    }

    /// Recent clips for the Clips pane, for a picture only: some of each kind, spread over the last hour,
    /// earlier today and yesterday. The pictures are drawn here or are the app's own mark, and the files
    /// are names only, so nothing is read from the disk or the pasteboard. Nothing is saved.
    static func standInClips(_ clips: ClipsStore, variant: String) {
        switch variant {
        case "off":
            clips.debugShow([], enabled: false)
            return
        case "empty":
            clips.debugShow([])
            return
        default:
            break
        }
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        // "Earlier today" needs more than an hour of today behind it; "yesterday" must still be inside the day kept.
        let morning = max(today.addingTimeInterval(70 * 60), ago(150))
        let lastNight = max(today.addingTimeInterval(-3 * 3600), ago(23 * 60))
        func clip(_ key: ClipKey, _ kind: ClipKind, _ content: ClipPayload.Content, _ date: Date,
                  screenCapture: Bool = false, picture: NSImage? = nil, icon: Bool = false) -> Clip {
            Clip(key: key, kind: kind, date: date, payload: ClipPayload(content: content, isScreenCapture: screenCapture, thumbnail: ClipThumbnail(image: picture, isIcon: icon)))
        }
        func text(_ value: String, _ date: Date) -> Clip { clip(.text(value), ClipKind.of(text: value), .text(value), date) }
        func file(_ name: String, _ kind: ClipKind, _ date: Date, screenCapture: Bool = false, picture: NSImage?, icon: Bool = false) -> Clip {
            let url = URL(fileURLWithPath: "/Stand-in").appendingPathComponent(name)
            return clip(.file(url.path), kind, .file(url), date, screenCapture: screenCapture, picture: picture, icon: icon)
        }
        // `-perchSnapshotClips <file.json>` changes the words (texts, links, file names), keeping the kinds,
        // times and drawn pictures: {"screenshot", "links": [2], "texts": [3], "document", "recording"}.
        let words = standInClipWords
        let links = words?.links ?? ["https://developer.apple.com/documentation/quicklookthumbnailing/qlthumbnailgenerator", "https://www.swift.org/documentation/concurrency/"]
        let texts = words?.texts ?? [
            "Book the room for Thursday's review, and send the final venue list round before noon.",
            "Packing list\n- Passport and charger\n- Rain jacket\n- Notebook for the workshop\n- Gifts for the hosts\n- Train tickets, printed\n- Reading for the flight\n- Adapter plugs",
            "Gate B32, boarding 18:05",
        ]
        let mark = NSImage(named: "PerchMark")
        let markData = mark?.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) } ?? Data()
        let items = [
            file(words?.screenshot ?? "Screenshot.png", .image, ago(3), screenCapture: true, picture: drawnScreenshot()),
            text(links[0], ago(14)),
            text(texts[0], ago(33)),
            clip(.image("stand-in-mark"), .image, .image(markData, .png), morning, picture: mark),
            file(words?.document ?? "Q4 roadmap review, final draft for the planning offsite.pdf", .file, morning.addingTimeInterval(-20 * 60), picture: drawnPage()),
            text(texts[1], morning.addingTimeInterval(-45 * 60)),
            file(words?.recording ?? "Screen Recording.mov", .file, lastNight, screenCapture: true, picture: NSWorkspace.shared.icon(for: .quickTimeMovie), icon: true),
            text(links[1], lastNight.addingTimeInterval(-30 * 60)),
            text(texts[2], lastNight.addingTimeInterval(-90 * 60)),
        ]
        let filters: [String: ClipFilter] = ["text": .kind(.text), "links": .kind(.link), "images": .kind(.image), "files": .kind(.file)]
        clips.debugShow(items, filter: filters[variant] ?? .all, hovered: variant == "hover" ? items.first?.id : nil)
    }

    /// A window on a desktop, drawn here, so a screenshot card has a picture without anyone's screen in it.
    private static func drawnScreenshot() -> NSImage {
        NSImage(size: NSSize(width: 720, height: 450), flipped: true) { rect in
            NSGradient(colors: [NSColor(red: 0.74, green: 0.86, blue: 0.96, alpha: 1), NSColor(red: 0.96, green: 0.88, blue: 0.8, alpha: 1)])?.draw(in: rect, angle: -35)
            let window = NSRect(x: 64, y: 44, width: 592, height: 372)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
            shadow.shadowBlurRadius = 18
            shadow.shadowOffset = NSSize(width: 0, height: -6)
            shadow.set()
            NSColor.white.setFill()
            NSBezierPath(roundedRect: window, xRadius: 12, yRadius: 12).fill()
            NSGraphicsContext.restoreGraphicsState()
            let sidebar = NSRect(x: window.minX, y: window.minY, width: 168, height: window.height)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: window, xRadius: 12, yRadius: 12).addClip()
            NSColor(white: 0.955, alpha: 1).setFill()
            sidebar.fill()
            NSGraphicsContext.restoreGraphicsState()
            for (index, color) in [NSColor(red: 1, green: 0.37, blue: 0.34, alpha: 1), NSColor(red: 1, green: 0.74, blue: 0.18, alpha: 1), NSColor(red: 0.16, green: 0.79, blue: 0.25, alpha: 1)].enumerated() {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: window.minX + 16 + CGFloat(index) * 18, y: window.minY + 15, width: 11, height: 11)).fill()
            }
            func bar(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: NSColor) {
                color.setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: height / 2, yRadius: height / 2).fill()
            }
            let accent = NSColor(red: 0.95, green: 0.45, blue: 0.27, alpha: 1)
            bar(sidebar.minX + 12, window.minY + 58, 144, 22, accent.withAlphaComponent(0.16))
            for (index, width) in [96.0, 118, 84, 104, 72, 110].enumerated() {
                bar(sidebar.minX + 20, window.minY + 65 + CGFloat(index) * 30, CGFloat(width), 8, index == 0 ? accent : NSColor(white: 0.78, alpha: 1))
            }
            let left = sidebar.maxX + 28
            bar(left, window.minY + 40, 210, 16, NSColor(white: 0.2, alpha: 1))
            bar(left, window.minY + 68, 140, 9, NSColor(white: 0.7, alpha: 1))
            for (index, width) in [360.0, 332, 352, 248].enumerated() {
                bar(left, window.minY + 102 + CGFloat(index) * 20, CGFloat(width), 8, NSColor(white: 0.84, alpha: 1))
            }
            let card = NSRect(x: left, y: window.minY + 196, width: 176, height: 140)
            accent.withAlphaComponent(0.14).setFill()
            NSBezierPath(roundedRect: card, xRadius: 10, yRadius: 10).fill()
            NSColor(red: 0.42, green: 0.62, blue: 0.95, alpha: 0.16).setFill()
            NSBezierPath(roundedRect: card.offsetBy(dx: 192, dy: 0), xRadius: 10, yRadius: 10).fill()
            for (index, height) in [46.0, 78, 60, 98].enumerated() {
                bar(card.minX + 22 + CGFloat(index) * 36, card.maxY - 16 - CGFloat(height), 20, CGFloat(height), accent.withAlphaComponent(0.75))
            }
            return true
        }
    }

    /// The first page of a document, drawn here, for a file card's Quick Look picture.
    private static func drawnPage() -> NSImage {
        NSImage(size: NSSize(width: 340, height: 440), flipped: true) { rect in
            NSColor.white.setFill()
            rect.fill()
            func bar(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: NSColor) {
                color.setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: 2, yRadius: 2).fill()
            }
            bar(32, 42, 190, 18, NSColor(red: 0.18, green: 0.22, blue: 0.34, alpha: 1))
            bar(32, 70, 120, 9, NSColor(white: 0.68, alpha: 1))
            for (index, width) in [276.0, 262, 270, 210, 276, 244, 188].enumerated() {
                bar(32, 106 + CGFloat(index) * 17, CGFloat(width), 7, NSColor(white: 0.84, alpha: 1))
            }
            for (index, height) in [52.0, 84, 66, 112, 94].enumerated() {
                bar(40 + CGFloat(index) * 54, 400 - CGFloat(height), 34, CGFloat(height), NSColor(red: 0.95, green: 0.45, blue: 0.27, alpha: 0.85))
            }
            return true
        }
    }

    struct Desk {
        var screenWidth: CGFloat = 1470
        var hasNotch = true
        var isDark = false
        /// Every step drawn at the open panel's size, so the frames of one clip line up.
        var isTall = false
        /// Open panels held fully arrived, so nothing that repeats (a presence ring) is caught mid-way.
        var isStill = false
    }

    /// The agents a run shows, from `-perchSnapshotAgents <file>`; nil keeps the built-in stand-ins.
    private struct StandInAgents: Decodable {
        struct Here: Decodable { var name: String; var status: String; var path: String? }
        struct Deed: Decodable { var agent: String; var text: String; var minutesAgo: Double }
        var here: [Here]
        var history: [Deed]?
    }

    private struct StandInClipWords: Decodable {
        var screenshot: String?
        var links: [String]?
        var texts: [String]?
        var document: String?
        var recording: String?
    }

    private static let standInClipWords: StandInClipWords? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-perchSnapshotClips"), arguments.indices.contains(index + 1),
              let data = try? Data(contentsOf: URL(fileURLWithPath: arguments[index + 1])),
              let words = try? JSONDecoder().decode(StandInClipWords.self, from: data),
              (words.links?.count ?? 2) >= 2, (words.texts?.count ?? 3) >= 3 else { return nil }
        return words
    }()

    private static let standInAgents: StandInAgents? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-perchSnapshotAgents"), arguments.indices.contains(index + 1),
              let data = try? Data(contentsOf: URL(fileURLWithPath: arguments[index + 1])) else { return nil }
        return try? JSONDecoder().decode(StandInAgents.self, from: data)
    }()

    /// The notebook's tasks as loaded, kept so a `notchtick` step can tick some in memory and the next
    /// step starts from the notebook again.
    private static var loadedTasks: [PerchTask]?

    /// Today's open tasks in the order the Today card lists them.
    private static func todayList(_ model: AppModel) -> [PerchTask] {
        NotchDay.open(model.tasks, day: model.today, today: model.today, area: nil).sorted(by: AppModel.ordered)
    }

    static var desk = Desk()

    struct Shot {
        var view: AnyView
        var size: CGSize
    }

    private static var focusWasForced = false
    private static var focusBeforeForcing: Any?

    /// Shows the focus timer for a step that draws it, and puts the setting back for the next step.
    /// Only this run's own (volatile) settings are touched, never the saved ones.
    private static func showFocus(_ needed: Bool) {
        var volatile = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        if needed, FocusAvailability.isHidden() {
            focusBeforeForcing = volatile[FocusAvailability.hiddenKey]
            focusWasForced = true
            volatile[FocusAvailability.hiddenKey] = false
        } else if !needed, focusWasForced {
            volatile[FocusAvailability.hiddenKey] = focusBeforeForcing
            focusWasForced = false
        } else {
            return
        }
        UserDefaults.standard.setVolatileDomain(volatile, forName: UserDefaults.argumentDomain)
    }

    /// A `set:focusHidden=…` step chose the setting for the rest of the run: what a timer step did
    /// before it is no longer something to put back.
    static func settingChanged(by step: String) {
        if step.hasPrefix("set:\(FocusAvailability.hiddenKey)=") { focusWasForced = false }
    }

    static func shot(_ step: String, services: NotchServices) -> Shot? {
        let parts = step.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let name = parts.first, name.hasPrefix("notch") else { return nil }
        let argument = parts.count > 1 ? parts[1] : ""
        let aboutFocus = name == "notchfocus"
            || (name == "notchdrag" && (NotchCardKind(rawValue: argument) ?? .focus) == .focus)
            || (name == "notchlive" && ["focus", "noroom", "paused", "focusdone"].contains(argument))
            || (name == "notch" && argument.lowercased() == "focus")
        if name != "notchscreen" { showFocus(aboutFocus) }

        if name == "notchscreen" {
            desk = Desk(screenWidth: CGFloat(Double(argument) ?? 1470), hasNotch: !parts.contains("nonotch"), isDark: parts.contains("dark"),
                        isTall: parts.contains("tall"), isStill: parts.contains("still"))
            return nil
        }

        // A tick step changes tasks in memory; every other step sees the notebook as it is.
        if let loaded = loadedTasks, name != "notchtick" {
            services.model.debugChangeTasks { $0 = loaded }
            loadedTasks = nil
        }

        let geometry = NotchGeometry(
            notchSize: desk.hasNotch ? CGSize(width: 185, height: 32) : CGSize(width: 180, height: 24),
            hasHardwareNotch: desk.hasNotch, screenFrame: CGRect(x: 0, y: 0, width: desk.screenWidth, height: desk.screenWidth * 0.65)
        )
        let state = NotchState(geometry: geometry)
        state.showsCounts = true
        var tall = true
        var crowded = false

        // Every step starts from the same quiet world, then sets up its own.
        services.notepad.debugShowToday()
        services.focus.debugClear()
        services.live.debugShow(nil)
        if let agents = standInAgents {
            services.model.agents = agents.here.map { AgentPresence(name: $0.name, status: $0.status, isActive: true, path: $0.path) }
        } else {
            services.model.agents = [
                AgentPresence(name: "claude", status: "Tidying this week's plan", isActive: true, path: "Personal/Plans/Week 46.md"),
                AgentPresence(name: "codex", status: "Reading the release notes", isActive: true),
            ]
        }
        let firstTask = services.model.todayTasks.first
        // The reminder a prompt is about: a task due today at a time, as a real reminder would be.
        let timedTask = services.model.todayTasks.first { $0.time != nil && $0.due == services.model.today } ?? firstTask
        // An agent's question: the notebook's own first proposal, when it has one.
        let proposal = services.model.readyToTick.first
        func prompt(_ kind: String) -> NotchPrompt {
            switch kind {
            case "agent":
                if let proposal {
                    let reason = Proposal(proposal).reason.map { ": \($0)" } ?? ""
                    return NotchPrompt(id: "p", kind: .proposal(taskID: proposal.id, agent: proposal.proposedDoneBy ?? "claude"),
                                       title: proposal.title, detail: "\(Proposal(proposal).sentence)\(reason)")
                }
                return NotchPrompt(
                    id: "p", kind: .proposal(taskID: firstTask?.id ?? "", agent: "claude"),
                    title: firstTask?.title ?? "Send the weekly update", detail: "claude says it's done: the email went out at 9:40"
                )
            case "focusdone":
                return NotchPrompt(id: "f", kind: .focusFinished(taskID: firstTask?.id), title: firstTask?.title ?? "Focus session", detail: "Time's up. Nicely done.")
            case "event":
                return NotchPrompt(id: "e", kind: .event, title: "Team standup", detail: "Starts 10:00")
            default:
                return reminder(for: timedTask)
            }
        }

        switch name {
        case "notchclosed":
            state.showsCounts = argument != "bare"
            tall = false
        case "notchpeek":
            if let amount = Double(argument) { state.stage = NotchStage(hover: amount) } else { state.isHovering = true }
            tall = false
        case "notchmove":
            let seconds = parts.count > 2 ? Double(parts[2]) ?? 0 : 0
            let variant = parts.count > 3 ? parts[3] : "reminder"
            switch argument {
            case "open":
                // The pointer arrives at zero and swells the notch; it opens once the pointer has rested.
                let opening = seconds - NotchHover.openDelay
                state.stage = NotchStage(openProgress: Motion.notchCurve(.open).value(at: opening), hover: Motion.notchCurve(.peek).value(at: seconds), revealTime: opening)
            case "close":
                state.stage = NotchStage(openProgress: 1 - Motion.notchCurve(.close).value(at: seconds), closing: true)
            case "prompt", "promptaway":
                services.live.debugShow(prompt(variant))
                let arriving = argument == "prompt"
                let amount = Motion.notchCurve(arriving ? .prompt : .promptAway).value(at: seconds)
                state.phase = arriving ? .prompt : .closed
                state.stage = NotchStage(change: arriving ? (.closed, .prompt, amount) : (.prompt, .closed, amount))
            case "live", "liveaway":
                // A session just started counts down from 25:00; the fourth part says how far it has got.
                showFocus(true)
                let elapsed = parts.count > 3 ? Int(parts[3]) ?? 0 : 0
                services.focus.debugPreview(total: 1500, elapsed: elapsed, task: firstTask?.id)
                let arriving = argument == "live"
                let amount = Motion.notchCurve(.live).value(at: seconds)
                state.phase = arriving ? .live : .closed
                state.stage = NotchStage(change: arriving ? (.closed, .live, amount) : (.live, .closed, amount))
            default:
                return nil
            }
            tall = argument == "open" || argument == "close"
        case "notchtick":
            state.phase = .open
            let loaded = loadedTasks ?? services.model.tasks
            loadedTasks = loaded
            let done = parts.count > 2 ? Int(parts[2]) ?? 0 : 0
            services.model.debugChangeTasks { $0 = loaded }
            let ticked = Set(todayList(services.model).prefix(done).map(\.id))
            let today = services.model.today
            services.model.debugChangeTasks { tasks in
                for index in tasks.indices where ticked.contains(tasks[index].id) {
                    tasks[index].status = .done
                    tasks[index].completed = today
                }
            }
            state.stage = NotchStage(openProgress: 1, tickTime: Double(argument) ?? 0)
        case "notchframe":
            state.stage = NotchStage(openProgress: min(max(Double(argument) ?? 0, -0.1), 1.1))
        case "notchmode":
            state.phase = .open
            state.panelMode = NotchPanelMode.allCases.first { $0.rawValue.lowercased() == argument.lowercased() } ?? .workspace
            if state.panelMode == .clips {
                let variant = parts.count > 2 ? parts[2] : ""
                standInClips(services.clips, variant: variant)
                if variant == "prompt" { services.live.debugShow(reminder(for: firstTask)) }
            }
        case "notchquiet":
            // The Agents card when nobody is here: what each agent did last (stand-in history for the picture).
            state.phase = .open
            state.panelMode = .workspace
            services.model.agents = []
            let now = Date()
            if let history = standInAgents?.history {
                services.model.agentHistory = history.map { .init(agent: $0.agent, text: $0.text, date: now.addingTimeInterval(-$0.minutesAgo * 60)) }
            } else {
            services.model.agentHistory = [
                .init(agent: "dot", text: "Ready to help with your notes and tasks through Perch.", date: now.addingTimeInterval(-120)),
                .init(agent: "claude", text: "Updated “Plan the spring garden”", date: now.addingTimeInterval(-2700)),
                .init(agent: "robin", text: "Added to Trip ideas", date: now.addingTimeInterval(-7200)),
            ]
            }
        case "notchready":
            state.phase = .open
            state.panelMode = .workspace
            if argument != "busy" { services.model.agents = [] }
            standInProposals(services.model)
        case "notch":
            state.phase = .open
            state.panelMode = argument.lowercased() == "clips" ? .clips : .workspace
            if state.panelMode == .clips { standInClips(services.clips, variant: "") }
        case "notchdrag":
            state.phase = .open
            let kind = NotchCardKind(rawValue: argument) ?? .focus
            state.stage = NotchStage(drag: kind, dragOffset: CGFloat(parts.count > 2 ? Double(parts[2]) ?? 150 : (kind == .agents ? -170 : 150)))
        case "notchcomplete":
            state.phase = .open
            state.stage = NotchStage(completion: CGFloat(min(max(Double(argument) ?? 0.4, 0), 1)))
        case "notchfocus":
            state.phase = .open
            services.focus.debugPreview(total: 1500, elapsed: 437, paused: argument == "paused", task: firstTask?.id)
        case "notchopen":
            state.phase = .open
            services.live.debugShow(reminder(for: firstTask))
        case "notchlive":
            tall = false
            switch argument {
            case "focus", "noroom", "paused":
                services.focus.debugPreview(total: 1500, elapsed: 437, paused: argument == "paused", task: firstTask?.id)
                state.phase = .live
                if argument == "noroom" {
                    state.hasRoom = false
                    crowded = true
                }
            case "agent":
                services.live.debugShow(prompt("agent"))
                state.phase = .prompt
                crowded = true
            case "focusdone", "event":
                services.live.debugShow(prompt(argument))
                state.phase = .prompt
            default:
                services.live.debugShow(prompt("reminder"))
                state.phase = .prompt
                crowded = true
            }
        default:
            return nil
        }

        // A still desk holds an open panel fully arrived instead of letting it play in.
        if desk.isStill, state.phase == .open, state.stage?.openProgress == nil {
            var stage = state.stage ?? NotchStage()
            stage.openProgress = 1
            state.stage = stage
        }
        if desk.isTall { tall = true }
        let window = state.windowSize
        let size = CGSize(width: tall ? window.width + 96 : 700, height: tall ? window.height + 40 : 130)
        let scene = NotchDeskScene(state: state, services: services, desk: desk, crowded: crowded)
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipped()
        return Shot(view: AnyView(scene), size: size)
    }

    private static func reminder(for task: PerchTask?) -> NotchPrompt {
        NotchPrompt(id: "r", kind: .reminder(taskID: task?.id ?? ""), title: task?.title ?? "Call the dentist", detail: "Due at \(task?.time ?? "16:30")")
    }
}

/// A stand-in desktop: wallpaper, a menu bar with menus and icons, the notch, and the camera.
private struct NotchDeskScene: View {
    @ObservedObject var state: NotchState
    let services: NotchServices
    let desk: NotchSnapshots.Desk
    /// Menus long enough to reach the notch, to check nothing of Perch's covers them.
    let crowded: Bool

    /// Today's date, and a time two minutes before the reminder the prompts show (16:28 without one),
    /// so the stand-in menu bar agrees with the notch.
    private var clock: String {
        let model = services.model
        let due = model.todayTasks.first { $0.time != nil && $0.due == model.today }?.time ?? "16:30"
        let pieces = due.split(separator: ":").compactMap { Int($0) }
        let minutes = max((pieces.first ?? 16) * 60 + (pieces.count > 1 ? pieces[1] : 30) - 2, 0)
        let day = DateFormatter()
        day.dateFormat = "EEE d MMM"
        return day.string(from: Date()) + String(format: "  %02d:%02d", minutes / 60, minutes % 60)
    }

    var body: some View {
        let neck = state.neck
        let ink = desk.isDark ? Color.white : Color.black
        ZStack(alignment: .top) {
            LinearGradient(
                colors: desk.isDark
                    ? [Color(red: 0.1, green: 0.12, blue: 0.2), Color(red: 0.22, green: 0.14, blue: 0.3)]
                    : [Color(red: 0.74, green: 0.86, blue: 0.96), Color(red: 0.96, green: 0.88, blue: 0.8)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            HStack(spacing: 16) {
                Image(systemName: "apple.logo")
                ForEach(crowded ? ["Xcode", "File", "Edit", "View", "Find", "Navigate", "Editor", "Product", "Debug", "Integrate", "Window", "Help"] : ["Finder", "File", "Edit", "View", "Go"], id: \.self) { title in
                    Text(title).fontWeight(title == "Finder" || title == "Xcode" ? .bold : .regular).fixedSize()
                }
                Spacer(minLength: 0)
                Image(systemName: "wifi")
                Image(systemName: "battery.75")
                Text(clock).fixedSize()
            }
            .font(.system(size: 13))
            .foregroundStyle(ink.opacity(0.85))
            .padding(.horizontal, 14)
            .frame(height: neck.height)
            .background(ink.opacity(0.06))
            NotchRootView(state: state, services: services, close: {})
                .frame(width: state.windowSize.width, height: state.windowSize.height)
            if desk.hasNotch {
                // Where the hardware is: nothing but black may sit inside the dashed line.
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: neck.width, height: neck.height + 9)
                    .offset(y: -9)
                Circle().fill(Color(white: 0.16)).frame(width: 7, height: 7).offset(y: neck.height / 2 - 3.5)
            }
        }
        .clipped()
    }
}
#endif
