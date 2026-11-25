import Foundation

public enum RepeatDays {
    public static let everyDay = Set<Locale.Weekday>([.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
    public static let weekdays = Set<Locale.Weekday>([.monday, .tuesday, .wednesday, .thursday, .friday])
    public static let weekends = Set<Locale.Weekday>([.saturday, .sunday])
    public static let mondayWednesdayFriday = Set<Locale.Weekday>([.monday, .wednesday, .friday])

    private static let letters = ["Su", "M", "T", "W", "Th", "F", "S"]

    /// Monday first, such as "M T Th".
    public static func abbreviations(_ days: Set<Locale.Weekday>) -> String {
        (1...7).map { $0 % 7 }.filter { days.contains(ordered[$0]) }.map { letters[$0] }.joined(separator: " ")
    }

    static let ordered: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]

    /// Calendar weekday numbering, where Sunday is 1.
    static func number(of day: Locale.Weekday) -> Int { ordered.firstIndex(of: day)! + 1 }

    /// Days from Monday, with distinct abbreviations and localized names.
    public static func inWeekOrder(calendar: Calendar = .current) -> [(day: Locale.Weekday, letter: String, name: String)] {
        (0..<7).map {
            let index = ($0 + 1) % 7
            return (ordered[index], letters[index], calendar.standaloneWeekdaySymbols[index])
        }
    }

    public static func summary(_ days: Set<Locale.Weekday>, calendar: Calendar = .current) -> String {
        if days.isEmpty { return "Once" }
        if days == everyDay { return "Every day" }
        if days == weekdays { return "Weekdays" }
        if days == weekends { return "Weekends" }
        return (0..<7)
            .map { ordered[($0 + 1) % 7] }
            .filter(days.contains)
            .map { calendar.shortWeekdaySymbols[number(of: $0) - 1] }
            .joined(separator: ", ")
    }
}
