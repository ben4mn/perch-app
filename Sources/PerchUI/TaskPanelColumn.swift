import PerchKit
import SwiftUI

/// How wide the Mac's task panel is.
public enum TaskPanelLayout {
    public static let minWidth: CGFloat = 340
    public static let maxWidth: CGFloat = 620
    public static let defaultWidth: CGFloat = 420
    /// What the list or note keeps beside the panel.
    public static let contentRoom: CGFloat = 380
    /// The panel's width when the window can't give both their room.
    public static let narrowestWidth: CGFloat = 300

    /// The saved width, kept between the limits, and narrower when the list or note needs the room.
    public static func width(saved: CGFloat, available: CGFloat) -> CGFloat {
        let wanted = min(max(saved, minWidth), maxWidth)
        return max(narrowestWidth, min(wanted, available - contentRoom))
    }

    /// The width while the panel's left edge is dragged: left (a negative distance) widens it.
    public static func dragged(from start: CGFloat, by distance: CGFloat, available: CGFloat) -> CGFloat {
        width(saved: start - distance, available: available)
    }
}

#if os(macOS)
/// The Mac's task panel: Perch's own column at the trailing edge of the list or note, shown exactly while a
/// task is selected. It replaces SwiftUI's inspector, which reported itself closed late when a panel opened
/// soon after another closed, and so closed the new panel by itself (a quarter of quick reopens in the
/// navigation stress test). Its left edge drags to resize it, and the width is remembered.
public struct TaskPanelColumn<Content: View>: View {
    @ObservedObject var model: AppModel
    let content: Content
    @AppStorage("taskPanelWidth") private var savedWidth = Double(TaskPanelLayout.defaultWidth)
    @State private var dragStart: CGFloat?
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: AppModel, @ViewBuilder content: () -> Content) {
        self.model = model
        self.content = content()
    }

    public var body: some View {
        GeometryReader { proxy in
            let available = proxy.size.width
            let width = TaskPanelLayout.width(saved: CGFloat(savedWidth), available: available)
            HStack(spacing: 0) {
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
                if let task = model.task(id: model.selectedTaskID) {
                    HStack(spacing: 0) {
                        edge(width: width, available: available)
                        ZStack {
                            TaskDetailHost(model: model, task: task)
                                .id(task.id)
                                .transition(.perchSwap(reduceMotion: reduceMotion))
                        }
                        .frame(width: width)
                        .frame(maxHeight: .infinity)
                        .background(theme.background.ignoresSafeArea())
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                }
            }
            .motion(Motion.smooth, value: model.selectedTaskID)
        }
    }

    /// A hairline with a wider grip around it.
    private func edge(width: CGFloat, available: CGFloat) -> some View {
        Rectangle()
            .fill(theme.hairline)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .ignoresSafeArea()
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .modifier(ColumnResizeCursor())
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let start = dragStart ?? width
                                dragStart = start
                                savedWidth = Double(TaskPanelLayout.dragged(from: start, by: value.translation.width, available: available))
                            }
                            .onEnded { _ in dragStart = nil }
                    )
                    .accessibilityHidden(true)
            }
    }
}

/// The left-right arrows over the panel's edge.
private struct ColumnResizeCursor: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.pointerStyle(.columnResize)
        } else {
            content.onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
        }
    }
}
#endif
