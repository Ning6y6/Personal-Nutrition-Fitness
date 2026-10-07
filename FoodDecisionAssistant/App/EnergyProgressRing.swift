import FoodDecisionCore
import SwiftUI

struct EnergyProgressRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        let display = EnergyRingPresentation(summary: evaluated)
        VStack {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: DesignTokens.ringLineWidth)
                EnergyRingArc(
                    progress: evaluated.baseLap ?? 0,
                    startColor: DesignTokens.ringStart,
                    endColor: DesignTokens.ringEnd,
                    showsEndpoint: evaluated.baseLap == 1
                )
                EnergyRingArc(
                    progress: evaluated.overflowLap ?? 0,
                    startColor: DesignTokens.overflowStart,
                    endColor: DesignTokens.overflowEnd,
                    showsEndpoint: (evaluated.overflowLap ?? 0) > 0
                )
                if !dynamicTypeSize.isAccessibilitySize {
                    EnergyRingValue(display: display.nutrition)
                        .padding(DesignTokens.ringLineWidth)
                }
            }
            .frame(maxWidth: DesignTokens.ringDiameter)
            .frame(height: DesignTokens.ringDiameter)
            .padding(DesignTokens.ringLineWidth / 2)
            .accessibilityHidden(true)

            if dynamicTypeSize.isAccessibilitySize {
                EnergyRingValue(display: display.nutrition)
            }
            Label(display.message, systemImage: display.nutrition.symbol)
                .font(.subheadline)
                .foregroundStyle(display.nutrition.tone.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .default, value: evaluated.baseLap)
        .animation(reduceMotion ? nil : .default, value: evaluated.overflowLap)
        .animation(reduceMotion ? nil : .smooth, value: evaluated.status)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日热量")
        .accessibilityValue("已记录 \(display.nutrition.currentText) 千卡，预算 \(display.nutrition.targetText) 千卡，\(display.message)")
    }
}

#Preview("预算内 · 浅色") {
    EnergyProgressRing(consumedKcal: 1_420, targetKcal: 2_000)
        .padding()
}

#Preview("3.2倍 · 深色") {
    EnergyProgressRing(consumedKcal: 6_400, targetKcal: 2_000)
        .padding()
        .preferredColorScheme(.dark)
}
