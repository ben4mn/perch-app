import PerchKit
import SwiftUI

struct SearchScreen: View {
    @ObservedObject var model: AppModel
    @Environment(\.perchTheme) private var theme
    /// The result showing in the pane beside the list, on a wide screen.
    @Environment(\.perchSelectedPath) private var selectedPath

    var body: some View {
        let query = jsTrim(model.searchQuery)
        let hits = model.search(model.searchQuery)
        VStack(spacing: 0) {
            ScreenHeader(title: "Search", stats: query.isEmpty ? [] : [HeaderStat(text: hits.count == 1 ? "1 result for “\(query)”" : "\(hits.count) results for “\(query)”")])
            if query.isEmpty {
                EmptyState(
                    symbol: "magnifyingglass", title: "Search everything",
                    message: "Type in the search field to look through every note, task and board. Start with # to find a hashtag."
                )
            } else if hits.isEmpty {
                EmptyState(
                    symbol: "magnifyingglass", title: "Nothing found for “\(query)”",
                    message: "Try fewer words or another spelling. Search reads titles and the text inside notes, tasks and boards.",
                    actionTitle: "Clear search", action: { model.searchQuery = "" }
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                            Button { open(hit) } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: fileIcon(hit.kind))
                                        .font(.perchCaption.weight(.medium))
                                        .foregroundStyle(FileLook.tint(hit.kind, theme: theme))
                                        .frame(width: 26, height: 26)
                                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(FileLook.tint(hit.kind, theme: theme).opacity(0.15)))
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                                            Text(hit.title).font(.perchRow).foregroundStyle(theme.text).lineLimit(1)
                                            Text(FileLook.label(hit.kind)).font(.perchSmall).foregroundStyle(theme.textMuted)
                                        }
                                        if !jsTrim(hit.snippet).isEmpty {
                                            Text(TaskText.plain(hit.snippet)).font(.perchCaption).foregroundStyle(theme.textSecondary).lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8).padding(.vertical, Metrics.rowPadding)
                                .contentShape(Rectangle())
                                .hoverHighlight(selected: hit.path == selectedPath)
                            }
                            .buttonStyle(PerchPressStyle())
                            .accessibilityAddTraits(hit.path == selectedPath ? .isSelected : [])
                            .riseIn(delay: Motion.stagger(index), distance: 6)
                        }
                    }
                    .padding(.horizontal, Metrics.screenPadding - 8)
                    .padding(.bottom, 28)
                }
                .id(query)
            }
        }
        .perchScreenBackground()
        .navigationTitle("Search")
    }

    private func open(_ hit: AppModel.SearchHit) {
        if hit.kind == .task, let task = model.tasks.first(where: { $0.path == hit.path }) {
            model.selectedTaskID = task.id
        } else {
            model.route = .file(hit.path)
        }
    }
}

struct InsightsScreen: View {
    @ObservedObject var model: AppModel
    /// The focus timer is turned off in Settings: the focus figures are left out. The task figures stay.
    @AppStorage(FocusAvailability.hiddenKey) private var hidesFocus = FocusAvailability.hiddenByDefault
    @Environment(\.perchTheme) private var theme

