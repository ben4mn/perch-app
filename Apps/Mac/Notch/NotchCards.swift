import AppKit
import PerchKit
import PerchUI
import SwiftUI

/// A card's background: a deep tint of its color, lit a little from the top, with a hairline edge.
struct NotchCardSurface: View {
    var tint: NotchTint
    var radius: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LinearGradient(colors: [tint.surfaceTop, tint.surfaceBottom], startPoint: .top, endPoint: .bottom))
            .overlay(
                // A soft highlight in one corner stands in for texture, and costs nothing to draw.
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(RadialGradient(colors: [tint.ink.opacity(0.1), .clear], center: .topLeading, startRadius: 0, endRadius: 190))
            )
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(tint.edge, lineWidth: 1))
    }
}

// MARK: - The row of cards

/// The workspace: cards side by side, each with a handle to drag it to a new place.
struct NotchCardsRow: View {
    @ObservedObject var state: NotchState
    @ObservedObject var services: NotchServices
    @AppStorage("notchCardOrder") private var storedOrder = ""
    @AppStorage(FocusAvailability.hiddenKey) private var focusHidden = FocusAvailability.hiddenByDefault
    @Environment(\.notchMotion) private var level
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var liveOrder: [NotchCardKind]?
    @State private var dragging: NotchCardKind?
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let saved = NotchCardOrder.decode(storedOrder)
            // With the focus timer hidden its card is left out and the others share the row.
            let visible = NotchLayout.visibleCards(NotchCardOrder.shown(saved, focusHidden: focusHidden), available: geometry.size.width)
            let widths = NotchLayout.widths(visible, available: geometry.size.width)
            let held = state.stage?.drag ?? dragging
            let offset = state.stage?.drag != nil ? state.stage?.dragOffset ?? 0 : dragOffset
            let home = NotchLayout.origins(visible, widths: widths)
            let order = held.map { kind in
                liveOrder ?? NotchLayout.reordered(visible, dragging: kind, centerX: (home[kind] ?? 0) + (widths[kind] ?? 0) / 2 + offset, widths: widths)
            } ?? visible
            let origins = NotchLayout.origins(order, widths: widths)
            ZStack(alignment: .topLeading) {
                ForEach(Array(visible.enumerated()), id: \.element) { index, kind in
                    let isHeld = held == kind
                    NotchCardFrame(
                        kind: kind, isHeld: isHeld,
                        moveLeft: index > 0 ? { move(kind, by: -1, visible: visible, saved: saved) } : nil,
                        moveRight: index < visible.count - 1 ? { move(kind, by: 1, visible: visible, saved: saved) } : nil,
                        handle: DragGesture(minimumDistance: 3, coordinateSpace: .named("notchCards"))
                            .onChanged { value in
                                dragging = kind
                                dragOffset = value.translation.width
                                let center = (home[kind] ?? 0) + (widths[kind] ?? 0) / 2 + value.translation.width
                                let next = NotchLayout.reordered(visible, dragging: kind, centerX: center, widths: widths)
                                if next != liveOrder {
                                    withNotchMotion(.arrange, level: level, reduceMotion: reduceMotion) { liveOrder = next }
                                }
                            }
                            .onEnded { _ in
                                let final = liveOrder ?? visible
                                // Saved only now, on the drop, and only if something moved. A card that isn't
                                // on screen (Focus while hidden, one that didn't fit) keeps its place.
                                let next = NotchCardOrder.encode(NotchCardOrder.merging(final, into: saved))
                                if final != visible, next != storedOrder { storedOrder = next }
                                withNotchMotion(.settle, level: level, reduceMotion: reduceMotion) {
                                    dragging = nil
                                    dragOffset = 0
                                    liveOrder = nil
                                }
                            }
                    ) {
                        card(kind)
                    }
                    .frame(width: widths[kind] ?? 0, height: geometry.size.height)
                    .offset(x: isHeld ? (home[kind] ?? 0) + offset : (origins[kind] ?? 0))
                    .zIndex(isHeld ? 1 : 0)
                    .notchStaged(index + 1)
                }
            }
            .coordinateSpace(name: "notchCards")
        }
    }

    /// Moves a card one place without dragging: from its handle's menu, or by VoiceOver.
    private func move(_ kind: NotchCardKind, by offset: Int, visible: [NotchCardKind], saved: [NotchCardKind]) {
        let next = NotchCardOrder.moved(visible, kind, by: offset)
        guard next != visible else { return }
        withNotchMotion(.arrange, level: level, reduceMotion: reduceMotion) {
            storedOrder = NotchCardOrder.encode(NotchCardOrder.merging(next, into: saved))
        }
    }

    @ViewBuilder private func card(_ kind: NotchCardKind) -> some View {
        let tint = NotchTint.card(kind)
        switch kind {
        case .today:
            TodayCard(services: services, model: services.model, focus: services.focus, tint: tint, focusQuickAdd: $state.focusQuickAdd, heldCompletion: state.stage?.completion,
                      heldTick: state.stage?.tickTime.map(HeldTick.init(time:)), showsFocus: !focusHidden)
        case .focus:
            FocusCard(focus: services.focus, model: services.model, tint: tint)
        case .notepad:
            NotepadCard(store: services.notepad, model: services.model, tint: tint)
        case .agents:
            AgentsCard(model: services.model, tint: tint, needsMainWindow: services.showNextDateSheetIfNeeded) {
                services.model.show(view: .ready)
                services.openMainWindow()
            }
        }
    }
}

