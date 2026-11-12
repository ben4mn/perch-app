import AppKit
import PerchKit
import PerchUI
import SwiftUI

/// The focus timer. It pauses while the Mac sleeps, and keeps running when the notch closes.
@MainActor
final class FocusController: ObservableObject {
    enum Mode: Equatable { case countdown(total: Int), stopwatch }

    @Published private(set) var mode: Mode?
    @Published private(set) var elapsed = 0
    @Published private(set) var isPaused = false
    @Published private(set) var didFinish = false
    @Published var taskID: String?

    var onFinish: (() -> Void)?
    private let log: FocusLog
    private var ticker: Timer?
    private var start = Date()
    private var observers: [NSObjectProtocol] = []
    private var pausedBySleep = false

    init(log: FocusLog) {
        self.log = log
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRunning, !self.isPaused else { return }
                self.pausedBySleep = true
                self.pause()
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.pausedBySleep else { return }
                self.pausedBySleep = false
                self.resume()
            }
        })
    }

    var isRunning: Bool { mode != nil }

    /// How far through a countdown, from 0 to 1. A stopwatch fills once a minute.
    var progress: Double {
        switch mode {
        case let .countdown(total): return total > 0 ? Double(elapsed) / Double(total) : 0
        case .stopwatch: return Double(elapsed % 60) / 60
        case nil: return 0
        }
    }

    var remaining: Int {
        if case let .countdown(total) = mode { return max(0, total - elapsed) }
        return elapsed
    }

    var display: String {
        let seconds = remaining
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    func startCountdown(minutes: Int, task: String? = nil) { begin(.countdown(total: minutes * 60), task: task) }
    func startStopwatch(task: String? = nil) { begin(.stopwatch, task: task) }

    private func begin(_ mode: Mode, task: String?) {
        if isRunning { stop() }
        self.mode = mode
        taskID = task
        elapsed = 0
        isPaused = false
        didFinish = false
        start = Date()
        schedule()
    }

    private func schedule() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard !isPaused else { return }
        elapsed += 1
        if case let .countdown(total) = mode, elapsed >= total {
            didFinish = true
            NSSound(named: "Glass")?.play()
            onFinish?()
            stop(keepFinished: true)
        }
    }

    func pause() { isPaused = true }
    func resume() { isPaused = false }

    /// The length of the countdown in seconds, or nil for a stopwatch or no session.
    var total: Int? {
        if case let .countdown(total) = mode { return total }
        return nil
    }

    /// Puts away the "finished" state once it has been acknowledged.
    func clearFinished() { didFinish = false }

    #if DEBUG
    /// Shows a session part-way through without starting a clock or writing to the focus log,
    /// for checking the look in a snapshot.
    func debugPreview(total: Int?, elapsed: Int, paused: Bool = false, task: String? = nil) {
        ticker?.invalidate()
        ticker = nil
        mode = total.map { .countdown(total: $0) } ?? .stopwatch
        self.elapsed = elapsed
        isPaused = paused
        taskID = task
    }

    /// Back to no session, without logging one.
    func debugClear() {
        ticker?.invalidate()
        ticker = nil
        mode = nil
        elapsed = 0
        isPaused = false
        didFinish = false
        taskID = nil
    }
    #endif

    func addFiveMinutes() {
        if case let .countdown(total) = mode { mode = .countdown(total: total + 300) }
    }

    /// The timer was hidden in Settings: a session under way ends here, and what was done is logged.
    func hide() {
        if isRunning { stop() }
        didFinish = false
        pausedBySleep = false
    }

    func stop(keepFinished: Bool = false) {
        ticker?.invalidate()
        ticker = nil
        if elapsed > 0 { log.add(FocusSession(start: start, seconds: elapsed, taskID: taskID)) }
        mode = nil
        elapsed = 0
        isPaused = false
        if !keepFinished { didFinish = false }
    }
}
