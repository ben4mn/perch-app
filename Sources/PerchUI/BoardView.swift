import PerchKit
import SwiftUI

struct BoardView: View {
    @ObservedObject var model: AppModel
    let path: String
    @State private var board = KanbanBoard()
    @State private var dropped: [(line: Int, text: String)] = []
    @State private var allowDrop = false
    @State private var filter = ""
    @State private var onlyToday = false
    @State private var editing: EditingCard?
    @State private var newCardText: [UUID: String] = [:]
    @State private var newList = ""
    @State private var lastText = ""
    @State private var targetedList: UUID?
    @Environment(\.perchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct EditingCard: Identifiable {
        var id: UUID { card.id }
        var card: KanbanCard
        var list: UUID
    }

    private var canEdit: Bool { dropped.isEmpty || allowDrop }

    var body: some View {
        VStack(spacing: 0) {
            if !dropped.isEmpty && !allowDrop { dropWarning }
            ScreenHeader(title: VaultFile(path: path).title, stats: [HeaderStat(text: summary)]) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        FilterField(text: $filter, prompt: "Filter cards").frame(maxWidth: 240)
                        dueTodayChip
                        Spacer(minLength: 8)
                        addListField.frame(maxWidth: 180)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        FilterField(text: $filter, prompt: "Filter cards")
                        HStack(spacing: 8) {
                            dueTodayChip
                            addListField
                        }
                    }
                }
            }
            if board.lists.isEmpty {
                EmptyState(
                    symbol: "rectangle.split.3x1", title: "This board has no lists yet",
                    message: "A board is a row of lists, like To do, Doing and Done, with cards you drag between them. Name the first list in “Add a list” above."
                )
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: Metrics.gap) {
                        ForEach(board.lists) { list in column(list) }
                    }
                    .padding(.horizontal, Metrics.screenPadding)
                    .padding(.bottom, Metrics.screenPadding)
                }
            }
        }
        .perchScreenBackground()
        .motion(Motion.smooth, value: board.lists.map { $0.cards.map(\.id) })
        .navigationTitle(VaultFile(path: path).title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear(perform: load)
        .onChange(of: model.files) {
            let disk = (try? model.vault?.read(path)) ?? lastText
            if disk != lastText { load() }
        }
        .sheet(item: $editing) { item in
            CardEditor(card: item.card, today: model.today) { result in
                if let listIndex = board.lists.firstIndex(where: { $0.id == item.list }),
                   let cardIndex = board.lists[listIndex].cards.firstIndex(where: { $0.id == item.id }) {
                    if let result {
                        board.lists[listIndex].cards[cardIndex] = result
                    } else {
                        board.lists[listIndex].cards.remove(at: cardIndex)
                    }
                    save()
                }
                editing = nil
            }
        }
    }

    private var summary: String {
        let cards = board.lists.reduce(0) { $0 + $1.cards.count }
        return "\(FolderListing.counted(board.lists.count, "list")) · \(FolderListing.counted(cards, "card"))"
    }

    private var dueTodayChip: some View {
        Button { onlyToday.toggle() } label: {
            ControlChip(symbol: onlyToday ? "sun.max.fill" : "sun.max", text: "Due today", isOn: onlyToday, showsChevron: false)
        }
        .buttonStyle(.plain)
        .help(onlyToday ? "Show every card" : "Show only cards due today")
        .accessibilityAddTraits(onlyToday ? .isSelected : [])
    }

    private var addListField: some View {
        FilterField(text: $newList, prompt: "Add a list", symbol: "plus")
            .onSubmit {
                let name = jsTrim(newList)
                guard !name.isEmpty else { return }
                board.lists.append(KanbanList(name: name))
                newList = ""
                save()
            }
            .disabled(!canEdit)
    }

    private var dropWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.warning)
            Text("\(dropped.count) line(s) in this file aren't part of a card. Saving, here or in NotesHub, would remove them.").font(.perchBody).foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Edit anyway") { withMotion(Motion.smooth, reduceMotion: reduceMotion) { allowDrop = true } }.buttonStyle(PerchButtonStyle())
        }
        .padding(.horizontal, Metrics.screenPadding).padding(.vertical, 10)
        .background(theme.warning.opacity(0.14))
        .transition(.perchBanner(from: .top, reduceMotion: reduceMotion))
    }

    private func visible(_ card: KanbanCard) -> Bool {
        if onlyToday, card.dueDate != model.today { return false }
        let query = jsTrim(filter)
        guard !query.isEmpty else { return true }
        return card.title.localizedCaseInsensitiveContains(query)
            || card.details.localizedCaseInsensitiveContains(query)
            || card.tags.contains { $0.localizedCaseInsensitiveContains(query) }
            || card.mentions.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func column(_ list: KanbanList) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("List", text: Binding(
                    get: { list.name },
                    set: { name in
                        if let index = board.lists.firstIndex(where: { $0.id == list.id }) { board.lists[index].name = name }
                    }
                ))
                .textFieldStyle(.plain).font(.perchHeading).foregroundStyle(theme.text)
                .onSubmit(save)
                CountBadge(count: list.cards.count)
                Menu {
                    Button("Delete list", role: .destructive) {
                        board.lists.removeAll { $0.id == list.id }
                        save()
                    }
                    .disabled(!list.cards.isEmpty)
                } label: { Image(systemName: "ellipsis").foregroundStyle(theme.textSecondary).frame(width: 22, height: 22).contentShape(Rectangle()) }
                .menuStyle(.button).buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("List options")
            }
            ScrollView {
                let cards = list.cards.filter(visible)
                VStack(spacing: 7) {
                    ForEach(cards) { card in cardView(card, in: list) }
                    if cards.isEmpty {
                        Text(targetedList == list.id ? "Drop to move here" : (list.cards.isEmpty ? "No cards yet" : "No cards match"))
                            .font(.perchCaption)
                            .foregroundStyle(targetedList == list.id ? theme.accent : theme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    }
                }
            }
            FilterField(text: Binding(
                get: { newCardText[list.id] ?? "" },
                set: { newCardText[list.id] = $0 }
            ), prompt: "Add a card", symbol: "plus")
            .onSubmit { addCard(to: list) }
            .disabled(!canEdit)
        }
        .frame(width: 270)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Metrics.cardRadius + 1, style: .continuous).fill(targetedList == list.id ? theme.dropFill : theme.wash))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius + 1, style: .continuous).strokeBorder(targetedList == list.id ? theme.accent : Color.clear, lineWidth: 1.5))
        .lift(targetedList == list.id, scale: 1.015)
        .motion(Motion.quick, value: targetedList)
        .dropDestination(for: String.self) { ids, location in
            guard canEdit, let id = ids.first.flatMap(UUID.init(uuidString:)) else { return false }
            var moved = false
            // The card settles into its new list with a small bounce.
            withMotion(Motion.bouncy, reduceMotion: reduceMotion) { moved = moveCard(id, to: list.id) }
            return moved
        } isTargeted: { targetedList = $0 ? list.id : (targetedList == list.id ? nil : targetedList) }
    }

    private func cardView(_ card: KanbanCard, in list: KanbanList) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top) {
                if card.isCompleted { Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.success) }
                Text(card.title).font(.perchCard).foregroundStyle(card.isCompleted ? theme.textMuted : theme.text).strikethrough(card.isCompleted)
            }
            if !card.details.isEmpty, card.taskCounts.total == 0 {
                Text(TaskText.plain(card.details.components(separatedBy: "\n")[0])).font(.perchCaption).foregroundStyle(theme.textSecondary).lineLimit(2)
            }
            HStack(spacing: 7) {
                if let due = card.dueDate {
                    Label(friendlyDate(due, today: model.today), systemImage: "calendar")
                        .foregroundStyle(due < model.today && !card.isCompleted ? theme.danger : (due == model.today ? theme.success : theme.textSecondary))
                }
                if let value = card.estimateValue { Label("\(value)\(card.estimateUnit ?? "")", systemImage: "clock") }
                if card.taskCounts.total > 0 { Label("\(card.taskCounts.completed)/\(card.taskCounts.total)", systemImage: "checklist") }
                ForEach(card.tags, id: \.self) { Text("#\($0)").foregroundStyle(Palette.label($0, theme: theme)) }
                ForEach(card.mentions, id: \.self) { Text("@\($0)") }
            }
            .font(.perchSmall).foregroundStyle(theme.textSecondary).labelStyle(CompactLabel())
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(BoardCardChrome())
        .onTapGesture { if canEdit { editing = EditingCard(card: card, list: list.id) } }
        .draggable(card.id.uuidString) { TaskDragPreview(title: card.title, tint: theme.info).environment(\.perchTheme, theme) }
        .transition(.perchPop(reduceMotion: reduceMotion))
    }

    private func addCard(to list: KanbanList) {
        let text = jsTrim(newCardText[list.id] ?? "")
        guard !text.isEmpty, let index = board.lists.firstIndex(where: { $0.id == list.id }) else { return }
        board.lists[index].cards.append(KanbanCodec.createCard(rawTitle: text))
        newCardText[list.id] = ""
        save()
    }

    private func moveCard(_ id: UUID, to listID: UUID) -> Bool {
        for sourceIndex in board.lists.indices {
            if let cardIndex = board.lists[sourceIndex].cards.firstIndex(where: { $0.id == id }),
               let target = board.lists.firstIndex(where: { $0.id == listID }) {
                let card = board.lists[sourceIndex].cards.remove(at: cardIndex)
                board.lists[target].cards.append(card)
                save()
                return true
            }
        }
        return false
    }

    private func load() {
        let text = (try? model.vault?.read(path)) ?? ""
        lastText = text
        let parsed = KanbanCodec.parse(text)
        board = parsed.board
        dropped = parsed.droppedLines
    }

    private func save() {
        guard canEdit else { return }
        let text = KanbanCodec.serialize(board)
        guard text != lastText else { return }
        lastText = text
        model.save(text, to: path)
    }
}

