import Foundation
import UniformTypeIdentifiers

// The notch's Clips: recent copies, screenshots and dropped files, kept in memory for a day.
// This is the bookkeeping, kept here so it can be tested: what kind a clip is, how long it is kept,
// what copying the same thing again does, how the pane groups and filters clips, and which new files
// in the screenshot folder are screenshots. Reading the pasteboard and the folder, and making the
// pictures, stay in the Mac app.

public enum ClipRules {
    /// Nothing is kept this long. Clips are in memory only, so this is the whole of their life.
    public static let maximumAge: TimeInterval = 24 * 60 * 60
    /// A guard on memory: past this many, the oldest go first.
    public static let maximumCount = 50
    /// The most memory images copied from the pasteboard may hold together, as their bytes are kept to copy
    /// them back. Past it the oldest of them go first. Files are not held in memory, and pictures don't count.
    public static let imageBudget = 100 * 1024 * 1024
    /// How much of a long text a card is given to draw. A card shows far less, so nothing visible is lost.
    public static let previewLength = 600

    /// A clip is gone once it is a full day old.
    public static func isExpired(_ date: Date, now: Date) -> Bool {
        now.timeIntervalSince(date) >= maximumAge
    }

    /// The text a card draws: trimmed, with Windows line ends made plain, and cut to `previewLength`.
    public static func preview(of text: String) -> String {
        let plain = text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return plain.count > previewLength ? String(plain.prefix(previewLength)) : plain
    }
}

/// What a clip is, for how its card is drawn and which filter shows it.
public enum ClipKind: String, CaseIterable, Sendable, Identifiable {
    case text, link, image, file

    public var id: String { rawValue }

    /// The filter chip's name.
    public var title: String {
        switch self {
        case .text: return "Text"
        case .link: return "Links"
        case .image: return "Images"
        case .file: return "Files"
        }
    }

    /// Copied text is a link when the whole of it, trimmed, is one web address.
    public static func of(text: String) -> ClipKind {
        ClipLink(text: text) == nil ? .text : .link
    }

    /// A file is an image when its type is one (saved screenshots are). Everything else, recordings,
    /// documents and folders included, is a file.
    public static func of(fileType type: UTType?) -> ClipKind {
        guard let type else { return .file }
        return type.conforms(to: .image) ? .image : .file
    }
}

/// A web address as a link card draws it: the site in normal ink, the rest of the address dimmer.
public struct ClipLink: Equatable, Sendable {
    public var url: URL
    /// The site without "www.", with its port if it has one.
    public var host: String
    /// Everything after the site. Empty for a bare site.
    public var rest: String

    public init?(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              let url = URL(string: trimmed) else { return nil }
        var site = host.lowercased()
        if site.hasPrefix("www."), site.count > 4 { site.removeFirst(4) }
        if let port = components.port { site += ":\(port)" }
        var rest = components.path == "/" ? "" : components.path
        if let query = components.query { rest += "?" + query }
        if let fragment = components.fragment { rest += "#" + fragment }
        self.url = url
        self.host = site
        self.rest = rest
    }
}

/// What makes two clips the same clip, so copying something again refreshes it instead of adding it twice.
public enum ClipKey: Hashable, Sendable {
    case text(String)
    /// A file, by its path.
    case file(String)
    /// An image from the pasteboard, by a digest of its bytes.
    case image(String)
}

/// Which clips the pane shows.
public enum ClipFilter: Hashable, Sendable {
    case all
    case kind(ClipKind)
}

/// The groups the pane puts clips in. Their names make the one-day rule visible.
public enum ClipAge: Int, CaseIterable, Sendable, Identifiable {
    case lastHour, earlierToday, yesterday

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .lastHour: return "Last hour"
        case .earlierToday: return "Earlier today"
        case .yesterday: return "Yesterday"
        }
    }

    /// The group for a clip from `date`, or nil once it has run out. Anything under an hour old is in the
    /// last hour, across midnight too; after that it is today's or yesterday's by the calendar.
    public static func of(_ date: Date, now: Date, calendar: Calendar = .current) -> ClipAge? {
        guard !ClipRules.isExpired(date, now: now) else { return nil }
        if now.timeIntervalSince(date) < 3600 { return .lastHour }
        return calendar.isDate(date, inSameDayAs: now) ? .earlierToday : .yesterday
    }
}

