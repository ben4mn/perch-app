import Foundation

/// One of the app's movements as a plain function of time: SwiftUI's `spring(response:dampingFraction:)`,
/// `easeOut(duration:)` and `easeInOut(duration:)`, worked out the way SwiftUI does. The animations in
/// `Motion` are built from these, so a snapshot that holds a moment of a movement (the notch opening,
/// a prompt dropping, a task being ticked) puts everything exactly where the animation would have it.
public enum MotionCurve: Equatable, Sendable {
    /// A spring from rest, with unit mass: stiffness (2π / response)², damping 4π · damping / response.
    case spring(response: Double, damping: Double)
    /// cubic-bezier(0, 0, 0.58, 1) over `duration` seconds.
    case easeOut(duration: Double)
    /// cubic-bezier(0.42, 0, 0.58, 1) over `duration` seconds.
    case easeInOut(duration: Double)

    /// How far along it is, 0 at the start and 1 at the end, `time` seconds after it starts
    /// (`delay` seconds after it is asked for). A spring may pass 1 and come back.
    public func value(at time: Double, delay: Double = 0) -> Double {
        let t = time - delay
        guard t > 0 else { return 0 }
        switch self {
        case let .spring(response, damping):
            return Self.spring(t, response: response, damping: damping)
        case let .easeOut(duration):
            return t >= duration ? 1 : Self.bezier(t / duration, 0, 0, 0.58, 1)
        case let .easeInOut(duration):
            return t >= duration ? 1 : Self.bezier(t / duration, 0.42, 0, 0.58, 1)
        }
    }

    /// The first moment after which it stays within `tolerance` of the end.
    public func settlingTime(tolerance: Double = 0.001) -> Double {
        switch self {
        case let .easeOut(duration), let .easeInOut(duration):
            // An ease reaches the end exactly at its duration; it is that close a little before.
            var time = duration
            while time > 0, abs(1 - value(at: time - 0.001)) <= tolerance { time -= 0.001 }
            return time
        case .spring:
            let step = 0.001
            var last = 0.0
            var time = 0.0
            while time < 10 {
                if abs(1 - value(at: time)) > tolerance { last = time + step }
                time += step
            }
            return last
        }
    }

    private static func spring(_ t: Double, response: Double, damping: Double) -> Double {
        let omega = 2 * Double.pi / max(response, 0.0001)
        let zeta = max(damping, 0)
        if zeta < 1 {
            let damped = omega * (1 - zeta * zeta).squareRoot()
            let decay = exp(-zeta * omega * t)
            return 1 - decay * (cos(damped * t) + (zeta * omega / damped) * sin(damped * t))
        } else if zeta == 1 {
            return 1 - exp(-omega * t) * (1 + omega * t)
        } else {
            let root = (zeta * zeta - 1).squareRoot()
            let r1 = -omega * (zeta - root), r2 = -omega * (zeta + root)
            return 1 - (r2 * exp(r1 * t) - r1 * exp(r2 * t)) / (r2 - r1)
        }
    }

    /// The y of a cubic bezier from (0, 0) to (1, 1) at the point whose x is `x`.
    private static func bezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        func coordinate(_ s: Double, _ p1: Double, _ p2: Double) -> Double {
            let inverse = 1 - s
            return 3 * inverse * inverse * s * p1 + 3 * inverse * s * s * p2 + s * s * s
        }
        // x(s) only ever increases for these curves, so halving the interval always finds it.
        var low = 0.0, high = 1.0
        for _ in 0..<60 {
            let middle = (low + high) / 2
            if coordinate(middle, x1, x2) < x { low = middle } else { high = middle }
        }
        return coordinate((low + high) / 2, y1, y2)
    }
}
