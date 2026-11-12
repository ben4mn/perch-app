import PerchKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// The theme settings: a compact section for a settings form, and the full screen with
// theme cards, a live preview, per-colour pickers and copy and paste.

// MARK: - Form section

/// Rows for a settings form: `Form { Section("Appearance") { ThemeSettingsSection() } }`.
/// Picks a theme in place and opens the full theme screen for everything else.
public struct ThemeSettingsSection: View {
    /// Read so this is drawn again when the interface size or density changes.
    @Environment(\.perchDisplay) private var display
    @ObservedObject private var store: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingThemes = false

    /// Uses `ThemeStore.shared` unless you pass another store.
    @MainActor public init(store: ThemeStore? = nil) {
        self.store = store ?? .shared
    }

    public var body: some View {
        let _ = display
        let scheme = store.preferredColorScheme ?? colorScheme
        let theme = store.theme(for: scheme)
        Group {
            Picker("Theme", selection: Binding(
                get: { store.selectedID },
                set: { id in withMotion(Motion.smooth, reduceMotion: reduceMotion) { store.select(id) } }
            )) {
                Text("System").tag(ThemePresets.systemID)
                Section("Light") { ForEach(ThemePresets.light) { Text($0.name).tag($0.id) } }
                Section("Dark") { ForEach(ThemePresets.dark) { Text($0.name).tag($0.id) } }
                if !store.importedThemes.isEmpty {
                    Section("Yours") { ForEach(store.importedThemes) { Text($0.name).tag($0.id) } }
                }
            }
            if store.selectedID == ThemePresets.systemID {
                Picker("Appearance", selection: Binding(get: { store.appearance }, set: { store.setAppearance($0) })) {
                    ForEach(ThemeAppearance.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            HStack(spacing: Metrics.gap) {
                ThemeThumbnail(theme: theme)
                    .frame(width: 84, height: 54)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.isCustomised(for: scheme) ? "\(theme.name), customized" : theme.name)
                    Text("Colors, accent and your own changes")
                        .font(.perchStyle(.caption)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Customize…") { showingThemes = true }
            }
        }
        .sheet(isPresented: $showingThemes) {
            NavigationStack {
                ThemeSettingsView(store: store)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showingThemes = false } }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 560, idealWidth: 760, minHeight: 560, idealHeight: 720)
            #endif
        }
    }
}

// MARK: - Full screen

/// The whole theme screen. Push it in a navigation stack on iPhone, or show it in a sheet or window on the Mac.
public struct ThemeSettingsView: View {
    @ObservedObject private var store: ThemeStore
    /// Read so this is drawn again when the interface size or density changes.
    @Environment(\.perchDisplay) private var display
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 600
    @State private var notice: Notice?

    private struct Notice: Equatable {
        var text: String
        var isProblem = false
    }

    /// Uses `ThemeStore.shared` unless you pass another store.
    @MainActor public init(store: ThemeStore? = nil) {
        self.store = store ?? .shared
    }

    private var scheme: ColorScheme { store.preferredColorScheme ?? colorScheme }
    private var theme: PerchTheme { store.theme(for: scheme) }
    private var isWide: Bool { width >= 720 }

