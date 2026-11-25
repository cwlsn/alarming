import Foundation
import Testing
@testable import AlarmingCore

@Suite struct UpcomingAlarmsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }
    /// 25 November 2026 is a Wednesday.
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func earliestWins() {
        let upcoming = UpcomingAlarms(publishedAt: date(25, 8), alarms: [
            AlarmDefinition(hour: 9, minute: 0, days: RepeatDays.weekends, label: "Late"),
            AlarmDefinition(hour: 22, minute: 30, days: RepeatDays.everyDay, label: "Soon"),
        ])
        #expect(upcoming.next(after: date(25, 10), calendar: calendar)?.alarm.label == "Soon")
        #expect(upcoming.next(after: date(25, 10), calendar: calendar)?.date == date(25, 22, 30))
    }

    @Test func oneTimeDoesNotRollToTomorrow() {
        let upcoming = UpcomingAlarms(publishedAt: date(25, 8), alarms: [AlarmDefinition(hour: 9, minute: 0)])
        #expect(upcoming.next(after: date(25, 8, 59), calendar: calendar)?.date == date(25, 9))
        #expect(upcoming.next(after: date(25, 9), calendar: calendar) == nil)
    }

    @Test func repeatingContinues() {
        let upcoming = UpcomingAlarms(publishedAt: date(25, 8), alarms: [AlarmDefinition(hour: 9, minute: 0, days: RepeatDays.weekdays)])
        #expect(upcoming.next(after: date(27, 9), calendar: calendar)?.date == date(30, 9))
    }

    @Test func changesIncludeMidnightsAndRings() {
        let upcoming = UpcomingAlarms(publishedAt: date(25, 8), alarms: [AlarmDefinition(hour: 7, minute: 0)])
        #expect(upcoming.changes(after: date(25, 10), limit: 10, calendar: calendar) == [date(26, 0), date(26, 7)])
        #expect(UpcomingAlarms(publishedAt: date(25, 8), alarms: []).changes(after: date(25, 10), limit: 10, calendar: calendar).isEmpty)
        let daily = UpcomingAlarms(publishedAt: date(25, 8), alarms: [AlarmDefinition(hour: 7, minute: 0, days: RepeatDays.everyDay)])
        #expect(daily.changes(after: date(25, 10), limit: 5, calendar: calendar).count == 5)
    }

    @Test func publishSkipsUnchanged() throws {
        let file = UpcomingAlarmsFile(url: URL.temporaryDirectory.appending(path: "\(UUID()).json"))
        let alarms = [AlarmDefinition(hour: 7, minute: 0)]
        #expect(file.load() == nil)
        #expect(try file.publish(alarms, now: date(25, 8)))
        #expect(try !file.publish(alarms, now: date(26, 8)))
        #expect(file.load()?.publishedAt == date(25, 8))
        #expect(try file.publish([]))
    }

    @MainActor @Test func modelPublishesOnlyWhatWillRing() async throws {
        final class Client: AlarmClient, @unchecked Sendable {
            var state: [UUID: RingState] = [:]
            var denied = false
            func authorize() async throws -> Bool { !denied }
            func isDenied() -> Bool { denied }
            func rings() throws -> [UUID: RingState] { state }
            func schedule(_ request: RingRequest) async throws { state[request.id] = .scheduled }
            func stop(_ id: UUID) throws { state[id] = nil }
            func cancel(_ id: UUID) throws { state[id] = nil }
        }
        let client = Client()
        var published: [AlarmDefinition] = []
        let model = AlarmModel(client: client, file: AlarmFile(url: URL.temporaryDirectory.appending(path: "\(UUID()).json"))) { published = $0 }
        let once = AlarmDefinition(hour: 7, minute: 0)
        let daily = AlarmDefinition(hour: 8, minute: 0, days: RepeatDays.everyDay)
        try await model.save(once)
        try await model.save(daily)
        try await model.save(AlarmDefinition(hour: 9, minute: 0, isEnabled: false))
        #expect(published.map(\.id) == [once.id, daily.id])
        // Ringing now, so its next occurrence is not tomorrow.
        client.state[once.id] = .alerting
        try await model.reconcile()
        #expect(published.map(\.id) == [daily.id])
        client.denied = true
        try await model.reconcile()
        #expect(published.isEmpty)
    }
}
