import Foundation
import Testing
@testable import AlarmingCore

private var newYork: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    calendar.locale = Locale(identifier: "en_US")
    return calendar
}

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
    newYork.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

@Suite struct SnoozePolicyTests {
    @Test func initialRingsThreeTimes() {
        #expect(SnoozePolicy.initial.intervals == [900, 600])
    }

    @Test func subtractExample() {
        let policy = SnoozePolicy(firstMinutes: 15, style: .subtract(minutes: 5))
        #expect(policy.intervals == [900, 600, 300])
        #expect(policy.ringTimes(from: date(2026, 12, 1, 7, 0)) ==
            [0, 15, 25, 30].map { date(2026, 12, 1, 7, $0) })
        #expect(policy.interval(after: 3) == nil)
    }

    @Test func halfExample() {
        let policy = SnoozePolicy(firstMinutes: 10, style: .multiply(.half), limit: 3)
        #expect(policy.intervals == [600, 300, 150])
        #expect(policy.projectedWake(from: date(2026, 12, 1, 7, 0)) == date(2026, 12, 1, 7, 17, 30))
    }

    @Test func constantLimitAndNoLimit() {
        #expect(SnoozePolicy(limit: 2).intervals == [540, 540])
        #expect(SnoozePolicy(limit: 2).interval(after: 2) == nil)
        #expect(SnoozePolicy().intervals == nil)
        #expect(SnoozePolicy().projectedWake(from: .now) == nil)
        #expect(SnoozePolicy().interval(after: 500) == 540)
    }

    @Test func disabledRingsOnce() {
        let start = date(2026, 12, 1, 7, 0)
        let policy = SnoozePolicy(isEnabled: false)
        #expect(policy.interval(after: 0) == nil)
        #expect(policy.ringTimes(from: start) == [start])
    }

    @Test func firstShorterThanStepAllowsOneSnooze() {
        #expect(SnoozePolicy(firstMinutes: 3, style: .subtract(minutes: 5)).intervals == [180])
    }

    @Test func exactlyOneMinuteIsAllowed() {
        #expect(SnoozePolicy(firstMinutes: 3, style: .subtract(minutes: 1)).intervals == [180, 120, 60])
    }

    @Test func limitAboveNaturalMaximumHasNoEffect() {
        #expect(SnoozePolicy(firstMinutes: 4, style: .multiply(.half), limit: 10).intervals == [240, 120, 60])
    }

    @Test(arguments: SnoozePolicy.Fraction.allCases, [1, 2, 9, 10, 30])
    func fractionsShrinkToFloor(fraction: SnoozePolicy.Fraction, first: Int) throws {
        let policy = SnoozePolicy(firstMinutes: first, style: .multiply(fraction))
        let intervals = try #require(policy.intervals)
        #expect(intervals.first == first * 60)
        #expect(zip(intervals, intervals.dropFirst()).allSatisfy { $0 > $1 })
        let ratio = Double(fraction.numerator) / Double(fraction.denominator)
        #expect(intervals.allSatisfy { $0 >= 60 })
        // The next one must genuinely be too short, proving the safety bound did not cut it off.
        #expect(Double(first * 60) * pow(ratio, Double(intervals.count)) < 60)
    }

    @Test func invalidValuesAreClampedIncludingWhenDecoded() throws {
        var policy = SnoozePolicy(firstMinutes: 0, style: .subtract(minutes: 0), limit: 0)
        #expect(policy.firstMinutes == 1 && policy.limit == 1 && policy.style == .subtract(minutes: 1))
        policy.firstMinutes = 99
        policy.limit = 99
        policy.style = .subtract(minutes: -4)
        #expect(policy.firstMinutes == 30 && policy.limit == 10 && policy.style == .subtract(minutes: 1))
        let json = Data(#"{"isEnabled":true,"firstMinutes":900,"style":{"subtract":{"minutes":0}},"limit":50}"#.utf8)
        let decoded = try JSONDecoder().decode(SnoozePolicy.self, from: json)
        #expect(decoded == SnoozePolicy(firstMinutes: 30, style: .subtract(minutes: 1), limit: 10))
    }
}

