import Foundation
import Synchronization
import Testing
@testable import AlarmingCore

private final class Client: AlarmClient {
    let state = Mutex<[UUID: RingState]>([:])
    func authorize() async throws -> Bool { true }
    func isDenied() -> Bool { false }
    func rings() throws -> [UUID: RingState] { state.withLock { $0 } }
    func schedule(_ request: RingRequest) async throws { state.withLock { $0[request.id] = .scheduled } }
    func stop(_ id: UUID) throws { state.withLock { $0[id] = nil } }
    func cancel(_ id: UUID) throws { state.withLock { $0[id] = nil } }
    func set(_ id: UUID, _ ring: RingState?) { state.withLock { $0[id] = ring } }
}

/// The moment the model sees as now, moved by the tests.
private final class TestClock: Sendable {
    private let value = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
    var now: Date { value.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { value.withLock { $0 += seconds } }
}

private let snoozing = SnoozePolicy(firstMinutes: 10, style: .subtract(minutes: 5))

@Suite struct OneTimeDefinitionTests {
    @Test func daysAndOneTimeExcludeEachOther() {
        var alarm = AlarmDefinition(hour: 7, minute: 0, days: RepeatDays.weekdays, isOneTime: true)
        #expect(alarm.isOneTime && alarm.days.isEmpty)
        alarm.days = [.monday]
        #expect(!alarm.isOneTime)
        alarm.isOneTime = true
        #expect(alarm.days.isEmpty)
    }

    @Test func neverSnoozesButKeepsTheChoice() {
        var alarm = AlarmDefinition(hour: 7, minute: 0, snooze: snoozing, isOneTime: true)
        #expect(!alarm.effectiveSnooze.isEnabled)
        #expect(alarm.snooze == snoozing)
        let ring = RingRequest(id: alarm.id, alarm: alarm, step: 0, timing: .base)
        #expect(ring.nextSnooze == nil && ring.snoozesLeft == 0 && !ring.needsEndButton)
        alarm.isOneTime = false
        #expect(alarm.effectiveSnooze == snoozing)
    }

    @Test func summaries() {
        #expect(AlarmDefinition(hour: 7, minute: 0, isOneTime: true).repeatSummary() == "One-time")
        #expect(AlarmDefinition(hour: 7, minute: 0).repeatSummary() == "No repeat")
    }

    @Test func oldFilesAndSnapshotsStillDecode() throws {
        let json = """
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","hour":7,"minute":30,"days":[],"label":"Gym",
         "snooze":{"isEnabled":true,"firstMinutes":9,"style":{"constant":{}}},"isEnabled":true}
        """
        let alarm = try JSONDecoder().decode(AlarmDefinition.self, from: Data(json.utf8))
        #expect(alarm.hour == 7 && alarm.label == "Gym" && alarm.tone == nil)
        #expect(!alarm.isOneTime && alarm.firesAt == nil)
    }

    @Test func roundTrip() throws {
        var alarm = AlarmDefinition(hour: 6, minute: 0, label: "Nap", isOneTime: true)
        alarm.firesAt = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(try JSONDecoder().decode(AlarmDefinition.self, from: JSONEncoder().encode(alarm)) == alarm)
    }

    @Test func snoozeIsRefused() async throws {
        let client = Client(), alarm = AlarmDefinition(hour: 7, minute: 0, snooze: snoozing, isOneTime: true)
        client.set(alarm.id, .alerting)
        #expect(try await SnoozeCoordinator(client: client).snooze(currentID: alarm.id, alarm: alarm, step: 0) == .noSnoozeLeft)
        #expect(try client.rings() == [alarm.id: .alerting])
    }
}

@MainActor @Suite struct OneTimeModelTests {
    private let client = Client()
    private let clock = TestClock()
    private let url = URL.temporaryDirectory.appending(path: "alarming-\(UUID()).json")
    private func model() -> AlarmModel {
        let clock = clock
        return AlarmModel(client: client, file: AlarmFile(url: url), now: { clock.now })
    }

    @Test func savingRecordsWhenItRings() async throws {
        let model = model()
        let alarm = AlarmDefinition(hour: 7, minute: 0, isOneTime: true)
        try await model.save(alarm)
        #expect(model.alarms[0].firesAt == alarm.nextOccurrence(after: clock.now))
        try await model.setEnabled(false, id: alarm.id)
        #expect(model.alarms[0].firesAt == nil)
        try await model.save(AlarmDefinition(hour: 8, minute: 0))
        #expect(model.alarms.allSatisfy { $0.isOneTime || $0.firesAt == nil })
    }

    @Test func stoppingDeletesOnlyOneTimeAlarms() async throws {
        let model = model()
        let oneTime = AlarmDefinition(hour: 7, minute: 0, isOneTime: true)
        let noRepeat = AlarmDefinition(hour: 8, minute: 0)
        try await model.save(oneTime)
        try await model.save(noRepeat)
        for id in [oneTime.id, noRepeat.id] {
            client.set(id, nil)
            try await model.ringEnded(alarmID: id)
        }
        #expect(model.alarms.map(\.id) == [noRepeat.id])
        #expect(model.alarms[0].isEnabled == false)
        #expect(self.model().alarms.map(\.id) == [noRepeat.id])
    }

    @Test func stillScheduledIsKept() async throws {
        let model = model(), alarm = AlarmDefinition(hour: 7, minute: 0, isOneTime: true)
        try await model.save(alarm)
        try await model.ringEnded(alarmID: alarm.id)
        #expect(model.alarms.map(\.id) == [alarm.id])
    }

    @Test func reconcileDeletesOnlyAfterItsTime() async throws {
        let model = model(), alarm = AlarmDefinition(hour: 7, minute: 0, isOneTime: true)
        try await model.save(alarm)
        client.set(alarm.id, nil)
        clock.advance(try #require(model.alarms[0].firesAt).timeIntervalSince(clock.now))
        try await model.reconcile()
        #expect(model.alarms.isEmpty)
    }

    @Test func reconcileTurnsOffALostAlarm() async throws {
        let model = model(), alarm = AlarmDefinition(hour: 7, minute: 0, isOneTime: true)
        try await model.save(alarm)
        client.set(alarm.id, nil)
        try await model.reconcile()
        #expect(model.alarms.count == 1)
        #expect(model.alarms[0].isEnabled == false && model.alarms[0].firesAt == nil)
        // Turned off, so passing its old time later deletes nothing.
        clock.advance(2 * 86_400)
        try await model.reconcile()
        #expect(model.alarms.count == 1)
    }
}
