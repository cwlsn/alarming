import Foundation

/// Reads a typed line such as "7:30 weekdays gym" or "in 20m nap".
public enum QuickEntry {
    public struct Result: Equatable, Sendable {
        public var hour: Int
        public var minute: Int
        public var days: Set<Locale.Weekday>
        public var label: String
    }

    private static let dayWords: [String: Set<Locale.Weekday>] = [
        "sun": [.sunday], "sunday": [.sunday], "sundays": [.sunday],
        "mon": [.monday], "monday": [.monday], "mondays": [.monday],
        "tue": [.tuesday], "tues": [.tuesday], "tuesday": [.tuesday], "tuesdays": [.tuesday],
        "wed": [.wednesday], "wednesday": [.wednesday], "wednesdays": [.wednesday],
        "thu": [.thursday], "thur": [.thursday], "thurs": [.thursday], "thursday": [.thursday], "thursdays": [.thursday],
        "fri": [.friday], "friday": [.friday], "fridays": [.friday],
        "sat": [.saturday], "saturday": [.saturday], "saturdays": [.saturday],
        "weekday": RepeatDays.weekdays, "weekdays": RepeatDays.weekdays,
        "weekend": RepeatDays.weekends, "weekends": RepeatDays.weekends,
        "daily": RepeatDays.everyDay, "everyday": RepeatDays.everyDay,
        "mwf": RepeatDays.mondayWednesdayFriday,
    ]

    /// `nil` when there is no time, or when the line asks for a date an alarm cannot hold.
    public static func parse(_ text: String, now: Date, uses24Hour: Bool, calendar: Calendar = .current) -> Result? {
        let words = text.split { $0.isWhitespace || $0 == "," }.map(String.init)
        var label: [String] = []
        var days: Set<Locale.Weekday> = []
        var clock: Clock?
        var relativeMinutes: Int?
        var namedDay: Int?
        var index = 0

        while index < words.count {
            let word = words[index].lowercased()
            let next = index + 1 < words.count ? words[index + 1].lowercased() : nil
            let hasTime = clock != nil || relativeMinutes != nil
            index += 1
            if !hasTime, word == "in", let next, let minutes = duration(next, unit: index + 1 < words.count ? words[index + 1] : nil) {
                relativeMinutes = minutes.value
                index += minutes.usedUnit ? 2 : 1
            } else if !hasTime, word == "at", let next, time(next) != nil {
                continue
            } else if !hasTime, let found = time(word) {
                clock = found
                if found.isPM == nil, found.hour <= 12, found.hour > 0, let next, let isPM = meridiem(next) {
                    clock?.isPM = isPM
                    index += 1
                }
            } else if word == "every", let next, next == "day" || dayWords[next] != nil {
                if next == "day" { days = RepeatDays.everyDay; index += 1 }
            } else if let found = dayWords[word] {
                days.formUnion(found)
            } else if word == "today" || word == "tomorrow" {
                namedDay = word == "today" ? 0 : 1
            } else {
                label.append(words[index - 1])
            }
        }

        let hour, minute: Int
        if let relativeMinutes {
            // Rounded up so the alarm never lands before the requested time.
            let target = now.addingTimeInterval(TimeInterval(relativeMinutes * 60))
            let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: target)
            let partial = (parts.second ?? 0) > 0 || (parts.nanosecond ?? 0) > 0
            let total = ((parts.hour ?? 0) * 60 + (parts.minute ?? 0) + (partial ? 1 : 0)) % 1440
            (hour, minute) = (total / 60, total % 60)
            guard days.isEmpty else { return nil }
        } else if let clock {
            minute = clock.minute
            if let isPM = clock.isPM {
                hour = clock.hour % 12 + (isPM ? 12 : 0)
            } else if uses24Hour || clock.isExplicit24 {
                hour = clock.hour
            } else {
                let morning = clock.hour % 12
                // A repeating time without AM or PM is a morning alarm; a one-time alarm takes whichever is sooner.
                hour = days.isEmpty
                    ? [morning, morning + 12].min { distance($0, minute, now, calendar) < distance($1, minute, now, calendar) }!
                    : morning
            }
        } else {
            return nil
        }

        let result = Result(hour: hour, minute: minute, days: days, label: label.joined(separator: " "))
        if let namedDay {
            // One-time alarms ring at the next matching time, so any other day cannot be honored.
            let alarm = AlarmDefinition(hour: hour, minute: minute)
            guard days.isEmpty, let ring = alarm.nextOccurrence(after: now, calendar: calendar),
                  let wanted = calendar.date(byAdding: .day, value: namedDay, to: now),
                  calendar.isDate(ring, inSameDayAs: wanted) else { return nil }
        }
        return result
    }

    private struct Clock {
        var hour: Int
        var minute: Int
        var isPM: Bool?
        var isExplicit24: Bool
    }

    private static func meridiem(_ word: String) -> Bool? {
        switch word {
        case "am", "a.m.", "a": false
        case "pm", "p.m.", "p": true
        default: nil
        }
    }

    private static func time(_ word: String) -> Clock? {
        if word == "noon" { return Clock(hour: 12, minute: 0, isPM: true, isExplicit24: false) }
        if word == "midnight" { return Clock(hour: 12, minute: 0, isPM: false, isExplicit24: false) }
        guard let match = word.wholeMatch(of: /(\d{1,2})(?:[:.](\d{2}))?(am|pm|a|p)?/),
              let hour = Int(match.1), let minute = Int(match.2 ?? "0"), minute < 60 else { return nil }
        let isPM = match.3.flatMap { meridiem(String($0)) }
        guard isPM == nil ? hour < 24 : (1...12).contains(hour) else { return nil }
        return Clock(hour: hour, minute: minute, isPM: isPM, isExplicit24: hour > 12 || hour == 0 || match.1.hasPrefix("0"))
    }

    private static func duration(_ word: String, unit: String?) -> (value: Int, usedUnit: Bool)? {
        func factor(_ unit: String) -> Int? {
            switch unit {
            case "m", "min", "mins", "minute", "minutes": 1
            case "h", "hr", "hrs", "hour", "hours": 60
            default: nil
            }
        }
        let total: Int
        var usedUnit = false
        if let match = word.wholeMatch(of: /(\d{1,2})h(\d{1,2})m?/), let hours = Int(match.1), let minutes = Int(match.2) {
            total = hours * 60 + minutes
        } else if let match = word.wholeMatch(of: /(\d{1,4})([a-z]+)/), let value = Int(match.1), let factor = factor(String(match.2)) {
            total = value * factor
        } else if let value = Int(word), word.count <= 4, let factor = unit.flatMap({ factor($0.lowercased()) }) {
            total = value * factor
            usedUnit = true
        } else {
            return nil
        }
        return (1..<1440).contains(total) ? (total, usedUnit) : nil
    }

    private static func distance(_ hour: Int, _ minute: Int, _ now: Date, _ calendar: Calendar) -> TimeInterval {
        AlarmDefinition(hour: hour, minute: minute).nextOccurrence(after: now, calendar: calendar)?.timeIntervalSince(now) ?? .infinity
    }
}
