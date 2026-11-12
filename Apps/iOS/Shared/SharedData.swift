import ActivityKit
import Foundation

/// What the app shares with its widgets and share extension through the App Group.
enum SharedStore {
    /// From each target's Info.plist (PERCH_APP_GROUP in Config/Perch.xcconfig), so the app and its
    /// extensions name the same group as their entitlements.
    static let groupID = Bundle.main.object(forInfoDictionaryKey: "PerchAppGroup") as? String ?? ""
    static var container: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) }
    static var snapshotURL: URL? { container?.appendingPathComponent("today.json") }
    static var inboxURL: URL? { container?.appendingPathComponent("Inbox", isDirectory: true) }
}

struct WidgetTask: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var priority: Int
    var isOverdue: Bool
    var area: String
}

struct WidgetSnapshot: Codable {
    var date: Date
    var total: Int
    var overdue: Int
    var tasks: [WidgetTask]
}

struct FocusAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endDate: Date?
        var startDate: Date
        var isPaused: Bool
        var pausedDisplay: String?
    }

    var taskTitle: String
}
