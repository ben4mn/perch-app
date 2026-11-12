import PerchKit
import SwiftUI

/// How a folder lays out what's inside it.
enum FolderLayout: String, CaseIterable {
    case grid, list

    /// The saved-setting keys. The snapshot runner sets the same keys for one run.
    static let storageKey = "folderLayout"
    static let sortStorageKey = "folderSort"
    static let dateFilterStorageKey = "folderDateFilter"

    static var platformDefault: FolderLayout {
        #if os(iOS)
        .list
        #else
        .grid
        #endif
    }

    /// The layout to show: the saved choice, or, with none saved, a grid wherever there is room for one.
    static func resolve(saved: String, width: CGFloat) -> FolderLayout {
        if let layout = FolderLayout(rawValue: saved) { return layout }
        return AdaptiveLayout.folderGrid(width: Double(width), prefersList: platformDefault == .list) ? .grid : .list
    }

    var symbol: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
    var title: String { self == .grid ? "Grid" : "List" }
}

/// Remembers the folder shown last, so opening the next one can move the right way:
/// in from the trailing edge when going deeper, from the leading edge when going back up.
@MainActor
enum FolderTrail {
    static var last: String?

    static func offset(to path: String) -> CGFloat {
        guard let last, last != path else { return 0 }
        if last.isEmpty || path.hasPrefix(last + "/") { return 22 }
        if path.isEmpty || last.hasPrefix(path + "/") { return -22 }
        return 0
    }
}

/// What a folder shows in the main pane: its subfolders and files.
struct FolderScreen: View {
    @ObservedObject var model: AppModel
    let path: String
    let kinds: Set<VaultFileKind>
    let rootTitle: String
    /// The choice of which kinds to list, when the screen offers one: All, Notes, Boards or Whiteboards.
    let kind: Binding<NotesKind>?
    /// Where a tap goes. The Mac changes the route; the iPhone changes the folder in place or pushes a file.
    let open: ((Route) -> Void)?
    /// The Notes folder chips are above this screen, so a top-level folder needs no path over its title.
    var besideFolderChips = false