    var body: some View {
        let insights = Insights.compute(tasks: model.tasks, focus: model.focusLog.sessions)
        let hasHistory = insights.completedThisWeek > 0 || (!hidesFocus && insights.focusMinutesThisWeek > 0) || insights.open > 0
        VStack(spacing: 0) {
            ScreenHeader(title: "Insights", stats: [HeaderStat(text: "The last 7 days")])
            if !hasHistory {
                EmptyState(
                    symbol: "chart.bar", title: "Nothing to count yet",
                    message: hidesFocus
                        ? "Insights show how many tasks you finish each day and your streak. Tick a task and the first bar appears."
                        : "Insights show how many tasks you finish each day, your streak and your focus time. Tick a task and the first bar appears.",
                    actionTitle: "Go to Today", action: { model.route = .today }
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.sectionGap) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Metrics.gap)], alignment: .leading, spacing: Metrics.gap) {
                            stat(insights.open, "Open tasks", "tray.full", theme.info)
                            stat(insights.overdue, "Overdue", "exclamationmark.circle", insights.overdue > 0 ? theme.danger : theme.textMuted)
                            stat(insights.completedThisWeek, "Done in 7 days", "checkmark.circle", theme.success)
                            stat(insights.streakDays, "Day streak", "flame", theme.warning)
                            if !hidesFocus { stat(insights.focusMinutesThisWeek, "Focus minutes", "timer", theme.accent) }
                        }
                        card("Completed each day") {
                            let peak = max(insights.lastSevenDays.map(\.completed).max() ?? 1, 1)
                            HStack(alignment: .bottom, spacing: Metrics.gap) {
                                ForEach(insights.lastSevenDays) { day in
                                    VStack(spacing: 5) {
                                        Text("\(day.completed)").font(.perchSmall).monospacedDigit().foregroundStyle(theme.textSecondary)
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(day.completed == 0 ? theme.washStrong : theme.accent)
                                            .frame(height: max(4, CGFloat(day.completed) / CGFloat(peak) * 96))
                                            .frame(maxWidth: 34)
                                        Text(DayMath.date(from: day.date)?.formatted(.dateTime.weekday(.abbreviated)) ?? "")
                                            .font(.perchSmall).foregroundStyle(day.date == model.today ? theme.accent : theme.textMuted)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("\(DayLabel.spoken(day.date, today: model.today)): \(day.completed) completed")
                                }
                            }
                            .frame(maxWidth: 460, alignment: .leading)
                            .motion(Motion.smooth, value: insights.lastSevenDays)
                        }
                        if !hidesFocus, let hour = insights.peakHour {
                            card("Focus") {
                                Label("You focus most around \(hour):00.", systemImage: "timer").font(.perchBody).foregroundStyle(theme.text)
                            }
                        }
                        if let oldest = insights.oldestOverdue {
                            card("Longest overdue") {
                                Button { model.selectedTaskID = oldest.id } label: {
                                    HStack(spacing: 8) {
                                        Text(oldest.title).font(.perchRow).foregroundStyle(theme.text).lineLimit(2).multilineTextAlignment(.leading)
                                        Spacer(minLength: 6)
                                        Chip(text: "Due \(friendlyDate(String((oldest.due ?? "").prefix(10)), today: model.today))", symbol: "calendar", tint: theme.danger)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PerchPressStyle())
                            }
                        }
                    }
                    .padding(.horizontal, Metrics.screenPadding)
                    .padding(.top, 4)
                    .padding(.bottom, Metrics.screenPadding)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .perchScreenBackground()
        .navigationTitle("Insights")
    }

    private func stat(_ value: Int, _ label: String, _ symbol: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).font(.perchBody.weight(.semibold)).foregroundStyle(tint).frame(height: 18)
            Text("\(value)").font(.system(.title, design: .rounded).weight(.bold)).monospacedDigit().foregroundStyle(theme.text)
                .contentTransition(.numericText())
            Text(label).font(.perchCaption).foregroundStyle(theme.textSecondary)
        }
        .padding(Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
        .motion(Motion.smooth, value: value)
        .accessibilityElement(children: .combine)
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Metrics.gap) {
            SectionLabel(title)
            content()
        }
        .padding(Metrics.cardPadding + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
    }
}

struct ImportScreen: View {
    @ObservedObject var model: AppModel
    @State private var token = ""
    @State private var snapshot: TodoistSnapshot?
    @State private var plan: TodoistImportPlan?
    @State private var fetchWarnings: [String] = []
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var resultMessage: String?
    @State private var includeCompleted = true
    @Environment(\.perchTheme) private var theme

    private var options: TodoistImportOptions {
        // Projects go to the area of the same name; the build's owners are the owner labels.
        var options = TodoistImportOptions(
            areas: model.areas, ownerLabels: Set(([model.author] + model.configuration.otherOwners).map { $0.lowercased() }), ownerID: model.author
        )
        options.includeCompleted = includeCompleted
        return options
    }

    var body: some View {
        Form {
            Section {
                Text("Copy your API token from Todoist: Settings → Integrations → Developer. Perch only reads from Todoist and doesn't store the token.")
                    .font(.perchStyle(.callout)).foregroundStyle(theme.textSecondary)
                SecureField("API token", text: $token)
                Toggle("Include completed history", isOn: $includeCompleted)
                    .onChange(of: includeCompleted) { rebuild() }
                Button(isWorking ? "Reading Todoist…" : "Preview import") { Task { await preview() } }
                    .disabled(token.isEmpty || isWorking)
            } header: {
                Text("1. Read your tasks")
            }
            if let errorMessage {
                Section { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(theme.danger) }
            }
            if let plan {
                Section("2. Check what will be created. Nothing has been written yet.") {
                    row("New open tasks", plan.summary.open)
                    row("Completed tasks", plan.summary.completed)
                    row("Already imported", plan.summary.alreadyImported)
                    row("Subtasks", plan.summary.subtasks)
                    row("With details", plan.summary.withDetails)
                    row("Comments", plan.summary.comments)
                    row("Reminders", plan.summary.reminders)
                    row("Repeating", plan.summary.repeating)
                    ForEach(plan.summary.byArea.sorted { $0.key < $1.key }, id: \.key) { row("In \($0.key)", $0.value) }
                    ForEach(plan.summary.byOwner.sorted { $0.key < $1.key }, id: \.key) { row("Owner: \($0.key)", $0.value) }
                    ForEach(plan.summary.byPriority.sorted { $0.key < $1.key }, id: \.key) { row("P\($0.key)", $0.value) }
                }
                let warnings = fetchWarnings + plan.warnings
                if !warnings.isEmpty {
                    Section("Worth checking") {
                        ForEach(warnings, id: \.self) { Text($0).font(.perchStyle(.callout)) }
                    }
                }
                Section("3. Import") {
                    Button("Create \(plan.tasks.count) task files") { apply(plan) }
                        .buttonStyle(.borderedProminent)
                        .disabled(plan.tasks.isEmpty)
                    Text("Tasks go into this notebook's area Tasks folders. You can run this again later; tasks already imported are skipped.")
                        .font(.perchStyle(.caption)).foregroundStyle(theme.textSecondary)
                }
            }
            if let resultMessage {
                Section { Label(resultMessage, systemImage: "checkmark.circle").foregroundStyle(theme.success) }
            }
        }
        .formStyle(.grouped)
        .perchScreenBackground()
        .motion(Motion.smooth, value: plan?.tasks.count)
        .motion(Motion.smooth, value: errorMessage)
        .navigationTitle("Import from Todoist")
    }

