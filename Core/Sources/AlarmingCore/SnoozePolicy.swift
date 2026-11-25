import Foundation

/// Decides how long each snooze lasts and when snoozing ends.
/// The editor projection and the alarm runtime both use this type so they cannot disagree.
public struct SnoozePolicy: Codable, Hashable, Sendable {
    public enum Style: Codable, Hashable, Sendable {
        case constant
        case subtract(minutes: Int)
        case multiply(Fraction)
    }

    public enum Fraction: String, Codable, CaseIterable, Sendable {
        case threeQuarters, twoThirds, half, third

        var numerator: Int {
            switch self {
            case .threeQuarters: 3
            case .twoThirds: 2
            case .half, .third: 1
            }
        }

        var denominator: Int {
            switch self {
            case .threeQuarters: 4
            case .twoThirds, .third: 3
            case .half: 2
            }
        }
    }

    public static let minimumSeconds = 60
    /// What a new alarm starts with until another choice is made.
    public static let initial = SnoozePolicy(firstMinutes: 15, style: .subtract(minutes: 5), limit: 2)

    public var isEnabled: Bool
    public var firstMinutes: Int {
        didSet { firstMinutes = Self.clampedFirst(firstMinutes) }
    }
    public var style: Style {
        didSet { style = Self.clamped(style) }
    }
    /// `nil` means no chosen limit. Shrinking styles still run out naturally.
    public var limit: Int? {
        didSet { limit = Self.clampedLimit(limit) }
    }

    public init(isEnabled: Bool = true, firstMinutes: Int = 9, style: Style = .constant, limit: Int? = nil) {
        self.isEnabled = isEnabled
        self.firstMinutes = Self.clampedFirst(firstMinutes)
        self.style = Self.clamped(style)
        self.limit = Self.clampedLimit(limit)
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, firstMinutes, style, limit
    }

    /// Decoding goes through the clamping initializer so stored data cannot produce an endless sequence.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isEnabled: try values.decode(Bool.self, forKey: .isEnabled),
            firstMinutes: try values.decode(Int.self, forKey: .firstMinutes),
            style: try values.decode(Style.self, forKey: .style),
            limit: try values.decodeIfPresent(Int.self, forKey: .limit)
        )
    }

    /// Seconds, always whole minutes, for the snooze taken after `completed` earlier snoozes, or `nil` when only Stop is allowed.
    public func interval(after completed: Int) -> Int? {
        guard isEnabled, completed >= 0 else { return nil }
        if let limit, completed >= limit { return nil }
        return unlimitedInterval(after: completed)
    }

    /// Most snoozes the style permits before the interval gets too short. `nil` if it never does.
    public var naturalMaximum: Int? {
        if style == .constant { return nil }
        var count = 0
        while unlimitedInterval(after: count) != nil { count += 1 }
        return count
    }

    /// Every snooze in order, or `nil` if snoozing has no end.
    public var intervals: [Int]? {
        guard isEnabled else { return [] }
        guard let count = [limit, naturalMaximum].compactMap({ $0 }).min() else { return nil }
        return (0..<count).compactMap { interval(after: $0) }
    }

    /// Ring times including the alarm itself, assuming each snooze is tapped immediately.
    public func ringTimes(from start: Date) -> [Date]? {
        intervals?.reduce(into: [start]) { rings, seconds in
            rings.append(rings[rings.count - 1].addingTimeInterval(TimeInterval(seconds)))
        }
    }

    public func projectedWake(from start: Date) -> Date? {
        ringTimes(from: start)?.last
    }

    private func unlimitedInterval(after completed: Int) -> Int? {
        let first = firstMinutes * 60
        let seconds: Int
        switch style {
        case .constant:
            seconds = first
        case .subtract(let minutes):
            // Beyond 30 steps the result is always below the minimum; this also avoids overflow.
            guard completed <= 30 else { return nil }
            seconds = first - completed * minutes * 60
        case .multiply(let fraction):
            // 30 minutes at 3/4 falls below one minute by step 12, so 16 is a safe bound for exact integers.
            guard completed <= 16 else { return nil }
            var numerator = first
            var denominator = 1
            for _ in 0..<completed {
                numerator *= fraction.numerator
                denominator *= fraction.denominator
            }
            seconds = numerator / denominator
        }
        // Too short is judged before rounding up to a whole minute, or dividing would never end.
        guard seconds >= Self.minimumSeconds else { return nil }
        return (seconds + 59) / 60 * 60
    }

    private static func clampedFirst(_ minutes: Int) -> Int { min(max(minutes, 1), 30) }
    private static func clampedLimit(_ limit: Int?) -> Int? { limit.map { min(max($0, 1), 10) } }
    private static func clamped(_ style: Style) -> Style {
        guard case .subtract(let minutes) = style else { return style }
        return .subtract(minutes: min(max(minutes, 1), 15))
    }
}
