import AVFoundation
import AppKit
import Carbon.HIToolbox
import EventKit
import PerchKit
import PerchUI
import Speech
import SwiftUI

/// A system-wide shortcut. Carbon hot keys need no Accessibility permission.
final class GlobalHotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }, 1, &eventType, pointer, &handler)
        let id = EventHotKeyID(signature: OSType(0x50524348), id: 1)
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &reference)
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}

/// Watches for due reminders and starting events, and hands each to the notch as a prompt.
@MainActor
final class ReminderCenter: ObservableObject {
    @Published private(set) var events: [EKEvent] = []
    @AppStorage("calendarEnabled") var calendarEnabled = false

    /// Called with each reminder or event as it comes due.
    var onPrompt: ((NotchPrompt) -> Void)?
    private let model: AppModel
    private let store = EKEventStore()
    private var fired: Set<String>
    /// The same keys, oldest first, as they are saved.
    private var firedOrder: [String]
    private var timer: Timer?
    private let firedKey = "firedReminders"
    /// False in a preview run, which must not ring, poll, or save what it has rung.
    private let isLive: Bool

    init(model: AppModel, isLive: Bool = true) {
        self.model = model
        self.isLive = isLive
        firedOrder = UserDefaults.standard.stringArray(forKey: firedKey) ?? []
        fired = Set(firedOrder)
        guard isLive else { return }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadEvents() }
        }
        if calendarEnabled { reloadEvents() }
    }

    /// Starts or stops watching the clock. Reminders are shown by the notch, so while there is no notch
    /// (it is turned off in Settings) nothing is checked, rung or marked as rung.
    func setActive(_ active: Bool) {
        guard isLive, active != (timer != nil) else { return }
        timer?.invalidate()
        timer = nil
        guard active else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer?.tolerance = 2
    }

    func check(now: Date = Date()) {
        let due = TaskReminders.due(tasks: model.tasks, now: now, fired: fired)
        if !due.passed.isEmpty { markFired(due.passed) }
        for ring in due.rings {
            onPrompt?(NotchPrompt(id: ring.key, kind: .reminder(taskID: ring.taskID), title: ring.title, detail: ring.detail))
        }
        guard calendarEnabled else { return }
        reloadEvents()
        for event in events where !event.isAllDay {
            guard let start = event.startDate, start > now, start.timeIntervalSince(now) < 120 else { continue }
            let key = "event|\(event.eventIdentifier ?? "")|\(start.timeIntervalSince1970)"
            guard !fired.contains(key) else { continue }
            markFired([key])
            onPrompt?(NotchPrompt(id: key, kind: .event, title: event.title ?? "Event", detail: "Starts \(start.formatted(date: .omitted, time: .shortened))"))
        }
    }

    private func markFired(_ keys: [String]) {
        firedOrder = TaskReminders.remembered(firedOrder, adding: keys)
        fired = Set(firedOrder)
        guard isLive else { return }
        UserDefaults.standard.set(firedOrder, forKey: firedKey)
    }

    /// Asks macOS for the calendar. Nothing calls this at launch: it is for a "show my events" switch,
    /// which the notch doesn't have at the moment, so Perch never asks on its own.
    func requestCalendar() {
        store.requestFullAccessToEvents { granted, _ in
            Task { @MainActor [weak self] in
                self?.calendarEnabled = granted
                self?.reloadEvents()
            }
        }
    }

    /// Reads today's events. It has no code path that changes your calendar.
    func reloadEvents() {
        guard calendarEnabled, EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            events = []
            return
        }
        let start = Calendar.current.startOfDay(for: Date())
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }
}

/// Dictation that runs on this Mac only.
@MainActor
final class DictationController: ObservableObject {
    @Published var isListening = false
    @Published var transcript = ""
    @Published var errorMessage: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var onFinish: ((String) -> Void)?

    func toggle(onFinish: @escaping (String) -> Void) {
        if isListening {
            stop()
        } else {
            self.onFinish = onFinish
            start()
        }
    }

    private func start() {
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor [weak self] in
                guard status == .authorized else {
                    self?.errorMessage = "Allow speech recognition in System Settings to dictate."
                    return
                }
                self?.begin()
            }
        }
    }

    private func begin() {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            errorMessage = "On-device dictation isn't available for this language."
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request
        transcript = ""
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            Task { @MainActor in
                if let text { self?.transcript = text }
                if isFinal || error != nil { self?.finish() }
            }
        }
        do {
            engine.prepare()
            try engine.start()
            isListening = true
        } catch {
            errorMessage = "Couldn't start the microphone."
            finish()
        }
    }

    func stop() { request?.endAudio() }

    private func finish() {
        guard request != nil else { return }
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request = nil
        task = nil
        isListening = false
        if !transcript.isEmpty { onFinish?(transcript) }
        onFinish = nil
    }
}

/// Today's notepad: one Markdown file a day, saved automatically.
@MainActor
final class NotepadStore: ObservableObject {
    @Published var text = "" {
        didSet { if text != oldValue, !isShowingOnly { scheduleSave() } }
    }
    @AppStorage("notepadFolder") var folder = "Personal/Daily"
    /// True while a snapshot puts today's file in the card, so showing it never writes it back.
    private var isShowingOnly = false

    private let model: AppModel
    private var day = ""
    private var saveTask: Task<Void, Never>?

    init(model: AppModel) { self.model = model }

    var path: String { "\(folder)/\(model.today).md" }

    /// Reloads when the day changes or another device updated the file.
    func refresh() {
        let disk = (try? model.vault?.read(path)) ?? ""
        if day != model.today || saveTask == nil {
            day = model.today
            if text != disk { text = disk }
        }
    }

    #if DEBUG
    /// For the snapshot runner: today's notepad as it is on disk, shown and never saved.
    func debugShowToday() {
        isShowingOnly = true
        text = (try? model.vault?.read(path)) ?? ""
        isShowingOnly = false
    }
    #endif

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            self.model.save(self.text, to: self.path)
            self.saveTask = nil
            await self.model.reload()
        }
    }

    /// Command-Return: the caret's line becomes a task, and the line keeps a link to it.
    func makeTask(fromLineAt location: Int) {
        let source = text as NSString
        guard source.length > 0 else { return }
        let range = source.lineRange(for: NSRange(location: min(location, source.length - 1), length: 0))
        var line = source.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("- ") { line.removeFirst(2) }
        if line.hasPrefix("[ ] ") { line.removeFirst(4) }
        guard !line.isEmpty, let task = model.quickAdd(line) else { return }
        let hadNewline = source.substring(with: range).hasSuffix("\n")
        let replacement = "- [[\(String(task.path.dropLast(3)))|\(task.title)]]" + (hadNewline ? "\n" : "")
        text = source.replacingCharacters(in: range, with: replacement)
    }
}
