import Foundation

/// What one folder holds, worked out from the flat list of vault files:
/// its subfolders (with how much is inside and when any of it last changed) and its own files.
/// Folders exist only because files live in them, so nothing here reads or writes the disk.
public struct FolderListing: Equatable, Sendable {
    public enum Sort: String, CaseIterable, Sendable {
        /// `modified` is last edited. The raw value stays as it was, so a saved choice still applies.
        case name, modified, created, kind

        public var title: String {
            switch self {
            case .name: return "Name"
            case .modified: return "Last edited"
            case .created: return "Created"
            case .kind: return "Kind"
            }
        }
    }

    /// Shows only files created, or last edited, within a stretch of time up to now.
    public struct DateFilter: Equatable, Hashable, Sendable {
        public enum Field: String, CaseIterable, Sendable {
            case edited, created

            public var title: String { self == .edited ? "Edited" : "Created" }
        }

        public enum Range: String, CaseIterable, Sendable {
            case any, today, week, month, year

            public var title: String {
                switch self {
                case .any: return "Any time"
                case .today: return "Today"
                case .week: return "Past 7 days"
                case .month: return "Past 30 days"
                case .year: return "This year"
                }
            }
        }

        public var field: Field
        public var range: Range

        public init(field: Field = .edited, range: Range = .any) {
            self.field = field
            self.range = range
        }

        public static let anyTime = DateFilter()
        public var isActive: Bool { range != .any }

        /// "Edited · Past 7 days", or "Any time" when it filters nothing.
        public var title: String { isActive ? "\(field.title) · \(range.title)" : Range.any.title }

        /// Saved as "edited.week"; anything unreadable is Any time.
        public var storage: String { "\(field.rawValue).\(range.rawValue)" }

        public init(storage: String) {
            let parts = storage.split(separator: ".").map(String.init)
            guard parts.count == 2, let field = Field(rawValue: parts[0]), let range = Range(rawValue: parts[1]) else {
                self = .anyTime
                return
            }
            self.init(field: field, range: range)
        }

        /// The earliest date that still counts, or nil for any time.
        public func start(now: Date, calendar: Calendar = .current) -> Date? {
            let today = calendar.startOfDay(for: now)
            switch range {
            case .any: return nil
            case .today: return today
            case .week: return calendar.date(byAdding: .day, value: -6, to: today)
            case .month: return calendar.date(byAdding: .day, value: -29, to: today)
            case .year: return calendar.dateInterval(of: .year, for: now)?.start
            }
        }

        /// Whether a file passes. A file with no date for the field only passes Any time.
        public func includes(_ file: VaultFile, now: Date, calendar: Calendar = .current) -> Bool {
            guard let start = start(now: now, calendar: calendar) else { return true }
            guard let date = field == .created ? file.created : file.lastEdited else { return false }
            return date >= start
        }
    }

    public struct Folder: Identifiable, Hashable, Sendable {
        public var path: String
        public var name: String
        /// Every matching file inside, at any depth.
        public var itemCount: Int
        /// The most recent edit among everything inside.
        public var modified: Date?
        /// When the newest thing inside was created.
        public var created: Date?
        public var id: String { path }

        public init(path: String, name: String, itemCount: Int, modified: Date?, created: Date? = nil) {
            self.path = path
            self.name = name
            self.itemCount = itemCount
            self.modified = modified
            self.created = created
        }
    }

    /// One step of the path to a folder.
    public struct Crumb: Identifiable, Hashable, Sendable {
        public var name: String
        public var path: String
        public var id: String { path }

        public init(name: String, path: String) {
            self.name = name
            self.path = path
        }
    }

    /// The kinds the notes tree shows. Task files live in `Tasks/` folders and have their own views.
    public static let browsableKinds: Set<VaultFileKind> = [.note, .board, .whiteboard, .notebook]

    public let path: String
    public let folders: [Folder]
    public let files: [VaultFile]

    /// Everything inside this folder, at any depth.
    public var itemCount: Int { files.count + folders.reduce(0) { $0 + $1.itemCount } }
    public var isEmpty: Bool { folders.isEmpty && files.isEmpty }