/// A card's surface and its grab handle. Picked up, it lifts and tilts a touch; put down, it settles.
private struct NotchCardFrame<Content: View, Handle: Gesture>: View {
    let kind: NotchCardKind
    let isHeld: Bool
    /// Nil when the card is already at that end.
    var moveLeft: (() -> Void)?
    var moveRight: (() -> Void)?
    let handle: Handle
    @ViewBuilder var content: Content
    @Environment(\.notchMotion) private var level
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var handleHover = false

    var body: some View {
        let tint = NotchTint.card(kind)
        let moves = level == .full && !reduceMotion
        VStack(spacing: 0) {
            Capsule()
                .fill(tint.ink.opacity(handleHover || isHeld ? 0.75 : 0.28))
                .frame(width: handleHover || isHeld ? 34 : 26, height: 4)
                .frame(maxWidth: .infinity)
                .frame(height: 14)
                .contentShape(Rectangle())
                .onHover { value in
                    withNotchMotion(.peek, level: level, reduceMotion: reduceMotion) { handleHover = value }
                }
                .gesture(handle)
                .help("Drag to reorder, or right-click to move")
                // The same reordering without a drag: a menu on the handle, and actions for VoiceOver.
                .contextMenu {
                    Button("Move Left") { moveLeft?() }.disabled(moveLeft == nil)
                    Button("Move Right") { moveRight?() }.disabled(moveRight == nil)
                }
                .accessibilityElement()
                .accessibilityLabel("\(kind.rawValue.capitalized) card")
                .accessibilityHint("Drag to reorder, or use the Move Left and Move Right actions")
                .accessibilityAction(named: "Move Left") { moveLeft?() }
                .accessibilityAction(named: "Move Right") { moveRight?() }
            content
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .background(NotchCardSurface(tint: tint))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(isHeld ? 0.55 : 0), radius: 14, y: 8)
        .scaleEffect(isHeld && moves ? 1.035 : 1)
        .rotationEffect(.degrees(isHeld && moves ? -1.2 : 0))
        .animation(Motion.notch(.settle, level: level, reduceMotion: reduceMotion), value: isHeld)
    }
}

/// A card's title line: its name on the left, whatever it wants on the right.
private struct CardHeader<Trailing: View>: View {
    let title: String
    let tint: NotchTint
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Ink.text).lineLimit(1)
            Spacer(minLength: 4)
            trailing
        }
        .frame(height: 22)
    }
}

private struct IconButton: View {
    let symbol: String
    var size: CGFloat = 20
    var tint: Color = Ink.dim
    var help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(PerchPressStyle())
        .notchHover(scale: 1.12)
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Today

struct TodayCard: View {
    @ObservedObject var services: NotchServices
    @ObservedObject var model: AppModel
    @ObservedObject var focus: FocusController
    let tint: NotchTint
    @Binding var focusQuickAdd: Bool
    /// A snapshot holding the first task mid-completion.
    var heldCompletion: CGFloat?
    /// A snapshot holding the first task's tick at a moment of its movement, counts included.
    var heldTick: HeldTick?
    /// False while the focus timer is hidden in Settings: rows then have no "focus on this" button.
    var showsFocus = true
    @Environment(\.notchMotion) private var level
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("notchFocusMinutes") private var focusMinutes = 25
    @State private var dayOffset = 0
    @State private var showsDone = false
    /// A local filter. The notch always works on every area's tasks; this only narrows what the card lists.
    @State private var area: String?
    @State private var justAdded: String?
    @State private var flourish = 0

    private var day: String { DayMath.adding(days: dayOffset, to: model.today) ?? model.today }

    private var openTasks: [PerchTask] {
        var tasks = NotchDay.open(model.tasks, day: day, today: model.today, area: area).sorted(by: AppModel.ordered)
        // What was just added shows first for a moment, wherever it sorts.
        if let justAdded, let index = tasks.firstIndex(where: { $0.id == justAdded }) { tasks.insert(tasks.remove(at: index), at: 0) }
        return tasks
    }

    private var doneTasks: [PerchTask] { NotchDay.done(model.tasks, day: day, area: area) }

    private var dayTitle: String {
        switch dayOffset {
        case 0: return "Today"
        case 1: return "Tomorrow"
        default: return (DayMath.date(from: day) ?? Date()).formatted(.dateTime.weekday(.wide))
        }
    }

