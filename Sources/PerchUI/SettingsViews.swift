import PerchKit
import SwiftUI

// The Display, Reading and Editing settings screens, shared by the Mac and the iPhone. Each one is a
// whole screen: a live preview at the top, its choices in groups, and Reset at the bottom.
//
//     NavigationLink("Reading") { ReadingSettingsView() }      // iPhone: push it
//     case .reading: ReadingSettingsView()                     // Mac: one pane of the Settings window

/// The groups in Settings. The Mac shows them all in its sidebar; the iPhone pushes the first four.
public enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
    case appearance, display, reading, editing, notebook, agents, notch, sync, updates
    /// Tabs: things being tried out. Today that is tabs and split view.
    case experimental

    public var id: String { rawValue }
    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    public var symbol: String {
        switch self {
        case .appearance: return "paintpalette"
        case .display: return "textformat.size"
        case .reading: return "book"
        case .editing: return "square.and.pencil"
        case .notebook: return "folder"
        case .agents: return "person.2"
        case .notch: return "macbook"
        case .sync: return "arrow.triangle.2.circlepath"
        case .updates: return "arrow.down.circle"
        case .experimental: return "flask"
        }
    }
}

/// Which pane the Mac's Settings shows, so "More settings…" in a note can open the right one.
/// Not saved: Settings opens on Appearance each launch.
@MainActor
public final class SettingsRouter: ObservableObject {
    public static let shared = SettingsRouter()
    @Published public var pane = SettingsPane.appearance
    public init() {}
}

// MARK: - Shared pieces

private struct SettingsRow: ViewModifier {
    @Environment(\.perchTheme) private var theme

    func body(content: Content) -> some View {
        #if os(iOS)
        content.listRowBackground(theme.surface)
        #else
        content
        #endif
    }
}

private extension View {
    /// The theme's surface behind a settings row or group on iPhone; the Mac's grouped form draws its own.
    func settingsRows() -> some View { modifier(SettingsRow()) }
}

/// The frame every settings screen shares: a grouped form on the theme's background.
private struct SettingsForm<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    @Environment(\.perchTheme) private var theme

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .perchScreenBackground()
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #else
            // The Mac doesn't scale a form's own labels, so they are given the interface size here.
            .environment(\.font, theme.display.metrics.size == .standard ? nil : Font.perchStyle(.body))
            #endif
    }
}

/// A preview at the top of a settings screen, edge to edge in its row. On the Mac it is a card on the
/// note background. On iPhone the list's own row is the card, with the same surface as the rows below:
/// a card drawn inside the row would have its corners cut off by the row's rounder ones.
private struct PreviewCard<Content: View>: View {
    var label: String
    @ViewBuilder var content: Content
    @Environment(\.perchTheme) private var theme

    var body: some View {
        Section {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                #if os(iOS)
                .listRowInsets(EdgeInsets())
                .listRowBackground(theme.surface)
                #else
                .background(theme.background)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                #endif
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
        } header: {
            Text("Preview")
        }
    }
}

private struct ResetSection: View {
    var title: String
    var isDefault: Bool
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Section {
            Button(title, role: .destructive) { withMotion(reduceMotion: reduceMotion, action) }
                .disabled(isDefault)
        } footer: {
            Text(isDefault ? "Everything here is at its default." : "Only these settings change. Your notes are never touched.")
        }
        .settingsRows()
    }
}

/// A picker over an enum's cases, shown the way that suits its length.
private struct ChoicePicker<Value: Hashable & CaseIterable & Identifiable>: View where Value.AllCases: RandomAccessCollection {
    var label: String
    @Binding var selection: Value
    var segmented = false
    var title: (Value) -> String

    var body: some View {
        let picker = Picker(label, selection: $selection) {
            ForEach(Value.allCases) { Text(title($0)).tag($0) }
        }
        if segmented {
            // The label stays for VoiceOver and, on the Mac, beside the control.
            #if os(iOS)
            VStack(alignment: .leading, spacing: 8) {
                Text(label)
                picker.pickerStyle(.segmented).labelsHidden()
            }
            .accessibilityElement(children: .contain)
            #else
            picker.pickerStyle(.segmented)
            #endif
        } else {
            picker
        }
    }
}

