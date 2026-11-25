import AppIntents

/// In both the app and the widget extension, because iOS runs it in the app to open it.
struct OpenAlarmingIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Alarming"
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .foreground

    func perform() async throws -> some IntentResult { .result() }
}
