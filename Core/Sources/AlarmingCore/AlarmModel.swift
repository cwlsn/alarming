import Foundation
import Observation

public struct AlarmFile: Sendable {
    private struct Contents: Codable {
        var version = 1
        var alarms: [AlarmDefinition]
    }

    private let url: URL
    public init(url: URL) { self.url = url }

    /// A missing file is an empty list; an unreadable one throws so alarms are never mistaken for deleted.
    public func load() throws -> [AlarmDefinition] {
        do {
            return try JSONDecoder().decode(Contents.self, from: Data(contentsOf: url)).alarms
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
    }

    public func save(_ alarms: [AlarmDefinition]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var options: Data.WritingOptions = .atomic
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try JSONEncoder().encode(Contents(alarms: alarms)).write(to: url, options: options)
    }
}

public enum AlarmModelError: Error, Equatable { case permissionDenied, storageUnavailable }

@MainActor @Observable
public final class AlarmModel {
    public private(set) var alarms: [AlarmDefinition] = []
    public private(set) var permissionDenied = false
    public private(set) var storageFailed = false

    @ObservationIgnored private let client: any AlarmClient
    @ObservationIgnored private let file: AlarmFile
    @ObservationIgnored private let publish: @MainActor ([AlarmDefinition]) -> Void
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var operation: Task<Void, Never>?

    /// `publish` receives the alarms that will ring, after every operation.
    public init(client: any AlarmClient, file: AlarmFile, publish: @escaping @MainActor ([AlarmDefinition]) -> Void = { _ in }) {
        self.client = client
        self.file = file
        self.publish = publish
        try? loadIfNeeded()
    }

    /// Adds or replaces an alarm. On any failure the previous alarm stays scheduled.
    public func save(_ alarm: AlarmDefinition) async throws {
        var alarm = alarm
        alarm.label = alarm.displayLabel
        let saved = alarm
        try await exclusively { try await self.replace(saved.id, with: saved) }
    }

    public func setEnabled(_ enabled: Bool, id: UUID) async throws {
        try await exclusively {
            try self.loadIfNeeded()
            guard var alarm = self.alarms.first(where: { $0.id == id }), alarm.isEnabled != enabled else { return }
            alarm.isEnabled = enabled
            try await self.replace(id, with: alarm)
        }
    }

    public func delete(_ id: UUID) async throws {
        try await exclusively { try await self.replace(id, with: nil) }
    }

    /// Called after a ring ends. A one-time alarm is finished once stopped.
    public func ringEnded(alarmID: UUID) async throws {
        try await exclusively {
            try self.loadIfNeeded()
            guard let index = self.alarms.firstIndex(where: { $0.id == alarmID }),
                  self.alarms[index].days.isEmpty, self.alarms[index].isEnabled else { return }
            // The user may have re-armed it already.
            guard try self.client.rings()[alarmID] == nil else { return }
            var updated = self.alarms
            updated[index].isEnabled = false
            try self.file.save(updated)
            self.alarms = updated
        }
    }

    /// Brings the list and the system back into agreement after anything that happened while the app was away.
    public func reconcile() async throws {
        try await exclusively {
            try self.loadIfNeeded()
            self.permissionDenied = self.client.isDenied()
            guard !self.permissionDenied else { return }
            let rings = try self.client.rings()
            var updated = self.alarms
            var expected: Set<UUID> = []
            var missing: [AlarmDefinition] = []
            for index in updated.indices where updated[index].isEnabled {
                let alarm = updated[index]
                let slots = SnoozeSlot.all(for: alarm.id)
                if alarm.days.isEmpty, rings[alarm.id] == nil, !slots.contains(where: { rings[$0] != nil }) {
                    updated[index].isEnabled = false
                } else {
                    expected.formUnion(slots + [alarm.id])
                    if !alarm.days.isEmpty, rings[alarm.id] == nil { missing.append(alarm) }
                }
            }
            if updated != self.alarms {
                try self.file.save(updated)
                self.alarms = updated
            }
            for id in rings.keys where !expected.contains(id) { try self.client.cancel(id) }
            for alarm in missing { try await self.schedule(alarm) }
        }
    }

    private func replace(_ id: UUID, with alarm: AlarmDefinition?) async throws {
        try loadIfNeeded()
        let previous = alarms.first { $0.id == id }
        if alarm?.isEnabled == true {
            let authorized = try await client.authorize()
            permissionDenied = !authorized
            guard authorized else { throw AlarmModelError.permissionDenied }
        }
        let baseWasScheduled = try client.rings()[id] != nil
        var updated = alarms.filter { $0.id != id }
        if let alarm { updated.append(alarm) }
        updated.sort { ($0.hour, $0.minute, $0.id.uuidString) < ($1.hour, $1.minute, $1.id.uuidString) }

        do {
            if baseWasScheduled { try client.cancel(id) }
            if let alarm, alarm.isEnabled { try await schedule(alarm) }
            try file.save(updated)
        } catch {
            if (try? client.rings()[id]) != nil { try? client.cancel(id) }
            if baseWasScheduled, let previous, previous.isEnabled { try? await schedule(previous) }
            throw error
        }
        alarms = updated
        // Last, so a failed edit leaves a pending snooze alone.
        let rings = try client.rings()
        for slot in SnoozeSlot.all(for: id) where rings[slot] != nil { try client.cancel(slot) }
    }

    private func schedule(_ alarm: AlarmDefinition) async throws {
        try await client.schedule(RingRequest(id: alarm.id, alarm: alarm, step: 0, timing: .base))
    }

    private func publishUpcoming() {
        guard loaded else { return }
        if permissionDenied { return publish([]) }
        guard let rings = try? client.rings() else { return }
        // A one-time alarm that is ringing or snoozing is still on, but has no later ring of its own.
        publish(alarms.filter { $0.isEnabled && (!$0.days.isEmpty || rings[$0.id] == .scheduled) })
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        do {
            alarms = try file.load()
            loaded = true
            storageFailed = false
        } catch {
            storageFailed = true
            throw AlarmModelError.storageUnavailable
        }
    }

    /// Runs operations one at a time so edits, toggles and reconciliation cannot interleave.
    private func exclusively(_ work: @escaping @MainActor () async throws -> Void) async throws {
        let before = operation
        let task = Task { @MainActor in
            await before?.value
            defer { self.publishUpcoming() }
            try await work()
        }
        operation = Task { _ = await task.result }
        try await task.value
    }
}
