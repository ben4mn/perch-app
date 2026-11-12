import Foundation

// The parts of the Mac notch that are plain arithmetic and bookkeeping, kept here so they can be tested:
// the outline the notch draws at every moment, how the open panel and its cards are sized, the saved
// card order, which reminders are due, and the queue of prompts the closed notch shows one at a time.

// MARK: - Outline

/// The black shape the notch draws: a neck the size of the hardware notch (or wider), and below the
/// menu bar an optional wider body. Every state of the notch is one of these, so moving between
/// states is one shape changing its numbers, never one picture fading into another.
///
///        ╮  neck  ╭            y = 0, flared into the menu bar by `topRadius`
///     ╭──╯        ╰──╮         y = neckHeight, the shoulder (only when the body is wider)
///     ╰──────────────╯         y = height, rounded by `bottomRadius`
public struct NotchOutline: Equatable, Sendable {
    /// Width of the widest part.
    public var width: Double
    public var height: Double
    /// Width of the part inside the menu bar. Equal to `width` when there is no shoulder.
    public var neckWidth: Double
    /// Height of the menu bar band. The body may only be wider than the neck below this line.
    public var neckHeight: Double
    public var topRadius: Double
    public var bottomRadius: Double
    public var shoulderRadius: Double

    public init(width: Double, height: Double, neckWidth: Double? = nil, neckHeight: Double? = nil,
                topRadius: Double, bottomRadius: Double, shoulderRadius: Double = 10) {
        self.width = width
        self.height = height
        self.neckWidth = neckWidth ?? width
        self.neckHeight = neckHeight ?? height
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
        self.shoulderRadius = shoulderRadius
    }

    /// The outline part-way from `a` to `b`. `progress` may run a little outside 0...1 while a spring overshoots.
    public static func mix(_ a: NotchOutline, _ b: NotchOutline, _ progress: Double) -> NotchOutline {
        func lerp(_ x: Double, _ y: Double) -> Double { x + (y - x) * progress }
        return NotchOutline(
            width: lerp(a.width, b.width), height: lerp(a.height, b.height),
            neckWidth: lerp(a.neckWidth, b.neckWidth), neckHeight: lerp(a.neckHeight, b.neckHeight),
            topRadius: lerp(a.topRadius, b.topRadius), bottomRadius: lerp(a.bottomRadius, b.bottomRadius),
            shoulderRadius: lerp(a.shoulderRadius, b.shoulderRadius)
        )
    }

    /// The numbers a path can be drawn from without a kink: nothing negative, and no corner larger than
    /// the edge it rounds, whatever a spring's overshoot or a half-finished transition asks for.
    public var resolved: Resolved {
        // A number that isn't one (a broken animation value) counts as nothing, so the path stays drawable.
        func clean(_ value: Double) -> Double { value.isFinite ? max(value, 0) : 0 }
        let width = clean(self.width), height = clean(self.height)
        let neckWidth = min(clean(self.neckWidth), width)
        let neckHeight = min(clean(self.neckHeight), height)
        let topRadius = clean(self.topRadius), bottomRadius = clean(self.bottomRadius), shoulderRadius = clean(self.shoulderRadius)
        let overhang = (width - neckWidth) / 2
        let depth = height - neckHeight
        // A body no wider than its neck, or with no depth, has no shoulder: it is a plain notch.
        let hasShoulder = overhang > 0.01 && depth > 0.01
        let top = min(topRadius, (hasShoulder ? neckHeight : height) / 2, neckWidth / 2)
        var inner = 0.0, outer = 0.0, bottom = 0.0
        if hasShoulder {
            inner = min(shoulderRadius, overhang / 2, max(neckHeight - top, 0))
            outer = min(shoulderRadius, overhang / 2, depth / 2)
            bottom = min(bottomRadius, depth - outer, width / 2)
        } else {
            bottom = min(bottomRadius, height - top, neckWidth / 2)
        }
        return Resolved(
            width: hasShoulder ? width : neckWidth, height: height,
            neckWidth: neckWidth, neckHeight: hasShoulder ? neckHeight : height,
            top: top, shoulderInner: inner, shoulderOuter: outer, bottom: max(bottom, 0), hasShoulder: hasShoulder
        )
    }

