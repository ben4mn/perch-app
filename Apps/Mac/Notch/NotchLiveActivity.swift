import AppKit
import Combine
import PerchKit
import PerchUI
import SwiftUI

/// What the closed notch is asking about right now. Reminders, a finished timer and agents'
/// proposals all come here; one shows at a time, and nothing here ever takes the keyboard.
@MainActor
final class NotchLiveCenter: ObservableObject {
    @Published private(set) var queue = NotchPromptQueue()
    /// Goes up each time something worth a small celebration happens (a timer finishing).
    @Published private(set) var celebrations = 0

    private let model: AppModel
    private let focus: FocusController
    private var proposals = ProposalTracker()
    private var timeout: Task<Void, Never>?
    private var wake: Task<Void, Never>?
    private var isHeld = false
    private var cancellables: Set<AnyCancellable> = []
    /// False in a preview run: no sounds, no clocks.
    private let isLive: Bool
    /// Called when "done" couldn't finish here because the task repeats and needs its next date picked:
    /// that sheet lives in the main window, so the window has to come forward.
    var onNeedsMainWindow: () -> Void = {}

    init(model: AppModel, focus: FocusController, isLive: Bool = true) {
        self.model = model
        self.focus = focus
        self.isLive = isLive
        guard isLive else { return }
        model.$tasks
            .receive(on: RunLoop.main)
            .sink { [weak self] tasks in self?.tasksChanged(tasks) }
            .store(in: &cancellables)
        // Another notebook: what it already proposes is not news, and the old one's prompts don't apply.
        model.$vault
            .map { $0?.root }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.proposals = ProposalTracker()
                self.queue = NotchPromptQueue()
                self.schedule()
            }
            .store(in: &cancellables)
    }

    var current: NotchPrompt? { queue.current }

    /// Shows a prompt, or queues it behind the one showing.
    func post(_ prompt: NotchPrompt, sound: String? = nil) {
        let hadCurrent = queue.current != nil
        guard queue.enqueue(prompt) else { return }
        if case .focusFinished = prompt.kind { celebrations += 1 }
        if isLive, let sound { NSSound(named: sound)?.play() }
        if !hadCurrent { schedule() }
    }

    /// The left, quieter button: snooze, add five minutes, or decide later.
    func secondary() {
        guard let prompt = queue.current else { return }
        switch prompt.kind {
        case .reminder:
            queue.snoozeCurrent(now: Date())
        case let .focusFinished(taskID):
            focus.clearFinished()
            if FocusAvailability.isAvailable() { focus.startCountdown(minutes: 5, task: taskID) }
            queue.finishCurrent()
        case .proposal, .event:
            queue.finishCurrent()
        }
        schedule()
    }

    /// The right, filled button: done.
    func primary() {
        guard let prompt = queue.current else { return }
        switch prompt.kind {
        case let .reminder(taskID):
            if let task = model.task(id: taskID) { model.complete(task) }
        case let .proposal(taskID, _):
            if let task = model.task(id: taskID), task.isReadyToTick { model.acceptProposal(task) }
        case .focusFinished:
            focus.clearFinished()
        case .event:
            break
        }
        // Completing the task may already have cleared this prompt through `tasksChanged`.
        if queue.current?.id == prompt.id { queue.finishCurrent() }
        schedule()
        // A repeating task with no rule for its next date isn't completed yet: Perch asks for the date.
        if let id = prompt.taskID, model.needsNextDate?.id == id { onNeedsMainWindow() }
    }

    /// Forgets everything showing, waiting and snoozed: the notch was turned off.
    func clear() {
        guard !queue.isEmpty else { return }
        queue = NotchPromptQueue()
        schedule()
    }

    /// Drops a finished timer's prompts: the focus timer was hidden in Settings.
    func dropFocusPrompts() {
        let before = queue
        queue.prune { if case .focusFinished = $0.kind { return true } else { return false } }
        if queue != before { schedule() }
    }

    func dismiss() {
        if case .focusFinished = queue.current?.kind { focus.clearFinished() }
        queue.finishCurrent()
        schedule()
    }

    /// While the pointer rests on a prompt it stays up.
    func hold(_ held: Bool) {
        guard held != isHeld else { return }
        isHeld = held
        schedule()
    }

    private func tasksChanged(_ tasks: [PerchTask]) {
        let before = queue
        queue.prune { prompt in
            switch prompt.kind {
            // A reminder goes when its task is done or deleted, and also when the task was moved to
            // another day or time while the reminder waited: it would be asking about a time that has changed.
            case let .reminder(id): return !TaskReminders.stillApplies(key: prompt.id, to: tasks.first { $0.id == id }, now: Date())
            case let .proposal(id, _): return tasks.first { $0.id == id }?.isReadyToTick != true
            case .event, .focusFinished: return false
            }
        }
        // Until the notebook has loaded there is nothing to compare against: its first tasks only set the baseline.
        for task in tasks.isEmpty ? [] : proposals.newProposals(in: tasks) {
            let agent = task.proposedDoneBy ?? "An agent"
            let proposal = Proposal(task)
            let reason = proposal.reason.map { ": \($0)" } ?? ""
            queue.enqueue(NotchPrompt(id: "proposal|\(task.id)|\(agent)", kind: .proposal(taskID: task.id, agent: agent), title: task.title, detail: "\(proposal.sentence)\(reason)"))
        }
        if queue != before { schedule() }
    }

    /// One sleeping task for the prompt showing and one for the next snooze. No repeating timers.
    private func schedule() {
        timeout?.cancel()
        timeout = nil
        wake?.cancel()
        wake = nil
        guard isLive else { return }
        if let prompt = queue.current, !isHeld {
            timeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(prompt.lifetime * 1_000_000_000))
                guard !Task.isCancelled, let self, self.queue.current?.id == prompt.id else { return }
                if case .focusFinished = prompt.kind { self.focus.clearFinished() }
                self.queue.timeOutCurrent(now: Date())
                self.schedule()
            }
        }
        if let next = queue.nextWake {
            wake = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(next.timeIntervalSinceNow, 0.1) * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                let hadCurrent = self.queue.current != nil
                self.queue.wake(now: Date())
                if !hadCurrent, self.queue.current != nil { NSSound(named: "Tink")?.play() }
                self.schedule()
            }
        }
    }

    #if DEBUG
    /// Shows a prompt for a snapshot, with no sound and no clock.
    func debugShow(_ prompt: NotchPrompt?) {
        queue = NotchPromptQueue()
        if let prompt { queue.enqueue(prompt) }
    }
    #endif
}

