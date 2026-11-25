import Foundation

/// Sky colors through the day. Every color is dark enough for white body text.
public struct SkyPalette: Hashable, Sendable {
    public struct RGB: Hashable, Sendable {
        public let red, green, blue: Double

        init(_ red: Double, _ green: Double, _ blue: Double) {
            (self.red, self.green, self.blue) = (red, green, blue)
        }

        func mixed(with other: RGB, by t: Double) -> RGB {
            RGB(red + (other.red - red) * t, green + (other.green - green) * t, blue + (other.blue - blue) * t)
        }

        /// WCAG contrast ratio against white.
        var contrastWithWhite: Double {
            func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 1.05 / (0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue) + 0.05)
        }
    }

    public let top, middle, horizon: RGB
    /// 0 in full daylight, 1 in full night.
    public let night: Double

    private static let keys: [(minute: Double, sky: SkyPalette)] = [
        (0, .init(.init(0.04, 0.05, 0.16), .init(0.09, 0.09, 0.28), .init(0.17, 0.13, 0.40), 1)),
        (300, .init(.init(0.09, 0.09, 0.30), .init(0.25, 0.17, 0.45), .init(0.50, 0.24, 0.48), 0.8)),
        (390, .init(.init(0.20, 0.24, 0.56), .init(0.56, 0.27, 0.52), .init(0.77, 0.31, 0.29), 0.1)),
        (480, .init(.init(0.10, 0.36, 0.70), .init(0.32, 0.40, 0.68), .init(0.72, 0.31, 0.46), 0)),
        (720, .init(.init(0.05, 0.31, 0.70), .init(0.08, 0.40, 0.74), .init(0.10, 0.46, 0.68), 0)),
        (1020, .init(.init(0.14, 0.33, 0.67), .init(0.40, 0.37, 0.64), .init(0.71, 0.36, 0.22), 0)),
        (1140, .init(.init(0.20, 0.18, 0.50), .init(0.55, 0.24, 0.48), .init(0.77, 0.31, 0.25), 0.2)),
        (1260, .init(.init(0.07, 0.07, 0.24), .init(0.15, 0.12, 0.38), .init(0.32, 0.17, 0.45), 0.9)),
    ]

    private init(_ top: RGB, _ middle: RGB, _ horizon: RGB, _ night: Double) {
        (self.top, self.middle, self.horizon, self.night) = (top, middle, horizon, night)
    }

    public init(minuteOfDay: Int) {
        let minute = Double(((minuteOfDay % 1440) + 1440) % 1440)
        let keys = Self.keys
        let index = keys.lastIndex { $0.minute <= minute } ?? 0
        let from = keys[index]
        let next = keys[(index + 1) % keys.count]
        let end = index + 1 == keys.count ? 1440 : next.minute
        let t = (minute - from.minute) / (end - from.minute)
        self.init(
            from.sky.top.mixed(with: next.sky.top, by: t),
            from.sky.middle.mixed(with: next.sky.middle, by: t),
            from.sky.horizon.mixed(with: next.sky.horizon, by: t),
            from.sky.night + (next.sky.night - from.sky.night) * t)
    }
}