    var body: some View {
        let open = openTasks, done = doneTasks
        let heldTicked = heldTick?.isTicked == true && !showsDone ? open.first?.id : nil
        let remaining = open.filter { !model.completing.contains($0.id) && $0.id != heldTicked }.count
        let progress = NotchDay.progress(open: remaining, done: done.count + (open.count - remaining))
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Text(dayTitle).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    .contentTransition(.opacity)
                DayRing(progress: progress, tint: tint, flourish: flourish)
                Spacer(minLength: 4)
                HStack(spacing: 3) {
                    IconButton(symbol: "chevron.left", size: 18, help: "Earlier day") { step(-1) }
                        .opacity(dayOffset > 0 ? 1 : 0.35).disabled(dayOffset == 0)
                    IconButton(symbol: "chevron.right", size: 18, help: "Later day") { step(1) }
                        .opacity(dayOffset < 6 ? 1 : 0.35).disabled(dayOffset == 6)
                }
            }
            .frame(height: 22)
            HStack(spacing: 5) {
                CountPill(title: "To do", count: remaining, isSelected: !showsDone, tint: tint) { show(done: false) }
                CountPill(title: "Done", count: done.count + (open.count - remaining), isSelected: showsDone, tint: tint) { show(done: true) }
                Spacer(minLength: 2)
                if model.visibleAreas.count > 1 { areaChip }
            }
            GeometryReader { geometry in
                let list = showsDone ? done : open
                let rows = max(1, Int((geometry.size.height - (list.count > 5 ? 16 : 0)) / 25))
                let shown = Array(list.prefix(rows))
                // A held tick past the moment its row leaves: the row fades and shrinks as the rows below
                // close up, and the next task comes in at the foot, as the transitions play.
                let leaving = showsDone ? nil : heldTick?.leave
                VStack(alignment: .leading, spacing: 0) {
                    if list.isEmpty {
                        VStack(spacing: 5) {
                            Image(systemName: showsDone ? "circle.dashed" : "sun.max").font(.system(size: 18)).foregroundStyle(tint.ink)
                            Text(showsDone ? "Nothing ticked yet" : (dayOffset == 0 ? "Clear for today" : "Nothing planned")).font(.system(size: 11.5)).foregroundStyle(Ink.dim)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                    } else {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, task in
                            NotchTaskRow(
                                model: model, task: task, isDone: showsDone, tint: tint,
                                heldBurst: index == 0 && !showsDone ? heldCompletion : nil,
                                heldTick: index == 0 && !showsDone ? heldTick : nil,
                                startFocus: showsFocus ? { startFocus(on: task) } : nil, open: { openTask(task) },
                                needsMainWindow: services.showNextDateSheetIfNeeded
                            )
                            .frame(height: 25)
                            .modifier(HeldRowLeave(amount: leaving, isLeaving: index == 0))
                            .transition(rowTransition(for: task))
                        }
                        Spacer(minLength: 0)
                        let more = list.count - shown.count - ((leaving ?? 0) >= 0.5 ? 1 : 0)
                        if more > 0 {
                            Button(action: services.openMainWindow) {
                                Text("\(more) more in Perch").font(.system(size: 10.5)).foregroundStyle(Ink.dim)
                                    .padding(.leading, 23).frame(height: 16)
                            }
                            .buttonStyle(.plain)
                            .notchHover(scale: 1.02)
                        }
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let leaving, list.count > shown.count {
                        NotchTaskRow(model: model, task: list[shown.count], tint: tint, startFocus: nil, open: {})
                            .frame(height: 25)
                            .opacity(min(max(leaving, 0), 1))
                            .scaleEffect(0.92 + 0.08 * leaving, anchor: .top)
                            .offset(y: 25 * CGFloat(shown.count - 1))
                    }
                }
                .animation(Motion.notch(.arrange, level: level, reduceMotion: reduceMotion), value: shown.map(\.id))
            }
            NotchQuickAdd(services: services, tint: tint, defaultDue: day, shouldFocus: $focusQuickAdd) { task in
                withNotchMotion(.arrange, level: level, reduceMotion: reduceMotion) {
                    showsDone = false
                    justAdded = task.id
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if justAdded == task.id {
                        withNotchMotion(.arrange, level: level, reduceMotion: reduceMotion) { justAdded = nil }
                    }
                }
            }
        }
        .onChange(of: progress) { old, new in
            // The day's ring closing is worth one flourish, once each time it closes.
            if new >= 1, old < 1, dayOffset == 0, level == .full { flourish += 1 }
        }
    }

    /// A new task drops in from the add field below; everything else closes up as rows do in the app.
    private func rowTransition(for task: PerchTask) -> AnyTransition {
        let plain = reduceMotion || level != .full
        if task.id == justAdded, !plain {
            // It travels up from the add field to its place at the top of the list.
            return .asymmetric(
                insertion: .offset(y: 104).combined(with: .scale(scale: 0.94, anchor: .leading)).combined(with: .opacity),
                removal: .perchRow(reduceMotion: plain)
            )
        }
        return .perchRow(reduceMotion: plain)
    }

    private var areaChip: some View {
        Button {
            let areas = model.visibleAreas
            withNotchMotion(.arrange, level: level, reduceMotion: reduceMotion) {
                if let area, let index = areas.firstIndex(of: area) {
                    self.area = index + 1 < areas.count ? areas[index + 1] : nil
                } else {
                    area = areas.first
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "line.3.horizontal.decrease").font(.system(size: 8.5, weight: .bold))
                Text(area ?? "All").font(.system(size: 10.5, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(area == nil ? Ink.dim : tint.ink)
            .padding(.horizontal, 7).frame(height: 20)
            .frame(maxWidth: 92)
            .fixedSize()
            .background(Capsule().fill(tint.well))
            .contentShape(Capsule())
        }
        .buttonStyle(PerchPressStyle())
        .notchHover(scale: 1.05)
        .help("Show one area's tasks. Click to step through your areas.")
    }

    private func step(_ change: Int) {
        withNotchMotion(.arrange, level: level, reduceMotion: reduceMotion) { dayOffset = min(max(dayOffset + change, 0), 6) }
    }

    private func show(done: Bool) {
        withNotchMotion(.arrange, level: level, reduceMotion: reduceMotion) { showsDone = done }
    }

    private func startFocus(on task: PerchTask) {
        guard showsFocus else { return }
        if focusMinutes > 0 { focus.startCountdown(minutes: focusMinutes, task: task.id) } else { focus.startStopwatch(task: task.id) }
    }

    private func openTask(_ task: PerchTask) {
        model.selectedTaskID = task.id
        services.openMainWindow()
    }
}

/// The day's progress as a small ring. When it closes it throws one ring outward.
private struct DayRing: View {
    var progress: Double
    var tint: NotchTint
    var flourish: Int

    var body: some View {
        ZStack {
            ProgressRing(progress: progress, lineWidth: 2.2, tint: tint.ink)
            if progress >= 1 {
                CheckMarkShape().stroke(tint.ink, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)).padding(1)
                    .transition(.opacity)
            }
            CompletionBurst(color: tint.ink, trigger: flourish)
        }
        .frame(width: 13, height: 13)
        .motion(Motion.smooth, value: progress >= 1)
        .help("\(Int((progress * 100).rounded()))% of the day's tasks done")
    }
}

private struct CountPill: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let tint: NotchTint
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 10.5, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
                    .motion(Motion.smooth, value: count)
                    .opacity(0.75)
            }
            .foregroundStyle(isSelected ? Color.black : Ink.dim)
            .padding(.horizontal, 8).frame(height: 20)
            .background(Capsule().fill(isSelected ? tint.ink : tint.well))
            .contentShape(Capsule())
        }
        .buttonStyle(PerchPressStyle())
        .notchHover(scale: 1.05)
    }
}

