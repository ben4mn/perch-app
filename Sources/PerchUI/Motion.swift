import PerchKit
import SwiftUI

/// Perch's shared motion. Every animation in the app goes through here, so Reduce Motion
/// is honoured in one place: movement becomes a short fade, and nothing bounces or slides.
public enum Motion {
    /// Quick state changes: hover, selection, chips appearing.
    public static let quick = quickCurve.animation
    /// Layout changes: rows moving, sections opening, a view switching mode.
    public static let smooth = smoothCurve.animation
    /// Small celebratory moments: ticking a task, dropping a card.
    public static let bouncy = bouncyCurve.animation
    /// The three above as functions of time, for a snapshot holding a moment of one.
    public static let quickCurve = MotionCurve.easeOut(duration: 0.16)
    public static let smoothCurve = MotionCurve.spring(response: 0.36, damping: 0.86)
    public static let bouncyCurve = MotionCurve.spring(response: 0.3, damping: 0.62)
    /// What everything becomes under Reduce Motion.
    public static let reduced = Animation.easeOut(duration: 0.12)

    public static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : animation
    }

    /// How long a ticked task shows its check before it leaves the list. Shorter under Reduce Motion,
    /// where there is nothing to watch.
    public static func completionDelay(reduceMotion: Bool) -> Double { reduceMotion ? 0.18 : 0.48 }

    /// Delay for the item at `index` in a staggered entrance. Capped so long lists don't crawl.
    public static func stagger(_ index: Int, step: Double = 0.025, cap: Int = 12) -> Double {
        Double(min(index, cap)) * step
    }
}

public extension MotionCurve {
    /// The SwiftUI animation this curve describes.
    var animation: Animation {
        switch self {
        case let .spring(response, damping): return .spring(response: response, dampingFraction: damping)
        case let .easeOut(duration): return .easeOut(duration: duration)
        case let .easeInOut(duration): return .easeInOut(duration: duration)
        }
    }
}

private struct MotionModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(Motion.resolve(animation, reduceMotion: reduceMotion), value: value)
    }
}

/// Content that rises into place as it appears. Under Reduce Motion it only fades.
private struct RiseIn: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let delay: Double
    let distance: CGFloat
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : distance)
            .onAppear {
                withAnimation(Motion.resolve(Motion.smooth, reduceMotion: reduceMotion).delay(reduceMotion ? 0 : delay)) { shown = true }
            }
    }
}

/// Grows slightly while pressed or targeted, for buttons, cards and drop targets.
private struct Lift: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let active: Bool
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(active && !reduceMotion ? scale : 1)
            .animation(Motion.resolve(Motion.bouncy, reduceMotion: reduceMotion), value: active)
    }
}

public extension View {
    /// `.animation(_:value:)` that respects Reduce Motion.
    func motion<Value: Equatable>(_ animation: Animation = Motion.smooth, value: Value) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }

    /// Fades and rises into place on appear. Use `Motion.stagger(index)` as the delay for lists and grids.
    func riseIn(delay: Double = 0, distance: CGFloat = 8) -> some View {
        modifier(RiseIn(delay: delay, distance: distance))
    }

    /// Scales up a touch while `active`: hover, press, or a drag hovering over a drop target.
    func lift(_ active: Bool, scale: CGFloat = 1.03) -> some View {
        modifier(Lift(active: active, scale: scale))
    }
}

/// One short scale-up-and-settle when `trigger` changes, for something that has just been dropped or moved.
private struct Settle<Trigger: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let trigger: Trigger
    @State private var bumped = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(bumped ? 1.035 : 1)
            .onChange(of: trigger) {
                guard !reduceMotion else { return }
                bumped = true
                withAnimation(Motion.bouncy.delay(0.02)) { bumped = false }
            }
    }
}

/// A ring that spreads out once from behind the content as it appears, to say "this one is today".
private struct PulseOnce: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let active: Bool
    let color: Color
    @State private var progress: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background {
                if active, !reduceMotion {
                    Circle()
                        .stroke(color.opacity(Double(1 - progress) * 0.7), lineWidth: 2)
                        .scaleEffect(1 + progress * 0.9)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onAppear {
                guard active, !reduceMotion, progress == 0 else { return }
                withAnimation(.easeOut(duration: 0.5).delay(0.25)) { progress = 1 }
            }
    }
}

