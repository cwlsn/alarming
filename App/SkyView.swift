import AlarmingCore
import SwiftUI

extension Color {
    /// Readable as small text in both appearances.
    static let accentText = Color(uiColor: UIColor {
        $0.userInterfaceStyle == .dark ? UIColor(red: 0.45, green: 0.68, blue: 1, alpha: 1) : UIColor(red: 0.10, green: 0.33, blue: 0.82, alpha: 1)
    })
    static let canvas = Color(uiColor: UIColor {
        $0.userInterfaceStyle == .dark ? UIColor(white: 0.04, alpha: 1) : UIColor(white: 0.99, alpha: 1)
    })
    /// Neutral fill for chips and fields.
    static let chip = Color.primary.opacity(0.06)
    static let hairline = Color.primary.opacity(0.10)
    /// Secondary text with at least 4.5:1 contrast on the canvas.
    static let quiet = Color(uiColor: UIColor {
        UIColor(white: $0.userInterfaceStyle == .dark ? 0.62 : 0.40, alpha: 1)
    })
    static let dusk = Color(red: 0.38, green: 0.31, blue: 0.75)
    private static let azure = Color(red: 0.05, green: 0.47, blue: 0.74)

    /// Night to morning blue. Dark enough throughout for white text.
    static func dawn(_ t: Double) -> Color {
        t < 0.5 ? dusk.mix(with: accentFill, by: t * 2) : accentFill.mix(with: azure, by: t * 2 - 1)
    }
}

/// Slowly drifting sky, with stars at night.
struct LivingSky: View {
    let minute: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let sky = SkyPalette(minuteOfDay: minute)
        ZStack {
            TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let drift = reduceMotion ? 0 : Float(sin(time * 0.45)) * 0.16
                let sway = reduceMotion ? 0 : Float(cos(time * 0.33)) * 0.12
                // TimelineView would stack its children, so both layers live in one ZStack.
                ZStack {
                    MeshGradient(
                        width: 3, height: 3,
                        points: [
                            [0, 0], [0.5, 0], [1, 0],
                            [0, 0.5 - sway], [0.5 + drift, 0.5 + sway], [1, 0.5 + drift],
                            [0, 1], [0.5, 1], [1, 1],
                        ],
                        colors: [
                            Color(sky.top), Color(sky.top), Color(sky.top),
                            Color(sky.middle), Color(sky.middle), Color(sky.top),
                            Color(sky.middle), Color(sky.horizon), Color(sky.horizon),
                        ])
                    Stars(time: reduceMotion ? 0 : time).opacity(sky.night)
                }
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: minute)
        .accessibilityHidden(true)
    }
}

private struct Stars: View {
    let time: TimeInterval

    var body: some View {
        Canvas { context, size in
            for index in 0..<36 {
                // The golden ratio scatters points evenly without looking like a grid.
                let x = (Double(index) * 0.618034).truncatingRemainder(dividingBy: 1) * size.width
                let y = (Double(index) * 0.414214 + 0.1).truncatingRemainder(dividingBy: 1) * size.height
                let radius = 0.6 + Double(index % 3) * 0.35
                let twinkle = 0.35 + 0.25 * sin(time * (0.7 + Double(index % 5) * 0.25) + Double(index))
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                             with: .color(.white.opacity(twinkle)))
            }
        }
    }
}

/// Snoozes as bars sized by how long each lasts.
struct SnoozeLadder: View {
    /// nil when snoozing never ends.
    let intervals: [Int]?
    let height: CGFloat
    var style: AnyShapeStyle?

    var body: some View {
        GeometryReader { proxy in
            let values = intervals ?? Array(repeating: 1, count: 6)
            let spacing: CGFloat = values.count > 12 ? 1.5 : 4
            // A small base keeps the shortest snooze visible beside the longest.
            let base = Double(values.reduce(0, +)) * 0.012
            let total = values.reduce(0) { $0 + Double($1) + base }
            let room = max(0, proxy.size.width - spacing * CGFloat(max(0, values.count - 1)))
            HStack(spacing: spacing) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, seconds in
                    let width = total > 0 ? room * (Double(seconds) + base) / total : 0
                    bar(index: index, count: values.count, width: width)
                        .transition(.scale(scale: 0.2, anchor: .leading).combined(with: .opacity))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func bar(index: Int, count: Int, width: CGFloat) -> some View {
        let t = count > 1 ? Double(index) / Double(count - 1) : 0
        return RoundedRectangle(cornerRadius: min(height / 2, 7), style: .continuous)
            .fill(style ?? AnyShapeStyle(Color.dawn(t).gradient))
            .opacity(intervals == nil ? 1 - t * 0.85 : 1)
            .frame(width: width)
    }
}

/// An alarm clock with cat ears: the app icon, alive. The hands sweep into place.
struct ClockMark: View {
    @State private var isSet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ear(-1)
            ear(1)
            Circle().fill(Color.accentFill).frame(width: 110)
            hand(34).rotationEffect(.degrees(isSet ? 360 : 0))
            hand(25).rotationEffect(.degrees(isSet ? 210 : 0))
        }
        .frame(width: 160, height: 160)
        .animation(reduceMotion ? nil : .spring(duration: 1.1, bounce: 0.2), value: isSet)
        .onAppear { isSet = true }
        .accessibilityHidden(true)
    }

    private func ear(_ side: CGFloat) -> some View {
        let shape = Path { path in
            func point(_ degrees: Double, _ radius: CGFloat) -> CGPoint {
                CGPoint(x: 80 + side * radius * cos(degrees * .pi / 180), y: 80 - radius * sin(degrees * .pi / 180))
            }
            path.addLines([point(32, 47), point(53, 73), point(74, 47)])
            path.closeSubpath()
        }
        return ZStack {
            shape.fill(Color.accentFill)
            shape.stroke(Color.accentFill, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
        }
    }

    private func hand(_ length: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 80, y: 80))
            path.addLine(to: CGPoint(x: 80, y: 80 - length))
        }
        .stroke(.white, style: StrokeStyle(lineWidth: 11, lineCap: .round))
    }
}

/// Dips under the finger and springs back.
struct SpringyButtonStyle: ButtonStyle {
    var scale = 0.9

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(duration: 0.28, bounce: 0.5), value: configuration.isPressed)
    }
}
