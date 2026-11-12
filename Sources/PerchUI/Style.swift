import PerchKit
import SwiftUI

// MARK: - Theme-derived colours

public extension PerchTheme {
    /// A faint fill that sits on the background: quiet headers, fields, resting cards.
    var wash: Color { text.opacity(isDark ? 0.07 : 0.05) }
    /// A slightly stronger fill, for hover and pressed.
    var washStrong: Color { text.opacity(isDark ? 0.12 : 0.09) }
    /// A hairline for separating things on the background.
    var hairline: Color { text.opacity(isDark ? 0.12 : 0.1) }
    /// The accent as a wash under a drop target.
    var dropFill: Color { accent.opacity(isDark ? 0.26 : 0.18) }
}

/// Colors and small visual pieces shared by every task view. Status colours come from the theme;
/// the colours that tell areas, people and labels apart are fixed hues, toned to stay readable on it.
enum Palette {
    private static let hues: [(Double, Double, Double)] = [
        (0.2, 0.72, 0.6), (0.55, 0.47, 0.95), (0.93, 0.42, 0.6), (0.25, 0.6, 0.95), (0.95, 0.6, 0.2),
    ]

    /// A fixed hue, darkened on light themes so text in it still reads on a pale background.
    private static func toned(_ hue: (Double, Double, Double), theme: PerchTheme) -> Color {
        let factor = theme.isDark ? 1 : 0.68
        return Color(.sRGB, red: hue.0 * factor, green: hue.1 * factor, blue: hue.2 * factor, opacity: 1)
    }

    private static func hashed(_ text: String, theme: PerchTheme) -> Color {
        toned(hues[abs(text.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % hues.count], theme: theme)
    }

    static func area(_ area: String, theme: PerchTheme) -> Color {
        switch AreaTint.fixed(for: area, standard: PerchConfiguration.main.standardAreas) {
        case .first: return toned((0.27, 0.52, 0.98), theme: theme)
        case .personal: return toned((0.16, 0.7, 0.56), theme: theme)
        case nil: return hashed(QuickAdd.simplifiedArea(area).lowercased(), theme: theme)
        }
    }

    static func person(_ name: String, me: String, theme: PerchTheme) -> Color {
        name == me ? theme.accent : hashed(name, theme: theme)
    }

    static func label(_ name: String, theme: PerchTheme) -> Color { hashed(name.lowercased(), theme: theme) }

    static func priority(_ value: Int, theme: PerchTheme) -> Color {
        switch value {
        case 1: return theme.danger
        case 2: return theme.warning
        case 3: return theme.info
        default: return theme.textMuted
        }
    }

    static func dueColor(_ task: PerchTask, today: String, theme: PerchTheme) -> Color {
        guard let due = task.due else { return theme.textMuted }
        if task.isOverdue(today: today) { return theme.danger }
        if due == today { return theme.success }
        if due == DayMath.adding(days: 1, to: today) { return theme.warning }
        return theme.info
    }

    /// The emoji at the start of an area's name, if it has one.
    static func emoji(_ area: String) -> String? {
        guard let first = area.unicodeScalars.first, first.properties.isEmojiPresentation || first.properties.isEmoji && first.value > 0x2000 else { return nil }
        return String(area.split(separator: " ").first ?? "")
    }
}

/// How each kind of file looks in a folder or a search result.
enum FileLook {
    static func tint(_ kind: VaultFileKind, theme: PerchTheme) -> Color {
        switch kind {
        case .board: return theme.info
        case .whiteboard: return theme.warning
        case .notebook, .task: return theme.success
        default: return theme.textSecondary
        }
    }

    static func label(_ kind: VaultFileKind) -> String {
        let noun = FolderListing.noun(kind)
        return noun.prefix(1).uppercased() + noun.dropFirst()
    }
}

// MARK: - Small pieces

/// A round initial for a person or agent.
struct Avatar: View {
    var name: String
    var me: String
    var size: CGFloat = 18
    @Environment(\.perchTheme) private var theme

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.perchFixed(size: size * 0.5, weight: .bold, design: .rounded))
            .foregroundStyle(name == me ? theme.accentText : Color.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Palette.person(name, me: me, theme: theme)))
            .help(name)
            .accessibilityLabel(name)
    }
}

