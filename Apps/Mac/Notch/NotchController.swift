import AppKit
import Combine
import PerchKit
import PerchUI
import SwiftUI

/// A panel that can take typing without activating the app or taking focus from your work.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// What the open panel is showing. Workspace is the row of cards; the others take the whole panel.
enum NotchPanelMode: String, CaseIterable, Identifiable {
    case workspace = "Workspace", week = "Week", insights = "Insights", clips = "Clips"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .workspace: return "rectangle.split.3x1"
        case .week: return "calendar"
        case .insights: return "chart.bar"
        case .clips: return "doc.on.clipboard"
        }
    }
}

/// The states one notch moves between. Each is one outline of the same black shape.
enum NotchPhase: Equatable {
    /// At rest: the bare notch, or the notch with today's counts beside it.
    case closed
    /// A focus timer is running: the time and an arc ride beside the notch.
    case live
    /// Asking something: a tab hangs below the notch with a title and two answers.
    case prompt
    /// The panel.
    case open
}

/// Holds the notch still part-way through something, so a snapshot can show a moment of motion.
struct NotchStage: Equatable {
    /// Progress of the opening, 0...1. The outline and the content's arrival both follow it.
    var openProgress: Double?
    /// A card held mid-drag, this far from where it started.
    var drag: NotchCardKind?
    var dragOffset: CGFloat = 0
    /// A task held mid-completion, with its burst at this progress.
    var completion: CGFloat?
    /// The pointer's swell over the notch, held part-way: 0 at rest, 1 swollen.
    var hover: Double?
    /// Seconds since the panel began to open, so its content is held where each item's own delayed
    /// spring would have it. Nil holds the content by `openProgress` alone.
    var revealTime: Double?
    /// The held opening is the panel going back: its content is in place and fades as the shape closes
    /// over it, while the closed notch's counts come back.
    var closing = false
    /// A change between two of the closed notch's shapes held part-way (`amount` 0 is `from`, 1 is `to`),
    /// such as a prompt dropping out of it or the timer widening it.
    var change: (from: NotchPhase, to: NotchPhase, amount: Double)?
    /// The first task's tick, held this many seconds after the click. Before zero the pointer is still
    /// arriving on its row.
    var tickTime: Double?

    static func == (a: NotchStage, b: NotchStage) -> Bool {
        a.openProgress == b.openProgress && a.drag == b.drag && a.dragOffset == b.dragOffset && a.completion == b.completion
            && a.hover == b.hover && a.revealTime == b.revealTime && a.closing == b.closing && a.tickTime == b.tickTime
            && a.change?.from == b.change?.from && a.change?.to == b.change?.to && a.change?.amount == b.change?.amount
    }
}

/// State one screen's notch shares with its views.
@MainActor
final class NotchState: ObservableObject {
    @Published var phase = NotchPhase.closed
    @Published var panelMode = NotchPanelMode.workspace
    @Published var focusQuickAdd = false
    /// Shows today's counts in small "ears" beside the closed notch.
    @Published var showsCounts = UserDefaults.standard.object(forKey: "notchAmbient") as? Bool ?? true
    /// False while menus or menu bar icons reach into the space beside the notch.
    @Published var hasRoom = true
    /// The pointer is over the closed notch: it swells slightly before opening.
    @Published var isHovering = false
    /// False while the notch's window is put away, as under a full-screen app.
    @Published var isOnScreen = true
    @Published var stage: NotchStage?
    let geometry: NotchGeometry

    init(geometry: NotchGeometry) { self.geometry = geometry }

    static let ear: CGFloat = 54
    static let liveEar: CGFloat = 66
    /// Height of the tab that carries the timer under the notch when there's no room beside it.
    static let liveTab: CGFloat = 22
    /// The part of a prompt below the menu bar.
    static let promptBody = CGSize(width: 420, height: 52)
    /// Room for the shadow and a spring's overshoot, inside the window.
    static let margin: CGFloat = 28

    /// The open panel, sized for this notch's screen.
    var openSize: CGSize {
        let size = NotchLayout.openSize(screenWidth: geometry.screenFrame.width)
        return CGSize(width: size.width, height: size.height)
    }

    /// The window that holds every state: the open panel plus room around it.
    var windowSize: CGSize {
        CGSize(width: openSize.width + Self.margin * 2, height: openSize.height + Self.margin)
    }