    public struct Resolved: Equatable, Sendable {
        public var width: Double
        public var height: Double
        public var neckWidth: Double
        public var neckHeight: Double
        public var top: Double
        public var shoulderInner: Double
        public var shoulderOuter: Double
        public var bottom: Double
        public var hasShoulder: Bool

        /// The widest the shape gets, flares included.
        public var extent: Double { max(width, neckWidth + top * 2) }
    }
}

/// How far the open panel's content has come in, for a given progress of the opening.
/// The shape leads by a moment and content follows while it is still growing, in order, so the
/// opening reads as one quick movement, not a box followed by its contents.
public enum NotchReveal {
    /// Where content starts to appear, as a share of the opening.
    public static let threshold = 0.3
    /// How much later each following item starts.
    public static let step = 0.04
    /// How long one item takes to arrive.
    public static let span = 0.45

    /// 0 (hidden) to 1 (in place) for the item at `index`, when the opening is at `progress`.
    public static func amount(progress: Double, index: Int) -> Double {
        let start = min(threshold + Double(max(index, 0)) * step, 1 - span)
        let raw = (progress - start) / span
        let clamped = min(max(raw, 0), 1)
        // Ease out, so items settle instead of stopping dead.
        return 1 - (1 - clamped) * (1 - clamped)
    }
}

// MARK: - Panel and cards

public enum NotchCardKind: String, CaseIterable, Sendable, Identifiable {
    case today, focus, notepad, agents
    public var id: String { rawValue }

    /// Share of the row each card takes. Today lists tasks, so it gets more room.
    public var weight: Double { self == .today ? 1.45 : 1 }
    public var minimumWidth: Double { self == .today ? 200 : 150 }
}

public enum NotchCardOrder {
    public static let standard: [NotchCardKind] = [.today, .focus, .notepad, .agents]

    /// Reads a saved order. Unknown names are dropped, repeats ignored, and any card the saved
    /// order doesn't mention (a card added in a later version) goes on the end.
    public static func decode(_ stored: String?) -> [NotchCardKind] {
        var result: [NotchCardKind] = []
        for name in (stored ?? "").split(separator: ",") {
            guard let kind = NotchCardKind(rawValue: name.trimmingCharacters(in: .whitespaces)), !result.contains(kind) else { continue }
            result.append(kind)
        }
        for kind in standard where !result.contains(kind) { result.append(kind) }
        return result
    }

    public static func encode(_ order: [NotchCardKind]) -> String {
        order.map(\.rawValue).joined(separator: ",")
    }

    /// The cards to lay out: the saved order without Focus while the focus timer is hidden in Settings.
    public static func shown(_ order: [NotchCardKind], focusHidden: Bool) -> [NotchCardKind] {
        focusHidden ? order.filter { $0 != .focus } : order
    }

    /// The saved order after the cards on screen were put in the order `arranged`. Cards that aren't on
    /// screen (Focus while it is hidden, one that didn't fit) keep their places, so they come back
    /// where they were.
    public static func merging(_ arranged: [NotchCardKind], into saved: [NotchCardKind]) -> [NotchCardKind] {
        var next = arranged.filter(saved.contains).makeIterator()
        let moved = Set(arranged)
        return saved.map { moved.contains($0) ? (next.next() ?? $0) : $0 }
    }

    /// `order` with `kind` moved `offset` places (-1 is left, 1 is right), stopping at the ends.
    /// The way to reorder without dragging.
    public static func moved(_ order: [NotchCardKind], _ kind: NotchCardKind, by offset: Int) -> [NotchCardKind] {
        guard let index = order.firstIndex(of: kind) else { return order }
        var result = order
        result.remove(at: index)
        result.insert(kind, at: min(max(index + offset, 0), result.count))
        return result
    }
}

public enum NotchLayout {
    public struct Size: Equatable, Sendable {
        public var width: Double
        public var height: Double
    }