/// A board card's surface: raised off its list, with a border that picks up the accent on hover.
private struct BoardCardChrome: ViewModifier {
    @Environment(\.perchTheme) private var theme
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).fill(theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).strokeBorder(hovering ? theme.accent.opacity(0.55) : theme.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
            .onHover { hovering = $0 }
            .lift(hovering, scale: 1.012)
            .motion(Motion.quick, value: hovering)
    }
}

private struct CardEditor: View {
    @State var card: KanbanCard
    let today: String
    let onDone: (KanbanCard?) -> Void
    @State private var tags: String
    @State private var mentions: String
    @State private var estimate: String
    @State private var hasDue: Bool
    @State private var due: Date
    @Environment(\.perchTheme) private var theme

    init(card: KanbanCard, today: String, onDone: @escaping (KanbanCard?) -> Void) {
        _card = State(initialValue: card)
        self.today = today
        self.onDone = onDone
        _tags = State(initialValue: card.tags.joined(separator: " "))
        _mentions = State(initialValue: card.mentions.joined(separator: " "))
        _estimate = State(initialValue: card.estimateValue.map { "\($0)\(card.estimateUnit ?? "")" } ?? "")
        _hasDue = State(initialValue: card.dueDate != nil)
        _due = State(initialValue: card.dueDate.flatMap { DayMath.date(from: $0) } ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            TextField("Title", text: $card.title).font(.perchStyle(.headline))
            TextEditor(text: $card.details)
                .font(.system(.callout, design: .monospaced))
                .frame(minHeight: 130)
                .scrollContentBackground(.hidden)
                .background(RoundedRectangle(cornerRadius: 6).fill(theme.codeBackground))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.border))
            Text("Details are Markdown. `- [ ] item` lines count as subtasks.").font(.perchStyle(.caption)).foregroundStyle(theme.textSecondary)
            HStack {
                Toggle("Due", isOn: $hasDue)
                if hasDue { DatePicker("Due", selection: $due, displayedComponents: .date).labelsHidden() }
                Toggle("Completed", isOn: $card.isCompleted).disabled(!hasDue)
            }
            TextField("Tags, separated by spaces", text: $tags).textFieldStyle(.roundedBorder)
            TextField("Mentions, separated by spaces", text: $mentions).textFieldStyle(.roundedBorder)
            TextField("Estimate: 30m, 2h, 3d, 1w", text: $estimate).textFieldStyle(.roundedBorder)
            HStack {
                Button("Delete card", role: .destructive) { onDone(nil) }
                Spacer()
                Button("Cancel") {
                    onDone(original)
                }
                Button("Save") { onDone(result) }.buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(minWidth: 300, idealWidth: 420)
        .perchPresented()
    }

