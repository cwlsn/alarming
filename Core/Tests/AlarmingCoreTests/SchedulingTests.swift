import Foundation
import Synchronization
import Testing
@testable import AlarmingCore

private struct Boom: Error {}

private final class FakeClient: AlarmClient {
    struct State {
        var rings: [UUID: RingState] = [:]
        var requests: [RingRequest] = []
        var cancelled: [UUID] = []
        var failSchedule = 0
        var failStop = false
        var authorized = true
        var slow = false
    }
    let state = Mutex(State())
    func authorize() async throws -> Bool { state.withLock { $0.authorized } }
    func isDenied() -> Bool { state.withLock { !$0.authorized } }
    func rings() throws -> [UUID: RingState] { state.withLock { $0.rings } }
    func schedule(_ request: RingRequest) async throws {
        if state.withLock({ $0.slow }) { try await Task.sleep(for: .milliseconds(50)) }
        try state.withLock {
            if $0.failSchedule > 0 { $0.failSchedule -= 1; throw Boom() }
            if $0.rings[request.id] != nil { throw Boom() }
            $0.rings[request.id] = request.timing == .base ? .scheduled : .countdown
            $0.requests.append(request)
        }
    }
    func stop(_ id: UUID) throws {
        try state.withLock {
            if $0.failStop || $0.rings[id] == nil { throw Boom() }
            let recurring = $0.requests.last { $0.id == id }.map { $0.timing == .base && !$0.alarm.days.isEmpty } ?? false
            $0.rings[id] = recurring ? .scheduled : nil
        }
    }
    func cancel(_ id: UUID) throws {
        try state.withLock {
            guard $0.rings.removeValue(forKey: id) != nil else { throw Boom() }
            $0.cancelled.append(id)
        }
    }
    func set(_ id: UUID, _ ring: RingState?) { state.withLock { $0.rings[id] = ring } }
    var last: RingRequest? { state.withLock { $0.requests.last } }
}

private func sample(days: Set<Locale.Weekday> = []) -> AlarmDefinition {
    AlarmDefinition(hour: 7, minute: 0, days: days, snooze: SnoozePolicy(firstMinutes: 3, style: .subtract(minutes: 1)))
}

private func tempURL() -> URL { URL.temporaryDirectory.appending(path: "alarming-\(UUID()).json") }

@Suite struct SnoozeTests {
    @Test func fullChainKeepsRecurringBase() async throws {
        let client = FakeClient(), alarm = sample(days: RepeatDays.everyDay)
        let coordinator = SnoozeCoordinator(client: client)
        try await client.schedule(RingRequest(id: alarm.id, alarm: alarm, step: 0, timing: .base))
        var current = alarm.id
        for (step, seconds) in [180, 120, 60].enumerated() {
            client.set(current, .alerting)
            #expect(try await coordinator.snooze(currentID: current, alarm: alarm, step: step) == .scheduled(seconds: seconds))
            current = try #require(client.last).id
            #expect(try client.rings() == [alarm.id: .scheduled, current: .countdown])
        }
        #expect(client.last?.nextSnooze == nil)
        #expect(client.last?.snoozesLeft == 0)
        client.set(current, .alerting)
        #expect(try await coordinator.snooze(currentID: current, alarm: alarm, step: 3) == .noSnoozeLeft)
        #expect(try client.rings()[current] == .alerting)
        client.set(current, nil)
        try await coordinator.end(currentID: current, alarmID: alarm.id)
        #expect(try client.rings() == [alarm.id: .scheduled])
        #expect(!client.state.withLock { $0.cancelled.contains(alarm.id) })
    }

    @Test func scheduleFailureKeepsRinging() async throws {
        let client = FakeClient(), alarm = sample()
        client.set(alarm.id, .alerting)
        client.state.withLock { $0.failSchedule = 1 }
        let coordinator = SnoozeCoordinator(client: client)
        await #expect(throws: Boom.self) { try await coordinator.snooze(currentID: alarm.id, alarm: alarm, step: 0) }
        #expect(try client.rings() == [alarm.id: .alerting])
        #expect(try await coordinator.snooze(currentID: alarm.id, alarm: alarm, step: 0) == .scheduled(seconds: 180))
    }

    @Test func stopFailureCanBeRetried() async throws {
        let client = FakeClient(), alarm = sample()
        client.set(alarm.id, .alerting)
        client.state.withLock { $0.failStop = true }
        let coordinator = SnoozeCoordinator(client: client)
        await #expect(throws: Boom.self) { try await coordinator.snooze(currentID: alarm.id, alarm: alarm, step: 0) }
        client.state.withLock { $0.failStop = false }
        _ = try await coordinator.snooze(currentID: alarm.id, alarm: alarm, step: 0)
        #expect(try client.rings() == [SnoozeSlot.id(for: alarm.id, step: 0): .countdown])
    }

    @Test func doubleTapSchedulesOnce() async throws {
        let client = FakeClient(), alarm = sample()
        client.set(alarm.id, .alerting)
        client.state.withLock { $0.slow = true }
        let coordinator = SnoozeCoordinator(client: client)
        async let a = coordinator.snooze(currentID: alarm.id, alarm: alarm, step: 0)
        async let b = coordinator.snooze(currentID: alarm.id, alarm: alarm, step: 0)
        let outcomes = try await [a, b]
        #expect(outcomes.contains(.duplicate) && outcomes.contains(.scheduled(seconds: 180)))
        #expect(try await coordinator.snooze(currentID: alarm.id, alarm: alarm, step: 0) == .duplicate)
        #expect(client.state.withLock { $0.requests.count } == 1)
    }