    public static let cardSpacing = 10.0
    public static let sidePadding = 14.0

    /// The open panel on a screen this wide: generous on a large display, never wider than a small one allows.
    public static func openSize(screenWidth: Double) -> Size {
        let ideal = screenWidth * 0.58
        let width = min(min(max(ideal, 760), 880), max(screenWidth - 48, 320))
        return Size(width: width.rounded(), height: 312)
    }

    /// How many cards fit side by side at their minimum widths. The rest are left off, last first.
    public static func visibleCards(_ order: [NotchCardKind], available: Double, spacing: Double = cardSpacing) -> [NotchCardKind] {
        var shown: [NotchCardKind] = []
        var used = 0.0
        for kind in order {
            let next = used + kind.minimumWidth + (shown.isEmpty ? 0 : spacing)
            if next > available, !shown.isEmpty { break }
            shown.append(kind)
            used = next
        }
        return shown
    }

    /// How many day columns the Week view shows beside its list: as many of the seven as stay readable.
    public static func weekDays(available: Double, listWidth: Double, minimumDay: Double = 90) -> Int {
        min(max(Int((available - listWidth) / minimumDay), 3), 7)
    }

    /// Each card's width when `order` shares `available` points.
    public static func widths(_ order: [NotchCardKind], available: Double, spacing: Double = cardSpacing) -> [NotchCardKind: Double] {
        guard !order.isEmpty else { return [:] }
        let room = max(available - spacing * Double(order.count - 1), 0)
        let total = order.map(\.weight).reduce(0, +)
        var result: [NotchCardKind: Double] = [:]
        for kind in order { result[kind] = (room * kind.weight / total).rounded(.down) }
        return result
    }

    /// Each card's left edge when laid out in `order`.
    public static func origins(_ order: [NotchCardKind], widths: [NotchCardKind: Double], spacing: Double = cardSpacing) -> [NotchCardKind: Double] {
        var result: [NotchCardKind: Double] = [:]
        var x = 0.0
        for kind in order {
            result[kind] = x
            x += (widths[kind] ?? 0) + spacing
        }
        return result
    }

    /// The order while `dragging` is held with its center at `centerX`: the card goes to whichever
    /// place puts its slot nearest the pointer. It depends only on where the card is now, so a card
    /// held still never flickers between two places.
    public static func reordered(_ order: [NotchCardKind], dragging: NotchCardKind, centerX: Double,
                                 widths: [NotchCardKind: Double], spacing: Double = cardSpacing) -> [NotchCardKind] {
        guard order.contains(dragging) else { return order }
        let others = order.filter { $0 != dragging }
        var best = order
        var bestDistance = Double.infinity
        for index in 0...others.count {
            var candidate = others
            candidate.insert(dragging, at: index)
            let origin = origins(candidate, widths: widths, spacing: spacing)[dragging] ?? 0
            let distance = abs(origin + (widths[dragging] ?? 0) / 2 - centerX)
            if distance < bestDistance - 0.001 {
                bestDistance = distance
                best = candidate
            }
        }
        return best
    }
}

/// How much the notch moves. Stored in settings as its raw value.
public enum NotchMotionLevel: String, CaseIterable, Sendable, Identifiable {
    /// Springs, staggered arrivals and small celebrations.
    case full
    /// The same movements without bounce, stagger or celebration.
    case subtle
    /// Every change is instant.
    case off

    public var id: String { rawValue }
    public init(stored: String?) { self = stored.flatMap(NotchMotionLevel.init(rawValue:)) ?? .full }

    public var title: String {
        switch self {
        case .full: "Full"
        case .subtle: "Subtle"
        case .off: "Off"
        }
    }
}

