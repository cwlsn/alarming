import ActivityKit
import AlarmKit
import AlarmingCore
import AppIntents
import Foundation
import SwiftUI

struct RingMetadata: AlarmMetadata {
    var label: String
    var snoozesLeft: Int?
    var alarmID: UUID
}

struct AlarmKitClient: AlarmClient {
    func authorize() async throws -> Bool {
        try await AlarmManager.shared.requestAuthorization() == .authorized
    }

    func isDenied() -> Bool { AlarmManager.shared.authorizationState == .denied }

    func rings() throws -> [UUID: RingState] {
        try AlarmManager.shared.alarms.reduce(into: [:]) { result, alarm in
            result[alarm.id] = switch alarm.state {
            case .scheduled: .scheduled
            case .countdown: .countdown
            case .paused: .paused
            case .alerting: .alerting
            @unknown default: .scheduled
            }
        }
    }

    func stop(_ id: UUID) throws { try AlarmManager.shared.stop(id: id) }
    func cancel(_ id: UUID) throws { try AlarmManager.shared.cancel(id: id) }

    func schedule(_ request: RingRequest) async throws {
        let alarm = request.alarm
        let snooze = request.nextSnooze
        let stop = StopIntent(ringID: request.id.uuidString, alarmID: alarm.id.uuidString)
        // iOS draws Stop itself and ignores custom stop buttons since 26.1, so the last ring after a
        // snooze shows both Stop and this. Spike/README.md has the evidence.
        let needsEndButton = request.needsEndButton
        let alert = AlarmPresentation.Alert(
            title: "\(alarm.displayLabel)",
            secondaryButton: snooze.map {
                AlarmButton(text: "Snooze \(DurationText.short($0))", textColor: .white, systemImageName: "zzz")
            } ?? (needsEndButton ? AlarmButton(text: "I'm up", textColor: .white, systemImageName: "checkmark") : nil),
            secondaryButtonBehavior: snooze != nil || needsEndButton ? .custom : nil)

        var countdown: Alarm.CountdownDuration?
        var schedule: Alarm.Schedule?
        switch request.timing {
        case .base:
            schedule = .relative(.init(
                time: .init(hour: alarm.hour, minute: alarm.minute),
                repeats: alarm.days.isEmpty ? .never : .weekly(Array(alarm.days))))
        case .countdown(let seconds):
            countdown = .init(preAlert: TimeInterval(seconds), postAlert: nil)
        }

        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(
                alert: alert,
                countdown: countdown == nil ? nil : .init(title: "\(alarm.displayLabel)")),
            metadata: RingMetadata(label: alarm.displayLabel, snoozesLeft: request.snoozesLeft, alarmID: alarm.id),
            tintColor: .accentBright)
        let snapshot = String(decoding: try JSONEncoder().encode(alarm), as: UTF8.self)
        let secondaryIntent: (any LiveActivityIntent)? = if snooze != nil {
            SnoozeIntent(ringID: request.id.uuidString, step: request.step, snapshot: snapshot)
        } else if needsEndButton { stop } else { nil }
        _ = try await AlarmManager.shared.schedule(id: request.id, configuration: .init(
            countdownDuration: countdown,
            schedule: schedule,
            attributes: attributes,
            stopIntent: stop,
            secondaryIntent: secondaryIntent,
            sound: alarm.tone.map { .named($0) } ?? .default))
    }
}
