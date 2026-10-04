import FoodDecisionCore
import SwiftUI

struct NutritionProgressRow: View {
    let title: LocalizedStringKey
    let current: Double?
    let target: Double?
    let unit: String
    let metric: NutritionGoalMetric

    private var presentation: NutritionProgressPresentation {
        NutritionProgressPresentation(
            summary: NutritionDisplayPolicy.v1.evaluate(
                consumed: current, target: target, semantics: metric.semantics
            ),
            unit: unit
        )
    }

    var body: some View {
        let display = presentation
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(display.valueLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            if let progress = display.progress {
                ProgressView(value: progress).tint(display.tone.color)
            }
            Label(display.message, systemImage: display.symbol)
                .font(.caption)
                .foregroundStyle(display.tone.color)
        }
        .accessibilityElement(children: .combine)
    }
}