    public var body: some View {
        let theme = theme
        let _ = display
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                systemCard(theme)
                themeGrid("Light", themes: ThemePresets.light.map(PerchTheme.init), current: theme)
                themeGrid("Dark", themes: ThemePresets.dark.map(PerchTheme.init), current: theme)
                if !store.importedThemes.isEmpty {
                    themeGrid("Yours", themes: store.importedThemes, current: theme, removable: true)
                }
                accentSection(theme)
                if isWide {
                    HStack(alignment: .top, spacing: 24) {
                        customiseSection(theme)
                        previewSection(theme).frame(width: min(width * 0.42, 380))
                    }
                } else {
                    previewSection(theme)
                    customiseSection(theme)
                }
                shareSection(theme)
            }
            .padding(.horizontal, width < 360 ? 14 : Metrics.screenPadding)
            .padding(.vertical, Metrics.screenPadding)
            .frame(maxWidth: 940, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background {
            GeometryReader { proxy in
                theme.background
                    .ignoresSafeArea()
                    .onAppear { width = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, new in width = new }
            }
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(theme.text)
        .tint(theme.accent)
        .environment(\.perchTheme, theme)
        .transformEnvironment(\.colorScheme) { $0 = theme.colorScheme }
        // In a sheet this screen has a window of its own, which needs pinning light or dark like the main one.
        .themeColorScheme(store.preferredColorScheme, theme: theme, paintsWindow: false)
        .navigationTitle("Theme")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .motion(Motion.smooth, value: theme)
    }

    private func select(_ id: String) {
        notice = nil
        withMotion(Motion.smooth, reduceMotion: reduceMotion) { store.select(id) }
    }

    // MARK: Choosing a theme

    private func systemCard(_ theme: PerchTheme) -> some View {
        let selected = store.selectedID == ThemePresets.systemID
        let appearance = Picker("Appearance", selection: Binding(get: { store.appearance }, set: { value in
            withMotion(Motion.smooth, reduceMotion: reduceMotion) {
                store.select(ThemePresets.systemID)
                store.setAppearance(value)
            }
        })) {
            ForEach(ThemeAppearance.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 260)

        return VStack(alignment: .leading, spacing: 10) {
            ThemeSectionHeader("Theme", detail: "Pick a look. It applies straight away, on this device.")
            VStack(alignment: .leading, spacing: 12) {
                Button { select(ThemePresets.systemID) } label: {
                    HStack(spacing: 12) {
                        SystemThumbnail().frame(width: 112, height: 70)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text("System").font(.perchStyle(.headline))
                                if selected {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            Text("Perch's own colors, light by day and dark by night, following your device.")
                                .font(.perchStyle(.footnote))
                                .foregroundStyle(theme.textSecondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        if isWide { appearance }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("System theme, follows your device")
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                if !isWide { appearance }
            }
            .padding(Metrics.cardPadding)
            .background(RoundedRectangle(cornerRadius: Metrics.cardRadius + 2, style: .continuous).fill(theme.surface))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius + 2, style: .continuous)
                    .strokeBorder(selected ? theme.accent : theme.border, lineWidth: selected ? 2 : 1)
            )
        }
    }

    private func themeGrid(_ title: String, themes: [PerchTheme], current: PerchTheme, removable: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ThemeSectionHeader(title)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128, maximum: 220), spacing: Metrics.gap)], alignment: .leading, spacing: Metrics.gap) {
                ForEach(themes) { item in
                    ThemeCard(theme: item, selected: store.selectedID == item.id, chrome: current) { select(item.id) }
                        .contextMenu {
                            if removable {
                                Button("Remove", role: .destructive) { store.removeImported(id: item.id) }
                            }
                        }
                }
            }
        }
    }

    // MARK: Accent

    private func accentSection(_ theme: PerchTheme) -> some View {
        let base = store.baseTheme(for: scheme)
        let current = store.accentOverride.flatMap { ThemeRGB(hex: $0) }
        return VStack(alignment: .leading, spacing: 10) {
            ThemeSectionHeader("Accent", detail: "One accent color across every theme, or leave each theme its own.")
            FlowLayout(spacing: 10) {
                AccentSwatch(color: base.accent, label: "Theme's own accent", selected: current == nil, ring: theme, symbol: "paintpalette.fill", symbolColor: base.accentText) {
                    withMotion(Motion.quick, reduceMotion: reduceMotion) { store.setAccent(nil) }
                }
                ForEach(ThemePresets.accentChoices, id: \.name) { choice in
                    let hex = theme.isDark ? choice.dark : choice.light
                    // Selected whichever shade was saved, so the mark survives switching between light and dark.
                    let isCurrent = current != nil && (current == ThemeRGB(hex: choice.dark) || current == ThemeRGB(hex: choice.light))
                    AccentSwatch(color: Color(hex: hex) ?? .gray, label: choice.name, selected: isCurrent, ring: theme) {
                        withMotion(Motion.quick, reduceMotion: reduceMotion) { store.setAccent(hex) }
                    }
                }
                ColorPicker("Any accent color", selection: Binding(
                    get: { theme.accent },
                    set: { store.setAccent($0.hexString()) }
                ), supportsOpacity: false)
                .labelsHidden()
                .frame(minWidth: AccentSwatch.target, minHeight: AccentSwatch.target)
            }
        }
    }

    // MARK: Preview

