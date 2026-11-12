import Foundation

/// Whether two texts are exactly the same, code unit for code unit.
///
/// Swift's `==` on strings is Unicode-aware: it treats "é" written as one character and as e plus an accent
/// as equal, and to do that it normalizes both texts as it goes. On a long note, and on text that comes from
/// the editor still bridged from Objective-C, that is the slowest thing a keystroke did: three such
/// comparisons of the whole note per key. A note's file is its bytes, so the exact comparison is also the
/// right one for deciding whether there is anything to save.
public enum TextIdentity {
    public static func same(_ a: String, _ b: String) -> Bool {
        // Native text: the lengths, then the bytes.
        if let result = a.utf8.withContiguousStorageIfAvailable({ x in
            b.utf8.withContiguousStorageIfAvailable { y in
                x.count == y.count && (x.isEmpty || memcmp(x.baseAddress!, y.baseAddress!, x.count) == 0)
            }
        }), let result {
            return result
        }
        // Text still bridged from Objective-C: compared as UTF-16, still exactly.
        return (a as NSString).isEqual(to: b)
    }

    /// A native copy of text taken from the editor, so comparing and searching it later is quick.
    public static func native(_ text: String) -> String {
        var copy = text
        copy.makeContiguousUTF8()
        return copy
    }
}

/// When a note's reader draws while someone types.
///
/// It used to wait for typing to pause for 110 ms, and each keystroke started the wait again, so at an
/// ordinary pace the preview didn't change until the person stopped. Now a change asks for a render soon,
/// renders are kept at least `spacing` apart (longer when the last one took a while, as it does for a huge
/// note), and a change made while a render is waiting joins it: that render sends the newest text.
public struct RenderPacer {
    /// The shortest wait: enough to gather a key held down, or a paste and the edit after it.
    public static let soonest: TimeInterval = 0.03
    /// About eight renders a second while typing.
    public static let spacing: TimeInterval = 0.12
    /// A render that took this long is followed by a gap 1.5 times as long, so the reader never falls behind.
    public static let costFactor = 1.5

    private var lastSent: TimeInterval?
    private var cost: TimeInterval = 0
    private var waiting = false

    public init() {}

    /// The text changed at `now`: how long to wait before sending a render, or nil when one is already
    /// waiting and will send the newest text.
    public mutating func changed(at now: TimeInterval) -> TimeInterval? {
        guard !waiting else { return nil }
        waiting = true
        let gap = max(Self.spacing, cost * Self.costFactor)
        guard let lastSent else { return Self.soonest }
        return max(Self.soonest, lastSent + gap - now)
    }

    /// A render went to the reader, waited for or sent at once.
    public mutating func sent(at now: TimeInterval) {
        waiting = false
        lastSent = now
    }

    /// A waiting render was called off (the reader went away, or one was sent at once instead): the next
    /// change asks for a new one.
    public mutating func cancelled() {
        waiting = false
    }

    /// How long the reader took to draw the last render.
    public mutating func drawn(cost: TimeInterval) {
        self.cost = max(0, cost)
    }
}