/// The clips themselves, newest first. `Payload` is whatever the app keeps with each one: the text, the
/// image's bytes or the file, and its picture.
public struct ClipShelf<Payload> {
    public struct Item: Identifiable {
        public let id: UUID
        public let key: ClipKey
        public let kind: ClipKind
        /// When it was copied, or when a screenshot was taken. Copying it again moves this on.
        public internal(set) var date: Date
        public let payload: Payload
        /// Bytes it holds in memory. Only an image from the pasteboard counts toward `ClipRules.imageBudget`.
        public let cost: Int

        public init(id: UUID = UUID(), key: ClipKey, kind: ClipKind, date: Date, payload: Payload, cost: Int = 0) {
            self.id = id
            self.key = key
            self.kind = kind
            self.date = date
            self.payload = payload
            self.cost = cost
        }

        /// An image from the pasteboard, whose bytes are held: the only kind of clip the image budget covers.
        var isHeldImage: Bool {
            if case .image = key { return true }
            return false
        }
    }

    /// One group of the strip.
    public struct Section: Identifiable {
        public var age: ClipAge
        public var items: [Item]
        public var id: ClipAge { age }
    }

    /// One filter chip and how many clips it would show.
    public struct Chip: Equatable, Identifiable {
        public var filter: ClipFilter
        public var count: Int
        public var id: ClipFilter { filter }
    }

    public private(set) var items: [Item]

    public init(items: [Item] = []) {
        self.items = items.sorted { $0.date > $1.date }
    }

    /// Adds a clip in its place by time, newest first. The same thing copied again is not added twice:
    /// the clip already here takes the new time and moves to its new place, keeping its id and what was
    /// made for it (its picture). Returns the clip as it now stands.
    @discardableResult
    public mutating func add(_ item: Item) -> Item {
        var stored = item
        if let index = items.firstIndex(where: { $0.key == item.key }) {
            stored = items.remove(at: index)
            stored.date = item.date
        }
        let place = items.firstIndex { $0.date <= stored.date } ?? items.endIndex
        items.insert(stored, at: place)
        if items.count > ClipRules.maximumCount { items.removeLast(items.count - ClipRules.maximumCount) }
        keepImagesInBudget(sparing: stored.id)
        return stored
    }

    /// Memory held by images copied from the pasteboard.
    public var imageBytes: Int {
        items.reduce(0) { $0 + ($1.isHeldImage ? $1.cost : 0) }
    }

    /// Over the image budget, the oldest pasteboard images go until it is met. Text, links and files never
    /// go for it. The clip just added and the newest image are spared, so one image larger than the whole
    /// budget is kept on its own until another image comes.
    private mutating func keepImagesInBudget(sparing added: UUID) {
        var total = imageBytes
        guard total > ClipRules.imageBudget else { return }
        let newest = items.first(where: \.isHeldImage)?.id
        while total > ClipRules.imageBudget,
              let index = items.lastIndex(where: { $0.isHeldImage && $0.id != added && $0.id != newest }) {
            total -= items[index].cost
            items.remove(at: index)
        }
    }

    /// Forgets clips a day old or more, and the oldest past the count limit. Returns whether anything
    /// went, so a caller can leave its published copy alone when nothing changed.
    @discardableResult
    public mutating func prune(now: Date) -> Bool {
        // Run every second, so the usual case, nothing to do, touches nothing.
        guard items.count > ClipRules.maximumCount || items.contains(where: { ClipRules.isExpired($0.date, now: now) }) else { return false }
        let before = items.count
        items.removeAll { ClipRules.isExpired($0.date, now: now) }
        if items.count > ClipRules.maximumCount { items.removeLast(items.count - ClipRules.maximumCount) }
        return items.count != before
    }

    @discardableResult
    public mutating func remove(id: UUID) -> Bool {
        removeAll { $0.id == id }
    }

    @discardableResult
    public mutating func removeAll(where shouldRemove: (Item) -> Bool) -> Bool {
        let before = items.count
        items.removeAll(where: shouldRemove)
        return items.count != before
    }

    public mutating func removeAll() {
        items.removeAll()
    }

    // MARK: Display

    private func current(_ now: Date) -> [Item] {
        items.filter { !ClipRules.isExpired($0.date, now: now) }
    }

    /// "All", then one chip for each kind that has clips, each with its count. A clip that has run out
    /// but isn't pruned yet is not counted.
    public func chips(now: Date) -> [Chip] {
        let current = current(now)
        var chips = [Chip(filter: .all, count: current.count)]
        for kind in ClipKind.allCases {
            let count = current.filter { $0.kind == kind }.count
            if count > 0 { chips.append(Chip(filter: .kind(kind), count: count)) }
        }
        return chips
    }

