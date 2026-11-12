import PerchKit
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
import UIKit.UIGestureRecognizerSubclass
#endif

// EXPERIMENTAL: tabs and split view. What is drawn when the setting is on: a slim strip of tabs above
// each pane, one pane or two with a line to drag between them, and the menus that go with them.
// See Workspace.swift in PerchKit for the model and for how to remove the feature.

// MARK: - The panes

/// One pane or two, each under its strip of tabs. The app says what a tab's place looks like.
struct WorkspaceView<Content: View>: View {
    @ObservedObject var store: WorkspaceStore
    /// True keeps the panes the way the user split them where that fits (the Mac). False picks by
    /// the room alone: side by side where two fit, else one above the other (a phone, where turning
    /// it is how you choose).
    var honorsAxis: Bool
    var minimumWidth: Double
    var minimumHeight: Double
    /// Draws a tab's place. Told whether its pane has the focus, and the pane's size.
    @ViewBuilder var content: (WorkspaceTab, Bool, CGSize) -> Content

    /// The first pane's length while the divider is being dragged.
    @State private var dragLength: Double?
    @State private var name = ""
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let workspace = store.workspace
            let arrangement = WorkspaceLayout.arrangement(
                width: size.width, height: size.height, isSplit: workspace.isSplit,
                preferred: honorsAxis ? workspace.axis : nil, minimumWidth: minimumWidth, minimumHeight: minimumHeight
            )
            Group {
                switch arrangement {
                case .single:
                    pane(workspace.focus, size: size, arrangement: arrangement)
                case .sideBySide:
                    let first = dragLength ?? WorkspaceLayout.firstLength(total: size.width, fraction: workspace.fraction, minimum: minimumWidth)
                    HStack(spacing: 0) {
                        pane(0, size: CGSize(width: first, height: size.height), arrangement: arrangement)
                            .frame(width: first)
                        WorkspaceDivider(store: store, axis: .horizontal, length: first, total: size.width, minimum: minimumWidth, dragLength: $dragLength)
                        pane(1, size: CGSize(width: size.width - first - 1, height: size.height), arrangement: arrangement)
                    }
                case .stacked:
                    let first = dragLength ?? WorkspaceLayout.firstLength(total: size.height, fraction: workspace.fraction, minimum: minimumHeight)
                    VStack(spacing: 0) {
                        pane(0, size: CGSize(width: size.width, height: first), arrangement: arrangement)
                            .frame(height: first)
                        WorkspaceDivider(store: store, axis: .vertical, length: first, total: size.height, minimum: minimumHeight, dragLength: $dragLength)
                        pane(1, size: CGSize(width: size.width, height: size.height - first - 1), arrangement: arrangement)
                    }
                }
            }
            .motion(Motion.smooth, value: arrangement)
        }
        .background(theme.background)
        .alert(
            promptTitle,
            isPresented: Binding(get: { store.prompt != nil }, set: { if !$0 { store.prompt = nil } }),
            presenting: store.prompt
        ) { prompt in
            TextField("Name", text: $name)
            Button(prompt == .saveAs ? "Save" : "Rename") {
                switch prompt {
                case .saveAs: store.saveWorkspace(as: name)
                case let .rename(old): store.renameWorkspace(old, to: name)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { prompt in
            Text(prompt == .saveAs
                ? "Saves which tabs are open and how the panes are split, so you can come back to this layout. A name already in use is replaced."
                : "A new name for this saved workspace.")
        }
        .onChange(of: store.prompt) { _, prompt in
            if case let .rename(old)? = prompt { name = old } else if prompt != nil { name = "" }
        }
    }

    private var promptTitle: String {
        if case .rename = store.prompt { return "Rename workspace" }
        return "Save workspace as"
    }

    @ViewBuilder
    private func pane(_ index: Int, size: CGSize, arrangement: WorkspaceLayout.Arrangement) -> some View {
        let workspace = store.workspace
        if workspace.panes.indices.contains(index) {
            let pane = workspace.panes[index]
            let focused = workspace.focus == index
            let tab = pane.selected
            let stripHeight = WorkspaceTabStrip.height
            let contentSize = CGSize(width: size.width, height: max(size.height - stripHeight, 0))
            VStack(spacing: 0) {
                WorkspaceTabStrip(
                    store: store, paneIndex: index, pane: pane, isFocused: focused,
                    hidesOtherPane: workspace.isSplit && arrangement == .single, offersAxis: honorsAxis
                )
                ZStack {
                    Group {
                        if tab.isMissing {
                            WorkspaceMissingView(store: store, tab: tab)
                        } else {
                            content(tab, focused, contentSize)
                        }
                    }
                    .id(tab.id)
                    .transition(.perchSwap(reduceMotion: reduceMotion))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .motion(Motion.smooth, value: tab.id)
                #if os(macOS)
                // The Mac has one toolbar for the window. On the iPhone each pane has its own bar.
                .environment(\.perchPaneOwnsToolbar, focused)
                #endif
                .modifier(PaneDropTarget(store: store, paneIndex: index, size: contentSize, splitAxes: honorsAxis ? [.horizontal, .vertical] : [.horizontal]))
            }
            .background(PaneAnchor { button in
                store.draggingTab = nil
                if button != 2 { store.focus(pane: index) }
                return false
            })
            .accessibilityElement(children: .contain)
            .accessibilityLabel(workspace.isSplit ? "\(WorkspaceStore.paneName(index, axis: arrangement == .stacked ? .vertical : .horizontal)) pane" : "")
        }
    }
}

/// What a tab shows when its file has gone.
private struct WorkspaceMissingView: View {
    @ObservedObject var store: WorkspaceStore
    let tab: WorkspaceTab

    var body: some View {
        EmptyState(
            symbol: "questionmark.folder", title: "“\(tab.title)” was moved or deleted",
            message: "It may have been renamed or removed on another device. If it comes back after a sync, this tab will show it again.",
            actionTitle: "Close Tab", action: { store.close(tab.id) }
        )
        .perchScreenBackground()
    }
}

// MARK: - The divider

/// The line between two panes. Drag it to give one side more room.
private struct WorkspaceDivider: View {
    @ObservedObject var store: WorkspaceStore
    /// `.horizontal` is two panes side by side: an upright line dragged left and right.
    let axis: SplitAxis
    /// The first pane's length now, and the room for both.
    let length: Double
    let total: Double
    let minimum: Double
    @Binding var dragLength: Double?
    @State private var dragStart: Double?
    @State private var hovering = false
    @Environment(\.perchTheme) private var theme
    @Environment(\.layoutDirection) private var direction

    #if os(iOS)
    private static let grip: CGFloat = 24
    #else
    private static let grip: CGFloat = 11
    #endif

    var body: some View {
        let upright = axis == .horizontal
        let active = dragLength != nil || hovering
        Rectangle().fill(active ? theme.accent : theme.hairline)
            .frame(width: upright ? 1 : nil, height: upright ? nil : 1)
            .overlay {
                Capsule().fill(active ? theme.accent : theme.textMuted.opacity(0.45))
                    .frame(width: upright ? 4 : 34, height: upright ? 34 : 4)
                    #if os(macOS)
                    .opacity(active ? 1 : 0)
                    #endif
            }
            .overlay {
                Color.clear
                    .frame(width: upright ? Self.grip : nil, height: upright ? nil : Self.grip)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        hovering = inside
                        #if os(macOS)
                        if inside { (upright ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() } else { NSCursor.pop() }
                        #endif
                    }
                    .gesture(
                        DragGesture(minimumDistance: 2, coordinateSpace: .global)
                            .onChanged { value in
                                let moved = upright ? value.translation.width * (direction == .rightToLeft ? -1 : 1) : value.translation.height
                                let start = dragStart ?? length
                                dragStart = start
                                dragLength = settled(start + moved)
                            }
                            .onEnded { _ in
                                if let dragLength { store.setFraction(WorkspaceLayout.fraction(firstLength: dragLength, total: total, minimum: minimum)) }
                                dragLength = nil
                                dragStart = nil
                            }
                    )
            }
            .motion(Motion.quick, value: active)
            .zIndex(2)
            .accessibilityElement()
            .accessibilityLabel("Pane divider")
            .accessibilityValue("\(Int((length / max(total, 1)) * 100)) percent for the \(WorkspaceStore.paneName(0, axis: axis).lowercased()) pane")
            .accessibilityAdjustableAction { change in
                store.setFraction(store.workspace.fraction + (change == .increment ? 0.05 : -0.05))
            }
    }

    /// A length the panes can really have: neither under the minimum.
    private func settled(_ wanted: Double) -> Double {
        WorkspaceLayout.firstLength(total: total, fraction: WorkspaceLayout.fraction(firstLength: wanted, total: total, minimum: minimum), minimum: minimum)
    }
}

// MARK: - The strip of tabs

/// A pane's tabs: an icon and a name each, a dot for a note with unsaved typing, a close button; then
/// "+" and a menu listing every tab, the split, and saved workspaces.
struct WorkspaceTabStrip: View {
    @ObservedObject var store: WorkspaceStore
    let paneIndex: Int
    let pane: WorkspacePane
    let isFocused: Bool
    /// The workspace has a second pane that there is no room to show.
    let hidesOtherPane: Bool
    /// Offers "Split Down" as well as "Split Right": the Mac, where the user picks the way.
    let offersAxis: Bool
    @ObservedObject private var dirt = NoteDirt.shared
    /// The tab a dragged tab would land before. `pane.tabs.count` is the end.
    @State private var dropIndex: Int?
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var height: CGFloat {
        #if os(iOS)
        max(Metrics.row(40), 40)
        #else
        Metrics.row(30)
        #endif
    }

    var body: some View {
        let tab = pane.selected
        HStack(spacing: 0) {
            StripButton(symbol: "chevron.backward", label: "Back", isEnabled: tab.canGoBack) { act { store.goBack() } }
            StripButton(symbol: "chevron.forward", label: "Forward", isEnabled: tab.canGoForward) { act { store.goForward() } }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(pane.tabs.enumerated()), id: \.element.id) { index, tab in
                            chip(tab, index: index)
                        }
                        // The empty end of the strip: a tab dropped here goes last.
                        Color.clear
                            .frame(minWidth: 28, maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(alignment: .leading) { insertionMark(at: pane.tabs.count) }
                            .contentShape(Rectangle())
                            .onDrop(of: [.plainText], delegate: TabDropDelegate(store: store, paneIndex: paneIndex, index: pane.tabs.count, dropIndex: $dropIndex))
                    }
                    .padding(.horizontal, 3)
                    .frame(maxHeight: .infinity)
                }
                // A turn later, so a tab that has only just been added is there to scroll to.
                .onChange(of: pane.selectedID, initial: true) { _, id in
                    DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center) }
                }
                .onChange(of: pane.tabs.count) { _, _ in
                    let id = pane.selectedID
                    DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(store.workspace.isSplit ? "\(WorkspaceStore.paneName(paneIndex, axis: store.workspace.axis)) pane tabs" : "Tabs")
            .accessibilityAddTraits(.isTabBar)
            if hidesOtherPane {
                StripButton(symbol: "rectangle.2.swap", label: "Show the other pane") { store.focusOtherPane() }
                    .help("The window is too small to show both panes. Show the other one.")
            }
            StripButton(symbol: "plus", label: "New tab") { act { store.newTab() } }
                .help("New tab")
            menu
        }
        .frame(height: Self.height)
        .background(theme.sidebar)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline).frame(height: 1) }
        .motion(Motion.smooth, value: pane.tabs.map(\.id))
        .motion(Motion.quick, value: dropIndex)
    }

    /// Runs something that acts on the focused pane, making this pane that one first. A click has
    /// already done so; VoiceOver and Full Keyboard Access have not.
    private func act(_ body: () -> Void) {
        store.focus(pane: paneIndex)
        body()
    }

    private func chip(_ tab: WorkspaceTab, index: Int) -> some View {
        let selected = tab.id == pane.selectedID
        let unsaved = tab.item.filePath.map(dirt.paths.contains) ?? false
        return TabChip(
            tab: tab, isSelected: selected, isFocused: isFocused, isUnsaved: unsaved, marksFocus: store.workspace.isSplit,
            select: { withMotion(Motion.quick, reduceMotion: reduceMotion) { store.select(tab.id) } },
            close: { withMotion(Motion.smooth, reduceMotion: reduceMotion) { store.close(tab.id) } }
        )
        .id(tab.id)
        .overlay(alignment: .leading) { insertionMark(at: index) }
        .onDrag {
            store.draggingTab = tab.id
            return NSItemProvider(object: ("perch-tab:" + tab.id) as NSString)
        } preview: {
            TabDragPreview(tab: tab).environment(\.perchTheme, theme)
        }
        .onDrop(of: [.plainText], delegate: TabDropDelegate(store: store, paneIndex: paneIndex, index: index, dropIndex: $dropIndex))
        .contextMenu {
            Button("Close Tab") { store.close(tab.id) }
            Button("Close Other Tabs") { store.closeOthers(keeping: tab.id) }.disabled(pane.tabs.count < 2)
            Divider()
            Button("Duplicate Tab") { store.duplicate(tab.id) }
            if store.workspace.isSplit {
                Button("Move to Other Pane") { store.move(tab.id, toPane: 1 - paneIndex) }
            } else {
                Button("Move to the Side") { store.move(tab.id, toPane: 1, axis: .horizontal) }.disabled(pane.tabs.count < 2)
            }
        }
        .accessibilityHint("Tab \(index + 1) of \(pane.tabs.count)")
    }

    /// The bar that shows where a dragged tab would land.
    @ViewBuilder
    private func insertionMark(at index: Int) -> some View {
        if dropIndex == index, store.draggingTab != nil {
            Capsule().fill(theme.accent).frame(width: 2).padding(.vertical, 5).offset(x: -2).transition(.opacity)
        }
    }

    private var menu: some View {
        Menu {
            Section {
                ForEach(pane.tabs) { tab in
                    Button { store.select(tab.id) } label: {
                        Label(tab.title, systemImage: tab.id == pane.selectedID ? "checkmark" : tab.symbol)
                    }
                }
            }
            Section {
                Button { act { store.newTab() } } label: { Label("New Tab", systemImage: "plus") }
                Button { store.reopenClosedTab() } label: { Label("Reopen Closed Tab", systemImage: "arrow.uturn.backward") }
                    .disabled(!store.workspace.canReopen)
                Button { store.closeOthers(keeping: pane.selectedID) } label: { Label("Close Other Tabs", systemImage: "xmark") }
                    .disabled(pane.tabs.count < 2)
            }
            Section {
                if store.workspace.isSplit {
                    Button { store.move(pane.selectedID, toPane: 1 - paneIndex) } label: { Label("Move Tab to Other Pane", systemImage: "arrow.left.arrow.right") }
                    if offersAxis {
                        let stacked = store.workspace.axis == .vertical
                        Button { store.split(stacked ? .horizontal : .vertical) } label: {
                            Label(stacked ? "Panes Side by Side" : "Panes One Above the Other", systemImage: stacked ? "rectangle.split.2x1" : "rectangle.split.1x2")
                        }
                    }
                    Button { store.closeSplit() } label: { Label("Close Split", systemImage: "rectangle") }
                } else {
                    Button { act { store.split(.horizontal) } } label: { Label(offersAxis ? "Split Right" : "Open to the Side", systemImage: "rectangle.split.2x1") }
                    if offersAxis {
                        Button { act { store.split(.vertical) } } label: { Label("Split Down", systemImage: "rectangle.split.1x2") }
                    }
                }
            }
            Section("Workspaces") {
                ForEach(store.saved.items) { saved in
                    Button { store.showWorkspace(saved.name) } label: { Label(saved.name, systemImage: "rectangle.3.group") }
                }
                Button { store.prompt = .saveAs } label: { Label("Save Workspace As…", systemImage: "square.and.arrow.down") }
                if !store.saved.items.isEmpty {
                    Menu("Rename") {
                        ForEach(store.saved.items) { saved in Button(saved.name) { store.prompt = .rename(saved.name) } }
                    }
                    Menu("Delete") {
                        ForEach(store.saved.items) { saved in Button(saved.name, role: .destructive) { store.deleteWorkspace(saved.name) } }
                    }
                }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.perchFixed(size: StripButton.iconSize, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
                .frame(width: StripButton.width, height: Self.height)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("All tabs, split view and saved workspaces")
        .accessibilityLabel("Tabs and split view")
    }
}

/// A small icon button at either end of the strip.
private struct StripButton: View {
    let symbol: String
    let label: String
    var isEnabled = true
    var action: () -> Void
    @State private var hovering = false
    @Environment(\.perchTheme) private var theme

    #if os(iOS)
    static let iconSize: CGFloat = 13
    static var width: CGFloat { max(Metrics.scaled(36), 36) }
    #else
    static let iconSize: CGFloat = 10.5
    static var width: CGFloat { Metrics.scaled(26) }
    #endif

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.perchFixed(size: Self.iconSize, weight: .semibold))
                .foregroundStyle(isEnabled ? theme.textSecondary : theme.textMuted.opacity(0.45))
                .frame(width: Self.width - 4, height: WorkspaceTabStrip.height - 8)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovering && isEnabled ? theme.wash : Color.clear))
                .frame(width: Self.width, height: WorkspaceTabStrip.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering = $0 }
        .motion(Motion.quick, value: hovering)
        .accessibilityLabel(label)
    }
}

