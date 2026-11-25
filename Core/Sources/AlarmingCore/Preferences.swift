import Foundation

/// What new alarms start with: the last tone and snooze chosen, so they rarely need setting twice.
public struct NewAlarmDefaults {
    private static let toneKey = "lastTone", snoozeKey = "newAlarmSnooze"
    private let store: UserDefaults?

    /// `nil` remembers nothing.
    public init(store: UserDefaults?) { self.store = store }

    public func remember(_ alarm: AlarmDefinition) {
        store?.set(alarm.tone, forKey: Self.toneKey)
        store?.set(try? JSONEncoder().encode(alarm.snooze), forKey: Self.snoozeKey)
    }

    public func apply(to alarm: AlarmDefinition) -> AlarmDefinition {
        var alarm = alarm
        alarm.tone = store?.string(forKey: Self.toneKey)
        alarm.snooze = store?.data(forKey: Self.snoozeKey).flatMap { try? JSONDecoder().decode(SnoozePolicy.self, from: $0) } ?? .initial
        return alarm
    }
}

/// Where day groups are kept. A missing or unreadable list becomes the defaults; an emptied one stays empty.
public struct DayGroupPreferences {
    private static let key = "dayGroups"
    private let store: UserDefaults?

    public init(store: UserDefaults?) { self.store = store }

    public func load() -> [DayGroup] {
        store?.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([DayGroup].self, from: $0) } ?? DayGroup.defaults
    }

    public func save(_ groups: [DayGroup]) {
        if let data = try? JSONEncoder().encode(DayGroup.normalized(groups)) { store?.set(data, forKey: Self.key) }
    }
}