    private func row(_ label: String, _ value: Int) -> some View {
        LabeledContent(label) { Text("\(value)").monospacedDigit() }
    }

    private func preview() async {
        isWorking = true
        errorMessage = nil
        resultMessage = nil
        defer { isWorking = false }
        do {
            var warnings: [String] = []
            snapshot = try await TodoistClient(token: jsTrim(token)).fetchSnapshot(warnings: &warnings)
            fetchWarnings = warnings
            rebuild()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rebuild() {
        guard let snapshot else { return }
        plan = TodoistMapper.plan(snapshot: snapshot, existing: model.tasks, options: options)
    }

    private func apply(_ plan: TodoistImportPlan) {
        guard let vault = model.vault else { return }
        do {
            let count = try TodoistMapper.apply(plan, to: vault)
            resultMessage = "Created \(count) task files."
            self.plan = nil
            snapshot = nil
            token = ""
            Task { await model.reload(force: true) }
            model.scheduleSync()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Reads who changed what from Git history, so every agent shows under its own name.
struct ActivityScreen: View {
    @ObservedObject var model: AppModel
    @State private var entries: [ActivityEntry] = []
    @State private var loaded = false
    @Environment(\.perchTheme) private var theme

    struct ActivityEntry: Identifiable, Equatable {
        var id: String
        var author: String
        var date: String
        var text: String
        var title: String?
        var path: String?
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Activity", stats: entries.isEmpty ? [] : [HeaderStat(text: entries.count == 1 ? "1 change" : "\(entries.count) recent changes")])
            if entries.isEmpty {
                if loaded {
                    EmptyState(
                        symbol: "clock.arrow.circlepath", title: "No activity yet",
                        message: "Every comment, completion and synced change by you or your agents is listed here, newest first. Comment on a task to see the first one."
                    )
                } else {
                    Color.clear
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groups, id: \.day) { group in
                            SectionLabel(friendlyDate(group.day, today: model.today))
                                .padding(.horizontal, 8).padding(.top, Metrics.gap).padding(.bottom, 2)
                            ForEach(group.entries) { entry in
                                let task = entry.path.flatMap { path in model.tasks.first { $0.path == path } }
                                Button { if let task { model.selectedTaskID = task.id } } label: {
                                    ActivityLine(author: entry.author, me: model.author, date: "", title: entry.title, text: entry.text)
                                }
                                .buttonStyle(PerchPressStyle())
                                .disabled(task == nil)
                            }
                        }
                    }
                    .padding(.horizontal, Metrics.screenPadding - 8)
                    .padding(.bottom, 28)
                }
            }
        }
        .perchScreenBackground()
        .motion(Motion.smooth, value: entries)
        .navigationTitle("Activity")
        .task(id: model.files) { await load() }
    }

    /// Entries gathered under the day they happened, newest day first.
    private var groups: [(day: String, entries: [ActivityEntry])] {
        var result: [(day: String, entries: [ActivityEntry])] = []
        for entry in entries {
            if result.last?.day == entry.date { result[result.count - 1].entries.append(entry) } else { result.append((entry.date, [entry])) }
        }
        return result
    }

    private func load() async {
        var result: [ActivityEntry] = []
        for task in model.tasks {
            for (index, item) in task.activity.enumerated() {
                result.append(.init(id: "\(task.id)-\(index)", author: item.author, date: String(item.date.prefix(10)), text: item.text, title: task.title, path: task.path))
            }
        }
        #if os(macOS)
        if let git = model.syncEngine as? GitCLISync {
            for entry in await git.log(limit: 80) {
                result.append(.init(id: entry.hash, author: entry.author, date: String(entry.date.prefix(10)), text: entry.subject, title: nil, path: nil))
            }
        }
        #endif
        entries = result.sorted { $0.date > $1.date }.prefix(200).map { $0 }
        loaded = true
    }
}