/// A light highlight and a slight sink while pressed. For cards and rows that are buttons.
public struct PerchPressStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
            .lift(configuration.isPressed, scale: 0.975)
    }
}

public extension View {
    /// A small bounce when `trigger` changes: the settle after a drop. Nothing under Reduce Motion.
    func settle<Trigger: Equatable>(on trigger: Trigger) -> some View {
        modifier(Settle(trigger: trigger))
    }

    /// One ring pulse on appear while `active`. Nothing under Reduce Motion.
    func pulseOnce(_ active: Bool, color: Color) -> some View {
        modifier(PulseOnce(active: active, color: color))
    }
}

public extension AnyTransition {
    /// For a row joining or leaving a list: it fades and closes up toward its top edge, so the rows
    /// below slide into the gap. Under Reduce Motion it only fades.
    static func perchRow(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92, anchor: .top))
    }

    /// For chips, pills and badges popping in and out.
    static func perchPop(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.8).combined(with: .opacity)
    }

    /// For banners and bars arriving from an edge.
    static func perchBanner(from edge: Edge, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }

    /// For content replacing other content in place. Pass the environment's Reduce Motion value.
    static func perchSwap(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985)).combined(with: .offset(y: 6))
    }

    /// For content sliding in from an edge, like moving to the next month.
    static func perchSlide(from edge: Edge, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let opposite: Edge = switch edge {
        case .leading: .trailing
        case .trailing: .leading
        case .top: .bottom
        case .bottom: .top
        }
        return .asymmetric(
            insertion: .move(edge: edge).combined(with: .opacity),
            removal: .move(edge: opposite).combined(with: .opacity)
        )
    }
}

/// Runs `body` with an animation, or with a plain fade under Reduce Motion.
@MainActor
public func withMotion(_ animation: Animation = Motion.smooth, reduceMotion: Bool, _ body: () -> Void) {
    withAnimation(Motion.resolve(animation, reduceMotion: reduceMotion), body)
}

// MARK: - The notch

public extension Motion {
    /// The notch's movements. They are tuned together so the open panel, a prompt and the focus timer
    /// all feel like the same object changing shape.
    enum NotchMove: Sendable {
        /// The panel growing out of the notch: quick and confident, with a small settle.
        case open
        /// The panel going back: faster than it came, and it doesn't bounce.
        case close
        /// The notch swelling under the pointer.
        case peek
        /// The closed notch widening for the timer or its counts.
        case live
        /// A prompt dropping out of the notch, with a visible overshoot so it gets noticed.
        case prompt
        /// A prompt going back in.
        case promptAway
        /// Content fading in or out inside the shape.
        case content
        /// Cards and rows moving to new places.
        case arrange
        /// The small bounce when something is dropped or ticked.
        case settle
        /// One item of the open panel coming in.
        case arrive
        /// A single nod from a waiting prompt's icon.
        case nod
    }

    /// A slow in-and-out that repeats, for the one place the notch breathes: its counts while something
    /// is overdue. Only ever started when the level is Full and Reduce Motion is off.
    static let notchBreath = Animation.easeInOut(duration: 2.6).repeatForever(autoreverses: true)
    /// A presence dot's ring spreading out, repeating. Same rule as `notchBreath`.
    static let notchPresence = Animation.easeOut(duration: 1.8).repeatForever(autoreverses: false)

    /// The animation for one of the notch's movements at the chosen level. Nil means "change at once":
    /// that is what Off asks for. Subtle keeps the timing and drops the bounce. Reduce Motion wins
    /// over both and turns every movement into the app's short fade.
    static func notch(_ move: NotchMove, level: NotchMotionLevel, reduceMotion: Bool) -> Animation? {
        if level == .off { return nil }
        if reduceMotion { return reduced }
        return notchCurve(move, level: level).animation
    }