/// A small tinted capsule: icon plus text.
struct Chip: View {
    /// Read so this is drawn again when the interface size or density changes.
    @Environment(\.perchDisplay) private var display
    var text: String
    var symbol: String?
    var tint: Color
    var filled = true
    var small = false

    var body: some View {
        let _ = display
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).imageScale(.small).fontWeight(.semibold) }
            Text(text).lineLimit(1)
        }
        .font(small ? .perchSmall : .perchChip)
        .foregroundStyle(tint)
        .padding(.horizontal, filled ? 7 : 2).padding(.vertical, 2.5)
        .background(Capsule().fill(tint.opacity(filled ? 0.14 : 0)))
    }
}

/// A small rounded count, as used beside group and day headings.
struct CountBadge: View {
    var count: Int
    var tint: Color?
    @Environment(\.perchTheme) private var theme

    var body: some View {
        let tint = tint ?? theme.textSecondary
        Text("\(count)")
            .font(.perchSmall.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .background(Capsule().fill(tint.opacity(0.14)))
            .fixedSize()
            .contentTransition(.numericText())
            .motion(Motion.smooth, value: count)
            .accessibilityLabel(DayLabel.tasks(count))
    }
}

/// A small uppercase label above a group of things.
struct SectionLabel: View {
    var text: String
    @Environment(\.perchTheme) private var theme

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased()).font(.perchEyebrow).kerning(0.5).foregroundStyle(theme.textMuted)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Perch's own button look, in the theme's colours. `prominent` fills with the accent.
struct PerchButtonStyle: ButtonStyle {
    var prominent = false
    var tint: Color?
    @Environment(\.perchTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let fill = tint ?? theme.accent
        configuration.label
            .font(.perchBody.weight(.medium))
            .foregroundStyle(prominent ? (tint == nil ? theme.accentText : Color.white) : theme.text)
            .padding(.horizontal, 12)
            .frame(minHeight: buttonHeight)
            .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).fill(prominent ? fill : (configuration.isPressed ? theme.washStrong : theme.surface)))
            .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).strokeBorder(prominent ? Color.clear : theme.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed && prominent ? 0.85 : 1) : 0.45)
            .lift(configuration.isPressed, scale: 0.97)
    }

    private var buttonHeight: CGFloat {
        #if os(iOS)
        Metrics.scaled(36)
        #else
        Metrics.scaled(26)
        #endif
    }
}

/// A fill behind a row or card that shows on hover, and stays on while it is the selected one.
private struct HoverHighlight: ViewModifier {
    var selected: Bool
    var radius: CGFloat
    var resting: Bool
    @Environment(\.perchTheme) private var theme
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .onHover { hovering = $0 }
            .motion(Motion.quick, value: hovering)
            .motion(Motion.quick, value: selected)
    }

    private var fill: Color {
        if selected { return theme.accentSoft }
        if hovering { return resting ? theme.washStrong : theme.wash }
        return resting ? theme.wash : .clear
    }
}

extension View {
    /// Highlights on hover (Mac and iPad pointers), and while `selected`. `resting` keeps a faint card behind it.
    func hoverHighlight(selected: Bool = false, radius: CGFloat = Metrics.controlRadius, resting: Bool = false) -> some View {
        modifier(HoverHighlight(selected: selected, radius: radius, resting: resting))
    }

}

public extension View {
    /// The theme's background behind a whole screen, so lists and forms don't show the system's own.
    /// On iPhone the navigation bar and tab bar take the theme's colours too.
    func perchScreenBackground() -> some View {
        modifier(ScreenBackground())
    }
}

