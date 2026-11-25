import Foundation

public enum DurationText {
    /// "9m". Snoozes are whole minutes.
    public static func short(_ seconds: Int) -> String { "\(seconds / 60)m" }
}

extension SnoozePolicy {
    public var summary: String {
        guard isEnabled else { return "No snooze" }
        if let intervals, style != .constant || limit != nil {
            if style != .constant {
                let shown = intervals.prefix(4).map(DurationText.short).joined(separator: ", ")
                return intervals.count > 4 ? "Snooze \(shown)..." : "Snooze \(shown)"
            }
            return "Snooze \(firstMinutes)m, up to \(intervals.count)x"
        }
        return "Snooze \(firstMinutes)m, no limit"
    }
}