    /// The same movement as a function of time, for a snapshot holding a moment of it. Subtle keeps the
    /// timing and drops the bounce.
    static func notchCurve(_ move: NotchMove, level: NotchMotionLevel = .full) -> MotionCurve {
        let calm = level == .subtle
        func spring(_ response: Double, _ damping: Double) -> MotionCurve {
            .spring(response: response, damping: calm ? 1 : damping)
        }
        switch move {
        case .open: return spring(0.3, 0.8)
        case .close: return spring(0.22, 0.96)
        case .peek: return spring(0.22, 0.7)
        case .live: return spring(0.36, 0.78)
        case .prompt: return spring(0.4, 0.66)
        case .promptAway: return spring(0.3, 0.92)
        case .content: return .easeOut(duration: 0.18)
        case .arrange: return spring(0.34, 0.84)
        case .settle: return spring(0.3, 0.6)
        case .arrive: return spring(0.32, 0.86)
        case .nod: return spring(0.28, 0.35)
        }
    }

    /// How long after the shape starts to open its first content begins to arrive, and the gap between
    /// items after that. Both are zero unless the level is Full.
    static func notchStagger(_ index: Int, level: NotchMotionLevel, reduceMotion: Bool) -> Double {
        guard level == .full, !reduceMotion else { return 0 }
        return 0.05 + Double(min(index, 8)) * 0.028
    }
}

/// Runs `body` with one of the notch's movements, or with no animation at all when the level is Off.
@MainActor
public func withNotchMotion(_ move: Motion.NotchMove, level: NotchMotionLevel, reduceMotion: Bool, _ body: () -> Void) {
    if let animation = Motion.notch(move, level: level, reduceMotion: reduceMotion) {
        withAnimation(animation, body)
    } else {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
    }
}

// MARK: - Completing a task

/// The tick inside a completion circle, as a path so it can be drawn on.
public struct CheckMarkShape: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.27, y: rect.minY + rect.height * 0.53))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.69))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.74, y: rect.minY + rect.height * 0.33))
        return path
    }
}

/// A ring and a few sparks thrown out from a completion circle, once, each time `trigger` goes up.
/// It draws nothing at rest and nothing at all under Reduce Motion.
public struct CompletionBurst: View {
    var color: Color
    var trigger: Int
    /// Holds the burst part-way through, for checking how it looks in a snapshot.
    var frozenAt: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 1

    public init(color: Color, trigger: Int, frozenAt: CGFloat? = nil) {
        self.color = color
        self.trigger = trigger
        self.frozenAt = frozenAt
    }