    /// The filter to show: the one chosen, or All once the chosen kind has no clips left.
    public func resolved(_ filter: ClipFilter, now: Date) -> ClipFilter {
        guard case let .kind(kind) = filter else { return .all }
        return current(now).contains { $0.kind == kind } ? filter : .all
    }

    /// The strip: clips the filter shows, newest first, in their age groups. Empty groups are left out,
    /// and so is anything that has run out, even before it is pruned.
    public func sections(_ filter: ClipFilter, now: Date, calendar: Calendar = .current) -> [Section] {
        var groups: [ClipAge: [Item]] = [:]
        for item in items {
            if case let .kind(kind) = filter, item.kind != kind { continue }
            guard let age = ClipAge.of(item.date, now: now, calendar: calendar) else { continue }
            groups[age, default: []].append(item)
        }
        return ClipAge.allCases.compactMap { age in groups[age].map { Section(age: age, items: $0) } }
    }
}

/// Picks new screenshots and screen recordings out of the screenshot folder, from what a listing says
/// about each file. It takes each one once, in the order they were taken, waits for one that is still
/// being written, and forgets what it took once that is a day old.
public struct ScreenshotWatch: Sendable {
    public struct File: Equatable, Sendable {
        public var name: String
        public var created: Date
        public var size: Int
        /// What macOS wrote on the file: true for a screenshot or recording, nil when it wrote nothing.
        public var isScreenCapture: Bool?

        public init(name: String, created: Date, size: Int, isScreenCapture: Bool?) {
            self.name = name
            self.created = created
            self.size = size
            self.isScreenCapture = isScreenCapture
        }
    }

    /// The extended attribute macOS sets on screenshots and screen recordings, whatever the language.
    public static let attribute = "com.apple.metadata:kMDItemIsScreenCapture"
    /// How long a new file may stay empty, or without that attribute, before it is taken as not one.
    public static let settleTime: TimeInterval = 10
    /// The English names, for a file that carries no attribute.
    public static let namePrefixes = ["Screenshot", "Screen Shot", "Screen Recording"]

    /// Files from before this are never taken: turning Clips on doesn't pull in old screenshots.
    public let started: Date
    /// A new file may still turn into a screenshot (it is being written, or not marked yet), so the
    /// folder should be read again on the next tick even if it hasn't changed.
    public private(set) var isWaiting = false
    private var taken: [String: Date] = [:]

    public init(started: Date) {
        self.started = started
    }

    /// Files created before this can be passed over without reading their details.
    public func earliest(now: Date) -> Date {
        max(started, now.addingTimeInterval(-ClipRules.maximumAge))
    }

    /// The new screenshots among `files`, oldest first. Each is taken once; two from the same moment are
    /// both taken, by name.
    public mutating func take(_ files: [File], now: Date) -> [File] {
        let earliest = earliest(now: now)
        taken = taken.filter { $0.value >= earliest }
        var ready: [File] = []
        var waiting = false
        for file in files where file.created >= earliest && taken[file.name] == nil && !Self.isTemporary(file.name) {
            let isNew = now.timeIntervalSince(file.created) < Self.settleTime
            if file.size <= 0 {
                if isNew { waiting = true }
                continue
            }
            switch file.isScreenCapture {
            case true?:
                ready.append(file)
            case false?:
                continue
            case nil:
                if Self.hasScreenshotName(file.name) {
                    ready.append(file)
                } else if isNew {
                    waiting = true
                }
            }
        }
        ready.sort { ($0.created, $0.name) < ($1.created, $1.name) }
        for file in ready { taken[file.name] = file.created }
        isWaiting = waiting
        return ready
    }

    /// Hidden files (macOS writes a screenshot as one first, then renames it) and the names apps use
    /// while a file is still arriving.
    public static func isTemporary(_ name: String) -> Bool {
        if name.hasPrefix(".") || name.hasPrefix("~") { return true }
        let lower = name.lowercased()
        return [".tmp", ".part", ".partial", ".download", ".crdownload"].contains { lower.hasSuffix($0) }
    }

    public static func hasScreenshotName(_ name: String) -> Bool {
        namePrefixes.contains { name.hasPrefix($0) }
    }

    /// Reads the attribute's value, a property list holding a boolean. Nil when there is none, or it
    /// can't be read.
    public static func flag(attribute data: Data?) -> Bool? {
        guard let data, let value = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return nil }
        if let number = value as? NSNumber { return number.boolValue }
        if let text = value as? String { return ["1", "true", "yes"].contains(text.lowercased()) }
        return nil
    }
}