public extension View {
    /// For what goes inside a sheet or popover. Those open in a window of their own, which would otherwise
    /// keep the system's background and text colors: this gives them the theme's surface, text, accent and
    /// light or dark controls, so a dark theme on a light Mac (or the reverse) still reads.
    func perchPresented() -> some View {
        modifier(PresentedSurface())
    }
}

private struct PresentedSurface: ViewModifier {
    @Environment(\.perchTheme) private var theme

    func body(content: Content) -> some View {
        content
            .foregroundStyle(theme.text)
            .tint(theme.accent)
            .background(theme.surface.ignoresSafeArea())
            .environment(\.colorScheme, theme.colorScheme)
            .presentationBackground(theme.surface)
    }
}

private struct ScreenBackground: ViewModifier {
    @Environment(\.perchTheme) private var theme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(theme.background.ignoresSafeArea())
            .foregroundStyle(theme.text)
            #if os(iOS)
            .toolbarBackground(theme.sidebar, for: .navigationBar, .tabBar)
            .toolbarColorScheme(theme.colorScheme, for: .navigationBar, .tabBar)
            #endif
    }
}

/// What follows the pointer while a task is dragged: its title on a small raised card.
struct TaskDragPreview: View {
    var title: String
    var tint: Color
    @Environment(\.perchTheme) private var theme

    var body: some View {
        HStack(spacing: 7) {
            Circle().strokeBorder(tint, lineWidth: 1.6).frame(width: 14, height: 14)
            Text(title).font(.perchBody).foregroundStyle(theme.text).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(maxWidth: 280, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).strokeBorder(theme.accent.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        .padding(10)
    }
}

// MARK: - Screen header

/// One fact in a screen's header: "12 open", "3 overdue".
struct HeaderStat: Identifiable {
    var id: String { text }
    var text: String
    var symbol: String?
    var tint: Color?
}

/// The top of every screen: its title, a line of counts, and its main controls, all in the content
/// area. On iPhone the navigation bar already shows the title, so only the counts and controls appear.
struct ScreenHeader<Trailing: View, Controls: View>: View {
    var title: String
    var stats: [HeaderStat] = []
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var controls: Controls
    @Environment(\.perchTheme) private var theme

    private var showsTitle: Bool {
        #if os(iOS)
        false
        #else
        true
        #endif
    }

    @ViewBuilder
    private var titleText: some View {
        if showsTitle {
            Text(title).font(.perchTitle).foregroundStyle(theme.text).lineLimit(1).minimumScaleFactor(0.75)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var statsRow: some View {
        ForEach(stats) { stat in
            HStack(spacing: 3) {
                if let symbol = stat.symbol { Image(systemName: symbol).imageScale(.small) }
                Text(stat.text).contentTransition(.numericText())
            }
            .font(stat.tint == nil ? .perchBody : .perchBody.weight(.medium))
            .foregroundStyle(stat.tint ?? theme.textSecondary)
            .lineLimit(1)
            .transition(.opacity)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsTitle || !stats.isEmpty || Trailing.self != EmptyView.self {
                // On one line when it fits. With large text on a narrow screen the counts drop under the
                // title instead of being cut short.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        titleText
                        statsRow
                        Spacer(minLength: 0)
                        trailing
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            titleText
                            Spacer(minLength: 0)
                            trailing
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 10) { statsRow }
                    }
                }
                .motion(Motion.smooth, value: stats.map(\.text))
            }
            controls
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, showsTitle ? 20 : 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, stats: [HeaderStat] = [], @ViewBuilder controls: () -> Controls) {
        self.init(title: title, stats: stats, trailing: { EmptyView() }, controls: controls)
    }
}

extension ScreenHeader where Trailing == EmptyView, Controls == EmptyView {
    init(title: String, stats: [HeaderStat] = []) {
        self.init(title: title, stats: stats, trailing: { EmptyView() }, controls: { EmptyView() })
    }
}

/// A screen's header above its scrolling content. With room to spare the header stays put; on a compact
/// screen, such as a phone, it scrolls away with the content so the list gets the whole height.
struct HeaderScroll<Header: View, Content: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .compact {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    content
                }
            }
        } else {
            VStack(spacing: 0) {
                header
                ScrollView { content }
            }
        }
    }
}