/// One tab.
private struct TabChip: View {
    let tab: WorkspaceTab
    let isSelected: Bool
    /// Its pane has the focus.
    let isFocused: Bool
    let isUnsaved: Bool
    /// With two panes on screen, the front tab of the focused one is underlined, so it is plain which
    /// pane the sidebar and the shortcuts are talking to.
    let marksFocus: Bool
    var select: () -> Void
    var close: () -> Void
    @State private var hovering = false
    @Environment(\.perchTheme) private var theme

    #if os(iOS)
    private static let iconSize: CGFloat = 13.5
    private static let closeSize: CGFloat = 26
    private static var maxWidth: CGFloat { Metrics.scaled(190) }
    #else
    private static let iconSize: CGFloat = 11.5
    private static let closeSize: CGFloat = 16
    private static var maxWidth: CGFloat { Metrics.scaled(180) }
    #endif

    /// The close button shows under the pointer, and always on the tab in front where there is no pointer.
    private var showsClose: Bool {
        #if os(iOS)
        isSelected || hovering
        #else
        hovering
        #endif
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: tab.symbol)
                .font(.perchFixed(size: Self.iconSize, weight: .medium))
                .foregroundStyle(tab.isMissing ? theme.textMuted : (isSelected && isFocused ? theme.accent : theme.textSecondary))
            Text(tab.title)
                .font(.perchCaption.weight(isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? theme.text : theme.textSecondary)
                .strikethrough(tab.isMissing, color: theme.textMuted)
                .lineLimit(1)
                .truncationMode(.tail)
            ZStack {
                if showsClose {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.perchFixed(size: 8.5, weight: .bold))
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: Self.closeSize, height: Self.closeSize)
                            .background(Circle().fill(theme.washStrong).padding(Self.closeSize > 20 ? 4 : 0))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Close tab")
                    .transition(.opacity)
                } else if isUnsaved {
                    Circle().fill(theme.accent).frame(width: 6, height: 6).transition(.opacity)
                }
            }
            .frame(width: Self.closeSize, height: Self.closeSize)
        }
        .padding(.leading, 8)
        .padding(.trailing, 3)
        .frame(maxWidth: Self.maxWidth)
        .frame(height: WorkspaceTabStrip.height - 8)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill))
        .overlay(alignment: .bottom) {
            if marksFocus, isSelected, isFocused {
                Capsule().fill(theme.accent).frame(height: 2).padding(.horizontal, 8).offset(y: 3).transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hovering = $0 }
        #if os(macOS)
        // Middle-click closes, as it does in a browser.
        .background(PaneAnchor { button in
            guard button == 2 else { return false }
            close()
            return true
        })
        #else
        // A flick up closes; the strip still scrolls sideways under the same finger.
        .simultaneousGesture(
            DragGesture(minimumDistance: 16).onEnded { value in
                if value.translation.height < -28, abs(value.translation.height) > abs(value.translation.width) * 1.5 { close() }
            }
        )
        #endif
        .motion(Motion.quick, value: hovering)
        .motion(Motion.quick, value: isSelected)
        .motion(Motion.quick, value: isFocused)
        .motion(Motion.quick, value: isUnsaved)
        .help(tab.isMissing ? "\(tab.title) was moved or deleted" : tab.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.title + (isUnsaved ? ", unsaved changes" : "") + (tab.isMissing ? ", moved or deleted" : ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, select)
        .accessibilityAction(named: "Close tab", close)
    }

    private var fill: Color {
        if isSelected { return isFocused ? theme.accentSoft : theme.wash }
        return hovering ? theme.wash : .clear
    }
}

