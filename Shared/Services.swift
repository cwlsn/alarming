import AlarmingCore
import Foundation
import OSLog
import WidgetKit

/// Live objects shared by the app's screens and the intents iOS runs in the app's process.
@MainActor
enum Services {
    static let client: any AlarmClient = makeClient()
    static let coordinator = SnoozeCoordinator(client: client)
    static let model = AlarmModel(client: client, file: AlarmFile(url: storeURL), publish: publish)

    /// UI tests always start fresh and save nothing.
    static let preferences: UserDefaults? = isUITesting ? nil : .standard
    static let newAlarms = NewAlarmDefaults(store: preferences)

    #if DEBUG
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
    static let forcesDark = ProcessInfo.processInfo.arguments.contains("-dark")
    static let isSeeded = isUITesting && ProcessInfo.processInfo.arguments.contains("-seed")

    /// A spread of times and snooze styles for screenshots.
    static func seed() async {
        let alarms = [
            AlarmDefinition(hour: 4, minute: 50, label: "Flight", snooze: SnoozePolicy(isEnabled: false)),
            AlarmDefinition(hour: 6, minute: 30, days: RepeatDays.weekdays, label: "Work",
                            snooze: SnoozePolicy(firstMinutes: 15, style: .subtract(minutes: 5))),
            AlarmDefinition(hour: 9, minute: 0, days: RepeatDays.weekends, label: "Lie-in",
                            snooze: SnoozePolicy(firstMinutes: 10, style: .multiply(.half), limit: 3)),
            AlarmDefinition(hour: 13, minute: 15, label: "Nap", isEnabled: false),
            AlarmDefinition(hour: 22, minute: 30, days: RepeatDays.everyDay, label: "Wind down",
                            snooze: SnoozePolicy(firstMinutes: 5, limit: 2)),
        ]
        for alarm in alarms { try? await model.save(alarm) }
    }
    #else
    static let isUITesting = false
    static let forcesDark = false
    #endif

    private static func makeClient() -> any AlarmClient {
        #if DEBUG
        if isUITesting { return PreviewAlarmClient(denied: ProcessInfo.processInfo.arguments.contains("-denied")) }
        #endif
        return AlarmKitClient()
    }

    private static func publish(_ alarms: [AlarmDefinition]) {
        #if !targetEnvironment(simulator)
        // Test alarms must not reach the widget on a real phone.
        guard !isUITesting else { return }
        #endif
        do {
            if try UpcomingAlarmsFile.shared?.publish(alarms) == true { WidgetCenter.shared.reloadTimelines(ofKind: NextAlarmKind.name) }
        } catch {
            Logger(subsystem: "com.cwlsn.alarming", category: "widget").error("Publish failed: \(error, privacy: .public)")
        }
    }

    private static var storeURL: URL {
        isUITesting
            ? URL.temporaryDirectory.appending(path: "uitest-\(UUID().uuidString).json")
            : URL.applicationSupportDirectory.appending(path: "alarms.json")
    }
}

enum NextAlarmKind { static let name = "NextAlarm" }

extension UpcomingAlarmsFile {
    /// In the container the app and its widget share.
    static let shared = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: Bundle.main.object(forInfoDictionaryKey: "AppGroup") as? String ?? "")
        .map { UpcomingAlarmsFile(url: $0.appending(path: "upcoming.json")) }
}

#if DEBUG
import Synchronization

/// The iOS 27 simulator refuses alarm permission, so UI tests use this in place of AlarmKit.
final class PreviewAlarmClient: AlarmClient {
    private let state = Mutex<[UUID: RingState]>([:])
    private let denied: Bool
    init(denied: Bool) { self.denied = denied }
    func authorize() async throws -> Bool { !denied }
    func isDenied() -> Bool { denied }
    func rings() throws -> [UUID: RingState] { state.withLock { $0 } }
    func schedule(_ request: RingRequest) async throws { state.withLock { $0[request.id] = .scheduled } }
    func stop(_ id: UUID) throws { state.withLock { $0[id] = nil } }
    func cancel(_ id: UUID) throws { state.withLock { $0[id] = nil } }
}
#endif