/// A tick held at one moment of its movement, for a snapshot: where every piece of the row is `time`
/// seconds after the click, each on the curve the app animates it with. Before zero the pointer is on
/// its way: the row lights up, then the circle half-fills under it.
struct HeldTick: Equatable {
    var time: Double
    /// How long before the click the pointer reaches the row, and then the circle.
    static let rowLead = 0.55, checkLead = 0.25

    var isTicked: Bool { time >= 0 }
    /// The row's highlight, as `hovering` animates it.
    var rowHover: Double { Motion.notchCurve(.content).value(at: time + Self.rowLead) }
    /// The circle's half fill under the pointer.
    var checkHover: Double { Motion.quickCurve.value(at: time + Self.checkLead) }
    /// From the half fill to full, with the bounce.
    var fill: Double { Motion.bouncyCurve.value(at: time) }
    /// The tick drawing on, a moment after the fill starts.
    var trim: Double { MotionCurve.easeOut(duration: 0.22).value(at: time, delay: 0.08) }
    /// The title's strike.
    var sweep: Double { Motion.smoothCurve.value(at: time) }
    /// The ring and sparks, as `CompletionBurst` plays them; nil before the click.
    var burst: CGFloat? { isTicked ? CGFloat(MotionCurve.easeOut(duration: 0.46).value(at: time)) : nil }
    /// The row leaving the list once the tick is written (`Motion.completionDelay` after the click), as the
    /// list's `arrange` animation plays it; nil until then.
    var leave: Double? {
        let start = Motion.completionDelay(reduceMotion: false)
        return time >= start ? Motion.notchCurve(.arrange).value(at: time - start) : nil
    }
}

/// A held row leaving: the ticked one fades and shrinks to the top (`perchRow`), the ones below move up.
private struct HeldRowLeave: ViewModifier {
    var amount: Double?
    var isLeaving: Bool

    func body(content: Content) -> some View {
        if let amount {
            content
                .opacity(isLeaving ? 1 - min(max(amount, 0), 1) : 1)
                .scaleEffect(isLeaving ? 1 - 0.08 * amount : 1, anchor: .top)
                .offset(y: isLeaving ? 0 : -25 * amount)
        } else {
            content
        }
    }
}

/// The app's completion check, at the notch's size: the fill springs, the tick draws on, sparks fly.
private struct NotchCheck: View {
    var color: Color
    var isDone: Bool
    var burst: Int
    var heldBurst: CGFloat?
    var held: HeldTick?
    var action: () -> Void
    @Environment(\.notchMotion) private var level
    @State private var hovering = false

    private var fillScale: CGFloat {
        guard let held else { return isDone ? 1 : (hovering ? 0.42 : 0.001) }
        return CGFloat(held.isTicked ? 0.42 + 0.58 * held.fill : 0.001 + 0.419 * held.checkHover)
    }

    private var fillOpacity: Double {
        guard let held else { return isDone ? 1 : 0.4 }
        return held.isTicked ? 0.4 + 0.6 * min(held.fill, 1) : 0.4
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(color, lineWidth: 1.5)
                Circle().fill(color).scaleEffect(fillScale).opacity(fillOpacity)
                    // The fill springs only at Full; Subtle fills without a bounce.
                    .motion(level == .full ? Motion.bouncy : Motion.quick, value: isDone)
                    .motion(Motion.quick, value: hovering)
                CheckMarkShape()
                    .trim(from: 0, to: held.map { CGFloat($0.trim) } ?? (isDone ? 1 : 0))
                    .stroke(Color.black, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                    .motion(.easeOut(duration: 0.22).delay(isDone ? 0.08 : 0), value: isDone)
                CompletionBurst(color: color, trigger: burst, frozenAt: held.map { $0.burst ?? 1 } ?? heldBurst)
            }
            .frame(width: 15, height: 15)
            .padding(5)
            .contentShape(Circle())
            .padding(-5)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(isDone ? "Reopen" : "Complete")
    }
}

