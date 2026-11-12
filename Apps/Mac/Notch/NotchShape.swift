import PerchKit
import PerchUI
import SwiftUI

/// The notch's colors. The panel itself is always hardware black, so it reads as part of the Mac;
/// the accent and the card tints come from the app's theme.
enum Ink {
    static let ground = Color.black
    static let raised = Color.white.opacity(0.07)
    static let hover = Color.white.opacity(0.12)
    static let text = Color.white.opacity(0.94)
    static let dim = Color.white.opacity(0.56)
    static let faint = Color.white.opacity(0.3)
    /// The theme's accent as its dark variant draws it, since the notch is always dark.
    @MainActor static var accent: Color { ThemeStore.shared.theme(for: .dark).accent }
    @MainActor static var danger: Color { ThemeStore.shared.theme(for: .dark).danger }
    @MainActor static var success: Color { ThemeStore.shared.theme(for: .dark).success }

    @MainActor static func priority(_ value: Int) -> Color {
        let theme = ThemeStore.shared.theme(for: .dark)
        switch value {
        case 1: return theme.danger
        case 2: return theme.warning
        case 3: return theme.info
        default: return Color.white.opacity(0.38)
        }
    }

    static func agent(_ name: String) -> Color {
        switch AgentHistory.mark(for: name) {
        case .claude: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .dot: return Color(red: 0.42, green: 0.74, blue: 1)
        case .house: return Color(red: 0.36, green: 0.86, blue: 0.72)
        case .initial: break
        }
        let palette: [Color] = [
            Color(red: 0.36, green: 0.86, blue: 0.72), Color(red: 0.66, green: 0.6, blue: 1),
            Color(red: 1, green: 0.58, blue: 0.72), Color(red: 0.42, green: 0.74, blue: 1),
        ]
        return palette[abs(name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % palette.count]
    }
}

/// One card's colors: a deep tinted surface that sits calmly on black, and a light ink of the
/// same hue for its icons, rings and buttons.
struct NotchTint: Equatable {
    var hue: Double

    @MainActor
    static func card(_ kind: NotchCardKind) -> NotchTint {
        let accent = ThemeRGB(hex: ThemeStore.shared.theme(for: .dark).hex(.accent)) ?? ThemeRGB(red: 1, green: 0.54, blue: 0.3)
        return NotchTint(hue: NotchTints.hue(for: kind, accentHue: NotchTints.hue(of: accent)))
    }

    private func color(_ saturation: Double, _ brightness: Double) -> Color {
        Color(hue: hue / 360, saturation: saturation, brightness: brightness)
    }

    var surfaceTop: Color { color(0.44, 0.29) }
    var surfaceBottom: Color { color(0.5, 0.18) }
    /// Light, slightly colored: for icons, rings and the filled button.
    var ink: Color { color(0.3, 1) }
    /// Wells and chips inside the card.
    var well: Color { Color.black.opacity(0.22) }
    var edge: Color { color(0.3, 1).opacity(0.13) }
}

/// Draws a `NotchOutline`, centered at the top of its rectangle. Its numbers animate, so the closed
/// notch, the peek, a prompt, the timer and the open panel are one shape changing size.
struct NotchOutlineShape: Shape {
    var outline: NotchOutline

    init(_ outline: NotchOutline) { self.outline = outline }