/// The button at the end of a header's counts line that shows and hides the screen's filter controls
/// on a compact screen, where a row of them above every list costs too much height.
struct FilterToggle: View {
    /// The controls are showing.
    var isOpen: Bool
    /// Something is being filtered, so the list below is not everything.
    var isFiltering: Bool
    var action: () -> Void
    @Environment(\.perchTheme) private var theme

    private var size: CGFloat { Metrics.scaled(28) }
    private var hitPadding: CGFloat { max((Metrics.minTap - size) / 2, 0) }

    var body: some View {
        Button(action: action) {
            Image(systemName: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.perchBody.weight(.medium))
                .foregroundStyle(isOpen || isFiltering ? theme.accent : theme.textSecondary)
                .frame(width: size, height: size)
                .background(Circle().fill(isOpen ? theme.accentSoft : theme.wash))
                // A small button to look at, with a full-size target around it that takes no room in the line.
                .padding(hitPadding)
                .contentShape(Rectangle())
                .padding(-hitPadding)
        }
        .buttonStyle(PerchPressStyle())
        .help(isOpen ? "Hide the filter" : "Filter")
        .accessibilityLabel(isFiltering ? "Filter, on" : "Filter")
        .accessibilityValue(isOpen ? "Showing" : "Hidden")
    }
}

/// A rounded search-style field for narrowing what a screen shows.
struct FilterField: View {
    @Binding var text: String
    var prompt = "Filter"
    var symbol = "magnifyingglass"
    @Environment(\.perchTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.perchCaption.weight(.medium)).foregroundStyle(theme.textMuted)
            TextField(prompt, text: $text).textFieldStyle(.plain).font(.perchBody).foregroundStyle(theme.text)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(theme.textMuted) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear filter")
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 9)
        .frame(minHeight: controlHeight)
        .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).fill(theme.wash))
        .motion(Motion.quick, value: text.isEmpty)
    }
}

private var controlHeight: CGFloat {
    #if os(iOS)
    Metrics.scaled(36)
    #else
    Metrics.scaled(28)
    #endif
}

/// A capsule button label for a screen's controls: "Group: Due date ⌄".
struct ControlChip: View {
    var symbol: String
    var text: String
    var isOn = false
    var showsChevron = true
    @Environment(\.perchTheme) private var theme
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).imageScale(.small).fontWeight(.semibold)
            Text(text).lineLimit(1)
            if showsChevron { Image(systemName: "chevron.down").font(.perchFixed(size: 8, weight: .bold)).opacity(0.6) }
        }
        .font(.perchChip)
        .foregroundStyle(isOn ? theme.accent : theme.text.opacity(0.85))
        .padding(.horizontal, 10)
        .frame(minHeight: controlHeight)
        .background(Capsule().fill(isOn ? theme.accentSoft : (hovering ? theme.washStrong : theme.wash)))
        .contentShape(Capsule())
        .fixedSize()
        .onHover { hovering = $0 }
        .motion(Motion.quick, value: hovering)
        .motion(Motion.quick, value: isOn)
    }
}

struct ChipMenu: ViewModifier {
    func body(content: Content) -> some View {
        content.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }
}

/// Lays out children left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + CGFloat(max(rows.count - 1, 0)) * spacing
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if rows[rows.count - 1].width + size.width > width, !rows[rows.count - 1].items.isEmpty { rows.append(Row()) }
            var row = rows[rows.count - 1]
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

func relativeDay(_ date: String, today: String) -> String {
    guard !date.isEmpty else { return "" }
    return friendlyDate(String(date.prefix(10)), today: today)
}

func friendlyDate(_ date: String, today: String) -> String {
    if let relative = DayLabel.relative(date, today: today) { return relative }
    guard let value = DayMath.date(from: date) else { return date }
    let sameYear = date.prefix(4) == today.prefix(4)
    return value.formatted(sameYear ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).day().year())
}
