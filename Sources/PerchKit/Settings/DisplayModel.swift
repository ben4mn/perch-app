import Foundation

/// How big Perch draws its own interface: text, icons and the spacing that goes with them.
public enum InterfaceSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case standard = "default"
    case large
    case extraLarge

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .small: return "Small"
        case .standard: return "Default"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }

    /// What every fixed size is multiplied by. Default is exactly 1, so it changes nothing.
    public var scale: Double {
        switch self {
        case .small: return 0.9
        case .standard: return 1
        case .large: return 1.12
        case .extraLarge: return 1.25
        }
    }

    /// The same change as steps of the iPhone's text size, which is how the iPhone app scales its text.
    /// The steps are chosen to land close to `scale` for body text (15, 17, 19 and 21 points).
    public var textSizeSteps: Int {
        switch self {
        case .small: return -2
        case .standard: return 0
        case .large: return 1
        case .extraLarge: return 2
        }
    }

    /// The next size up or down, stopping at the ends. For the zoom shortcuts.
    public func stepped(by delta: Int) -> InterfaceSize {
        let all = Self.allCases
        let index = (all.firstIndex(of: self) ?? 1) + delta
        return all[min(max(index, 0), all.count - 1)]
    }
}

/// How much air rows get: lists, calendar cells and folder rows.
public enum InterfaceDensity: String, CaseIterable, Identifiable, Sendable {
    case compact, comfortable, roomy

    public var id: String { rawValue }
    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// Multiplies the space above and below a row.
    public var rowFactor: Double {
        switch self {
        case .compact: return 0.55
        case .comfortable: return 1
        case .roomy: return 1.5
        }
    }

    /// Multiplies gaps between things. Gentler than rows, so layouts keep their shape.
    public var gapFactor: Double {
        switch self {
        case .compact: return 0.85
        case .comfortable: return 1
        case .roomy: return 1.15
        }
    }
}

/// The sums behind the Display settings. Everything is exact at Default and Comfortable:
/// every function then returns the number it was given.
public struct DisplayMetrics: Equatable, Sendable {
    public var size: InterfaceSize
    public var density: InterfaceDensity

    public init(size: InterfaceSize = .standard, density: InterfaceDensity = .comfortable) {
        self.size = size
        self.density = density
    }

    public static let standard = DisplayMetrics()

    public var scale: Double { size.scale }
    public var isStandard: Bool { self == .standard }

    private static func half(_ value: Double) -> Double { (value * 2).rounded() / 2 }

    /// A font size in points. Rounded to half a point, and never unreadably small.
    public func font(_ base: Double) -> Double {
        size == .standard ? base : max(Self.half(base * scale), 8)
    }

    /// A length that should grow with the text: an icon, a check circle, a fixed row height.
    public func length(_ base: Double) -> Double {
        size == .standard ? base : Self.half(base * scale)
    }

    /// A gap between things. Follows the interface size at 60%, so bigger text doesn't spend the
    /// whole screen on space, and the density's gap factor.
    public func gap(_ base: Double) -> Double {
        isStandard ? base : Self.half(base * (1 + (scale - 1) * 0.6) * density.gapFactor)
    }

    /// The space above and below a row's content. Never less than 2 points, so rows stay apart.
    public func rowPadding(_ base: Double) -> Double {
        isStandard ? base : max(Self.half(base * scale * density.rowFactor), 2)
    }

    /// A fixed height that holds a row or cell: grows with the text, and with the density for the
    /// part that is padding (taken as a third of the height).
    public func rowHeight(_ base: Double) -> Double {
        isStandard ? base : Self.half(base * scale * (2.0 / 3 + density.rowFactor / 3))
    }

    // MARK: iPhone text size

    /// The iPhone's text sizes in order, as SwiftUI's `DynamicTypeSize.allCases` has them:
    /// 0 is xSmall, 3 is Large (the iPhone's default), 6 is xxxLarge, 7 to 11 are the accessibility sizes.
    public static let textSizeCount = 12
    public static let defaultTextSizeIndex = 3

    /// Which text size the iPhone app should draw with.
    /// - Parameters:
    ///   - system: the size chosen in the iPhone's own settings.
    ///   - matchSystem: start from the iPhone's size (true), or from the standard size (false).
    /// The interface size is added on top either way, and the result stays inside the range.
    public func textSizeIndex(system: Int, matchSystem: Bool) -> Int {
        let base = matchSystem ? system : Self.defaultTextSizeIndex
        return min(max(base + size.textSizeSteps, 0), Self.textSizeCount - 1)
    }
}

public extension AdaptiveLayout {
    /// The width a screen should lay itself out for. With wide layouts turned off, a wide screen is
    /// treated as just narrower than `wideWidth`, so it keeps the phone layouts.
    static func effectiveWidth(_ width: Double, allowsWide: Bool) -> Double {
        allowsWide ? width : min(width, wideWidth - 1)
    }
}