/// Four calm card colors taken from the theme's accent, so the notch belongs to the theme
/// without borrowing anyone else's palette.
public enum NotchTints {
    /// Hue of a color, 0..<360. Grays answer 0.
    public static func hue(of color: ThemeRGB) -> Double {
        let high = max(color.red, color.green, color.blue), low = min(color.red, color.green, color.blue)
        let delta = high - low
        guard delta > 0.0001 else { return 0 }
        var hue: Double
        if high == color.red {
            hue = (color.green - color.blue) / delta
        } else if high == color.green {
            hue = 2 + (color.blue - color.red) / delta
        } else {
            hue = 4 + (color.red - color.green) / delta
        }
        hue *= 60
        return hue < 0 ? hue + 360 : hue
    }

    /// The hue for a card: the accent itself for Today, and steps around the wheel for the others,
    /// far enough apart to tell the cards from each other at a glance.
    public static func hue(for card: NotchCardKind, accentHue: Double) -> Double {
        let turn: Double = switch card {
        case .today: 0
        case .focus: 232
        case .notepad: 38
        case .agents: 140
        }
        return (accentHue + turn).truncatingRemainder(dividingBy: 360)
    }
}

// MARK: - Reminders

public enum TaskReminders {
    public struct Moment: Equatable, Sendable {
        /// Names this one ringing of this task, so it rings once.
        public var key: String
        public var date: Date
    }

    public struct Ring: Equatable, Sendable {
        public var key: String
        public var taskID: String
        public var title: String
        public var detail: String
    }

    private static func formatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter
    }

    /// A wall-clock time such as `2026-11-09T16:30` in the calendar's time zone. A time the clocks skip
    /// (02:30 on the night they go forward) counts as the first real moment after it, so its reminder
    /// still rings; a time that happens twice (the night they go back) counts the first time.
    static func date(_ text: String, calendar: Calendar) -> Date? {
        if let date = formatter(calendar: calendar).date(from: text) { return date }
        let numbers = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard numbers.count >= 5 else { return nil }
        var parts = DateComponents()
        parts.year = numbers[0]; parts.month = numbers[1]; parts.day = numbers[2]
        parts.hour = numbers[3]; parts.minute = numbers[4]
        return calendar.date(from: parts)
    }

    /// When an open task should ring: at its due time when it has no `remind` entries, otherwise at
    /// each entry (`-15m` before the due time, or a full `2026-11-09T16:30`).
    public static func moments(for task: PerchTask, calendar: Calendar = .current) -> [Moment] {
        guard task.isOpen else { return [] }
        let due = task.due.flatMap { day in task.time.flatMap { date("\(day)T\($0)", calendar: calendar) } }
        var result: [Moment] = []
        if task.remind.isEmpty, let due, let day = task.due { result.append(.init(key: "\(task.id)|\(day)T\(task.time ?? "")", date: due)) }
        for entry in task.remind {
            if entry.hasPrefix("-"), entry.hasSuffix("m"), let minutes = Int(entry.dropFirst().dropLast()), let due, let day = task.due {
                result.append(.init(key: "\(task.id)|\(day)|\(entry)", date: due.addingTimeInterval(TimeInterval(-minutes * 60))))
            } else if let date = date(String(entry.prefix(16)), calendar: calendar) {
                result.append(.init(key: "\(task.id)|\(entry)", date: date))
            }
        }
        return result
    }

    /// What has come due by `now` and hasn't rung. Everything returned in `passed` should be remembered
    /// as rung; only `rings` should be shown, because a moment more than `window` seconds old is one
    /// Perch slept through, and those shouldn't all go off at once when it wakes.
    public static func due(tasks: [PerchTask], now: Date, fired: Set<String>, window: TimeInterval = 3600,
                           calendar: Calendar = .current) -> (rings: [Ring], passed: [String]) {
        var rings: [Ring] = []
        var passed: [String] = []
        for task in tasks {
            for moment in moments(for: task, calendar: calendar) where moment.date <= now && !fired.contains(moment.key) && !passed.contains(moment.key) {
                passed.append(moment.key)
                guard now.timeIntervalSince(moment.date) < window, !rings.contains(where: { $0.taskID == task.id }) else { continue }
                rings.append(.init(key: moment.key, taskID: task.id, title: task.title, detail: task.time.map { "Due at \($0)" } ?? "Reminder"))
            }
        }
        return (rings, passed)
    }

    /// Whether a reminder that rang as `key` still stands for `task`: the task is open and still has
    /// that moment, at or before `now`. Completing the task, deleting it (pass nil), moving its date or
    /// time, or changing its `remind` entries all make a waiting or snoozed reminder out of date.
    public static func stillApplies(key: String, to task: PerchTask?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let task else { return false }
        return moments(for: task, calendar: calendar).contains { $0.key == key && $0.date <= now }
    }

    /// The list of rung reminders to save: `adding` goes on the end, nothing is listed twice, and only
    /// the newest `limit` are kept, so the oldest are the ones forgotten.
    public static func remembered(_ existing: [String], adding keys: [String], limit: Int = 2000) -> [String] {
        var seen = Set<String>()
        let all = (existing + keys).filter { seen.insert($0).inserted }
        return Array(all.suffix(max(limit, 0)))
    }
}

