import AlarmingCore
import Charts
import SwiftUI

/// The time of each ring by how many snoozes came before it, climbing to the wake-up time.
struct WakeChart: View {
    let policy: SnoozePolicy
    let start: Date
    @State private var selected: Double?
    @Environment(\.dynamicTypeSize) private var typeSize

    private struct Point: Identifiable {
        /// Snoozes taken before this ring. 0 is the alarm itself.
        let id: Int
        let date: Date
    }

    /// Without a limit, the first few rings stand for the rest.
    private var isOpen: Bool { policy.intervals == nil }

    private var points: [Point] {
        let intervals = policy.intervals ?? (0..<6).compactMap { policy.interval(after: $0) }
        return intervals.reduce(into: [Point(id: 0, date: start)]) { points, seconds in
            points.append(Point(id: points.count, date: points[points.count - 1].date + TimeInterval(seconds)))
        }
    }

    var body: some View {
        let points = points
        let focus = selected.map { points[min(max(Int($0.rounded()), 0), points.count - 1)] }
        VStack(alignment: .leading, spacing: 10) {
            Text(focus.map(readout) ?? "Ring time after each snooze")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(focus == nil ? Color.quiet : Color.primary)
                .accessibilityHidden(true)
            chart(points, focus: focus)
                .frame(height: typeSize.isAccessibilitySize ? 240 : 170)
                .padding(.vertical, 14)
                // Axis labels take the plot's room at the largest sizes.
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(isOpen ? "Snoozes without a limit" : "Rings at " + points.map { ClockText.string($0.date) }.joined(separator: ", "))
                .accessibilityIdentifier("wake-chart")
        }
        .sensoryFeedback(.selection, trigger: focus?.id)
    }

    private func readout(_ point: Point) -> String {
        let time = ClockText.string(point.date)
        return switch point.id {
        case 0: "\(time) · alarm"
        case 1: "\(time) · after 1 snooze"
        default: "\(time) · after \(point.id) snoozes"
        }
    }

    private func chart(_ points: [Point], focus: Point?) -> some View {
        let span = elapsed(points[points.count - 1])
        // Headroom keeps the end markers clear of the plot's edges.
        let room = span * 0.1
        return Chart {
            ForEach(points) { point in
                LineMark(x: .value("Snooze", Double(point.id)), y: .value("Time", elapsed(point)))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: isOpen ? [2, 6] : []))
                    .foregroundStyle(Color.accentText)
            }
            if let focus {
                RuleMark(x: .value("Snooze", Double(focus.id)))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.quiet.opacity(0.5))
            }
            ForEach(points) { point in
                PointMark(x: .value("Snooze", Double(point.id)), y: .value("Time", elapsed(point)))
                    .symbol {
                        Circle()
                            .fill(Color.accentText)
                            .frame(width: 9)
                            .padding(2)
                            .background(Color.canvas, in: .circle)
                    }
            }
        }
        .chartYScale(domain: -room...(span + room))
        .chartXScale(domain: 0...Double(points.count - 1), range: .plotDimension(padding: 16))
        .chartYAxis {
            AxisMarks(position: .leading, values: labeledTimes(points)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Color.hairline)
                AxisValueLabel(collisionResolution: .disabled) {
                    if let seconds = value.as(Double.self) {
                        Text(ClockText.string(start.addingTimeInterval(seconds))).font(.caption).monospacedDigit().foregroundStyle(Color.quiet)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: labeledSnoozes(points)) { value in
                AxisValueLabel(anchor: .top, collisionResolution: .disabled, horizontalSpacing: 0) {
                    if let number = value.as(Double.self) {
                        Text("\(Int(number))").font(.caption).monospacedDigit().foregroundStyle(Color.quiet)
                    }
                }
            }
        }
        .chartXSelection(value: $selected)
        .chartLegend(.hidden)
    }

    /// Plotted as seconds because charts draw later dates lower.
    private func elapsed(_ point: Point) -> Double { point.date.timeIntervalSince(start) }

    /// The first and last ring always, and any between with room for its label.
    private func labeledTimes(_ points: [Point]) -> [Double] {
        let last = elapsed(points[points.count - 1])
        let gap = last * (typeSize.isAccessibilitySize ? 0.22 : 0.17)
        var labeled = [0.0]
        for time in points.dropFirst().dropLast().map(elapsed) where time - labeled[labeled.count - 1] >= gap && last - time >= gap {
            labeled.append(time)
        }
        return labeled + [last]
    }

    /// Every snooze while they fit, then evenly spaced ones.
    private func labeledSnoozes(_ points: [Point]) -> [Double] {
        stride(from: 0, to: points.count, by: max(1, Int((Double(points.count) / 11).rounded(.up)))).map(Double.init)
    }
}
