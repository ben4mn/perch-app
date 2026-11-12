import AVFoundation
import CryptoKit
import PerchKit
import SwiftUI
import UniformTypeIdentifiers

/// How a note is showing: just the reader, just the editor, or both side by side.
public enum NoteMode: String, CaseIterable, Identifiable, Sendable {
    case read, edit, split
    public var id: String { rawValue }
}

/// Scroll positions shared between the reader and the editor. Not published: scrolling must not redraw the view.
@MainActor
final class NoteScrollState {
    var readerLine: Double = 0
    var syncsPreview = false
}

/// What each open note was doing, so a note that is drawn again a moment later carries on from there.
///
/// When the layout changes under a note (a folding phone is opened or closed, so the note moves from
/// a pushed screen to a pane or back) its view is built afresh. Without this it would come back in the
/// reader at the top; with it, a note being edited is still being edited, at about the same line.
/// Nothing is remembered for longer than a moment: opening the same note later starts as usual.
struct NoteResume {
    struct Place: Equatable {
        var editing = false
        var line: Double = 0
    }

    private struct Entry {
        var place = Place()
        /// How many views of this note are on screen.
        var showing = 0
        var left = Date.distantPast
    }

    /// How long after a note's view goes away another view of it still counts as the same visit.
    static let window: TimeInterval = 2

    private var entries: [String: Entry] = [:]

    /// A view of the note has appeared. Returns where to carry on from, when the note is on screen
    /// already or left it within the last moment.
    mutating func appear(_ path: String, now: Date = Date()) -> Place? {
        var entry = entries[path] ?? Entry()
        let resumes = entry.showing > 0 || now.timeIntervalSince(entry.left) <= Self.window
        let place = resumes ? entry.place : nil
        if !resumes { entry.place = Place() }
        entry.showing += 1
        entries[path] = entry
        return place
    }

    mutating func update(_ path: String, editing: Bool? = nil, line: Double? = nil) {
        guard entries[path] != nil else { return }
        if let editing { entries[path]?.place.editing = editing }
        if let line { entries[path]?.place.line = line }
    }

    /// The note was renamed: the view built for its new path carries on where the old one was.
    mutating func renamed(from old: String, to new: String) {
        guard let entry = entries.removeValue(forKey: old) else { return }
        entries[new] = entry
    }

    mutating func disappear(_ path: String, now: Date = Date()) {
        guard var entry = entries[path] else { return }
        entry.showing = max(entry.showing - 1, 0)
        entry.left = now
        entries[path] = entry
        // Old visits are dropped, so this never grows past the notes opened in the last moment.
        entries = entries.filter { $0.value.showing > 0 || now.timeIntervalSince($0.value.left) <= Self.window }
    }

    @MainActor static var shared = NoteResume()
}

/// Keeps one note's text, saving quietly and never overwriting changes from elsewhere.
@MainActor
final class NoteSession: ObservableObject {
    @Published var text: String {
        // Compared exactly, not with ==: see TextIdentity.
        didSet {
            if !TextIdentity.same(text, oldValue) { scheduleSave() }
            NoteDirt.shared.mark(path, unsaved: isReadable && !isDiscarded && !TextIdentity.same(text, lastDiskText))
        }
    }
    let path: String
    /// False when the file is there but isn't UTF-8 text. It is shown empty and never written, so opening
    /// it can't replace whatever it really holds.
    let isReadable: Bool
    private let model: AppModel
    private var lastDiskText: String
    private var saveTask: Task<Void, Never>?
    private var isDiscarded = false
    /// Text taken over from another view of this note that had not saved it. That view writes it as it
    /// goes; finding it on disk later is this note's own typing, not a change from elsewhere.
    private var inherited: String?

    init(path: String, model: AppModel) {
        self.path = path
        self.model = model
        let initial: String
        if let disk = try? model.vault?.read(path) {
            initial = disk
            isReadable = true
        } else if model.vault?.exists(path) == true {
            initial = ""
            isReadable = false
        } else {
            initial = model.text(of: path)
            isReadable = true
        }
        // Another view of this note is still on screen with typing it hasn't written yet: the layout
        // changed under it (a folding phone was opened or closed) and this view is taking over before
        // the old one has gone. Carry its text on, so nothing typed in the last half second is lost
        // and the next save here doesn't mistake the old view's save for someone else's change.
        if isReadable, let unsaved = Self.unsavedText(of: path, onDisk: initial) {
            text = unsaved
            lastDiskText = initial
            inherited = unsaved
        } else {
            text = initial
            lastDiskText = initial
        }
        Self.live[path, default: []].removeAll { $0.session == nil }
        Self.live[path, default: []].append(Live(session: self))
    }

    private struct Live {
        weak var session: NoteSession?
    }

    /// The sessions that exist, by path. A note has one, except for the moment a new arrangement's
    /// view of it has been built and the old arrangement's has not yet been taken down.
    private static var live: [String: [Live]] = [:]

    /// What the newest other session for this note holds, when that differs from the file.
    private static func unsavedText(of path: String, onDisk disk: String) -> String? {
        live[path]?.reversed().lazy.compactMap(\.session)
            .first { !$0.isDiscarded && $0.isReadable && $0.text != $0.lastDiskText && $0.text != disk }?.text
    }

    deinit {
        let path = path
        Task { @MainActor in
            NoteSession.live[path]?.removeAll { $0.session == nil }
            if NoteSession.live[path]?.isEmpty == true {
                NoteSession.live[path] = nil
                NoteDirt.shared.mark(path, unsaved: false)
            }
        }
    }

