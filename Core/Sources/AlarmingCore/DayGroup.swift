import Foundation

/// A named-by-its-days shortcut for choosing several days at once.
public struct DayGroup: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var days: Set<Locale.Weekday>

    public init(id: UUID = UUID(), days: Set<Locale.Weekday>) {
        self.id = id
        self.days = days
    }

    /// "M T Th"
    public var title: String { RepeatDays.abbreviations(days) }

    public static let defaults = [
        DayGroup(days: [.monday, .tuesday, .thursday]),
        DayGroup(days: [.wednesday, .friday]),
    ]

    /// Drops groups with no days, and any that repeat another group or a built-in choice.
    public static func normalized(_ groups: [DayGroup]) -> [DayGroup] {
        var seen: Set<Set<Locale.Weekday>> = [[], RepeatDays.everyDay, RepeatDays.weekdays, RepeatDays.weekends]
        return groups.filter { seen.insert($0.days).inserted }
    }
}