struct NotchTaskRow: View {
    @ObservedObject var model: AppModel
    let task: PerchTask
    var isDone = false
    let tint: NotchTint
    var heldBurst: CGFloat?
    var heldTick: HeldTick?
    /// Nil while the focus timer is hidden: the row then has no play button.
    var startFocus: (() -> Void)?
    var open: () -> Void
    /// Called after a tick, in case the task needs its next date picked in the main window.
    var needsMainWindow: () -> Void = {}
    @Environment(\.notchMotion) private var level
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var burst = 0

    private var isCompleting: Bool { model.completing.contains(task.id) || heldBurst != nil || heldTick?.isTicked == true }

    var body: some View {
        let ticked = isDone || isCompleting
        HStack(spacing: 8) {
            NotchCheck(color: Ink.priority(task.priority), isDone: ticked, burst: burst, heldBurst: heldBurst, held: heldTick, action: toggle)
            StrikeSweepText(text: task.title, isDone: ticked, font: .system(size: 12), color: Ink.text, doneColor: Ink.dim, lineLimit: 1,
                            heldSweep: heldTick.map { $0.isTicked ? $0.sweep : 0 })
            Spacer(minLength: 4)
            if hovering, !ticked, let startFocus {
                Button(action: startFocus) {
                    Image(systemName: "play.fill").font(.system(size: 8)).foregroundStyle(Color.black)
                        .frame(width: 18, height: 18).background(Circle().fill(tint.ink))
                }
                .buttonStyle(PerchPressStyle())
                .notchHover(scale: 1.15)
                .help("Focus on this")
                .accessibilityLabel("Start a focus session on \(task.title)")
                .transition(.perchPop(reduceMotion: reduceMotion || level != .full))
            } else {
                trailing
            }
        }
        .padding(.horizontal, 4)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(heldTick.map { Color.white.opacity(0.09 * $0.rowHover) } ?? (hovering ? Color.white.opacity(0.09) : .clear)))
        .contentShape(Rectangle())
        .onHover { value in
            withNotchMotion(.content, level: level, reduceMotion: reduceMotion) { hovering = value }
        }
        .onTapGesture(perform: open)
        .draggable(task.id) { NotchDragPreview(task: task) }
        .help(task.title)
    }

    @ViewBuilder private var trailing: some View {
        HStack(spacing: 5) {
            if let owner = task.owner, owner != model.author {
                Circle().fill(Ink.agent(owner)).frame(width: 6, height: 6).help("@\(owner)")
            }
            if isDone {
                EmptyView()
            } else if task.isOverdue(today: model.today), let due = task.due {
                Text(DayMath.date(from: due)?.formatted(.dateTime.month(.abbreviated).day()) ?? due)
                    .font(.system(size: 10.5)).foregroundStyle(Ink.danger.opacity(0.9))
            } else if let time = task.time {
                Text(time).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(Ink.dim)
            }
        }
    }

    /// Ticks through the app's completion queue: the row shows its check for a moment, a second click
    /// takes it back, and a tick still waiting when Perch quits is written, not lost.
    private func toggle() {
        if isDone {
            model.reopen(task)
        } else if model.completing.contains(task.id) {
            model.cancelCompleting(task.id)
        } else {
            if level == .full { burst += 1 }
            model.beginCompleting(task, after: level == .off ? 0.18 : Motion.completionDelay(reduceMotion: reduceMotion))
            // A repeating task with no rule for its next date isn't ticked: Perch asks for the date, in the main window.
            needsMainWindow()
        }
    }
}

struct NotchQuickAdd: View {
    @ObservedObject var services: NotchServices
    let tint: NotchTint
    var defaultDue: String
    @Binding var shouldFocus: Bool
    var added: (PerchTask) -> Void
    @ObservedObject private var dictation: DictationController
    @Environment(\.notchMotion) private var level
    @State private var text = ""
    @State private var confirmed = false
    @FocusState private var focused: Bool

    init(services: NotchServices, tint: NotchTint, defaultDue: String, shouldFocus: Binding<Bool>, added: @escaping (PerchTask) -> Void) {
        self.services = services
        self.tint = tint
        self.defaultDue = defaultDue
        _shouldFocus = shouldFocus
        self.added = added
        dictation = services.dictation
    }

    private var parsed: QuickAdd { QuickAdd.parse(text, areas: services.model.areas) }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: confirmed ? "checkmark.circle.fill" : "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(confirmed ? Ink.success : Ink.dim)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 14)
            TextField("New task", text: $text, prompt: Text("New task").foregroundStyle(Ink.faint))
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($focused)
                .onSubmit(add)
            if !text.isEmpty, let hint = hint {
                Text(hint).font(.system(size: 10.5)).foregroundStyle(tint.ink).lineLimit(1).transition(.opacity)
            }
            Button {
                dictation.toggle { spoken in text = text.isEmpty ? spoken : text + " " + spoken }
            } label: {
                Image(systemName: dictation.isListening ? "waveform" : "mic")
                    .font(.system(size: 11))
                    .foregroundStyle(dictation.isListening ? tint.ink : Ink.faint)
                    .symbolEffect(.variableColor.iterative, isActive: dictation.isListening && level != .off)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .notchHover(scale: 1.15)
            .help(dictation.errorMessage ?? "Dictate on this Mac")
            .accessibilityLabel(dictation.isListening ? "Stop dictating" : "Dictate a task")
        }
        .padding(.horizontal, 9).frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.well))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(focused ? tint.ink.opacity(0.55) : .clear, lineWidth: 1))
        .motion(Motion.quick, value: focused)
        .motion(Motion.quick, value: confirmed)
        .onChange(of: shouldFocus) { _, wanted in
            if wanted { focused = true; shouldFocus = false }
        }
        .onAppear { if shouldFocus { focused = true; shouldFocus = false } }
    }

    private var hint: String? {
        var parts: [String] = []
        if let due = parsed.due { parts.append(friendly(due) + (parsed.time.map { " \($0)" } ?? "")) }
        if let area = parsed.area { parts.append(area) }
        if let priority = parsed.priority { parts.append("P\(priority)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func friendly(_ date: String) -> String {
        if date == services.model.today { return "Today" }
        if date == DayMath.adding(days: 1, to: services.model.today) { return "Tomorrow" }
        return DayMath.date(from: date)?.formatted(.dateTime.weekday(.abbreviated).day()) ?? date
    }

    private func add() {
        guard let task = services.model.quickAdd(text, defaultDue: defaultDue) else { return }
        text = ""
        confirmed = true
        added(task)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            confirmed = false
        }
    }
}

