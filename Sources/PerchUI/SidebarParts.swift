import PerchKit
import SwiftUI

// The pieces of the sidebar that the Mac's sidebar and the iPhone's wide-screen sidebar both draw:
// which rows there are, and the rows themselves. Each app wraps them in its own chrome (the Mac's
// toolbar and keyboard handling; the iPhone's rail, drawer and footer).

/// A fixed row of the sidebar: a task view, an area, or All notes.
struct SidebarPlace: Identifiable {
    var route: Route
    var title: String
    var symbol: String
    var count = 0
    var alert = false
    var id: Route { route }
}

@MainActor
enum SidebarPlaces {
    /// The row for an area. All areas is the empty name.
    static func areaRow(_ area: String?) -> Route { .area(area ?? "") }

    static let allNotes = SidebarPlace(route: .folder(""), title: "All notes", symbol: "tray.full")

    static func route(for view: TaskViewKind) -> Route { AppModel.route(for: .tasks(view)) }

    /// The task views on offer. Their counts follow the area in scope, like the views themselves.
    static func views(_ model: AppModel, offersBoard: Bool = true) -> [SidebarPlace] {
        let today = model.today
        let scoped = model.scopedTasks
        return TaskViewKind.offered(wide: offersBoard, ready: model.offersReadyView).map { view in
            var count = 0
            switch view {
            case .today: count = scoped.reduce(0) { $0 + ($1.isDueTodayOrEarlier(today: today) && !$1.isOverdue(today: today) ? 1 : 0) }
            case .ready: count = model.scopedReadyToTick.count
            default: break
            }
            return SidebarPlace(route: route(for: view), title: view.title, symbol: view.symbol, count: count)
        }
    }

    /// All, then each area, with open counts and a dot where something is overdue.
    static func areas(_ model: AppModel) -> [SidebarPlace] {
        let counts = TaskScope.counts(model.tasks, today: model.today)
        let scope = model.taskScope
        return [SidebarPlace(route: areaRow(nil), title: "All", symbol: scope == nil ? "tray.full.fill" : "tray.full", count: counts.all.open, alert: counts.all.overdue > 0)]
            + model.visibleAreas.map { area in
                let count = counts.byArea[area] ?? .init()
                return SidebarPlace(route: areaRow(area), title: area, symbol: scope == area ? "circle.inset.filled" : "circle.dashed", count: count.open, alert: count.overdue > 0)
            }
    }
}

/// The rows of one section: in Tasks the views, then the areas and "Edit areas…"; in Notes All notes
/// and the folder tree. Selection, the keyboard's row and what a tap does come from whoever draws it.
struct SidebarRows: View {
    @ObservedObject var model: AppModel
    let section: AppSection
    /// The notes tree's showing rows. Unused in Tasks.
    var entries: [SidebarEntry] = []
    var offersBoard = true
    var isSelected: (Route) -> Bool
    /// The row to draw the keyboard's focus ring on, when the sidebar has the keyboard.
    var focused: Route?
    var select: (Route) -> Void
    var toggle: (String) -> Void
    var editAreas: () -> Void
    /// Tabs: the workspace, where there is one, for "Open in New Tab" in each row's menu.
    @Environment(\.perchWorkspace) private var workspace

    var body: some View {
        Group {
            if section == .tasks {
                ForEach(SidebarPlaces.views(model, offersBoard: offersBoard)) { place($0) }
                SectionLabel("Areas").padding(.leading, 12).padding(.top, 16).padding(.bottom, 4)
                ForEach(SidebarPlaces.areas(model)) { place($0) }
                SidebarRow(title: "Edit areas…", symbol: "plus", inset: 6, select: editAreas)
                    .opacity(0.75)
            } else {
                place(SidebarPlaces.allNotes)
                ForEach(entries) { entry in
                    row(for: entry)
                        .transition(.opacity)
                }
            }
        }
        .transition(.opacity)
    }

    private func place(_ place: SidebarPlace) -> some View {
        SidebarRow(
            title: place.title, symbol: place.symbol, count: place.count, alert: place.alert,
            isSelected: isSelected(place.route), showsFocus: focused == place.route, inset: 6,
            select: { select(place.route) }
        )
        .id(place.route)
        .workspaceOpenMenu(workspace, WorkspaceItem(place.route))
    }

    @ViewBuilder
    private func row(for entry: SidebarEntry) -> some View {
        let selected = isSelected(entry.route)
        switch entry.kind {
        case let .folder(isExpanded):
            let path = entry.folderPath ?? ""
            SidebarRow(
                title: entry.title, symbol: isExpanded ? "folder.fill" : "folder", depth: entry.depth,
                isSelected: selected, showsFocus: focused == entry.route, isExpanded: isExpanded,
                select: { select(entry.route) }, toggle: { toggle(path) }
            )
            .id(entry.route)
            .contextMenu {
                WorkspaceOpenButtons(store: workspace, item: .folder(path))
                Button(isExpanded ? "Collapse" : "Expand") { toggle(path) }
                Divider()
                newItemButtons(model: model, folder: path)
            }
        case let .file(kind):
            SidebarRow(
                title: entry.title, symbol: fileIcon(kind), depth: entry.depth,
                isSelected: selected, showsFocus: focused == entry.route,
                select: { select(entry.route) }
            )
            .id(entry.route)
            .contextMenu {
                Button("Open") { select(entry.route) }
                WorkspaceOpenButtons(store: workspace, item: WorkspaceItem(entry.route))
                Divider()
                // Asks first, the same as deleting from the folder's own screen.
                if case let .file(path) = entry.route {
                    Button("Rename…") { model.pendingFileRename = path }
                    Button("Delete…", role: .destructive) { model.pendingFileDelete = path }
                }
            }
        }
    }
}
