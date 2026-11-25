import AlarmingCore
import AppIntents
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.cwlsn.alarming", category: "intents")

struct SnoozeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Snooze"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Ring") var ringID: String
    @Parameter(title: "Step") var step: Int
    @Parameter(title: "Snapshot") var snapshot: String

    init() {}
    init(ringID: String, step: Int, snapshot: String) {
        self.ringID = ringID
        self.step = step
        self.snapshot = snapshot
    }

    func perform() async throws -> some IntentResult {
        do {
            guard let ring = UUID(uuidString: ringID) else { return .result() }
            let alarm = try JSONDecoder().decode(AlarmDefinition.self, from: Data(snapshot.utf8))
            let outcome = try await Services.coordinator.snooze(currentID: ring, alarm: alarm, step: step)
            logger.info("Snooze step \(step): \(String(describing: outcome), privacy: .public)")
        } catch {
            // The current ring is still sounding, so the person can tap again or stop it.
            logger.error("Snooze failed: \(error, privacy: .public)")
        }
        return .result()
    }
}

struct StopIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Ring") var ringID: String
    @Parameter(title: "Alarm") var alarmID: String

    init() {}
    init(ringID: String, alarmID: String) {
        self.ringID = ringID
        self.alarmID = alarmID
    }

    func perform() async throws -> some IntentResult {
        do {
            guard let ring = UUID(uuidString: ringID), let alarm = UUID(uuidString: alarmID) else { return .result() }
            try await Services.coordinator.end(currentID: ring, alarmID: alarm)
            try await Services.model.ringEnded(alarmID: alarm)
        } catch {
            // Reconciliation on next launch covers this.
            logger.error("Stop cleanup failed: \(error, privacy: .public)")
        }
        return .result()
    }
}
