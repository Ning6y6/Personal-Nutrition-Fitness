import FoodDecisionCore
import SwiftUI

struct EnergyProgressRing: View {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
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
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 14)

            Circle()
                .trim(from: 0, to: summary.ringProgress)
                .stroke(
                    statusColor,
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
                    .accessibilityHidden(true)

                Text(formatted(summary.consumedKcal))
                    .font(.title.bold())
                    .contentTransition(.numericText())

                Text("目标 \(formatted(summary.targetKcal)) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
            .multilineTextAlignment(.center)
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(reduceMotion ? nil : .smooth, value: summary.ringProgress)
        .animation(reduceMotion ? nil : .smooth, value: summary.status)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日热量")
        .accessibilityValue(accessibilityValue)
    }

    private var statusColor: Color {
        switch summary.status {
        case .withinTarget:
            .green
        case .overTarget:
            .orange
        case .significantlyOverTarget:
            .red
        }
    }

    private var statusSymbol: String {
        switch summary.status {
        case .withinTarget:
            differentiateWithoutColor ? "checkmark.circle" : "flame.fill"
        case .overTarget:
            "exclamationmark.circle.fill"
        case .significantlyOverTarget:
            "exclamationmark.triangle.fill"
        }
    }

    private var statusLabel: String {
        switch summary.status {
        case .withinTarget:
            summary.ratio >= 1
                ? "已达到目标"
                : "还差 \(formatted(summary.remainingKcal)) kcal"
        case .overTarget, .significantlyOverTarget:
            "超出 \(formatted(summary.overageKcal)) kcal"
        }
    }

    private var accessibilityValue: String {
        "已摄入 \(formatted(summary.consumedKcal)) 千卡，目标 \(formatted(summary.targetKcal)) 千卡，\(statusLabel)"
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
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