@Suite struct AlarmDefinitionTests {
    @Test func projectionCrossesMidnight() {
        let policy = SnoozePolicy(firstMinutes: 15, style: .subtract(minutes: 5))
        #expect(policy.projectedWake(from: date(2026, 12, 1, 23, 50)) == date(2026, 12, 2, 0, 20))
    }

    @Test func oneTimeRollsToTomorrow() {
        let alarm = AlarmDefinition(hour: 7, minute: 0)
        #expect(alarm.nextOccurrence(after: date(2026, 12, 1, 7, 0), calendar: newYork) == date(2026, 12, 2, 7, 0))
    }

    @Test func weekdaysSkipWeekend() {
        let alarm = AlarmDefinition(hour: 7, minute: 0, days: RepeatDays.weekdays)
        #expect(alarm.nextOccurrence(after: date(2026, 12, 4, 8, 0), calendar: newYork) == date(2026, 12, 7, 7, 0))
    }

    @Test func clockChanges() {
        let alarm = AlarmDefinition(hour: 2, minute: 30)
        // 2:30 does not exist on March 14, 2027, so the next valid moment is 3:00.
        #expect(alarm.nextOccurrence(after: date(2027, 3, 14, 1, 0), calendar: newYork) == date(2027, 3, 14, 3, 0))
        let seven = AlarmDefinition(hour: 7, minute: 0)
        #expect(seven.nextOccurrence(after: date(2027, 3, 13, 22, 0), calendar: newYork) == date(2027, 3, 14, 7, 0))
        #expect(seven.nextOccurrence(after: date(2026, 10, 31, 22, 0), calendar: newYork) == date(2026, 11, 1, 7, 0))
    }

    @Test func projectionAcrossSpringForward() {
        let policy = SnoozePolicy(firstMinutes: 20, limit: 1)
        #expect(policy.projectedWake(from: date(2027, 3, 14, 1, 50)) == date(2027, 3, 14, 3, 10))
    }

    @Test(arguments: ["", "  \n", "Alarm"])
    func blankLabelDefaults(label: String) {
        #expect(AlarmDefinition(hour: 1, minute: 1, label: label).displayLabel == "Alarm")
    }

    @Test func labelIsTrimmed() {
        #expect(AlarmDefinition(hour: 1, minute: 1, label: " Gym ").displayLabel == "Gym")
    }

    @Test func repeatSummaries() {
        #expect(RepeatDays.summary([], calendar: newYork) == "Once")
        #expect(RepeatDays.summary(RepeatDays.everyDay, calendar: newYork) == "Every day")
        #expect(RepeatDays.summary(RepeatDays.weekdays, calendar: newYork) == "Weekdays")
        #expect(RepeatDays.summary(RepeatDays.weekends, calendar: newYork) == "Weekends")
        #expect(RepeatDays.summary(RepeatDays.mondayWednesdayFriday, calendar: newYork) == "Mon, Wed, Fri")
        // Monday first, even where the calendar starts on Sunday.
        #expect(RepeatDays.summary([.sunday, .monday], calendar: newYork) == "Mon, Sun")
        #expect(RepeatDays.inWeekOrder(calendar: newYork).map(\.letter) == ["M", "T", "W", "Th", "F", "S", "Su"])
    }

    @Test func jsonRoundTrip() throws {
        let alarm = AlarmDefinition(
            hour: 6, minute: 45, days: RepeatDays.mondayWednesdayFriday, label: "Gym", tone: "chime",
            snooze: SnoozePolicy(firstMinutes: 10, style: .multiply(.twoThirds), limit: 4))
        #expect(try JSONDecoder().decode(AlarmDefinition.self, from: JSONEncoder().encode(alarm)) == alarm)
    }
}