// MARK: - Focus

struct FocusCard: View {
    @ObservedObject var focus: FocusController
    @ObservedObject var model: AppModel
    let tint: NotchTint
    @AppStorage("notchFocusMinutes") private var minutes = 25
    @Environment(\.notchMotion) private var level
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var subject: PerchTask? { focus.isRunning ? model.task(id: focus.taskID) : model.todayTasks.first }

    private var display: String {
        if focus.isRunning { return focus.display }
        return minutes > 0 ? "\(minutes):00" : "0:00"
    }

    var body: some View {
        VStack(spacing: 6) {
            CardHeader(title: "Focus", tint: tint) {
                if focus.isRunning {
                    Text(focus.isPaused ? "Paused" : "Running").font(.system(size: 10.5, weight: .medium)).foregroundStyle(tint.ink)
                        .transition(.opacity)
                }
            }
            FocusDial(progress: focus.isRunning ? focus.progress : 0, display: display, isPaused: focus.isPaused, tint: tint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(subject.map { "On: \($0.title)" } ?? "No task: just time")
                .font(.system(size: 10.5)).foregroundStyle(Ink.dim).lineLimit(1)
                .frame(maxWidth: .infinity)
            if focus.isRunning {
                HStack(spacing: 5) {
                    WideButton(title: focus.isPaused ? "Resume" : "Pause", symbol: focus.isPaused ? "play.fill" : "pause.fill", tint: tint, prominent: true) {
                        focus.isPaused ? focus.resume() : focus.pause()
                    }
                    if focus.total != nil { IconButton(symbol: "plus", size: 28, tint: Ink.text, help: "Add 5 minutes") { focus.addFiveMinutes() } }
                    IconButton(symbol: "checkmark", size: 28, tint: Ink.text, help: "Finish and log this session") { focus.stop() }
                }
                .transition(.perchSwap(reduceMotion: reduceMotion || level != .full))
            } else {
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        ForEach([15, 25, 45, 0], id: \.self) { value in
                            PresetChip(title: value > 0 ? "\(value)" : "∞", isSelected: minutes == value, tint: tint) {
                                withNotchMotion(.arrange, level: level, reduceMotion: reduceMotion) { minutes = value }
                            }
                        }
                    }
                    WideButton(title: "Start", symbol: "play.fill", tint: tint, prominent: true) {
                        if minutes > 0 { focus.startCountdown(minutes: minutes, task: subject?.id) } else { focus.startStopwatch(task: subject?.id) }
                    }
                }
                .transition(.perchSwap(reduceMotion: reduceMotion || level != .full))
            }
        }
        .animation(Motion.notch(.arrange, level: level, reduceMotion: reduceMotion), value: focus.isRunning)
    }
}

/// Perch's timer face: an open arc that fills as the session runs, around large rounded numerals
/// whose digits roll as they change.
struct FocusDial: View {
    var progress: Double
    var display: String
    var isPaused: Bool
    var tint: NotchTint

    /// The arc leaves a gap at the bottom, like a dial.
    private let sweep = 0.76

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height * 1.12)
            ZStack {
                Circle()
                    .trim(from: 0, to: sweep)
                    .stroke(Color.black.opacity(0.28), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(90 + (1 - sweep) * 180))
                Circle()
                    .trim(from: 0, to: max(sweep * min(progress, 1), 0.0001))
                    .stroke(
                        LinearGradient(colors: [tint.ink.opacity(0.75), tint.ink], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90 + (1 - sweep) * 180))
                    .opacity(progress > 0 ? 1 : 0)
                    .motion(Motion.smooth, value: progress)
                Text(display)
                    .font(.system(size: side * 0.27, weight: .semibold, design: .rounded).monospacedDigit())
                    .kerning(-0.5)
                    .foregroundStyle(LinearGradient(colors: [.white, tint.ink], startPoint: .top, endPoint: .bottom))
                    .contentTransition(.numericText(countsDown: true))
                    .motion(Motion.smooth, value: display)
                    .opacity(isPaused ? 0.55 : 1)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
            }
            .frame(width: side - 8, height: side - 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(y: side * 0.05)
        }
    }
}

private struct PresetChip: View {
    let title: String
    let isSelected: Bool
    let tint: NotchTint
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(isSelected ? tint.ink : Ink.dim)
                .frame(maxWidth: .infinity).frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.well))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(isSelected ? tint.ink.opacity(0.7) : .clear, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(PerchPressStyle())
        .notchHover(scale: 1.06)
        .help(title == "∞" ? "No end: count up" : "\(title) minutes")
    }
}