// MARK: - Prompts in the closed notch

/// One thing the closed notch asks about: a reminder, a finished timer, an agent's proposal.
public struct NotchPrompt: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable {
        case reminder(taskID: String)
        case event
        case focusFinished(taskID: String?)
        case proposal(taskID: String, agent: String)
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var detail: String
    /// How many more times an unanswered reminder comes back on its own.
    public var repeatsLeft: Int

    public init(id: String, kind: Kind, title: String, detail: String, repeatsLeft: Int? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        if let repeatsLeft {
            self.repeatsLeft = repeatsLeft
        } else if case .reminder = kind {
            self.repeatsLeft = 2
        } else {
            self.repeatsLeft = 0
        }
    }

    /// Seconds it stays up when nobody answers.
    public var lifetime: TimeInterval {
        switch kind {
        case .reminder: 30
        case .event: 20
        case .focusFinished: 30
        case .proposal: 14
        }
    }

    /// The task this is about, if any.
    public var taskID: String? {
        switch kind {
        case let .reminder(id): id
        case let .proposal(id, _): id
        case let .focusFinished(id): id
        case .event: nil
        }
    }

    /// Things with a time attached go ahead of an agent's suggestion, which can wait.
    var rank: Int {
        if case .proposal = kind { return 1 }
        return 0
    }
}

/// The prompts waiting for the closed notch. One shows at a time; the rest wait their turn; snoozed
/// ones come back later. All of it lives in memory: snoozing never writes to a task's file.
public struct NotchPromptQueue: Equatable, Sendable {
    public struct Snoozed: Equatable, Sendable {
        public var prompt: NotchPrompt
        public var until: Date
    }

    public static let snoozeInterval: TimeInterval = 300

    public private(set) var current: NotchPrompt?
    public private(set) var waiting: [NotchPrompt] = []
    public private(set) var snoozed: [Snoozed] = []

    public init() {}

    public func contains(_ id: String) -> Bool {
        current?.id == id || waiting.contains { $0.id == id } || snoozed.contains { $0.prompt.id == id }
    }

    /// Adds a prompt. One already showing, waiting or snoozed isn't added twice. Returns whether it was added.
    @discardableResult
    public mutating func enqueue(_ prompt: NotchPrompt) -> Bool {
        guard !contains(prompt.id) else { return false }
        if current == nil {
            current = prompt
        } else {
            let index = waiting.firstIndex { $0.rank > prompt.rank } ?? waiting.count
            waiting.insert(prompt, at: index)
        }
        return true
    }

    /// The current prompt was answered or dismissed: the next one takes its place.
    public mutating func finishCurrent() {
        current = waiting.isEmpty ? nil : waiting.removeFirst()
    }

    /// Puts the current prompt away until `now` plus five minutes.
    public mutating func snoozeCurrent(now: Date, interval: TimeInterval = snoozeInterval) {
        if let current { snoozed.append(.init(prompt: current, until: now.addingTimeInterval(interval))) }
        finishCurrent()
    }