    private func previewSection(_ theme: PerchTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ThemeSectionHeader("Preview")
            ThemePreview(theme: theme)
        }
    }

    // MARK: Customise

    private func customiseSection(_ theme: PerchTheme) -> some View {
        let customised = store.isCustomised(for: scheme)
        return VStack(alignment: .leading, spacing: 10) {
            ThemeSectionHeader("Customize", detail: "Change any color of \(theme.name). Your changes are kept with this theme.")
            ForEach(ThemeColorGroup.allCases, id: \.self) { group in
                VStack(alignment: .leading, spacing: 0) {
                    Text(group.label)
                        .font(.perchStyle(.subheadline).weight(.semibold))
                        .padding(.horizontal, Metrics.cardPadding)
                        .padding(.top, Metrics.cardPadding)
                        .padding(.bottom, 4)
                        .accessibilityAddTraits(.isHeader)
                    let keys = ThemeColorKey.allCases.filter { $0.group == group }
                    ForEach(keys, id: \.self) { key in
                        colorRow(key, theme: theme)
                        if key != keys.last { Rectangle().fill(theme.divider).frame(height: 1).padding(.leading, Metrics.cardPadding) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(theme.surface))
                .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
            }
            Button {
                withMotion(Motion.smooth, reduceMotion: reduceMotion) { store.resetCustomisation() }
                notice = Notice(text: "Back to \(store.baseTheme(for: scheme).name) as it came.")
            } label: {
                Label("Reset to preset", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(ThemeButtonStyle(theme: theme))
            .disabled(!customised)
            .opacity(customised ? 1 : 0.5)
            .padding(.top, 4)
        }
    }

    private func colorRow(_ key: ThemeColorKey, theme: PerchTheme) -> some View {
        let changed = store.isOverridden(key, for: scheme)
        let issues = theme.palette.contrastIssues(for: key).filter { $0.foreground == key }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(key.label).font(.perchStyle(.body))
                    Text(theme.hex(key) + (changed ? " · changed" : ""))
                        .font(.perchStyle(.caption).monospaced())
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 0)
                if changed {
                    Button {
                        withMotion(Motion.quick, reduceMotion: reduceMotion) { store.setColor(key, to: nil, for: scheme) }
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.perchStyle(.footnote).weight(.semibold))
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Put back \(key.label)")
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
                ColorPicker(key.label, selection: Binding(
                    get: { theme.color(key) },
                    set: { store.setColor(key, to: $0.hexString(), for: scheme) }
                ), supportsOpacity: false)
                .labelsHidden()
            }
            ForEach(issues, id: \.background) { issue in
                Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.perchStyle(.caption))
                    .foregroundStyle(theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Metrics.cardPadding)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }

    // MARK: Sharing

    private func shareSection(_ theme: PerchTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ThemeSectionHeader("Share", detail: "Copy this theme here and paste it into Perch on your other device.")
            FlowLayout(spacing: 10) {
                Button {
                    ThemeClipboard.write(store.exportJSON(for: scheme))
                    notice = Notice(text: "Copied \(theme.name).")
                } label: {
                    Label("Copy theme", systemImage: "doc.on.doc")
                }
                Button {
                    guard let text = ThemeClipboard.read(), !text.isEmpty else {
                        notice = Notice(text: "There's nothing on the clipboard to paste.", isProblem: true)
                        return
                    }
                    do {
                        var imported: PerchTheme?
                        try withAnimation(Motion.resolve(Motion.smooth, reduceMotion: reduceMotion)) { imported = try store.importJSON(text) }
                        notice = Notice(text: "Now using \(imported?.name ?? "the pasted theme").")
                    } catch {
                        notice = Notice(text: "That isn't a Perch theme. Copy one with Copy theme first.", isProblem: true)
                    }
                } label: {
                    Label("Paste theme", systemImage: "doc.on.clipboard")
                }
            }
            .buttonStyle(ThemeButtonStyle(theme: theme))
            if let notice {
                Label(notice.text, systemImage: notice.isProblem ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.perchStyle(.footnote))
                    .foregroundStyle(notice.isProblem ? theme.danger : theme.textSecondary)
                    .transition(.opacity)
            }
        }
        .motion(Motion.quick, value: notice)
    }
}

// MARK: - Pieces

private struct ThemeSectionHeader: View {
    @Environment(\.perchTheme) private var theme
    var title: String
    var detail: String?

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.perchStyle(.title3).weight(.semibold)).foregroundStyle(theme.text)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail).font(.perchStyle(.footnote)).foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A quiet bordered button drawn in the theme's own colours.
private struct ThemeButtonStyle: ButtonStyle {
    /// Read so this is drawn again when the interface size or density changes.
    @Environment(\.perchDisplay) private var display
    var theme: PerchTheme