private struct WideButton: View {
    let title: String
    var symbol: String?
    let tint: NotchTint
    var prominent = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 9)) }
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(prominent ? Color.black : Ink.text)
            .frame(maxWidth: .infinity).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(prominent ? tint.ink : tint.well))
            .contentShape(Rectangle())
        }
        .buttonStyle(PerchPressStyle())
        .notchHover(scale: 1.03)
    }
}

// MARK: - Notepad

struct NotepadCard: View {
    @ObservedObject var store: NotepadStore
    @ObservedObject var model: AppModel
    let tint: NotchTint

    private var words: Int { store.text.split { $0.isWhitespace || $0.isNewline }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CardHeader(title: "Notepad", tint: tint) {
                Text(Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.system(size: 10.5)).foregroundStyle(Ink.dim)
            }
            NotepadEditor(text: $store.text) { store.makeTask(fromLineAt: $0) }
                .overlay(alignment: .topLeading) {
                    if store.text.isEmpty {
                        Text("Today's notes").font(.system(size: 12.5)).foregroundStyle(Ink.faint).padding(.leading, 9).padding(.top, 6).allowsHitTesting(false)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.well))
            HStack(spacing: 4) {
                Text("\(words) \(words == 1 ? "word" : "words")")
                    .contentTransition(.numericText())
                    .motion(Motion.smooth, value: words)
                Spacer(minLength: 2)
                Text("⌘↩ makes a task").lineLimit(1)
            }
            .font(.system(size: 10)).foregroundStyle(Ink.dim)
        }
    }
}

// MARK: - Agents

/// Who is working in the notebook right now, and what they think is finished.
struct AgentsCard: View {
    @ObservedObject var model: AppModel
    let tint: NotchTint
    var needsMainWindow: () -> Void = {}
    /// Opens Ready to tick in the main window, for the proposals the card has no room for.
    var openReady: () -> Void = {}
    @Environment(\.notchMotion) private var level
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let active = model.agents.filter(\.isActive)
        let ready = model.readyToTick
        VStack(alignment: .leading, spacing: 6) {
            CardHeader(title: "Agents", tint: tint) {
                if !active.isEmpty {
                    Text("\(active.count) here").font(.system(size: 10.5, weight: .medium)).foregroundStyle(tint.ink)
                }
            }
            if active.isEmpty, ready.isEmpty, !model.agentHistory.isEmpty {
                // Nobody is here: what each agent did last.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recently").font(.system(size: 10, weight: .semibold)).foregroundStyle(Ink.faint)
                    ForEach(model.agentHistory) { deed in
                        AgentDeedRow(deed: deed)
                            .transition(.perchRow(reduceMotion: reduceMotion || level != .full))
                    }
                    Spacer(minLength: 0)
                }
            } else if active.isEmpty, ready.isEmpty {
                VStack(spacing: 5) {
                    Image(systemName: "moon.zzz").font(.system(size: 18)).foregroundStyle(tint.ink)
                    Text("Nobody else is here").font(.system(size: 11.5)).foregroundStyle(Ink.dim)
                    Text("Agents show up when they open your notebook.").font(.system(size: 10)).foregroundStyle(Ink.faint).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(active.prefix(ready.isEmpty ? 5 : 2)) { agent in
                        AgentRow(agent: agent)
                            .transition(.perchRow(reduceMotion: reduceMotion || level != .full))
                    }
                    if active.isEmpty {
                        Text("Nobody is here right now").font(.system(size: 10.5)).foregroundStyle(Ink.dim)
                    }
                }
                if !ready.isEmpty {
                    // One at a time: a proposal needs its reason and both answers to be read properly.
                    let shown = 1
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 9.5)).foregroundStyle(Ink.success)
                            Text("Ready to tick").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Ink.dim)
                            Spacer(minLength: 0)
                            if ready.count > shown {
                                Button(action: openReady) {
                                    Text("+\(ready.count - shown) more").font(.system(size: 10, weight: .semibold)).foregroundStyle(tint.ink)
                                }
                                .buttonStyle(.plain)
                                .help("Open Ready to tick in Perch")
                            }
                        }
                        // What this is: agents can't close the user's tasks, so they ask here.
                        Text("Agents ask you before closing a task.")
                            .font(.system(size: 9.5)).foregroundStyle(Ink.faint).lineLimit(1)
                    }
                    .padding(.top, 2)
                    ForEach(ready.prefix(shown)) { task in
                        ProposalRow(model: model, task: task, tint: tint, needsMainWindow: needsMainWindow)
                            .transition(.perchRow(reduceMotion: reduceMotion || level != .full))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .animation(Motion.notch(.arrange, level: level, reduceMotion: reduceMotion), value: ready.map(\.id))
        .animation(Motion.notch(.arrange, level: level, reduceMotion: reduceMotion), value: active.map(\.id))
        .animation(Motion.notch(.arrange, level: level, reduceMotion: reduceMotion), value: model.agentHistory.map(\.id))
    }
}

/// One agent's last deed: its badge, its name, how long ago, and what it did.
private struct AgentDeedRow: View {
    let deed: AgentHistory.Deed

    var body: some View {
        HStack(spacing: 8) {
            AgentFace(name: deed.agent, size: 20)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Text(AgentHistory.displayName(for: deed.agent)).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Text(deed.date, format: .relative(presentation: .named)).font(.system(size: 9.5)).foregroundStyle(Ink.faint).lineLimit(1)
                }
                Text(deed.text).font(.system(size: 10)).foregroundStyle(Ink.dim).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .help("\(AgentHistory.displayName(for: deed.agent)): \(deed.text)")
    }
}

