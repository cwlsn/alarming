import Foundation
import Testing
@testable import AlarmingCore

@Suite struct QuickEntryTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }
    /// Wednesday 10:15:30 PM
    private var night: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 22, minute: 15, second: 30))! }

    private func parse(_ text: String, uses24Hour: Bool = false) -> QuickEntry.Result? {
        QuickEntry.parse(text, now: night, uses24Hour: uses24Hour, calendar: calendar)
    }

    @Test func timeDaysAndLabel() {
        #expect(parse("7:30 weekdays Morning gym") == .init(hour: 7, minute: 30, days: RepeatDays.weekdays, label: "Morning gym"))
        #expect(parse("Gym mon, wed 6pm") == .init(hour: 18, minute: 0, days: [.monday, .wednesday], label: "Gym"))
        #expect(parse("every day at 8 pm meds") == .init(hour: 20, minute: 0, days: RepeatDays.everyDay, label: "meds"))
        #expect(parse("every friday 5:45am") == .init(hour: 5, minute: 45, days: [.friday], label: ""))
    }

    @Test func ambiguousHours() {
        #expect(parse("7")?.hour == 7)
        #expect(parse("11")?.hour == 23)
        #expect(parse("11 daily")?.hour == 11)
        #expect(parse("11", uses24Hour: true)?.hour == 11)
        #expect(parse("07:00")?.hour == 7)
        #expect(parse("19:05")?.hour == 19)
        #expect(parse("12am")?.hour == 0)
        #expect(parse("12pm")?.hour == 12)
        #expect(parse("noon")?.hour == 12)
        #expect(parse("midnight")?.hour == 0)
    }

    @Test func relativeRoundsUpAndWraps() {
        #expect(parse("in 20m nap") == .init(hour: 22, minute: 36, days: [], label: "nap"))
        #expect(parse("in 2 hours")?.hour == 0)
        #expect(parse("in 1h30")?.minute == 46)
        #expect(parse("in 20m daily") == nil)
    }

    @Test func namedDaysMustBeHonored() {
        #expect(parse("7am tomorrow")?.label == "")
        #expect(parse("11pm tomorrow") == nil)
        #expect(parse("11pm today")?.hour == 23)
        #expect(parse("7am today") == nil)
    }

    @Test func laterNumbersStayInTheLabelAndNonsenseIsRejected() {
        #expect(parse("7am Gate 4")?.label == "Gate 4")
        #expect(parse("") == nil)
        #expect(parse("gym") == nil)
        #expect(parse("25:00") == nil)
        #expect(parse("7:75") == nil)
    }
}