    func makeBody(configuration: Configuration) -> some View {
        let _ = display
        configuration.label
            .font(.perchStyle(.subheadline).weight(.medium))
            .foregroundStyle(theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(configuration.isPressed ? theme.accentSoft : theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .lift(configuration.isPressed, scale: 0.97)
    }
}

private struct AccentSwatch: View {
    var color: Color
    var label: String
    var selected: Bool
    var ring: PerchTheme
    var symbol: String?
    var symbolColor: Color = .white
    var action: () -> Void
    @State private var hovering = false

    /// How big the thing you press is: a full 44 points under a finger, the swatch itself under a pointer.
    static var target: CGFloat {
        #if os(iOS)
        44
        #else
        34
        #endif
    }

    private var dot: CGFloat { Self.target - 10 }

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: dot, height: dot)
                .overlay {
                    if let symbol { Image(systemName: symbol).font(.system(size: dot * 0.42, weight: .semibold)).foregroundStyle(symbolColor) }
                }
                .padding(5)
                .overlay(Circle().strokeBorder(selected ? ring.text : .clear, lineWidth: 2))
                .frame(width: Self.target, height: Self.target)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .lift(hovering, scale: 1.1)
        .onHover { hovering = $0 }
        .motion(Motion.quick, value: selected)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// One theme in the grid: a miniature of the app in its colours, and its name.
private struct ThemeCard: View {
    /// Read so this is drawn again when the interface size or density changes.
    @Environment(\.perchDisplay) private var display
    var theme: PerchTheme
    var selected: Bool
    /// The theme the screen itself is drawn in.
    var chrome: PerchTheme
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        let _ = display
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                ThemeThumbnail(theme: theme).frame(height: 78)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(theme.name)
                        .font(.perchStyle(.footnote).weight(.medium))
                        .foregroundStyle(chrome.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.perchStyle(.footnote))
                            .foregroundStyle(chrome.accent)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 3)
            }
            .padding(6)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Metrics.cardRadius + 2, style: .continuous).fill(selected ? chrome.accentSoft : chrome.surface))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius + 2, style: .continuous)
                    .strokeBorder(selected ? chrome.accent : chrome.border, lineWidth: selected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius + 2, style: .continuous))
        }
        .buttonStyle(.plain)
        .lift(hovering, scale: 1.02)
        .onHover { hovering = $0 }
        .motion(Motion.quick, value: selected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(theme.name), \(theme.isDark ? "dark" : "light") theme")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A tiny drawing of Perch in a theme: sidebar, a note's heading and lines, a task and the accent.
struct ThemeThumbnail: View {
    var theme: PerchTheme

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.height / 13
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: unit) {
                    bar(theme.textMuted, width: 0.7, unit: unit)
                    RoundedRectangle(cornerRadius: unit * 0.7, style: .continuous)
                        .fill(theme.accentSoft)
                        .frame(height: unit * 2)
                        .overlay(alignment: .leading) { bar(theme.accent, width: 0.6, unit: unit).padding(.leading, unit * 0.6) }
                    bar(theme.textMuted, width: 0.85, unit: unit)
                    bar(theme.textMuted, width: 0.55, unit: unit)
                    Spacer(minLength: 0)
                }
                .padding(unit)
                .frame(width: proxy.size.width * 0.3)
                .background(theme.sidebar)
                Rectangle().fill(theme.border).frame(width: 1)
                VStack(alignment: .leading, spacing: unit) {
                    bar(theme.text, width: 0.5, unit: unit * 1.25)
                    bar(theme.textSecondary, width: 0.92, unit: unit)
                    bar(theme.textSecondary, width: 0.7, unit: unit)
                    HStack(spacing: unit) {
                        Circle().strokeBorder(theme.accent, lineWidth: max(1, unit * 0.3)).frame(width: unit * 1.8, height: unit * 1.8)
                        bar(theme.text, width: 0.5, unit: unit)
                        Spacer(minLength: 0)
                        Capsule().fill(theme.danger).frame(width: unit * 2.4, height: unit)
                    }
                    .padding(unit * 0.7)
                    .background(RoundedRectangle(cornerRadius: unit * 0.8, style: .continuous).fill(theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: unit * 0.8, style: .continuous).strokeBorder(theme.border, lineWidth: 0.5))
                    Spacer(minLength: 0)
                }
                .padding(unit)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.background)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(theme.isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 1))
    }

    private func bar(_ color: Color, width: CGFloat, unit: CGFloat) -> some View {
        GeometryReader { proxy in
            Capsule().fill(color).frame(width: proxy.size.width * width)
        }
        .frame(height: unit)
    }
}

