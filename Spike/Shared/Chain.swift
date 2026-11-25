import ActivityKit
import AlarmKit
import AppIntents
import CryptoKit
import Foundation
import SwiftUI

struct SpikeMetadata: AlarmMetadata {
    var step: Int
    var snoozesLeft: Int
}

enum SpikeLog {
    static var url: URL { URL.documentsDirectory.appending(path: "spike.log") }

    static func write(_ message: String) {
        // Unprotected so an intent running before first unlock can still leave evidence.
        let line = Data("\(Date.now.formatted(.iso8601.time(includingFractionalSeconds: true))) pid=\(getpid()) \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url, options: .noFileProtection)
        }
    }

    static func read() -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
}

/// Ways to build a last ring, which iOS may not show when it follows a countdown without a second button.
enum LastRing: String {
    case countdown, fixed, stopButton
    static var current: LastRing {
        get { LastRing(rawValue: UserDefaults.standard.string(forKey: "lastRing") ?? "") ?? .countdown }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "lastRing") }
    }
}

enum Chain {
    static func id(_ chain: UUID, step: Int) -> UUID {
        let bytes = Array(SHA256.hash(data: Data("\(chain.uuidString)-\(step)".utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    static func configuration(
        id: UUID, chain: UUID, step: Int, intervals: [Int], tone: String,
        schedule: Alarm.Schedule?, countdown: TimeInterval?
    ) -> AlarmManager.AlarmConfiguration<SpikeMetadata> {
        let canSnooze = step < intervals.count
        let doubleStop = !canSnooze && LastRing.current == .stopButton
        let alert = AlarmPresentation.Alert(
            title: "Ring \(step + 1)",
            secondaryButton: canSnooze
                ? AlarmButton(text: "Snooze \(intervals[step])s", textColor: .white, systemImageName: "zzz")
                : doubleStop ? AlarmButton(text: "End", textColor: .white, systemImageName: "checkmark") : nil,
            secondaryButtonBehavior: canSnooze || doubleStop ? .custom : nil)
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(
                alert: alert,
                countdown: countdown == nil ? nil : AlarmPresentation.Countdown(title: "Snoozing")),
            metadata: SpikeMetadata(step: step, snoozesLeft: intervals.count - step),
            tintColor: .orange)
        return .init(
            countdownDuration: countdown.map { .init(preAlert: $0, postAlert: nil) },
            schedule: schedule,
            attributes: attributes,
            stopIntent: StopIntent(alarmID: id.uuidString),
            secondaryIntent: canSnooze
                ? SnoozeIntent(alarmID: id.uuidString, chainID: chain.uuidString, step: step, intervals: intervals, tone: tone)
                : doubleStop ? StopIntent(alarmID: id.uuidString) : nil,
            sound: tone.isEmpty ? .default : .named(tone))
    }

    static func states() -> String {
        do {
            return try AlarmManager.shared.alarms
                .map { "\($0.id.uuidString.prefix(4)):\($0.state)" }.joined(separator: ",")
        } catch { return "error \(error)" }
    }
}

struct SnoozeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Snooze"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Alarm") var alarmID: String
    @Parameter(title: "Chain") var chainID: String
    @Parameter(title: "Step") var step: Int
    @Parameter(title: "Intervals") var intervals: [Int]
    @Parameter(title: "Tone") var tone: String

    init() {}
    init(alarmID: String, chainID: String, step: Int, intervals: [Int], tone: String) {
        self.alarmID = alarmID
        self.chainID = chainID
        self.step = step
        self.intervals = intervals
        self.tone = tone
    }

    func perform() async throws -> some IntentResult {
        SpikeLog.write("SNOOZE step=\(step) before=[\(Chain.states())]")
        guard let current = UUID(uuidString: alarmID), let chain = UUID(uuidString: chainID),
              intervals.indices.contains(step) else {
            SpikeLog.write("SNOOZE bad parameters")
            return .result()
        }
        let next = Chain.id(chain, step: step)
        do {
            if try AlarmManager.shared.alarms.contains(where: { $0.id == next }) {
                SpikeLog.write("SNOOZE duplicate ignored")
            } else {
                let fixed = step + 1 == intervals.count && LastRing.current == .fixed
                _ = try await AlarmManager.shared.schedule(id: next, configuration: Chain.configuration(
                    id: next, chain: chain, step: step + 1, intervals: intervals, tone: tone,
                    schedule: fixed ? .fixed(.now.addingTimeInterval(TimeInterval(intervals[step]))) : nil,
                    countdown: fixed ? nil : TimeInterval(intervals[step])))
                SpikeLog.write("SNOOZE scheduled +\(intervals[step])s [\(Chain.states())]")
            }
            try AlarmManager.shared.stop(id: current)
        } catch {
            SpikeLog.write("SNOOZE ERROR \(error)")
        }
        SpikeLog.write("SNOOZE after=[\(Chain.states())]")
        return .result()
    }
}

struct StopIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Alarm") var alarmID: String

    init() {}
    init(alarmID: String) { self.alarmID = alarmID }

    func perform() async throws -> some IntentResult {
        SpikeLog.write("STOP \(alarmID.prefix(4)) before=[\(Chain.states())]")
        if let id = UUID(uuidString: alarmID) { try? AlarmManager.shared.stop(id: id) }
        SpikeLog.write("STOP after=[\(Chain.states())]")
        return .result()
    }
}
