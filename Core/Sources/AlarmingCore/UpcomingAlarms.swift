import Foundation

/// What the Home Screen widget needs to name the next ring without the app running.
public struct UpcomingAlarms: Codable, Equatable, Sendable {
    public struct Next: Equatable, Sendable {
        public let alarm: AlarmDefinition
        public let date: Date
    }

    public let publishedAt: Date
    public let alarms: [AlarmDefinition]

    public init(publishedAt: Date, alarms: [AlarmDefinition]) {
        self.publishedAt = publishedAt
        self.alarms = alarms
    }

    public func next(after now: Date, calendar: Calendar = .current) -> Next? {
        alarms.compactMap { alarm in
            // A one-time alarm rings once, so it must not roll to tomorrow after it has rung.
            let start = alarm.days.isEmpty ? publishedAt : now
            guard let date = alarm.nextOccurrence(after: start, calendar: calendar), date > now else { return nil }
            return Next(alarm: alarm, date: date)
        }
        .min { $0.date < $1.date }
    }

    /// Every moment the widget's content changes: each ring, and each midnight because it names the day.
    public func changes(after now: Date, limit: Int, calendar: Calendar = .current) -> [Date] {
        var dates: [Date] = []
        var last = now
        while dates.count < limit, let ring = next(after: last, calendar: calendar)?.date {
            let midnight = calendar.nextDate(after: last, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime)
            last = min(ring, midnight ?? ring)
            dates.append(last)
        }
        return dates
    }
}

public struct UpcomingAlarmsFile: Sendable {
    private let url: URL
    public init(url: URL) { self.url = url }

    public func load() -> UpcomingAlarms? {
        try? JSONDecoder().decode(UpcomingAlarms.self, from: Data(contentsOf: url))
    }

    /// Returns whether anything changed, so the widget is only reloaded when it needs to be.
    public func publish(_ alarms: [AlarmDefinition], now: Date = .now) throws -> Bool {
        guard load()?.alarms != alarms else { return false }
        var options: Data.WritingOptions = .atomic
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try JSONEncoder().encode(UpcomingAlarms(publishedAt: now, alarms: alarms)).write(to: url, options: options)
        return true
    }
}
