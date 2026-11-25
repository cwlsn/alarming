import AlarmKit
import SwiftUI

@main
struct SpikeApp: App {
    init() { SpikeLog.write("APP LAUNCH [\(Chain.states())]") }
    var body: some Scene { WindowGroup { SpikeView() } }
}

struct SpikeView: View {
    @State private var log = ""
    @State private var states = ""
    @State private var useTone = true

    var body: some View {
        NavigationStack {
            List {
                // First, so the tests can always see it.
                Section("Alarms") { Text(states.isEmpty ? "none" : states).accessibilityIdentifier("states") }
                Section("Schedule") {
                    Toggle("Custom tone", isOn: $useTone)
                    Button("One-time in 15s (30, 20, 10)") { schedule(after: 15, intervals: [30, 20, 10]) }
                    Button("One-time in 60s (180, 120, 60)") { schedule(after: 60, intervals: [180, 120, 60]) }
                    Button("One-time in 15s, no snooze") { schedule(after: 15, intervals: []) }
                    Button("One-time in 15s (10)") { schedule(after: 15, intervals: [10]) }
                    Button("Countdown 15s, no snooze") { submit(nil, [], countdown: 15) }
                    Button("Last ring fixed (10)") { schedule(after: 15, intervals: [10], lastRing: .fixed) }
                    Button("Last ring two buttons (10)") { schedule(after: 15, intervals: [10], lastRing: .stopButton) }
                    Button("Daily, next minute (30, 20, 10)") { scheduleDaily() }
                    Button("Open Settings") {
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    }
                    Button("Cancel all", role: .destructive) { cancelAll() }
                    Button("Clear log", role: .destructive) {
                        try? FileManager.default.removeItem(at: SpikeLog.url)
                        log = ""
                    }
                }
                Section("Log") {
                    Text(log.split(separator: "\n").suffix(12).joined(separator: "\n")).font(.caption2.monospaced()).textSelection(.enabled).accessibilityIdentifier("log")
                }
            }
            .navigationTitle("Snooze spike")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("--schedule") { schedule(after: 15, intervals: [30, 20, 10]) }
            while !Task.isCancelled {
                log = SpikeLog.read()
                states = Chain.states()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func schedule(after seconds: Int, intervals: [Int], lastRing: LastRing = .countdown) {
        LastRing.current = lastRing
        submit(.fixed(.now.addingTimeInterval(TimeInterval(seconds))), intervals)
    }

    private func scheduleDaily() {
        let time = Calendar.current.dateComponents([.hour, .minute], from: .now.addingTimeInterval(60))
        submit(.relative(.init(
            time: .init(hour: time.hour!, minute: time.minute!),
            repeats: .weekly([.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]))), [30, 20, 10])
    }

    private func submit(_ schedule: Alarm.Schedule?, _ intervals: [Int], countdown: TimeInterval? = nil) {
        if countdown != nil { LastRing.current = .countdown }
        Task {
            do {
                let authorization = try await AlarmManager.shared.requestAuthorization()
                SpikeLog.write("AUTH \(authorization)")
                let id = UUID()
                _ = try await AlarmManager.shared.schedule(id: id, configuration: Chain.configuration(
                    id: id, chain: id, step: 0, intervals: intervals, tone: useTone ? "spike.caf" : "",
                    schedule: schedule, countdown: countdown))
                SpikeLog.write("BASE \(id.uuidString.prefix(4)) [\(Chain.states())]")
            } catch { SpikeLog.write("BASE ERROR \(error)") }
        }
    }

    private func cancelAll() {
        for alarm in (try? AlarmManager.shared.alarms) ?? [] { try? AlarmManager.shared.cancel(id: alarm.id) }
    }
}