// MARK: - The closed notch at rest

/// Today's counts beside the notch: progress on the left, what needs you on the right.
struct AmbientStrip: View {
    @ObservedObject var model: AppModel
    var notchWidth: CGFloat
    /// How far the pointer's swell has come: 0 at rest, 1 under the pointer. The counts brighten with it.
    var peek: Double
    var isOnScreen: Bool
    @AppStorage("notchBreathe") private var breathes = true
    @Environment(\.notchMotion) private var level
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breath = false

    private var dueToday: [PerchTask] { model.tasks.filter { $0.isOpen && $0.due == model.today } }
    private var doneToday: Int { model.tasks.filter { $0.completed == model.today }.count }
    private var overdue: Int { model.tasks.filter { $0.isOverdue(today: model.today) }.count }
    private var nextTime: String? { NotchDay.nextTime(model.tasks, today: model.today, now: Date()) }

    /// A slow glow, only while something is overdue, the strip is really on screen, and motion is welcome.
    private var shouldBreathe: Bool { overdue > 0 && breathes && isOnScreen && level == .full && !reduceMotion }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                ProgressRing(progress: NotchDay.progress(open: dueToday.count, done: doneToday), lineWidth: 2.2, tint: Ink.accent)
                    .frame(width: 12, height: 12)
                Text("\(dueToday.count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
                    .motion(Motion.smooth, value: dueToday.count)
            }
            .frame(width: NotchState.ear)
            .help("\(dueToday.count) due today, \(doneToday) done")
            Spacer(minLength: notchWidth)
            HStack(spacing: 4) {
                if let agent = model.agents.first(where: \.isActive) {
                    HStack(spacing: 3) {
                        Circle().fill(Ink.agent(agent.name)).frame(width: 7, height: 7)
                        if model.agents.filter(\.isActive).count > 1 {
                            Text("\(model.agents.filter(\.isActive).count)").font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                    }
                    .help("\(agent.name): \(agent.status)")
                } else if let nextTime {
                    Text(nextTime).font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                }
                if overdue > 0 {
                    // Overdue is a number when there's nothing else to say, and a quiet dot when there is.
                    if nextTime == nil, !model.agents.contains(where: \.isActive) {
                        Text("\(overdue)")
                            .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Ink.danger)
                            .contentTransition(.numericText(countsDown: true))
                            .opacity(breath ? 1 : 0.7)
                    } else {
                        Circle().fill(Ink.danger).frame(width: 5, height: 5).opacity(breath ? 1 : 0.45)
                    }
                }
            }
            .help(overdue > 0 ? "\(overdue) overdue" : "")
            .frame(width: NotchState.ear)
        }
        .foregroundStyle(Ink.text)
        .opacity(0.78 + 0.22 * min(max(peek, 0), 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(dueToday.count) due today, \(doneToday) done" + (overdue > 0 ? ", \(overdue) overdue" : ""))
        .onAppear { updateBreath(shouldBreathe) }
        .onChange(of: shouldBreathe) { _, value in updateBreath(value) }
    }

    private func updateBreath(_ on: Bool) {
        if on {
            withAnimation(Motion.notchBreath) { breath = true }
        } else {
            withAnimation(Motion.reduced) { breath = false }
        }
    }
}