    /// Nobody answered. A reminder comes back in five minutes, a limited number of times, so stepping
    /// away from the desk doesn't lose it; everything else simply goes.
    public mutating func timeOutCurrent(now: Date) {
        guard var prompt = current else { return }
        if case .reminder = prompt.kind, prompt.repeatsLeft > 0 {
            prompt.repeatsLeft -= 1
            snoozed.append(.init(prompt: prompt, until: now.addingTimeInterval(Self.snoozeInterval)))
        }
        finishCurrent()
    }

    /// Brings back snoozed prompts whose time has come.
    public mutating func wake(now: Date) {
        let due = snoozed.filter { $0.until <= now }.sorted { $0.until < $1.until }
        guard !due.isEmpty else { return }
        snoozed.removeAll { $0.until <= now }
        for item in due {
            if current == nil {
                current = item.prompt
            } else {
                let index = waiting.firstIndex { $0.rank > item.prompt.rank } ?? waiting.count
                waiting.insert(item.prompt, at: index)
            }
        }
    }

    /// When the next snoozed prompt is due back, if any.
    public var nextWake: Date? { snoozed.map(\.until).min() }

    /// Drops every prompt about a task, wherever it is: the task was completed, deleted or answered elsewhere.
    public mutating func removeAll(forTask id: String) {
        waiting.removeAll { $0.taskID == id }
        snoozed.removeAll { $0.prompt.taskID == id }
        if current?.taskID == id { finishCurrent() }
    }

    /// Whether nothing is showing, waiting or snoozed.
    public var isEmpty: Bool { current == nil && waiting.isEmpty && snoozed.isEmpty }

    /// Drops prompts that no longer apply, judged by `isStale`.
    public mutating func prune(_ isStale: (NotchPrompt) -> Bool) {
        waiting.removeAll(where: isStale)
        snoozed.removeAll { isStale($0.prompt) }
        if let current, isStale(current) { finishCurrent() }
    }
}

/// Notices when an agent newly proposes a task as done. Proposals already there when Perch starts
/// don't count as new: they wait in "Ready to tick" without interrupting.
public struct ProposalTracker: Equatable, Sendable {
    private var seen: Set<String>?

    public init() {}

    private static func key(_ task: PerchTask) -> String { "\(task.id)|\(task.proposedDoneBy ?? "")" }

    /// The tasks proposed since the last call. The first call only takes stock.
    public mutating func newProposals(in tasks: [PerchTask]) -> [PerchTask] {
        let proposed = tasks.filter(\.isReadyToTick)
        let keys = Set(proposed.map(Self.key))
        defer { seen = keys }
        guard let seen else { return [] }
        return proposed.filter { !seen.contains(Self.key($0)) }
    }
}

/// The Today card's numbers for one day.
public enum NotchDay {
    /// Open tasks for `day`: on today that means everything due today or earlier; on any other day, tasks due that day.
    public static func open(_ tasks: [PerchTask], day: String, today: String, area: String? = nil) -> [PerchTask] {
        tasks.filter { task in
            guard task.isOpen, let due = TaskCalendar.dayKey(task.due), area == nil || task.area == area else { return false }
            return day == today ? due <= today : due == day
        }
    }

    public static func done(_ tasks: [PerchTask], day: String, area: String? = nil) -> [PerchTask] {
        tasks.filter { $0.completed == day && (area == nil || $0.area == area) }
    }

    /// The time of day as tasks write it, `16:05`: always 24-hour, whatever the Mac's own clock setting,
    /// so it can be compared with a task's `time`.
    public static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// The earliest time still to come among today's open tasks, for the closed notch.
    public static func nextTime(_ tasks: [PerchTask], today: String, now: Date, calendar: Calendar = .current) -> String? {
        let clock = clock(now, calendar: calendar)
        return tasks.filter { $0.isOpen && $0.due == today }.compactMap(\.time)
            .map { $0.count == 4 ? "0" + $0 : $0 }.filter { $0 >= clock }.min()
    }

    /// Share of the day's tasks that are done, 0...1. A day with nothing on it is 0, not complete.
    public static func progress(open: Int, done: Int) -> Double {
        let total = open + done
        return total > 0 ? Double(done) / Double(total) : 0
    }
}