// MARK: - Display

/// Interface size, density, and what task rows show.
public struct DisplaySettingsView: View {
    private var display = DisplaySettings()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        SettingsForm(title: "Display") {
            PreviewCard(label: "A sample header and two task rows at the chosen size and density") { DisplayPreview() }

            Section {
                ChoicePicker(label: "Interface size", selection: display.$interfaceSize) { $0.title }
                #if os(iOS)
                Toggle("Match iPhone text size", isOn: display.$matchSystemTextSize)
                #endif
                ChoicePicker(label: "Density", selection: display.$density, segmented: true) { $0.title }
            } header: {
                Text("Size")
            } footer: {
                #if os(iOS)
                Text(display.matchSystemTextSize
                    ? "Perch starts from the text size in the iPhone's Settings, and Interface size moves it up or down from there. Density changes how much space rows get."
                    : "Perch ignores the iPhone's text size and uses Interface size alone. Density changes how much space rows get.")
                #else
                Text("Interface size scales Perch's own text, icons and spacing; press ⌃⌘+ or ⌃⌘− to change it from anywhere. Density changes how much space rows get in lists, the calendar and folders.")
                #endif
            }
            .settingsRows()

            Section {
                Toggle("Show preview line", isOn: display.$taskPreview)
                Toggle("Show labels and chips", isOn: display.$taskChips)
            } header: {
                Text("Task rows")
            } footer: {
                Text("Turn these off to fit more tasks on a small screen. Dates, areas and labels still show when you open a task.")
            }
            .settingsRows()

            #if os(iOS)
            Section {
                Toggle("Use wide layouts on large screens", isOn: display.$wideLayouts)
            } header: {
                Text("Large screens")
            } footer: {
                Text("On a screen 640 points wide or more, the calendar shows a day beside the month and folders open as a grid. Turn this off to keep the phone layouts.")
            }
            .settingsRows()
            #endif

            ResetSection(title: "Reset Display to Defaults", isDefault: display.isDefault, action: display.reset)
        }
        .motion(Motion.smooth, value: display.state)
    }
}

/// A header and two task rows, drawn with the same pieces the real screens use.
struct DisplayPreview: View {
    @Environment(\.perchTheme) private var theme

    var body: some View {
        let display = theme.display
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Today").font(.perchTitle).foregroundStyle(theme.text)
                Text("3 open").font(.perchBody).foregroundStyle(theme.textSecondary)
                Label("1 overdue", systemImage: "exclamationmark.circle").labelStyle(CompactLabel())
                    .font(.perchBody.weight(.medium)).foregroundStyle(theme.danger)
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .padding(.bottom, Metrics.tightGap)
            row(
                "Renew passport", preview: "Photos are in the blue folder on the shelf", priority: 1,
                chips: [("Yesterday", "calendar", theme.danger), ("Personal", nil, Palette.area("Personal", theme: theme)), ("#errands", nil, Palette.label("errands", theme: theme))],
                display: display
            )
            row(
                "Book the ferry for Saturday", preview: nil, priority: 3,
                chips: [("Today", "calendar", theme.success), ("Trips", nil, Palette.area("Trips", theme: theme))],
                display: display
            )
        }
        .padding(Metrics.cardPadding)
    }

    private func row(_ title: String, preview: String?, priority: Int, chips: [(String, String?, Color)], display: PerchDisplay) -> some View {
        HStack(alignment: .top, spacing: 10) {
            CheckCircle(color: Palette.priority(priority, theme: theme), isDone: false) {}
                .padding(.top, 1)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.perchRow).foregroundStyle(theme.text).lineLimit(2)
                if display.showsTaskPreview, let preview {
                    Text(preview).font(.perchCaption).foregroundStyle(theme.textSecondary).lineLimit(1)
                }
                if display.showsTaskChips {
                    FlowLayout(spacing: 6) {
                        ForEach(chips, id: \.0) { chip in Chip(text: chip.0, symbol: chip.1, tint: chip.2) }
                    }
                    .padding(.top, 3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Metrics.rowPadding)
        .padding(.horizontal, 8)
    }
}