    var showsAmbient: Bool { geometry.hasHardwareNotch && showsCounts && hasRoom }
    /// Whether the running timer can sit beside the notch, or must hang in a tab below it.
    var liveBeside: Bool { geometry.hasHardwareNotch && hasRoom }

    /// The band the hardware notch (or the menu bar, on a screen without one) occupies.
    var neck: CGSize { geometry.notchSize }

    func outline(for phase: NotchPhase) -> NotchOutline {
        let neck = self.neck, hardware = geometry.hasHardwareNotch
        let hover = stage?.hover ?? (isHovering ? 1 : 0)
        let swell: Double = 12 * hover, drop: Double = 3 * hover
        switch phase {
        case .closed:
            // A screen without a notch shows nothing at rest, and a sliver under the pointer.
            guard hardware else { return NotchOutline(width: neck.width + swell, height: isHovering ? 5 : 0, topRadius: 5, bottomRadius: 5) }
            return NotchOutline(width: neck.width + (showsAmbient ? Self.ear * 2 : 0) + swell, height: neck.height + drop, topRadius: 6, bottomRadius: 9 + drop)
        case .live:
            if liveBeside {
                return NotchOutline(width: neck.width + Self.liveEar * 2 + swell, height: neck.height + drop, topRadius: 6, bottomRadius: 9 + drop)
            } else if hardware {
                return NotchOutline(width: neck.width + swell, height: neck.height + Self.liveTab + drop, topRadius: 6, bottomRadius: 12)
            }
            return NotchOutline(width: 124 + swell, height: max(neck.height, 26) + drop, topRadius: 6, bottomRadius: 11)
        case .prompt:
            // On a screen without a notch the neck is only a stem, so it takes little of the menu bar.
            return NotchOutline(
                width: max(Self.promptBody.width, neck.width + 40), height: neck.height + Self.promptBody.height,
                neckWidth: hardware ? neck.width : 112, neckHeight: neck.height, topRadius: 6, bottomRadius: 18, shoulderRadius: 9
            )
        case .open:
            return NotchOutline(width: openSize.width, height: openSize.height, topRadius: 10, bottomRadius: 24)
        }
    }

    /// What to draw now: the phase's outline, or a held moment of the opening.
    var outline: NotchOutline {
        if let change = stage?.change {
            return NotchOutline.mix(outline(for: change.from), outline(for: change.to), change.amount)
        }
        if let progress = stage?.openProgress {
            return stage?.closing == true
                ? NotchOutline.mix(outline(for: .open), outline(for: .closed), 1 - progress)
                : NotchOutline.mix(outline(for: .closed), outline(for: .open), progress)
        }
        return outline(for: phase)
    }

    /// The on-screen size of the current shape, for deciding where the pointer counts as "on the notch".
    var shapeSize: CGSize {
        let resolved = outline(for: phase).resolved
        return CGSize(width: resolved.width, height: resolved.height)
    }
}

/// Runs one notch per screen, and decides when each opens and closes.
@MainActor
final class NotchController: ObservableObject {
    let services: NotchServices
    private var notches: [CGDirectDisplayID: ScreenNotch] = [:]
    private var monitors: [Any] = []
    private var hotKey: GlobalHotKey?
    private var cancellables: Set<AnyCancellable> = []
    /// Checks the space beside the notch now and then. Runs only while some screen has a notch to check.
    private var roomTimer: Timer?
    /// The settings the current notches were built for, to notice when Settings changes them.
    private var applied: (enabled: Bool, screens: String)?
    private var appliedFocusHidden = FocusAvailability.isHidden()
    /// Counts app switches and space changes, so only the latest one's follow-up looks run.
    private var settleRound = 0

    // Read straight from the saved settings: the Settings window changes them through its own
    // bindings, so a property observer here would never hear about it.
    private var isEnabled: Bool { UserDefaults.standard.object(forKey: "notchEnabled") as? Bool ?? true }
    private var screenChoice: String { UserDefaults.standard.string(forKey: "notchScreens") ?? "builtin" }