    @Test func missingCurrentRingStillSnoozes() async throws {
        let client = FakeClient(), alarm = sample()
        #expect(try await SnoozeCoordinator(client: client).snooze(currentID: alarm.id, alarm: alarm, step: 0) == .scheduled(seconds: 180))
    }

    @Test func newOccurrenceReplacesOldChain() async throws {
        let client = FakeClient(), alarm = sample(days: RepeatDays.everyDay)
        try await client.schedule(RingRequest(id: alarm.id, alarm: alarm, step: 0, timing: .base))
        for id in SnoozeSlot.all(for: alarm.id) { client.set(id, .countdown) }
        client.set(alarm.id, .alerting)
        _ = try await SnoozeCoordinator(client: client).snooze(currentID: alarm.id, alarm: alarm, step: 0)
        #expect(try client.rings().count == 2)
        #expect(client.last?.step == 1)
    }
}

@MainActor @Suite struct AlarmModelTests {
    private let client = FakeClient()
    private let url = tempURL()
    private func model() -> AlarmModel { AlarmModel(client: client, file: AlarmFile(url: url)) }

    @Test func saveNormalizesSortsAndPersists() async throws {
        let model = model()
        var late = sample(); late.hour = 9; late.label = " "
        try await model.save(late)
        try await model.save(sample())
        #expect(model.alarms.map(\.hour) == [7, 9])
        #expect(model.alarms[1].label == "Alarm")
        #expect(self.model().alarms == model.alarms)
        #expect(try client.rings().count == 2)
    }

    @Test func deniedSavesNothing() async throws {
        client.state.withLock { $0.authorized = false }
        let model = model()
        await #expect(throws: AlarmModelError.permissionDenied) { try await model.save(sample()) }
        #expect(model.alarms.isEmpty && model.permissionDenied)
    }

    @Test func failedEditRestoresOldAlarmAndKeepsSnooze() async throws {
        let model = model()
        let original = sample(days: RepeatDays.weekdays)
        try await model.save(original)
        let slot = SnoozeSlot.id(for: original.id, step: 0)
        client.set(slot, .countdown)
        var edited = original; edited.hour = 10
        client.state.withLock { $0.failSchedule = 1 }
        await #expect(throws: Boom.self) { try await model.save(edited) }
        #expect(model.alarms == [original])
        #expect(try client.rings() == [original.id: .scheduled, slot: .countdown])
        #expect(client.last?.alarm == original)
    }

    @Test func failedWriteRollsBack() async throws {
        let blocked = AlarmFile(url: URL(filePath: "/dev/null/nope/alarms.json"))
        let model = AlarmModel(client: client, file: blocked)
        await #expect(throws: (any Error).self) { try await model.save(sample()) }
        #expect(model.alarms.isEmpty)
        #expect(try client.rings().isEmpty)
    }

    @Test func editToggleDeleteClearSnoozes() async throws {
        let model = model(), alarm = sample(days: RepeatDays.weekdays)
        let slot = SnoozeSlot.id(for: alarm.id, step: 1)
        try await model.save(alarm)
        client.set(slot, .countdown)
        try await model.save(alarm)
        #expect(try client.rings() == [alarm.id: .scheduled])
        client.set(slot, .countdown)
        try await model.setEnabled(false, id: alarm.id)
        #expect(try client.rings().isEmpty)
        try await model.setEnabled(true, id: alarm.id)
        client.set(slot, .countdown)
        try await model.delete(alarm.id)
        #expect(try client.rings().isEmpty && model.alarms.isEmpty)
    }

    @Test func stoppingTurnsOffOnlyOneTimeAlarms() async throws {
        let model = model(), once = sample(), daily = sample(days: RepeatDays.everyDay)
        try await model.save(once)
        try await model.save(daily)
        client.set(once.id, nil)
        try await model.ringEnded(alarmID: once.id)
        try await model.ringEnded(alarmID: daily.id)
        #expect(model.alarms.first { $0.id == once.id }?.isEnabled == false)
        #expect(model.alarms.first { $0.id == daily.id }?.isEnabled == true)
    }

    @Test func reconcileRepairsDifferences() async throws {
        let model = model(), finished = sample(), snoozing = sample(), daily = sample(days: RepeatDays.everyDay)
        for alarm in [finished, snoozing, daily] { try await model.save(alarm) }
        client.set(finished.id, nil)
        client.set(snoozing.id, nil)
        client.set(SnoozeSlot.id(for: snoozing.id, step: 0), .countdown)
        client.set(daily.id, nil)
        let orphan = UUID()
        client.set(orphan, .scheduled)
        try await model.reconcile()
        #expect(model.alarms.first { $0.id == finished.id }?.isEnabled == false)
        #expect(model.alarms.first { $0.id == snoozing.id }?.isEnabled == true)
        #expect(try client.rings() == [SnoozeSlot.id(for: snoozing.id, step: 0): .countdown, daily.id: .scheduled])
    }

    @Test func unreadableFileNeverCancelsAlarms() async throws {
        try Data("garbage".utf8).write(to: url)
        client.set(UUID(), .scheduled)
        let model = model()
        await #expect(throws: AlarmModelError.storageUnavailable) { try await model.reconcile() }
        #expect(model.storageFailed)
        #expect(try client.rings().count == 1)
        #expect(try Data(contentsOf: url) == Data("garbage".utf8))
    }
}

@Test func snoozeSummaries() {
    #expect(SnoozePolicy(isEnabled: false).summary == "No snooze")
    #expect(SnoozePolicy().summary == "Snooze 9m, no limit")
    #expect(SnoozePolicy(limit: 2).summary == "Snooze 9m, up to 2x")
    #expect(SnoozePolicy(firstMinutes: 10, style: .multiply(.half), limit: 3).summary == "Snooze 10m, 5m, 3m")
}
