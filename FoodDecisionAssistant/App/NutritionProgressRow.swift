import FoodDecisionCore
import SwiftUI

struct NutritionProgressRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: LocalizedStringKey
    let current: Double?
    let target: Double?
    let unit: String
    let metric: NutritionGoalMetric

    private var presentation: NutritionProgressPresentation {
        NutritionProgressPresentation(
            summary: NutritionDisplayPolicy.standard.evaluate(
                consumed: current, target: target, semantics: metric.semantics
            ),
            unit: unit
        )
    }

    var body: some View {
        let display = presentation
        VStack(alignment: .leading) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(title).font(.subheadline)
                    Spacer()
                    Text(display.valueLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                VStack(alignment: .leading) {
                    Text(title)
                        .font(.subheadline)
                    Text(display.valueLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .contentTransition(reduceMotion ? .identity : .numericText())
            if let progress = display.progress {
                ProgressView(value: progress)
                    .tint(display.tone == .warning || display.tone == .danger ? DesignTokens.warning : DesignTokens.accent)
            }
            Label(display.message, systemImage: display.symbol)
                .font(.caption)
                .foregroundStyle(display.tone.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
