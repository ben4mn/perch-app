import Foundation

public struct ParsedWhen: Equatable, Sendable {
    public var date: String?
    public var time: String?
    public var recurrence: String?
}

/// Calendar dates are plain `yyyy-MM-dd` strings in the local calendar, as in the files.
public enum DayMath {
    public static func string(from date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    public static func date(from string: String, calendar: Calendar = .current) -> Date? {
        let parts = string.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    public static func adding(days: Int, to string: String, calendar: Calendar = .current) -> String? {
        guard let start = date(from: string, calendar: calendar),
              let result = calendar.date(byAdding: .day, value: days, to: start) else { return nil }
        return self.string(from: result, calendar: calendar)
    }
}

public enum Recurrence {
    private static let weekdays: [(names: [String], number: Int)] = [
        (["sunday", "sun"], 1), (["monday", "mon"], 2), (["tuesday", "tue", "tues"], 3),
        (["wednesday", "wed"], 4), (["thursday", "thu", "thur", "thurs"], 5), (["friday", "fri"], 6), (["saturday", "sat"], 7),
    ]

    static func weekday(named name: String) -> Int? {
        weekdays.first { $0.names.contains(name) }?.number
    }

    public static func isSupported(_ rule: String) -> Bool {
        next(rule: rule, after: "2026-01-01", calendar: Calendar(identifier: .gregorian)) != nil
    }

    /// The next due date for a rule. Returns nil for a rule Perch doesn't understand,
    /// so the app can ask instead of guessing.
    public static func next(rule: String, after due: String, calendar: Calendar = .current) -> String? {
        var words = rule.lowercased().replacingOccurrences(of: ",", with: " ").split(separator: " ").map(String.init)
        if words.first == "every" || words.first == "every!" { words.removeFirst() } else { return nil }
        if words.first == "other" { words[0] = "2" }
        guard let start = DayMath.date(from: due, calendar: calendar) else { return nil }

        func advanced(_ component: Calendar.Component, _ count: Int) -> String? {
            calendar.date(byAdding: component, value: count, to: start).map { DayMath.string(from: $0, calendar: calendar) }
        }

        if words == ["weekday"] || words == ["workday"] || words == ["weekdays"] {
            var candidate = start
            repeat {
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate)!
            } while [1, 7].contains(calendar.component(.weekday, from: candidate))
            return DayMath.string(from: candidate, calendar: calendar)
        }

        let names = words.filter { $0 != "and" }
        if !names.isEmpty, names.allSatisfy({ weekday(named: $0) != nil }) {
            let targets = Set(names.compactMap(weekday(named:)))
            var candidate = start
            for _ in 0..<7 {
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate)!
                if targets.contains(calendar.component(.weekday, from: candidate)) {
                    return DayMath.string(from: candidate, calendar: calendar)
                }
            }
            return nil
        }

        var count = 1
        var unitWords = words
        if let first = unitWords.first, let number = Int(first) {
            count = number
            unitWords.removeFirst()
        }
        guard unitWords.count == 1, count > 0 else { return nil }
        switch unitWords[0] {
        case "day", "days": return advanced(.day, count)
        case "week", "weeks": return advanced(.day, count * 7)
        case "month", "months": return advanced(.month, count)
        case "year", "years": return advanced(.year, count)
        default: return nil
        }
    }
}