    public var body: some View {
        let progress = frozenAt ?? progress
        ZStack {
            if progress < 1, !reduceMotion || frozenAt != nil {
                Circle()
                    .stroke(color.opacity(Double(1 - progress) * 0.8), lineWidth: 2.2 * (1 - progress) + 0.4)
                    .scaleEffect(1 + progress * 1.15)
                ForEach(0..<6, id: \.self) { index in
                    Capsule()
                        .fill(color.opacity(Double(1 - progress)))
                        .frame(width: 2.4, height: 5.5 * (1 - progress * 0.6))
                        .offset(y: -(11 + progress * 10))
                        .rotationEffect(.degrees(Double(index) * 60 + 20))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { old, new in
            guard new > old, !reduceMotion else { return }
            self.progress = 0
            withAnimation(.easeOut(duration: 0.46)) { self.progress = 1 }
        }
    }
}

/// Text that is struck through with a left-to-right sweep when `isDone` turns on.
public struct StrikeSweepText: View {
    var text: String
    var isDone: Bool
    var font: Font
    var color: Color
    var doneColor: Color
    var lineLimit: Int? = 2
    /// Holds the sweep part-way (0 to 1, as `Motion.smoothCurve` has it), for a snapshot of a tick.
    var heldSweep: Double?

    public init(text: String, isDone: Bool, font: Font, color: Color, doneColor: Color, lineLimit: Int? = 2, heldSweep: Double? = nil) {
        self.text = text
        self.isDone = isDone
        self.font = font
        self.color = color
        self.doneColor = doneColor
        self.lineLimit = lineLimit
        self.heldSweep = heldSweep
    }

    public var body: some View {
        Text(text)
            .font(font)
            .lineLimit(lineLimit)
            .foregroundStyle(color)
            .opacity(heldSweep.map { 1 - min(max($0, 0), 1) } ?? (isDone ? 0 : 1))
            .overlay(alignment: .topLeading) {
                Text(text)
                    .font(font)
                    .lineLimit(lineLimit)
                    .strikethrough(true, color: doneColor)
                    .foregroundStyle(doneColor)
                    .mask(alignment: .leading) {
                        GeometryReader { geometry in
                            Rectangle().frame(width: heldSweep.map { geometry.size.width * max($0, 0) } ?? (isDone ? geometry.size.width : 0))
                        }
                    }
                    .accessibilityHidden(true)
            }
            .motion(Motion.smooth, value: isDone)
    }
}

// MARK: - Spacing and type

/// Shared spacing and sizes, so screens line up with each other. The ones that belong to text and rows
/// follow the Display settings (interface size and density); at the defaults they are the numbers below.
public enum Metrics {
    private static var display: DisplayMetrics { PerchDisplay.current.metrics }

    #if os(iOS)
    public static let screenPadding: CGFloat = 16
    /// Space above and below a list row's content.
    public static var rowPadding: CGFloat { CGFloat(display.rowPadding(10)) }
    public static var checkSize: CGFloat { CGFloat(display.length(22)) }
    /// The smallest comfortable thing to tap.
    public static let minTap: CGFloat = 44
    #else
    public static let screenPadding: CGFloat = 24
    public static var rowPadding: CGFloat { CGFloat(display.rowPadding(7)) }
    public static var checkSize: CGFloat { CGFloat(display.length(18)) }
    public static var minTap: CGFloat { CGFloat(max(display.length(24), 24)) }
    #endif
    public static let cardRadius: CGFloat = 10
    public static let controlRadius: CGFloat = 8
    public static var cardPadding: CGFloat { CGFloat(display.gap(12)) }
    public static var gap: CGFloat { CGFloat(display.gap(12)) }
    public static var tightGap: CGFloat { CGFloat(display.gap(6)) }
    /// Between a screen's header and its content, and between groups.
    public static var sectionGap: CGFloat { CGFloat(display.gap(18)) }
    /// Reading width for lists on very wide windows.
    public static var readableWidth: CGFloat { CGFloat(max(display.length(860), 860)) }

    /// A fixed size that belongs to text, such as an icon, a badge or a control's height: follows the interface size.
    public static func scaled(_ value: CGFloat) -> CGFloat { CGFloat(display.length(Double(value))) }
    /// Padding above and below a row that isn't `rowPadding`: follows the interface size and the density.
    public static func dense(_ value: CGFloat) -> CGFloat { CGFloat(display.rowPadding(Double(value))) }
    /// A fixed height for a row or cell: follows the interface size, and the density for its padding.
    public static func row(_ value: CGFloat) -> CGFloat { CGFloat(display.rowHeight(Double(value))) }
    /// A gap between things: follows the interface size gently, and the density.
    public static func spaced(_ value: CGFloat) -> CGFloat { CGFloat(display.gap(Double(value))) }
}

/// Perch's type scale. The iPhone uses text styles, so everything follows Dynamic Type and the text size
/// the root sets from the Display settings; the Mac keeps compact fixed sizes, multiplied by the interface size.
public extension Font {
    #if os(iOS)
    static let perchTitle = Font.title2.weight(.bold)
    static let perchHeading = Font.subheadline.weight(.semibold)
    static let perchBody = Font.callout
    /// A task or file title in a list.
    static let perchRow = Font.body
    static let perchCaption = Font.footnote
    /// A task title on a calendar card, a touch smaller than a list row.
    static let perchCard = Font.subheadline
    /// Text inside chips and small controls.
    static let perchChip = Font.caption.weight(.medium)
    static let perchSmall = Font.caption2.weight(.medium)
    /// Small uppercase section labels.
    static let perchEyebrow = Font.caption2.weight(.semibold)

    /// A system text style. It already follows the text size on iPhone.
    static func perchStyle(_ style: Font.TextStyle) -> Font { .system(style) }
    #else
    private static func sized(_ size: Double, _ weight: Font.Weight = .regular) -> Font {
        .system(size: CGFloat(PerchDisplay.current.metrics.font(size)), weight: weight)
    }
    static var perchTitle: Font { sized(22, .bold) }
    static var perchHeading: Font { sized(13, .semibold) }
    static var perchBody: Font { sized(13.5) }
    /// A task or file title in a list.
    static var perchRow: Font { sized(13.5) }
    static var perchCaption: Font { sized(11.5) }
    /// A task title on a calendar card, a touch smaller than a list row.
    static var perchCard: Font { sized(12.5) }
    /// Text inside chips and small controls.
    static var perchChip: Font { sized(11, .medium) }
    static var perchSmall: Font { sized(10, .medium) }
    /// Small uppercase section labels.
    static var perchEyebrow: Font { sized(10.5, .semibold) }

    /// A system text style that follows the interface size. The Mac doesn't scale text styles itself,
    /// so anything but Default is the style's own point size multiplied up or down.
    static func perchStyle(_ style: Font.TextStyle) -> Font {
        let metrics = PerchDisplay.current.metrics
        guard metrics.size != .standard else { return .system(style) }
        let base: (Double, Font.Weight) = switch style {
        case .largeTitle: (26, .regular)
        case .title: (22, .regular)
        case .title2: (17, .regular)
        case .title3: (15, .regular)
        case .headline: (13, .bold)
        case .body: (13, .regular)
        case .callout: (12, .regular)
        case .subheadline: (11, .regular)
        case .footnote, .caption: (10, .regular)
        case .caption2: (10, .medium)
        @unknown default: (13, .regular)
        }
        return .system(size: CGFloat(metrics.font(base.0)), weight: base.1)
    }
    #endif

    /// A fixed point size, for icons and other things that aren't running text, multiplied by the interface size.
    static func perchFixed(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: CGFloat(PerchDisplay.current.metrics.font(Double(size))), weight: weight, design: design)
    }
}

// MARK: - Empty state

/// A calm, helpful empty state: what this place is for, and one thing to do next.
public struct EmptyState: View {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?
    /// A small moment when the emptiness is an achievement: the icon springs in inside a spreading ring.
    var celebrates = false
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    public init(symbol: String, title: String, message: String, actionTitle: String? = nil, celebrates: Bool = false, action: (() -> Void)? = nil) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.celebrates = celebrates
        self.action = action
    }

    public var body: some View {
        let tint = celebrates ? theme.success : theme.textMuted
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.perchFixed(size: 28, weight: celebrates ? .regular : .light))
                .foregroundStyle(tint)
                .frame(width: 64, height: 64)
                .background(Circle().fill(celebrates ? theme.success.opacity(0.14) : theme.wash))
                .scaleEffect(celebrates && !arrived && !reduceMotion ? 0.6 : 1)
                .pulseOnce(celebrates, color: theme.success)
                .padding(.bottom, 2)
            Text(title).font(.perchHeading).foregroundStyle(theme.text).multilineTextAlignment(.center)
            Text(message)
                .font(.perchBody)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(PerchButtonStyle()).padding(.top, 6)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .riseIn()
        .onAppear {
            withAnimation(Motion.resolve(Motion.bouncy, reduceMotion: reduceMotion).delay(0.08)) { arrived = true }
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
/// The moving pieces held still, so they can be checked in a snapshot: the check at rest and ticked,
/// the burst part-way through, a struck title, and the "done for today" moment.
public struct MotionGallery: View {
    @Environment(\.perchTheme) private var theme
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Completing a task").font(.perchTitle).foregroundStyle(theme.text)
            HStack(spacing: 34) {
                ForEach(Array([theme.danger, theme.warning, theme.info, theme.textMuted].enumerated()), id: \.offset) { index, color in
                    VStack(spacing: 16) {
                        CheckCircle(color: color, isDone: false) {}
                        CheckCircle(color: color, isDone: true) {}
                        ZStack {
                            CheckCircle(color: color, isDone: true) {}
                            CompletionBurst(color: color, trigger: 0, frozenAt: [0.2, 0.45, 0.7, 0.9][index])
                                .frame(width: Metrics.checkSize, height: Metrics.checkSize)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    StrikeSweepText(text: "Not started", isDone: false, font: .perchRow, color: theme.text, doneColor: theme.textMuted)
                    StrikeSweepText(text: "Ticked a moment ago", isDone: true, font: .perchRow, color: theme.text, doneColor: theme.textMuted)
                }
            }
            .padding(.leading, 12)
            EmptyState(
                symbol: "checkmark", title: "Done for today",
                message: "You finished 6 tasks today. Enjoy it, or pull something forward from Upcoming.",
                actionTitle: "See Upcoming", celebrates: true, action: {}
            )
            .background(RoundedRectangle(cornerRadius: Metrics.cardRadius).fill(theme.wash))
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.background)
    }
}
#endif