    /// Tabs: with tabs and split view on, two panes can show one note for as long as they like, so
    /// they share its session: typing in one is in the other at once, and there is one save, never
    /// two that could take each other for a change from elsewhere. With tabs off every view makes
    /// its own session, as before.
    static func forView(path: String, model: AppModel) -> NoteSession {
        if WorkspaceStore.isEnabled,
           let shared = live[path]?.reversed().lazy.compactMap(\.session).first(where: { !$0.isDiscarded && $0.model === model }) {
            return shared
        }
        return NoteSession(path: path, model: model)
    }

    /// Before a note's file is moved: anything typed and not yet written goes into it, so it moves too.
    static func saveAll(at path: String) {
        live[path]?.compactMap(\.session).forEach { $0.saveNow() }
    }

    /// After the move: the sessions still holding the old path stop saving, so a late save can't make
    /// the old file again. The note's view is built afresh for the new path.
    static func retire(at path: String) {
        live[path]?.compactMap(\.session).forEach { $0.discard() }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        guard isReadable, !isDiscarded, text != lastDiskText else { return }
        let disk = (try? model.vault?.read(path)) ?? lastDiskText
        if disk != lastDiskText, disk != text, disk != inherited {
            // Something else changed the file while this note was being edited: keep both.
            text = ConflictBlocks.wrap(remote: disk, local: text)
        }
        model.save(text, to: path)
        // Only count it as saved once it is really on disk; a save that failed is tried again next time.
        if (try? model.vault?.read(path)) == text {
            lastDiskText = text
            inherited = nil
            NoteDirt.shared.mark(path, unsaved: false)
        }
    }

    /// Drops anything unsaved, for a note that is being deleted: a late save must not bring it back.
    func discard() {
        saveTask?.cancel()
        isDiscarded = true
        NoteDirt.shared.mark(path, unsaved: false)
    }

    /// Takes in outside changes, such as a sync or an agent, when there's nothing unsaved here.
    func refreshFromDisk() {
        guard isReadable, !isDiscarded, text == lastDiskText, let disk = try? model.vault?.read(path), disk != lastDiskText else { return }
        lastDiskText = disk
        text = disk
    }
}

/// The note's name in the title bar. While the note is being edited it is a text field: click it, type,
/// and Return (or clicking away) renames the note. Esc puts the old name back. Nothing is renamed while
/// typing, and a stray click outside editing can't rename anything.
private struct NoteTitle: ViewModifier {
    let title: String
    let isEditable: Bool
    let rename: (String) -> Void

    func body(content: Content) -> some View {
        if isEditable {
            content
                #if os(macOS)
                // The field stands in for the title, so the window's own title is left empty meanwhile.
                .navigationTitle("")
                .toolbar { ToolbarItem(placement: .navigation) { NoteTitleField(title: title, rename: rename) } }
                #else
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .principal) { NoteTitleField(title: title, rename: rename) } }
                #endif
        } else {
            content
                .navigationTitle(title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }
    }
}

private struct NoteTitleField: View {
    let title: String
    let rename: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool
    @Environment(\.perchTheme) private var theme

    var body: some View {
        TextField("Title", text: $draft)
            .textFieldStyle(.plain)
            .font(.headline)
            .foregroundStyle(theme.text)
            .frame(minWidth: 120, idealWidth: 260, maxWidth: 420)
            .fixedSize(horizontal: false, vertical: true)
            .focused($focused)
            .onAppear { draft = title }
            .onChange(of: title) { _, new in if !focused { draft = new } }
            .onSubmit { commit(); focused = false }
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            #if os(macOS)
            .onExitCommand { draft = title; focused = false }
            #endif
            .help("Click to rename this note")
            .accessibilityLabel("Note title")
    }

    private func commit() {
        let clean = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != title else { draft = title; return }
        rename(clean)
    }
}

