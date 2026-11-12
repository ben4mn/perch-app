import Foundation

/// When the pointer opens and closes the Mac notch.
///
/// Fed by every pointer event and, while it matters (the pointer is on the closed notch, or the panel is
/// open), by a steady poll of where the pointer is. The poll is what makes it dependable: macOS sends Perch
/// no pointer events while the pointer is over Perch's own window, so a panel that waited for events
/// could stay open after the pointer had left.
public struct NotchHover: Sendable {
    /// A short pause before opening, so the pointer passing by on its way to the menu bar doesn't open it.
    public static let openDelay: TimeInterval = 0.09
    /// How long the pointer may be away from the open panel before it closes.
    public static let closeDelay: TimeInterval = 0.35

    public enum Decision: Equatable, Sendable {
        case stay, open, close
    }

    private var arrivedAt: Date?
    private var leftAt: Date?
    /// False right after the panel closes with the pointer still on the notch: hover can't open it again
    /// until the pointer has left. Otherwise Escape, or a click, would be undone by the next small move.
    public private(set) var armed = true

    public init() {}

    /// While the panel is closed. `onNotch` is the pointer being over the notch's hover area.
    public mutating func closed(onNotch: Bool, pressed: Bool, at now: Date) -> Decision {
        guard onNotch, !pressed else {
            arrivedAt = nil
            if !onNotch { armed = true }
            return .stay
        }
        guard armed else { return .stay }
        let since = arrivedAt ?? now
        arrivedAt = since
        return now.timeIntervalSince(since) >= Self.openDelay ? .open : .stay
    }

    /// Whether the pointer is waiting on the closed notch, so the poll should keep running.
    public var isWaitingToOpen: Bool { arrivedAt != nil }

    /// While the panel is open. While something in the panel has the keyboard, it stays open.
    public mutating func open(insidePanel: Bool, keyboardInPanel: Bool, at now: Date) -> Decision {
        if insidePanel || keyboardInPanel {
            leftAt = nil
            return .stay
        }
        let since = leftAt ?? now
        leftAt = since
        return now.timeIntervalSince(since) >= Self.closeDelay ? .close : .stay
    }

    public mutating func didOpen() {
        arrivedAt = nil
        leftAt = nil
        armed = true
    }

    public mutating func didClose(pointerOnNotch: Bool) {
        arrivedAt = nil
        leftAt = nil
        armed = !pointerOnNotch
    }

    /// While a full-screen app covers the notch, hover can't open it. It stops waiting, so the poll stops,
    /// and an arrival from before the cover doesn't count afterwards. The pointer leaving still counts, so
    /// a close just before the cover doesn't outlive it.
    public mutating func covered(onNotch: Bool) {
        arrivedAt = nil
        if !onNotch { armed = true }
    }

    /// The notch's window is larger than the panel (room for its shadow and spring). Only the panel itself
    /// takes clicks; the clear border around it lets them through to whatever is underneath.
    public static func panelTakesClicks(open: Bool, pointerInPanel: Bool) -> Bool { open && pointerInPanel }

    /// How far beyond the drawn notch the pointer still counts as on it. The same whether or not menus
    /// need the room beside the notch, so the notch feels the same over every app.
    public static func hoverMargin(hasRoom: Bool) -> Double { 10 }
}

/// Whether a full-screen app covers the notch's screen, as last looked, and when to look again.
///
/// Looking means listing every window on screen (about half a millisecond), so it isn't done on every
/// pointer event. But while the answer is yes the notch is put away and hover can't open it, so a yes must
/// never wait for another app to come forward or the space to change before it is looked at again. It can
/// be left over from the slide out of a full-screen space, if macOS announces the change while the window
/// being left still counts as on screen, or from a screen-sized window that went without any app coming
/// forward.
public struct NotchFullScreenCheck: Sendable {
    /// While the answer is yes, the pointer on the notch looks again at most this often.
    public static let pointerInterval: TimeInterval = 0.5
    /// After another app comes forward or the space changes, look again this long after, once the slide is over.
    public static let settleDelays: [TimeInterval] = [0.5, 1.5]

    public private(set) var isFullScreen = false
    private var checkedAt: Date?

    public init() {}

    public mutating func record(_ fullScreen: Bool, at now: Date) {
        isFullScreen = fullScreen
        checkedAt = now
    }

    /// The pointer moved while the panel is closed. Whether to look again before deciding what hover does.
    public func shouldCheck(pointerOnNotch: Bool, at now: Date) -> Bool {
        guard isFullScreen, pointerOnNotch else { return false }
        guard let checkedAt else { return true }
        return now.timeIntervalSince(checkedAt) >= Self.pointerInterval
    }
}