    init(services: NotchServices) {
        self.services = services
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.notches.values.forEach { $0.updateFullScreen(); $0.updateRoom() }
                    self?.lookAgainAfterTheSlide()
                }
            }
        }
        // Option-N opens the notch ready to add a task.
        hotKey = GlobalHotKey(keyCode: 45, modifiers: 2048) { [weak self] in
            DispatchQueue.main.async { self?.openPrimary(focus: true) }
        }
        // Mouse movement events need no special permission, unlike keyboard monitoring.
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown]
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.mouse(event) }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.mouse(event) }
            return event
        } as Any)
        // A timer starting or stopping, and a prompt arriving or leaving, change the closed notch's shape.
        services.focus.$mode.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.notches.values.forEach { $0.refresh() } }
        }.store(in: &cancellables)
        services.live.$queue.map(\.current?.id).removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.notches.values.forEach { $0.refresh() } }
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                // "Show the notch" or "Show on" changed in Settings: build the notches again, at once.
                if self.applied?.enabled != self.isEnabled || self.applied?.screens != self.screenChoice { self.rebuild() }
                let value = UserDefaults.standard.object(forKey: "notchAmbient") as? Bool ?? true
                self.notches.values.forEach { $0.setShowsCounts(value) }
                // The focus timer was hidden or shown: the closed notch may need to change shape.
                let focusHidden = FocusAvailability.isHidden()
                if focusHidden != self.appliedFocusHidden {
                    self.appliedFocusHidden = focusHidden
                    self.services.focusAvailabilityChanged()
                    self.notches.values.forEach { $0.refresh() }
                }
            }
            .store(in: &cancellables)
        rebuild()
    }

    private func rebuild() {
        notches.values.forEach { $0.tearDown() }
        notches = [:]
        applied = (isEnabled, screenChoice)
        if isEnabled {
            for screen in NSScreen.screens {
                guard let id = screen.displayID else { continue }
                let notch = NotchGeometry(screen: screen)
                // By default only real notches. Other screens get one only when chosen in Settings.
                if screenChoice == "builtin", !notch.hasHardwareNotch, NSScreen.screens.contains(where: { NotchGeometry(screen: $0).hasHardwareNotch }) { continue }
                notches[id] = ScreenNotch(screen: screen, services: services)
            }
        }
        // With no notch on any screen there is nowhere to ask anything: reminders stop being checked
        // (and aren't marked as rung), and nothing waits in the queue to chime later.
        services.setNotchActive(!notches.isEmpty)
        // Menu bar icons come and go, and apps change their menus, so check again now and then,
        // but only while there is a notch with something beside it to make room for.
        roomTimer?.invalidate()
        roomTimer = nil
        if notches.values.contains(where: \.hasHardwareNotch) {
            let timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.notches.values.forEach { $0.updateRoom() } }
            }
            timer.tolerance = 0.5
            roomTimer = timer
        }
    }

    /// macOS can announce a new space, or the app coming forward, while the slide out of a full-screen
    /// space is still running and the window being left still counts as on screen. Look again once the
    /// slide is over, so that answer can't hide the notch until the next app switch.
    private func lookAgainAfterTheSlide() {
        settleRound += 1
        let round = settleRound
        for delay in NotchFullScreenCheck.settleDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.settleRound == round else { return }
                self.notches.values.forEach { $0.recheckFullScreen() }
            }
        }
    }

    private func mouse(_ event: NSEvent) {
        let point = NSEvent.mouseLocation
        let pressed = event.type == .leftMouseDown || event.type == .leftMouseDragged
        for notch in notches.values { notch.track(point, pressed: pressed, isClick: event.type == .leftMouseDown) }
    }

    func openPrimary(focus: Bool = false) {
        let point = NSEvent.mouseLocation
        let target = notches.values.first { $0.screenFrame.contains(point) } ?? notches.values.first
        target?.open(focusQuickAdd: focus)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? { deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID }
}

/// One screen's notch. Its window never moves or resizes; only the drawn shape animates.
@MainActor
final class ScreenNotch {
    private let panel: NotchPanel
    private let state: NotchState
    private let screen: NSScreen
    private let services: NotchServices
    let screenFrame: CGRect
    /// When the pointer opens and closes the panel; see NotchHover.
    private var hover = NotchHover()
    /// Reads where the pointer is while it matters, because macOS sends no pointer events while the
    /// pointer is over Perch's own window.
    private var pollTimer: Timer?
    /// Whether a full-screen app covers this screen, as last looked, and when to look again.
    private var fullScreen = NotchFullScreenCheck()
    private var isFullScreen: Bool { fullScreen.isFullScreen }
    private var resignObserver: NSObjectProtocol?
    /// Watching for Escape, only while the panel is open.
    private var escapeMonitors: [Any] = []

    var hasHardwareNotch: Bool { state.geometry.hasHardwareNotch }

