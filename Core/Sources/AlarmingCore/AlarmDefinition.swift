import Foundation

public struct AlarmDefinition: Codable, Hashable, Identifiable, Sendable {
    public static let defaultLabel = "Alarm"
    public static let oneTimeName = "One-time"

    public let id: UUID
    public var hour: Int
    public var minute: Int
    /// Choosing days makes the alarm repeat, so it is no longer one-time.
    public var days: Set<Locale.Weekday> {
        didSet { if !days.isEmpty { isOneTime = false } }
    }
    public var label: String
    /// Bundled sound file name, or `nil` for the system default.
    public var tone: String?
    /// Kept while one-time so switching back restores it. Rings use `effectiveSnooze`.
    public var snooze: SnoozePolicy
    public var isEnabled: Bool
    /// Rings once without snooze and is deleted when stopped. Never has days.
    public var isOneTime: Bool {
        didSet { if isOneTime { days = [] } }
    }
    /// When a scheduled one-time alarm rings, so a ring that finished can be told from one that was lost.
    public internal(set) var firesAt: Date?

    public init(
        id: UUID = UUID(), hour: Int, minute: Int, days: Set<Locale.Weekday> = [],
        label: String = AlarmDefinition.defaultLabel, tone: String? = nil,
        snooze: SnoozePolicy = SnoozePolicy(), isEnabled: Bool = true, isOneTime: Bool = false
    ) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.days = isOneTime ? [] : days
        self.label = label
        self.tone = tone
        self.snooze = snooze
        self.isEnabled = isEnabled
        self.isOneTime = isOneTime
    }

    private enum CodingKeys: String, CodingKey {
        case id, hour, minute, days, label, tone, snooze, isEnabled, isOneTime, firesAt
    }

    /// Files and ring snapshots written before one-time alarms existed have neither key.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            hour: try values.decode(Int.self, forKey: .hour),
            minute: try values.decode(Int.self, forKey: .minute),
            days: try values.decode(Set<Locale.Weekday>.self, forKey: .days),
            label: try values.decode(String.self, forKey: .label),
            tone: try values.decodeIfPresent(String.self, forKey: .tone),
            snooze: try values.decode(SnoozePolicy.self, forKey: .snooze),
            isEnabled: try values.decode(Bool.self, forKey: .isEnabled),
            isOneTime: try values.decodeIfPresent(Bool.self, forKey: .isOneTime) ?? false)
        firesAt = try values.decodeIfPresent(Date.self, forKey: .firesAt)
    }

    public var displayLabel: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultLabel : trimmed
    }

    /// What actually rings: one-time alarms never snooze.
    public var effectiveSnooze: SnoozePolicy {
        isOneTime ? SnoozePolicy(isEnabled: false) : snooze
    }

    /// "One-time", "No repeat", "Weekdays" and so on.
    public func repeatSummary(calendar: Calendar = .current) -> String {
        isOneTime ? Self.oneTimeName : RepeatDays.summary(days, calendar: calendar)
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