/// What follows the pointer while a tab is dragged.
private struct TabDragPreview: View {
    let tab: WorkspaceTab
    @Environment(\.perchTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tab.symbol).font(.perchFixed(size: 12, weight: .medium)).foregroundStyle(theme.accent)
            Text(tab.title).font(.perchCaption.weight(.medium)).foregroundStyle(theme.text).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
    }
}

// MARK: - Dragging tabs

/// A tab dropped on another tab lands before it; on the end of the strip, last. Only tabs are
/// accepted: `validateDrop` is false for anything else, so a task being dragged is never taken.
private struct TabDropDelegate: DropDelegate {
    let store: WorkspaceStore
    let paneIndex: Int
    let index: Int
    @Binding var dropIndex: Int?

    func validateDrop(info: DropInfo) -> Bool { store.draggingTab != nil }
    func dropEntered(info: DropInfo) { dropIndex = index }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func dropExited(info: DropInfo) { if dropIndex == index { dropIndex = nil } }

    func performDrop(info: DropInfo) -> Bool {
        dropIndex = nil
        guard let id = store.draggingTab else { return false }
        store.draggingTab = nil
        store.move(id, toPane: paneIndex, at: index)
        return true
    }
}

/// Where over a pane's content a dragged tab is: an edge splits the workspace that way, and the
/// middle (or anywhere, once there are two panes) moves the tab into this pane.
private enum PaneDropZone: Equatable {
    case leading, trailing, bottom, whole