    init(screen: NSScreen, services: NotchServices) {
        self.services = services
        self.screen = screen
        screenFrame = screen.frame
        state = NotchState(geometry: NotchGeometry(screen: screen))
        panel = NotchPanel(contentRect: state.geometry.frame(for: state.windowSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        // Transient, not stationary: during Mission Control the notch steps aside and comes back after.
        // A stationary panel this size made Mission Control show an empty desktop, with every app gone.
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        // Clicking a button in the notch must not take the keyboard from the app in front;
        // only a text field does.
        panel.becomesKeyOnlyIfNeeded = true
        let view = NSHostingView(rootView: NotchRootView(
            state: state, services: services,
            close: { [weak self] in self?.close(animated: true) },
            expand: { [weak self] in self?.open(focusQuickAdd: false) }
        ))
        view.sizingOptions = []
        panel.contentView = view
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state.phase == .open, !self.openRect.contains(NSEvent.mouseLocation) else { return }
                self.close(animated: true)
            }
        }
        panel.orderFrontRegardless()
        refresh()
        updateFullScreen()
    }

    private var level: NotchMotionLevel { NotchMotionLevel(stored: UserDefaults.standard.string(forKey: "notchMotion")) }
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Where hovering opens it: the visible closed shape, a little wider, reaching past the
    /// screen's top edge so pushing the pointer to the top always counts.
    private var hoverRect: CGRect {
        let size = state.geometry.hasHardwareNotch || state.phase == .live ? state.shapeSize : CGSize(width: 220, height: 6)
        let margin = -CGFloat(NotchHover.hoverMargin(hasRoom: state.hasRoom))
        return state.geometry.frame(for: size).insetBy(dx: margin, dy: 0).union(
            state.geometry.frame(for: CGSize(width: size.width - margin * 2, height: 1)).offsetBy(dx: 0, dy: 2))
    }

    /// The tab a prompt hangs in. While the pointer is over it, clicks reach its buttons.
    /// Only the part below the menu bar counts, so the menus beside the notch always take their clicks.
    private var promptRect: CGRect {
        let full = state.geometry.frame(for: state.shapeSize)
        return CGRect(x: full.minX, y: full.minY, width: full.width, height: NotchState.promptBody.height)
    }

    func updateRoom() {
        // Measuring means listing every window on screen (and, with Accessibility, the front app's menus),
        // so it is only done while something of Perch's sits beside the notch: the counts or the timer.
        guard state.geometry.hasHardwareNotch, state.phase != .open, !isFullScreen,
              state.showsCounts || services.focus.isRunning else { return }
        let room = MenuBarClearance.isClear(screen: screen, notch: state.geometry.frame(for: state.geometry.notchSize), earWidth: max(NotchState.ear, NotchState.liveEar))
        guard room != state.hasRoom else { return }
        withNotchMotion(.live, level: level, reduceMotion: reduceMotion) { state.hasRoom = room }
    }

    func setShowsCounts(_ value: Bool) {
        guard state.showsCounts != value else { return }
        withNotchMotion(.live, level: level, reduceMotion: reduceMotion) { state.showsCounts = value }
        updateRoom()
    }

    private func setHovering(_ value: Bool) {
        guard state.isHovering != value else { return }
        withNotchMotion(.peek, level: level, reduceMotion: reduceMotion) { state.isHovering = value }
    }

    private var openRect: CGRect { state.geometry.frame(for: state.openSize).insetBy(dx: -18, dy: -18) }

    /// The open panel exactly as drawn. Only this part of the window takes clicks.
    private var panelRect: CGRect { state.geometry.frame(for: state.openSize) }

    /// Puts this notch away for good: its screen went, or the notch was turned off.
    func tearDown() {
        pollTimer?.invalidate()
        pollTimer = nil
        stopWatchingEscape()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
    }

