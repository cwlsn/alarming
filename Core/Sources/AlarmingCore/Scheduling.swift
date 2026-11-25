import CryptoKit
import Foundation

public enum RingState: Sendable, Equatable { case scheduled, countdown, paused, alerting }

/// One alarm to hand to the system. The snapshot lets a snooze continue without reading the store,
/// which may be unavailable before the phone's first unlock.
public struct RingRequest: Sendable, Equatable {
    public enum Timing: Sendable, Equatable {
        case base
        case countdown(seconds: Int)
    }

    public let id: UUID
    public let alarm: AlarmDefinition
    /// Snoozes already taken when this ring sounds.
    public let step: Int
    public let timing: Timing

    public init(id: UUID, alarm: AlarmDefinition, step: Int, timing: Timing) {
        self.id = id
        self.alarm = alarm
        self.step = step
        self.timing = timing
    }

    public var nextSnooze: Int? { alarm.effectiveSnooze.interval(after: step) }
    /// After a snooze, iOS 27.2 shows nothing for a countdown ring with only a Stop button.
    public var needsEndButton: Bool { nextSnooze == nil && timing != .base }
    /// `nil` when there is no end.
    public var snoozesLeft: Int? { alarm.effectiveSnooze.intervals.map { max(0, $0.count - step) } }
}

public protocol AlarmClient: Sendable {
    func authorize() async throws -> Bool
    func isDenied() -> Bool
    func rings() throws -> [UUID: RingState]
    func schedule(_ request: RingRequest) async throws
    func stop(_ id: UUID) throws
    func cancel(_ id: UUID) throws
}

public enum SnoozeSlot {
    /// Two alternating IDs are enough: one ring sounds while the next counts down.
    public static func id(for alarm: UUID, step: Int) -> UUID {
        let b = Array(SHA256.hash(data: Data("\(alarm.uuidString)-snooze-\(step % 2)".utf8)).prefix(16))
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    public static func all(for alarm: UUID) -> [UUID] { [id(for: alarm, step: 0), id(for: alarm, step: 1)] }
}

public actor SnoozeCoordinator {
    public enum Outcome: Sendable, Equatable { case scheduled(seconds: Int), duplicate, noSnoozeLeft }

    private let client: any AlarmClient
    private var inFlight: Set<UUID> = []

    public init(client: any AlarmClient) { self.client = client }

    /// Schedules the next ring before silencing the current one, so a failure leaves the alarm ringing.
    public func snooze(currentID: UUID, alarm: AlarmDefinition, step: Int) async throws -> Outcome {
        guard inFlight.insert(currentID).inserted else { return .duplicate }
        defer { inFlight.remove(currentID) }
        guard let seconds = alarm.effectiveSnooze.interval(after: step) else { return .noSnoozeLeft }

        let next = SnoozeSlot.id(for: alarm.id, step: step)
        let rings = try client.rings()
        // Already handled: the tapped ring is quiet and its successor exists.
        if rings[currentID] != .alerting, rings[next] != nil { return .duplicate }

        // Anything else in the slots belongs to an earlier occurrence or a half-finished attempt.
        for id in SnoozeSlot.all(for: alarm.id) where id != currentID && rings[id] != nil {
            try client.cancel(id)
        }
        try await client.schedule(RingRequest(id: next, alarm: alarm, step: step + 1, timing: .countdown(seconds: seconds)))
        // stop, not cancel: a recurring base must keep its future days.
        if try client.rings()[currentID] == .alerting { try client.stop(currentID) }
        return .scheduled(seconds: seconds)
    }

    /// The system may already have removed the ring, so missing IDs are expected.
    public func end(currentID: UUID, alarmID: UUID) throws {
        let rings = try client.rings()
        for id in SnoozeSlot.all(for: alarmID) where rings[id] != nil { try client.cancel(id) }
        if currentID == alarmID, rings[currentID] == .alerting { try client.stop(currentID) }
    }
}
