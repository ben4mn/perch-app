import Foundation

/// What clicking Perch in the Dock, or asking the notch to open Perch, does to the main window: bring back
/// the one there is, and open a new one only when none is left. Never two.
public enum MainWindowReopen {
    public enum Action: Equatable, Sendable {
        case bringForward
        case restore
        case openNew
    }

    /// The main window as it stands, if Perch still holds one.
    public struct Window: Equatable, Sendable {
        public var isVisible: Bool
        public var isMiniaturized: Bool

        public init(isVisible: Bool, isMiniaturized: Bool) {
            self.isVisible = isVisible
            self.isMiniaturized = isMiniaturized
        }
    }

    public static func action(window: Window?) -> Action {
        guard let window else { return .openNew }
        if window.isMiniaturized { return .restore }
        return window.isVisible ? .bringForward : .openNew
    }

    /// The answer to AppKit's "should I handle this Dock click?". Always no: Perch has done it. AppKit's own
    /// test, "are any windows visible?", counts the notch, so it would sometimes do nothing and, when it
    /// does act, SwiftUI opens a window beside the one Perch opened.
    public static func letsAppKitHandleReopen(hasVisibleWindows: Bool) -> Bool { false }
}

#if DEBUG
/// Where things are on screen, for the Mac's navigation stress test, which clicks them. Debug builds only.
@MainActor
public enum DebugProbes {
    /// Each shown task panel's X, by task, in the window's SwiftUI coordinates (top-left origin). By task, so a
    /// panel leaving late can't wipe out the one that replaced it.
    public static var taskPanelClose: [String: CGRect] = [:]
    /// How many times File, Close has run, and what it saw the last time.
    public static var closeCommands = 0
    public static var lastClose = ""
    /// What happened when, for the stress test's log.
    public static var timeline: [String] = []
    public static let started = Date()
    /// Each render the note view sent its reader (when, and how long the text was), and each "rendered"
    /// the reader answered with, for the note stress test.
    public static var renderSent: [(at: Date, length: Int)] = []
    public static var rendered: [Date] = []
    /// The open note's preview toggle, as its toolbar button calls it.
    public static var togglePreview: (() -> Void)?

    public static func mark(_ text: String) {
        timeline.append(String(format: "%7.2f ", Date().timeIntervalSince(started)) + text)
    }
}
#endif

#if os(macOS)
/// File, Close (Cmd+W) in the main window. A task's panel is the thing in front, so Cmd+W closes it first,
/// as Esc and the panel's X do. With no panel open it closes the window as usual, and every other window
/// (Settings, a sheet) is left to macOS.
public enum MainWindowClose {
    public enum Outcome: Equatable, Sendable {
        case closePanel
        case closeWindow
        case notOurs
    }

    public static func commandW(panelOpen: Bool, inMainWindow: Bool) -> Outcome {
        guard inMainWindow else { return .notOurs }
        return panelOpen ? .closePanel : .closeWindow
    }
}
#endif