private struct AgentRow: View {
    let agent: AgentPresence

    var body: some View {
        // With a session to go back to, the whole row opens it.
        if let link = agent.link {
            Button { NSWorkspace.shared.open(link) } label: { row(opens: true).contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .help("\(SessionLink.title(for: link))\n\(agent.status)")
        } else {
            row(opens: false).help(agent.path.map { "\(agent.status)\n\($0)" } ?? agent.status)
        }
    }

    private func row(opens: Bool) -> some View {
        HStack(spacing: 8) {
            AgentFace(name: agent.name, size: 22)
                .overlay(alignment: .bottomTrailing) { PresenceDot(color: Ink.agent(agent.name)).offset(x: 1, y: 1) }
            VStack(alignment: .leading, spacing: 0) {
                Text(AgentHistory.displayName(for: agent.name)).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                Text(detail).font(.system(size: 10)).foregroundStyle(Ink.dim).lineLimit(1)
            }
            Spacer(minLength: 0)
            if opens { OpenSessionGlyph() }
        }
    }

    /// The file they are in, when they are in one; otherwise what they say they're doing.
    private var detail: String {
        if let path = agent.path, !path.isEmpty {
            let name = (path as NSString).lastPathComponent
            return name.hasSuffix(".md") ? String(name.dropLast(3)) : name
        }
        return agent.status
    }
}

/// A green dot with one ring spreading from it, over and over, to say "here now".
/// It only repeats while it is on screen, at Full motion, with Reduce Motion off.
private struct PresenceDot: View {
    var color: Color
    @Environment(\.notchMotion) private var level
    @Environment(\.notchReveal) private var reveal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spread = false

    var body: some View {
        ZStack {
            Circle().stroke(Ink.success, lineWidth: 1.5).scaleEffect(spread ? 2.4 : 1).opacity(spread ? 0 : 0.6)
            Circle().fill(Ink.success)
            Circle().strokeBorder(Color.black.opacity(0.55), lineWidth: 1)
        }
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
        .onAppear { update(repeats) }
        .onChange(of: repeats) { _, value in update(value) }
    }

    private var repeats: Bool { level == .full && !reduceMotion && reveal == nil }

    /// Starts the repeating ring, or stops it the moment the setting or Reduce Motion changes.
    private func update(_ on: Bool) {
        if on {
            withAnimation(Motion.notchPresence) { spread = true }
        } else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { spread = false }
        }
    }
}

/// One agent's proposal: who asks and when (a link back to their session when there is one), what they
/// think, the task, why, and the two answers. Nothing changes until one is pressed.
private struct ProposalRow: View {
    @ObservedObject var model: AppModel
    let task: PerchTask
    let tint: NotchTint
    var needsMainWindow: () -> Void = {}

    var body: some View {
        let proposal = Proposal(task)
        VStack(alignment: .leading, spacing: 4) {
            byline(proposal)
            Text(task.title).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
            (Text(proposal.kind == .noLongerNeeded ? "No longer needed" : "Done").foregroundStyle(Ink.success)
                + Text(proposal.reason.map { ". \($0)" } ?? "").foregroundStyle(Ink.dim))
                .font(.system(size: 10)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 5) {
                SmallButton(title: proposal.declineTitle, tint: tint) { model.rejectProposal(task) }
                SmallButton(title: proposal.acceptTitle, tint: tint, prominent: true) {
                    model.acceptProposal(task)
                    needsMainWindow()
                }
            }
            .padding(.top, 1)
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.well))
        .help(help(proposal))
    }

    /// The agent's face and name, and how long ago. It opens the agent's session when Perch knows it.
    @ViewBuilder private func byline(_ proposal: Proposal) -> some View {
        let label = HStack(spacing: 5) {
            AgentFace(name: task.proposedDoneBy ?? proposal.agent, size: 15)
            Text(proposal.agent).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Ink.text).lineLimit(1)
            if let date = proposal.date {
                Text(date, format: .relative(presentation: .named)).font(.system(size: 9.5)).foregroundStyle(Ink.faint).lineLimit(1)
            }
            Spacer(minLength: 0)
            if proposal.link != nil { OpenSessionGlyph() }
        }
        if let link = proposal.link {
            Button { NSWorkspace.shared.open(link) } label: { label.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .help(proposal.linkTitle ?? "")
        } else {
            label
        }
    }

    private func help(_ proposal: Proposal) -> String {
        var lines = [proposal.sentence + ".", task.title]
        if let reason = proposal.reason { lines.append(reason) }
        if let during = proposal.during { lines.append("While: \(during)") }
        return lines.joined(separator: "\n")
    }
}

/// A small arrow: this opens the agent's session in its own app.
private struct OpenSessionGlyph: View {
    var body: some View {
        Image(systemName: "arrow.up.right").font(.system(size: 8.5, weight: .bold)).foregroundStyle(Ink.faint)
            .accessibilityLabel("Opens the session")
    }
}

private struct SmallButton: View {
    let title: String
    let tint: NotchTint
    var prominent = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
                .foregroundStyle(prominent ? Color.black : Ink.text)
                .frame(maxWidth: .infinity).frame(height: 21)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(prominent ? tint.ink : Color.white.opacity(0.1)))
                .contentShape(Rectangle())
        }
        .buttonStyle(PerchPressStyle())
        .notchHover(scale: 1.04)
    }
}
