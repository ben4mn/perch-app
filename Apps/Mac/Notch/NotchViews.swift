import PerchKit
import PerchUI
import SwiftUI
import UniformTypeIdentifiers

/// One screen's notch: a single black shape and whatever it holds right now.
///
/// The shape is drawn once and only its outline changes, so the closed notch, the peek, the timer,
/// a prompt and the open panel grow out of each other. Content is laid out at its final size and
/// clipped by the shape, so nothing reflows while the shape moves.
struct NotchRootView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var services: NotchServices
    @ObservedObject private var live: NotchLiveCenter
    @ObservedObject private var focus: FocusController
    @ObservedObject private var themes = ThemeStore.shared
    @AppStorage("notchMotion") private var motionRaw = NotchMotionLevel.full.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glow = 0.0
    var close: () -> Void
    var expand: () -> Void

    init(state: NotchState, services: NotchServices, close: @escaping () -> Void, expand: @escaping () -> Void = {}) {
        self.state = state
        self.services = services
        live = services.live
        focus = services.focus
        self.close = close
        self.expand = expand
    }

    private var level: NotchMotionLevel { NotchMotionLevel(stored: motionRaw) }
    private var isOpen: Bool { state.phase == .open || state.stage?.openProgress != nil }

    var body: some View {
        let outline = state.outline
        let shape = NotchOutlineShape(outline)
        // How far "out of the notch" it is: drives the shadow and the lit lower edge.
        let lift = heldLift ?? (isOpen ? 1 : (state.phase == .prompt ? 0.7 : 0))
        ZStack(alignment: .top) {
            shape.fill(Ink.ground)
                .shadow(color: .black.opacity(0.42 * lift), radius: 16, y: 8)
            content.clipShape(shape)
            shape.stroke(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.13)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                .opacity(lift)
                .allowsHitTesting(false)
            // A timer finishing lights the edge once.
            shape.stroke(NotchTint.card(.focus).ink, lineWidth: 2.5)
                .opacity(glow)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .environment(\.perchTheme, themes.theme(for: .dark))
        .environment(\.notchMotion, level)
        // A held close has its content in place; a held opening shows where it has got to.
        .environment(\.notchReveal, state.stage?.closing == true ? 1 : state.stage?.openProgress)
        .environment(\.notchRevealTime, state.stage?.closing == true ? nil : state.stage?.revealTime)
        .transaction { transaction in
            // Off means off: nothing inside the notch animates, whatever asked for it.
            if level == .off {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .onChange(of: live.celebrations) {
            guard level == .full, !reduceMotion else { return }
            glow = 0.9
            withMotion(.easeOut(duration: 1.3), reduceMotion: reduceMotion) { glow = 0 }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        services.clips.addDropped(url)
                        state.panelMode = .clips
                    }
                }
            }
            return true
        }
    }

    @ViewBuilder private var content: some View {
        ZStack(alignment: .top) {
            if let change = state.stage?.change {
                // Snapshots only: a change between two closed shapes held part-way. What leaves fades as what
                // arrives fades in, as their transitions do in the app.
                restingContent(change.from).modifier(HeldSwap(amount: 1 - change.amount, swaps: change.from == .prompt))
                restingContent(change.to).modifier(HeldSwap(amount: change.amount, swaps: change.to == .prompt))
            } else if let progress = state.stage?.openProgress {
                // Snapshots only: the opening or the close held part-way. The counts leave (or come back) with
                // the shape's own spring; going back, the panel fades as a whole as the shape closes over it.
                let closing = state.stage?.closing == true
                if state.showsAmbient {
                    ambientStrip(peek: closing ? 0 : state.stage?.hover ?? 0).opacity(min(max(1 - progress, 0), 1))
                }
                openView.opacity(closing ? min(max(progress, 0), 1) : 1)
            } else if isOpen {
                openView
                    // Its pieces arrive on their own; leaving, the whole thing fades as the shape closes over it.
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
            } else if state.phase == .prompt, let prompt = live.current {
                promptView(prompt)
                    .id(prompt.id)
                    .transition(.perchSwap(reduceMotion: reduceMotion || level != .full))
            } else if state.phase == .live {
                liveStrip.transition(.opacity)
            } else if state.showsAmbient {
                ambientStrip(peek: state.stage?.hover ?? (state.isHovering ? 1 : 0)).transition(.opacity)
            }
        }
    }

    /// How far out of the notch a held moment is, when one is held.
    private var heldLift: Double? {
        func lift(_ phase: NotchPhase) -> Double { phase == .open ? 1 : (phase == .prompt ? 0.7 : 0) }
        if let change = state.stage?.change { return lift(change.from) + (lift(change.to) - lift(change.from)) * change.amount }
        return state.stage?.openProgress
    }

    private var openView: some View {
        NotchOpenView(state: state, services: services, close: close)
            .frame(width: state.openSize.width, height: state.openSize.height)
    }

    private func promptView(_ prompt: NotchPrompt) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: state.neck.height)
            PromptContent(prompt: prompt, live: live, model: services.model)
                .frame(height: NotchState.promptBody.height)
        }
        .frame(width: state.outline(for: .prompt).width)
        .contentShape(Rectangle())
        .onTapGesture(perform: expand)
    }

    private var liveStrip: some View {
        let neck = state.neck, size = state.outline(for: .live).resolved
        return FocusLiveStrip(focus: focus, notchWidth: neck.width, neckHeight: neck.height, place: state.liveBeside ? .beside : (state.geometry.hasHardwareNotch ? .below : .pill))
            .frame(width: size.width, height: size.height)
    }

    private func ambientStrip(peek: Double) -> some View {
        AmbientStrip(model: services.model, notchWidth: state.neck.width, peek: peek, isOnScreen: state.isOnScreen)
            .frame(width: state.neck.width + NotchState.ear * 2, height: state.neck.height)
    }

    /// What one of the closed shapes holds, for a held change between two of them.
    @ViewBuilder private func restingContent(_ phase: NotchPhase) -> some View {
        switch phase {
        case .prompt: if let prompt = live.current { promptView(prompt) }
        case .live: liveStrip
        case .closed: if state.showsAmbient { ambientStrip(peek: 0) }
        case .open: openView
        }
    }
}