    /// Escape closes the open panel whether or not a text field in it has the keyboard. Inside Perch
    /// that always works. While another app is in front, macOS only lets Perch hear the key if it has
    /// Accessibility access (the same one the counts use); without it, clicking elsewhere or moving
    /// the pointer away closes the panel. Perch never asks for the access here, and never takes the
    /// key away from another app.
    private func watchEscape() {
        guard escapeMonitors.isEmpty else { return }
        let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            return MainActor.assumeIsolated {
                guard let self, self.state.phase == .open else { return event }
                self.close(animated: true)
                return nil
            }
        }
        if let local { escapeMonitors.append(local) }
        guard MenuBarClearance.canMeasureMenus else { return }
        let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            MainActor.assumeIsolated {
                guard let self, self.state.phase == .open else { return }
                self.close(animated: true)
            }
        }
        if let global { escapeMonitors.append(global) }
    }

    private func stopWatchingEscape() {
        escapeMonitors.forEach(NSEvent.removeMonitor)
        escapeMonitors = []
    }

    func updateFullScreen() {
        fullScreen.record(coveredByFullScreenApp(), at: Date())
        showOrPutAway()
    }

    /// Looks again between app switches and space changes. Shows or puts away the notch only if the
    /// answer changed, so these extra looks never reorder the window for nothing.
    func recheckFullScreen() {
        let was = isFullScreen
        fullScreen.record(coveredByFullScreenApp(), at: Date())
        guard isFullScreen != was else { return }
        showOrPutAway()
        // The space beside the notch isn't measured while it is away.
        if !isFullScreen { updateRoom() }
    }

    /// A full-screen app has a window covering the whole screen at the normal level.
    private func coveredByFullScreenApp() -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return windows.contains { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  (info[kCGWindowOwnerPID as String] as? pid_t) != ProcessInfo.processInfo.processIdentifier else { return false }
            let rect = CGRect(x: bounds["X"] ?? 0, y: mainHeight - (bounds["Y"] ?? 0) - (bounds["Height"] ?? 0), width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            return rect.equalTo(screenFrame)
        }
    }

    private func showOrPutAway() {
        let hidden = isFullScreen && state.phase != .open
        if hidden { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        // Anything that repeats (the overdue glow) stops while the window is away.
        if state.isOnScreen == hidden { state.isOnScreen = !hidden }
    }

    /// What the notch shows when the panel isn't open.
    private var restingPhase: NotchPhase {
        if services.live.current != nil { return .prompt }
        return services.focus.isRunning && FocusAvailability.isAvailable() ? .live : .closed
    }

    /// Moves to `phase` with the movement that suits where it is coming from. Springs pick up from
    /// wherever the shape is, so changing its mind half-way never jumps or queues.
    private func setPhase(_ phase: NotchPhase) {
        let old = state.phase
        guard old != phase else { return }
        let move: Motion.NotchMove
        if phase == .open {
            move = .open
        } else if old == .open {
            move = .close
        } else if phase == .prompt {
            move = .prompt
        } else if old == .prompt {
            move = .promptAway
        } else {
            move = .live
        }
        withNotchMotion(move, level: level, reduceMotion: reduceMotion) { state.phase = phase }
    }

    /// Follows the timer and the prompt queue while the panel is closed.
    func refresh() {
        guard state.phase != .open else { return }
        // A timer that has just started needs to know whether there is room beside the notch.
        updateRoom()
        setPhase(restingPhase)
        if state.phase != .prompt {
            panel.ignoresMouseEvents = true
            services.live.hold(false)
        }
    }

    func track(_ point: NSPoint, pressed: Bool, isClick: Bool) {
        if isFullScreen, state.phase != .open {
            // A full-screen app covered this screen when last looked. That can be left over, so the
            // pointer reaching the notch looks again (now and then, not on every move).
            let onNotch = hoverRect.contains(point)
            if fullScreen.shouldCheck(pointerOnNotch: onNotch, at: Date()) { recheckFullScreen() }
            if isFullScreen {
                // Still covered: nothing to open. Stop waiting, which stops the poll.
                hover.covered(onNotch: onNotch)
                updatePoll()
                return
            }
        }
        switch state.phase {
        case .prompt:
            // A prompt never opens the panel by hover: its buttons need to be reachable. Clicks only
            // land on the window while the pointer is on the tab, so nothing else is ever blocked.
            let inside = promptRect.contains(point)
            panel.ignoresMouseEvents = !inside
            services.live.hold(inside)
        case .closed, .live:
            let onNotch = hoverRect.contains(point)
            if onNotch, isClick {
                open(focusQuickAdd: false)
                return
            }
            let decision = hover.closed(onNotch: onNotch, pressed: pressed, at: Date())
            setHovering(onNotch && !pressed && hover.armed)
            if decision == .open { open(focusQuickAdd: false) } else { updatePoll() }
        case .open:
            let near = openRect.contains(point)
            // The window is larger than the panel; the clear border around it lets clicks through.
            let takesClicks = NotchHover.panelTakesClicks(open: true, pointerInPanel: panelRect.contains(point))
            if panel.ignoresMouseEvents == takesClicks { panel.ignoresMouseEvents = !takesClicks }
            if isClick, !near {
                close(animated: true)
                return
            }
            if hover.open(insidePanel: near, keyboardInPanel: panel.isKeyWindow, at: Date()) == .close {
                close(animated: true)
            }
        }
    }

    /// Polls the pointer while it matters: the panel is open, or the pointer is waiting on the notch.
    private func updatePoll() {
        let needed = state.phase == .open || hover.isWaitingToOpen
        if needed, pollTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.track(NSEvent.mouseLocation, pressed: NSEvent.pressedMouseButtons & 1 != 0, isClick: false)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        } else if !needed, let timer = pollTimer {
            timer.invalidate()
            pollTimer = nil
        }
    }

    func open(focusQuickAdd: Bool) {
        hover.didOpen()
        state.isHovering = false
        panel.orderFrontRegardless()
        panel.ignoresMouseEvents = !panelRect.contains(NSEvent.mouseLocation)
        if !state.isOnScreen { state.isOnScreen = true }
        services.live.hold(false)
        services.notepad.refresh()
        services.reminders.reloadEvents()
        if focusQuickAdd { state.panelMode = .workspace }
        setPhase(.open)
        updatePoll()
        watchEscape()
        if focusQuickAdd {
            panel.makeKey()
            state.focusQuickAdd = true
        }
    }

    func close(animated: Bool) {
        stopWatchingEscape()
        state.focusQuickAdd = false
        panel.ignoresMouseEvents = true
        if panel.isKeyWindow { panel.resignKey() }
        setPhase(restingPhase)
        // Closed with the pointer still on the notch (Escape, a click): it opens again only after the
        // pointer has left, so the next small move doesn't undo the close.
        hover.didClose(pointerOnNotch: hoverRect.contains(NSEvent.mouseLocation))
        updatePoll()
        if isFullScreen { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.updateFullScreen() } }
    }
}

