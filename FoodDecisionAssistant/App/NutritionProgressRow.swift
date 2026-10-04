import SwiftUI

struct NutritionProgressRow: View {
    let title: LocalizedStringKey
    let current: Double
    let target: Double
    let unit: String
    var isUpperLimit = false

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(valueLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            ProgressView(value: progress)
                .tint(progressTint)
            Label(gapLabel, systemImage: gapSymbol)
                .font(.caption)
                .foregroundStyle(gapColor)
        }
        .accessibilityElement(children: .combine)
    }

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(max(current / target, 0), 1)
    }

    private var valueLabel: String {
        "\(formatted(current)) / \(formatted(target)) \(unit)"
    }

    private var gapLabel: String {
        let difference = target - current
        if difference >= 0 {
            return isUpperLimit
                ? "还可 \(formatted(difference)) \(unit)"
                : "还差 \(formatted(difference)) \(unit)"
        }
        return "已超出 \(formatted(abs(difference))) \(unit)"
    }

    private var gapSymbol: String {
        current > target ? "exclamationmark.circle.fill" : "circle.dotted"
    }

    private var progressTint: Color {
        if isUpperLimit {
            if current > target {
                return .red
            }
            if target > 0, current / target >= 0.8 {
                return .orange
            }
        }
        return .green
    }

    private var gapColor: Color {
        current > target ? .red : .secondary
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