/// A held `perchSwap`: content part-way in (1) or out (0), faded, a little smaller and lower. Without
/// `swaps` it only fades, as `.opacity` does.
private struct HeldSwap: ViewModifier {
    var amount: Double
    var swaps: Bool

    func body(content: Content) -> some View {
        let clamped = min(max(amount, 0), 1)
        content
            .opacity(clamped)
            .scaleEffect(swaps ? 0.985 + 0.015 * amount : 1)
            .offset(y: swaps ? 6 * (1 - amount) : 0)
    }
}

// MARK: - The open panel

struct NotchOpenView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var services: NotchServices
    @ObservedObject private var live: NotchLiveCenter
    @Environment(\.notchMotion) private var level
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var close: () -> Void
    @Namespace private var switcher

    init(state: NotchState, services: NotchServices, close: @escaping () -> Void) {
        self.state = state
        self.services = services
        live = services.live
        self.close = close
    }

    var body: some View {
        VStack(spacing: 6) {
            header.notchStaged(0)
            Group {
                switch state.panelMode {
                case .workspace:
                    NotchCardsRow(state: state, services: services)
                case .week:
                    WeekPane(model: services.model).notchStaged(1)
                case .insights:
                    InsightsPane(model: services.model).notchStaged(1)
                case .clips:
                    ClipsPane(clips: services.clips).notchStaged(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .id(state.panelMode)
            .transition(.perchSwap(reduceMotion: reduceMotion || level != .full))
            // Something came due while the panel is open: it asks from a bar at the foot. The bar takes
            // its own row and the cards shorten to make room, so it never lies over a button or a field.
            if let prompt = live.current {
                PromptContent(prompt: prompt, live: live, model: services.model)
                    .frame(height: 42)
                    .frame(maxWidth: 520)
                    .background(Capsule().fill(Color(white: 0.13)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                    .id(prompt.id)
                    .transition(.perchBanner(from: .bottom, reduceMotion: reduceMotion || level != .full))
            }
        }
        .padding(.horizontal, NotchLayout.sidePadding)
        .padding(.bottom, 12)
        .foregroundStyle(Ink.text)
        .font(.system(size: 12.5))
        .animation(Motion.notch(.arrange, level: level, reduceMotion: reduceMotion), value: live.current?.id)
        .onExitCommand(perform: close)
    }

    /// Modes on the left, agents on the right, and the camera's width kept empty in the middle.
    private var header: some View {
        let neck = state.neck
        return HStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                modeSwitch(showsTitles: true)
                modeSwitch(showsTitles: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: state.geometry.hasHardwareNotch ? neck.width + 16 : 0)
            HStack(spacing: 6) {
                AgentFaces(model: services.model)
                Button {
                    services.openMainWindow()
                    close()
                } label: {
                    Image(systemName: "arrow.up.forward.app").font(.system(size: 12)).foregroundStyle(Ink.dim).frame(width: 26, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .notchHover(scale: 1.12)
                .help("Open Perch")
                .accessibilityLabel("Open Perch")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: max(neck.height, 30))
    }

    private func modeSwitch(showsTitles: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(NotchPanelMode.allCases) { mode in
                ModeButton(mode: mode, isSelected: state.panelMode == mode, showsTitle: showsTitles, namespace: switcher) {
                    withNotchMotion(.arrange, level: level, reduceMotion: reduceMotion) { state.panelMode = mode }
                }
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .fixedSize()
    }
}

private struct ModeButton: View {
    let mode: NotchPanelMode
    let isSelected: Bool
    let showsTitle: Bool
    let namespace: Namespace.ID
    var select: () -> Void
    @State private var hovering = false
    @State private var dragOver = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 4) {
                if !showsTitle { Image(systemName: mode.symbol).font(.system(size: 11, weight: .medium)) }
                if showsTitle { Text(mode.rawValue).font(.system(size: 11.5, weight: .medium)) }
            }
            .foregroundStyle(isSelected ? Ink.text : (hovering ? Ink.text.opacity(0.8) : Ink.dim))
            .padding(.horizontal, showsTitle ? 10 : 9)
            .frame(height: 22)
            .background {
                if isSelected {
                    Capsule().fill(Color.white.opacity(0.16)).matchedGeometryEffect(id: "mode", in: namespace)
                } else if dragOver {
                    Capsule().strokeBorder(Ink.accent, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(mode.rawValue)
        .accessibilityLabel(mode.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        // Carrying a task over "Week" opens the week, so it can be dropped on a day.
        .dropDestination(for: String.self) { _, _ in false } isTargeted: { over in
            dragOver = over && mode == .week
            if over, mode == .week, !isSelected { select() }
        }
    }
}

struct AgentFaces: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: -5) {
            ForEach(model.agents.filter(\.isActive).prefix(4)) { agent in
                AgentFace(name: agent.name, size: 18)
                    .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                    .help("\(agent.name): \(agent.status)")
                    .accessibilityLabel("\(agent.name): \(agent.status)")
            }
        }
    }
}

// MARK: - Week

/// Seven days ahead beside today's list: drag a task onto a day to move it there.
struct WeekPane: View {
    @ObservedObject var model: AppModel
    @Environment(\.notchMotion) private var level
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let listWidth: CGFloat = 180

    var body: some View {
        GeometryReader { geometry in
            let count = NotchLayout.weekDays(available: geometry.size.width, listWidth: listWidth)
            content(days: (0..<count).compactMap { DayMath.adding(days: $0, to: model.today) })
        }
    }

    private func content(days: [String]) -> some View {
        let tint = NotchTint.card(.today)
        let overdue = TaskCalendar.overdue(model.tasks, today: model.today).sorted(by: AppModel.ordered)
        let byDay = TaskCalendar.byDay(model.tasks.filter(\.isOpen))
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("To place").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("\(overdue.count) overdue").font(.system(size: 10.5)).foregroundStyle(overdue.isEmpty ? Ink.dim : Ink.danger)
                }
                if overdue.isEmpty {
                    Text("Nothing is overdue. Drag any task between days to move it.")
                        .font(.system(size: 11)).foregroundStyle(Ink.dim)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    VStack(spacing: 1) {
                        ForEach(overdue.prefix(8)) { task in WeekTaskChip(task: task, showsDate: true) }
                    }
                    .animation(Motion.notch(.arrange, level: level, reduceMotion: reduceMotion), value: overdue.prefix(8).map(\.id))
                    Spacer(minLength: 0)
                    if overdue.count > 8 { Text("\(overdue.count - 8) more").font(.system(size: 10.5)).foregroundStyle(Ink.faint) }
                }
            }
            .padding(10)
            .frame(width: listWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(NotchCardSurface(tint: tint))
            ForEach(days, id: \.self) { day in
                WeekDayCell(model: model, day: day, tasks: (byDay[day] ?? []).sorted(by: TaskCalendar.inDayOrder), tint: tint)
            }
        }
    }
}

private struct WeekTaskChip: View {
    let task: PerchTask
    var showsDate = false
    /// Day cells are narrow, so a title there may wrap once.
    var wraps = false
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: wraps ? 4 : 6) {
            Circle().fill(Ink.priority(task.priority)).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 2.5 }
            Text(task.title).font(.system(size: wraps ? 10.5 : 11)).lineLimit(wraps ? 2 : 1).multilineTextAlignment(.leading)
            Spacer(minLength: 2)
            if showsDate, let due = task.due, let date = DayMath.date(from: due) {
                Text(date.formatted(.dateTime.month(.abbreviated).day())).font(.system(size: 10)).foregroundStyle(Ink.dim)
            }
        }
        .padding(.horizontal, wraps ? 4 : 6).padding(.vertical, wraps ? 3 : 0).frame(height: wraps ? nil : 21)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovering ? Color.white.opacity(0.1) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .draggable(task.id) { NotchDragPreview(task: task) }
        .help(task.title)
    }
}

private struct WeekDayCell: View {
    @ObservedObject var model: AppModel
    let day: String
    let tasks: [PerchTask]
    let tint: NotchTint
    @Environment(\.notchMotion) private var level
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var targeted = false
    @State private var drops = 0

    private var isToday: Bool { day == model.today }

    var body: some View {
        let date = DayMath.date(from: day) ?? Date()
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 9.5, weight: .semibold)).foregroundStyle(isToday ? tint.ink : Ink.dim).fixedSize()
                Spacer(minLength: 0)
                Text("\(tasks.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Ink.dim)
                    .contentTransition(.numericText())
                    .motion(Motion.smooth, value: tasks.count)
                    .opacity(tasks.isEmpty ? 0 : 1)
            }
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(isToday ? tint.ink : Ink.text)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(tasks.prefix(4)) { task in
                    WeekTaskChip(task: task, wraps: true).padding(.horizontal, -4)
                        .transition(.perchRow(reduceMotion: reduceMotion || level != .full))
                }
            }
            .motion(Motion.smooth, value: tasks.prefix(4).map(\.id))
            Spacer(minLength: 0)
            if targeted {
                Label("Move here", systemImage: "arrow.down.to.line").font(.system(size: 10, weight: .semibold)).foregroundStyle(tint.ink)
                    .transition(.opacity)
            } else if tasks.count > 4 {
                Text("+\(tasks.count - 4) more").font(.system(size: 10)).foregroundStyle(Ink.faint)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(targeted ? tint.ink.opacity(0.2) : Color.white.opacity(isToday ? 0.09 : 0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(targeted ? tint.ink : (isToday ? tint.ink.opacity(0.35) : .clear), lineWidth: targeted ? 1.5 : 1)
        )
        // The lift and the bounce after a drop are for Full only; Subtle and Off just show the highlight.
        .lift(targeted && level == .full, scale: 1.035)
        .settle(on: level == .full ? drops : 0)
        .motion(Motion.quick, value: targeted)
        .dropDestination(for: String.self) { ids, _ in
            let moved = model.move(taskIDs: ids, to: day)
            if !moved.isEmpty { drops += 1 }
            return !moved.isEmpty
        } isTargeted: { targeted = $0 }
    }
}