/// The closed notch while a timer runs: an arc filling on one side, the time on the other. When
/// menus leave no room beside the notch, both sit in a small tab below it instead.
struct FocusLiveStrip: View {
    @ObservedObject var focus: FocusController
    var notchWidth: CGFloat
    var neckHeight: CGFloat
    /// Where the timer sits: either side of the notch, in a tab under it when menus leave no room,
    /// or together in a small pill on a screen with no notch.
    enum Place { case beside, below, pill }
    var place: Place

    private var time: some View {
        Text(focus.isPaused ? "Paused" : focus.display)
            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
            .contentTransition(.numericText(countsDown: true))
            .motion(Motion.smooth, value: focus.display)
            .foregroundStyle(focus.isPaused ? Ink.dim : Ink.text)
    }

    private var arc: some View {
        ProgressRing(progress: focus.progress, lineWidth: 2.4, tint: NotchTint.card(.focus).ink)
            .frame(width: 14, height: 14)
    }

    var body: some View {
        switch place {
        case .beside:
            HStack(spacing: 0) {
                arc.frame(width: NotchState.liveEar)
                Spacer(minLength: notchWidth)
                time.frame(width: NotchState.liveEar)
            }
        case .below:
            VStack(spacing: 0) {
                Spacer(minLength: neckHeight)
                HStack(spacing: 7) { arc; time }
                    .frame(height: NotchState.liveTab)
            }
        case .pill:
            HStack(spacing: 7) { arc; time }
        }
    }
}

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat
    var tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(progress > 0 ? 1 : 0)
                .motion(Motion.smooth, value: progress)
        }
    }
}

// MARK: - Prompts

/// A prompt's contents: who or what it is about, the title, and two answers. Used in the tab that
/// hangs from the closed notch and, when the panel is open, as a bar across its foot.
struct PromptContent: View {
    let prompt: NotchPrompt
    @ObservedObject var live: NotchLiveCenter
    @ObservedObject var model: AppModel
    @Environment(\.notchMotion) private var level
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nudged = false

    private var labels: (secondary: String?, primary: String) {
        switch prompt.kind {
        case .reminder: ("5 min", "Done")
        case .event: (nil, "OK")
        case .focusFinished: ("5 min", "Done")
        case .proposal: ("Later", "Mark done")
        }
    }

