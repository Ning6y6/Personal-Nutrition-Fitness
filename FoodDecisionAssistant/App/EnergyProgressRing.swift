import FoodDecisionCore
import SwiftUI

struct EnergyProgressRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let consumedKcal: Double
    let targetKcal: Double

    private var summary: EnergyProgressSummary {
        EnergyProgressPolicy.standard.evaluate(
            consumedKcal: consumedKcal,
            targetKcal: targetKcal
        )
    }

    var body: some View {
        let evaluated = summary
        let display = NutritionProgressPresentation(summary: evaluated.nutritionProgress, unit: "kcal")
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 14)

            Circle()
                .trim(from: 0, to: display.progress ?? 0)
                .stroke(
                    display.tone.color,
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack {
                Image(systemName: display.symbol)
                    .foregroundStyle(display.tone.color)
                    .accessibilityHidden(true)

                Text(display.currentText)
                    .font(.title.bold())
                    .contentTransition(.numericText())

                Text("预算 \(display.targetText) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(display.message)
                    .font(.caption)
                    .foregroundStyle(display.tone.color)
            }
            .multilineTextAlignment(.center)
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(reduceMotion ? nil : .smooth, value: display.progress)
        .animation(reduceMotion ? nil : .smooth, value: evaluated.status)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日热量")
        .accessibilityValue("已摄入 \(display.currentText) 千卡，预算 \(display.targetText) 千卡，\(display.message)")
    }
}

#Preview("目标内") {
    EnergyProgressRing(consumedKcal: 1_420, targetKcal: 2_000)
        .frame(maxWidth: 180)
        .padding()
}

#Preview("显著超出") {
    EnergyProgressRing(consumedKcal: 2_260, targetKcal: 2_000)
        .frame(maxWidth: 180)
        .padding()
}
