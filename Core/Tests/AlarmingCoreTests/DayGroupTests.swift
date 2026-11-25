import Foundation
import Testing
@testable import AlarmingCore

@Suite struct DayGroupTests {
    @Test func defaultTitles() {
        #expect(DayGroup.defaults.map(\.title) == ["M T Th", "W F"])
        #expect(RepeatDays.abbreviations(RepeatDays.everyDay) == "M T W Th F S Su")
    }

    @Test func normalizingDropsEmptyRepeatedAndBuiltIn() {
        let keep = DayGroup(days: [.monday])
        let groups = [DayGroup(days: []), keep, DayGroup(days: [.monday]), DayGroup(days: RepeatDays.weekends)]
        #expect(DayGroup.normalized(groups) == [keep])
        #expect(DayGroup.normalized(DayGroup.defaults) == DayGroup.defaults)
    }

    @Test func pickerUsesDistinctAbbreviations() {
        #expect(Set(RepeatDays.inWeekOrder().map(\.letter)) == ["M", "T", "W", "Th", "F", "S", "Su"])
    }
}