// MARK: - Reading

/// How notes look in the reader.
public struct ReadingSettingsView: View {
    private var reading = ReadingSettings()
    /// The preview's web page. Kept by the screen, so it is loaded once: not again when a setting changes
    /// or when the preview scrolls out of the list and back.
    @StateObject private var previewHost = WebHost.reader { nil }

    public init() {}

    public var body: some View {
        SettingsForm(title: "Reading") {
            PreviewCard(label: "A sample note drawn with these reading settings") { ReadingPreview(host: previewHost) }

            Section("Text") {
                ChoicePicker(label: "Font", selection: reading.$font) { $0.title }
                LabeledContent("Text size") {
                    TextSizeStepper(
                        size: reading.readingPointSize, step: reading.textSize, range: ReadingSettings.textSizeRange,
                        change: reading.stepTextSize, reset: { reading.textSize = 0 }
                    )
                }
                ChoicePicker(label: "Heading font", selection: reading.$headingFont) { $0.title }
                ChoicePicker(label: "Line spacing", selection: reading.$lineSpacing) { $0.title }
                ChoicePicker(label: "Paragraph spacing", selection: reading.$paragraphSpacing) { $0.title }
                ChoicePicker(label: "Line width", selection: reading.$lineWidth) { $0.title }
            }
            .settingsRows()

            Section {
                Toggle("Justify text", isOn: reading.$justify)
                Toggle("Hyphenate long words", isOn: Binding(get: { reading.style.hyphenates }, set: { reading.hyphenate = $0 }))
                    .disabled(reading.justify)
                Toggle("Underline links", isOn: reading.$underlineLinks)
            } footer: {
                Text(reading.justify ? "Justified text is always hyphenated, so its lines don't spread out." : "Links to other notes keep their soft highlight either way.")
            }
            .settingsRows()

            Section("Code blocks") {
                ChoicePicker(label: "Long lines", selection: reading.$codeWrap) { $0.title }
                ChoicePicker(label: "Code text size", selection: reading.$codeTextSize) { $0.title }
            }
            .settingsRows()

            Section {
                ChoicePicker(label: "Properties", selection: reading.$properties) { $0.title }
                ChoicePicker(label: "Images", selection: reading.$imageWidth) { $0.title }
                Toggle("Show contents alongside wide notes", isOn: reading.$showOutline)
            } header: {
                Text("Notes")
            } footer: {
                Text("Properties are the lines between --- at the top of a note. Automatic opens them when there are four or fewer. Full width lets a picture on its own line run past the text column.")
            }
            .settingsRows()

            ResetSection(title: "Reset Reading to Defaults", isDefault: reading.isDefault, action: reading.reset)
        }
    }
}

/// A few lines of real Markdown in the real reader, restyled as the settings change.
struct ReadingPreview: View {
    /// A page of its own with no notebook behind it: it can only show the sample below.
    @ObservedObject var host: WebHost
    private var reading = ReadingSettings()
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didRender = false
    /// True once the page says the sample is on screen. Until then a few grey lines hold its place.
    @State private var isDrawn = false

    static let sample = """
    ---
    status: draft
    tags: [trips, autumn]
    ---
    ## Weekend plan

    Take the coast road. The [ferry timetable](https://example.com) changes in October, so check the sailing times the night before.

    Pack the tent and both lamps.

    ```swift
    let stops = ["Harbor", "Lighthouse", "Old quarry", "Ridge camp"].joined(separator: " to ")
    ```
    """

    private var appearance: [String: Any] {
        #if os(iOS)
        // The list row behind the preview is the card, so the page stays see-through.
        var theme = theme.webAppearance(paintsBackground: false)
        #else
        var theme = theme.webAppearance()
        #endif
        // Less margin than a real note, so more of the sample fits in the card.
        var variables = theme["variables"] as? [String: String] ?? [:]
        variables["--perch-pad-top"] = "14px"
        variables["--perch-pad-inline"] = "16px"
        theme["variables"] = variables
        return reading.appearance.payload.merging(theme) { _, new in new }
    }