    typealias Pair = AnimatablePair<Double, Double>
    var animatableData: AnimatablePair<AnimatablePair<Pair, Pair>, AnimatablePair<Pair, Double>> {
        get {
            .init(
                .init(.init(outline.width, outline.height), .init(outline.neckWidth, outline.neckHeight)),
                .init(.init(outline.topRadius, outline.bottomRadius), outline.shoulderRadius)
            )
        }
        set {
            outline.width = newValue.first.first.first
            outline.height = newValue.first.first.second
            outline.neckWidth = newValue.first.second.first
            outline.neckHeight = newValue.first.second.second
            outline.topRadius = newValue.second.first.first
            outline.bottomRadius = newValue.second.first.second
            outline.shoulderRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let r = outline.resolved
        var path = Path()
        guard r.height > 0.05, r.neckWidth > 0.05 else { return path }
        let center = rect.midX, top = rect.minY
        let neck = r.neckWidth / 2, half = r.width / 2
        // A quarter circle as a cubic curve.
        let k = 0.5523
        func corner(_ path: inout Path, to end: CGPoint, from start: CGPoint, around pivot: CGPoint) {
            // `pivot` is the corner point the curve rounds off: control points lie toward it.
            path.addCurve(
                to: end,
                control1: CGPoint(x: start.x + (pivot.x - start.x) * k, y: start.y + (pivot.y - start.y) * k),
                control2: CGPoint(x: end.x + (pivot.x - end.x) * k, y: end.y + (pivot.y - end.y) * k)
            )
        }
        /// One side, drawn from the top edge down to the bottom edge. `side` is -1 for left, 1 for right.
        func points(_ side: Double) -> [(start: CGPoint, end: CGPoint, pivot: CGPoint)] {
            var corners: [(CGPoint, CGPoint, CGPoint)] = []
            let neckX = center + side * neck
            // The flare into the menu bar.
            corners.append((CGPoint(x: neckX + side * r.top, y: top), CGPoint(x: neckX, y: top + r.top), CGPoint(x: neckX, y: top)))
            var edgeX = neckX
            if r.hasShoulder {
                let y = top + r.neckHeight
                edgeX = center + side * half
                corners.append((CGPoint(x: neckX, y: y - r.shoulderInner), CGPoint(x: neckX + side * r.shoulderInner, y: y), CGPoint(x: neckX, y: y)))
                corners.append((CGPoint(x: edgeX - side * r.shoulderOuter, y: y), CGPoint(x: edgeX, y: y + r.shoulderOuter), CGPoint(x: edgeX, y: y)))
            }
            let bottom = top + r.height
            corners.append((CGPoint(x: edgeX, y: bottom - r.bottom), CGPoint(x: edgeX - side * r.bottom, y: bottom), CGPoint(x: edgeX, y: bottom)))
            return corners.map { (start: $0.0, end: $0.1, pivot: $0.2) }
        }
        let left = points(-1), right = points(1)
        path.move(to: left[0].start)
        for piece in left {
            path.addLine(to: piece.start)
            corner(&path, to: piece.end, from: piece.start, around: piece.pivot)
        }
        for piece in right.reversed() {
            path.addLine(to: piece.end)
            corner(&path, to: piece.start, from: piece.end, around: piece.pivot)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Motion level and staging

private struct NotchMotionKey: EnvironmentKey {
    static let defaultValue = NotchMotionLevel.full
}

private struct NotchRevealKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

private struct NotchRevealTimeKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

extension EnvironmentValues {
    /// The "Notch animations" setting, for views inside the notch.
    var notchMotion: NotchMotionLevel {
        get { self[NotchMotionKey.self] }
        set { self[NotchMotionKey.self] = newValue }
    }

    /// When set, the opening is held at this progress instead of playing, so a still can show it.
    var notchReveal: Double? {
        get { self[NotchRevealKey.self] }
        set { self[NotchRevealKey.self] = newValue }
    }

    /// When set with `notchReveal`, the content is held this many seconds after the panel began to open,
    /// each item where its own delayed spring would have it, instead of by the opening's progress.
    var notchRevealTime: Double? {
        get { self[NotchRevealTimeKey.self] }
        set { self[NotchRevealTimeKey.self] = newValue }
    }
}

/// Content of the open panel arriving: a fade and a short rise, each item a little after the last.
/// It starts while the shape is still growing, so the whole opening is one movement.
private struct NotchStagedIn: ViewModifier {
    @Environment(\.notchMotion) private var level
    @Environment(\.notchReveal) private var reveal
    @Environment(\.notchRevealTime) private var revealTime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    @State private var shown = false

    /// Held by time: the arrival the app plays, an `arrive` spring after this item's place in the stagger.
    private var heldByTime: Double? {
        revealTime.map { Motion.notchCurve(.arrive, level: level).value(at: $0, delay: Motion.notchStagger(index, level: level, reduceMotion: reduceMotion)) }
    }

    func body(content: Content) -> some View {
        let amount = heldByTime ?? reveal.map { NotchReveal.amount(progress: $0, index: index) } ?? (shown ? 1 : 0)
        let moves = level == .full && !reduceMotion
        content
            .opacity(amount)
            .offset(y: moves ? (1 - amount) * 7 : 0)
            .scaleEffect(moves ? 0.985 + 0.015 * amount : 1, anchor: .top)
            .onAppear {
                guard reveal == nil else { return }
                guard let animation = Motion.notch(.arrive, level: level, reduceMotion: reduceMotion) else {
                    shown = true
                    return
                }
                withAnimation(animation.delay(Motion.notchStagger(index, level: level, reduceMotion: reduceMotion))) { shown = true }
            }
    }
}

/// A small lift under the pointer, for anything in the notch that can be clicked.
private struct NotchHoverLift: ViewModifier {
    @Environment(\.notchMotion) private var level
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let scale: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .brightness(hovering ? 0.06 : 0)
            .scaleEffect(hovering && level == .full && !reduceMotion ? scale : 1)
            .onHover { value in
                withNotchMotion(.peek, level: level, reduceMotion: reduceMotion) { hovering = value }
            }
    }
}

extension View {
    /// Arrives with the open panel, `index` places into the stagger.
    func notchStaged(_ index: Int) -> some View { modifier(NotchStagedIn(index: index)) }

    /// Brightens and lifts slightly under the pointer.
    func notchHover(scale: CGFloat = 1.05) -> some View { modifier(NotchHoverLift(scale: scale)) }
}