    private var original: KanbanCard { _card.wrappedValue }

    private var result: KanbanCard {
        var output = card
        // Tags and mentions must be letters and digits, or NotesHub reads them as title text.
        let token = { (text: String) in
            text.split(separator: " ").map { $0.drop { "#@".contains($0) } }.map { String($0.filter { $0.isLetter || $0.isNumber }) }.filter { !$0.isEmpty }
        }
        output.tags = token(tags)
        output.mentions = token(mentions)
        output.dueDate = hasDue ? DayMath.string(from: due) : nil
        if !hasDue { output.isCompleted = false }
        if let match = estimate.range(of: #"^\s*~?(\d+)\s*([mhdw])?\s*$"#, options: .regularExpression) {
            let cleaned = estimate[match].filter { $0.isNumber || "mhdw".contains($0) }
            output.estimateValue = Int(cleaned.filter(\.isNumber))
            output.estimateUnit = cleaned.last.flatMap { $0.isLetter ? String($0) : nil }
        } else {
            output.estimateValue = nil
            output.estimateUnit = nil
        }
        return output
    }
}

struct WhiteboardScreen: View {
    @ObservedObject var model: AppModel
    let path: String
    @StateObject private var host: WebHost
    @State private var loadError: String?

    init(model: AppModel, path: String) {
        self.model = model
        self.path = path
        _host = StateObject(wrappedValue: WebHost(page: "whiteboard") { [weak model] in
            MainActor.assumeIsolated { model?.vault?.root }
        })
    }