/// What follows the pointer while a task is dragged out of the notch.
struct NotchDragPreview: View {
    let task: PerchTask

    var body: some View {
        HStack(spacing: 7) {
            Circle().strokeBorder(Ink.priority(task.priority), lineWidth: 1.6).frame(width: 13, height: 13)
            Text(task.title).font(.system(size: 12)).foregroundStyle(Ink.text).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(maxWidth: 240, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(white: 0.16)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Ink.accent.opacity(0.6), lineWidth: 1))
    }
}

// MARK: - Insights

struct InsightsPane: View {
    @ObservedObject var model: AppModel
    @AppStorage(FocusAvailability.hiddenKey) private var focusHidden = FocusAvailability.hiddenByDefault

    private var insights: Insights { Insights.compute(tasks: model.tasks, focus: model.focusLog.sessions) }

    /// One honest line about the week, from the numbers.
    static func headline(_ insights: Insights) -> String {
        if insights.streakDays >= 3 { return "\(insights.streakDays) days in a row" }
        if insights.completedThisWeek == 0 { return "A quiet week so far" }
        if insights.overdue == 0 { return "All caught up" }
        let today = insights.lastSevenDays.last?.completed ?? 0
        let earlier = insights.lastSevenDays.dropLast().map(\.completed).max() ?? 0
        if today > 0, today >= earlier { return "Your best day this week" }
        return "Steady progress"
    }