    private var tint: Color {
        switch prompt.kind {
        case let .reminder(id): Ink.priority(model.task(id: id)?.priority ?? 4)
        case .event: Ink.accent
        case .focusFinished: NotchTint.card(.focus).ink
        case let .proposal(_, agent): Ink.agent(agent)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            mark
                .frame(width: 30, height: 30)
                .pulseOnce(isCelebration && level == .full, color: tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(prompt.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Ink.text).lineLimit(1)
                Text(prompt.detail).font(.system(size: 10.5)).foregroundStyle(Ink.dim).lineLimit(1)
            }
            Spacer(minLength: 6)
            if let secondary = labels.secondary {
                PillButton(secondary, symbol: secondarySymbol) { live.secondary() }
                    .accessibilityLabel(secondaryLabel)
            }
            PillButton(labels.primary, symbol: "checkmark", prominent: true, tint: tint) { live.primary() }
        }
        .padding(.horizontal, 14)
        .onAppear {
            // One small sign of life while it waits: the mark nods once.
            guard level == .full, !reduceMotion else { return }
            if let nod = Motion.notch(.nod, level: level, reduceMotion: reduceMotion) {
                withAnimation(nod.delay(1.4)) { nudged = true }
            }
        }
    }

    private var isCelebration: Bool {
        if case .focusFinished = prompt.kind { return true }
        return false
    }

    /// What the quieter button does, in words, for VoiceOver.
    private var secondaryLabel: String {
        switch prompt.kind {
        case .reminder: "Remind me in 5 minutes"
        case .focusFinished: "Add 5 minutes"
        default: labels.secondary ?? ""
        }
    }

    private var secondarySymbol: String? {
        switch prompt.kind {
        case .reminder: "zzz"
        case .focusFinished: "plus"
        default: nil
        }
    }

    @ViewBuilder private var mark: some View {
        switch prompt.kind {
        case .reminder:
            ZStack {
                Circle().strokeBorder(tint, lineWidth: 2)
                Image(systemName: "bell.fill").font(.system(size: 12)).foregroundStyle(tint)
                    .rotationEffect(.degrees(nudged ? 0 : -14), anchor: .top)
            }
        case .event:
            ZStack {
                Circle().fill(tint.opacity(0.2))
                Image(systemName: "calendar").font(.system(size: 13, weight: .medium)).foregroundStyle(tint)
            }
        case .focusFinished:
            ZStack {
                Circle().fill(tint)
                CheckMarkShape().stroke(Color.black, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                    .scaleEffect(nudged ? 1 : 0.86)
            }
        case let .proposal(_, agent):
            AgentFace(name: agent, size: 30)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 12)).foregroundStyle(Ink.success)
                        .background(Circle().fill(.black).padding(1))
                        .offset(x: 3, y: 3)
                        .scaleEffect(nudged ? 1 : 0.8)
                }
        }
    }
}

/// An agent's badge: the mark the build gives that agent (a spark for Claude, a dot, or a house for a home
/// assistant; see `PerchConfiguration.agentMarks`), otherwise its initial, on the agent's color.
struct AgentFace: View {
    var name: String
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Ink.agent(name))
            switch AgentHistory.mark(for: name) {
            case .dot:
                Circle().fill(Color.black.opacity(0.82)).frame(width: size * 0.38, height: size * 0.38)
            case .claude:
                Image(systemName: "asterisk").font(.system(size: size * 0.52, weight: .heavy)).foregroundStyle(.white)
            case .house:
                Image(systemName: "house.fill").font(.system(size: size * 0.44, weight: .semibold)).foregroundStyle(.black.opacity(0.85))
            case let .initial(letter):
                Text(letter).font(.system(size: size * 0.5, weight: .bold, design: .rounded)).foregroundStyle(.black)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(AgentHistory.displayName(for: name))
    }
}

struct PillButton: View {
    var title: String
    var symbol: String?
    var prominent = false
    var tint: Color?
    var action: () -> Void

    init(_ title: String, symbol: String? = nil, prominent: Bool = false, tint: Color? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.prominent = prominent
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 9.5, weight: .bold)) }
                Text(title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(prominent ? Color.black : Ink.text)
            .padding(.horizontal, 11).frame(height: 26)
            .background(Capsule().fill(prominent ? (tint ?? Ink.accent) : Color.white.opacity(0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(PerchPressStyle())
        .notchHover(scale: 1.05)
    }
}