    static func zone(at point: CGPoint, in size: CGSize, isSplit: Bool, axes: Set<SplitAxis>) -> PaneDropZone? {
        guard !isSplit else { return .whole }
        guard size.width > 0, size.height > 0 else { return nil }
        if axes.contains(.horizontal), point.x < size.width * 0.3 { return .leading }
        if axes.contains(.horizontal), point.x > size.width * 0.7 { return .trailing }
        if axes.contains(.vertical), point.y > size.height * 0.65 { return .bottom }
        return nil
    }
}

/// Lets a tab be dropped on a pane's content, and shows where it would go.
private struct PaneDropTarget: ViewModifier {
    @ObservedObject var store: WorkspaceStore
    let paneIndex: Int
    let size: CGSize
    let splitAxes: Set<SplitAxis>
    @State private var zone: PaneDropZone?
    @Environment(\.perchTheme) private var theme

    func body(content: Content) -> some View {
        content
            .overlay {
                if let zone, store.draggingTab != nil {
                    highlight(zone).transition(.opacity)
                }
            }
            .motion(Motion.quick, value: zone)
            .onDrop(of: [.plainText], delegate: Delegate(store: store, paneIndex: paneIndex, size: size, axes: splitAxes, zone: $zone))
    }

    private func highlight(_ zone: PaneDropZone) -> some View {
        let alignment: Alignment
        var width: CGFloat? = nil
        var height: CGFloat? = nil
        switch zone {
        case .leading: (alignment, width) = (.leading, size.width / 2)
        case .trailing: (alignment, width) = (.trailing, size.width / 2)
        case .bottom: (alignment, height) = (.bottom, size.height / 2)
        case .whole: alignment = .center
        }
        return RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
            .fill(theme.accentSoft)
            .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(theme.accent.opacity(0.6), lineWidth: 1.5))
            .frame(width: width, height: height)
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private struct Delegate: DropDelegate {
        let store: WorkspaceStore
        let paneIndex: Int
        let size: CGSize
        let axes: Set<SplitAxis>
        @Binding var zone: PaneDropZone?

        private func zone(_ info: DropInfo) -> PaneDropZone? {
            PaneDropZone.zone(at: info.location, in: size, isSplit: store.workspace.isSplit, axes: axes)
        }

        func validateDrop(info: DropInfo) -> Bool { store.draggingTab != nil }
        func dropEntered(info: DropInfo) { zone = zone(info) }
        func dropExited(info: DropInfo) { zone = nil }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            let now = zone(info)
            if now != zone { zone = now }
            return DropProposal(operation: now == nil ? .forbidden : .move)
        }