    var body: some View {
        WebHostView(host: host)
            .opacity(isDrawn ? 1 : 0)
            .frame(height: 330)
            .overlay(alignment: .topLeading) { if !isDrawn { placeholder.transition(.opacity) } }
            // A picture of the reader, not a place to read: scrolling stays with the settings.
            .allowsHitTesting(false)
            .onAppear {
                // The page may already be drawn: the screen keeps it while this row is off screen.
                host.onMessage = { message in
                    guard message["type"] as? String == "rendered", !isDrawn else { return }
                    withMotion(Motion.quick, reduceMotion: reduceMotion) { isDrawn = true }
                }
                guard !didRender else { return }
                didRender = true
                render()
            }
            // The page keeps the closure above and the closure keeps this view, which keeps the page.
            .onDisappear { host.onMessage = nil }
            .onChange(of: reading.appearance) { host.call("setAppearance", arguments: appearance) }
            // The page recolours itself for a new theme; nothing is rendered again.
            .onChange(of: theme) { host.call("setAppearance", arguments: appearance) }
    }

    private func render() {
        host.call("render", arguments: ["markdown": Self.sample, "basePath": "", "appearance": appearance])
    }

    /// Grey lines where the sample will be, while the page loads. On a slow device that takes a moment,
    /// and an empty card looks broken.
    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 4).fill(theme.wash).frame(width: 150, height: 18)
            ForEach([1.0, 0.92, 0.6, 0.8, 0.45], id: \.self) { share in
                RoundedRectangle(cornerRadius: 3).fill(theme.wash).frame(height: 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .scaleEffect(x: share, anchor: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .accessibilityHidden(true)
    }
}

// MARK: - Editing

/// How the editor looks, and what it does as you type.
public struct EditingSettingsView: View {
    private var editing = EditingSettings()

    public init() {}

    public var body: some View {
        SettingsForm(title: "Editing") {
            PreviewCard(label: "A sample of Markdown in the editor with these settings. You can type in it.") { EditingPreview() }

            Section("Text") {
                ChoicePicker(label: "Editor font", selection: editing.$font) { $0.title }
                LabeledContent("Editor text size") {
                    TextSizeStepper(
                        size: editing.pointSize, step: editing.textSize, range: ReadingSettings.editorTextSizeRange,
                        change: editing.stepTextSize, reset: { editing.textSize = 0 }
                    )
                }
                ChoicePicker(label: "Line spacing", selection: editing.$lineSpacing) { $0.title }
                ChoicePicker(label: "Line width", selection: editing.$lineWidth) { $0.title }
                ChoicePicker(label: "Markdown marks", selection: editing.$marks) { $0.title }
                Toggle("Highlight current line", isOn: editing.$highlightLine)
            }
            .settingsRows()

            Section {
                #if os(macOS)
                Toggle("Show format bar above the editor", isOn: editing.$formattingBar)
                #endif
                Toggle("Hide formatting tags while editing", isOn: editing.$hideTags)
                LabeledContent("Recent colors") {
                    HStack(spacing: 5) {
                        let colors = FormatRecents.list(editing.recentColors)
                        if colors.isEmpty { Text("None yet").foregroundStyle(.secondary) }
                        ForEach(colors, id: \.self) { hex in
                            Circle().fill(Color(hex: hex) ?? .gray).frame(width: 14, height: 14)
                                .accessibilityLabel(FormatPalette.name(for: hex))
                        }
                        Button("Clear") { editing.recentColors = "" }.disabled(colors.isEmpty)
                    }
                }
            } header: {
                Text("Formatting")
            } footer: {
                Text("Color, highlight, underline and size are saved in the note as small HTML tags that other Markdown apps also read. Hidden tags reappear on the line you are editing.")
            }
            .settingsRows()

            Section("Opening notes") {
                ChoicePicker(label: "Open notes in", selection: editing.$openIn) { $0.title }
                Toggle("Show preview while editing", isOn: editing.$editWithPreview)
                ChoicePicker(label: "Preview side", selection: editing.$previewSide) { $0.title }
                    .disabled(!editing.editWithPreview)
                Toggle("Keep preview scrolled with the editor", isOn: editing.$syncPreviewScroll)
                    .disabled(!editing.editWithPreview)
            }
            .settingsRows()

            Section {
                Toggle("Continue lists and quotes on Return", isOn: editing.$continueLists)
                Toggle("Indent lists with Tab", isOn: editing.$tabIndents)
                Toggle("Wrap selection with * _ ` [ ( ~ \"", isOn: editing.$wrapSelection)
                    .accessibilityLabel("Wrap the selection when you type an asterisk, underscore, backtick, bracket, parenthesis, tilde or quote")
                ChoicePicker(label: "List indent", selection: editing.$indent) { $0.title }
            } header: {
                Text("Typing helpers")
            } footer: {
                Text("List indent is what one level adds to the note's text: it changes new indents, not lines already written.")
            }
            .settingsRows()

            Section {
                Toggle("Check spelling", isOn: editing.$spellCheck)
                Toggle("Autocorrect", isOn: editing.$autocorrect)
                Toggle("Smart quotes and dashes", isOn: editing.$smartPunctuation)
                #if os(iOS)
                Toggle("Capitalize sentences", isOn: editing.$autocapitalize)
                #endif
            } header: {
                Text("Text checking")
            } footer: {
                #if os(iOS)
                Text("Autocorrect follows the iPhone's keyboard settings when it is on. Smart quotes and dashes start off because curly quotes and long dashes break Markdown and code.")
                #else
                Text("Autocorrect follows the Mac's keyboard settings when it is on. Smart quotes and dashes start off because curly quotes and long dashes break Markdown and code.")
                #endif
            }
            .settingsRows()

            #if os(iOS)
            Section("Keyboard") {
                Toggle("Show formatting bar above the keyboard", isOn: editing.$formattingBar)
            }
            .settingsRows()
            #endif

            ResetSection(title: "Reset Editing to Defaults", isDefault: editing.isDefault, action: editing.reset)
        }
    }
}

/// The real editor on a few lines of sample text. It is live, so the typing helpers can be tried in place;
/// what is typed here goes nowhere.
struct EditingPreview: View {
    @State private var text = EditingPreview.sample
    @StateObject private var actions = EditorActions()

    static let sample = """
    ## Packing list

    Take the **coast road** to the [harbor](https://example.com) for the <span style="color: #3B82D9">early</span> ferry.

    - [x] Tent and both lamps
    - [ ] Water carrier
    > Check the tide tables.
    """

    var body: some View {
        MarkdownEditor(text: $text, actions: actions, roomy: true)
            .frame(height: 260)
    }
}

// MARK: - Inside a note

/// "More settings…" at the foot of the note's Aa panel. On the Mac it opens the Settings window at the
/// right pane; on iPhone it opens the full screen over the note.
struct MoreSettingsLink: View {
    var pane: SettingsPane
    @Environment(\.perchTheme) private var theme
    @State private var showing = false
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    #endif

    var body: some View {
        Button {
            #if os(macOS)
            SettingsRouter.shared.pane = pane
            dismiss()
            openSettings()
            #else
            showing = true
            #endif
        } label: {
            HStack {
                Text("More settings…")
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").imageScale(.small).accessibilityHidden(true)
            }
            .font(.perchStyle(.callout))
            .foregroundStyle(theme.accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(pane == .editing ? "Opens every editing setting" : "Opens every reading setting")
        #if os(iOS)
        .sheet(isPresented: $showing) {
            NavigationStack {
                Group {
                    if pane == .editing { EditingSettingsView() } else { ReadingSettingsView() }
                }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showing = false } } }
            }
            .presentationBackground(theme.background)
        }
        #endif
    }
}
