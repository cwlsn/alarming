import Foundation
import Testing
@testable import AlarmingCore

@Suite struct PreferencesTests {
    private func withStore(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "test-\(UUID())"
        let store = UserDefaults(suiteName: name)!
        defer { store.removePersistentDomain(forName: name) }
        try body(store)
    }

    @Test func newAlarmsStartWithTheInitialSnooze() {
        withStore { store in
            for defaults in [NewAlarmDefaults(store: store), NewAlarmDefaults(store: nil)] {
                let alarm = defaults.apply(to: AlarmDefinition(hour: 7, minute: 0))
                #expect(alarm.snooze == .initial && alarm.tone == nil)
            }
        }
    }

    @Test func newAlarmsRepeatTheLastChoice() {
        withStore { store in
            let policy = SnoozePolicy(firstMinutes: 12, style: .multiply(.third), limit: 1)
            NewAlarmDefaults(store: store).remember(AlarmDefinition(hour: 7, minute: 0, label: "Gym", tone: "drift.caf", snooze: policy))
            let alarm = NewAlarmDefaults(store: store).apply(to: AlarmDefinition(hour: 8, minute: 0))
            #expect(alarm.snooze == policy && alarm.tone == "drift.caf")
            #expect(alarm.hour == 8 && alarm.label == AlarmDefinition.defaultLabel)
        }
    }

    @Test func unreadableSnoozeFallsBack() {
        withStore { store in
            store.set(Data("?".utf8), forKey: "newAlarmSnooze")
            #expect(NewAlarmDefaults(store: store).apply(to: AlarmDefinition(hour: 7, minute: 0)).snooze == .initial)
        }
    }

    @Test func dayGroupsRoundTrip() {
        withStore { store in
            let preferences = DayGroupPreferences(store: store)
            #expect(preferences.load() == DayGroup.defaults)
            let group = DayGroup(days: [.monday])
            preferences.save([group, DayGroup(days: []), DayGroup(days: [.monday])])
            #expect(preferences.load() == [group])
            preferences.save([])
            #expect(preferences.load().isEmpty)
            store.set(Data("?".utf8), forKey: "dayGroups")
            #expect(preferences.load() == DayGroup.defaults)
        }
    }

    /// iOS hides a countdown ring that has only a Stop button, so only those need a second one.
    @Test func onlyTheLastRingAfterASnoozeNeedsAnEndButton() {
        let alarm = AlarmDefinition(hour: 7, minute: 0, snooze: SnoozePolicy(firstMinutes: 10, limit: 1))
        let off = AlarmDefinition(hour: 7, minute: 0, snooze: SnoozePolicy(isEnabled: false))
        func needs(_ alarm: AlarmDefinition, _ step: Int, _ timing: RingRequest.Timing) -> Bool {
            RingRequest(id: alarm.id, alarm: alarm, step: step, timing: timing).needsEndButton
        }
        #expect(!needs(alarm, 0, .base))
        #expect(!needs(off, 0, .base))
        #expect(!needs(alarm, 0, .countdown(seconds: 600)))
        #expect(needs(alarm, 1, .countdown(seconds: 600)))
    }
}