/// Half light, half dark: the System choice.
private struct SystemThumbnail: View {
    var body: some View {
        ZStack {
            ThemeThumbnail(theme: .light)
            ThemeThumbnail(theme: .dark).mask(DiagonalHalf())
        }
    }

    private struct DiagonalHalf: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.maxX * 0.62, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX * 0.38, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}

// MARK: - Live preview

/// A realistic sample drawn entirely in a theme: tasks with chips, a note excerpt and a few calendar days.
public struct ThemePreview: View {
    /// Read so this is drawn again when the interface size or density changes.
    @Environment(\.perchDisplay) private var display
    var theme: PerchTheme

    public init(theme: PerchTheme) {
        self.theme = theme
    }

    public var body: some View {
        let _ = display
        VStack(alignment: .leading, spacing: 14) {
            tasks
            note
            calendar
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Metrics.cardRadius + 2, style: .continuous).fill(theme.background))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius + 2, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of \(theme.name): sample tasks, a note and a calendar")
    }

    private var tasks: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 9) {
                Circle().strokeBorder(theme.danger, lineWidth: 1.6).frame(width: 17, height: 17).padding(.top, 1)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Renew passport").font(.perchBody.weight(.medium)).foregroundStyle(theme.text)
                    FlowLayout(spacing: 5) {
                        Chip(text: "2 days overdue", symbol: "calendar", tint: theme.danger)
                        Chip(text: "Personal", symbol: "folder", tint: theme.info)
                        Chip(text: "Waiting", symbol: "hourglass", tint: theme.warning)
                    }
                }
            }
            .padding(Metrics.cardPadding - 2)
            Rectangle().fill(theme.divider).frame(height: 1)
            HStack(spacing: 9) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 17)).foregroundStyle(theme.success)
                Text("Water the plants").font(.perchBody).strikethrough().foregroundStyle(theme.textMuted)
                Spacer(minLength: 0)
                Chip(text: "Today", symbol: nil, tint: theme.success)
            }
            .padding(Metrics.cardPadding - 2)
        }
        .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
    }

    private var note: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Weekend plan").font(.system(size: 17, weight: .bold)).foregroundStyle(theme.text)
            (Text("Pick up the keys, then read the ").foregroundStyle(theme.text)
                + Text("trip checklist").foregroundStyle(theme.accent).underline()
                + Text(" before leaving.").foregroundStyle(theme.text))
                .font(.perchBody)
                .fixedSize(horizontal: false, vertical: true)
            Text("perch sync --now")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.text)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.codeBackground))
            Text("Edited five minutes ago").font(.perchCaption).foregroundStyle(theme.textSecondary)
        }
    }

    private var calendar: some View {
        HStack(spacing: 6) {
            day("Sat", "7", muted: true)
            day("Sun", "8", marker: theme.danger)
            day("Mon", "9", today: true, marker: theme.accent)
            day("Tue", "10", marker: theme.info)
            day("Wed", "11")
        }
    }

    private func day(_ weekday: String, _ number: String, today: Bool = false, muted: Bool = false, marker: Color? = nil) -> some View {
        VStack(spacing: 4) {
            Text(weekday.uppercased()).font(.perchEyebrow).foregroundStyle(today ? theme.accent : theme.textMuted)
            Text(number)
                .font(.system(size: 13, weight: today ? .bold : .regular))
                .foregroundStyle(today ? theme.accentText : muted ? theme.textMuted : theme.text)
                .frame(width: 24, height: 24)
                .background(Circle().fill(today ? theme.accent : .clear))
            Circle().fill(marker ?? .clear).frame(width: 5, height: 5)
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(today ? theme.accent.opacity(0.6) : theme.border, lineWidth: 1))
    }
}

// MARK: - Clipboard

@MainActor
private enum ThemeClipboard {
    static func write(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    static func read() -> String? {
        #if canImport(UIKit)
        return UIPasteboard.general.string
        #elseif canImport(AppKit)
        return NSPasteboard.general.string(forType: .string)
        #else
        return nil
        #endif
    }
}