/// Everything the notch shows, shared across screens.
@MainActor
final class NotchServices: ObservableObject {
    let model: AppModel
    let focus: FocusController
    let clips: ClipsStore
    let reminders: ReminderCenter
    let live: NotchLiveCenter
    let dictation = DictationController()
    let notepad: NotepadStore
    var openMainWindow: () -> Void = {}

    init(model: AppModel) {
        self.model = model
        // A snapshot or stress-test run draws the notch but must not ring, poll, or save anything.
        let arguments = ProcessInfo.processInfo.arguments
        let isLive = !arguments.contains("-perchSnapshotDir") && !arguments.contains("-perchNavStress")
        focus = FocusController(log: model.focusLog)
        // Not live, Clips reads neither the pasteboard nor the screenshot folder, and saves nothing.
        clips = ClipsStore(isLive: isLive)
        reminders = ReminderCenter(model: model, isLive: isLive)
        live = NotchLiveCenter(model: model, focus: focus, isLive: isLive)
        notepad = NotepadStore(model: model)
        // Reminders and a finished timer ask from the closed notch; they no longer throw the panel open.
        reminders.onPrompt = { [weak self] prompt in self?.live.post(prompt, sound: "Tink") }
        live.onNeedsMainWindow = { [weak self] in self?.openMainWindow() }
        focus.onFinish = { [weak self] in
            guard let self, FocusAvailability.isAvailable() else { return }
            let title = self.model.task(id: self.focus.taskID)?.title ?? "Focus session"
            self.live.post(NotchPrompt(id: "focus|\(Date().timeIntervalSince1970)", kind: .focusFinished(taskID: self.focus.taskID), title: title, detail: "Time's up. Nicely done."))
        }
        if isLive { focusAvailabilityChanged() }
    }

    /// There is a notch to ask from, or there no longer is.
    func setNotchActive(_ active: Bool) {
        reminders.setActive(active)
        if !active { live.clear() }
    }

    /// "Hide the focus timer" may have changed. Hiding it ends a session under way (what was done is
    /// logged, as when it is stopped by hand) and takes away a finished timer's prompt.
    func focusAvailabilityChanged() {
        guard FocusAvailability.isHidden() else { return }
        focus.hide()
        live.dropFocusPrompts()
    }

    /// Completing from the notch reached a repeating task that needs its next date picked. That sheet
    /// is in the main window, so bring the window forward instead of leaving the tick doing nothing.
    func showNextDateSheetIfNeeded() {
        if model.needsNextDate != nil { openMainWindow() }
    }
}