struct NoteView: View {
    @ObservedObject var model: AppModel
    let path: String
    @StateObject private var session: NoteSession
    @StateObject private var host: WebHost
    @StateObject private var actions = EditorActions()
    @StateObject private var recorder = AudioNoteRecorder()
    private var reading = ReadingSettings()
    @AppStorage(EditingSettings.Key.syncPreviewScroll) private var syncPreviewScroll = true
    @AppStorage(ReadingSettings.Key.showOutline) private var showOutline = false
    @AppStorage(ReadingSettings.Key.splitFraction) private var splitFraction = 0.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.perchTheme) private var theme
    /// Tabs: false in a Mac workspace pane that isn't the focused one, whose buttons would otherwise
    /// sit in the window's one toolbar beside the focused pane's.
    @Environment(\.perchPaneOwnsToolbar) private var ownsToolbar

    /// Notes open in the reader. Editing is a step the person takes.
    @State private var isEditing = false
    /// While editing: the preview sits beside the editor when there's room.
    @State private var wantsPreview = true
    /// While editing on a narrow screen: the preview is temporarily shown in place of the editor.
    @State private var peeking = false
    /// The editor is only built the first time it's needed.
    @State private var editorLoaded = false
    @State private var didSetUp = false
    @State private var paneWidth: CGFloat = 0
    @State private var scroll = NoteScrollState()
    @State private var needsRender = false
    @State private var dragFraction: Double?

    @State private var completion: EditorCompletion?
    @State private var completionAnchor: CGRect?
    @State private var toc: [TOCItem] = []
    @State private var renderTask: Task<Void, Never>?
    /// Keeps the reader drawing while someone types: see RenderPacer.
    @State private var pacer = RenderPacer()
    @State private var renderSentAt: Date?
    @State private var mentionLookup = MentionLookup()
    @State private var showOutlineSheet = false
    @State private var showReadingSettings = false
    @State private var findText = ""
    @State private var showFind = false
    @State private var replaceText = ""
    @State private var shareFile: URL?

    struct TOCItem: Identifiable, Hashable {
        var id: Int { line }
        var level: Int
        var text: String
        var line: Int
    }

    /// Which panes are on screen.
    enum Arrangement: Equatable { case reader, editor, split }

    private static let splitMinimum: CGFloat = 700
    private static let outlineMinimum: CGFloat = 900
    private static let outlineWidth: CGFloat = 264

    /// Posted when the app quits (Mac) or leaves the screen (iPhone): the last moment to save typing.
    private static var appIsLeaving: Notification.Name {
        #if os(macOS)
        NSApplication.willTerminateNotification
        #else
        UIApplication.willResignActiveNotification
        #endif
    }

    init(model: AppModel, path: String) {
        self.model = model
        self.path = path
        _session = StateObject(wrappedValue: NoteSession.forView(path: path, model: model))
        // A page that is already loaded, when one is waiting: opening a note doesn't start a web view.
        _host = StateObject(wrappedValue: WebHost.reader { [weak model] in
            MainActor.assumeIsolated { model?.vault?.root }
        })
    }

    private var file: VaultFile { VaultFile(path: path) }
    private var isBlank: Bool { session.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// How the reader should look: the reading settings, in the theme's colours.
    private var readerAppearance: [String: Any] {
        NotePanes.readerAppearance(
            reading.appearance.payload.merging(theme.webAppearance()) { _, new in new },
            previewTop: arrangement == .split ? actions.textTop : nil
        )
    }

    private func canSplit(width: CGFloat) -> Bool { width >= Self.splitMinimum }

    private func arrangement(width: CGFloat) -> Arrangement {
        guard isEditing else { return .reader }
        if canSplit(width: width) { return wantsPreview ? .split : .editor }
        return peeking ? .reader : .editor
    }

    private var arrangement: Arrangement { arrangement(width: paneWidth) }

    private var outlineIsOpen: Bool { showOutlineSheet || (showOutline && paneWidth + (showOutline ? Self.outlineWidth : 0) >= Self.outlineMinimum) }
    private var readerIsNeeded: Bool { arrangement != .editor || outlineIsOpen }

    var body: some View {
        VStack(spacing: 0) {
            if showFind { findBar }
            if ConflictBlocks.contains(session.text) { conflictHint }
            GeometryReader { geometry in panes(in: geometry.size) }
        }
        .background(sizeShortcuts)
        .modifier(NoteTitle(title: file.title, isEditable: isEditing && ownsToolbar) { model.rename(path, to: $0) })
        .perchScreenBackground()
        .toolbar { if ownsToolbar { toolbar } }
        .onAppear(perform: setUp)
        .onDisappear {
            // The page and the editor report to closures that hold this view, and this view holds them:
            // left connected, a closed note's session, editor and page (with its WebKit process) would
            // never be let go. They are connected again if the note comes back on screen.
            host.onMessage = nil
            actions.onEscape = nil
            actions.onScroll = nil
            session.saveNow()
            NoteResume.shared.update(path, line: isEditing && arrangement != .reader ? actions.topLine() : scroll.readerLine)
            NoteResume.shared.disappear(path)
        }
        .onChange(of: isEditing) { _, editing in NoteResume.shared.update(path, editing: editing) }
        .onChange(of: session.text) { render() }
        .onChange(of: model.files) { session.refreshFromDisk() }
        .onChange(of: reading.appearance) { host.call("setAppearance", arguments: readerAppearance) }
        // The page recolours itself, diagrams included; the note is not rendered again.
        .onChange(of: theme) { host.call("setAppearance", arguments: readerAppearance) }
        .onReceive(NotificationCenter.default.publisher(for: Self.appIsLeaving)) { _ in session.saveNow() }
        .onChange(of: readerIsNeeded) { if readerIsNeeded, needsRender { render(immediately: true) } }
        .onChange(of: arrangement) {
            scroll.syncsPreview = arrangement == .split && syncPreviewScroll
            // Beside the editor the preview starts its text level with the editor's; alone, at its own spacing.
            host.call("setAppearance", arguments: readerAppearance)
        }
        .onChange(of: actions.textTop) { if arrangement == .split { host.call("setAppearance", arguments: readerAppearance) } }
        .onChange(of: syncPreviewScroll) { scroll.syncsPreview = arrangement == .split && syncPreviewScroll }
        #if os(macOS)
        .onExitCommand { _ = handleEscape() }
        #endif
        .sheet(item: $shareFile) { url in ExportSheet(url: url) }
        .sheet(isPresented: $showOutlineSheet) { outlineSheet }
        #if os(iOS)
        .sheet(isPresented: $showReadingSettings) {
            ReadingQuickSettings(showsEditor: isEditing)
                .presentationBackground(theme.surface)
                .presentationDetents([.height(440), .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .height(440)))
                .presentationDragIndicator(.visible)
        }
        #endif
    }

    // MARK: Panes

    /// The reader and the editor stay in place and are resized, so switching modes never rebuilds either.
    private func panes(in size: CGSize) -> some View {
        let outlineInline = showOutline && size.width >= Self.outlineMinimum
        let width = max(size.width - (outlineInline ? Self.outlineWidth : 0), 0)
        let arrangement = arrangement(width: width)
        let fraction = min(max(dragFraction ?? splitFraction, 0.28), 0.72)
        let editorWidth = arrangement == .split ? (width * fraction).rounded() : width
        let previewWidth = arrangement == .split ? width - editorWidth : width
        let previewOnLeft = reading.previewSide == .left
        let editorX: CGFloat = arrangement == .split && previewOnLeft ? previewWidth : 0
        let readerX: CGFloat = arrangement == .split && !previewOnLeft ? editorWidth : 0
        let showsReader = arrangement != .editor
        let showsEditor = arrangement != .reader

        return ZStack(alignment: .topLeading) {
            readerPane
                .frame(width: max(previewWidth, 1), height: size.height)
                .offset(x: readerX)
                .opacity(showsReader ? 1 : 0)
                .allowsHitTesting(showsReader)
                .accessibilityHidden(!showsReader)
            if editorLoaded {
                editorPane
                    .frame(width: max(editorWidth, 1), height: size.height)
                    .offset(x: editorX)
                    .opacity(showsEditor ? 1 : 0)
                    .allowsHitTesting(showsEditor)
                    .accessibilityHidden(!showsEditor)
            }
            if arrangement == .split {
                splitHandle(width: width, height: size.height)
                    .offset(x: (previewOnLeft ? previewWidth : editorWidth) - 5)
                    .transition(.opacity)
            }
            if !session.isReadable {
                EmptyState(
                    symbol: "doc.questionmark", title: "Perch can't read this file",
                    message: "It isn't saved as plain UTF-8 text, so Perch will leave it exactly as it is."
                )
                .frame(width: width, height: size.height)
            } else if arrangement == .reader, isBlank {
                EmptyState(
                    symbol: "square.and.pencil", title: "Nothing here yet",
                    message: "This note is empty.", actionTitle: "Start writing", action: startEditing
                )
                .frame(width: width, height: size.height)
            }
            if outlineInline {
                outline
                    .frame(width: Self.outlineWidth, height: size.height)
                    .background(theme.sidebar)
                    .overlay(alignment: .leading) { Rectangle().fill(theme.border).frame(width: 1) }
                    .offset(x: width)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .coordinateSpace(name: "notePanes")
        .onAppear { paneWidth = width }
        .onChange(of: width) { paneWidth = width }
    }

    private var readerPane: some View {
        WebHostView(host: host).background(Color.clear)
    }

    private var editorPane: some View {
        MarkdownEditor(text: $session.text, actions: actions, roomy: true, isActive: arrangement != .reader, formatBar: true) { query in
            if query != nil { completionAnchor = actions.caretRect() }
            completion = query
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                if let completion {
                    let anchor = completionAnchor ?? CGRect(x: 16, y: 0, width: 0, height: 16)
                    let menuWidth = min(280, max(geometry.size.width - 24, 160))
                    completionMenu(completion, width: menuWidth)
                        .offset(
                            x: min(max(anchor.minX, 12), max(geometry.size.width - menuWidth - 12, 12)),
                            y: min(max(anchor.maxY + 6, 8), max(geometry.size.height - 250, 8))
                        )
                        .transition(.opacity)
                }
            }
        }
    }

    /// The line between editor and preview. Drag it to give one side more room.
    private func splitHandle(width: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(dragFraction == nil ? theme.border : theme.accent)
            .frame(width: 1, height: height)
            .frame(width: 11)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("notePanes"))
                    .onChanged { value in
                        guard width > 0 else { return }
                        let share = Double(value.location.x / width)
                        dragFraction = reading.previewSide == .left ? 1 - share : share
                    }
                    .onEnded { _ in
                        if let dragFraction { splitFraction = min(max(dragFraction, 0.28), 0.72) }
                        dragFraction = nil
                    }
            )
            #if os(macOS)
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            #endif
            .accessibilityLabel("Resize editor and preview")
    }

    private var conflictHint: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.warning).accessibilityHidden(true)
            Text("This note changed in two places. Choose which version to keep in the preview.").foregroundStyle(theme.text)
            Spacer()
            if arrangement == .editor { Button("Show preview") { togglePreview() } }
        }
        .font(.perchStyle(.callout))
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(theme.warning.opacity(0.14))
    }

    private var findBar: some View {
        HStack {
            TextField("Find", text: $findText).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
            TextField("Replace", text: $replaceText).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
            Text(findText.isEmpty ? "" : "\(session.text.components(separatedBy: findText).count - 1) found")
                .font(.perchStyle(.caption)).foregroundStyle(theme.textSecondary)
            Button("Replace all") {
                guard !findText.isEmpty else { return }
                session.text = session.text.replacingOccurrences(of: findText, with: replaceText)
            }
            .disabled(findText.isEmpty)
            Spacer()
            Button { showFind = false } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close find and replace")
        }
        .padding(8)
        .background(theme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.border).frame(height: 1) }
    }

    @ViewBuilder
    private func completionMenu(_ completion: EditorCompletion, width: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                switch completion {
                case let .wiki(query):
                    ForEach(model.links.completions(for: query, limit: 8), id: \.path) { item in
                        Button {
                            let ambiguous: Bool = { if case .ambiguous = model.links.resolve(item.title) { return true } else { return false } }()
                            let target = ambiguous ? String(item.path.dropLast((item.path as NSString).pathExtension.count + 1)) : item.title
                            actions.replaceTrigger("[[\(target)]]")
                            self.completion = nil
                        } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.title).foregroundStyle(theme.text).lineLimit(1)
                                Text(VaultFile(path: item.path).folder).font(.perchStyle(.caption2)).foregroundStyle(theme.textSecondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                    }
                case let .slash(query):
                    ForEach(slashCommands.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { command in
                        Button {
                            let insertion = command.insertion == "@DATE@" ? model.today : command.insertion
                            actions.replaceTrigger(insertion)
                            self.completion = nil
                        } label: {
                            Label(command.name, systemImage: command.symbol)
                                .foregroundStyle(theme.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(8)
        }
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: 236)
        .fixedSize(horizontal: false, vertical: true)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }

    // MARK: Contents and links

    /// Contents, backlinks and mentions, in one quiet column.
    private var outline: some View {
        NoteOutline(
            model: model, path: path, text: session.text, toc: toc,
            jump: jump(toLine:), open: open(path:), saveMention: saveMention(text:path:)
        )
    }

    private var outlineSheet: some View {
        NavigationStack {
            outline
                .navigationTitle("Contents and links")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { showOutlineSheet = false } }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.background)
        #if os(macOS)
        .frame(minWidth: 340, minHeight: 420)
        #endif
    }

    private func jump(toLine line: Int) {
        showOutlineSheet = false
        if arrangement != .editor { host.call("scrollToLine", arguments: ["line": line]) }
        if arrangement != .reader { actions.scrollToLine(Double(line)) }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { toggleEditing() } label: {
                #if os(macOS)
                Label(isEditing ? "Done" : "Edit", systemImage: isEditing ? "checkmark" : "square.and.pencil").labelStyle(.titleAndIcon)
                #else
                Text(isEditing ? "Done" : "Edit").fontWeight(isEditing ? .semibold : .regular)
                #endif
            }
            .keyboardShortcut("e", modifiers: .command)
            .help(isEditing ? "Finish editing (⌘E or Esc)" : "Edit this note (⌘E)")
            .accessibilityLabel(isEditing ? "Done editing" : "Edit note")
            .disabled(!session.isReadable)
        }
        if isEditing {
            ToolbarItem(placement: .automatic) {
                let wide = canSplit(width: paneWidth)
                let active = wide ? wantsPreview : peeking
                Button { togglePreview() } label: {
                    Image(systemName: wide ? "rectangle.split.2x1" : (peeking ? "eye.fill" : "eye"))
                        .symbolVariant(wide && wantsPreview ? .fill : .none)
                }
                .help(wide ? (active ? "Hide the preview" : "Show the preview beside the editor") : (active ? "Back to the editor" : "Peek at the preview"))
                .accessibilityLabel(active ? "Hide preview" : "Show preview")
            }
        }
        #if os(macOS)
        ToolbarItem(placement: .automatic) {
            Button { showReadingSettings.toggle() } label: { Image(systemName: "textformat.size") }
                .help("Text and layout")
                .accessibilityLabel("Text and layout")
                .popover(isPresented: $showReadingSettings, arrowEdge: .bottom) {
                    ReadingQuickSettings(showsEditor: isEditing).presentationBackground(theme.surface)
                }
        }
        ToolbarItem(placement: .automatic) {
            Button { toggleOutline() } label: { Image(systemName: "list.bullet.indent") }
                .help("Contents, backlinks and mentions")
                .accessibilityLabel("Contents and links")
        }
        #endif
        ToolbarItem(placement: .automatic) {
            Menu {
                #if os(iOS)
                Button { showReadingSettings = true } label: { Label("Text and layout", systemImage: "textformat.size") }
                Button { toggleOutline() } label: { Label("Contents and links", systemImage: "list.bullet.indent") }
                Divider()
                #endif
                Button("Find and replace") { showFind = true }.keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Rename…") { model.pendingFileRename = path }
                Button(recorder.isRecording ? "Stop recording" : "Record audio") { toggleRecording() }
                Button("Export PDF…") { exportPDF() }
                Divider()
                Button("Delete note", role: .destructive) {
                    session.discard()
                    model.deleteFile(path)
                }
            } label: { Image(systemName: "ellipsis.circle") }
            .accessibilityLabel("More")
        }
    }

    /// ⌘+ / ⌘− / ⌘0 change the text size of whichever pane is being used.
    @ViewBuilder
    private var sizeShortcuts: some View {
        #if os(macOS)
        Group {
            Button("Bigger text") { stepSize(1) }.keyboardShortcut("=", modifiers: .command)
            Button("Bigger text") { stepSize(1) }.keyboardShortcut("+", modifiers: .command)
            Button("Smaller text") { stepSize(-1) }.keyboardShortcut("-", modifiers: .command)
            Button("Default text size") { stepSize(0) }.keyboardShortcut("0", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
        #endif
    }

    private func stepSize(_ delta: Int) {
        if arrangement == .editor {
            if delta == 0 { reading.editorTextSize = 0 } else { reading.stepEditorTextSize(delta) }
        } else {
            if delta == 0 { reading.textSize = 0 } else { reading.stepTextSize(delta) }
        }
    }

    // MARK: Modes

    private func setUp() {
        // Every time the note comes back on screen; see onDisappear.
        configureHost()
        actions.onEscape = { handleEscape() }
        #if DEBUG
        DebugProbes.togglePreview = { togglePreview() }
        #endif
        actions.onScroll = { [scroll, weak host] line in
            guard scroll.syncsPreview else { return }
            host?.call("scrollToSourceLine", arguments: ["line": line])
        }
        guard !didSetUp else { return }
        didSetUp = true
        // `path` is captured by itself. Reading it through the view would put a copy of the whole view,
        // with its session, page and these very actions, inside a closure the actions keep: a ring
        // nothing could break, and every note ever opened would stay in memory with its page.
        actions.pasteImage = { [weak model, path] data, fileExtension in
            MainActor.assumeIsolated { NoteView.storeAttachment(model: model, notePath: path, data: data, fileExtension: fileExtension) }
        }
        // Sent before the first render, so the note never appears in the wrong type.
        host.call("setAppearance", arguments: readerAppearance)
        wantsPreview = reading.editWithPreview
        // The same note drawn again a moment later (the layout changed under it) carries on as it was.
        let resume = NoteResume.shared.appear(path)
        // A new, empty note has nothing to read: go straight to writing.
        if session.isReadable, isBlank || reading.openIn == .edit || resume?.editing == true {
            actions.focusOnAppear = isBlank
            if let line = resume?.line, line > 0 { actions.initialLine = line }
            editorLoaded = true
            isEditing = true
        }
        NoteResume.shared.update(path, editing: isEditing)
        render(immediately: true, scrollLine: resume.flatMap { $0.line > 0 ? $0.line : nil })
    }

    private func toggleEditing() {
        if isEditing { finishEditing() } else { startEditing() }
    }

    private func startEditing() {
        guard !isEditing, session.isReadable else { return }
        // Start where the reader was, so the text doesn't jump.
        actions.initialLine = scroll.readerLine
        actions.focusOnAppear = true
        wantsPreview = reading.editWithPreview
        peeking = false
        let alreadyLoaded = editorLoaded
        withMotion(reduceMotion: reduceMotion) {
            editorLoaded = true
            isEditing = true
        }
        if alreadyLoaded { actions.applyPending() }
    }

    private func finishEditing() {
        guard isEditing else { return }
        let line: Double? = arrangement == .editor ? actions.topLine() : nil
        session.saveNow()
        completion = nil
        dismissKeyboard()
        withMotion(reduceMotion: reduceMotion) {
            isEditing = false
            peeking = false
        }
        render(immediately: true, scrollLine: line)
    }

    /// Beside the editor when there's room; otherwise a quick look that swaps with the editor.
    private func togglePreview() {
        if canSplit(width: paneWidth) {
            let line = actions.topLine()
            withMotion(reduceMotion: reduceMotion) { wantsPreview.toggle() }
            if wantsPreview { render(immediately: true, scrollLine: line) }
        } else if peeking {
            actions.initialLine = scroll.readerLine
            actions.focusOnAppear = true
            withMotion(reduceMotion: reduceMotion) { peeking = false }
            actions.applyPending()
        } else {
            let line = actions.topLine()
            dismissKeyboard()
            withMotion(reduceMotion: reduceMotion) { peeking = true }
            render(immediately: true, scrollLine: line)
        }
    }

    private func toggleOutline() {
        if paneWidth + (showOutline ? Self.outlineWidth : 0) >= Self.outlineMinimum {
            withMotion(reduceMotion: reduceMotion) { showOutline.toggle() }
        } else {
            showOutlineSheet = true
        }
        if needsRender { render(immediately: true) }
    }

    private func handleEscape() -> Bool {
        if completion != nil {
            completion = nil
            return true
        }
        if showFind {
            showFind = false
            return true
        }
        guard isEditing else { return false }
        finishEditing()
        return true
    }

    private func dismissKeyboard() {
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    // MARK: Actions

    private func toggleRecording() {
        if recorder.isRecording {
            guard let url = recorder.stop(), let data = try? Data(contentsOf: url) else { return }
            if let link = Self.storeAttachment(model: model, notePath: path, data: data, fileExtension: "m4a") {
                let plain = link.replacingOccurrences(of: "![", with: "[Audio ").replacingOccurrences(of: "](", with: "](")
                session.text += (session.text.hasSuffix("\n") || session.text.isEmpty ? "" : "\n") + plain + "\n"
            }
        } else {
            recorder.start { message in model.banner = message }
        }
    }

    private func exportPDF() {
        Task {
            // The reader is always there, even behind the editor; make sure it shows the latest text.
            await renderNow()
            guard let data = await host.makePDF() else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.title + ".pdf")
            try? data.write(to: url, options: .atomic)
            shareFile = url
        }
    }

    private func configureHost() {
        host.onMessage = { message in
            switch message["type"] as? String {
            case "rendered":
                if let sentAt = renderSentAt { pacer.drawn(cost: Date().timeIntervalSince(sentAt)) }
                #if DEBUG
                DebugProbes.rendered.append(Date())
                #endif
                let items = message["toc"] as? [[String: Any]] ?? []
                toc = items.compactMap { item in
                    guard let level = item["level"] as? Int, let text = item["text"] as? String, let line = item["line"] as? Int else { return nil }
                    return TOCItem(level: level, text: text, line: line)
                }
            case "scroll":
                if let line = message["line"] as? Double {
                    scroll.readerLine = line
                    if NotePanes.editorFollowsPreview(byUser: message["byUser"] as? Bool ?? false, syncing: scroll.syncsPreview) {
                        actions.scrollToLine(line)
                    }
                }
            case "copy":
                if let text = message["text"] as? String { PlatformOpen.copy(text) }
            case "toggleTask":
                if let line = message["line"] as? Int { toggleCheckbox(line: line, checked: message["checked"] as? Bool) }
            case "openNote":
                if let target = message["path"] as? String { open(path: target) }
            case "openWiki":
                if let target = message["target"] as? String { openWiki(target) }
            case "openExternal":
                if let string = message["url"] as? String, let url = URL(string: string) { PlatformOpen.url(url) }
            case "saveMention":
                if let text = message["text"] as? String, let target = message["path"] as? String { saveMention(text: text, path: target) }
            case "resolveConflict":
                if let index = message["index"] as? Int, let variant = message["variant"] as? String {
                    session.text = ConflictBlocks.resolve(session.text, blockIndex: index, variant: variant)
                }
            default: break
            }
        }
    }

    private func open(path target: String) {
        if model.files.contains(where: { $0.path == target }) {
            showOutlineSheet = false
            model.route = .file(target)
        } else {
            model.banner = "\(target) doesn't exist."
        }
    }

    private func openWiki(_ target: String) {
        var resolution = model.links.resolve(target, from: path)
        // `[[Note#Heading]]` opens Note.
        if case .missing = resolution, let hash = target.firstIndex(of: "#"), hash != target.startIndex {
            resolution = model.links.resolve(String(target[..<hash]).trimmingCharacters(in: .whitespaces), from: path)
        }
        switch resolution {
        case let .note(found): model.route = .file(found)
        case let .ambiguous(paths): model.route = .file(paths[0])
        case .folder: model.banner = "\(target) is a folder."
        case .missing:
            // The target comes from the page, so it is checked here: a new note is only ever made inside
            // the notebook, and a file that is already there is opened, never written over.
            guard let newPath = WikiLinks.pathForNewNote(target: target, besideNoteIn: file.folder) else {
                model.banner = "Can't make a note called \(target)."
                return
            }
            if let existing = model.files.first(where: { $0.path.caseInsensitiveCompare(newPath) == .orderedSame }) {
                model.route = .file(existing.path)
                return
            }
            if let vault = model.vault, FileManager.default.fileExists(atPath: vault.url(for: newPath).path) {
                model.banner = "\(newPath) is already there."
                Task { await model.reload(force: true) }
                return
            }
            model.save("", to: newPath)
            Task { await model.reload(force: true) }
            model.route = .file(newPath)
        }
    }

    private func saveMention(text: String, path target: String) {
        guard let range = model.links.mentions(in: session.text, excluding: path).first(where: {
            $0.path == target && String(session.text[$0.range]).caseInsensitiveCompare(text) == .orderedSame
        })?.range else { return }
        let title = VaultFile(path: target).title
        let spelled = String(session.text[range])
        let link: String = {
            if case .note = model.links.resolve(title, from: path) {
                return spelled == title ? "[[\(title)]]" : "[[\(title)|\(spelled)]]"
            }
            let stem = String(target.dropLast((target as NSString).pathExtension.count + 1))
            return "[[\(stem)|\(spelled)]]"
        }()
        session.text.replaceSubrange(range, with: link)
    }

    /// A click on a task's box in the reader. Changes the one character between its brackets and nothing else.
    private func toggleCheckbox(line: Int, checked: Bool?) {
        if let edit = MarkdownEditing.setTaskBox(in: session.text, line: line, checked: checked) {
            session.text = edit.applied(to: session.text)
        } else {
            // The click didn't land on a task in the text: draw the note again so the box shows the truth.
            render(immediately: true)
        }
    }

    // MARK: Rendering

    /// Draws the note in the reader. Skipped while only the editor is showing, and caught up when the reader returns.
    private func render(immediately: Bool = false, scrollLine: Double? = nil) {
        guard readerIsNeeded || immediately else {
            renderTask?.cancel()
            renderTask = nil
            pacer.cancelled()
            needsRender = true
            return
        }
        if immediately {
            renderTask?.cancel()
            pacer.cancelled()
            renderTask = Task { sendRender(scrollLine: scrollLine) }
            return
        }
        // While typing: drawn about eight times a second, or less often when the last render was slow. A
        // change made while a render waits joins it, since that render sends the newest text. The page only
        // rebuilds the blocks that changed.
        guard let wait = pacer.changed(at: Date().timeIntervalSinceReferenceDate) else { return }
        renderTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            sendRender(scrollLine: scrollLine)
        }
    }

    private func renderNow() async {
        renderTask?.cancel()
        pacer.cancelled()
        sendRender(scrollLine: nil)
        // Code is coloured and diagrams are drawn after the text appears; a PDF waits for all of it.
        await host.settle()
    }

    private func sendRender(scrollLine: Double?) {
        needsRender = false
        renderSentAt = Date()
        pacer.sent(at: Date().timeIntervalSinceReferenceDate)
        let text = session.text
        // Finding mentions means searching the note for every title in the notebook: seconds for a long
        // note. The text is drawn now with the mentions already known, and the search runs off to the side;
        // when it finds something different the page is told, and only the mentions on it change.
        let mentions = mentionLookup.mentions(for: text, in: model.links, excluding: path) {
            sendRender(scrollLine: nil)
        }
        var resolved: [String: Bool] = [:]
        for link in WikiLinks.parse(text) {
            if case .missing = model.links.resolve(link.target, from: path) {
                resolved[link.target] = false
            } else {
                resolved[link.target] = true
            }
        }
        var arguments: [String: Any] = [
            "markdown": text, "basePath": path, "mentions": mentions, "resolved": resolved,
            "appearance": readerAppearance,
        ]
        if let scrollLine { arguments["scrollLine"] = scrollLine }
        #if DEBUG
        DebugProbes.renderSent.append((Date(), text.utf16.count))
        #endif
        host.call("render", arguments: arguments)
    }

    /// Saves attachments the way NotesHub does: `.attachments/<sha1>.<ext>` beside the note.
    static func storeAttachment(model: AppModel?, notePath: String, data: Data, fileExtension: String) -> String? {
        guard let vault = model?.vault else { return nil }
        let hash = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let name = "\(hash).\(fileExtension.lowercased())"
        let folder = (notePath as NSString).deletingLastPathComponent
        let path = (folder.isEmpty ? "" : folder + "/") + ".attachments/" + name
        guard (try? vault.writeData(data, to: path)) != nil else { return nil }
        model?.scheduleSync()
        return "![](.attachments/\(name))"
    }
}

/// The unlinked mentions the reader underlines, found without holding up the note.
/// The search runs off the main thread; until it answers, the last answer stands.
@MainActor
private final class MentionLookup {
    private var known: [[String: String]] = []
    private var knownFor: String?
    private var searching: Task<Void, Never>?
    private var searchingFor: String?

    deinit { searching?.cancel() }

    /// The mentions to draw now. If they were worked out for other text, a search starts once typing
    /// pauses, and `changed` is called when it ends with a different answer. One search runs at a time:
    /// a newer text cancels the one in flight, which stops at the next name it would have looked for.
    func mentions(for text: String, in links: LinkIndex, excluding path: String, changed: @escaping @MainActor () -> Void) -> [[String: String]] {
        guard knownFor != text, searchingFor != text else { return known }
        searching?.cancel()
        searchingFor = text
        // The first search for a note starts at once; later ones wait for a pause in the typing.
        let delay: UInt64 = knownFor == nil ? 0 : 350_000_000
        searching = Task.detached(priority: .utility) { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            guard !Task.isCancelled else { return }
            var seen = Set<String>()
            let found: [[String: String]] = links.mentions(in: text, excluding: path, isCancelled: { Task.isCancelled }).compactMap { mention in
                let key = String(text[mention.range]).lowercased()
                // The page underlines every place a name appears; it needs each name once, and a note
                // that names half the notebook doesn't need all of them underlined.
                guard seen.count < 400, seen.insert(key).inserted else { return nil }
                return ["key": key, "path": mention.path, "title": mention.title]
            }
            guard !Task.isCancelled else { return }
            await self?.finish(found, for: text, changed: changed)
        }
        return known
    }

    private func finish(_ found: [[String: String]], for text: String, changed: @MainActor () -> Void) {
        // An answer for text that has since been replaced is dropped.
        guard searchingFor == text else { return }
        searchingFor = nil
        let differs = found != known
        known = found
        knownFor = text
        if differs { changed() }
    }
}

/// Contents, backlinks and mentions for one note. Looks links up after a pause, never on every redraw:
/// finding mentions means searching the note for every title in the notebook.
private struct NoteOutline: View {
    @ObservedObject var model: AppModel
    let path: String
    let text: String
    let toc: [NoteView.TOCItem]
    var jump: (Int) -> Void
    var open: (String) -> Void
    var saveMention: (String, String) -> Void
    @State private var backlinks: [String] = []
    @State private var mentions: [Mention] = []
    @Environment(\.perchTheme) private var theme

    /// A mention with the words as they were spelled, so nothing here holds positions in text that has since changed.
    struct Mention { var path: String, title: String, spelled: String }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section("Contents") {
                    if toc.isEmpty { hint("Headings in this note appear here.") }
                    ForEach(toc) { item in
                        Button { jump(item.line) } label: {
                            Text(item.text)
                                .font(.perchStyle(.subheadline).weight(item.level <= 1 ? .semibold : .regular))
                                .foregroundStyle(item.level <= 2 ? theme.text : theme.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .padding(.leading, CGFloat(max(item.level - 1, 0)) * 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                section("Linked from") {
                    if backlinks.isEmpty { hint("Nothing links here yet.") }
                    ForEach(backlinks, id: \.self) { source in
                        Button(model.tasks.first { $0.path == source }?.title ?? VaultFile(path: source).title) { open(source) }
                            .buttonStyle(PerchLinkStyle())
                    }
                }
                section("Mentions") {
                    if mentions.isEmpty { hint("No other notes are mentioned.") }
                    ForEach(mentions.prefix(12), id: \.path) { mention in
                        VStack(alignment: .leading, spacing: 1) {
                            Button(mention.title) { open(mention.path) }.buttonStyle(PerchLinkStyle())
                            Button("Save as link") { saveMention(mention.spelled, mention.path) }
                                .buttonStyle(.borderless).font(.perchStyle(.caption)).foregroundStyle(theme.textSecondary)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: text) {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            backlinks = model.links.backlinks(to: path)
            var seen = Set<String>()
            let source = text
            mentions = model.links.mentions(in: source, excluding: path)
                .filter { seen.insert($0.path).inserted }
                .map { Mention(path: $0.path, title: $0.title, spelled: String(source[$0.range])) }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased()).font(.perchEyebrow).foregroundStyle(theme.textSecondary).kerning(0.4)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.perchCaption).foregroundStyle(theme.textMuted)
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

@MainActor
final class AudioNoteRecorder: ObservableObject {
    @Published var isRecording = false
    private var recorder: AVAudioRecorder?
    private var url: URL?

    func start(onError: @escaping (String) -> Void) {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                guard granted else {
                    onError("Perch needs microphone access to record audio. Turn it on in System Settings.")
                    return
                }
                let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
                let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1]
                self.recorder = try? AVAudioRecorder(url: target, settings: settings)
                self.url = target
                self.isRecording = self.recorder?.record() ?? false
                if !self.isRecording { onError("Recording couldn't start.") }
            }
        }
    }

    func stop() -> URL? {
        recorder?.stop()
        isRecording = false
        return url
    }
}

/// Saves a Mac file through the save panel, or hands it to the iPhone's share sheet.
struct ExportSheet: View {
    /// Read so this is drawn again when the interface size or density changes.
    @Environment(\.perchDisplay) private var display
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let _ = display
        VStack(spacing: 14) {
            Image(systemName: "doc.richtext").font(.perchStyle(.largeTitle)).foregroundStyle(.secondary)
            Text(url.lastPathComponent).font(.perchStyle(.headline))
            ShareLink(item: url) { Label("Share or save PDF", systemImage: "square.and.arrow.up") }
                .buttonStyle(.borderedProminent)
            Button("Close") { dismiss() }
        }
        .padding(24)
        .frame(minWidth: 280)
    }
}