    /// Empty until the user picks one, so an untouched folder can follow the width of the screen.
    @AppStorage(FolderLayout.storageKey) private var layoutRaw = ""
    @AppStorage(FolderLayout.sortStorageKey) private var sortRaw = FolderListing.Sort.name.rawValue
    @AppStorage(FolderLayout.dateFilterStorageKey) private var dateFilterRaw = FolderListing.DateFilter.anyTime.storage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.perchTheme) private var theme
    @Environment(\.perchSelectedPath) private var selectedPath
    /// Tabs: the workspace, where there is one, for "Open in New Tab" in each item's menu.
    @Environment(\.perchWorkspace) private var workspace
    @State private var width: CGFloat = 700
    @State private var entered = false
    @State private var settled = false
    @State private var slide: CGFloat
    /// The file waiting for a yes before it is deleted.
    @State private var pendingDelete: VaultFile?

    init(
        model: AppModel, path: String,
        kinds: Set<VaultFileKind> = FolderListing.browsableKinds,
        rootTitle: String = "Notes", kind: Binding<NotesKind>? = nil, besideFolderChips: Bool = false, open: ((Route) -> Void)? = nil
    ) {
        self.besideFolderChips = besideFolderChips
        self.model = model
        self.path = path
        self.kinds = kinds
        self.rootTitle = rootTitle
        self.kind = kind
        self.open = open
        _slide = State(initialValue: FolderTrail.offset(to: path))
    }

    /// What "New" makes first here: a note, unless only boards or only whiteboards are listed.
    private var primaryKind: VaultFileKind {
        if kinds.contains(.note) { return .note }
        return kinds.contains(.board) ? .board : .whiteboard
    }

    private var layout: FolderLayout { FolderLayout.resolve(saved: layoutRaw, width: theme.display.layoutWidth(width)) }
    private var creatable: [VaultFileKind] { [.note, .board, .whiteboard].filter(kinds.contains) }
    private var sort: FolderListing.Sort { FolderListing.Sort(rawValue: sortRaw) ?? .name }
    private var dateFilter: FolderListing.DateFilter { FolderListing.DateFilter(storage: dateFilterRaw) }
    /// Which date a row names first: the one the folder is sorted or filtered by.
    private var createdFirst: Bool { sort == .created || (sort != .modified && dateFilter.isActive && dateFilter.field == .created) }
    private var title: String { path.isEmpty ? rootTitle : (path as NSString).lastPathComponent }

    var body: some View {
        let listing = FolderListing(files: model.files, path: path, kinds: kinds, sort: sort, filter: dateFilter)
        let layout = layout
        HeaderScroll {
            header(listing, layout: layout)
        } content: {
                VStack(alignment: .leading, spacing: Metrics.gap + 4) {
                    if model.visibleAreas.contains(path) { areaLink }
                    if listing.isEmpty {
                        emptyState.frame(minHeight: 340)
                    } else {
                        Group {
                            if layout == .grid { grid(listing) } else { rows(listing) }
                        }
                        .transition(.perchSwap(reduceMotion: reduceMotion))
                    }
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.top, 4)
                .padding(.bottom, Metrics.screenPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .motion(Motion.smooth, value: layout)
                .motion(Motion.smooth, value: sortRaw)
                .motion(Motion.smooth, value: dateFilterRaw)
        }
        .opacity(entered ? 1 : 0)
        .offset(x: entered || reduceMotion ? 0 : slide)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { width = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, new in width = new }
            }
        }
        .perchScreenBackground()
        #if os(macOS)
        .contextMenu { newItemButtons(model: model, folder: path, kinds: kinds) }
        #endif
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.syncNow() }
        #endif
        .alert(
            "Delete \(pendingDelete?.title ?? "this file")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { file in
            Button("Delete", role: .destructive) {
                model.deleteFile(file.path)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("Its file is removed. It stays recoverable in Git history once synced.")
        }
        .onAppear {
            FolderTrail.last = path
            withMotion(reduceMotion: reduceMotion) { entered = true }
        }
        .task {
            // After the opening stagger, rows that scroll into view arrive without a delay.
            try? await Task.sleep(nanoseconds: 600_000_000)
            settled = true
        }
    }

    private func go(_ route: Route) {
        if let open { open(route) } else { model.route = route }
    }

    @ViewBuilder
    private var emptyState: some View {
        let noun = FolderListing.noun(primaryKind)
        let filter = dateFilter
        if filter.isActive, !FolderListing(files: model.files, path: path, kinds: kinds).isEmpty {
            // The folder has things in it, just none created or edited in that time.
            EmptyState(
                symbol: "calendar",
                title: "Nothing \(filter.field == .created ? "created" : "edited") \(filter.range.title.lowercased()) in \(title)",
                message: "The date filter hides everything in this folder. Show files from any time, or pick a longer stretch.",
                actionTitle: "Show any time", action: { dateFilterRaw = FolderListing.DateFilter(field: filter.field, range: .any).storage }
            )
        } else if let kind, kind.wrappedValue != .all, !FolderListing(files: model.files, path: path).isEmpty {
            // The folder has things in it, just none of the kind being shown.
            EmptyState(
                symbol: kind.wrappedValue.symbol,
                title: "No \(kind.wrappedValue.title.lowercased()) in \(title)",
                message: "This folder holds other kinds of file. Show everything, or start a \(noun) here.",
                actionTitle: "Show all kinds", action: { kind.wrappedValue = .all }
            )
        } else {
            EmptyState(
                symbol: "folder",
                title: "Nothing in \(title) yet",
                message: primaryKind == .board
                    ? "Boards live here: lists of cards you drag from one stage to the next. Start one and it shows up in this folder."
                    : "A folder holds notes, boards and whiteboards. Whatever you create here shows up in this folder.",
                actionTitle: "New \(noun)",
                action: { _ = model.createNote(in: path, kind: primaryKind) }
            )
        }
    }

    private func delay(_ index: Int) -> Double { settled ? 0 : Motion.stagger(index) }

    // MARK: Header

    private func header(_ listing: FolderListing, layout: FolderLayout) -> some View {
        let showsPath = FolderListing.showsBreadcrumb(for: path, besideFolderChips: besideFolderChips)
        return VStack(alignment: .leading, spacing: 0) {
            if showsPath {
                breadcrumb.padding(.horizontal, Metrics.screenPadding).padding(.top, crumbTop)
            }
            #if os(iOS)
            // The iPhone always puts the chips on their own row, scrolling sideways when they don't fit.
            // Measuring both arrangements with ViewThatFits, as the Mac does, never finished on iOS 27.1:
            // the first layout of Notes spun forever and the app took no touches (watchdog kills).
            stackedHeader(listing, layout: layout)
                .padding(.top, showsPath ? -crumbTop : 0)
            #else
            ViewThatFits(in: .horizontal) {
                ScreenHeader(title: title, stats: [HeaderStat(text: listing.summary)], trailing: { controls(layout) }, controls: { EmptyView() })
                // Under the title when they don't fit beside it, and scrolling sideways when they don't
                // fit there either: four chips at the largest interface size are wider than a phone.
                stackedHeader(listing, layout: layout)
            }
            .padding(.top, showsPath ? -crumbTop : 0)
            #endif
        }
    }

    private func stackedHeader(_ listing: FolderListing, layout: FolderLayout) -> some View {
        ScreenHeader(title: title, stats: [HeaderStat(text: listing.summary)]) {
            ScrollView(.horizontal, showsIndicators: false) { controls(layout) }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
    }

    private var crumbTop: CGFloat {
        #if os(iOS)
        6
        #else
        14
        #endif
    }

    private var breadcrumb: some View {
        let crumbs = [FolderListing.Crumb(name: rootTitle, path: "")] + FolderListing.crumbs(for: path)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(crumbs.enumerated()), id: \.element.id) { index, crumb in
                    HStack(spacing: 4) {
                        if index > 0 {
                            Image(systemName: "chevron.right").font(.perchFixed(size: 8, weight: .semibold)).foregroundStyle(theme.textMuted)
                                .accessibilityHidden(true)
                        }
                        if crumb.path == path {
                            Text(crumb.name).font(.perchCaption.weight(.medium)).foregroundStyle(theme.textSecondary)
                        } else {
                            CrumbButton(name: crumb.name) { go(.folder(crumb.path)) }
                        }
                    }
                    // Each step of the path arrives a beat after the one before it.
                    .riseIn(delay: Motion.stagger(index, step: 0.04), distance: 0)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Path")
    }

    private func controls(_ layout: FolderLayout) -> some View {
        HStack(spacing: Metrics.tightGap + 2) {
            if !creatable.isEmpty {
                Menu {
                    newItemButtons(model: model, folder: path, kinds: kinds)
                } label: {
                    ControlChip(symbol: "plus", text: "New")
                }
                .modifier(ChipMenu())
                .help("New in \(title)")
            }

            if let kind {
                Menu {
                    Picker("Show", selection: kind) {
                        ForEach(NotesKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    ControlChip(symbol: kind.wrappedValue.symbol, text: kind.wrappedValue == .all ? "All kinds" : kind.wrappedValue.title, isOn: kind.wrappedValue != .all)
                }
                .modifier(ChipMenu())
                .help("Show notes, boards or whiteboards")
                .accessibilityLabel("Kind: \(kind.wrappedValue.title)")
            }

            Menu {
                Picker("Sort by", selection: $sortRaw) {
                    ForEach(FolderListing.Sort.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.inline)
            } label: {
                ControlChip(symbol: "arrow.up.arrow.down", text: sort.title)
            }
            .modifier(ChipMenu())
            .help("Sort by")

            Menu {
                Picker("Date", selection: Binding(
                    get: { dateFilter.field },
                    set: { dateFilterRaw = FolderListing.DateFilter(field: $0, range: dateFilter.range).storage }
                )) {
                    ForEach(FolderListing.DateFilter.Field.allCases, id: \.rawValue) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                Picker("When", selection: Binding(
                    get: { dateFilter.range },
                    set: { dateFilterRaw = FolderListing.DateFilter(field: dateFilter.field, range: $0).storage }
                )) {
                    ForEach(FolderListing.DateFilter.Range.allCases, id: \.rawValue) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                ControlChip(symbol: "calendar", text: dateFilter.title, isOn: dateFilter.isActive)
            }
            .modifier(ChipMenu())
            .help("Show only files created or edited recently")
            .accessibilityLabel("Date filter: \(dateFilter.title)")

            Button {
                layoutRaw = (layout == .grid ? FolderLayout.list : .grid).rawValue
            } label: {
                ControlChip(symbol: layout == .grid ? FolderLayout.list.symbol : FolderLayout.grid.symbol, text: layout == .grid ? "List" : "Grid", showsChevron: false)
            }
            .buttonStyle(.plain)
            .help(layout == .grid ? "Show as a list" : "Show as a grid")
            .accessibilityLabel(layout == .grid ? "Show as a list" : "Show as a grid")
        }
    }

    /// A folder that is also a task area links across to its tasks.
    private var areaLink: some View {
        let count = model.tasks.filter { $0.area == path && $0.isOpen }.count
        return FolderItemView(
            layout: .list, compact: true, filled: true, symbol: "checklist", tint: Palette.area(path, theme: theme),
            title: "Tasks in \(title)", detail: count == 0 ? "No open tasks" : FolderListing.counted(count, "open task"),
            date: "", showsChevron: true
        ) { model.showTasks(area: path) }
            .frame(maxWidth: 420)
    }

    // MARK: Contents

    private func sectionLabel(_ text: String) -> some View { SectionLabel(text) }

    private func filesLabel(_ listing: FolderListing) -> String {
        let kinds = Set(listing.files.map(\.kind))
        return kinds.count == 1 ? FolderListing.noun(kinds.first!) + "s" : "Files"
    }

    private func grid(_ listing: FolderListing) -> some View {
        let columns = [GridItem(.adaptive(minimum: 190), spacing: Metrics.gap, alignment: .top)]
        return VStack(alignment: .leading, spacing: Metrics.gap) {
            if !listing.folders.isEmpty {
                sectionLabel("Folders")
                LazyVGrid(columns: columns, alignment: .leading, spacing: Metrics.gap) {
                    ForEach(Array(listing.folders.enumerated()), id: \.element.id) { index, folder in
                        folderItem(folder, layout: .grid).riseIn(delay: delay(index))
                    }
                }
            }
            if !listing.files.isEmpty {
                sectionLabel(filesLabel(listing)).padding(.top, listing.folders.isEmpty ? 0 : Metrics.tightGap)
                LazyVGrid(columns: columns, alignment: .leading, spacing: Metrics.gap) {
                    ForEach(Array(listing.files.enumerated()), id: \.element.id) { index, file in
                        fileItem(file, layout: .grid).riseIn(delay: delay(index + listing.folders.count))
                    }
                }
            }
        }
    }

    private func rows(_ listing: FolderListing) -> some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            #if os(macOS)
            if !stacksRows {
            HStack(spacing: Metrics.gap) {
                sectionLabel("Name")
                Spacer()
                sectionLabel("Kind").frame(width: FolderItemView.kindWidth, alignment: .leading)
                sectionLabel("Created").frame(width: FolderItemView.dateWidth, alignment: .trailing)
                sectionLabel("Last edited").frame(width: FolderItemView.dateWidth, alignment: .trailing)
            }
            .padding(.horizontal, Metrics.cardPadding - 2)
            .padding(.bottom, 4)
            }
            #endif
            ForEach(Array(listing.folders.enumerated()), id: \.element.id) { index, folder in
                folderItem(folder, layout: .list).riseIn(delay: delay(index), distance: 6)
            }
            ForEach(Array(listing.files.enumerated()), id: \.element.id) { index, file in
                fileItem(file, layout: .list).riseIn(delay: delay(index + listing.folders.count), distance: 6)
            }
        }
    }

    /// Whether list rows put the details under the name instead of in columns: always on iPhone, and on
    /// the Mac when the columns (which grow with the interface size) would leave the name too little room.
    private var stacksRows: Bool {
        #if os(iOS)
        true
        #else
        width < FolderItemView.kindWidth + FolderItemView.dateWidth * 2 + Metrics.scaled(200)
        #endif
    }

    private func folderItem(_ folder: FolderListing.Folder, layout: FolderLayout) -> some View {
        FolderItemView(
            layout: layout, compact: stacksRows, symbol: "folder.fill", tint: theme.accent,
            title: folder.name, detail: FolderListing.counted(folder.itemCount, "item"),
            date: friendlyModified(folder.modified, today: model.today),
            // A folder's dates are its newest edit and its newest file, so it sorts the way its rows do.
            created: friendlyModified(folder.created, today: model.today), createdFirst: createdFirst, showsChevron: true
        ) { go(.folder(folder.path)) }
            .contextMenu {
                WorkspaceOpenButtons(store: workspace, item: .folder(folder.path))
                newItemButtons(model: model, folder: folder.path, kinds: kinds)
            }
    }

    private func fileItem(_ file: VaultFile, layout: FolderLayout) -> some View {
        FolderItemView(
            layout: layout, compact: stacksRows, symbol: fileIcon(file.kind), tint: FileLook.tint(file.kind, theme: theme),
            title: file.title, detail: FileLook.label(file.kind),
            date: friendlyModified(file.lastEdited, today: model.today),
            created: friendlyModified(file.created, today: model.today), createdFirst: createdFirst, showsChevron: false,
            isSelected: file.path == selectedPath
        ) { go(.file(file.path)) }
            .contextMenu {
                Button("Open") { go(.file(file.path)) }
                WorkspaceOpenButtons(store: workspace, item: .file(file.path))
                Divider()
                newItemButtons(model: model, folder: path, kinds: kinds)
                Divider()
                Button("Rename…") { model.pendingFileRename = file.path }
                Button("Delete…", role: .destructive) { pendingDelete = file }
            }
    }
}

/// One step of the path at the top of a folder.
private struct CrumbButton: View {
    let name: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.perchTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.perchCaption.weight(.medium))
                .foregroundStyle(hovering ? theme.accent : theme.textSecondary)
                .underline(hovering, color: theme.accent.opacity(0.5))
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .motion(Motion.quick, value: hovering)
        .accessibilityHint("Opens this folder")
    }
}

/// "Today, 14:05", "Yesterday", "Oct 12": when something was created or last changed.
func friendlyModified(_ date: Date?, today: String) -> String {
    guard let date else { return "" }
    let day = DayMath.string(from: date)
    if day == today { return "Today, \(date.formatted(date: .omitted, time: .shortened))" }
    return friendlyDate(day, today: today)
}

/// A folder or file, as a card in the grid or a row in the list.
private struct FolderItemView: View {
    static var kindWidth: CGFloat { Metrics.scaled(110) }
    static var dateWidth: CGFloat { Metrics.scaled(130) }

    let layout: FolderLayout
    var compact = FolderItemView.compactByDefault
    /// Rows are bare until hovered; a row standing on its own gets a card behind it.
    var filled = false
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    /// When it was last edited.
    let date: String
    /// When it was created; for a folder, when its newest file was.
    var created = ""
    /// Name the created date before the edited one, when the folder is sorted or filtered by it.
    var createdFirst = false
    let showsChevron: Bool
    /// The file showing in the pane beside the browser.
    var isSelected = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.perchTheme) private var theme

    private static var compactByDefault: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    private var isCard: Bool { layout == .grid || filled }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous) }

    var body: some View {
        Button(action: action) {
            Group {
                if layout == .grid { card } else { row }
            }
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(isSelected ? theme.accent.opacity(0.7) : (isCard ? (hovering ? theme.accent.opacity(0.55) : theme.border) : Color.clear), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(PerchPressStyle())
        .onHover { hovering = $0 }
        .motion(Motion.quick, value: hovering)
        .motion(Motion.quick, value: isSelected)
        .lift(hovering && layout == .grid, scale: 1.015)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        // Labelled on the button itself, so VoiceOver keeps its press action.
        .accessibilityLabel(([title, detail] + datesNamed).filter { !$0.isEmpty }.joined(separator: ", "))
    }

    private var fill: Color {
        if isSelected { return theme.accentSoft }
        if isCard { return theme.surface }
        return hovering ? theme.wash : .clear
    }

    private func icon(_ size: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.perchFixed(size: size * 0.48, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: Metrics.scaled(size), height: Metrics.scaled(size))
            .background(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(tint.opacity(0.15)))
    }

    /// "Edited Today, 14:05", "Created Oct 12": in the order the folder is sorted by.
    private var datesNamed: [String] {
        guard !created.isEmpty else { return [date] }
        let edited = date.isEmpty ? "" : "Edited \(date)"
        let made = "Created \(created)"
        return createdFirst ? [made, edited] : [edited, made]
    }

    private var caption: String { ([detail] + datesNamed).filter { !$0.isEmpty }.joined(separator: " · ") }

    /// The icon beside the name, with the details straight under it, so a short name leaves no hole.
    private var card: some View {
        HStack(alignment: .center, spacing: Metrics.gap - 2) {
            icon(36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.perchHeading)
                    .foregroundStyle(theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(caption).font(.perchCaption).foregroundStyle(theme.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(Metrics.cardPadding)
        .frame(maxWidth: .infinity, minHeight: Metrics.row(72), alignment: .leading)
    }

    private var row: some View {
        HStack(spacing: Metrics.gap) {
            icon(compact ? 32 : 26)
            if compact {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.perchRow).foregroundStyle(theme.text).lineLimit(1)
                    Text(caption).font(.perchCaption).foregroundStyle(theme.textSecondary).lineLimit(1)
                }
                Spacer(minLength: Metrics.tightGap)
                if showsChevron {
                    Image(systemName: "chevron.right").font(.perchFixed(size: 11, weight: .semibold)).foregroundStyle(theme.textMuted)
                }
            } else {
                Text(title).font(.perchBody).foregroundStyle(theme.text).lineLimit(1)
                Spacer(minLength: Metrics.tightGap)
                Text(detail).font(.perchCaption).foregroundStyle(theme.textSecondary).lineLimit(1)
                    .frame(width: Self.kindWidth, alignment: .leading)
                Text(created).font(.perchCaption).foregroundStyle(theme.textSecondary).lineLimit(1).monospacedDigit()
                    .frame(width: Self.dateWidth, alignment: .trailing)
                Text(date).font(.perchCaption).foregroundStyle(theme.textSecondary).lineLimit(1).monospacedDigit()
                    .frame(width: Self.dateWidth, alignment: .trailing)
            }
        }
        .padding(.horizontal, Metrics.cardPadding - 2)
        .padding(.vertical, Metrics.dense(compact ? 9 : 6))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Public wrapper, so the iPhone app can push a folder onto its own stack.
public struct FolderHost: View {
    @ObservedObject var model: AppModel
    let path: String
    let kinds: Set<VaultFileKind>
    let rootTitle: String
    let open: ((Route) -> Void)?

    /// - Parameters:
    ///   - kinds: Only these kinds are listed, and only folders holding some of them.
    ///   - rootTitle: What the top level is called, in the title and the path.
    ///   - open: Called with `.folder` or `.file` when something is tapped.
    ///     Leave it out to change `model.route` instead.
    public init(
        model: AppModel, path: String,
        kinds: Set<VaultFileKind> = FolderListing.browsableKinds,
        rootTitle: String = "Notes", open: ((Route) -> Void)? = nil
    ) {
        self.model = model
        self.path = path
        self.kinds = kinds
        self.rootTitle = rootTitle
        self.open = open
    }

    public var body: some View {
        FolderScreen(model: model, path: path, kinds: kinds, rootTitle: rootTitle, open: open)
    }
}