    var body: some View {
        let insights = insights
        let tint = NotchTint.card(.agents)
        let chartTint = NotchTint.card(.focus)
        let planned = TaskCalendar.byDay(model.tasks)
        HStack(spacing: NotchLayout.cardSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.headline(insights)).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint.ink)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(insights.completedThisWeek)")
                        .font(.system(size: 54, weight: .semibold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                        .motion(Motion.smooth, value: insights.completedThisWeek)
                    Text("\(insights.completedThisWeek == 1 ? "task" : "tasks") done\nin 7 days").font(.system(size: 11.5)).foregroundStyle(Ink.dim)
                }
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    // Focus time is left out while the focus timer is hidden in Settings.
                    if !focusHidden { stat(insights.focusMinutesThisWeek >= 60 ? "\(insights.focusMinutesThisWeek / 60)h \(insights.focusMinutesThisWeek % 60)m" : "\(insights.focusMinutesThisWeek)m", "Focus", "timer") }
                    stat("\(insights.streakDays)", insights.streakDays == 1 ? "Day streak" : "Days streak", "flame")
                    stat("\(insights.open)", "Open", "circle")
                    stat("\(insights.overdue)", "Overdue", "exclamationmark.circle", color: insights.overdue > 0 ? Ink.danger : nil)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(NotchCardSurface(tint: tint))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("This week").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    legend("Done", fill: chartTint.ink)
                    legend("Planned", fill: Color.white.opacity(0.16))
                }
                let top = max(insights.lastSevenDays.map { max($0.completed, planned[$0.date]?.count ?? 0) }.max() ?? 1, 1)
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(insights.lastSevenDays.enumerated()), id: \.element.id) { index, day in
                        InsightBar(
                            day: day, planned: planned[day.date]?.count ?? 0, top: top,
                            isToday: day.date == model.today, tint: chartTint, index: index
                        )
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(NotchCardSurface(tint: chartTint))
        }
    }

    private func stat(_ value: String, _ label: String, _ symbol: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(color ?? Ink.dim)
            Text(value).font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(color ?? Ink.text)
            Text(label).font(.system(size: 10)).foregroundStyle(Ink.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legend(_ title: String, fill: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(fill).frame(width: 8, height: 8)
            Text(title).font(.system(size: 10)).foregroundStyle(Ink.dim)
        }
    }
}