    /// - Parameters:
    ///   - path: The folder, relative to the vault root. Empty is the top level.
    ///   - kinds: Only these kinds count. A subfolder with none of them inside is left out.
    ///   - filter: Only files created or edited in this stretch of time count, the same way.
    public init(
        files all: [VaultFile], path: String, kinds: Set<VaultFileKind> = FolderListing.browsableKinds,
        sort: Sort = .name, filter: DateFilter = .anyTime, now: Date = Date()
    ) {
        let base = path.split(separator: "/").map(String.init)
        self.path = base.joined(separator: "/")
        var direct: [VaultFile] = []
        var found: [String: Folder] = [:]
        for file in all where kinds.contains(file.kind) && filter.includes(file, now: now) {
            let parts = file.path.split(separator: "/").map(String.init)
            guard parts.count > base.count, Array(parts.prefix(base.count)) == base else { continue }
            if parts.count == base.count + 1 {
                direct.append(file)
                continue
            }
            let name = parts[base.count]
            var folder = found[name] ?? Folder(path: (base + [name]).joined(separator: "/"), name: name, itemCount: 0, modified: nil)
            folder.itemCount += 1
            if let edited = file.lastEdited, edited > (folder.modified ?? .distantPast) { folder.modified = edited }
            if let created = file.created, created > (folder.created ?? .distantPast) { folder.created = created }
            found[name] = folder
        }
        folders = Self.sorted(Array(found.values), by: sort, name: \.name, path: \.path, modified: \.modified, created: \.created, rank: { _ in 0 })
        files = Self.sorted(direct, by: sort, name: \.title, path: \.path, modified: \.lastEdited, created: \.created, rank: { Self.kindRank($0.kind) })
    }

    /// "4 folders · 12 notes · 1 board": what is directly inside.
    public var summary: String {
        var parts: [String] = []
        if !folders.isEmpty { parts.append(Self.counted(folders.count, "folder")) }
        for kind in Self.kindOrder {
            let count = files.filter { $0.kind == kind }.count
            if count > 0 { parts.append(Self.counted(count, Self.noun(kind))) }
        }
        let others = files.filter { !Self.kindOrder.contains($0.kind) }.count
        if others > 0 { parts.append(Self.counted(others, "file")) }
        return parts.isEmpty ? "Empty" : parts.joined(separator: " · ")
    }

    /// Whether a folder's title has its path above it. Beside the folder chips a top-level folder has
    /// none: its chip is selected and its name is the title, so the path would only say it a third time.
    public static func showsBreadcrumb(for path: String, besideFolderChips: Bool) -> Bool {
        let depth = path.split(separator: "/").count
        return besideFolderChips ? depth >= 2 : depth >= 1
    }

    /// The path to a folder, one step per level. The top level itself isn't included.
    public static func crumbs(for path: String) -> [Crumb] {
        var current = ""
        return path.split(separator: "/").map { part in
            current = current.isEmpty ? String(part) : current + "/" + part
            return Crumb(name: String(part), path: current)
        }
    }

    public static func noun(_ kind: VaultFileKind) -> String {
        switch kind {
        case .note: return "note"
        case .board: return "board"
        case .whiteboard: return "whiteboard"
        case .notebook: return "notebook"
        case .task: return "task"
        case .attachment: return "attachment"
        case .other: return "file"
        }
    }

    public static func counted(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    private static let kindOrder: [VaultFileKind] = [.note, .board, .whiteboard, .notebook]

    private static func kindRank(_ kind: VaultFileKind) -> Int {
        kindOrder.firstIndex(of: kind) ?? kindOrder.count
    }

    private static func sorted<Item>(
        _ items: [Item], by sort: Sort,
        name: KeyPath<Item, String>, path: KeyPath<Item, String>, modified: KeyPath<Item, Date?>, created: KeyPath<Item, Date?>,
        rank: (Item) -> Int
    ) -> [Item] {
        // Two files can share a title ("Plans.md" and "Plans.kanban.md"); the path settles it,
        // so the order never depends on the order the files were found in.
        func byName(_ a: Item, _ b: Item) -> Bool {
            switch a[keyPath: name].localizedStandardCompare(b[keyPath: name]) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return a[keyPath: path] < b[keyPath: path]
            }
        }
        // Newest first; anything without a date goes last.
        func byDate(_ date: KeyPath<Item, Date?>, _ a: Item, _ b: Item) -> Bool {
            switch (a[keyPath: date], b[keyPath: date]) {
            case let (x?, y?) where x != y: return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return byName(a, b)
            }
        }
        return items.sorted { a, b in
            switch sort {
            case .name:
                return byName(a, b)
            case .modified:
                return byDate(modified, a, b)
            case .created:
                return byDate(created, a, b)
            case .kind:
                let (x, y) = (rank(a), rank(b))
                return x == y ? byName(a, b) : x < y
            }
        }
    }
}
