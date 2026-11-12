import ActivityKit
import SwiftUI
import WidgetKit

struct TodayEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot?
}

struct TodayProvider: TimelineProvider {
    private func load() -> WidgetSnapshot? {
        guard let url = SharedStore.snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: WidgetSnapshot(date: Date(), total: 3, overdue: 1, tasks: [
            .init(id: "1", title: "Renew passport", priority: 1, isOverdue: true, area: "Personal"),
            .init(id: "2", title: "Draft the deck", priority: 2, isOverdue: false, area: "Work"),
        ]))
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : TodayEntry(date: Date(), snapshot: load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [TodayEntry(date: Date(), snapshot: load())], policy: .after(next)))
    }
}

private func priorityColor(_ value: Int) -> Color {
    switch value {
    case 1: return .red
    case 2: return .orange
    case 3: return .blue
    default: return .secondary
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(entry.snapshot?.total ?? 0)").font(.title3.bold())
                    Text("today").font(.caption2)
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("\(entry.snapshot?.total ?? 0) today").font(.headline)
                Text(entry.snapshot?.tasks.first?.title ?? "Nothing due").font(.caption).lineLimit(2)
            }
        default:
            list
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Today").font(.headline)
                Spacer()
                Text("\(entry.snapshot?.total ?? 0)").font(.headline).foregroundStyle(.secondary)
            }
            if let tasks = entry.snapshot?.tasks, !tasks.isEmpty {
                ForEach(tasks.prefix(family == .systemSmall ? 3 : (family == .systemLarge ? 10 : 4))) { task in
                    Link(destination: URL(string: "perch://task/\(task.id)")!) {
                        HStack(spacing: 6) {
                            Circle().strokeBorder(priorityColor(task.priority), lineWidth: 1.5).frame(width: 11, height: 11)
                            Text(task.title).font(.caption).lineLimit(1).foregroundStyle(task.isOverdue ? Color.red : Color.primary)
                        }
                    }
                }
            } else {
                Text("Nothing due.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PerchToday", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Your most important tasks today.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
    }
}

struct FocusLiveActivity: Widget {
    @ViewBuilder
    private func timer(_ state: FocusAttributes.ContentState) -> some View {
        if let end = state.endDate {
            Text(timerInterval: state.startDate...max(end, state.startDate), countsDown: true).monospacedDigit()
        } else {
            Text(state.startDate, style: .timer).monospacedDigit()
        }
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusAttributes.self) { context in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Focus").font(.caption).foregroundStyle(.secondary)
                    Text(context.attributes.taskTitle).font(.callout.weight(.semibold)).lineLimit(1)
                }
                Spacer()
                timer(context.state).font(.title.bold()).frame(maxWidth: 110, alignment: .trailing)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "timer").font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timer(context.state).font(.title2.bold()).frame(maxWidth: 100, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.taskTitle).font(.callout).lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "timer")
            } compactTrailing: {
                timer(context.state).frame(maxWidth: 46).font(.caption.monospacedDigit())
            } minimal: {
                Image(systemName: "timer")
            }
        }
    }
}

@main
struct PerchWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        FocusLiveActivity()
    }
}