        func performDrop(info: DropInfo) -> Bool {
            let target = zone(info)
            zone = nil
            guard let id = store.draggingTab, let target else { return false }
            store.draggingTab = nil
            switch target {
            case .whole: store.move(id, toPane: paneIndex)
            case .trailing: store.move(id, toPane: 1, axis: .horizontal)
            case .bottom: store.move(id, toPane: 1, axis: .vertical)
            case .leading: store.splitLeading(id)
            }
            return true
        }
    }
}

extension WorkspaceStore {
    /// A tab dragged to the leading edge: it becomes the first pane, and the rest the second.
    func splitLeading(_ id: String) {
        guard !workspace.isSplit, workspace.panes[0].tabs.count > 1 else { return }
        move(id, toPane: 1, axis: .horizontal)
        swapPanes()
    }
}

// MARK: - Focus follows the pointer going down

#if os(macOS)
/// Sits behind a pane (or a tab) and hears every mouse button going down inside it, before the view
/// that was clicked does. That is how a pane takes the focus first, so whatever the click does next
/// (opens a note, picks a view) lands in the pane it was made in. It never takes a click itself.
struct PaneAnchor: NSViewRepresentable {
    /// Called with the button number: 0 left, 1 right, 2 middle. True swallows the click.
    var onDown: (Int) -> Bool