/// One day of the chart: what was planned behind, what got done in front. The bar grows from the
/// floor as the panel arrives; only its scale animates.
private struct InsightBar: View {
    let day: Insights.Day
    let planned: Int
    let top: Int
    let isToday: Bool
    let tint: NotchTint
    let index: Int
    @Environment(\.notchMotion) private var level
    @Environment(\.notchReveal) private var reveal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        let amount = reveal.map { NotchReveal.amount(progress: $0, index: index + 1) } ?? (grown ? 1 : 0)
        VStack(spacing: 5) {
            Text("\(day.completed)")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(day.completed > 0 ? Ink.text : Ink.faint)
            GeometryReader { geometry in
                let height = geometry.size.height
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: max(CGFloat(planned) / CGFloat(top) * height, 5))
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(LinearGradient(colors: [tint.ink, tint.ink.opacity(0.62)], startPoint: .top, endPoint: .bottom))
                        .frame(height: max(CGFloat(day.completed) / CGFloat(top) * height, day.completed > 0 ? 5 : 0))
                        .opacity(isToday ? 1 : 0.7)
                        .scaleEffect(y: amount, anchor: .bottom)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            Text((DayMath.date(from: day.date) ?? Date()).formatted(.dateTime.weekday(.narrow)))
                .font(.system(size: 10, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? tint.ink : Ink.dim)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            guard reveal == nil else { return }
            guard let animation = Motion.notch(.settle, level: level, reduceMotion: reduceMotion) else {
                grown = true
                return
            }
            withAnimation(animation.delay(Motion.notchStagger(index + 2, level: level, reduceMotion: reduceMotion))) { grown = true }
        }
    }
}

// MARK: - Notepad editor

struct NotepadEditor: NSViewRepresentable {
    @Binding var text: String
    var onCommandReturn: (Int) -> Void

    final class CommandTextView: NSTextView {
        var onCommandReturn: ((Int) -> Void)?
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36, event.modifierFlags.contains(.command) {
                onCommandReturn?(selectedRange().location)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let view = CommandTextView()
        view.isRichText = false
        view.drawsBackground = false
        view.font = .systemFont(ofSize: 13)
        view.textColor = NSColor.white.withAlphaComponent(0.92)
        view.insertionPointColor = NSColor(Ink.accent)
        view.delegate = context.coordinator
        view.autoresizingMask = [.width]
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        view.textContainerInset = NSSize(width: 4, height: 6)
        view.string = text
        view.onCommandReturn = onCommandReturn
        scroll.documentView = view
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? CommandTextView else { return }
        view.onCommandReturn = onCommandReturn
        if view.string != text { view.string = text }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotepadEditor
        init(_ parent: NotepadEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let view = notification.object as? NSTextView { parent.text = view.string }
        }
    }
}
