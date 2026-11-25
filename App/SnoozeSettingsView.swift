import AlarmingCore
import SwiftUI

struct SnoozeSettingsView: View {
    @Binding var policy: SnoozePolicy
    let start: Date
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Kind: String, CaseIterable { case off = "Off", linear = "Linear", subtract = "Subtract", divide = "Divide" }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            result
            choices("Snooze", Kind.allCases, selection: kind) { $0.rawValue }
            if policy.isEnabled {
                OptionRow(title: "First snooze", options: [15, 10], value: $policy.firstMinutes, range: 1...30, optionText: { "\($0) min" }) { "\($0) min" }
                switch policy.style {
                case .constant: EmptyView()
                case .subtract(let minutes):
                    ValueStepper(title: "Subtract", value: Binding(get: { minutes }, set: { policy.style = .subtract(minutes: $0) }),
                                 range: 1...15, showsTitle: true) { "\($0) min" }
                case .multiply(let fraction):
                    choices("Divide by", SnoozePolicy.Fraction.allCases,
                            selection: Binding(get: { fraction }, set: { policy.style = .multiply($0) })) { $0.label }
                }
                OptionRow(title: "Snoozes", options: [2, 3, 5], value: limit, range: 1...(maximumLimit + 1), largestOption: maximumLimit) {
                    $0 <= maximumLimit ? "\($0)" : (policy.style == .constant ? "No limit" : "All \(policy.naturalMaximum ?? maximumLimit)")
                }
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.22), value: policy)
        .animation(reduceMotion ? nil : .snappy, value: start)
        .sensoryFeedback(.selection, trigger: policy)
        .onChange(of: policy.naturalMaximum) { _, maximum in
            if let maximum, let limit = policy.limit, limit > maximum { policy.limit = maximum }
        }
    }

    private var rings: [Date]? { policy.ringTimes(from: start) }

    /// The result sits above the controls so it can be watched while they change.
    private var result: some View {
        VStack(alignment: .leading, spacing: 12) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
            layout {
                Text(policy.isEnabled ? "Up by" : "Snooze off").foregroundStyle(Color.quiet)
                if !typeSize.isAccessibilitySize { Spacer() }
                if let wake = rings?.last {
                    Text(TimeText.string(wake))
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(policy.isEnabled ? Color.accentText : Color.quiet)
                        .contentTransition(.numericText(value: wake.timeIntervalSinceReferenceDate))
                        .accessibilityIdentifier("projected-wake")
                } else {
                    Text("No limit set").foregroundStyle(Color.quiet)
                }
            }
            .font(.subheadline.weight(.medium))
            if policy.isEnabled {
                WakeChart(policy: policy, start: start)
            }
        }
    }

    private var maximumLimit: Int { min(10, max(1, policy.naturalMaximum ?? 10)) }

    /// The stepper's last position means no chosen limit.
    private var limit: Binding<Int> {
        Binding(
            get: { min(policy.limit ?? maximumLimit + 1, maximumLimit + 1) },
            set: { policy.limit = $0 > maximumLimit ? nil : $0 })
    }

    private var kind: Binding<Kind> {
        Binding(
            get: {
                guard policy.isEnabled else { return .off }
                return switch policy.style {
                case .constant: .linear
                case .subtract: .subtract
                case .multiply: .divide
                }
            },
            set: {
                policy.isEnabled = $0 != .off
                switch $0 {
                case .off: break
                case .linear: policy.style = .constant
                case .subtract: policy.style = .subtract(minutes: 5)
                case .divide: policy.style = .multiply(.half)
                }
            })
    }

    /// Segments cannot grow with text, so large sizes get scrolling chips instead.
    @ViewBuilder private func choices<Value: Hashable>(
        _ title: String, _ values: [Value], selection: Binding<Value>, text: @escaping (Value) -> String
    ) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.subheadline)
                ChipScroll {
                    ForEach(values, id: \.self) { value in
                        Button { selection.wrappedValue = value } label: {
                            Chip(isSelected: selection.wrappedValue == value) { Text(text(value)) }
                        }
                        .buttonStyle(SpringyButtonStyle())
                        .accessibilityAddTraits(selection.wrappedValue == value ? .isSelected : [])
                    }
                }
            }
        } else {
            Picker(title, selection: selection) {
                ForEach(values, id: \.self) { Text(text($0)) }
            }
            .pickerStyle(.segmented)
        }
    }
}

/// The usual choices, and Custom for anything else.
private struct OptionRow: View {
    let title: String
    let options: [Int]
    @Binding var value: Int
    let range: ClosedRange<Int>
    var largestOption = Int.max
    var optionText: (Int) -> String = { "\($0)" }
    let text: (Int) -> String
    @State private var choseCustom = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var isCustom: Bool { choseCustom || !options.contains(value) || value > largestOption }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline).accessibilityHidden(true)
            if typeSize.isAccessibilitySize {
                ChipScroll { chips(fill: false) }
            } else {
                HStack(spacing: 8) { chips(fill: true) }
            }
            if isCustom {
                ValueStepper(title: title, value: $value, range: range, text: text)
                    .transition(.opacity)
            }
        }
    }

    private func chips(fill: Bool) -> some View {
        Group {
            ForEach(options, id: \.self) { option in
                chip(optionText(option), isSelected: !isCustom && value == option, fill: fill) {
                    choseCustom = false
                    value = option
                }
                .disabled(option > largestOption)
                .opacity(option > largestOption ? 0.35 : 1)
            }
            chip("Custom", isSelected: isCustom, fill: fill) { choseCustom = true }
        }
        .buttonStyle(SpringyButtonStyle(scale: 0.95))
    }

    private func chip(_ name: String, isSelected: Bool, fill: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.smooth(duration: 0.3), action) } label: {
            Chip(isSelected: isSelected) { Text(name).lineLimit(1).fixedSize().frame(maxWidth: fill ? .infinity : nil) }
        }
        .accessibilityLabel("\(title), \(name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Minus and plus, with the value beside them where a thumb cannot cover it.
private struct ValueStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var showsTitle = false
    let text: (Int) -> String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout())
        Stepper(value: $value, in: range) {
            layout {
                if showsTitle { Text(title) }
                Text(text(value))
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(showsTitle ? Color.quiet : Color.primary)
                    .contentTransition(.numericText(value: Double(value)))
            }
        }
        .font(.subheadline)
        .frame(minHeight: 44)
        .accessibilityLabel(title)
        .accessibilityValue(text(value))
    }
}

private extension SnoozePolicy.Fraction {
    /// As a divisor: keeping 3/4 of a snooze is dividing it by 1 1/3.
    var label: String {
        switch self {
        case .threeQuarters: "÷ 1⅓"
        case .twoThirds: "÷ 1½"
        case .half: "÷ 2"
        case .third: "÷ 3"
        }
    }
}