    func makeNSView(context: Context) -> AnchorView { AnchorView() }
    func updateNSView(_ view: AnchorView, context: Context) { view.onDown = onDown }

    final class AnchorView: NSView {
        var onDown: ((Int) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                guard let self, event.window === self.window, self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                return self.onDown?(event.buttonNumber) == true ? nil : event
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// The shortcuts that have to be heard before the menus: ⌘W, which is otherwise Close Window, and
/// ⌃Tab and ⌃⇧Tab, which a text view would otherwise take.
struct WorkspaceKeys: NSViewRepresentable {
    let store: WorkspaceStore

    func makeNSView(context: Context) -> KeysView { KeysView(store: store) }
    func updateNSView(_ view: KeysView, context: Context) {}

    final class KeysView: NSView {
        let store: WorkspaceStore
        private var monitor: Any?

        init(store: WorkspaceStore) {
            self.store = store
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.store.isActive, event.window === self.window, self.window?.isKeyWindow == true, self.window?.attachedSheet == nil else { return event }
                let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
                // ⌘W closes the tab in front. With one tab left it is Close Window, as it always was.
                if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "w", self.store.workspace.tabCount > 1 {
                    self.store.closeFocusedTab()
                    return nil
                }
                if event.keyCode == 48, flags == .control || flags == [.control, .shift] {
                    self.store.selectAdjacent(flags.contains(.shift) ? -1 : 1)
                    return nil
                }
                return event
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
#else
/// Sits behind a pane and hears every touch that begins inside it, before the view that was touched
/// acts: a recognizer on the window that sees touches begin and never recognizes anything. That is how
/// a pane takes the focus first, so what the tap does next lands in the pane it was made in.
struct PaneAnchor: UIViewRepresentable {
    /// Called with 0. The result is ignored: a touch is never swallowed.
    var onDown: (Int) -> Bool

    func makeUIView(context: Context) -> AnchorView { AnchorView() }
    func updateUIView(_ view: AnchorView, context: Context) { view.onDown = onDown }

    final class AnchorView: UIView {
        var onDown: ((Int) -> Bool)?
        private var recognizer: TouchDown?
        private weak var host: UIWindow?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let recognizer { host?.removeGestureRecognizer(recognizer) }
            recognizer = nil
            host = window
            guard let window else { return }
            let recognizer = TouchDown { [weak self] touch in
                guard let self, let window = self.window else { return }
                // A sheet is drawn in the same window, over the panes. A touch in it is not a touch in a pane.
                if let root = window.rootViewController?.view, let touched = touch.view, !touched.isDescendant(of: root) { return }
                if self.bounds.contains(touch.location(in: self)) { _ = self.onDown?(0) }
            }
            window.addGestureRecognizer(recognizer)
            self.recognizer = recognizer
        }
    }

    final class TouchDown: UIGestureRecognizer {
        private let began: (UITouch) -> Void

        init(began: @escaping (UITouch) -> Void) {
            self.began = began
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            if let touch = touches.first { began(touch) }
            state = .failed
        }

        override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
        override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    }
}
#endif

// MARK: - Menus elsewhere in the app

/// "Open in New Tab" and "Open to the Side", for a row's context menu. Nothing where there is no
/// workspace on screen: tabs are off, or this is a phone-sized layout.
struct WorkspaceOpenButtons: View {
    let store: WorkspaceStore?
    let item: WorkspaceItem?

    var body: some View {
        if let store, let item, store.isActive {
            Button { store.open(item, in: .newTab) } label: { Label("Open in New Tab", systemImage: "plus.rectangle.on.rectangle") }
            Button { store.open(item, in: .otherPane) } label: { Label("Open to the Side", systemImage: "rectangle.split.2x1") }
            Divider()
        }
    }
}

private struct WorkspaceOpenMenu: ViewModifier {
    let store: WorkspaceStore?
    let item: WorkspaceItem?

    func body(content: Content) -> some View {
        if let store, let item {
            content.contextMenu { WorkspaceOpenButtons(store: store, item: item) }
        } else {
            content
        }
    }
}

extension View {
    /// Gives a row with no menu of its own one that opens it in a new tab or to the side, where
    /// there is a workspace. Without one the row is exactly as it was.
    func workspaceOpenMenu(_ store: WorkspaceStore?, _ item: WorkspaceItem?) -> some View {
        modifier(WorkspaceOpenMenu(store: store, item: item))
    }
}

// MARK: - Commands

/// The Tabs menu and its shortcuts, for the Mac and for an iPhone with a keyboard attached.
public struct WorkspaceCommands: Commands {
    @ObservedObject var store: WorkspaceStore

    public init(store: WorkspaceStore) { self.store = store }

    public var body: some Commands {
        CommandMenu("Tabs") {
            // On a phone-sized screen there are no tabs, and everything here is dimmed.
            Group {
                let active = store.isActive
                Button("New Tab") { store.newTab() }.keyboardShortcut("t").disabled(!active)
                // On the Mac ⌘W is heard before the menus (see WorkspaceKeys); this shows the shortcut.
                Button("Close Tab") { store.closeFocusedTab() }.keyboardShortcut("w").disabled(!active || store.workspace.tabCount < 2)
                Button("Reopen Closed Tab") { store.reopenClosedTab() }.keyboardShortcut("t", modifiers: [.command, .shift]).disabled(!active || !store.workspace.canReopen)
                Divider()
                Button("Next Tab") { store.selectAdjacent(1) }.keyboardShortcut("]", modifiers: [.command, .shift]).disabled(!active)
                Button("Previous Tab") { store.selectAdjacent(-1) }.keyboardShortcut("[", modifiers: [.command, .shift]).disabled(!active)
                #if os(iOS)
                Button("Next Tab (Control-Tab)") { store.selectAdjacent(1) }.keyboardShortcut(.tab, modifiers: .control).disabled(!active)
                Button("Previous Tab (Control-Shift-Tab)") { store.selectAdjacent(-1) }.keyboardShortcut(.tab, modifiers: [.control, .shift]).disabled(!active)
                #endif
                Button("Back") { store.goBack() }.keyboardShortcut("[").disabled(!active || !store.workspace.focusedTab.canGoBack)
                Button("Forward") { store.goForward() }.keyboardShortcut("]").disabled(!active || !store.workspace.focusedTab.canGoForward)
                Divider()
                // ⌘\ is Clear Formatting, so the split takes ⌃⌘\.
                Button("Split Right") { store.split(.horizontal) }.keyboardShortcut("\\", modifiers: [.command, .control]).disabled(!active)
                #if os(macOS)
                Button("Split Down") { store.split(.vertical) }.keyboardShortcut("\\", modifiers: [.command, .control, .shift]).disabled(!active)
                #endif
                Button("Focus Other Pane") { store.focusOtherPane() }.keyboardShortcut("\\", modifiers: [.command, .option]).disabled(!active || !store.workspace.isSplit)
                Button("Move Tab to Other Pane") { store.moveFocusedTabAcross() }.disabled(!active || (!store.workspace.isSplit && store.workspace.tabCount < 2))
                Button("Close Split") { store.closeSplit() }.keyboardShortcut("w", modifiers: [.command, .control]).disabled(!active || !store.workspace.isSplit)
                Divider()
                Menu("Workspaces") {
                    ForEach(store.saved.items) { saved in
                        Button(saved.name) { store.showWorkspace(saved.name) }
                    }
                    if !store.saved.items.isEmpty { Divider() }
                    Button("Save Workspace As…") { store.prompt = .saveAs }
                }
                .disabled(!active)
            }
        }
    }
}

// MARK: - The Mac's detail area

/// The Mac window's detail area with tabs and split view on: the workspace, each pane drawing its
/// tab's place with the same screens as without tabs.
public struct WorkspaceDetail: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var model: AppModel
    let settings: AnyView

    public init(store: WorkspaceStore, model: AppModel, settings: AnyView) {
        self.store = store
        self.model = model
        self.settings = settings
    }

    public var body: some View {
        WorkspaceView(store: store, honorsAxis: true, minimumWidth: 280, minimumHeight: 220) { tab, _, _ in
            DetailRouter(model: model, settings: settings, route: tab.item.route)
        }
        #if os(macOS)
        .background(WorkspaceKeys(store: store))
        #endif
        .onAppear { store.activate() }
        .onDisappear { store.deactivate() }
    }
}

// MARK: - The iPhone's wide layout

/// The content of the iPhone's wide layout with tabs and split view on. Each pane draws its tab's
/// place with the pieces the wide layout already uses, told to draw that place and not the app's.
struct PhoneWorkspaceContent: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var model: AppModel
    @ObservedObject var shell: ShellState
    let layout: ShellLayout
    let agents: AnyView
    let tasksAccessory: AnyView?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        WorkspaceView(
            store: store, honorsAxis: false,
            minimumWidth: WorkspaceLayout.minimumPaneWidth, minimumHeight: WorkspaceLayout.minimumPaneHeight
        ) { tab, focused, size in
            pane(tab, focused: focused, size: size)
        }
        .onAppear { store.activate() }
        .onDisappear { store.deactivate() }
    }

    /// The layout as one pane sees it: the same navigation, and only its own room.
    private func paneLayout(_ size: CGSize) -> ShellLayout {
        var pane = layout
        pane.contentWidth = Double(size.width)
        pane.height = Double(size.height)
        return pane
    }

    @ViewBuilder
    private func pane(_ tab: WorkspaceTab, focused: Bool, size: CGSize) -> some View {
        let paneLayout = paneLayout(size)
        switch tab.item {
        case let .tasks(view):
            // The focused pane shows the selected task beside its list where it has the room; with
            // less, or in the other pane, the task opens over the screen.
            let _ = focused ? (shell.workspaceTaskPane = paneLayout.splitsContent) : ()
            WideTasksView(model: model, shell: shell, layout: paneLayout, accessory: tasksAccessory, view: view, showsDetail: focused)
        case let .folder(path):
            let _ = focused ? (shell.workspaceTaskPane = false) : ()
            NavigationStack {
                NotesSectionView(model: model, path: path, showsBars: layout.showsContentBars) { route in
                    if let item = WorkspaceItem(route) {
                        withMotion(Motion.smooth, reduceMotion: reduceMotion) { store.open(item) }
                    }
                }
                .inlineTitle()
            }
        case let .file(path):
            let _ = focused ? (shell.workspaceTaskPane = false) : ()
            NavigationStack {
                FileScreen(model: model, path: path)
            }
        case .search:
            let _ = focused ? (shell.workspaceTaskPane = false) : ()
            NavigationStack {
                VStack(spacing: 0) {
                    FilterField(text: $model.searchQuery, prompt: "Notes, tasks, boards")
                        .padding(.horizontal, Metrics.screenPadding)
                        .padding(.top, 10)
                        .padding(.bottom, 2)
                        .accessibilityLabel("Search")
                    SearchScreen(model: model)
                }
                .inlineTitle()
            }
        case .page(.agents):
            let _ = focused ? (shell.workspaceTaskPane = false) : ()
            agents
        case .page(.insights):
            NavigationStack { InsightsScreen(model: model).inlineTitle() }
        case .page:
            NavigationStack { ActivityScreen(model: model).inlineTitle() }
        }
    }
}

private extension View {
    func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

// MARK: - The setting

/// The switch for tabs and split view, with what it does, for each app's Settings.
public struct ExperimentalSettings: View {
    @AppStorage(WorkspaceStore.settingKey) private var tabsOn = false

    public init() {}

    public var body: some View {
        Section {
            Toggle("Tabs and split view (experimental)", isOn: $tabsOn)
        } header: {
            Text("Experimental")
        } footer: {
            #if os(macOS)
            Text("Adds a strip of tabs above the main pane, and lets it split in two. ⌘T opens a tab, ⌘W closes it, ⌘-click opens anything in a new tab and ⌥⌘-click to the side; ⌃⌘\\ splits. Nothing in your notebook changes, and turning this off puts the window back as it was.")
            #else
            Text("On a wide screen (an open folding phone, a phone on its side), adds tabs above the content and lets two things sit side by side: touch and hold a note, folder or task and choose Open to the Side. A phone-sized screen is unchanged. Nothing in your notebook changes.")
            #endif
        }
    }
}
