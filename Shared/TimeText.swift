import SwiftUI

enum TimeText {
    static var uses24Hour: Bool {
        !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("a")
    }

    static func minuteOfDay(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// A large time with a smaller AM or PM where the locale uses one.
    static func display(_ date: Date, size: CGFloat) -> AttributedString {
        var text = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).attributedStyle)
        text.font = .system(size: size, weight: .medium).monospacedDigit()
        for run in text.runs where run.dateField == .amPM {
            text[run.range].font = .system(size: size * 0.5, weight: .medium)
        }
        return text
    }

    static func ringsIn(_ date: Date, now: Date) -> String {
        // Rounded up so an alarm at the next minute never reads as zero.
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.up))
        guard minutes > 1 else { return "Rings in under a minute" }
        let duration = Duration.seconds(minutes * 60)
        return "Rings in " + duration.formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated))
    }
}