    var body: some View {
        Group {
            if let loadError {
                EmptyState(
                    symbol: "scribble", title: "This whiteboard can't be opened",
                    message: "Its file couldn't be read as a drawing, so Perch has left it untouched. \(loadError)"
                )
                .perchScreenBackground()
            } else {
                WebHostView(host: host)
            }
        }
        .navigationTitle(VaultFile(path: path).title)
        .onAppear(perform: load)
        .onDisappear { host.call("flush", arguments: [:]) }
    }

    private func load() {
        // The model and the path, and not this view: the page keeps this closure, and a copy of the view
        // inside it would keep the page, so a closed whiteboard's page would never be let go. It can't
        // be cleared on the way out instead, because the last save arrives after the view has gone.
        host.onMessage = { [weak model, path] message in
            if message["type"] as? String == "whiteboardSave", let content = message["content"] as? String {
                model?.save(content, to: path)
            }
        }
        do {
            let file = VaultFile(path: path)
            let text = try model.vault?.read(path) ?? ""
            let scene = try WhiteboardCodec.sceneJSON(fromFileNamed: file.name, text: text)
            host.call("load", arguments: ["name": file.name, "sceneJSON": String(decoding: scene, as: UTF8.self)])
        } catch {
            loadError = "\(error)"
        }
    }
}