public enum NaturalDates {
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// Finds a date phrase in free text. Returns what it found and the text without it.
    public static func extract(from text: String, today: Date = Date(), calendar: Calendar = .current) -> (when: ParsedWhen, remainder: String) {
        var when = ParsedWhen()
        var remainder = text
        let todayString = DayMath.string(from: today, calendar: calendar)

        func take(_ pattern: String, _ handler: ([String]) -> Bool) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return }
            let range = NSRange(remainder.startIndex..., in: remainder)
            guard let match = regex.firstMatch(in: remainder, range: range), let whole = Range(match.range, in: remainder) else { return }
            let groups: [String] = (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: remainder).map { String(remainder[$0]) } ?? ""
            }
            if handler(groups) { remainder.removeSubrange(whole) }
        }

        take(#"(?:^|\s)(every!?\s+(?:other\s+)?(?:\d+\s+)?[a-z]+(?:(?:\s+and\s+|,\s*)[a-z]+)*)(?=\s|$)"#) { groups in
            let rule = groups[1].lowercased()
            guard Recurrence.isSupported(rule) else { return false }
            when.recurrence = rule
            when.date = firstOccurrence(rule: rule, today: todayString, calendar: calendar)
            return true
        }

        take(#"(?:^|\s)(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)(?=\s|$)"#) { groups in
            guard var hour = Int(groups[1]), (1...12).contains(hour) else { return false }
            if groups[3].lowercased() == "pm", hour < 12 { hour += 12 }
            if groups[3].lowercased() == "am", hour == 12 { hour = 0 }
            when.time = String(format: "%02d:%@", hour, groups[2].isEmpty ? "00" : groups[2])
            return true
        }
        take(#"(?:^|\s)at\s+(\d{1,2}):(\d{2})(?=\s|$)"#) { groups in
            guard let hour = Int(groups[1]), hour < 24 else { return false }
            when.time = String(format: "%02d:%@", hour, groups[2])
            return true
        }

        if when.date == nil {
            take(#"(?:^|\s)(\d{4}-\d{2}-\d{2})(?=\s|$)"#) { groups in
                when.date = groups[1]
                return true
            }
        }
        if when.date == nil {
            take(#"(?:^|\s)(today|tonight|tod)(?=\s|$)"#) { _ in
                when.date = todayString
                return true
            }
        }
        if when.date == nil {
            take(#"(?:^|\s)(tomorrow|tmrw|tom)(?=\s|$)"#) { _ in
                when.date = DayMath.adding(days: 1, to: todayString, calendar: calendar)
                return true
            }
        }
        if when.date == nil {
            take(#"(?:^|\s)in\s+(\d+)\s+(day|days|week|weeks)(?=\s|$)"#) { groups in
                guard let count = Int(groups[1]) else { return false }
                when.date = DayMath.adding(days: groups[2].lowercased().hasPrefix("week") ? count * 7 : count, to: todayString, calendar: calendar)
                return true
            }
        }
        if when.date == nil {
            take(#"(?:^|\s)next\s+week(?=\s|$)"#) { _ in
                when.date = DayMath.adding(days: 7, to: todayString, calendar: calendar)
                return true
            }
        }
        if when.date == nil {
            take(#"(?:^|\s)((?:next|on)\s+)?(sunday|sun|monday|mon|tuesday|tues|tue|wednesday|wed|thursday|thurs|thur|thu|friday|fri|saturday|sat)(?=\s|$)"#) { groups in
                guard let target = Recurrence.weekday(named: groups[2].lowercased()) else { return false }
                let current = calendar.component(.weekday, from: today)
                var offset = (target - current + 7) % 7
                if offset == 0 { offset = 7 }
                if groups[1].lowercased().hasPrefix("next"), offset < 7, target > current { offset += 7 }
                when.date = DayMath.adding(days: offset, to: todayString, calendar: calendar)
                return true
            }
        }
        if when.date == nil {
            take(#"(?:^|\s)(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?(?=\s|$)"#) { groups in
                guard let month = months.firstIndex(of: String(groups[1].lowercased().prefix(3))), let day = Int(groups[2]) else { return false }
                var year = Int(groups[3]) ?? calendar.component(.year, from: today)
                var candidate = String(format: "%04d-%02d-%02d", year, month + 1, day)
                if groups[3].isEmpty, candidate < todayString {
                    year += 1
                    candidate = String(format: "%04d-%02d-%02d", year, month + 1, day)
                }
                when.date = candidate
                return true
            }
        }
        if when.time != nil, when.date == nil { when.date = todayString }
        return (when, jsTrim(remainder.replacingOccurrences(of: "  ", with: " ")))
    }

    private static func firstOccurrence(rule: String, today: String, calendar: Calendar) -> String? {
        let words = rule.split(separator: " ").dropFirst().map(String.init)
        if words.allSatisfy({ Recurrence.weekday(named: $0.replacingOccurrences(of: ",", with: "")) != nil || $0 == "and" }) {
            // Weekday rules start on the next matching day, or today if it matches.
            if let yesterday = DayMath.adding(days: -1, to: today, calendar: calendar) {
                return Recurrence.next(rule: rule, after: yesterday, calendar: calendar)
            }
        }
        return today
    }
}

/// The result of parsing a quick-add line like `Call the vet tomorrow 5pm #Personal !p2 @claude`.
public struct QuickAdd: Equatable, Sendable {
    public var title: String
    public var area: String?
    public var labels: [String] = []
    public var owner: String?
    public var priority: Int?
    public var due: String?
    public var time: String?
    public var recurrence: String?

    public static func parse(_ text: String, areas: [String] = [], today: Date = Date(), calendar: Calendar = .current) -> QuickAdd {
        var result = QuickAdd(title: "")
        var kept: [String] = []
        for word in text.split(separator: " ", omittingEmptySubsequences: true).map(String.init) {
            let lower = word.lowercased()
            if lower.range(of: #"^!p?[1-4]$"#, options: .regularExpression) != nil, let last = lower.last, let value = Int(String(last)) {
                result.priority = value
            } else if word.hasPrefix("#"), word.count > 1 {
                let name = String(word.dropFirst())
                if let area = areas.first(where: { simplifiedArea($0).caseInsensitiveCompare(name) == .orderedSame }) {
                    result.area = area
                } else {
                    result.labels.append(name)
                }
            } else if word.hasPrefix("@"), word.count > 1 {
                result.owner = String(word.dropFirst())
            } else {
                kept.append(word)
            }
        }
        let extracted = NaturalDates.extract(from: kept.joined(separator: " "), today: today, calendar: calendar)
        result.title = extracted.remainder
        result.due = extracted.when.date
        result.time = extracted.when.time
        result.recurrence = extracted.when.recurrence
        return result
    }

    /// `✈️ Work` matches `#Work`.
    public static func simplifiedArea(_ area: String) -> String {
        jsTrim(String(String.UnicodeScalarView(area.unicodeScalars.filter {
            $0.properties.isAlphabetic || $0.properties.numericType != nil || $0 == " " || $0 == "-" || $0 == "_"
        })))
    }
}
