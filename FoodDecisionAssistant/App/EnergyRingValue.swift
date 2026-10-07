import SwiftUI

struct EnergyRingValue: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let display: NutritionProgressPresentation

    var body: some View {
        VStack {
            Text(display.currentText)
                .font(.largeTitle.bold())
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .fixedSize(horizontal: false, vertical: true)
            Text("kcal")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("预算 \(display.targetText) kcal")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
