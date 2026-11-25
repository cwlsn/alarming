import Foundation

public struct AlarmDefinition: Codable, Hashable, Identifiable, Sendable {
    public static let defaultLabel = "Alarm"

    public let id: UUID
    public var hour: Int
    public var minute: Int
    public var days: Set<Locale.Weekday>
    public var label: String
    /// Bundled sound file name, or `nil` for the system default.
    public var tone: String?
    public var snooze: SnoozePolicy
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(), hour: Int, minute: Int, days: Set<Locale.Weekday> = [],
        label: String = AlarmDefinition.defaultLabel, tone: String? = nil,
        snooze: SnoozePolicy = SnoozePolicy(), isEnabled: Bool = true
    ) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.days = days
        self.label = label
        self.tone = tone
        self.snooze = snooze
        self.isEnabled = isEnabled
    }

    public var displayLabel: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultLabel : trimmed
    }

    /// Next ring strictly after `now`, following the calendar through midnight and clock changes.
    public func nextOccurrence(after now: Date, calendar: Calendar = .current) -> Date? {
        let time = DateComponents(hour: hour, minute: minute, second: 0)
        guard !days.isEmpty else {
            return calendar.nextDate(after: now, matching: time, matchingPolicy: .nextTime)
        }
        return days.compactMap { day in
            var components = time
            components.weekday = RepeatDays.number(of: day)
            return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime)
        }.min()
    }
}
